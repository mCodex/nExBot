--[[
  Monster AI Analysis Module v2.1
  
  Deep learning-inspired analysis system for predicting monster behavior
  and optimizing player positioning for maximum damage output.
  
  Features:
  - Monster behavior pattern recognition
  - Attack timing prediction
  - Wave/beam attack anticipation
  - Optimal positioning for AoE spells
  - Confidence-based decision making
  - Extended OTClient API telemetry
  - Automatic TargetBot danger tuning
  - Monster type classification
  - Scenario-aware targeting (anti-zigzag)
  - Multi-monster handling optimization
  
  Architecture:
  - MonsterAI.Patterns: Known monster attack patterns
  - MonsterAI.Tracker: Real-time monster behavior tracking
  - MonsterAI.Predictor: Behavior prediction engine
  - MonsterAI.Confidence: Decision confidence scoring
  - MonsterAI.Telemetry: Extended creature data collection
  - MonsterAI.AutoTuner: Automatic targetbot configuration tuning
  - MonsterAI.Classifier: Monster behavior classification
  - MonsterAI.Scenario: Combat scenario detection and target locking
  - MonsterAI.CombatFeedback: Adaptive learning from combat outcomes
]]

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

MonsterAI = MonsterAI or {}
MonsterAI.VERSION = "2.1"

-- Time helper (milliseconds). Prefer existing global 'now' if available, else use g_clock.millis or os.time()*1000
local function nowMs()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

-- Extended telemetry defaults
MonsterAI.COLLECT_EXTENDED = (MonsterAI.COLLECT_EXTENDED == nil) and true or MonsterAI.COLLECT_EXTENDED
MonsterAI.DPS_WINDOW = MonsterAI.DPS_WINDOW or 5000 -- ms window for DPS calculation
MonsterAI.AUTO_TUNE_ENABLED = (MonsterAI.AUTO_TUNE_ENABLED == nil) and true or MonsterAI.AUTO_TUNE_ENABLED
MonsterAI.TELEMETRY_INTERVAL = MonsterAI.TELEMETRY_INTERVAL or 200 -- ms between telemetry samples

-- ============================================================================
-- REAL-TIME EVENT-DRIVEN STATE (O(1) lookups)
-- ============================================================================
MonsterAI.RealTime = MonsterAI.RealTime or {
  -- Direction tracking: id -> {dir, lastChangeTime, consecutiveChanges, turnRate}
  directions = {},
  
  -- Threat level cache: refreshed on every direction/position change
  threatCache = {
    lastUpdate = 0,
    totalThreat = 0,
    highThreatMonsters = {},  -- monsters facing player
    immediateThreat = false   -- true if any monster about to attack
  },
  
  -- Attack prediction queue: sorted by predicted attack time
  predictedAttacks = {},
  
  -- Performance metrics
  metrics = {
    eventsProcessed = 0,
    predictionsCorrect = 0,
    predictionsMissed = 0,
    avgPredictionAccuracy = 0,
    telemetrySamples = 0,
    autoTuneAdjustments = 0
  }
}

-- ============================================================================
-- EXTENDED TELEMETRY MODULE (OTClient API Integration)
-- Collects rich creature data for analysis and auto-tuning
-- ============================================================================

MonsterAI.Telemetry = MonsterAI.Telemetry or {
  -- Per-creature extended data: id -> telemetry snapshot
  snapshots = {},
  
  -- Global combat session stats
  session = {
    startTime = nowMs(),
    totalMonstersTracked = 0,
    totalDamageDealt = 0,
    totalDamageReceived = 0,
    killCount = 0,
    deathCount = 0,
    avgKillTime = 0,
    avgDPSReceived = 0
  },
  
  -- Creature type statistics: name -> aggregated stats
  typeStats = {}
}

-- Collect extended telemetry from creature using OTClient API
function MonsterAI.Telemetry.collectSnapshot(creature)
  if not creature or not creature:getId() then return nil end
  
  local id = creature:getId()
  local nowt = nowMs()
  local snapshot = {
    timestamp = nowt,
    
    -- Basic creature info
    id = id,
    name = creature:getName() or "Unknown",
    healthPercent = creature:getHealthPercent() or 100,
    
    -- Position and movement (OTClient API)
    position = creature:getPosition(),
    direction = creature:getDirection(),
    isWalking = creature.isWalking and creature:isWalking() or false,
    
    -- Speed telemetry (OTClient API)
    speed = creature.getSpeed and creature:getSpeed() or 0,
    baseSpeed = creature.getBaseSpeed and creature:getBaseSpeed() or 0,
    
    -- Walk timing (OTClient API)
    stepDuration = creature.getStepDuration and creature:getStepDuration() or 0,
    stepProgress = creature.getStepProgress and creature:getStepProgress() or 0,
    stepTicksLeft = creature.getStepTicksLeft and creature:getStepTicksLeft() or 0,
    walkTicksElapsed = creature.getWalkTicksElapsed and creature:getWalkTicksElapsed() or 0,
    
    -- Walk direction (can differ from facing direction)
    walkDirection = creature.getWalkDirection and creature:getWalkDirection() or creature:getDirection(),
    
    -- State flags
    isDead = creature:isDead() or false,
    isRemoved = creature.isRemoved and creature:isRemoved() or false,
    isInvisible = creature.isInvisible and creature:isInvisible() or false,
    
    -- Creature type classification (OTClient API)
    creatureType = creature.getType and creature:getType() or 0,
    skull = creature.getSkull and creature:getSkull() or 0,
    shield = creature.getShield and creature:getShield() or 0,
    icon = creature.getIcon and creature:getIcon() or 0,
    
    -- Outfit info (can indicate monster variant)
    outfit = creature.getOutfit and creature:getOutfit() or nil,
    
    -- Step history for trajectory prediction
    lastStepFrom = creature.getLastStepFromPosition and creature:getLastStepFromPosition() or nil,
    lastStepTo = creature.getLastStepToPosition and creature:getLastStepToPosition() or nil
  }
  
  -- Calculate derived metrics
  if snapshot.baseSpeed > 0 and snapshot.speed > 0 then
    snapshot.speedMultiplier = snapshot.speed / snapshot.baseSpeed
    snapshot.isHasted = snapshot.speedMultiplier > 1.15
    snapshot.isSlowed = snapshot.speedMultiplier < 0.85
  end
  
  -- Store snapshot
  MonsterAI.Telemetry.snapshots[id] = snapshot
  MonsterAI.RealTime.metrics.telemetrySamples = (MonsterAI.RealTime.metrics.telemetrySamples or 0) + 1
  
  return snapshot
end

-- Aggregate type statistics from tracked monsters
function MonsterAI.Telemetry.updateTypeStats(name, data)
  if not name or name == "" then return end
  
  local nameLower = name:lower()
  local stats = MonsterAI.Telemetry.typeStats[nameLower] or {
    name = name,
    sampleCount = 0,
    avgSpeed = 0,
    avgDPS = 0,
    avgHealthDrain = 0,
    totalDamageDealt = 0,
    killCount = 0,
    totalKillTime = 0,
    waveAttackCount = 0,
    lastSeen = 0,
    -- Classification results
    isRanged = nil,
    isMelee = nil,
    isAOE = nil,
    isSummoner = nil,
    estimatedDanger = nil
  }
  
  stats.sampleCount = stats.sampleCount + 1
  stats.lastSeen = nowMs()
  
  if data then
    -- Update averages using EWMA
    local alpha = 0.15
    if data.avgSpeed then
      stats.avgSpeed = stats.avgSpeed * (1 - alpha) + data.avgSpeed * alpha
    end
    if data.dps then
      stats.avgDPS = stats.avgDPS * (1 - alpha) + data.dps * alpha
    end
    if data.totalDamage then
      stats.totalDamageDealt = stats.totalDamageDealt + data.totalDamage
    end
    if data.waveCount then
      stats.waveAttackCount = stats.waveAttackCount + (data.waveCount or 0)
    end
  end
  
  MonsterAI.Telemetry.typeStats[nameLower] = stats
end

-- Get telemetry summary for a creature type
function MonsterAI.Telemetry.getTypeSummary(name)
  if not name then return nil end
  return MonsterAI.Telemetry.typeStats[name:lower()]
end

-- ============================================================================
-- MONSTER CLASSIFIER
-- Automatically classifies monsters based on observed behavior
-- ============================================================================

MonsterAI.Classifier = MonsterAI.Classifier or {
  -- Classification thresholds
  THRESHOLDS = {
    RANGED_DISTANCE = 4,        -- Prefers staying at this distance or more
    MELEE_DISTANCE = 2,         -- Stays close
    HIGH_DPS = 50,              -- Damage per second considered high
    FAST_SPEED = 250,           -- Speed considered fast
    SLOW_SPEED = 120,           -- Speed considered slow
    WAVE_FREQUENT = 0.3,        -- Wave attacks per second
    SUMMON_THRESHOLD = 2        -- Number of summons to classify as summoner
  },
  
  -- Classification results cache
  cache = {}
}

-- Classify monster behavior type based on observations
function MonsterAI.Classifier.classify(name, data)
  if not name or not data then return nil end
  
  local nameLower = name:lower()
  local existing = MonsterAI.Classifier.cache[nameLower]
  
  -- Require minimum samples for classification
  if (data.movementSamples or 0) < 15 then
    return existing -- Not enough data
  end
  
  local classification = existing or {
    name = name,
    confidence = 0,
    lastUpdated = 0,
    
    -- Behavior types (can be multiple)
    isRanged = false,
    isMelee = true,
    isWaveAttacker = false,
    isAOE = false,
    isSummoner = false,
    isFast = false,
    isSlow = false,
    isAggressive = false,
    isPassive = false,
    
    -- Computed attributes
    preferredDistance = 1,
    estimatedDanger = 1,
    attackCooldown = 2000,
    movementPattern = 2, -- CHASE by default
    
    -- Raw scores for debugging
    scores = {}
  }
  
  local nowt = nowMs()
  local thresholds = MonsterAI.Classifier.THRESHOLDS
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- Speed Classification
  -- ═══════════════════════════════════════════════════════════════════════════
  local avgSpeed = data.avgSpeed or 0
  classification.isFast = avgSpeed >= thresholds.FAST_SPEED
  classification.isSlow = avgSpeed <= thresholds.SLOW_SPEED and avgSpeed > 0
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- Distance Preference (Ranged vs Melee)
  -- ═══════════════════════════════════════════════════════════════════════════
  local stationaryRatio = (data.stationaryCount or 0) / math.max(1, data.movementSamples)
  local chaseRatio = (data.chaseCount or 0) / math.max(1, data.movementSamples - (data.stationaryCount or 0))
  
  -- High stationary + wave attacks = likely ranged
  if stationaryRatio > 0.5 and (data.waveCount or 0) > 3 then
    classification.isRanged = true
    classification.isMelee = false
    classification.preferredDistance = 4
  -- Low chase ratio + stationary = definitely ranged/kiting
  elseif stationaryRatio > 0.6 and chaseRatio < 0.3 then
    classification.isRanged = true
    classification.isMelee = false
    classification.preferredDistance = 5
  -- High chase = melee
  elseif chaseRatio > 0.6 then
    classification.isMelee = true
    classification.isRanged = false
    classification.preferredDistance = 1
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- Wave/Beam Attack Classification
  -- ═══════════════════════════════════════════════════════════════════════════
  local observationTime = (nowt - (data.trackingStartTime or nowt)) / 1000 -- seconds
  local waveRate = (data.waveCount or 0) / math.max(1, observationTime)
  
  if waveRate >= thresholds.WAVE_FREQUENT or (data.waveCount or 0) >= 3 then
    classification.isWaveAttacker = true
    classification.isAOE = true
  end
  
  if data.ewmaCooldown and data.ewmaCooldown > 0 then
    classification.attackCooldown = data.ewmaCooldown
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- Aggressiveness (based on facing player and attack frequency)
  -- ═══════════════════════════════════════════════════════════════════════════
  local facingRatio = (data.facingCount or 0) / math.max(1, data.movementSamples)
  
  if facingRatio > 0.4 and (data.waveCount or 0) > 2 then
    classification.isAggressive = true
    classification.isPassive = false
  elseif facingRatio < 0.2 and (data.waveCount or 0) == 0 then
    classification.isPassive = true
    classification.isAggressive = false
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- Movement Pattern Classification
  -- ═══════════════════════════════════════════════════════════════════════════
  local MOVE = MonsterAI.CONSTANTS.MOVEMENT_PATTERN
  
  if stationaryRatio > 0.8 then
    classification.movementPattern = MOVE.STATIC
  elseif chaseRatio > 0.6 then
    classification.movementPattern = MOVE.CHASE
  elseif stationaryRatio > 0.4 and classification.isRanged then
    classification.movementPattern = MOVE.KITE
  elseif chaseRatio < 0.3 and stationaryRatio < 0.3 then
    classification.movementPattern = MOVE.ERRATIC
  else
    classification.movementPattern = MOVE.CHASE
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- Danger Level Estimation
  -- ═══════════════════════════════════════════════════════════════════════════
  local danger = 1 -- Base danger
  
  -- DPS contribution
  local dps = MonsterAI.Tracker.getDPS and MonsterAI.Tracker.getDPS(data.id) or 0
  if dps > thresholds.HIGH_DPS then
    danger = danger + 2
  elseif dps > thresholds.HIGH_DPS / 2 then
    danger = danger + 1
  end
  
  -- Wave attack contribution
  if classification.isWaveAttacker then
    danger = danger + 1
    if waveRate > 0.5 then danger = danger + 1 end
  end
  
  -- Speed contribution (fast = harder to escape)
  if classification.isFast then danger = danger + 0.5 end
  
  -- Aggressiveness contribution
  if classification.isAggressive then danger = danger + 0.5 end
  
  classification.estimatedDanger = math.min(danger, 4) -- Cap at 4 (CRITICAL)
  
  -- Update confidence based on sample count
  classification.confidence = math.min(0.95, 0.3 + (data.movementSamples / 100) * 0.65)
  classification.lastUpdated = nowt
  
  -- Store scores for debugging
  classification.scores = {
    stationaryRatio = stationaryRatio,
    chaseRatio = chaseRatio,
    facingRatio = facingRatio,
    waveRate = waveRate,
    dps = dps,
    avgSpeed = avgSpeed
  }
  
  -- Cache result
  MonsterAI.Classifier.cache[nameLower] = classification
  
  -- Emit classification event
  if EventBus and EventBus.emit then
    EventBus.emit("monsterai:classified", name, classification)
  end
  
  return classification
end

-- Get classification for a monster (cached)
function MonsterAI.Classifier.get(name)
  if not name then return nil end
  return MonsterAI.Classifier.cache[name:lower()]
end

-- ============================================================================
-- AUTO-TUNER MODULE
-- Automatically adjusts TargetBot configuration based on learned data
-- ============================================================================

MonsterAI.AutoTuner = MonsterAI.AutoTuner or {
  -- Tuning state
  enabled = true,
  lastTuneTime = 0,
  tuneInterval = 30000, -- 30 seconds between auto-tunes
  
  -- Suggested adjustments (not applied until confirmed or auto-apply enabled)
  suggestions = {},
  
  -- History of adjustments
  history = {}
}

-- Generate danger value suggestion for a monster type
function MonsterAI.AutoTuner.suggestDanger(name)
  if not name then return nil end
  
  local nameLower = name:lower()
  local classification = MonsterAI.Classifier.get(name)
  local typeStats = MonsterAI.Telemetry.getTypeSummary(name)
  local pattern = MonsterAI.Patterns.get(name)
  
  if not classification and not typeStats then return nil end
  
  local suggestion = {
    name = name,
    timestamp = nowMs(),
    currentDanger = (pattern and pattern.dangerLevel) or 2,
    suggestedDanger = 2,
    confidence = 0,
    reasons = {}
  }
  
  local danger = 2 -- Start with medium
  local reasons = {}
  
  -- Factor 1: Classification-based danger
  if classification then
    danger = classification.estimatedDanger or 2
    suggestion.confidence = classification.confidence or 0.5
    
    if classification.isWaveAttacker then
      table.insert(reasons, "Uses wave/beam attacks")
    end
    if classification.isAggressive then
      table.insert(reasons, "Aggressive behavior")
    end
    if classification.isFast then
      table.insert(reasons, "High mobility")
    end
  end
  
  -- Factor 2: Observed DPS
  if typeStats and typeStats.avgDPS then
    local dps = typeStats.avgDPS
    if dps > 80 then
      danger = math.max(danger, 4)
      table.insert(reasons, string.format("Very high DPS (%.0f)", dps))
    elseif dps > 50 then
      danger = math.max(danger, 3)
      table.insert(reasons, string.format("High DPS (%.0f)", dps))
    elseif dps > 25 then
      danger = math.max(danger, 2)
    end
  end
  
  -- Factor 3: Wave attack patterns
  if pattern and pattern.waveCooldown and pattern.waveCooldown < 2000 then
    danger = math.max(danger, 3)
    table.insert(reasons, string.format("Fast wave cooldown (%dms)", math.floor(pattern.waveCooldown)))
  end
  
  -- Factor 4: Observed damage history
  local trackerStats = MonsterAI.Tracker.stats
  if typeStats and typeStats.totalDamageDealt > 0 then
    local avgDmgPerEncounter = typeStats.totalDamageDealt / math.max(1, typeStats.sampleCount)
    if avgDmgPerEncounter > 500 then
      danger = math.max(danger, 4)
      table.insert(reasons, string.format("High damage per encounter (%.0f avg)", avgDmgPerEncounter))
    elseif avgDmgPerEncounter > 200 then
      danger = math.max(danger, 3)
    end
  end
  
  suggestion.suggestedDanger = math.min(4, math.max(1, math.floor(danger + 0.5)))
  suggestion.reasons = reasons
  suggestion.confidence = math.min(0.95, (suggestion.confidence or 0.5) + #reasons * 0.1)
  
  -- Store suggestion
  MonsterAI.AutoTuner.suggestions[nameLower] = suggestion
  
  -- Emit suggestion event
  if EventBus and EventBus.emit then
    EventBus.emit("monsterai:danger_suggestion", name, suggestion)
  end
  
  return suggestion
end

-- Apply a danger suggestion to the pattern database
function MonsterAI.AutoTuner.applyDangerSuggestion(name, force)
  if not name then return false end
  
  local nameLower = name:lower()
  local suggestion = MonsterAI.AutoTuner.suggestions[nameLower]
  
  if not suggestion then
    -- Generate suggestion first
    suggestion = MonsterAI.AutoTuner.suggestDanger(name)
  end
  
  if not suggestion then return false end
  
  -- Only apply if confidence is high enough or forced
  if suggestion.confidence < 0.5 and not force then
    return false
  end
  
  -- Apply to pattern database
  MonsterAI.Patterns.persist(nameLower, {
    dangerLevel = suggestion.suggestedDanger,
    autoTuned = true,
    autoTuneTime = nowMs()
  })
  
  -- Record in history
  table.insert(MonsterAI.AutoTuner.history, {
    name = name,
    oldDanger = suggestion.currentDanger,
    newDanger = suggestion.suggestedDanger,
    timestamp = nowMs(),
    reasons = suggestion.reasons
  })
  
  -- Keep history bounded
  while #MonsterAI.AutoTuner.history > 100 do
    table.remove(MonsterAI.AutoTuner.history, 1)
  end
  
  MonsterAI.RealTime.metrics.autoTuneAdjustments = (MonsterAI.RealTime.metrics.autoTuneAdjustments or 0) + 1
  
  if MonsterAI.DEBUG then
    print(string.format("[MonsterAI] Auto-tuned %s: danger %d -> %d (conf=%.2f)",
      name, suggestion.currentDanger, suggestion.suggestedDanger, suggestion.confidence))
  end
  
  return true
end

-- Run auto-tuning pass on all tracked monsters
function MonsterAI.AutoTuner.runPass()
  if not MonsterAI.AUTO_TUNE_ENABLED then return end
  
  local nowt = nowMs()
  if (nowt - MonsterAI.AutoTuner.lastTuneTime) < MonsterAI.AutoTuner.tuneInterval then
    return -- Too soon
  end
  
  MonsterAI.AutoTuner.lastTuneTime = nowt
  
  -- Gather all tracked monster names
  local processedNames = {}
  for id, data in pairs(MonsterAI.Tracker.monsters) do
    if data.name and not processedNames[data.name:lower()] then
      processedNames[data.name:lower()] = true
      
      -- Classify if enough data
      MonsterAI.Classifier.classify(data.name, data)
      
      -- Generate danger suggestion
      local suggestion = MonsterAI.AutoTuner.suggestDanger(data.name)
      
      -- Auto-apply if high confidence and significant change
      if suggestion and suggestion.confidence >= 0.7 then
        local changeMagnitude = math.abs(suggestion.suggestedDanger - suggestion.currentDanger)
        if changeMagnitude >= 1 then
          MonsterAI.AutoTuner.applyDangerSuggestion(data.name, false)
        end
      end
    end
  end
end

-- Get all current suggestions
function MonsterAI.AutoTuner.getSuggestions()
  return MonsterAI.AutoTuner.suggestions
end

-- Get tuning history
function MonsterAI.AutoTuner.getHistory()
  return MonsterAI.AutoTuner.history
end


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
  },

  -- EWMA / learning tuning
  EWMA = {
    ALPHA_DEFAULT = 0.25,           -- Smoothing factor (0..1). Lower = smoother/less responsive
    VARIANCE_PENALTY_SCALE = 0.28,  -- Scales std/mean into penalty multiplier
    VARIANCE_PENALTY_MAX = 0.45     -- Maximum fraction to reduce confidence
  },

  -- Damage correlation tuning
  DAMAGE = {
    CORRELATION_RADIUS = 7,        -- Tiles to search for likely source
    CORRELATION_THRESHOLD = 0.4    -- Minimum score to accept attribution
  },
  
  -- Event-driven thresholds
  EVENT_DRIVEN = {
    DIRECTION_CHANGE_COOLDOWN = 150,    -- ms between direction change processing
    TURN_RATE_WINDOW = 2000,            -- ms window for turn rate calculation
    CONSECUTIVE_TURNS_ALERT = 2,        -- Number of quick turns to trigger alert
    IMMEDIATE_THREAT_WINDOW = 800,      -- ms before predicted attack to flag immediate
    THREAT_CACHE_TTL = 100,             -- ms to cache threat calculations
    ATTACK_PREDICTION_HORIZON = 2000,   -- ms ahead to predict attacks
    FACING_PLAYER_THRESHOLD = 0.6       -- Confidence threshold for "facing player"
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

-- Helper to get monster patterns from storage (UnifiedStorage with fallback)
local function getStoredPatterns()
  if UnifiedStorage and UnifiedStorage.isReady and UnifiedStorage.isReady() then
    return UnifiedStorage.get("targetbot.monsterPatterns") or {}
  end
  return storage.monsterPatterns or {}
end

-- Helper to save monster patterns to storage (UnifiedStorage with fallback)
local function setStoredPatterns(patterns)
  if UnifiedStorage and UnifiedStorage.isReady and UnifiedStorage.isReady() then
    UnifiedStorage.set("targetbot.monsterPatterns", patterns)
    -- Emit event for real-time sync
    if EventBus and EventBus.emit then
      EventBus.emit("monsterAI:patternsUpdated", patterns)
    end
  end
  -- Also keep in global storage for compatibility
  storage.monsterPatterns = patterns
end

-- Load persisted patterns from storage (if any)
local storedPatterns = getStoredPatterns()
for k,v in pairs(storedPatterns) do
  MonsterAI.Patterns.knownMonsters[k] = v
end

-- Persist a known monster pattern to storage
function MonsterAI.savePattern(monsterName)
  if not monsterName then return end
  local name = monsterName:lower()
  local patterns = getStoredPatterns()
  patterns[name] = MonsterAI.Patterns.knownMonsters[name]
  setStoredPatterns(patterns)
  -- Emit individual pattern update event
  if EventBus and EventBus.emit then
    EventBus.emit("monsterAI:patternUpdated", name, MonsterAI.Patterns.knownMonsters[name])
  end
end

-- Persist partial updates to a known monster pattern (SRP)
function MonsterAI.Patterns.persist(monsterName, updates)
  if not monsterName then return end
  local name = monsterName:lower()
  MonsterAI.Patterns.knownMonsters[name] = MonsterAI.Patterns.knownMonsters[name] or {}
  for k,v in pairs(updates) do MonsterAI.Patterns.knownMonsters[name][k] = v end
  local patterns = getStoredPatterns()
  patterns[name] = MonsterAI.Patterns.knownMonsters[name]
  setStoredPatterns(patterns)
end
-- Simple decay: slowly reduce confidence and nudge cooldown toward default when long unseen
function MonsterAI.decayPatterns()
  local nowt = nowMs()
  local decayWindow = 7 * 24 * 3600 * 1000 -- 7 days
  local patterns = getStoredPatterns()
  for k, v in pairs(patterns) do
    if v.lastSeen and (nowt - v.lastSeen) > decayWindow then
      v.confidence = (v.confidence or 0.5) * 0.9
      if v.waveCooldown then v.waveCooldown = v.waveCooldown * 1.05 end
      patterns[k] = v
      MonsterAI.Patterns.knownMonsters[k] = v
    end
  end
  setStoredPatterns(patterns)
end

-- Schedule recurring decay (hourly)
schedule(3600000, function()
  MonsterAI.decayPatterns()
  schedule(3600000, function() MonsterAI.decayPatterns() end)
end)


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

-- ============================================================================
-- REAL-TIME THREAT ANALYSIS (Event-Driven)
-- ============================================================================

-- Fast direction change detection (called on creature:move)
function MonsterAI.RealTime.onDirectionChange(creature, oldDir, newDir)
  if not creature then return end
  local id = creature:getId()
  if not id then return end
  
  local nowt = nowMs()
  local rt = MonsterAI.RealTime.directions[id]
  
  if not rt then
    rt = { dir = newDir, lastChangeTime = nowt, consecutiveChanges = 0, turnRate = 0, positions = {} }
    MonsterAI.RealTime.directions[id] = rt
  end
  
  -- Calculate turn rate (changes per second)
  local dt = nowt - (rt.lastChangeTime or nowt)
  if dt > 0 and dt < CONST.EVENT_DRIVEN.TURN_RATE_WINDOW then
    rt.turnRate = rt.turnRate * 0.7 + (1000 / dt) * 0.3  -- EWMA
    rt.consecutiveChanges = rt.consecutiveChanges + 1
  else
    rt.consecutiveChanges = 1
    rt.turnRate = 0
  end
  
  rt.dir = newDir
  rt.lastChangeTime = nowt
  
  -- Check if now facing player (immediate threat signal)
  local playerPos = player and player:getPosition()
  local monsterPos = creature:getPosition()
  if playerPos and monsterPos then
    local isFacing = MonsterAI.Predictor.isFacingPosition(monsterPos, newDir, playerPos)
    
    if isFacing then
      -- Monster just turned to face player - potential attack incoming
      rt.facingPlayerSince = nowt
      
      -- High turn rate + now facing = high threat
      if rt.consecutiveChanges >= CONST.EVENT_DRIVEN.CONSECUTIVE_TURNS_ALERT then
        -- Emit immediate threat event
        MonsterAI.RealTime.registerImmediateThreat(creature, "direction_lock", 0.75 + rt.turnRate * 0.05)
      else
        MonsterAI.RealTime.registerImmediateThreat(creature, "facing", 0.50)
      end
    else
      rt.facingPlayerSince = nil
    end
  end
  
  MonsterAI.RealTime.metrics.eventsProcessed = (MonsterAI.RealTime.metrics.eventsProcessed or 0) + 1
end

-- Register an immediate threat from a monster
function MonsterAI.RealTime.registerImmediateThreat(creature, reason, confidence)
  if not creature then return end
  local id = creature:getId()
  if not id then return end
  
  local nowt = nowMs()
  local pos = creature:getPosition()
  local dir = creature:getDirection()
  
  -- Get learned cooldown for prediction
  local data = MonsterAI.Tracker.monsters[id]
  local pattern = MonsterAI.Patterns.get(creature:getName())
  local cooldown = (data and data.ewmaCooldown) or (pattern and pattern.waveCooldown) or 2000
  
  -- Calculate time to attack based on cooldown and last attack
  local lastAttack = (data and data.lastWaveTime) or (data and data.lastAttackTime) or 0
  local elapsed = nowt - lastAttack
  local timeToAttack = math.max(0, cooldown - elapsed)
  
  -- If cooldown is almost up and facing player, this is very high threat
  if timeToAttack < CONST.EVENT_DRIVEN.IMMEDIATE_THREAT_WINDOW then
    confidence = math.min(0.95, confidence + 0.25)
  end
  
  -- Add to prediction queue
  local prediction = {
    id = id,
    creature = creature,
    pos = pos,
    dir = dir,
    reason = reason,
    confidence = confidence,
    predictedTime = nowt + timeToAttack,
    registeredAt = nowt
  }
  
  -- Insert sorted by predicted time
  local queue = MonsterAI.RealTime.predictedAttacks
  local inserted = false
  for i = 1, #queue do
    if queue[i].predictedTime > prediction.predictedTime then
      table.insert(queue, i, prediction)
      inserted = true
      break
    end
  end
  if not inserted then
    table.insert(queue, prediction)
  end
  
  -- Cap queue size
  while #queue > 20 do
    table.remove(queue)
  end
  
  -- Emit event for immediate avoidance
  if confidence >= CONST.EVENT_DRIVEN.FACING_PLAYER_THRESHOLD and EventBus then
    pcall(function()
      EventBus.emit("monsterai/threat_detected", creature, {
        reason = reason,
        confidence = confidence,
        timeToAttack = timeToAttack,
        pos = pos,
        dir = dir
      })
    end)
    
    -- Also register intent with MovementCoordinator if high confidence
    if confidence >= 0.65 and MovementCoordinator and MovementCoordinator.Intent then
      local playerPos = player and player:getPosition()
      if playerPos and pos then
        -- Find safe tile away from attack arc
        local safeTile = MonsterAI.RealTime.findSafeTileFromArc(playerPos, pos, dir, pattern)
        if safeTile then
          MovementCoordinator.Intent.register(
            MovementCoordinator.CONSTANTS.INTENT.WAVE_AVOIDANCE,
            safeTile,
            confidence,
            "MonsterAI.RealTime",
            { reason = reason, timeToAttack = timeToAttack, source = id }
          )
        end
      end
    end
  end
end

-- Find safe tile outside of monster's attack arc
function MonsterAI.RealTime.findSafeTileFromArc(playerPos, monsterPos, monsterDir, pattern)
  if not playerPos or not monsterPos then return nil end
  
  local range = (pattern and pattern.waveRange) or 5
  local width = (pattern and pattern.waveWidth) or 1
  
  -- Direction vectors
  local dirVecs = {
    [0] = {x=0, y=-1}, [1] = {x=1, y=-1}, [2] = {x=1, y=0}, [3] = {x=1, y=1},
    [4] = {x=0, y=1}, [5] = {x=-1, y=1}, [6] = {x=-1, y=0}, [7] = {x=-1, y=-1}
  }
  
  local dirVec = dirVecs[monsterDir] or {x=0, y=0}
  
  -- Get perpendicular directions (safe directions)
  local perpX, perpY = -dirVec.y, dirVec.x
  
  local candidates = {}
  -- Check tiles perpendicular to attack direction
  for dist = 1, 2 do
    for _, mult in ipairs({1, -1}) do
      local tile = {
        x = playerPos.x + perpX * dist * mult,
        y = playerPos.y + perpY * dist * mult,
        z = playerPos.z
      }
      
      -- Verify not in attack arc
      if not MonsterAI.Predictor.isPositionInWavePath(tile, monsterPos, monsterDir, range, width) then
        -- Check walkability
        local walkable = true
        if g_map and g_map.isTileWalkable then
          local ok, result = pcall(g_map.isTileWalkable, tile)
          walkable = ok and result
        elseif g_map and g_map.getTile then
          local ok, mapTile = pcall(g_map.getTile, tile)
          walkable = ok and mapTile and mapTile:isWalkable()
        end
        
        if walkable then
          -- Score by distance from monster (further = safer)
          local distFromMonster = math.abs(tile.x - monsterPos.x) + math.abs(tile.y - monsterPos.y)
          table.insert(candidates, { pos = tile, score = distFromMonster })
        end
      end
    end
  end
  
  -- Also try diagonal escapes
  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        local tile = { x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z }
        if not MonsterAI.Predictor.isPositionInWavePath(tile, monsterPos, monsterDir, range, width) then
          local walkable = true
          if g_map and g_map.getTile then
            local ok, mapTile = pcall(g_map.getTile, tile)
            walkable = ok and mapTile and mapTile:isWalkable()
          end
          if walkable then
            local distFromMonster = math.abs(tile.x - monsterPos.x) + math.abs(tile.y - monsterPos.y)
            table.insert(candidates, { pos = tile, score = distFromMonster + 0.5 })  -- Slight penalty vs perpendicular
          end
        end
      end
    end
  end
  
  -- Sort by score (higher = better)
  table.sort(candidates, function(a, b) return a.score > b.score end)
  
  return candidates[1] and candidates[1].pos or nil
end

-- Update threat cache (called periodically or on significant events)
function MonsterAI.RealTime.updateThreatCache()
  local nowt = nowMs()
  local cache = MonsterAI.RealTime.threatCache
  
  -- Skip if recently updated
  if (nowt - cache.lastUpdate) < CONST.EVENT_DRIVEN.THREAT_CACHE_TTL then
    return cache
  end
  
  local playerPos = player and player:getPosition()
  if not playerPos then return cache end
  
  cache.totalThreat = 0
  cache.highThreatMonsters = {}
  cache.immediateThreat = false
  
  -- Check all tracked directions for monsters facing player
  for id, rt in pairs(MonsterAI.RealTime.directions) do
    local data = MonsterAI.Tracker.monsters[id]
    if data and data.creature and not data.creature:isDead() then
      local monsterPos = data.creature:getPosition()
      if monsterPos and monsterPos.z == playerPos.z then
        local dist = math.max(math.abs(monsterPos.x - playerPos.x), math.abs(monsterPos.y - playerPos.y))
        
        if dist <= 7 then  -- Within threat range
          local isFacing = MonsterAI.Predictor.isFacingPosition(monsterPos, rt.dir, playerPos)
          if isFacing then
            local pattern = MonsterAI.Patterns.get(data.name or "")
            local cooldown = data.ewmaCooldown or (pattern and pattern.waveCooldown) or 2000
            local lastAttack = data.lastWaveTime or data.lastAttackTime or 0
            local elapsed = nowt - lastAttack
            local timeToAttack = math.max(0, cooldown - elapsed)
            
            local threat = {
              id = id,
              creature = data.creature,
              timeToAttack = timeToAttack,
              confidence = data.confidence or 0.5,
              turnRate = rt.turnRate or 0
            }
            
            table.insert(cache.highThreatMonsters, threat)
            
            if timeToAttack < CONST.EVENT_DRIVEN.IMMEDIATE_THREAT_WINDOW then
              cache.immediateThreat = true
              cache.totalThreat = cache.totalThreat + 1.5
            else
              cache.totalThreat = cache.totalThreat + 0.5
            end
          end
        end
      end
    end
  end
  
  cache.lastUpdate = nowt
  return cache
end

-- Clean up stale direction tracking
function MonsterAI.RealTime.cleanup()
  local nowt = nowMs()
  local staleThreshold = 10000  -- 10 seconds
  
  for id, rt in pairs(MonsterAI.RealTime.directions) do
    if (nowt - (rt.lastChangeTime or 0)) > staleThreshold then
      MonsterAI.RealTime.directions[id] = nil
    end
  end
  
  -- Clean prediction queue
  local queue = MonsterAI.RealTime.predictedAttacks
  local i = 1
  while i <= #queue do
    if (nowt - queue[i].registeredAt) > 5000 then
      table.remove(queue, i)
    else
      i = i + 1
    end
  end
end

-- ============================================================================
-- GET IMMEDIATE THREAT (Pure function for wave avoidance integration)
-- Returns a threat assessment suitable for instant decision-making
-- @return table { immediateThreat: boolean, totalThreat: number, threatCount: number, highestConfidence: number }
-- ============================================================================
function MonsterAI.getImmediateThreat()
  local nowt = nowMs()
  local result = {
    immediateThreat = false,
    totalThreat = 0,
    threatCount = 0,
    highestConfidence = 0,
    imminentMonsters = {}
  }
  
  -- Check threat cache first (fast path)
  local cache = MonsterAI.RealTime.threatCache
  if cache and (nowt - (cache.lastUpdate or 0)) < CONST.EVENT_DRIVEN.THREAT_CACHE_TTL then
    result.immediateThreat = cache.immediateThreat or false
    result.totalThreat = cache.totalThreat or 0
    result.threatCount = #(cache.highThreatMonsters or {})
    for _, t in ipairs(cache.highThreatMonsters or {}) do
      if t.confidence and t.confidence > result.highestConfidence then
        result.highestConfidence = t.confidence
      end
    end
    return result
  end
  
  -- Recalculate from prediction queue
  local queue = MonsterAI.RealTime.predictedAttacks
  for i = 1, #queue do
    local pred = queue[i]
    if pred and pred.predictedTime then
      local timeToAttack = pred.predictedTime - nowt
      if timeToAttack <= CONST.EVENT_DRIVEN.IMMEDIATE_THREAT_WINDOW then
        result.immediateThreat = true
        result.threatCount = result.threatCount + 1
        result.totalThreat = result.totalThreat + (pred.confidence or 0.5)
        if (pred.confidence or 0) > result.highestConfidence then
          result.highestConfidence = pred.confidence
        end
        table.insert(result.imminentMonsters, pred)
      end
    end
  end
  
  -- Also check directions for monsters facing player with short cooldown
  local playerPos = player and player:getPosition()
  if playerPos then
    for id, rt in pairs(MonsterAI.RealTime.directions) do
      if rt.facingPlayerSince then
        local facingDuration = nowt - rt.facingPlayerSince
        -- Monster has been facing player for >500ms = likely attack incoming
        if facingDuration > 500 then
          local data = MonsterAI.Tracker.monsters[id]
          if data and data.ewmaCooldown then
            local lastAttack = data.lastWaveTime or data.lastAttackTime or 0
            local elapsed = nowt - lastAttack
            local cooldown = data.ewmaCooldown
            if elapsed >= cooldown * 0.8 then
              result.immediateThreat = true
              result.totalThreat = result.totalThreat + 0.7
              result.threatCount = result.threatCount + 1
            end
          end
        end
      end
    end
  end
  
  return result
end

-- Alias for backward compatibility
MonsterAI.RealTime.getImmediateThreat = MonsterAI.getImmediateThreat

-- Initialize tracking for a monster
function MonsterAI.Tracker.track(creature)
  if not creature or creature:isDead() then return end
  
  local id = creature:getId()
  if not id then return end  -- Creature ID unavailable (invalid creature or getId() failed)
  if MonsterAI.Tracker.monsters[id] then return end  -- Already tracking
  
  local pos = creature:getPosition()
  if not pos then return end  -- Creature position unavailable (teleporting/disappearing)
  
  local nowt = nowMs()
  
  -- Collect initial telemetry snapshot
  local initialSnapshot = MonsterAI.Telemetry.collectSnapshot(creature)
  
  MonsterAI.Tracker.monsters[id] = {
    creature = creature,
    id = id,
    name = creature:getName(),
    samples = {},           -- {time, pos, dir, health, isAttacking}
    lastDirection = creature:getDirection(),
    lastPosition = {x = pos.x, y = pos.y, z = pos.z},
    lastSampleTime = nowt,
    lastAttackTime = 0,
    lastWaveTime = 0,
    attackCount = 0,
    directionChanges = 0,
    movementSamples = 0,
    stationaryCount = 0,
    chaseCount = 0,
    observedWaveAttacks = {},
    waveCount = 0,
    trackingStartTime = nowt, -- For classification timing

    -- Extended telemetry (OTClient API)
    damageSamples = {},     -- { {time, amount}, ... }
    totalDamage = 0,
    missileCount = 0,
    facingCount = 0,
    avgSpeed = initialSnapshot and initialSnapshot.speed or 0,
    baseSpeed = initialSnapshot and initialSnapshot.baseSpeed or 0,
    
    -- Walk pattern tracking
    walkSamples = {},       -- {time, isWalking, stepDuration, direction}
    avgStepDuration = 0,
    walkingRatio = 0,       -- Proportion of time spent walking
    
    -- Health tracking for damage rate calculation
    healthSamples = {},     -- {time, percent}
    lastHealthPercent = creature:getHealthPercent() or 100,
    healthChangeRate = 0,   -- Health % change per second
    
    -- Direction pattern tracking
    directionHistory = {},  -- {time, direction}
    turnFrequency = 0,      -- Turns per second
    
    -- Distance from player tracking
    distanceSamples = {},   -- {time, distance}
    avgDistanceFromPlayer = 0,
    preferredDistance = nil,
    
    -- Combat engagement metrics
    engagementStart = nil,  -- When player started attacking this
    engagementDuration = 0,
    damageDealtToMonster = 0,

    -- EWMA estimator for wave cooldown (learning)
    ewmaCooldown = nil,
    ewmaVariance = 0,
    ewmaAlpha = 0.3,

    -- Learned behavior
    predictedWaveCooldown = nil,
    confidence = 0.1         -- Start with low confidence
  }
  
  -- Update session stats
  MonsterAI.Telemetry.session.totalMonstersTracked = 
    (MonsterAI.Telemetry.session.totalMonstersTracked or 0) + 1
  
  -- Emit tracking started event
  if EventBus and EventBus.emit then
    EventBus.emit("monsterai:tracking_started", creature, id)
  end
end

-- Stop tracking a monster
function MonsterAI.Tracker.untrack(creatureId)
  local data = MonsterAI.Tracker.monsters[creatureId]
  
  if data then
    -- Update type statistics before removing
    MonsterAI.Telemetry.updateTypeStats(data.name, {
      avgSpeed = data.avgSpeed,
      dps = MonsterAI.Tracker.getDPS and MonsterAI.Tracker.getDPS(creatureId) or 0,
      totalDamage = data.totalDamage,
      waveCount = data.waveCount
    })
    
    -- Classify monster if enough data
    if data.movementSamples >= 10 then
      MonsterAI.Classifier.classify(data.name, data)
    end
    
    -- Check if this was a kill (monster dead)
    if data.creature and data.creature:isDead() then
      MonsterAI.Telemetry.session.killCount = (MonsterAI.Telemetry.session.killCount or 0) + 1
      
      -- Track kill time if we were engaged
      if data.engagementStart then
        local killTime = nowMs() - data.engagementStart
        local session = MonsterAI.Telemetry.session
        session.avgKillTime = session.avgKillTime * 0.8 + killTime * 0.2
      end
      
      -- Emit kill event
      if EventBus and EventBus.emit then
        EventBus.emit("monsterai:monster_killed", data.name, creatureId, {
          engagementDuration = data.engagementDuration,
          damageReceived = data.totalDamage,
          waveAttacks = data.waveCount
        })
      end
    end
  end
  
  MonsterAI.Tracker.monsters[creatureId] = nil
  MonsterAI.Telemetry.snapshots[creatureId] = nil
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
  local nowt = nowMs()
  local pos = creature:getPosition()
  if not pos then return end  -- Creature position unavailable
  
  local dir = creature:getDirection()
  local hp = creature:getHealthPercent()
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- CORE SAMPLE COLLECTION
  -- ═══════════════════════════════════════════════════════════════════════════
  
  local sample = {
    time = currentTime,
    pos = {x = pos.x, y = pos.y, z = pos.z},
    dir = dir,
    health = hp
  }
  
  -- Keep samples within analysis window
  table.insert(data.samples, sample)
  while #data.samples > 0 and 
        (currentTime - data.samples[1].time) > CONST.ANALYSIS_WINDOW do
    table.remove(data.samples, 1)
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- EXTENDED TELEMETRY (OTClient API)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  -- Collect full telemetry snapshot periodically
  local timeSinceLastTelemetry = nowt - (data.lastTelemetryTime or 0)
  if timeSinceLastTelemetry >= MonsterAI.TELEMETRY_INTERVAL then
    local snapshot = MonsterAI.Telemetry.collectSnapshot(creature)
    data.lastTelemetryTime = nowt
    
    if snapshot then
      -- Update speed tracking
      if snapshot.speed and snapshot.speed > 0 then
        data.avgSpeed = (data.avgSpeed or 0) * 0.85 + snapshot.speed * 0.15
        data.baseSpeed = snapshot.baseSpeed or data.baseSpeed
      end
      
      -- Track walk pattern
      table.insert(data.walkSamples, {
        time = nowt,
        isWalking = snapshot.isWalking,
        stepDuration = snapshot.stepDuration,
        direction = snapshot.walkDirection
      })
      -- Keep bounded
      while #data.walkSamples > 50 do table.remove(data.walkSamples, 1) end
      
      -- Update walking ratio
      local walkingCount = 0
      for i = 1, #data.walkSamples do
        if data.walkSamples[i].isWalking then walkingCount = walkingCount + 1 end
      end
      data.walkingRatio = walkingCount / math.max(1, #data.walkSamples)
      
      -- Track step duration average
      if snapshot.stepDuration and snapshot.stepDuration > 0 then
        data.avgStepDuration = (data.avgStepDuration or 0) * 0.8 + snapshot.stepDuration * 0.2
      end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- DIRECTION TRACKING
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if dir ~= data.lastDirection then
    data.directionChanges = data.directionChanges + 1
    
    -- Track direction history
    table.insert(data.directionHistory, { time = nowt, direction = dir })
    while #data.directionHistory > 30 do table.remove(data.directionHistory, 1) end
    
    -- Calculate turn frequency
    if #data.directionHistory >= 2 then
      local firstTurn = data.directionHistory[1]
      local timeWindow = (nowt - firstTurn.time) / 1000 -- seconds
      if timeWindow > 0 then
        data.turnFrequency = (#data.directionHistory - 1) / timeWindow
      end
    end
    
    data.lastDirection = dir
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- HEALTH CHANGE TRACKING
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if hp ~= data.lastHealthPercent then
    local healthChange = data.lastHealthPercent - hp -- Positive = damage taken
    
    table.insert(data.healthSamples, { time = nowt, percent = hp, change = healthChange })
    while #data.healthSamples > 30 do table.remove(data.healthSamples, 1) end
    
    -- Calculate health change rate (per second)
    if #data.healthSamples >= 2 then
      local totalChange = 0
      local totalTime = 0
      for i = 2, #data.healthSamples do
        totalChange = totalChange + (data.healthSamples[i].change or 0)
        totalTime = totalTime + (data.healthSamples[i].time - data.healthSamples[i-1].time)
      end
      if totalTime > 0 then
        data.healthChangeRate = (totalChange / (totalTime / 1000)) -- % per second
      end
    end
    
    -- Track damage dealt to monster (for kill time calculation)
    if healthChange > 0 then
      data.damageDealtToMonster = (data.damageDealtToMonster or 0) + healthChange
      
      -- Start engagement timer on first damage
      if not data.engagementStart then
        data.engagementStart = nowt
      end
    end
    
    data.lastHealthPercent = hp
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- MOVEMENT & DISTANCE TRACKING
  -- ═══════════════════════════════════════════════════════════════════════════
  
  data.movementSamples = data.movementSamples + 1
  local moved = not (pos.x == data.lastPosition.x and pos.y == data.lastPosition.y)
  
  local playerPos = player and player:getPosition()
  if playerPos then
    local dist = math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y))
    
    -- Track distance samples
    table.insert(data.distanceSamples, { time = nowt, distance = dist })
    while #data.distanceSamples > 30 do table.remove(data.distanceSamples, 1) end
    
    -- Calculate average distance
    local totalDist = 0
    for i = 1, #data.distanceSamples do
      totalDist = totalDist + data.distanceSamples[i].distance
    end
    data.avgDistanceFromPlayer = totalDist / math.max(1, #data.distanceSamples)
    
    -- Infer preferred distance (mode of distances)
    if #data.distanceSamples >= 10 then
      local distCounts = {}
      for i = 1, #data.distanceSamples do
        local d = data.distanceSamples[i].distance
        distCounts[d] = (distCounts[d] or 0) + 1
      end
      local maxCount, modeDistance = 0, 1
      for d, count in pairs(distCounts) do
        if count > maxCount then
          maxCount = count
          modeDistance = d
        end
      end
      data.preferredDistance = modeDistance
    end
  end
  
  if not moved then
    data.stationaryCount = data.stationaryCount + 1
  else
    -- Compute speed (tiles/sec) from last sample
    local dt = nowt - (data.lastSampleTime or nowt)
    local dx = math.max(math.abs(pos.x - data.lastPosition.x), math.abs(pos.y - data.lastPosition.y))
    if dt > 0 and dx > 0 then
      local instSpeed = dx / (dt / 1000)
      data.avgSpeed = (data.avgSpeed or 0) * 0.8 + instSpeed * 0.2 -- EWMA
    end
    data.lastSampleTime = nowt

    -- Check if moving toward player
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

    -- Facing detection (counts how often monster faces player)
    if playerPos then
      local ok, isFacing = pcall(function()
        if MonsterAI.Predictor and MonsterAI.Predictor.isFacingPosition then
          return MonsterAI.Predictor.isFacingPosition(pos, creature:getDirection(), playerPos)
        end
        return false
      end)
      if ok and isFacing then data.facingCount = (data.facingCount or 0) + 1 end
    end

    data.lastPosition = {x = pos.x, y = pos.y, z = pos.z}
  end
  
  -- Update confidence based on sample count
  local sampleRatio = math.min(#data.samples / 50, 1)  -- Need 50 samples for full confidence
  data.confidence = 0.1 + 0.6 * sampleRatio
end

-- Central helper: update EWMA mean and variance for observed intervals
-- Update EWMA mean + variance for an observed interval and persist summary
function MonsterAI.Tracker.updateEWMA(data, observed)
  if not data or not observed or observed <= 0 then return end
  local alpha = data.ewmaAlpha or CONST.EWMA.ALPHA_DEFAULT
  if not data.ewmaCooldown then
    data.ewmaCooldown = observed
    data.ewmaVariance = 0
  else
    local err = observed - data.ewmaCooldown
    data.ewmaCooldown = alpha * observed + (1 - alpha) * data.ewmaCooldown
    -- EWMA of squared error (variance proxy)
    data.ewmaVariance = (1 - alpha) * (data.ewmaVariance or 0) + alpha * (err * err)
  end
  data.predictedWaveCooldown = data.ewmaCooldown

  -- Persist via helper
  local pname = (data.name or ""):lower()
  MonsterAI.Patterns.persist(pname, {
    waveCooldown = data.ewmaCooldown,
    waveVariance = data.ewmaVariance,
    lastSeen = nowMs(),
    confidence = math.min((MonsterAI.Patterns.knownMonsters[pname] and MonsterAI.Patterns.knownMonsters[pname].confidence or 0.5) + 0.02, 0.99)
  })
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

-- Utility: compute DPS for a tracked creature
function MonsterAI.Tracker.getDPS(creatureId, windowMs)
  windowMs = windowMs or MonsterAI.DPS_WINDOW
  local nowt = nowMs()
  local data = MonsterAI.Tracker.monsters[creatureId]
  if not data or not data.damageSamples or #data.damageSamples == 0 then return 0 end
  local sum = 0
  for i = #data.damageSamples, 1, -1 do
    local s = data.damageSamples[i]
    if nowt - s.time <= windowMs then
      sum = sum + (s.amount or 0)
    else
      break
    end
  end
  local seconds = math.max(windowMs / 1000, 0.001)
  return sum / seconds
end


  
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
  
  -- Reduce confidence if we have noisy observations (large variance) via helper
  local function computeVariancePenalty(d)
    if not d or not d.ewmaVariance or not d.ewmaCooldown or d.ewmaCooldown <= 0 then return 0 end
    local std = math.sqrt(d.ewmaVariance or 0)
    local ratio = std / (d.ewmaCooldown + 1e-6)
    local penalty = math.min(CONST.EWMA.VARIANCE_PENALTY_MAX, ratio * CONST.EWMA.VARIANCE_PENALTY_SCALE)
    return penalty
  end

  local variancePenalty = computeVariancePenalty(data)
  if variancePenalty and variancePenalty > 0 then
    confidence = confidence * (1 - variancePenalty)
  end

  confidence = math.min(confidence, 0.95)
  confidence = math.max(confidence, 0.05)
  
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
      
      -- Emit wave prediction event for other modules (Exeta Amp, etc.)
      if isPredicted and confidence >= 0.5 and EventBus then
        EventBus.emit("monsterai:wave_predicted", monster, confidence, timeToAttack)
      end
      
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
-- COMBAT FEEDBACK MODULE (NEW in v2.0)
-- Tracks prediction accuracy and adjusts targeting weights dynamically
-- This enables the 30%+ accuracy improvement through adaptive learning
-- ============================================================================

MonsterAI.CombatFeedback = MonsterAI.CombatFeedback or {
  -- Prediction accuracy tracking
  predictions = {
    waveAttacks = { correct = 0, missed = 0, falsePositive = 0 },
    damageCorrelation = { correct = 0, missed = 0 },
    targetSelection = { optimal = 0, suboptimal = 0 }
  },
  
  -- Rolling accuracy metrics (EWMA)
  accuracy = {
    waveAttack = 0.5,       -- Start at 50%
    damageCorrelation = 0.5,
    targetSelection = 0.5,
    overall = 0.5
  },
  
  -- Adaptive weight adjustments
  weights = {
    wavePrediction = 1.0,    -- Multiplier for wave prediction confidence
    dpsBased = 1.0,          -- Multiplier for DPS-based priority
    facingBased = 1.0,       -- Multiplier for facing-based priority
    cooldownBased = 1.0,     -- Multiplier for cooldown prediction
    classificationBased = 1.0 -- Multiplier for classification-based priority
  },
  
  -- Recent events for feedback correlation
  recentPredictions = {},   -- {timestamp, monsterId, type, confidence, outcome}
  recentDamage = {},        -- {timestamp, amount, attributedTo}
  
  -- Tuning parameters
  EWMA_ALPHA = 0.15,        -- Learning rate for accuracy EWMA
  WEIGHT_ADJUST_RATE = 0.02, -- How fast weights change
  MIN_WEIGHT = 0.5,         -- Minimum weight multiplier
  MAX_WEIGHT = 1.5,         -- Maximum weight multiplier
  PREDICTION_WINDOW = 2000  -- ms window to correlate predictions with outcomes
}

-- Record a wave attack prediction
function MonsterAI.CombatFeedback.recordPrediction(monsterId, monsterName, predictedTime, confidence)
  local nowt = nowMs()
  
  table.insert(MonsterAI.CombatFeedback.recentPredictions, {
    timestamp = nowt,
    monsterId = monsterId,
    monsterName = monsterName,
    predictedTime = predictedTime,
    confidence = confidence,
    type = "wave",
    outcome = nil -- Will be updated when damage is received or timeout
  })
  
  -- Keep bounded
  while #MonsterAI.CombatFeedback.recentPredictions > 50 do
    table.remove(MonsterAI.CombatFeedback.recentPredictions, 1)
  end
end

-- Record damage received and correlate with predictions
function MonsterAI.CombatFeedback.recordDamage(amount, attributedMonsterId, attributedName)
  local nowt = nowMs()
  local fb = MonsterAI.CombatFeedback
  
  -- Record damage event
  table.insert(fb.recentDamage, {
    timestamp = nowt,
    amount = amount,
    attributedTo = attributedMonsterId,
    attributedName = attributedName
  })
  
  -- Keep bounded
  while #fb.recentDamage > 30 do
    table.remove(fb.recentDamage, 1)
  end
  
  -- Correlate with recent predictions
  local foundMatch = false
  for i = #fb.recentPredictions, 1, -1 do
    local pred = fb.recentPredictions[i]
    
    -- Check if this damage matches a prediction
    if pred.outcome == nil and pred.monsterId == attributedMonsterId then
      local timeDiff = math.abs(nowt - (pred.predictedTime or nowt))
      
      if timeDiff < fb.PREDICTION_WINDOW then
        -- Prediction was correct!
        pred.outcome = "correct"
        fb.predictions.waveAttacks.correct = fb.predictions.waveAttacks.correct + 1
        foundMatch = true
        
        -- Boost wave prediction weight
        fb.weights.wavePrediction = math.min(fb.MAX_WEIGHT, 
          fb.weights.wavePrediction + fb.WEIGHT_ADJUST_RATE * pred.confidence)
        
        break
      end
    end
  end
  
  -- If damage came from an unpredicted source, record as missed prediction
  if not foundMatch and attributedMonsterId then
    fb.predictions.damageCorrelation.missed = fb.predictions.damageCorrelation.missed + 1
  else
    fb.predictions.damageCorrelation.correct = fb.predictions.damageCorrelation.correct + 1
  end
  
  -- Update accuracy EWMA
  fb.updateAccuracyMetrics()
end

-- Check for timed-out predictions (false positives)
function MonsterAI.CombatFeedback.checkTimeouts()
  local nowt = nowMs()
  local fb = MonsterAI.CombatFeedback
  
  for i = #fb.recentPredictions, 1, -1 do
    local pred = fb.recentPredictions[i]
    
    if pred.outcome == nil then
      local elapsed = nowt - (pred.predictedTime or pred.timestamp)
      
      -- If predicted attack should have happened but no damage recorded
      if elapsed > fb.PREDICTION_WINDOW * 1.5 then
        pred.outcome = "falsePositive"
        fb.predictions.waveAttacks.falsePositive = fb.predictions.waveAttacks.falsePositive + 1
        
        -- Slightly reduce wave prediction weight for false positives
        fb.weights.wavePrediction = math.max(fb.MIN_WEIGHT, 
          fb.weights.wavePrediction - fb.WEIGHT_ADJUST_RATE * 0.5 * (pred.confidence or 0.5))
      end
    end
  end
end

-- Update accuracy metrics using EWMA
function MonsterAI.CombatFeedback.updateAccuracyMetrics()
  local fb = MonsterAI.CombatFeedback
  local alpha = fb.EWMA_ALPHA
  
  -- Wave attack accuracy
  local waveTotal = fb.predictions.waveAttacks.correct + fb.predictions.waveAttacks.missed + fb.predictions.waveAttacks.falsePositive
  if waveTotal > 0 then
    local waveAcc = fb.predictions.waveAttacks.correct / waveTotal
    fb.accuracy.waveAttack = fb.accuracy.waveAttack * (1 - alpha) + waveAcc * alpha
  end
  
  -- Damage correlation accuracy
  local dmgTotal = fb.predictions.damageCorrelation.correct + fb.predictions.damageCorrelation.missed
  if dmgTotal > 0 then
    local dmgAcc = fb.predictions.damageCorrelation.correct / dmgTotal
    fb.accuracy.damageCorrelation = fb.accuracy.damageCorrelation * (1 - alpha) + dmgAcc * alpha
  end
  
  -- Overall accuracy (weighted average)
  fb.accuracy.overall = (fb.accuracy.waveAttack * 0.4 + 
                         fb.accuracy.damageCorrelation * 0.4 +
                         fb.accuracy.targetSelection * 0.2)
  
  -- Emit accuracy update event
  if EventBus and EventBus.emit then
    EventBus.emit("monsterai:accuracy_update", fb.accuracy, fb.weights)
  end
end

-- Record target selection feedback (was our choice optimal?)
function MonsterAI.CombatFeedback.recordTargetSelection(selectedId, wasOptimal)
  local fb = MonsterAI.CombatFeedback
  
  if wasOptimal then
    fb.predictions.targetSelection.optimal = fb.predictions.targetSelection.optimal + 1
  else
    fb.predictions.targetSelection.suboptimal = fb.predictions.targetSelection.suboptimal + 1
  end
  
  -- Update target selection accuracy
  local total = fb.predictions.targetSelection.optimal + fb.predictions.targetSelection.suboptimal
  if total > 0 then
    local acc = fb.predictions.targetSelection.optimal / total
    fb.accuracy.targetSelection = fb.accuracy.targetSelection * (1 - fb.EWMA_ALPHA) + acc * fb.EWMA_ALPHA
  end
end

-- Get current weight adjustments for priority calculation
function MonsterAI.CombatFeedback.getWeights()
  return MonsterAI.CombatFeedback.weights
end

-- Get current accuracy metrics
function MonsterAI.CombatFeedback.getAccuracy()
  return MonsterAI.CombatFeedback.accuracy
end

-- Get feedback summary
function MonsterAI.CombatFeedback.getSummary()
  local fb = MonsterAI.CombatFeedback
  return {
    predictions = fb.predictions,
    accuracy = fb.accuracy,
    weights = fb.weights,
    recentPredictionCount = #fb.recentPredictions,
    recentDamageCount = #fb.recentDamage
  }
end

-- Reset feedback data (useful for new hunting session)
function MonsterAI.CombatFeedback.reset()
  local fb = MonsterAI.CombatFeedback
  fb.predictions = {
    waveAttacks = { correct = 0, missed = 0, falsePositive = 0 },
    damageCorrelation = { correct = 0, missed = 0 },
    targetSelection = { optimal = 0, suboptimal = 0 }
  }
  fb.accuracy = {
    waveAttack = 0.5,
    damageCorrelation = 0.5,
    targetSelection = 0.5,
    overall = 0.5
  }
  fb.weights = {
    wavePrediction = 1.0,
    dpsBased = 1.0,
    facingBased = 1.0,
    cooldownBased = 1.0,
    classificationBased = 1.0
  }
  fb.recentPredictions = {}
  fb.recentDamage = {}
end

-- ============================================================================
-- EVENTBUS INTEGRATION (Enhanced for Real-Time Threat Detection)
-- ============================================================================

if EventBus then
  -- Track monsters when they appear
  EventBus.on("monster:appear", function(creature)
    MonsterAI.Tracker.track(creature)
    
    -- Initialize direction tracking immediately
    if creature and creature:getId() then
      local id = creature:getId()
      local dir = creature:getDirection()
      MonsterAI.RealTime.directions[id] = {
        dir = dir,
        lastChangeTime = nowMs(),
        consecutiveChanges = 0,
        turnRate = 0
      }
      
      -- Check if already facing player (instant threat check)
      local playerPos = player and player:getPosition()
      local monsterPos = creature:getPosition()
      if playerPos and monsterPos then
        local dist = math.max(math.abs(monsterPos.x - playerPos.x), math.abs(monsterPos.y - playerPos.y))
        if dist <= 5 then
          local isFacing = MonsterAI.Predictor and MonsterAI.Predictor.isFacingPosition
            and MonsterAI.Predictor.isFacingPosition(monsterPos, dir, playerPos)
          if isFacing then
            MonsterAI.RealTime.registerImmediateThreat(creature, "spawn_facing", 0.55)
          end
        end
      end
    end
  end, 35)  -- Higher priority for faster registration
  
  -- Untrack monsters when they disappear
  EventBus.on("monster:disappear", function(creature)
    if creature then
      local id = creature:getId()
      if id then
        MonsterAI.Tracker.untrack(id)
        MonsterAI.RealTime.directions[id] = nil
        
        -- Remove from prediction queue
        local queue = MonsterAI.RealTime.predictedAttacks
        for i = #queue, 1, -1 do
          if queue[i].id == id then
            table.remove(queue, i)
          end
        end
      end
    end
  end, 35)
  
  -- CRITICAL: Direction change detection (primary wave anticipation)
  EventBus.on("creature:move", function(creature, oldPos)
    if not creature or not creature:isMonster() then return end
    
    local id = creature:getId()
    if not id then return end
    
    local newDir = creature:getDirection()
    local rt = MonsterAI.RealTime.directions[id]
    local oldDir = rt and rt.dir or newDir
    
    -- Direction changed - this is a key attack indicator
    if oldDir ~= newDir then
      MonsterAI.RealTime.onDirectionChange(creature, oldDir, newDir)
    else
      -- Position changed but direction same - update position tracking
      if rt then
        rt.positions = rt.positions or {}
        table.insert(rt.positions, { pos = creature:getPosition(), time = nowMs() })
        -- Keep last 10 positions
        while #rt.positions > 10 do table.remove(rt.positions, 1) end
      end
    end
    
    -- Also update the general tracker
    MonsterAI.Tracker.update(creature)
  end, 40)  -- High priority for instant response
  
  -- Update tracking on monster health change (potential attack indicator)
  EventBus.on("monster:health", function(creature, percent)
    if creature then
      MonsterAI.Tracker.update(creature)
      
      -- Health change often indicates monster is active/attacking
      local id = creature:getId()
      if id then
        local data = MonsterAI.Tracker.monsters[id]
        if data then
          data.lastActivityTime = nowMs()
        end
      end
    end
  end, 30)
  
  -- Record when player takes damage (learning opportunity)
  EventBus.on("player:damage", function(damage, source)
    MonsterAI.Tracker.stats.totalDamageReceived = 
      MonsterAI.Tracker.stats.totalDamageReceived + damage

    -- Try to correlate this damage to a nearby monster (handles non-projectile attacks)
    local nowt = nowMs()
    local playerPos = player and player:getPosition()
    if not playerPos then return end

    local function scoreMonsterForDamage(m, playerPos, nowt)
      if not m or not m:getPosition() or m:isDead() or not m:isMonster() then return 0, nil end
      local mpos = m:getPosition()
      local dist = math.max(math.abs(playerPos.x - mpos.x), math.abs(playerPos.y - mpos.y))
      local score = 1 / (1 + dist)
      local id = m:getId()
      local data = id and MonsterAI.Tracker.monsters[id]

      -- Prefer recently active/visible attackers
      if data and data.lastWaveTime and math.abs(nowt - data.lastWaveTime) < 800 then score = score + 1.2 end
      if data and data.lastAttackTime and math.abs(nowt - data.lastAttackTime) < 1500 then score = score + 0.8 end
      -- Prefer ones facing the player
      if data and MonsterAI.Predictor.isFacingPosition then
        local facing = MonsterAI.Predictor.isFacingPosition(mpos, m:getDirection(), playerPos)
        if facing then score = score + 0.6 end
      end
      return score, data
    end

    local creatures = (MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby)
      and MovementCoordinator.MonsterCache.getNearby(CONST.DAMAGE.CORRELATION_RADIUS)
      or g_map.getSpectatorsInRange(playerPos, false, CONST.DAMAGE.CORRELATION_RADIUS, CONST.DAMAGE.CORRELATION_RADIUS)

    local bestScore, bestData, bestMonster = 0, nil, nil
    for i = 1, #creatures do
      local m = creatures[i]
      local score, data = scoreMonsterForDamage(m, playerPos, nowt)
      if score and score > bestScore then bestScore, bestData, bestMonster = score, data, m end
    end

    if bestScore and bestScore > CONST.DAMAGE.CORRELATION_THRESHOLD and bestData then
      -- Attribute this damage
      bestData.lastDamageTime = nowt
      bestData.lastAttackTime = nowt
      bestData.waveCount = (bestData.waveCount or 0) + 1
      MonsterAI.Tracker.stats.areaAttacksObserved = MonsterAI.Tracker.stats.areaAttacksObserved + 1

      -- Record damage sample for DPS calculation
      bestData.damageSamples = bestData.damageSamples or {}
      table.insert(bestData.damageSamples, { time = nowt, amount = damage })
      -- Trim samples older than DPS window
      while #bestData.damageSamples > 0 and (nowt - bestData.damageSamples[1].time) > MonsterAI.DPS_WINDOW do
        table.remove(bestData.damageSamples, 1)
      end
      bestData.totalDamage = (bestData.totalDamage or 0) + damage

      -- If we have a previous damage timestamp, derive interval and update EWMA
      if bestData._lastDamageSample then
        local observed = nowt - bestData._lastDamageSample
        if observed > 80 then
          MonsterAI.Tracker.updateEWMA(bestData, observed)
        end
      end
      bestData._lastDamageSample = nowt
      
      -- ═══════════════════════════════════════════════════════════════════════
      -- COMBAT FEEDBACK INTEGRATION (NEW in v2.0)
      -- Record damage for accuracy tracking and weight adjustment
      -- ═══════════════════════════════════════════════════════════════════════
      if MonsterAI.CombatFeedback and MonsterAI.CombatFeedback.recordDamage then
        local attributedId = bestMonster and bestMonster:getId()
        local attributedName = bestData.name
        MonsterAI.CombatFeedback.recordDamage(damage, attributedId, attributedName)
      end

      -- Persist small bump
      local pname = (bestData.name or ""):lower()
      MonsterAI.Patterns.persist(pname, { lastSeen = nowMs(), confidence = math.min((MonsterAI.Patterns.knownMonsters[pname] and MonsterAI.Patterns.knownMonsters[pname].confidence or 0.5) + 0.03, 0.99) })
    end
  end, 30)

  -- Projectile/missile events: observe attacks originating from monsters
  if onMissle then
    onMissle(function(missle)
      local src = missle and missle:getSource()
      -- Guard method calls in case src does not implement expected API
      if not src or type(src.isCreature) ~= 'function' or not src:isCreature() then return end
      if type(src.isMonster) ~= 'function' or not src:isMonster() then return end

      local id = src:getId()
      if not id then return end

      if not MonsterAI.Tracker.monsters[id] then MonsterAI.Tracker.track(src) end
      local data = MonsterAI.Tracker.monsters[id]
      if not data then return end

      local nowt = nowMs()
      -- Record the attack timestamp
      if data.lastWaveTime and data.lastWaveTime > 0 then
        local observed = nowt - data.lastWaveTime
        if observed > 100 then -- ignore micro-events
          -- Update EWMA mean + variance via helper
          MonsterAI.Tracker.updateEWMA(data, observed)
          data.waveCount = (data.waveCount or 0) + 1

          -- Also persist this sample to pattern samples (bounded history)
          local pname = (data.name or ""):lower()
          local pattern = MonsterAI.Patterns.knownMonsters[pname] or {}
          pattern.samples = pattern.samples or {}
          table.insert(pattern.samples, 1, observed) -- newest first
          -- keep only last N samples
          while #pattern.samples > 30 do table.remove(pattern.samples) end
          MonsterAI.Patterns.persist(pname, { waveCooldown = data.ewmaCooldown, waveVariance = data.ewmaVariance, samples = pattern.samples, lastSeen = nowMs() })
        end
      end

      data.lastWaveTime = nowt
      data.observedWaveAttacks = data.observedWaveAttacks or {}
      table.insert(data.observedWaveAttacks, nowt)
      -- Bound the sample history to avoid unbounded growth
      if #data.observedWaveAttacks > 100 then table.remove(data.observedWaveAttacks, 1) end
      data.missileCount = (data.missileCount or 0) + 1
    end)
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- NATIVE OTCLIENT TURN CALLBACK
  -- Direct hook into OTClient's onCreatureTurn for fastest direction change detection
  -- This is critical for wave attack prediction as monsters turn before attacking
  -- ═══════════════════════════════════════════════════════════════════════════
  if onCreatureTurn then
    onCreatureTurn(function(creature, direction)
      if not creature then return end
      if not creature:isMonster() then return end
      if creature:isDead() then return end
      
      local id = creature:getId()
      if not id then return end
      
      local nowt = nowMs()
      local rt = MonsterAI.RealTime.directions[id]
      local oldDir = rt and rt.dir or direction
      
      -- Only process if direction actually changed
      if oldDir == direction then return end
      
      -- Initialize if not tracked
      if not rt then
        rt = {
          dir = direction,
          lastChangeTime = nowt,
          consecutiveChanges = 0,
          turnRate = 0
        }
        MonsterAI.RealTime.directions[id] = rt
        return
      end
      
      -- Calculate turn rate
      local deltaT = nowt - (rt.lastChangeTime or nowt)
      if deltaT > 50 then
        rt.turnRate = 1000 / deltaT  -- turns per second
      end
      
      -- Track consecutive changes
      rt.consecutiveChanges = (rt.consecutiveChanges or 0) + 1
      rt.dir = direction
      rt.lastChangeTime = nowt
      
      -- Emit creature:turn event for other modules (Exeta Amp, etc.)
      if EventBus then
        EventBus.emit("creature:turn", creature, direction, oldDir)
      end
      
      -- Check if now facing player
      local playerPos = player and player:getPosition()
      local monsterPos = creature:getPosition()
      if playerPos and monsterPos then
        local dist = math.max(math.abs(monsterPos.x - playerPos.x), math.abs(monsterPos.y - playerPos.y))
        if dist <= 6 then
          local isFacing = MonsterAI.Predictor and MonsterAI.Predictor.isFacingPosition
            and MonsterAI.Predictor.isFacingPosition(monsterPos, direction, playerPos)
          
          if isFacing then
            rt.facingPlayerSince = rt.facingPlayerSince or nowt
            
            -- High turn rate + now facing = imminent attack!
            if rt.turnRate > 1.5 or rt.consecutiveChanges >= 2 then
              MonsterAI.RealTime.registerImmediateThreat(creature, "turn_facing", 
                math.min(0.4 + rt.turnRate * 0.2, 0.9))
              
              if EventTargeting and EventTargeting.DEBUG then
                local name = creature:getName() or "Unknown"
                print("[MonsterAI] Turn threat: " .. name .. 
                      " turnRate=" .. string.format("%.2f", rt.turnRate) ..
                      " changes=" .. rt.consecutiveChanges)
              end
            end
          else
            rt.facingPlayerSince = nil
          end
        end
      end
      
      -- Reset consecutive changes after delay
      schedule(400, function()
        if rt and rt.lastChangeTime and (nowMs() - rt.lastChangeTime) > 350 then
          rt.consecutiveChanges = 0
          rt.turnRate = 0
        end
      end)
    end)
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- PLAYER ATTACK EVENT - Track engagement with monsters
  -- ═══════════════════════════════════════════════════════════════════════════
  EventBus.on("player:attack", function(target)
    if not target or not target:isMonster() then return end
    
    local id = target:getId()
    if not id then return end
    
    local data = MonsterAI.Tracker.monsters[id]
    if data then
      local nowt = nowMs()
      
      -- Record engagement start if not already engaged
      if not data.engagementStart then
        data.engagementStart = nowt
      end
      
      -- Emit engagement event
      if EventBus and EventBus.emit then
        EventBus.emit("monsterai:engagement_started", target, id, {
          name = data.name,
          healthPercent = target:getHealthPercent()
        })
      end
    end
  end, 25)
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- CREATURE DEATH EVENT - Finalize tracking and collect kill stats
  -- ═══════════════════════════════════════════════════════════════════════════
  EventBus.on("creature:death", function(creature)
    if not creature or not creature:isMonster() then return end
    
    local id = creature:getId()
    if not id then return end
    
    local data = MonsterAI.Tracker.monsters[id]
    if data then
      local nowt = nowMs()
      
      -- Calculate engagement duration if we were fighting it
      if data.engagementStart then
        data.engagementDuration = nowt - data.engagementStart
      end
      
      -- Update type stats with kill data
      local typeStats = MonsterAI.Telemetry.typeStats[data.name:lower()] or {}
      typeStats.killCount = (typeStats.killCount or 0) + 1
      if data.engagementDuration then
        typeStats.totalKillTime = (typeStats.totalKillTime or 0) + data.engagementDuration
      end
      MonsterAI.Telemetry.typeStats[data.name:lower()] = typeStats
      
      -- Classify monster if enough data
      if data.movementSamples >= 10 then
        local classification = MonsterAI.Classifier.classify(data.name, data)
        
        -- Auto-suggest danger adjustment after kill
        if classification then
          MonsterAI.AutoTuner.suggestDanger(data.name)
        end
      end
      
      -- Emit kill completed event with full stats
      if EventBus and EventBus.emit then
        EventBus.emit("monsterai:kill_completed", creature, id, {
          name = data.name,
          engagementDuration = data.engagementDuration or 0,
          damageReceived = data.totalDamage or 0,
          waveAttacks = data.waveCount or 0,
          missileCount = data.missileCount or 0,
          classification = MonsterAI.Classifier.get(data.name)
        })
      end
    end
    
    -- Untrack will be called by monster:disappear, but ensure we process death stats first
  end, 30)
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- PLAYER DEATH EVENT - Track session death stats
  -- ═══════════════════════════════════════════════════════════════════════════
  EventBus.on("player:death", function()
    local nowt = nowMs()
    
    MonsterAI.Telemetry.session.deathCount = (MonsterAI.Telemetry.session.deathCount or 0) + 1
    
    -- Emit death analysis event with nearby monster data
    local nearbyThreats = {}
    for id, data in pairs(MonsterAI.Tracker.monsters) do
      if data.creature and not data.creature:isDead() then
        local pos = data.creature:getPosition()
        local playerPos = player and player:getPosition()
        if pos and playerPos then
          local dist = math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y))
          if dist <= 5 then
            table.insert(nearbyThreats, {
              name = data.name,
              id = id,
              distance = dist,
              dps = MonsterAI.Tracker.getDPS(id) or 0,
              waveCount = data.waveCount or 0,
              classification = MonsterAI.Classifier.get(data.name)
            })
          end
        end
      end
    end
    
    if EventBus and EventBus.emit then
      EventBus.emit("monsterai:death_analysis", {
        timestamp = nowt,
        sessionDeaths = MonsterAI.Telemetry.session.deathCount,
        nearbyThreats = nearbyThreats,
        totalDamageReceived = MonsterAI.Tracker.stats.totalDamageReceived or 0
      })
    end
    
    if MonsterAI.DEBUG then
      print("[MonsterAI] Player death recorded. Nearby threats: " .. #nearbyThreats)
    end
  end, 20)
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- SPELL CAST EVENT - Track player damage output for kill time calculation
  -- ═══════════════════════════════════════════════════════════════════════════
  EventBus.on("player:spell", function(spellName, target)
    if not target or not target:isMonster() then return end
    
    local id = target:getId()
    if not id then return end
    
    local data = MonsterAI.Tracker.monsters[id]
    if data then
      -- Record spell usage against this monster (for DPS analysis)
      data.spellsReceived = (data.spellsReceived or 0) + 1
    end
  end, 20)
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- COMBAT STATUS CHANGES - Track when entering/leaving combat
  -- ═══════════════════════════════════════════════════════════════════════════
  EventBus.on("player:combat_start", function()
    local nowt = nowMs()
    MonsterAI.Telemetry.session.lastCombatStart = nowt
    
    -- Emit combat start with nearby monster summary
    local nearbyMonsters = {}
    for id, data in pairs(MonsterAI.Tracker.monsters) do
      if data.name then
        table.insert(nearbyMonsters, {
          name = data.name,
          classification = MonsterAI.Classifier.get(data.name),
          estimatedDanger = MonsterAI.Patterns.get(data.name).dangerLevel
        })
      end
    end
    
    if EventBus and EventBus.emit then
      EventBus.emit("monsterai:combat_start", {
        timestamp = nowt,
        nearbyMonsters = nearbyMonsters
      })
    end
  end, 20)
  
  EventBus.on("player:combat_end", function()
    local nowt = nowMs()
    local combatStart = MonsterAI.Telemetry.session.lastCombatStart or nowt
    local combatDuration = nowt - combatStart
    
    MonsterAI.Telemetry.session.lastCombatDuration = combatDuration
    
    if EventBus and EventBus.emit then
      EventBus.emit("monsterai:combat_end", {
        timestamp = nowt,
        duration = combatDuration,
        damageReceived = MonsterAI.Tracker.stats.totalDamageReceived or 0
      })
    end
  end, 20)
end

-- ============================================================================
-- PERIODIC UPDATE (Enhanced with RealTime threat processing)
-- ============================================================================

-- Update all tracked monsters periodically
function MonsterAI.updateAll()
  local playerPos = player and player:getPosition()
  if not playerPos then
    return
  end

  -- OPTIMIZED: Prefer MonsterCache for O(1) cached creature lookup
  -- This avoids expensive g_map.getSpectatorsInRange calls
  local creatures = nil
  if MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby then
    creatures = MovementCoordinator.MonsterCache.getNearby(8)
  end
  
  -- Fallback only if MonsterCache is empty or unavailable
  if not creatures or #creatures == 0 then
    if SpectatorCache and SpectatorCache.getNearby then
      creatures = SpectatorCache.getNearby(8, 8) or {}
    else
      local ok, result = pcall(function() return g_map.getSpectatorsInRange(playerPos, false, 8, 8) end)
      creatures = ok and result or {}
    end
  end

  if not creatures then
    return
  end

  local processed = 0
  for i = 1, #creatures do
    local creature = creatures[i]
    if creature and creature:isMonster() and not creature:isDead() then
      local ok, err = pcall(function() MonsterAI.Tracker.update(creature) end)
      if not ok then
        -- Tracker.update failed (silent)
      end
      processed = processed + 1
    end
  end

  -- Update RealTime threat cache and cleanup stale entries
  if MonsterAI.RealTime then
    pcall(function() MonsterAI.RealTime.updateThreatCache() end)
    pcall(function() MonsterAI.RealTime.cleanup() end)
    
    -- Process prediction queue - emit warnings for imminent attacks
    local nowt = nowMs()
    local queue = MonsterAI.RealTime.predictedAttacks
    for i = #queue, 1, -1 do
      local pred = queue[i]
      local timeToAttack = (pred.predictedTime or 0) - nowt
      
      -- Imminent attack warning (within 300ms)
      if timeToAttack > 0 and timeToAttack < 300 and pred.confidence >= 0.6 then
        if EventBus then
          pcall(function()
            EventBus.emit("monsterai/imminent_attack", pred.creature, {
              timeToAttack = timeToAttack,
              confidence = pred.confidence,
              pos = pred.pos,
              dir = pred.dir
            })
          end)
        end
        
        -- Record prediction for feedback tracking (NEW in v2.0)
        if MonsterAI.CombatFeedback and MonsterAI.CombatFeedback.recordPrediction then
          local monsterId = pred.id
          local monsterName = pred.creature and pred.creature:getName() or "unknown"
          MonsterAI.CombatFeedback.recordPrediction(monsterId, monsterName, pred.predictedTime, pred.confidence)
        end
        
        table.remove(queue, i)
      elseif timeToAttack < -1000 then
        -- Attack should have happened, remove stale prediction
        -- Check if it was a miss (no damage recorded)
        if MonsterAI.RealTime.metrics then
          MonsterAI.RealTime.metrics.predictionsMissed = (MonsterAI.RealTime.metrics.predictionsMissed or 0) + 1
        end
        table.remove(queue, i)
      end
    end
  end
  
  -- Combat Feedback timeout check (NEW in v2.0)
  if MonsterAI.CombatFeedback and MonsterAI.CombatFeedback.checkTimeouts then
    pcall(function() MonsterAI.CombatFeedback.checkTimeouts() end)
  end

  MonsterAI.lastUpdate = nowMs()
end

-- ============================================================================
-- PUBLIC API: Real-Time Threat Queries  
-- NOTE: getImmediateThreat() is defined earlier (after cleanup function)
-- for better integration with wave avoidance and prediction queue
-- ============================================================================

-- Get prediction accuracy stats
function MonsterAI.getPredictionStats()
  local stats = {
    eventsProcessed = 0,
    predictionsCorrect = 0,
    predictionsMissed = 0,
    accuracy = 0
  }
  
  if MonsterAI.RealTime and MonsterAI.RealTime.metrics then
    local m = MonsterAI.RealTime.metrics
    stats.eventsProcessed = m.eventsProcessed or 0
    stats.predictionsCorrect = m.predictionsCorrect or 0
    stats.predictionsMissed = m.predictionsMissed or 0
    
    local total = stats.predictionsCorrect + stats.predictionsMissed
    if total > 0 then
      stats.accuracy = stats.predictionsCorrect / total
    end
  end
  
  -- Also include WavePredictor stats if available
  if WavePredictor and WavePredictor.getStats then
    local wpStats = WavePredictor.getStats()
    stats.wavePredictor = wpStats
  end
  
  return stats
end

-- Check if a specific position is currently dangerous
function MonsterAI.isPositionDangerous(pos)
  if not pos then return false, 0 end
  
  local playerPos = player and player:getPosition()
  if not playerPos or pos.z ~= playerPos.z then return false, 0 end
  
  local totalDanger = 0
  local monstersChecked = 0
  
  for id, rt in pairs(MonsterAI.RealTime.directions or {}) do
    local data = MonsterAI.Tracker.monsters[id]
    if data and data.creature and not data.creature:isDead() then
      local monsterPos = data.creature:getPosition()
      if monsterPos and monsterPos.z == pos.z then
        local pattern = MonsterAI.Patterns.get(data.name or "")
        local inPath = MonsterAI.Predictor.isPositionInWavePath(
          pos, monsterPos, rt.dir, pattern.waveRange, pattern.waveWidth
        )
        
        if inPath then
          -- Calculate threat based on cooldown timing
          local cooldown = data.ewmaCooldown or (pattern.waveCooldown or 2000)
          local elapsed = nowMs() - (data.lastWaveTime or data.lastAttackTime or 0)
          local timeToAttack = math.max(0, cooldown - elapsed)
          
          -- Closer to attack = more danger
          local urgency = 1 - math.min(1, timeToAttack / 2000)
          local danger = urgency * (data.confidence or 0.5)
          
          -- Boost if monster is facing this position
          local isFacing = rt.facingPlayerSince and (nowMs() - rt.facingPlayerSince) < 2000
          if isFacing then danger = danger * 1.5 end
          
          totalDanger = totalDanger + danger
          monstersChecked = monstersChecked + 1
        end
      end
    end
  end
  
  return totalDanger > 0.5, totalDanger
end

-- Export for external use
nExBot = nExBot or {}
nExBot.MonsterAI = MonsterAI

-- ============================================================================
-- ENHANCED PUBLIC API
-- ============================================================================

-- Get full statistics summary for UI or debugging
function MonsterAI.getStatsSummary()
  local nowt = nowMs()
  local session = MonsterAI.Telemetry.session
  local sessionDuration = (nowt - (session.startTime or nowt)) / 1000 -- seconds
  
  return {
    version = MonsterAI.VERSION,
    
    -- Session stats
    session = {
      duration = sessionDuration,
      monstersTracked = session.totalMonstersTracked or 0,
      killCount = session.killCount or 0,
      avgKillTime = session.avgKillTime or 0,
      damageReceived = MonsterAI.Tracker.stats.totalDamageReceived or 0,
      avgDPSReceived = sessionDuration > 0 and (MonsterAI.Tracker.stats.totalDamageReceived or 0) / sessionDuration or 0
    },
    
    -- Prediction stats
    predictions = MonsterAI.getPredictionStats(),
    
    -- Tracking stats
    tracking = {
      activeMonsters = 0,  -- Will be counted below
      waveAttacksObserved = MonsterAI.Tracker.stats.waveAttacksObserved or 0,
      areaAttacksObserved = MonsterAI.Tracker.stats.areaAttacksObserved or 0
    },
    
    -- Auto-tuner stats
    autoTuner = {
      enabled = MonsterAI.AUTO_TUNE_ENABLED,
      adjustmentsMade = MonsterAI.RealTime.metrics.autoTuneAdjustments or 0,
      pendingSuggestions = 0  -- Will be counted below
    },
    
    -- Telemetry stats
    telemetry = {
      samplesCollected = MonsterAI.RealTime.metrics.telemetrySamples or 0,
      typesClassified = 0  -- Will be counted below
    }
  }
end

-- Count active stats
pcall(function()
  local stats = MonsterAI.getStatsSummary()
  local activeCount = 0
  for id, _ in pairs(MonsterAI.Tracker.monsters) do activeCount = activeCount + 1 end
  stats.tracking.activeMonsters = activeCount
  
  local suggestionCount = 0
  for name, _ in pairs(MonsterAI.AutoTuner.suggestions) do suggestionCount = suggestionCount + 1 end
  stats.autoTuner.pendingSuggestions = suggestionCount
  
  local classifiedCount = 0
  for name, _ in pairs(MonsterAI.Classifier.cache) do classifiedCount = classifiedCount + 1 end
  stats.telemetry.typesClassified = classifiedCount
end)

-- Get all classifications
function MonsterAI.getClassifications()
  return MonsterAI.Classifier.cache
end

-- Get classification for specific monster
function MonsterAI.getClassification(name)
  return MonsterAI.Classifier.get(name)
end

-- Force classification of a monster
function MonsterAI.classifyMonster(name, forceReclassify)
  if not name then return nil end
  
  -- Find tracking data for this monster type
  local targetData = nil
  for id, data in pairs(MonsterAI.Tracker.monsters) do
    if data.name and data.name:lower() == name:lower() then
      targetData = data
      break
    end
  end
  
  if not targetData then
    -- No active tracking data, use stored patterns if available
    local pattern = MonsterAI.Patterns.get(name)
    if pattern then
      -- Create minimal data from pattern
      targetData = {
        name = name,
        movementSamples = 20, -- Minimum to trigger classification
        stationaryCount = 0,
        chaseCount = 10,
        facingCount = 5,
        waveCount = pattern.waveCount or 0,
        avgSpeed = 0
      }
    end
  end
  
  if targetData then
    return MonsterAI.Classifier.classify(name, targetData)
  end
  
  return nil
end

-- Get danger suggestion for a monster
function MonsterAI.getDangerSuggestion(name)
  return MonsterAI.AutoTuner.suggestDanger(name)
end

-- Apply danger suggestion
function MonsterAI.applyDangerSuggestion(name, force)
  return MonsterAI.AutoTuner.applyDangerSuggestion(name, force)
end

-- Get all pending suggestions
function MonsterAI.getPendingSuggestions()
  return MonsterAI.AutoTuner.getSuggestions()
end

-- Get telemetry for a creature by ID
function MonsterAI.getTelemetry(creatureId)
  return MonsterAI.Telemetry.snapshots[creatureId]
end

-- Get type statistics
function MonsterAI.getTypeStats(name)
  return MonsterAI.Telemetry.getTypeSummary(name)
end

-- Get all type statistics
function MonsterAI.getAllTypeStats()
  return MonsterAI.Telemetry.typeStats
end

-- Reset session statistics
function MonsterAI.resetSession()
  MonsterAI.Telemetry.session = {
    startTime = nowMs(),
    totalMonstersTracked = 0,
    totalDamageDealt = 0,
    totalDamageReceived = 0,
    killCount = 0,
    deathCount = 0,
    avgKillTime = 0,
    avgDPSReceived = 0
  }
  
  MonsterAI.Tracker.stats = {
    waveAttacksObserved = 0,
    areaAttacksObserved = 0,
    totalDamageReceived = 0,
    avoidanceSuccesses = 0,
    avoidanceFailures = 0
  }
  
  MonsterAI.RealTime.metrics = {
    eventsProcessed = 0,
    predictionsCorrect = 0,
    predictionsMissed = 0,
    avgPredictionAccuracy = 0,
    telemetrySamples = 0,
    autoTuneAdjustments = 0
  }
  
  if MonsterAI.DEBUG then
    print("[MonsterAI] Session statistics reset")
  end
end

-- ============================================================================
-- ENHANCED EVENTBUS EMISSIONS
-- ============================================================================

-- Emit periodic stats update for interested modules
if EventBus then
  schedule(5000, function()
    local function emitStatsUpdate()
      if EventBus and EventBus.emit then
        local stats = MonsterAI.getStatsSummary()
        EventBus.emit("monsterai:stats_update", stats)
      end
      schedule(10000, emitStatsUpdate) -- Every 10 seconds
    end
    emitStatsUpdate()
  end)
end

-- Enable automatic collection by default so Monster Insights shows data without console commands
-- You can disable via: MonsterAI.COLLECT_ENABLED = false
MonsterAI.COLLECT_ENABLED = (MonsterAI.COLLECT_ENABLED == nil) and true or MonsterAI.COLLECT_ENABLED

-- Periodic background updater - now faster (500ms) for better responsiveness
-- The updateAll function is optimized and event-driven tracking handles most work
macro(500, function()
  if MonsterAI.COLLECT_ENABLED and MonsterAI.updateAll then
    pcall(function() MonsterAI.updateAll() end)
  end
end)

-- Auto-tuner periodic pass (runs every 30 seconds)
macro(30000, function()
  if MonsterAI.AUTO_TUNE_ENABLED and MonsterAI.AutoTuner and MonsterAI.AutoTuner.runPass then
    pcall(function() MonsterAI.AutoTuner.runPass() end)
  end
end)

-- ============================================================================
-- SCENARIO MANAGER MODULE v2.1
-- Intelligent multi-monster handling and anti-zigzag movement system
-- Detects combat scenarios and applies appropriate targeting strategies
-- ============================================================================

MonsterAI.Scenario = MonsterAI.Scenario or {}
local Scenario = MonsterAI.Scenario

-- Scenario types
Scenario.TYPES = {
  IDLE = "idle",              -- No monsters nearby
  SINGLE = "single",          -- 1 monster - simple target
  FEW = "few",                -- 2-3 monsters - careful targeting, prevent zigzag
  MODERATE = "moderate",      -- 4-6 monsters - balanced approach
  SWARM = "swarm",            -- 7-10 monsters - focus on survival
  OVERWHELMING = "overwhelming" -- 11+ monsters - emergency mode
}

-- Current scenario state
Scenario.state = {
  type = Scenario.TYPES.IDLE,
  monsterCount = 0,
  lastUpdate = 0,
  targetLockId = nil,           -- Current locked target to prevent switching
  targetLockTime = 0,           -- When target was locked
  targetLockHealth = 100,       -- Health when locked (to detect progress)
  switchCooldown = 0,           -- Prevent rapid target switches
  lastSwitchTime = 0,           -- When we last switched targets
  consecutiveSwitches = 0,      -- Count of rapid switches (zigzag indicator)
  movementHistory = {},         -- Recent movement directions for zigzag detection
  scenarioStartTime = 0,        -- When current scenario started
  avgDangerLevel = 0,           -- Average threat level of nearby monsters
  clusterInfo = nil             -- Monster clustering analysis
}

-- Configuration for each scenario type
Scenario.configs = {
  [Scenario.TYPES.IDLE] = {
    switchCooldownMs = 0,
    targetStickiness = 0,
    prioritizeFinishingKills = false,
    allowZigzag = true,
    description = "No combat"
  },
  
  [Scenario.TYPES.SINGLE] = {
    switchCooldownMs = 500,       -- Can switch quickly if needed
    targetStickiness = 10,        -- Low stickiness
    prioritizeFinishingKills = true,
    allowZigzag = true,           -- Single target, movement doesn't matter
    description = "Single target - aggressive"
  },
  
  [Scenario.TYPES.FEW] = {
    switchCooldownMs = 2000,      -- 2 second minimum before switching (ANTI-ZIGZAG)
    targetStickiness = 50,        -- HIGH stickiness to prevent zigzag
    prioritizeFinishingKills = true,
    allowZigzag = false,          -- STRICT: No zigzag allowed
    maxSwitchesPerMinute = 6,     -- Max 6 switches per minute (every 10s avg)
    healthThresholdForSwitch = 40, -- Only switch if target above 40% health AND better target exists
    description = "Few targets - stable targeting, anti-zigzag"
  },
  
  [Scenario.TYPES.MODERATE] = {
    switchCooldownMs = 1500,      -- 1.5 second cooldown
    targetStickiness = 35,        -- Medium stickiness
    prioritizeFinishingKills = true,
    allowZigzag = false,          -- Still prevent zigzag
    maxSwitchesPerMinute = 10,
    healthThresholdForSwitch = 30,
    description = "Moderate - balanced targeting"
  },
  
  [Scenario.TYPES.SWARM] = {
    switchCooldownMs = 1000,      -- Faster switching for survival
    targetStickiness = 20,        -- Lower stickiness, need to react
    prioritizeFinishingKills = false, -- Survival over kills
    allowZigzag = false,          -- But still prevent erratic movement
    maxSwitchesPerMinute = 15,
    healthThresholdForSwitch = 20,
    focusLowestHealth = true,     -- Prioritize finishing any monster
    description = "Swarm - survival mode"
  },
  
  [Scenario.TYPES.OVERWHELMING] = {
    switchCooldownMs = 500,       -- Fast reaction needed
    targetStickiness = 10,        -- Very low stickiness
    prioritizeFinishingKills = false,
    allowZigzag = true,           -- Survival trumps movement quality
    focusLowestHealth = true,
    emergencyMode = true,         -- Special handling
    description = "Overwhelming - emergency survival"
  }
}

-- ============================================================================
-- SCENARIO DETECTION
-- ============================================================================

-- Detect current combat scenario
function Scenario.detectScenario()
  local playerPos = player and player:getPosition()
  if not playerPos then
    Scenario.state.type = Scenario.TYPES.IDLE
    Scenario.state.monsterCount = 0
    return Scenario.state.type
  end
  
  local nowt = nowMs()
  
  -- Rate limit updates (every 200ms)
  if nowt - Scenario.state.lastUpdate < 200 then
    return Scenario.state.type
  end
  Scenario.state.lastUpdate = nowt
  
  -- Count nearby monsters and gather info
  local monsters = {}
  local totalDanger = 0
  local monsterCount = 0
  
  local creatures = g_map.getSpectators(playerPos, false) or {}
  
  for _, creature in ipairs(creatures) do
    if creature and creature:isMonster() and not creature:isDead() and not creature:isRemoved() then
      local creaturePos = creature:getPosition()
      if creaturePos and creaturePos.z == playerPos.z then
        local dx = math.abs(creaturePos.x - playerPos.x)
        local dy = math.abs(creaturePos.y - playerPos.y)
        local dist = math.max(dx, dy)
        
        if dist <= 10 then  -- Within targeting range
          monsterCount = monsterCount + 1
          
          local danger = 1
          local id = creature:getId()
          local trackerData = MonsterAI.Tracker and MonsterAI.Tracker.monsters[id]
          if trackerData then
            danger = (trackerData.ewmaDps or 1) / 10 + 1
          end
          totalDanger = totalDanger + danger
          
          table.insert(monsters, {
            creature = creature,
            id = id,
            distance = dist,
            health = creature:getHealthPercent() or 100,
            danger = danger,
            pos = creaturePos
          })
        end
      end
    end
  end
  
  -- Update state
  local prevType = Scenario.state.type
  Scenario.state.monsterCount = monsterCount
  Scenario.state.avgDangerLevel = monsterCount > 0 and (totalDanger / monsterCount) or 0
  
  -- Determine scenario type
  local newType
  if monsterCount == 0 then
    newType = Scenario.TYPES.IDLE
  elseif monsterCount == 1 then
    newType = Scenario.TYPES.SINGLE
  elseif monsterCount <= 3 then
    newType = Scenario.TYPES.FEW
  elseif monsterCount <= 6 then
    newType = Scenario.TYPES.MODERATE
  elseif monsterCount <= 10 then
    newType = Scenario.TYPES.SWARM
  else
    newType = Scenario.TYPES.OVERWHELMING
  end
  
  Scenario.state.type = newType
  
  -- Track scenario changes
  if newType ~= prevType then
    Scenario.state.scenarioStartTime = nowt
    Scenario.state.consecutiveSwitches = 0  -- Reset on scenario change
    
    if EventBus and EventBus.emit then
      EventBus.emit("scenario:changed", newType, prevType, monsterCount)
    end
  end
  
  -- Analyze clustering for optimal positioning
  Scenario.analyzeCluster(monsters)
  
  return newType
end

-- ============================================================================
-- MONSTER CLUSTERING ANALYSIS
-- ============================================================================

function Scenario.analyzeCluster(monsters)
  if #monsters < 2 then
    Scenario.state.clusterInfo = nil
    return
  end
  
  -- Calculate centroid and spread
  local sumX, sumY = 0, 0
  for _, m in ipairs(monsters) do
    sumX = sumX + m.pos.x
    sumY = sumY + m.pos.y
  end
  
  local centroidX = sumX / #monsters
  local centroidY = sumY / #monsters
  
  -- Calculate spread (average distance from centroid)
  local totalSpread = 0
  for _, m in ipairs(monsters) do
    local dx = m.pos.x - centroidX
    local dy = m.pos.y - centroidY
    totalSpread = totalSpread + math.sqrt(dx*dx + dy*dy)
  end
  local avgSpread = totalSpread / #monsters
  
  -- Determine cluster type
  local clusterType
  if avgSpread < 2 then
    clusterType = "tight"     -- Good for AoE
  elseif avgSpread < 4 then
    clusterType = "medium"    -- Moderate AoE potential
  else
    clusterType = "spread"    -- Better to focus single targets
  end
  
  Scenario.state.clusterInfo = {
    centroid = {x = centroidX, y = centroidY},
    spread = avgSpread,
    type = clusterType,
    monsters = monsters
  }
end

-- ============================================================================
-- TARGET LOCK SYSTEM (Anti-Zigzag)
-- ============================================================================

-- Check if we should allow a target switch
function Scenario.shouldAllowTargetSwitch(newTargetId, newTargetPriority, newTargetHealth)
  local nowt = nowMs()
  local cfg = Scenario.configs[Scenario.state.type] or Scenario.configs[Scenario.TYPES.FEW]
  
  -- No lock exists - allow switch
  if not Scenario.state.targetLockId then
    return true, "no_lock"
  end
  
  -- Check if locked target is still valid
  local lockedCreature = nil
  if MonsterAI.Tracker and MonsterAI.Tracker.monsters[Scenario.state.targetLockId] then
    local data = MonsterAI.Tracker.monsters[Scenario.state.targetLockId]
    lockedCreature = data.creature
  end
  
  if not lockedCreature or lockedCreature:isDead() or lockedCreature:isRemoved() then
    Scenario.clearTargetLock()
    return true, "target_dead"
  end
  
  -- Same target - always allow
  if newTargetId == Scenario.state.targetLockId then
    return true, "same_target"
  end
  
  -- Check switch cooldown
  local timeSinceSwitch = nowt - Scenario.state.lastSwitchTime
  if timeSinceSwitch < cfg.switchCooldownMs then
    return false, "cooldown"
  end
  
  -- Check switches per minute limit
  if cfg.maxSwitchesPerMinute then
    local switchInterval = 60000 / cfg.maxSwitchesPerMinute
    if timeSinceSwitch < switchInterval and Scenario.state.consecutiveSwitches > 2 then
      return false, "rate_limit"
    end
  end
  
  -- Calculate locked target's current state
  local lockedHealth = lockedCreature:getHealthPercent() or 100
  local lockedHealthDrop = Scenario.state.targetLockHealth - lockedHealth
  
  -- If we're making progress on current target (health dropping), stay focused
  if lockedHealthDrop > 10 and lockedHealth > 5 then
    -- Good progress - add stickiness bonus
    local progressBonus = math.min(30, lockedHealthDrop)
    
    -- Check if new target is significantly better
    local lockData = MonsterAI.Tracker.monsters[Scenario.state.targetLockId]
    local lockedPriority = 100  -- Base priority for calculation
    if lockData then
      lockedPriority = lockedPriority + (100 - lockedHealth) * 0.5  -- Health-based
    end
    
    -- Add stickiness and progress bonus
    lockedPriority = lockedPriority + cfg.targetStickiness + progressBonus
    
    -- New target must be SIGNIFICANTLY better to justify switch
    local switchThreshold = 1.3  -- 30% better required
    if newTargetPriority < lockedPriority * switchThreshold then
      return false, "making_progress"
    end
  end
  
  -- Health threshold check (don't switch if current target is low health)
  if cfg.healthThresholdForSwitch and lockedHealth < cfg.healthThresholdForSwitch then
    -- Current target is low health - finish it!
    if lockedHealth < 20 then
      return false, "finishing_kill"
    end
  end
  
  -- Zigzag detection - check if we've been switching too rapidly
  if not cfg.allowZigzag and Scenario.state.consecutiveSwitches >= 3 then
    local avgSwitchTime = (nowt - Scenario.state.scenarioStartTime) / math.max(1, Scenario.state.consecutiveSwitches)
    if avgSwitchTime < 3000 then  -- Less than 3 seconds per switch on average
      -- Force lock on current target
      return false, "zigzag_prevention"
    end
  end
  
  return true, "allowed"
end

-- Lock onto a target
function Scenario.lockTarget(creatureId, health)
  local nowt = nowMs()
  local prevLock = Scenario.state.targetLockId
  
  Scenario.state.targetLockId = creatureId
  Scenario.state.targetLockTime = nowt
  Scenario.state.targetLockHealth = health or 100
  
  -- Track switches
  if prevLock and prevLock ~= creatureId then
    Scenario.state.lastSwitchTime = nowt
    Scenario.state.consecutiveSwitches = Scenario.state.consecutiveSwitches + 1
    
    -- Record movement for zigzag detection
    Scenario.recordMovement()
  end
end

-- Clear target lock
function Scenario.clearTargetLock()
  Scenario.state.targetLockId = nil
  Scenario.state.targetLockTime = 0
  Scenario.state.targetLockHealth = 100
end

-- ============================================================================
-- ZIGZAG MOVEMENT DETECTION
-- ============================================================================

function Scenario.recordMovement()
  local playerPos = player and player:getPosition()
  if not playerPos then return end
  
  local nowt = nowMs()
  local history = Scenario.state.movementHistory
  
  -- Add current position
  table.insert(history, {
    x = playerPos.x,
    y = playerPos.y,
    time = nowt
  })
  
  -- Keep only last 10 positions
  while #history > 10 do
    table.remove(history, 1)
  end
end

function Scenario.isZigzagging()
  local history = Scenario.state.movementHistory
  if #history < 4 then return false end
  
  -- Check for direction reversals
  local reversals = 0
  local prevDx, prevDy = 0, 0
  
  for i = 2, #history do
    local dx = history[i].x - history[i-1].x
    local dy = history[i].y - history[i-1].y
    
    -- Check for reversal (moving opposite direction)
    if (dx * prevDx < 0) or (dy * prevDy < 0) then
      reversals = reversals + 1
    end
    
    prevDx, prevDy = dx, dy
  end
  
  -- If more than 50% of movements are reversals, we're zigzagging
  return reversals >= (#history - 1) * 0.5
end

-- ============================================================================
-- SCENARIO-AWARE PRIORITY MODIFIER
-- ============================================================================

-- Apply scenario-based priority modifications
function Scenario.modifyPriority(creatureId, basePriority, creatureHealth)
  local cfg = Scenario.configs[Scenario.state.type] or Scenario.configs[Scenario.TYPES.FEW]
  local modifiedPriority = basePriority
  
  -- Target stickiness: Current target gets bonus
  if creatureId == Scenario.state.targetLockId then
    modifiedPriority = modifiedPriority + cfg.targetStickiness
    
    -- Extra bonus for low health targets (finish the kill!)
    if cfg.prioritizeFinishingKills and creatureHealth then
      if creatureHealth < 20 then
        modifiedPriority = modifiedPriority + 50  -- Huge bonus to finish
      elseif creatureHealth < 35 then
        modifiedPriority = modifiedPriority + 30
      elseif creatureHealth < 50 then
        modifiedPriority = modifiedPriority + 15
      end
    end
  end
  
  -- Swarm mode: Focus lowest health to reduce mob count
  if cfg.focusLowestHealth and creatureHealth then
    local healthBonus = (100 - creatureHealth) * 0.3
    modifiedPriority = modifiedPriority + healthBonus
  end
  
  -- Emergency mode: Prioritize closest high-damage monster
  if cfg.emergencyMode then
    -- Additional handling in emergency situations
    local trackerData = MonsterAI.Tracker and MonsterAI.Tracker.monsters[creatureId]
    if trackerData and trackerData.ewmaDps and trackerData.ewmaDps > 50 then
      modifiedPriority = modifiedPriority + 20
    end
  end
  
  return modifiedPriority
end

-- ============================================================================
-- OPTIMAL TARGET SELECTION
-- ============================================================================

-- Get the optimal target based on current scenario
function Scenario.getOptimalTarget()
  Scenario.detectScenario()
  
  local cfg = Scenario.configs[Scenario.state.type]
  local playerPos = player and player:getPosition()
  if not playerPos then return nil end
  
  local nowt = nowMs()
  local candidates = {}
  
  -- Check if current locked target is still valid
  if Scenario.state.targetLockId then
    local lockData = MonsterAI.Tracker and MonsterAI.Tracker.monsters[Scenario.state.targetLockId]
    if lockData and lockData.creature and not lockData.creature:isDead() then
      local lockedHealth = lockData.creature:getHealthPercent() or 100
      
      -- In FEW scenario with anti-zigzag, strongly prefer current target
      if Scenario.state.type == Scenario.TYPES.FEW then
        local timeLocked = nowt - Scenario.state.targetLockTime
        
        -- If we've been attacking for less than 5 seconds, or target is below 50% health
        if timeLocked < 5000 or lockedHealth < 50 then
          -- Keep current target unless it's at very high health
          if lockedHealth < 80 then
            return {
              creature = lockData.creature,
              id = Scenario.state.targetLockId,
              priority = 999,  -- Maximum priority for locked target
              reason = "target_locked"
            }
          end
        end
      end
    else
      -- Locked target died or invalid
      Scenario.clearTargetLock()
    end
  end
  
  -- Get all valid targets with priorities
  if MonsterAI.TargetBot and MonsterAI.TargetBot.getSortedTargets then
    candidates = MonsterAI.TargetBot.getSortedTargets({maxRange = 10})
  else
    -- Fallback to basic targeting
    local creatures = g_map.getSpectators(playerPos, false) or {}
    for _, creature in ipairs(creatures) do
      if creature and creature:isMonster() and not creature:isDead() then
        local pos = creature:getPosition()
        if pos and pos.z == playerPos.z then
          local dist = math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y))
          if dist <= 10 then
            table.insert(candidates, {
              creature = creature,
              id = creature:getId(),
              priority = 100 - dist + (100 - (creature:getHealthPercent() or 100)) * 0.5,
              distance = dist,
              name = creature:getName() or "unknown"
            })
          end
        end
      end
    end
    table.sort(candidates, function(a, b) return a.priority > b.priority end)
  end
  
  if #candidates == 0 then
    Scenario.clearTargetLock()
    return nil
  end
  
  -- Apply scenario-based priority modifications
  for _, candidate in ipairs(candidates) do
    local health = candidate.creature:getHealthPercent() or 100
    candidate.priority = Scenario.modifyPriority(candidate.id, candidate.priority, health)
  end
  
  -- Re-sort after modifications
  table.sort(candidates, function(a, b) return a.priority > b.priority end)
  
  local bestTarget = candidates[1]
  local bestHealth = bestTarget.creature:getHealthPercent() or 100
  
  -- Check if we should switch to this target
  local canSwitch, reason = Scenario.shouldAllowTargetSwitch(
    bestTarget.id, 
    bestTarget.priority, 
    bestHealth
  )
  
  if canSwitch then
    Scenario.lockTarget(bestTarget.id, bestHealth)
    bestTarget.reason = reason
    return bestTarget
  else
    -- Return current locked target instead
    local lockData = MonsterAI.Tracker and MonsterAI.Tracker.monsters[Scenario.state.targetLockId]
    if lockData and lockData.creature and not lockData.creature:isDead() then
      return {
        creature = lockData.creature,
        id = Scenario.state.targetLockId,
        priority = 999,
        reason = "switch_blocked:" .. reason
      }
    end
    
    -- Lock invalid, accept new target
    Scenario.lockTarget(bestTarget.id, bestHealth)
    return bestTarget
  end
end

-- ============================================================================
-- SCENARIO STATISTICS
-- ============================================================================

function Scenario.getStats()
  return {
    currentScenario = Scenario.state.type,
    monsterCount = Scenario.state.monsterCount,
    avgDangerLevel = Scenario.state.avgDangerLevel,
    targetLockId = Scenario.state.targetLockId,
    consecutiveSwitches = Scenario.state.consecutiveSwitches,
    isZigzagging = Scenario.isZigzagging(),
    clusterType = Scenario.state.clusterInfo and Scenario.state.clusterInfo.type or "none",
    config = Scenario.configs[Scenario.state.type] or {}
  }
end

-- ============================================================================
-- EVENTBUS INTEGRATION
-- ============================================================================

if EventBus and EventBus.on then
  -- Listen for target changes from TargetBot
  EventBus.on("targetbot:target_changed", function(creature, prevCreature)
    if creature then
      local health = creature:getHealthPercent() or 100
      Scenario.lockTarget(creature:getId(), health)
    else
      Scenario.clearTargetLock()
    end
  end)
  
  -- Listen for creature deaths
  EventBus.on("creature:death", function(creature)
    if creature and creature:getId() == Scenario.state.targetLockId then
      Scenario.clearTargetLock()
    end
  end)
end

-- Periodic scenario update
macro(500, function()
  if MonsterAI.COLLECT_ENABLED then
    pcall(function() Scenario.detectScenario() end)
  end
end)

-- ============================================================================
-- REACHABILITY MODULE v2.1
-- Smart detection of unreachable creatures to prevent "Creature not reachable"
-- Uses pathfinding, line-of-sight, and tile analysis
-- ============================================================================

MonsterAI.Reachability = MonsterAI.Reachability or {}
local Reachability = MonsterAI.Reachability

-- Cache for reachability checks (creature id -> result)
Reachability.cache = {}
Reachability.cacheTime = {}
Reachability.CACHE_TTL = 1500  -- ms before re-checking reachability
Reachability.BLOCKED_COOLDOWN = 5000  -- ms to remember blocked creatures

-- Blocked creature tracking (avoid repeated attack attempts)
Reachability.blockedCreatures = {}  -- id -> {blockedTime, attempts, reason}

-- Statistics
Reachability.stats = {
  checksPerformed = 0,
  cacheHits = 0,
  blocked = 0,
  reachable = 0,
  byReason = {
    no_path = 0,
    blocked_tile = 0,
    elevation = 0,
    too_far = 0,
    no_los = 0
  }
}

-- Direction offsets for path validation
local DIR_OFFSETS = {
  [0] = {x = 0, y = -1},   -- North
  [1] = {x = 1, y = 0},    -- East  
  [2] = {x = 0, y = 1},    -- South
  [3] = {x = -1, y = 0},   -- West
  [4] = {x = 1, y = -1},   -- NorthEast
  [5] = {x = 1, y = 1},    -- SouthEast
  [6] = {x = -1, y = 1},   -- SouthWest
  [7] = {x = -1, y = -1}   -- NorthWest
}

-- ============================================================================
-- CORE REACHABILITY CHECK
-- ============================================================================

-- Check if a creature is reachable from player position
-- Returns: isReachable, reason, path
function Reachability.isReachable(creature, forceRecheck)
  if not creature or creature:isDead() or creature:isRemoved() then
    return false, "invalid", nil
  end
  
  local id = creature:getId()
  local nowt = nowMs()
  
  -- Check cache first (unless forcing recheck)
  if not forceRecheck then
    local cachedResult = Reachability.cache[id]
    local cachedTime = Reachability.cacheTime[id] or 0
    
    if cachedResult ~= nil and (nowt - cachedTime) < Reachability.CACHE_TTL then
      Reachability.stats.cacheHits = Reachability.stats.cacheHits + 1
      return cachedResult.reachable, cachedResult.reason, cachedResult.path
    end
    
    -- Check if creature is in blocked list (recently failed)
    local blocked = Reachability.blockedCreatures[id]
    if blocked and (nowt - blocked.blockedTime) < Reachability.BLOCKED_COOLDOWN then
      -- Still in blocked cooldown - don't waste time rechecking
      if blocked.attempts < 3 then
        -- Allow a few retries
        blocked.attempts = blocked.attempts + 1
      else
        Reachability.stats.cacheHits = Reachability.stats.cacheHits + 1
        return false, blocked.reason, nil
      end
    end
  end
  
  Reachability.stats.checksPerformed = Reachability.stats.checksPerformed + 1
  
  local playerPos = player and player:getPosition()
  local creaturePos = creature:getPosition()
  
  if not playerPos or not creaturePos then
    return Reachability.cacheResult(id, false, "no_position", nil)
  end
  
  -- ─────────────────────────────────────────────────────────────────────
  -- CHECK 1: Same floor (elevation check)
  -- ─────────────────────────────────────────────────────────────────────
  if creaturePos.z ~= playerPos.z then
    Reachability.stats.byReason.elevation = Reachability.stats.byReason.elevation + 1
    return Reachability.cacheResult(id, false, "elevation", nil)
  end
  
  -- ─────────────────────────────────────────────────────────────────────
  -- CHECK 2: Distance check (basic range)
  -- ─────────────────────────────────────────────────────────────────────
  local dx = math.abs(creaturePos.x - playerPos.x)
  local dy = math.abs(creaturePos.y - playerPos.y)
  local dist = math.max(dx, dy)
  
  if dist > 15 then
    Reachability.stats.byReason.too_far = Reachability.stats.byReason.too_far + 1
    return Reachability.cacheResult(id, false, "too_far", nil)
  end
  
  -- ─────────────────────────────────────────────────────────────────────
  -- CHECK 3: Pathfinding (main reachability check)
  -- ─────────────────────────────────────────────────────────────────────
  local path = nil
  local pathParams = {
    ignoreCreatures = true,     -- Don't let other monsters block
    ignoreNonPathable = false,  -- Respect blocked tiles
    ignoreCost = true,          -- We just want to know if reachable
    precision = 1               -- We want to get adjacent to creature
  }
  
  -- Try to find path to creature
  local ok, result = pcall(function()
    return findPath(playerPos, creaturePos, 12, pathParams)
  end)
  
  if not ok or not result or #result == 0 then
    -- No path found - creature is blocked
    Reachability.stats.byReason.no_path = Reachability.stats.byReason.no_path + 1
    Reachability.markBlocked(id, "no_path")
    return Reachability.cacheResult(id, false, "no_path", nil)
  end
  
  path = result
  
  -- ─────────────────────────────────────────────────────────────────────
  -- CHECK 4: Path validation (verify first few tiles are walkable)
  -- ─────────────────────────────────────────────────────────────────────
  local pathLen = #path
  local checkCount = math.min(5, pathLen)
  local probe = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  
  for i = 1, checkCount do
    local dir = path[i]
    local offset = DIR_OFFSETS[dir]
    
    if offset then
      probe = {x = probe.x + offset.x, y = probe.y + offset.y, z = probe.z}
      
      local tile = g_map.getTile(probe)
      if tile then
        -- Check if tile is walkable
        local walkable = tile.isWalkable and tile:isWalkable()
        if not walkable then
          -- Path crosses a blocked tile
          Reachability.stats.byReason.blocked_tile = Reachability.stats.byReason.blocked_tile + 1
          Reachability.markBlocked(id, "blocked_tile")
          return Reachability.cacheResult(id, false, "blocked_tile", nil)
        end
        
        -- Check for blocking items (doors, walls, etc.)
        local items = tile.getItems and tile:getItems()
        if items then
          for _, item in ipairs(items) do
            local isBlocking = item.isNotWalkable and item:isNotWalkable()
            if isBlocking then
              Reachability.stats.byReason.blocked_tile = Reachability.stats.byReason.blocked_tile + 1
              Reachability.markBlocked(id, "blocked_tile")
              return Reachability.cacheResult(id, false, "blocked_tile", nil)
            end
          end
        end
      end
    end
  end
  
  -- ─────────────────────────────────────────────────────────────────────
  -- CHECK 5: Line of sight (for ranged attacks)
  -- ─────────────────────────────────────────────────────────────────────
  -- Note: We don't require LOS for melee, only for ranged
  -- This is a soft check - creature may still be reachable for melee
  local hasLOS = true
  if dist <= 7 then
    -- For close creatures, check if there's a clear line
    local ok2, los = pcall(function()
      -- Use Bresenham line check if available
      if g_map.isSightClear then
        return g_map.isSightClear(playerPos, creaturePos)
      end
      return true  -- Assume LOS if API not available
    end)
    
    if ok2 then
      hasLOS = los
    end
  end
  
  -- ─────────────────────────────────────────────────────────────────────
  -- RESULT: Creature is reachable
  -- ─────────────────────────────────────────────────────────────────────
  Reachability.stats.reachable = Reachability.stats.reachable + 1
  Reachability.clearBlocked(id)
  
  return Reachability.cacheResult(id, true, hasLOS and "clear" or "no_los_melee_ok", path)
end

-- ============================================================================
-- CACHE MANAGEMENT
-- ============================================================================

function Reachability.cacheResult(id, reachable, reason, path)
  Reachability.cache[id] = {
    reachable = reachable,
    reason = reason,
    path = path
  }
  Reachability.cacheTime[id] = nowMs()
  
  if not reachable then
    Reachability.stats.blocked = Reachability.stats.blocked + 1
  end
  
  return reachable, reason, path
end

function Reachability.markBlocked(id, reason)
  local existing = Reachability.blockedCreatures[id]
  if existing then
    existing.attempts = existing.attempts + 1
    existing.reason = reason
  else
    Reachability.blockedCreatures[id] = {
      blockedTime = nowMs(),
      attempts = 1,
      reason = reason
    }
  end
end

function Reachability.clearBlocked(id)
  Reachability.blockedCreatures[id] = nil
end

function Reachability.clearCache()
  Reachability.cache = {}
  Reachability.cacheTime = {}
end

-- Cleanup old blocked entries
function Reachability.cleanup()
  local nowt = nowMs()
  local expiry = Reachability.BLOCKED_COOLDOWN * 2
  
  for id, data in pairs(Reachability.blockedCreatures) do
    if (nowt - data.blockedTime) > expiry then
      Reachability.blockedCreatures[id] = nil
    end
  end
  
  -- Also cleanup old cache entries
  for id, time in pairs(Reachability.cacheTime) do
    if (nowt - time) > Reachability.CACHE_TTL * 3 then
      Reachability.cache[id] = nil
      Reachability.cacheTime[id] = nil
    end
  end
end

-- ============================================================================
-- BATCH OPERATIONS
-- ============================================================================

-- Filter a list of creatures to only reachable ones
function Reachability.filterReachable(creatures)
  local reachable = {}
  local unreachable = {}
  
  for _, creature in ipairs(creatures) do
    local isReach, reason = Reachability.isReachable(creature)
    if isReach then
      table.insert(reachable, creature)
    else
      table.insert(unreachable, {creature = creature, reason = reason})
    end
  end
  
  return reachable, unreachable
end

-- Get cached path for a creature (if available)
function Reachability.getCachedPath(creatureId)
  local cached = Reachability.cache[creatureId]
  return cached and cached.path or nil
end

-- Check if creature is in blocked list
function Reachability.isBlocked(creatureId)
  local blocked = Reachability.blockedCreatures[creatureId]
  if not blocked then return false end
  
  local nowt = nowMs()
  if (nowt - blocked.blockedTime) > Reachability.BLOCKED_COOLDOWN then
    -- Expired
    Reachability.blockedCreatures[creatureId] = nil
    return false
  end
  
  return true, blocked.reason, blocked.attempts
end

-- ============================================================================
-- STATISTICS
-- ============================================================================

function Reachability.getStats()
  return {
    checksPerformed = Reachability.stats.checksPerformed,
    cacheHits = Reachability.stats.cacheHits,
    blocked = Reachability.stats.blocked,
    reachable = Reachability.stats.reachable,
    byReason = Reachability.stats.byReason,
    blockedCount = (function()
      local count = 0
      for _ in pairs(Reachability.blockedCreatures) do count = count + 1 end
      return count
    end)(),
    cacheSize = (function()
      local count = 0
      for _ in pairs(Reachability.cache) do count = count + 1 end
      return count
    end)()
  }
end

-- ============================================================================
-- INTEGRATION WITH TARGETING
-- ============================================================================

-- Hook for target validation before attack
function Reachability.validateTarget(creature)
  if not creature then return false, "no_creature" end
  
  local isReach, reason, path = Reachability.isReachable(creature)
  
  if not isReach then
    -- Emit event for debugging/monitoring
    if EventBus and EventBus.emit then
      EventBus.emit("reachability:blocked", creature, reason)
    end
    return false, reason
  end
  
  return true, reason, path
end

-- Periodic cleanup
macro(10000, function()
  pcall(function() Reachability.cleanup() end)
end)

-- EventBus integration
if EventBus and EventBus.on then
  -- Clear cache when player moves significantly
  EventBus.on("player:position", function(newPos, oldPos)
    if newPos and oldPos then
      local dx = math.abs(newPos.x - oldPos.x)
      local dy = math.abs(newPos.y - oldPos.y)
      if dx > 2 or dy > 2 then
        -- Player moved significantly, clear cache
        Reachability.clearCache()
      end
    end
  end)
  
  -- Clear blocked status when creature moves
  EventBus.on("creature:move", function(creature, oldPos, newPos)
    if creature and creature:isMonster() then
      local id = creature:getId()
      if Reachability.blockedCreatures[id] then
        -- Creature moved, might be reachable now
        Reachability.clearBlocked(id)
        Reachability.cache[id] = nil
        Reachability.cacheTime[id] = nil
      end
    end
  end)
end

-- ============================================================================
-- TARGETBOT INTEGRATION MODULE v2.0
-- Provides enhanced targeting functions for 30%+ accuracy improvement
-- ============================================================================

MonsterAI.TargetBot = MonsterAI.TargetBot or {}
local TBI = MonsterAI.TargetBot

-- Integration configuration
TBI.config = {
  -- Weighting multipliers for priority calculation
  baseWeight = 1.0,
  distanceWeight = 0.8,
  healthWeight = 0.7,
  dangerWeight = 1.5,
  waveWeight = 2.0,
  imminentWeight = 3.0,
  
  -- Thresholds
  imminentThresholdMs = 600,     -- Attack is imminent if within this time
  dangerousCooldownRatio = 0.7,  -- Monster is dangerous if cooldown > this ratio
  lowHealthThreshold = 30,       -- % health to consider low
  criticalHealthThreshold = 15,  -- % health to consider critical
  
  -- Distance scoring
  meleeRange = 1,
  closeRange = 3,
  mediumRange = 6,
  
  -- Speed-based adjustments
  fastMonsterThreshold = 250,    -- Speed above this = fast monster
  slowMonsterThreshold = 100,    -- Speed below this = slow monster
}

-- ============================================================================
-- ENHANCED PRIORITY CALCULATION
-- ============================================================================

-- Calculate comprehensive priority score for a monster
function TBI.calculatePriority(creature, options)
  if not creature or creature:isDead() or creature:isRemoved() then
    return 0, {}
  end
  
  options = options or {}
  local cfg = TBI.config
  local breakdown = {} -- For debugging
  
  local creatureId = creature:getId()
  local creatureName = creature:getName() or "unknown"
  local creaturePos = creature:getPosition()
  local playerPos = player and player:getPosition()
  
  if not playerPos or not creaturePos then
    return 0, breakdown
  end
  
  -- Base score
  local priority = 100 * cfg.baseWeight
  breakdown.base = priority
  
  -- ============================================================================
  -- 1. DISTANCE SCORING (closer = higher priority)
  -- ============================================================================
  local dx = math.abs(creaturePos.x - playerPos.x)
  local dy = math.abs(creaturePos.y - playerPos.y)
  local distance = math.max(dx, dy)
  
  local distanceScore = 0
  if distance <= cfg.meleeRange then
    distanceScore = 50  -- Very high priority for melee range
  elseif distance <= cfg.closeRange then
    distanceScore = 35  -- High priority for close range
  elseif distance <= cfg.mediumRange then
    distanceScore = 20  -- Medium priority
  else
    distanceScore = math.max(0, 15 - (distance - cfg.mediumRange) * 2)
  end
  distanceScore = distanceScore * cfg.distanceWeight
  priority = priority + distanceScore
  breakdown.distance = distanceScore
  
  -- ============================================================================
  -- 2. HEALTH SCORING (lower health = slightly higher priority)
  -- ============================================================================
  local healthPct = creature:getHealthPercent() or 100
  local healthScore = 0
  
  if healthPct <= cfg.criticalHealthThreshold then
    healthScore = 30  -- Very low health, finish it off
  elseif healthPct <= cfg.lowHealthThreshold then
    healthScore = 20  -- Low health
  elseif healthPct <= 50 then
    healthScore = 10  -- Medium health
  else
    healthScore = 0   -- Full health, no bonus
  end
  healthScore = healthScore * cfg.healthWeight
  priority = priority + healthScore
  breakdown.health = healthScore
  
  -- ============================================================================
  -- 3. MONSTER AI TRACKER DATA
  -- ============================================================================
  local trackerData = MonsterAI.Tracker and MonsterAI.Tracker.monsters[creatureId]
  local trackerScore = 0
  
  if trackerData then
    -- a) DPS-based priority
    local ewmaDps = trackerData.ewmaDps or 0
    if ewmaDps >= 80 then
      trackerScore = trackerScore + 40  -- Critical DPS
    elseif ewmaDps >= 40 then
      trackerScore = trackerScore + 25  -- High DPS
    elseif ewmaDps >= 20 then
      trackerScore = trackerScore + 10  -- Medium DPS
    end
    breakdown.dps = ewmaDps
    
    -- b) Hit count (more hits = more aggressive)
    local hitCount = trackerData.hitCount or 0
    if hitCount >= 10 then
      trackerScore = trackerScore + 15
    elseif hitCount >= 5 then
      trackerScore = trackerScore + 8
    elseif hitCount >= 2 then
      trackerScore = trackerScore + 3
    end
    
    -- c) Recent damage attribution
    local recentDamage = trackerData.recentDamage or 0
    if recentDamage > 0 then
      local damageBonus = math.min(30, recentDamage / 5)
      trackerScore = trackerScore + damageBonus
      breakdown.recentDamage = recentDamage
    end
    
    -- d) Wave attack tracking
    local waveCount = trackerData.waveCount or 0
    if waveCount >= 3 then
      trackerScore = trackerScore + 20  -- Confirmed wave attacker
    elseif waveCount >= 1 then
      trackerScore = trackerScore + 10
    end
    
    -- e) Last attack time (recently attacked = higher threat)
    local lastAttack = trackerData.lastAttackTime or trackerData.firstSeen or 0
    local timeSinceAttack = nowMs() - lastAttack
    if timeSinceAttack < 2000 then
      trackerScore = trackerScore + 20  -- Very recent attack
    elseif timeSinceAttack < 5000 then
      trackerScore = trackerScore + 10  -- Recent attack
    end
  end
  
  trackerScore = trackerScore * cfg.dangerWeight
  priority = priority + trackerScore
  breakdown.tracker = trackerScore
  
  -- ============================================================================
  -- 4. WAVE PREDICTION SCORING
  -- ============================================================================
  local waveScore = 0
  local waveData = nil
  
  if MonsterAI.RealTime and MonsterAI.RealTime.directions then
    local rtData = MonsterAI.RealTime.directions[creatureId]
    if rtData then
      waveData = rtData
      
      -- Get pattern data
      local pattern = MonsterAI.Patterns and MonsterAI.Patterns.get(creatureName) or {}
      local waveCooldown = pattern.waveCooldown or 2000
      
      -- Calculate cooldown status
      local lastWave = trackerData and (trackerData.lastWaveTime or trackerData.lastAttackTime) or 0
      local elapsed = nowMs() - lastWave
      local cooldownRemaining = math.max(0, waveCooldown - elapsed)
      local cooldownRatio = elapsed / waveCooldown
      
      -- Imminent wave attack
      if cooldownRemaining <= cfg.imminentThresholdMs and cooldownRatio >= cfg.dangerousCooldownRatio then
        waveScore = 60 * cfg.imminentWeight  -- Maximum priority for imminent attack
        breakdown.imminent = true
      elseif cooldownRemaining <= 1500 then
        waveScore = 40 * cfg.waveWeight  -- High priority
      elseif cooldownRemaining <= 2500 then
        waveScore = 20 * cfg.waveWeight  -- Medium priority
      end
      
      -- Direction-based bonus (facing player)
      if rtData.dir and playerPos then
        local facingPlayer = TBI.isCreatureFacingPosition(creaturePos, rtData.dir, playerPos)
        if facingPlayer then
          waveScore = waveScore + 15
          breakdown.facing = true
        end
        
        -- In wave path bonus
        local inWavePath = MonsterAI.Predictor and MonsterAI.Predictor.isPositionInWavePath(
          playerPos, creaturePos, rtData.dir, pattern.waveRange or 5, pattern.waveWidth or 3
        )
        if inWavePath then
          waveScore = waveScore + 25
          breakdown.inWavePath = true
        end
      end
    end
  end
  
  priority = priority + waveScore
  breakdown.wave = waveScore
  
  -- ============================================================================
  -- 5. MONSTER CLASSIFICATION SCORING
  -- ============================================================================
  local classScore = 0
  
  if MonsterAI.Classifier then
    local classification = MonsterAI.Classifier.classify(creatureName)
    if classification then
      if classification.dangerLevel == "critical" then
        classScore = 50
      elseif classification.dangerLevel == "high" then
        classScore = 30
      elseif classification.dangerLevel == "medium" then
        classScore = 15
      end
      
      if classification.isWaveCaster then
        classScore = classScore + 20
      end
      if classification.isRanged then
        classScore = classScore + 10  -- Range monsters can't be ignored
      end
      
      breakdown.classification = classification.dangerLevel
    end
  end
  
  priority = priority + classScore
  breakdown.class = classScore
  
  -- ============================================================================
  -- 6. MOVEMENT/TRAJECTORY SCORING
  -- ============================================================================
  local movementScore = 0
  
  if creature.isWalking and creature:isWalking() then
    local walkDir = creature.getWalkDirection and creature:getWalkDirection()
    if walkDir then
      -- Check if approaching player
      local predictedPos = TBI.predictPosition(creaturePos, walkDir, 1)
      if predictedPos then
        local currentDist = distance
        local futureDist = math.max(
          math.abs(predictedPos.x - playerPos.x),
          math.abs(predictedPos.y - playerPos.y)
        )
        
        if futureDist < currentDist then
          movementScore = 15  -- Approaching
          breakdown.approaching = true
        elseif futureDist > currentDist then
          movementScore = -5  -- Fleeing (slightly lower priority)
          breakdown.fleeing = true
        end
      end
    end
    
    -- Fast monsters are more dangerous
    local speed = creature.getSpeed and creature:getSpeed() or 100
    if speed >= cfg.fastMonsterThreshold then
      movementScore = movementScore + 10
      breakdown.fast = true
    end
  end
  
  priority = priority + movementScore
  breakdown.movement = movementScore
  
  -- ============================================================================
  -- 7. ADAPTIVE WEIGHTS FROM COMBAT FEEDBACK
  -- ============================================================================
  local feedbackScore = 0
  
  if MonsterAI.CombatFeedback and MonsterAI.CombatFeedback.getWeights then
    local weights = MonsterAI.CombatFeedback.getWeights(creatureName)
    if weights then
      -- Apply adaptive multiplier to the entire score
      local adaptiveMultiplier = weights.overall or 1.0
      priority = priority * adaptiveMultiplier
      
      -- Add specific bonuses based on learned weights
      if weights.wave and weights.wave > 1.1 then
        feedbackScore = feedbackScore + 15  -- Historically waves more
      end
      if weights.melee and weights.melee > 1.1 then
        feedbackScore = feedbackScore + 10  -- Historically more melee damage
      end
      
      breakdown.adaptiveMultiplier = adaptiveMultiplier
    end
  end
  
  priority = priority + feedbackScore
  breakdown.feedback = feedbackScore
  
  -- ============================================================================
  -- 8. TELEMETRY BONUSES
  -- ============================================================================
  local telemetryScore = 0
  
  if MonsterAI.Telemetry and MonsterAI.Telemetry.get then
    local telemetry = MonsterAI.Telemetry.get(creatureId)
    if telemetry then
      -- Variance in damage (unpredictable monsters)
      local damageVariance = telemetry.damageVariance or 0
      if damageVariance > 50 then
        telemetryScore = telemetryScore + 10  -- Unpredictable damage
      end
      
      -- Step speed consistency
      local stepConsistency = telemetry.stepConsistency or 0
      if stepConsistency < 0.5 then
        telemetryScore = telemetryScore + 5  -- Erratic movement
      end
      
      breakdown.telemetryVariance = damageVariance
    end
  end
  
  priority = priority + telemetryScore
  breakdown.telemetry = telemetryScore
  
  -- ============================================================================
  -- 9. FINAL ADJUSTMENTS
  -- ============================================================================
  
  -- Clamp priority to reasonable range
  priority = math.max(0, math.min(1000, priority))
  breakdown.final = priority
  
  return priority, breakdown
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Check if a creature is facing a specific position
function TBI.isCreatureFacingPosition(creaturePos, direction, targetPos)
  if not creaturePos or not direction or not targetPos then
    return false
  end
  
  local dx = targetPos.x - creaturePos.x
  local dy = targetPos.y - creaturePos.y
  
  -- Direction enum: 0=North, 1=East, 2=South, 3=West (typically)
  if direction == 0 then      -- North
    return dy < 0 and math.abs(dx) <= math.abs(dy)
  elseif direction == 1 then  -- East
    return dx > 0 and math.abs(dy) <= math.abs(dx)
  elseif direction == 2 then  -- South
    return dy > 0 and math.abs(dx) <= math.abs(dy)
  elseif direction == 3 then  -- West
    return dx < 0 and math.abs(dy) <= math.abs(dx)
  end
  
  return false
end

-- Predict position after N steps in a direction
function TBI.predictPosition(pos, direction, steps)
  if not pos or not direction then return nil end
  
  steps = steps or 1
  local dx, dy = 0, 0
  
  if direction == 0 then      -- North
    dy = -steps
  elseif direction == 1 then  -- East
    dx = steps
  elseif direction == 2 then  -- South
    dy = steps
  elseif direction == 3 then  -- West
    dx = -steps
  elseif direction == 4 then  -- NorthEast
    dx, dy = steps, -steps
  elseif direction == 5 then  -- SouthEast
    dx, dy = steps, steps
  elseif direction == 6 then  -- SouthWest
    dx, dy = -steps, steps
  elseif direction == 7 then  -- NorthWest
    dx, dy = -steps, -steps
  end
  
  return {x = pos.x + dx, y = pos.y + dy, z = pos.z}
end

-- ============================================================================
-- GET SORTED TARGETS (replacement for basic targeting)
-- ============================================================================

-- Get all valid targets sorted by priority
function TBI.getSortedTargets(options)
  options = options or {}
  local targets = {}
  
  local playerPos = player and player:getPosition()
  if not playerPos then return targets end
  
  local maxRange = options.maxRange or 10
  
  -- Get all creatures on screen
  local creatures = g_map.getSpectators(playerPos, false) or {}
  
  for _, creature in ipairs(creatures) do
    if creature and creature:isMonster() and not creature:isDead() and not creature:isRemoved() then
      local creaturePos = creature:getPosition()
      if creaturePos and creaturePos.z == playerPos.z then
        local dx = math.abs(creaturePos.x - playerPos.x)
        local dy = math.abs(creaturePos.y - playerPos.y)
        local dist = math.max(dx, dy)
        
        if dist <= maxRange then
          local priority, breakdown = TBI.calculatePriority(creature, options)
          
          table.insert(targets, {
            creature = creature,
            priority = priority,
            distance = dist,
            breakdown = breakdown,
            id = creature:getId(),
            name = creature:getName()
          })
        end
      end
    end
  end
  
  -- Sort by priority (highest first)
  table.sort(targets, function(a, b) return a.priority > b.priority end)
  
  return targets
end

-- Get the single best target
function TBI.getBestTarget(options)
  local targets = TBI.getSortedTargets(options)
  return targets[1]
end

-- ============================================================================
-- DANGER ASSESSMENT
-- ============================================================================

-- Get overall danger level for current situation
function TBI.getDangerLevel()
  local playerPos = player and player:getPosition()
  if not playerPos then return 0, {} end
  
  local dangerLevel = 0
  local threats = {}
  
  local targets = TBI.getSortedTargets({maxRange = 8})
  
  for _, target in ipairs(targets) do
    local threatLevel = target.priority / 200  -- Normalize to 0-5 scale
    dangerLevel = dangerLevel + threatLevel
    
    if threatLevel >= 1.0 then
      table.insert(threats, {
        name = target.name,
        level = threatLevel,
        imminent = target.breakdown and target.breakdown.imminent
      })
    end
  end
  
  return math.min(10, dangerLevel), threats
end

-- ============================================================================
-- STATISTICS AND DEBUGGING
-- ============================================================================

function TBI.getStats()
  local stats = {
    config = TBI.config,
    feedbackActive = MonsterAI.CombatFeedback ~= nil,
    trackerActive = MonsterAI.Tracker ~= nil,
    realTimeActive = MonsterAI.RealTime ~= nil
  }
  
  if MonsterAI.CombatFeedback and MonsterAI.CombatFeedback.getStats then
    stats.feedback = MonsterAI.CombatFeedback.getStats()
  end
  
  return stats
end

-- Debug print for a specific creature's priority breakdown
function TBI.debugCreature(creature)
  if not creature then
    print("[TBI] No creature specified")
    return
  end
  
  local priority, breakdown = TBI.calculatePriority(creature)
  
  print("[TBI] Priority breakdown for " .. (creature:getName() or "unknown") .. ":")
  print("  Final Priority: " .. priority)
  for key, value in pairs(breakdown) do
    print("  " .. key .. ": " .. tostring(value))
  end
end

-- ============================================================================
-- EVENTBUS INTEGRATION
-- ============================================================================

if EventBus and EventBus.on then
  -- Listen for target requests
  EventBus.on("targetbot:request_priority", function(creature, callback)
    if creature and callback then
      local priority, breakdown = TBI.calculatePriority(creature)
      callback(priority, breakdown)
    end
  end)
  
  -- Emit best target updates periodically
  schedule(2000, function()
    local function emitBestTarget()
      if EventBus and EventBus.emit then
        local best = TBI.getBestTarget()
        if best then
          EventBus.emit("targetbot:ai_recommendation", best.creature, best.priority, best.breakdown)
        end
      end
      schedule(1000, emitBestTarget)  -- Every second
    end
    emitBestTarget()
  end)
end

-- Toggle to enable debug prints
MonsterAI.DEBUG = MonsterAI.DEBUG or false
local SpectatorCache = SpectatorCache or (type(require) == 'function' and (function() local ok, mod = pcall(require, "utils.spectator_cache"); if ok then return mod end; return nil end)() or nil)
if MonsterAI.DEBUG then print("[MonsterAI] Monster AI Analysis Module v" .. MonsterAI.VERSION .. " loaded; automatic collection=" .. tostring(MonsterAI.COLLECT_ENABLED) .. "; auto-tune=" .. tostring(MonsterAI.AUTO_TUNE_ENABLED)) end
