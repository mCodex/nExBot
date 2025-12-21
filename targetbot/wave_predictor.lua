-- WavePredictor: lightweight per-monster pattern learner to predict wave/beam attacks
-- Emits WAVE_AVOIDANCE intents into MovementCoordinator when immediate threats exist

WavePredictor = WavePredictor or {}
WavePredictor.VERSION = "0.1"

-- Per-creature state
local patterns = {} -- id -> { lastAttack = ts, cooldownEMA, directionBias, observedWidth }

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

local function ensurePattern(c)
  local k = key(c)
  if not patterns[k] then
    patterns[k] = { lastAttack = 0, cooldownEMA = 0, directionBias = {}, observedWidth = 1, seen = 0 }
  end
  return patterns[k]
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

-- EventBus hooks
if EventBus then
  EventBus.on("monster:appear", function(c)
    ensurePattern(c)
  end, 20)

  EventBus.on("creature:move", function(c, oldPos)
    -- direction changes can be informative; simple heuristic: if a monster moves in a straight line and stops, may wave
    if c and c:isMonster() then
      local p = ensurePattern(c)
      -- small update to observedWidth bias for moving monsters
      p.observedWidth = math.max(1, (p.observedWidth or 1))
    end
  end, 10)

  -- Hook into player damage or monster health events to detect attacks
  EventBus.on("monster:health", function(c, percent)
    -- when health percent changes abruptly, treat as attack-like signal
    if c and c:isMonster() then onAttackLike(c) end
  end, 25)

  -- Also listen for text messages that might indicate wave attacks (server texts) - optional
  EventBus.on("message:text", function(mode, text)
    -- placeholder for future parsing
  end, 5)
end

-- Expose helpers for other modules (MovementCoordinator will call these)
WavePredictor.ensurePattern = ensurePattern
WavePredictor.onMove = function(c, oldPos)
  if c and c:isMonster() then
    local p = ensurePattern(c)
    -- small update to observedWidth bias for moving monsters
    p.observedWidth = math.max(1, (p.observedWidth or 1))
  end
end

return WavePredictor
