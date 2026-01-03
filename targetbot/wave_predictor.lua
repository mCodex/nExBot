-- WavePredictor: lightweight per-monster pattern learner to predict wave/beam attacks
-- Emits WAVE_AVOIDANCE intents into MovementCoordinator when immediate threats exist
-- Enhanced with MonsterAI.RealTime integration for shared intelligence

WavePredictor = WavePredictor or {}
WavePredictor.VERSION = "0.2"

-- Per-creature state
local patterns = {} -- id -> { lastAttack = ts, cooldownEMA, directionBias, observedWidth, ... }

-- Prediction validation tracking
WavePredictor.Validation = {
  predictions = {},     -- id -> { predictedTime, predictedPos, validatedAt }
  stats = {
    total = 0,
    correct = 0,
    missed = 0,
    falsePositive = 0
  }
}

-- Telemetry (increment via nExBot.Telemetry)
local function incr(name)
  if nExBot and nExBot.Telemetry and nExBot.Telemetry.increment then
    nExBot.Telemetry.increment(name)
  end
end

local function key(c)
  local id = c and c:getId()
  if not id then return tostring(c) end
  return tostring(id)
end

local function nowMs()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

local function ensurePattern(c)
  local k = key(c)
  if not patterns[k] then
    -- Initialize with data from MonsterAI if available
    local learned = nil
    if MonsterAI and MonsterAI.Patterns and MonsterAI.Patterns.get then
      local name = c and c:getName and c:getName()
      if name then
        learned = MonsterAI.Patterns.get(name)
      end
    end
    
    patterns[k] = {
      lastAttack = 0,
      cooldownEMA = learned and learned.waveCooldown or 0,
      cooldownVariance = learned and learned.waveVariance or 0,
      directionBias = {},
      observedWidth = learned and learned.waveWidth or 1,
      seen = 0,
      -- Enhanced tracking
      directionHistory = {},      -- Recent directions for pattern detection
      attackDirections = {},      -- Directions when attacks occurred
      consecutiveFacing = 0,      -- How long has been facing player
      lastDirection = nil,
      lastPositionChange = 0,
      confidence = learned and learned.confidence or 0.3
    }
  end
  return patterns[k]
end

-- Sync pattern data with MonsterAI.RealTime
local function syncWithMonsterAI(creature, pattern)
  if not MonsterAI or not MonsterAI.RealTime then return end
  
  local id = creature and creature:getId()
  if not id then return end
  
  local rt = MonsterAI.RealTime.directions[id]
  if rt then
    -- Import turn rate data
    pattern.turnRate = rt.turnRate or 0
    pattern.consecutiveFacing = rt.consecutiveChanges or 0
    
    -- If MonsterAI has better cooldown estimate, use it
    local data = MonsterAI.Tracker and MonsterAI.Tracker.monsters[id]
    if data and data.ewmaCooldown and data.ewmaCooldown > 0 then
      -- Blend estimates (MonsterAI has more samples usually)
      if pattern.cooldownEMA > 0 then
        pattern.cooldownEMA = pattern.cooldownEMA * 0.3 + data.ewmaCooldown * 0.7
      else
        pattern.cooldownEMA = data.ewmaCooldown
      end
      pattern.cooldownVariance = data.ewmaVariance or 0
      pattern.confidence = math.max(pattern.confidence, data.confidence or 0.3)
    end
  end
end

local function predictArc(creature, pattern)
  -- Simple projection: take creature position and direction and return a list of tile positions in an arc
  local pos = creature and creature:getPosition()
  if not pos then return {} end
  local dir = creature.getDirection and creature:getDirection() or 0

  -- Direction vectors (approx) 0:N,2:E,4:S,6:W or OTClient mapping; keep simple 4-cardinal
  local DIR_OFF = {
    [0] = {x=0,y=-1}, [1] = {x=1,y=-1}, [2] = {x=1,y=0}, [3] = {x=1,y=1},
    [4] = {x=0,y=1}, [5] = {x=-1,y=1}, [6] = {x=-1,y=0}, [7] = {x=-1,y=-1}
  }
  local vec = DIR_OFF[dir] or {x=0,y=0}
  local res = {}
  -- width controls arc breadth, range modest (3)
  local range = 4
  local width = math.max(1, pattern.observedWidth or 1)
  for r=1,range do
    for w=-math.floor(width/2),math.floor(width/2) do
      -- simple lateral offset by rotating vector 90deg for w
      local lx = vec.x * r - vec.y * w
      local ly = vec.y * r + vec.x * w
      res[#res+1] = {x = pos.x + lx, y = pos.y + ly, z = pos.z}
    end
  end
  return res
end

local function scoreThreatForPlayer(threatMap, playerPos)
  -- Find tile with minimum threat (safe spot) among adjacent 8 tiles including current
  local safe = nil
  local bestScore = 1e9
  local dirs = {{0,0},{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}
  for i=1,#dirs do
    local d = dirs[i]
    local tkey = (playerPos.x+d[1])..","..(playerPos.y+d[2])
    local s = threatMap[tkey] or 0
    if s < bestScore then bestScore = s; safe = {x=playerPos.x+d[1], y=playerPos.y+d[2], z=playerPos.z} end
  end
  return safe, bestScore
end

-- Build threat map (tile string -> probability [0,1]) from recent attack
local function buildThreatMap(creature, pattern)
  local arc = predictArc(creature, pattern)
  local map = {}
  for i=1,#arc do
    local t = arc[i]
    local k = t.x..","..t.y
    map[k] = math.min(1, (map[k] or 0) + 0.6) -- base probability for arc tiles
  end
  return map
end

-- Called on events to update pattern
local function onAttackLike(creature)
  if not creature then return end
  local k = key(creature)
  local p = ensurePattern(creature)
  local nowt = now
  local dt = p.lastAttack > 0 and (nowt - p.lastAttack) or 0
  if p.cooldownEMA == 0 then p.cooldownEMA = dt else p.cooldownEMA = p.cooldownEMA * 0.7 + dt * 0.3 end
  p.lastAttack = nowt
  p.seen = (p.seen or 0) + 1

  -- If recently attacked and near player, compute threat and register
  local playerPos = player and player:getPosition()
  if not playerPos then return end

  local threatMap = buildThreatMap(creature, p)
  -- compute max threat near player
  local maxThreat = 0
  for k,v in pairs(threatMap) do
    maxThreat = math.max(maxThreat, v)
  end

  if maxThreat > 0.2 then
    incr('wavePredictions')
    -- choose safe tile
    local safeTile, score = scoreThreatForPlayer(threatMap, playerPos)
    local confidence = math.min(1, maxThreat + 0.1)
    
    -- VALIDATE SAFE TILE: Ensure it's not a floor change position
    -- Prevent wave avoidance from suggesting unsafe Z-level changes
    if safeTile and TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isPositionSafeForMovement then
      if not TargetCore.PathSafety.isPositionSafeForMovement(safeTile, playerPos) then
        -- Safe tile is unsafe - don't register the intent
        incr('wavePredictions.blocked.floor_change')
        return
      end
    end
    
    -- register WAVE_AVOIDANCE intent with MovementCoordinator
    if MovementCoordinator and MovementCoordinator.Intent and MovementCoordinator.CONSTANTS and MovementCoordinator.CONSTANTS.INTENT then
      MovementCoordinator.Intent.register(MovementCoordinator.CONSTANTS.INTENT.WAVE_AVOIDANCE, safeTile, confidence, "WavePredictor", {threat=threatMap, src=creature})
    end
  end
end

-- EventBus hooks (Enhanced with MonsterAI integration and prediction validation)
if EventBus then
  EventBus.on("monster:appear", function(c)
    ensurePattern(c)
  end, 20)

  -- Enhanced creature:move with direction change detection
  EventBus.on("creature:move", function(c, oldPos)
    if not c or not c:isMonster() then return end
    
    local p = ensurePattern(c)
    local newDir = c:getDirection()
    local oldDir = p.lastDirection
    
    -- Sync with MonsterAI for shared intelligence
    syncWithMonsterAI(c, p)
    
    -- Track direction history
    p.directionHistory = p.directionHistory or {}
    table.insert(p.directionHistory, { dir = newDir, time = nowMs() })
    while #p.directionHistory > 20 do table.remove(p.directionHistory, 1) end
    
    -- Direction change detection
    if oldDir ~= nil and oldDir ~= newDir then
      p.lastDirectionChange = nowMs()
      
      -- Check if now facing player
      local playerPos = player and player:getPosition()
      local monsterPos = c:getPosition()
      if playerPos and monsterPos then
        local isFacing = false
        if MonsterAI and MonsterAI.Predictor and MonsterAI.Predictor.isFacingPosition then
          isFacing = MonsterAI.Predictor.isFacingPosition(monsterPos, newDir, playerPos)
        end
        
        if isFacing then
          p.facingPlayerSince = nowMs()
          p.consecutiveFacing = (p.consecutiveFacing or 0) + 1
          
          -- Calculate threat based on cooldown timing
          local cooldown = p.cooldownEMA > 0 and p.cooldownEMA or 2000
          local elapsed = nowMs() - (p.lastAttack or 0)
          local timeToAttack = math.max(0, cooldown - elapsed)
          
          -- High threat if: facing player + cooldown almost ready + recent direction change
          local threatConfidence = 0.4
          if timeToAttack < 800 then threatConfidence = threatConfidence + 0.35 end
          if p.consecutiveFacing >= 2 then threatConfidence = threatConfidence + 0.15 end
          if p.turnRate and p.turnRate > 0.5 then threatConfidence = threatConfidence + 0.10 end
          threatConfidence = math.min(0.95, threatConfidence + (p.confidence or 0) * 0.2)\n          \n          -- Register prediction for later validation
          local predKey = key(c)
          WavePredictor.Validation.predictions[predKey] = {
            predictedTime = nowMs() + timeToAttack,
            playerPos = { x = playerPos.x, y = playerPos.y, z = playerPos.z },
            monsterPos = { x = monsterPos.x, y = monsterPos.y, z = monsterPos.z },
            confidence = threatConfidence,
            registeredAt = nowMs()
          }
          WavePredictor.Validation.stats.total = (WavePredictor.Validation.stats.total or 0) + 1
          
          if threatConfidence >= 0.55 then
            -- Emit threat event
            incr('wavePredictor.directionThreat')
            
            local threatMap = buildThreatMap(c, p)
            local safeTile, score = scoreThreatForPlayer(threatMap, playerPos)
            
            -- Validate safe tile
            if safeTile and TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isPositionSafeForMovement then
              if not TargetCore.PathSafety.isPositionSafeForMovement(safeTile, playerPos) then
                incr('wavePredictor.blocked.floor_change')
                safeTile = nil
              end
            end
            
            if safeTile and MovementCoordinator and MovementCoordinator.Intent and MovementCoordinator.CONSTANTS then
              MovementCoordinator.Intent.register(
                MovementCoordinator.CONSTANTS.INTENT.WAVE_AVOIDANCE,
                safeTile,
                threatConfidence,
                "WavePredictor.direction",
                { threat = threatMap, src = c, reason = "direction_change", timeToAttack = timeToAttack }
              )
            end
            
            -- Also notify MonsterAI.RealTime if available
            if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.registerImmediateThreat then
              MonsterAI.RealTime.registerImmediateThreat(c, "wave_predictor_dir", threatConfidence)
            end
          end
        else
          p.facingPlayerSince = nil
          p.consecutiveFacing = 0
        end
      end
    end
    
    p.lastDirection = newDir
    p.lastPositionChange = nowMs()
    p.observedWidth = math.max(1, (p.observedWidth or 1))
  end, 25)  -- Higher priority for faster response

  -- Hook into player damage to validate predictions
  EventBus.on("player:damage", function(damage, source)
    local nowt = nowMs()
    
    -- Check if any prediction was correct (damage within 500ms of predicted time)
    for id, pred in pairs(WavePredictor.Validation.predictions) do
      if pred.predictedTime and math.abs(nowt - pred.predictedTime) < 500 then
        -- Prediction was correct!
        WavePredictor.Validation.stats.correct = (WavePredictor.Validation.stats.correct or 0) + 1
        incr('wavePredictor.validation.correct')
        
        -- Update accuracy metric
        local total = WavePredictor.Validation.stats.total or 1
        local correct = WavePredictor.Validation.stats.correct or 0
        if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.metrics then
          MonsterAI.RealTime.metrics.predictionsCorrect = correct
          MonsterAI.RealTime.metrics.avgPredictionAccuracy = correct / total
        end
        
        -- Remove validated prediction
        WavePredictor.Validation.predictions[id] = nil
        break
      end
    end
    
    -- Clean up old predictions (false positives if too old)
    for id, pred in pairs(WavePredictor.Validation.predictions) do
      if (nowt - (pred.registeredAt or 0)) > 3000 then
        WavePredictor.Validation.stats.falsePositive = (WavePredictor.Validation.stats.falsePositive or 0) + 1
        WavePredictor.Validation.predictions[id] = nil
      end
    end
  end, 20)

  -- Hook into monster health events to detect attacks
  EventBus.on("monster:health", function(c, percent)
    if c and c:isMonster() then
      onAttackLike(c)
      
      -- Validate any pending predictions for this monster
      local predKey = key(c)
      local pred = WavePredictor.Validation.predictions[predKey]
      if pred then
        local nowt = nowMs()
        if math.abs(nowt - (pred.predictedTime or 0)) < 1000 then
          WavePredictor.Validation.stats.correct = (WavePredictor.Validation.stats.correct or 0) + 1
        end
        WavePredictor.Validation.predictions[predKey] = nil
      end
    end
  end, 25)
  
  -- Listen for MonsterAI threat events for cross-module coordination
  EventBus.on("monsterai/threat_detected", function(creature, data)
    if not creature then return end
    
    local p = ensurePattern(creature)
    
    -- Boost our confidence based on MonsterAI's analysis
    if data and data.confidence then
      p.confidence = math.max(p.confidence or 0, data.confidence * 0.8)
    end
    
    -- Record attack direction if provided
    if data and data.dir then
      p.attackDirections = p.attackDirections or {}
      table.insert(p.attackDirections, data.dir)
      while #p.attackDirections > 10 do table.remove(p.attackDirections, 1) end
    end
  end, 15)
  
  -- Clean up on monster disappear
  EventBus.on("monster:disappear", function(c)
    if c then
      local k = key(c)
      patterns[k] = nil
      WavePredictor.Validation.predictions[k] = nil
    end
  end, 20)

  -- Also listen for text messages that might indicate wave attacks (server texts)
  EventBus.on("message:text", function(mode, text)
    -- placeholder for future parsing
  end, 5)
end

-- Expose helpers for other modules
WavePredictor.ensurePattern = ensurePattern
WavePredictor.syncWithMonsterAI = syncWithMonsterAI
WavePredictor.buildThreatMap = buildThreatMap
WavePredictor.predictArc = predictArc
WavePredictor.onMove = function(c, oldPos)
  if c and c:isMonster() then
    local p = ensurePattern(c)
    syncWithMonsterAI(c, p)
    p.observedWidth = math.max(1, (p.observedWidth or 1))
  end
end

-- Get prediction stats
WavePredictor.getStats = function()
  local stats = WavePredictor.Validation.stats
  local accuracy = 0
  if stats.total and stats.total > 0 then
    accuracy = (stats.correct or 0) / stats.total
  end
  return {
    total = stats.total or 0,
    correct = stats.correct or 0,
    falsePositive = stats.falsePositive or 0,
    accuracy = accuracy
  }
end

return WavePredictor
