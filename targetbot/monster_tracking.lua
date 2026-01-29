--[[
  Monster Tracking Module - Extracted from monster_ai.lua
  
  Single Responsibility: Track individual monster behavior and collect samples.
  
  This module handles:
  - Per-monster data collection (position, direction, health)
  - Extended telemetry using OTClient API
  - Safe creature validation helpers
  - Walk pattern and direction history tracking
  
  Depends on: RingBuffer, ClientHelper, EventBus
  Used by: monster_prediction.lua, auto_tuner.lua
]]

-- Load dependencies (use global RingBuffer if already loaded, else try to load)
local RingBuffer = RingBuffer or (function()
  local ok, rb = pcall(dofile, "/utils/ring_buffer.lua")
  if ok and rb then return rb end
  -- Try alternate path
  ok, rb = pcall(dofile, "/core/utils/ring_buffer.lua")
  if ok and rb then return rb end
  return nil
end)()

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

local MonsterTracking = {}
MonsterTracking.VERSION = "1.0"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

MonsterTracking.CONFIG = {
  ANALYSIS_WINDOW = 10000,      -- 10 seconds of history
  SAMPLE_INTERVAL = 100,        -- Sample every 100ms
  TELEMETRY_INTERVAL = 200,     -- Extended telemetry interval
  MAX_WALK_SAMPLES = 30,        -- Ring buffer size for walk samples
  MAX_HEALTH_SAMPLES = 30,      -- Ring buffer size for health samples
  MAX_DIRECTION_HISTORY = 20,   -- Ring buffer size for direction changes
  MAX_DISTANCE_SAMPLES = 30,    -- Ring buffer size for distance samples
  VALIDATED_CACHE_TTL = 100,    -- Validation cache TTL (ms)
}

-- ============================================================================
-- TIME HELPER (use ClientHelper for DRY)
-- ============================================================================

local nowMs = ClientHelper and ClientHelper.nowMs or function()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

-- ============================================================================
-- CLIENT HELPERS
-- ============================================================================

local function getClient()
  return ClientService
end

local function getLocalPlayer()
  local Client = getClient()
  if Client and Client.getLocalPlayer then
    return Client.getLocalPlayer()
  elseif g_game and g_game.getLocalPlayer then
    return g_game.getLocalPlayer()
  end
  return nil
end

-- ============================================================================
-- SAFE CREATURE VALIDATION (Prevents C++ crashes)
-- ============================================================================

-- Cache for recently validated creatures
local validatedCreatures = {}

-- Check if a creature is valid and safe to call methods on
function MonsterTracking.isCreatureValid(creature)
  if not creature then return false end
  if type(creature) ~= "userdata" and type(creature) ~= "table" then return false end
  
  local ok, id = pcall(function() return creature:getId() end)
  if not ok or not id then return false end
  
  local nowt = nowMs()
  local cached = validatedCreatures[id]
  if cached and (nowt - cached.time) < MonsterTracking.CONFIG.VALIDATED_CACHE_TTL then
    return cached.valid
  end
  
  local okPos, pos = pcall(function() return creature:getPosition() end)
  local valid = okPos and pos ~= nil
  
  validatedCreatures[id] = { valid = valid, time = nowt }
  
  -- Periodic cleanup
  if math.random(1, 50) == 1 then
    for cid, data in pairs(validatedCreatures) do
      if (nowt - data.time) > MonsterTracking.CONFIG.VALIDATED_CACHE_TTL * 10 then
        validatedCreatures[cid] = nil
      end
    end
  end
  
  return valid
end

-- Safely call a method on a creature
function MonsterTracking.safeCall(creature, methodName, default)
  if not creature then return default end
  
  local ok, result = pcall(function()
    local method = creature[methodName]
    if not method then return nil end
    return method(creature)
  end)
  
  return ok and result ~= nil and result or default
end

-- Safe getters
function MonsterTracking.safeGetId(creature)
  if not creature then return nil end
  local ok, id = pcall(function() return creature:getId() end)
  return ok and id or nil
end

function MonsterTracking.safeIsDead(creature)
  if not creature then return true end
  local ok, dead = pcall(function() return creature:isDead() end)
  return ok and dead or true
end

function MonsterTracking.safeIsMonster(creature)
  if not creature then return false end
  local ok, monster = pcall(function() return creature:isMonster() end)
  return ok and monster or false
end

function MonsterTracking.safeIsRemoved(creature)
  if not creature then return true end
  local ok, removed = pcall(function() return creature:isRemoved() end)
  return ok and removed or true
end

-- Combined check: valid, alive monster?
function MonsterTracking.isValidAliveMonster(creature)
  if not creature then return false end
  
  local ok, result = pcall(function()
    return creature:isMonster() and not creature:isDead() and not creature:isRemoved()
  end)
  
  return ok and result or false
end

-- ============================================================================
-- TRACKER STATE
-- ============================================================================

MonsterTracking.monsters = {}   -- creatureId -> tracking data
MonsterTracking.stats = {
  totalTracked = 0,
  waveAttacksObserved = 0,
  areaAttacksObserved = 0,
  totalDamageReceived = 0,
  avoidanceSuccesses = 0,
  avoidanceFailures = 0
}

-- ============================================================================
-- TRACKING FUNCTIONS
-- ============================================================================

-- Create tracking entry for a monster (uses ring buffers)
function MonsterTracking.createEntry(creature)
  local id = MonsterTracking.safeGetId(creature)
  if not id then return nil end
  
  local pos = MonsterTracking.safeCall(creature, "getPosition", nil)
  if not pos then return nil end
  
  local nowt = nowMs()
  local config = MonsterTracking.CONFIG
  
  local entry = {
    creature = creature,
    id = id,
    name = MonsterTracking.safeCall(creature, "getName", "Unknown"),
    
    -- Core samples (still use array for simple time-based data)
    samples = {},
    lastDirection = MonsterTracking.safeCall(creature, "getDirection", 0),
    lastPosition = {x = pos.x, y = pos.y, z = pos.z},
    lastSampleTime = nowt,
    trackingStartTime = nowt,
    
    -- Combat tracking
    lastAttackTime = 0,
    lastWaveTime = 0,
    attackCount = 0,
    waveCount = 0,
    
    -- Movement analysis
    directionChanges = 0,
    movementSamples = 0,
    stationaryCount = 0,
    chaseCount = 0,
    facingCount = 0,
    
    -- Ring buffers for efficient history (replaces table.remove patterns)
    walkSamples = RingBuffer.new(config.MAX_WALK_SAMPLES, "walkSample"),
    healthSamples = RingBuffer.new(config.MAX_HEALTH_SAMPLES, "healthSample"),
    directionHistory = RingBuffer.new(config.MAX_DIRECTION_HISTORY, "dirHistory"),
    distanceSamples = RingBuffer.new(config.MAX_DISTANCE_SAMPLES, "distSample"),
    damageSamples = RingBuffer.new(20, "damageSample"),
    
    -- Aggregates
    avgSpeed = 0,
    baseSpeed = 0,
    avgStepDuration = 0,
    walkingRatio = 0,
    turnFrequency = 0,
    avgDistanceFromPlayer = 0,
    preferredDistance = nil,
    lastHealthPercent = MonsterTracking.safeCall(creature, "getHealthPercent", 100),
    healthChangeRate = 0,
    totalDamage = 0,
    
    -- Engagement tracking
    engagementStart = nil,
    engagementDuration = 0,
    damageDealtToMonster = 0,
    
    -- EWMA learning
    ewmaCooldown = nil,
    ewmaVariance = 0,
    ewmaAlpha = 0.3,
    predictedWaveCooldown = nil,
    confidence = 0.1,
    
    -- Telemetry timing
    lastTelemetryTime = 0
  }
  
  return entry
end

-- Start tracking a monster
function MonsterTracking.track(creature)
  if not creature then return false end
  if not MonsterTracking.isCreatureValid(creature) then return false end
  if MonsterTracking.safeIsDead(creature) then return false end
  
  local id = MonsterTracking.safeGetId(creature)
  if not id then return false end
  if MonsterTracking.monsters[id] then return true end  -- Already tracking
  
  local entry = MonsterTracking.createEntry(creature)
  if not entry then return false end
  
  MonsterTracking.monsters[id] = entry
  MonsterTracking.stats.totalTracked = MonsterTracking.stats.totalTracked + 1
  
  -- Emit event
  if EventBus and EventBus.emit then
    pcall(function() EventBus.emit("monsterTracking:started", creature, id) end)
  end
  
  return true
end

-- Stop tracking a monster
function MonsterTracking.untrack(creatureId)
  local data = MonsterTracking.monsters[creatureId]
  if not data then return false end
  
  -- Clear ring buffers
  if data.walkSamples then data.walkSamples:clear() end
  if data.healthSamples then data.healthSamples:clear() end
  if data.directionHistory then data.directionHistory:clear() end
  if data.distanceSamples then data.distanceSamples:clear() end
  if data.damageSamples then data.damageSamples:clear() end
  
  -- Emit event before removal
  if EventBus and EventBus.emit then
    local isDead = data.creature and MonsterTracking.safeIsDead(data.creature)
    if isDead then
      EventBus.emit("monsterTracking:killed", data.name, creatureId, {
        engagementDuration = data.engagementDuration,
        damageReceived = data.totalDamage,
        waveAttacks = data.waveCount
      })
    end
  end
  
  MonsterTracking.monsters[creatureId] = nil
  return true
end

-- Update tracking data for a monster
function MonsterTracking.update(creature)
  if not creature then return false end
  if not MonsterTracking.isCreatureValid(creature) then return false end
  if MonsterTracking.safeIsDead(creature) then return false end
  
  local id = MonsterTracking.safeGetId(creature)
  if not id then return false end
  
  local data = MonsterTracking.monsters[id]
  if not data then
    MonsterTracking.track(creature)
    return true
  end
  
  local nowt = nowMs()
  local pos = MonsterTracking.safeCall(creature, "getPosition", nil)
  if not pos then return false end
  
  local dir = MonsterTracking.safeCall(creature, "getDirection", 0)
  local hp = MonsterTracking.safeCall(creature, "getHealthPercent", 100)
  
  -- Core sample
  local sample = {
    time = nowt,
    pos = {x = pos.x, y = pos.y, z = pos.z},
    dir = dir,
    health = hp
  }
  
  -- Keep samples within analysis window (batch trim for O(1) amortized)
  data.samples[#data.samples + 1] = sample
  if #data.samples > 0 and (nowt - data.samples[1].time) > MonsterTracking.CONFIG.ANALYSIS_WINDOW then
    local cutoff = 1
    while cutoff <= #data.samples and (nowt - data.samples[cutoff].time) > MonsterTracking.CONFIG.ANALYSIS_WINDOW do
      cutoff = cutoff + 1
    end
    if cutoff > 1 then
      for i = 1, #data.samples - cutoff + 1 do
        data.samples[i] = data.samples[i + cutoff - 1]
      end
      for i = #data.samples - cutoff + 2, #data.samples do
        data.samples[i] = nil
      end
    end
  end
  
  -- Direction change tracking
  if dir ~= data.lastDirection then
    data.directionChanges = data.directionChanges + 1
    data.directionHistory:push({ time = nowt, direction = dir })
    
    -- Calculate turn frequency
    if data.directionHistory:count() >= 2 then
      local oldest = data.directionHistory:oldest()
      if oldest then
        local timeWindow = (nowt - oldest.time) / 1000
        if timeWindow > 0 then
          data.turnFrequency = (data.directionHistory:count() - 1) / timeWindow
        end
      end
    end
    
    data.lastDirection = dir
  end
  
  -- Health tracking
  if hp ~= data.lastHealthPercent then
    data.healthSamples:push({ time = nowt, percent = hp })
    
    -- Calculate health change rate
    if data.healthSamples:count() >= 2 then
      local oldest = data.healthSamples:oldest()
      local newest = data.healthSamples:newest()
      if oldest and newest then
        local timeWindow = (newest.time - oldest.time) / 1000
        if timeWindow > 0 then
          data.healthChangeRate = (oldest.percent - newest.percent) / timeWindow
        end
      end
    end
    
    data.lastHealthPercent = hp
  end
  
  -- Distance from player tracking
  local player = getLocalPlayer()
  if player then
    local playerPos = MonsterTracking.safeCall(player, "getPosition", nil)
    if playerPos and playerPos.z == pos.z then
      local dist = math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y))
      data.distanceSamples:push({ time = nowt, distance = dist })
      
      -- Calculate average distance
      local sum = 0
      local count = 0
      for sample in data.distanceSamples:iterate() do
        sum = sum + sample.distance
        count = count + 1
      end
      if count > 0 then
        data.avgDistanceFromPlayer = sum / count
      end
    end
  end
  
  -- Movement analysis
  data.movementSamples = data.movementSamples + 1
  
  local moved = pos.x ~= data.lastPosition.x or pos.y ~= data.lastPosition.y
  if not moved then
    data.stationaryCount = data.stationaryCount + 1
  else
    -- Chase detection
    if player then
      local playerPos = MonsterTracking.safeCall(player, "getPosition", nil)
      if playerPos then
        local oldDist = math.max(
          math.abs(data.lastPosition.x - playerPos.x),
          math.abs(data.lastPosition.y - playerPos.y)
        )
        local newDist = math.max(
          math.abs(pos.x - playerPos.x),
          math.abs(pos.y - playerPos.y)
        )
        if newDist < oldDist then
          data.chaseCount = data.chaseCount + 1
        end
      end
    end
  end
  
  data.lastPosition = {x = pos.x, y = pos.y, z = pos.z}
  data.lastSampleTime = nowt
  
  return true
end

-- Collect extended telemetry snapshot
function MonsterTracking.collectTelemetry(creature)
  if not creature then return nil end
  if not MonsterTracking.isCreatureValid(creature) then return nil end
  
  local id = MonsterTracking.safeGetId(creature)
  if not id then return nil end
  
  local data = MonsterTracking.monsters[id]
  if not data then return nil end
  
  local nowt = nowMs()
  
  -- Check telemetry interval
  if (nowt - data.lastTelemetryTime) < MonsterTracking.CONFIG.TELEMETRY_INTERVAL then
    return nil
  end
  
  local snapshot = {
    timestamp = nowt,
    id = id,
    name = data.name,
    healthPercent = MonsterTracking.safeCall(creature, "getHealthPercent", 100),
    position = MonsterTracking.safeCall(creature, "getPosition", nil),
    direction = MonsterTracking.safeCall(creature, "getDirection", 0),
    isWalking = MonsterTracking.safeCall(creature, "isWalking", false),
    speed = MonsterTracking.safeCall(creature, "getSpeed", 0),
    baseSpeed = MonsterTracking.safeCall(creature, "getBaseSpeed", 0),
    stepDuration = MonsterTracking.safeCall(creature, "getStepDuration", 0),
    stepProgress = MonsterTracking.safeCall(creature, "getStepProgress", 0),
    isDead = MonsterTracking.safeCall(creature, "isDead", false),
    isRemoved = MonsterTracking.safeCall(creature, "isRemoved", false)
  }
  
  if not snapshot.position then return nil end
  
  -- Update walk samples (using ring buffer)
  data.walkSamples:push({
    time = nowt,
    isWalking = snapshot.isWalking,
    stepDuration = snapshot.stepDuration,
    direction = snapshot.direction
  })
  
  -- Update walking ratio
  local walkingCount = 0
  for sample in data.walkSamples:iterate() do
    if sample.isWalking then walkingCount = walkingCount + 1 end
  end
  data.walkingRatio = walkingCount / math.max(1, data.walkSamples:count())
  
  -- Update speed averages
  if snapshot.speed and snapshot.speed > 0 then
    data.avgSpeed = data.avgSpeed * 0.85 + snapshot.speed * 0.15
    data.baseSpeed = snapshot.baseSpeed or data.baseSpeed
  end
  
  if snapshot.stepDuration and snapshot.stepDuration > 0 then
    data.avgStepDuration = data.avgStepDuration * 0.8 + snapshot.stepDuration * 0.2
  end
  
  data.lastTelemetryTime = nowt
  
  return snapshot
end

-- Get tracking data for a monster
function MonsterTracking.get(creatureId)
  return MonsterTracking.monsters[creatureId]
end

-- Get all tracked monsters
function MonsterTracking.getAll()
  return MonsterTracking.monsters
end

-- Get monster count
function MonsterTracking.getCount()
  local count = 0
  for _ in pairs(MonsterTracking.monsters) do
    count = count + 1
  end
  return count
end

-- Record damage received from a monster
function MonsterTracking.recordDamage(creatureId, damage)
  local data = MonsterTracking.monsters[creatureId]
  if not data then return end
  
  local nowt = nowMs()
  data.damageSamples:push({ time = nowt, amount = damage })
  data.totalDamage = data.totalDamage + damage
  MonsterTracking.stats.totalDamageReceived = MonsterTracking.stats.totalDamageReceived + damage
end

-- Record a wave attack observation
function MonsterTracking.recordWaveAttack(creatureId)
  local data = MonsterTracking.monsters[creatureId]
  if not data then return end
  
  local nowt = nowMs()
  local timeSinceLastWave = nowt - data.lastWaveTime
  
  if data.lastWaveTime > 0 and timeSinceLastWave > 500 then
    -- Update EWMA cooldown estimate
    local alpha = data.ewmaAlpha or 0.3
    if data.ewmaCooldown then
      local delta = timeSinceLastWave - data.ewmaCooldown
      data.ewmaCooldown = data.ewmaCooldown + alpha * delta
      data.ewmaVariance = data.ewmaVariance * (1 - alpha) + alpha * delta * delta
    else
      data.ewmaCooldown = timeSinceLastWave
    end
    
    -- Update confidence based on variance
    if data.ewmaCooldown > 0 then
      local cv = math.sqrt(data.ewmaVariance) / data.ewmaCooldown
      data.confidence = math.max(0.1, math.min(0.95, 1 - cv))
    end
  end
  
  data.lastWaveTime = nowt
  data.waveCount = data.waveCount + 1
  MonsterTracking.stats.waveAttacksObserved = MonsterTracking.stats.waveAttacksObserved + 1
end

-- Calculate DPS from a monster
function MonsterTracking.getDPS(creatureId)
  local data = MonsterTracking.monsters[creatureId]
  if not data or not data.damageSamples then return 0 end
  
  local nowt = nowMs()
  local windowMs = 5000  -- 5 second window
  
  local totalDamage = 0
  local oldestTime = nowt
  
  for sample in data.damageSamples:iterate() do
    if (nowt - sample.time) <= windowMs then
      totalDamage = totalDamage + sample.amount
      if sample.time < oldestTime then
        oldestTime = sample.time
      end
    end
  end
  
  local duration = (nowt - oldestTime) / 1000  -- seconds
  if duration > 0 then
    return totalDamage / duration
  end
  
  return 0
end

-- Cleanup stale entries
function MonsterTracking.cleanup()
  local nowt = nowMs()
  local staleThreshold = 15000  -- 15 seconds
  local removed = 0
  
  for id, data in pairs(MonsterTracking.monsters) do
    local isStale = (nowt - data.lastSampleTime) > staleThreshold
    local isDead = data.creature and MonsterTracking.safeIsDead(data.creature)
    local isRemoved = data.creature and MonsterTracking.safeIsRemoved(data.creature)
    
    if isStale or isDead or isRemoved then
      MonsterTracking.untrack(id)
      removed = removed + 1
    end
  end
  
  return removed
end

-- Get statistics
function MonsterTracking.getStats()
  return {
    activeCount = MonsterTracking.getCount(),
    totalTracked = MonsterTracking.stats.totalTracked,
    waveAttacksObserved = MonsterTracking.stats.waveAttacksObserved,
    totalDamageReceived = MonsterTracking.stats.totalDamageReceived
  }
end

return MonsterTracking
