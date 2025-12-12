--[[
  Monster AI Analysis Module v1.0
  
  Deep learning-inspired analysis system for predicting monster behavior
  and optimizing player positioning for maximum damage output.
  
  Features:
  - Monster behavior pattern recognition
  - Attack timing prediction
  - Wave/beam attack anticipation
  - Optimal positioning for AoE spells
  - Confidence-based decision making
  
  Architecture:
  - MonsterAI.Patterns: Known monster attack patterns
  - MonsterAI.Tracker: Real-time monster behavior tracking
  - MonsterAI.Predictor: Behavior prediction engine
  - MonsterAI.Confidence: Decision confidence scoring
]]

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

MonsterAI = MonsterAI or {}
MonsterAI.VERSION = "1.0"

-- ============================================================================
-- CONSTANTS
-- ============================================================================

MonsterAI.CONSTANTS = {
  -- Behavior analysis window (in ms)
  ANALYSIS_WINDOW = 10000,     -- 10 seconds of history
  SAMPLE_INTERVAL = 100,       -- Sample every 100ms
  
  -- Prediction confidence thresholds
  CONFIDENCE = {
    VERY_HIGH = 0.85,
    HIGH = 0.70,
    MEDIUM = 0.50,
    LOW = 0.30,
    VERY_LOW = 0.15
  },
  
  -- Monster attack types (learned from observation)
  ATTACK_TYPE = {
    MELEE = 1,
    TARGETED_SPELL = 2,
    WAVE_BEAM = 3,
    AREA_SPELL = 4,
    SUMMON = 5
  },
  
  -- Movement patterns
  MOVEMENT_PATTERN = {
    STATIC = 1,       -- Stays still
    CHASE = 2,        -- Follows player
    KITE = 3,         -- Keeps distance
    ERRATIC = 4,      -- Random movement
    PATROL = 5        -- Moves in pattern
  },
  
  -- Wave attack danger levels
  WAVE_DANGER = {
    NONE = 0,
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3,
    CRITICAL = 4
  }
}

local CONST = MonsterAI.CONSTANTS

-- ============================================================================
-- MONSTER BEHAVIOR PATTERNS (Learned Data)
-- This serves as a "training dataset" that can be extended
-- ============================================================================

MonsterAI.Patterns = {
  -- Known monster patterns (can be loaded from config)
  -- Structure: monsterName -> { attackPatterns, movementPattern, dangerLevel, ... }
  knownMonsters = {},
  
  -- Default pattern for unknown monsters (conservative estimate)
  default = {
    hasWaveAttack = true,       -- Assume worst case
    waveWidth = 1,              -- Narrow beam
    waveRange = 5,              -- Standard range
    waveCooldown = 2000,        -- 2 second cooldown guess
    hasAreaAttack = false,
    areaRadius = 0,
    movementPattern = CONST.MOVEMENT_PATTERN.CHASE,
    dangerLevel = CONST.WAVE_DANGER.MEDIUM,
    preferredDistance = 1       -- Melee
  }
}

-- Register known monster patterns (extendable)
function MonsterAI.Patterns.register(monsterName, pattern)
  MonsterAI.Patterns.knownMonsters[monsterName:lower()] = pattern
end

-- Get pattern for a monster (returns default if unknown)
function MonsterAI.Patterns.get(monsterName)
  return MonsterAI.Patterns.knownMonsters[monsterName:lower()] 
         or MonsterAI.Patterns.default
end

-- ============================================================================
-- MONSTER TRACKER
-- Real-time tracking of monster behavior for pattern learning
-- ============================================================================

MonsterAI.Tracker = {
  -- Per-monster tracking data
  -- Structure: creatureId -> { samples[], lastAttack, direction, position, ... }
  monsters = {},
  
  -- Global statistics for learning
  stats = {
    waveAttacksObserved = 0,
    areaAttacksObserved = 0,
    totalDamageReceived = 0,
    avoidanceSuccesses = 0,
    avoidanceFailures = 0
  }
}

-- Initialize tracking for a monster
function MonsterAI.Tracker.track(creature)
  if not creature or creature:isDead() then return end
  
  local id = creature:getId()
  if not id then return end  -- Invalid creature
  if MonsterAI.Tracker.monsters[id] then return end  -- Already tracking
  
  local pos = creature:getPosition()
  if not pos then return end  -- Creature position unavailable (teleporting/disappearing)
  
  MonsterAI.Tracker.monsters[id] = {
    creature = creature,
    name = creature:getName(),
    samples = {},           -- {time, pos, dir, health, isAttacking}
    lastDirection = creature:getDirection(),
    lastPosition = {x = pos.x, y = pos.y, z = pos.z},
    lastAttackTime = 0,
    attackCount = 0,
    directionChanges = 0,
    movementSamples = 0,
    stationaryCount = 0,
    chaseCount = 0,
    -- Learned behavior
    predictedWaveCooldown = nil,
    observedWaveAttacks = {},
    confidence = 0.1         -- Start with low confidence
  }
end

-- Stop tracking a monster
function MonsterAI.Tracker.untrack(creatureId)
  MonsterAI.Tracker.monsters[creatureId] = nil
end

-- Update tracking data for a monster
function MonsterAI.Tracker.update(creature)
  if not creature or creature:isDead() then return end
  
  local id = creature:getId()
  if not id then return end  -- Invalid creature
  
  local data = MonsterAI.Tracker.monsters[id]
  if not data then
    MonsterAI.Tracker.track(creature)
    return
  end
  
  local currentTime = now
  local pos = creature:getPosition()
  if not pos then return end  -- Creature position unavailable
  
  local dir = creature:getDirection()
  
  -- Add sample
  local sample = {
    time = currentTime,
    pos = {x = pos.x, y = pos.y, z = pos.z},
    dir = dir,
    health = creature:getHealthPercent()
  }
  
  -- Keep samples within analysis window
  table.insert(data.samples, sample)
  while #data.samples > 0 and 
        (currentTime - data.samples[1].time) > CONST.ANALYSIS_WINDOW do
    table.remove(data.samples, 1)
  end
  
  -- Analyze direction changes (potential attack indicator)
  if dir ~= data.lastDirection then
    data.directionChanges = data.directionChanges + 1
    data.lastDirection = dir
  end
  
  -- Analyze movement pattern
  data.movementSamples = data.movementSamples + 1
  if pos.x == data.lastPosition.x and pos.y == data.lastPosition.y then
    data.stationaryCount = data.stationaryCount + 1
  else
    -- Check if moving toward player
    local playerPos = player:getPosition()
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
    
    data.lastPosition = {x = pos.x, y = pos.y, z = pos.z}
  end
  
  -- Update confidence based on sample count
  local sampleRatio = math.min(#data.samples / 50, 1)  -- Need 50 samples for full confidence
  data.confidence = 0.1 + 0.6 * sampleRatio
end

-- Get predicted movement pattern for a monster
function MonsterAI.Tracker.getPredictedPattern(creatureId)
  local data = MonsterAI.Tracker.monsters[creatureId]
  if not data or data.movementSamples < 10 then
    return CONST.MOVEMENT_PATTERN.CHASE, 0.2  -- Default with low confidence
  end
  
  local stationaryRatio = data.stationaryCount / data.movementSamples
  local chaseRatio = data.chaseCount / (data.movementSamples - data.stationaryCount + 1)
  
  if stationaryRatio > 0.8 then
    return CONST.MOVEMENT_PATTERN.STATIC, data.confidence
  elseif chaseRatio > 0.6 then
    return CONST.MOVEMENT_PATTERN.CHASE, data.confidence
  elseif chaseRatio < 0.3 and stationaryRatio < 0.3 then
    return CONST.MOVEMENT_PATTERN.ERRATIC, data.confidence * 0.8
  else
    return CONST.MOVEMENT_PATTERN.CHASE, data.confidence * 0.7  -- Default
  end
end

-- ============================================================================
-- PREDICTOR ENGINE
-- Predicts monster behavior based on tracked data
-- ============================================================================

MonsterAI.Predictor = {}

-- Predict if monster is about to use a wave attack
-- Returns: isPredicted, confidence, timeToAttack
function MonsterAI.Predictor.predictWaveAttack(creature)
  if not creature or creature:isDead() then
    return false, 0, 999999
  end
  
  local id = creature:getId()
  local data = MonsterAI.Tracker.monsters[id]
  local pattern = MonsterAI.Patterns.get(creature:getName())
  
  -- Base prediction on known pattern
  if not pattern.hasWaveAttack then
    return false, 0.8, 999999
  end
  
  -- Check if monster is facing player (primary indicator)
  local monsterPos = creature:getPosition()
  local monsterDir = creature:getDirection()
  local playerPos = player:getPosition()
  
  local isFacingPlayer = MonsterAI.Predictor.isFacingPosition(
    monsterPos, monsterDir, playerPos
  )
  
  if not isFacingPlayer then
    return false, 0.7, 999999
  end
  
  -- Calculate time since last observed wave attack
  local timeSinceLastWave = 999999
  if data and data.lastAttackTime > 0 then
    timeSinceLastWave = now - data.lastAttackTime
  end
  
  -- Predict based on cooldown
  local cooldown = data and data.predictedWaveCooldown or pattern.waveCooldown
  local timeToAttack = math.max(0, cooldown - timeSinceLastWave)
  
  -- Calculate confidence
  local confidence = 0.5  -- Base
  if data then
    confidence = confidence + data.confidence * 0.3
  end
  if isFacingPlayer then
    confidence = confidence + 0.2
  end
  if timeSinceLastWave > cooldown * 0.8 then
    confidence = confidence + 0.15  -- Cooldown almost up
  end
  
  confidence = math.min(confidence, 0.95)
  
  return timeToAttack < 500, confidence, timeToAttack
end

-- Check if monster is facing a position (pure function)
function MonsterAI.Predictor.isFacingPosition(monsterPos, monsterDir, targetPos)
  local dirVec = TargetCore and TargetCore.CONSTANTS.DIR_VECTORS[monsterDir]
  if not dirVec then
    -- Fallback direction vectors
    local fallbackDirs = {
      [0] = {x = 0, y = -1},
      [1] = {x = 1, y = 0},
      [2] = {x = 0, y = 1},
      [3] = {x = -1, y = 0},
      [4] = {x = 1, y = -1},
      [5] = {x = 1, y = 1},
      [6] = {x = -1, y = 1},
      [7] = {x = -1, y = -1}
    }
    dirVec = fallbackDirs[monsterDir]
    if not dirVec then return false end
  end
  
  local dx = targetPos.x - monsterPos.x
  local dy = targetPos.y - monsterPos.y
  
  -- Check if target is generally in the direction monster faces
  if dirVec.x == 0 then
    -- North or South
    return (dy * dirVec.y) > 0 and math.abs(dx) <= 1
  elseif dirVec.y == 0 then
    -- East or West
    return (dx * dirVec.x) > 0 and math.abs(dy) <= 1
  else
    -- Diagonal
    local inX = (dirVec.x > 0 and dx > 0) or (dirVec.x < 0 and dx < 0)
    local inY = (dirVec.y > 0 and dy > 0) or (dirVec.y < 0 and dy < 0)
    return inX and inY
  end
end

-- Predict danger level for a position
-- Returns: dangerLevel (0-4), confidence
function MonsterAI.Predictor.predictPositionDanger(position, monsters)
  local totalDanger = 0
  local totalConfidence = 0
  local count = 0
  
  for i = 1, #monsters do
    local monster = monsters[i]
    if monster and not monster:isDead() then
      local isPredicted, confidence, timeToAttack = 
        MonsterAI.Predictor.predictWaveAttack(monster)
      
      if isPredicted and timeToAttack < 1000 then
        -- Check if position is in attack path
        local mpos = monster:getPosition()
        local mdir = monster:getDirection()
        local pattern = MonsterAI.Patterns.get(monster:getName())
        
        local inDanger = MonsterAI.Predictor.isPositionInWavePath(
          position, mpos, mdir, pattern.waveRange, pattern.waveWidth
        )
        
        if inDanger then
          -- Closer time to attack = more danger
          local urgency = 1 - (timeToAttack / 1000)
          totalDanger = totalDanger + (pattern.dangerLevel * urgency)
          totalConfidence = totalConfidence + confidence
          count = count + 1
        end
      end
    end
  end
  
  if count == 0 then
    return CONST.WAVE_DANGER.NONE, 0.8
  end
  
  local avgDanger = totalDanger / count
  local avgConfidence = totalConfidence / count
  
  local level = CONST.WAVE_DANGER.NONE
  if avgDanger >= 3 then level = CONST.WAVE_DANGER.CRITICAL
  elseif avgDanger >= 2 then level = CONST.WAVE_DANGER.HIGH
  elseif avgDanger >= 1 then level = CONST.WAVE_DANGER.MEDIUM
  elseif avgDanger > 0 then level = CONST.WAVE_DANGER.LOW
  end
  
  return level, avgConfidence
end

-- Check if a position is in wave attack path (pure function)
function MonsterAI.Predictor.isPositionInWavePath(pos, monsterPos, monsterDir, range, width)
  range = range or 5
  width = width or 1
  
  local dirVec = TargetCore and TargetCore.CONSTANTS.DIR_VECTORS[monsterDir]
  if not dirVec then return false end
  
  local dx = pos.x - monsterPos.x
  local dy = pos.y - monsterPos.y
  local dist = math.max(math.abs(dx), math.abs(dy))
  
  if dist == 0 or dist > range then
    return false
  end
  
  -- Check alignment with wave direction
  if dirVec.x == 0 then
    return (dy * dirVec.y) > 0 and math.abs(dx) <= width
  elseif dirVec.y == 0 then
    return (dx * dirVec.x) > 0 and math.abs(dy) <= width
  else
    local inX = (dirVec.x > 0 and dx > 0) or (dirVec.x < 0 and dx < 0)
    local inY = (dirVec.y > 0 and dy > 0) or (dirVec.y < 0 and dy < 0)
    return inX and inY
  end
end

-- ============================================================================
-- CONFIDENCE SYSTEM
-- Aggregates confidence from multiple sources for decision making
-- ============================================================================

MonsterAI.Confidence = {}

-- Calculate overall movement decision confidence
-- @param sources: array of {name, confidence, weight}
-- @return aggregated confidence (0-1)
function MonsterAI.Confidence.aggregate(sources)
  if not sources or #sources == 0 then
    return 0.5  -- Neutral confidence
  end
  
  local weightedSum = 0
  local totalWeight = 0
  
  for i = 1, #sources do
    local source = sources[i]
    weightedSum = weightedSum + (source.confidence * source.weight)
    totalWeight = totalWeight + source.weight
  end
  
  if totalWeight == 0 then
    return 0.5
  end
  
  return weightedSum / totalWeight
end

-- Determine if we should act based on confidence threshold
function MonsterAI.Confidence.shouldAct(confidence, threshold)
  threshold = threshold or CONST.CONFIDENCE.MEDIUM
  return confidence >= threshold
end

-- Get confidence category string
function MonsterAI.Confidence.getCategory(confidence)
  if confidence >= CONST.CONFIDENCE.VERY_HIGH then return "VERY_HIGH"
  elseif confidence >= CONST.CONFIDENCE.HIGH then return "HIGH"
  elseif confidence >= CONST.CONFIDENCE.MEDIUM then return "MEDIUM"
  elseif confidence >= CONST.CONFIDENCE.LOW then return "LOW"
  else return "VERY_LOW"
  end
end

-- ============================================================================
-- EVENTBUS INTEGRATION
-- ============================================================================

if EventBus then
  -- Track monsters when they appear
  EventBus.on("monster:appear", function(creature)
    MonsterAI.Tracker.track(creature)
  end, 30)
  
  -- Untrack monsters when they disappear
  EventBus.on("monster:disappear", function(creature)
    if creature then
      MonsterAI.Tracker.untrack(creature:getId())
    end
  end, 30)
  
  -- Update tracking on monster health change (potential attack indicator)
  EventBus.on("monster:health", function(creature, percent)
    if creature then
      MonsterAI.Tracker.update(creature)
    end
  end, 30)
  
  -- Record when player takes damage (learning opportunity)
  EventBus.on("player:damage", function(damage, source)
    MonsterAI.Tracker.stats.totalDamageReceived = 
      MonsterAI.Tracker.stats.totalDamageReceived + damage
    -- TODO: Correlate with monster that caused it
  end, 30)
end

-- ============================================================================
-- PERIODIC UPDATE (for monsters not triggering events)
-- ============================================================================

-- Update all tracked monsters periodically
function MonsterAI.updateAll()
  local playerPos = player:getPosition()
  if not playerPos then return end
  
  local creatures = g_map.getSpectatorsInRange(playerPos, false, 8, 8)
  if not creatures then return end
  
  for i = 1, #creatures do
    local creature = creatures[i]
    if creature and creature:isMonster() and not creature:isDead() then
      MonsterAI.Tracker.update(creature)
    end
  end
end

-- Export for external use
nExBot = nExBot or {}
nExBot.MonsterAI = MonsterAI

print("[MonsterAI] Monster AI Analysis Module v" .. MonsterAI.VERSION .. " loaded")
