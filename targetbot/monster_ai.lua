--[[
  Monster AI Analysis Module v2.2
  
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
  - Spell/missile tracking and analysis (NEW in v2.2)
  - Volume-based reactivity adaptation (NEW in v2.2)
  - Centralized metrics aggregation (NEW in v2.2)
  
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
  - MonsterAI.SpellTracker: Monster spell/missile analysis (NEW in v2.2)
  - MonsterAI.VolumeAdaptation: Dynamic reactivity tuning (NEW in v2.2)
  - MonsterAI.Metrics: Centralized metrics aggregator (NEW in v2.2)
]]

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

MonsterAI = MonsterAI or {}
MonsterAI.VERSION = "2.2"

--------------------------------------------------------------------------------
-- CLIENTSERVICE HELPERS (cross-client compatibility)
--------------------------------------------------------------------------------
local function getClient()
  return ClientService
end

local function getClientVersion()
  local Client = getClient()
  return (Client and Client.getClientVersion) and Client.getClientVersion() or (g_game and g_game.getClientVersion and g_game.getClientVersion()) or 1200
end

-- Time helper (milliseconds). Prefer existing global 'now' if available, else use g_clock.millis or os.time()*1000
local function nowMs()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

-- ============================================================================
-- SAFE CREATURE VALIDATION (Prevents C++ crashes)
-- The OTClient C++ layer can crash even when methods exist if the creature
-- object is in an invalid internal state. These helpers prevent that.
-- ============================================================================

-- Cache for recently validated creatures to reduce overhead
local validatedCreatures = {}
local validatedCreaturesTTL = 100 -- ms

-- Check if a creature is valid and safe to call methods on
-- Returns true only if the creature can be safely accessed
local function isCreatureValid(creature)
  if not creature then return false end
  if type(creature) ~= "userdata" and type(creature) ~= "table" then return false end
  
  -- Try the most basic operation possible - if this fails, creature is invalid
  local ok, id = pcall(function() return creature:getId() end)
  if not ok or not id then return false end
  
  -- Check validation cache
  local nowt = nowMs()
  local cached = validatedCreatures[id]
  if cached and (nowt - cached.time) < validatedCreaturesTTL then
    return cached.valid
  end
  
  -- Perform full validation - try to access position (critical method)
  local okPos, pos = pcall(function() return creature:getPosition() end)
  local valid = okPos and pos ~= nil
  
  -- Cache result
  validatedCreatures[id] = { valid = valid, time = nowt }
  
  -- Cleanup old cache entries periodically
  if math.random(1, 50) == 1 then
    for cid, data in pairs(validatedCreatures) do
      if (nowt - data.time) > validatedCreaturesTTL * 10 then
        validatedCreatures[cid] = nil
      end
    end
  end
  
  return valid
end

-- Safely call a method on a creature, returning default if it fails
-- This wraps the entire call including method lookup in pcall
local function safeCreatureCall(creature, methodName, default)
  if not creature then return default end
  
  local ok, result = pcall(function()
    local method = creature[methodName]
    if not method then return nil end
    return method(creature)
  end)
  
  if ok then
    return result ~= nil and result or default
  else
    return default
  end
end

-- Safely get creature ID (most common operation)
local function safeGetId(creature)
  if not creature then return nil end
  local ok, id = pcall(function() return creature:getId() end)
  return ok and id or nil
end

-- Safely check if creature is dead
local function safeIsDead(creature)
  if not creature then return true end
  local ok, dead = pcall(function() return creature:isDead() end)
  return ok and dead or true
end

-- Safely check if creature is a monster
local function safeIsMonster(creature)
  if not creature then return false end
  local ok, monster = pcall(function() return creature:isMonster() end)
  return ok and monster or false
end

-- Safely check if creature is removed
local function safeIsRemoved(creature)
  if not creature then return true end
  local ok, removed = pcall(function() return creature:isRemoved() end)
  if not ok then return true end
  return removed or false
end

-- Combined safe check: is the creature a valid, alive monster?
local function isValidAliveMonster(creature)
  if not creature then return false end
  
  local ok, result = pcall(function()
    return creature:isMonster() and not creature:isDead() and not creature:isRemoved()
  end)
  
  return ok and result or false
end

-- Extended telemetry defaults
MonsterAI.COLLECT_EXTENDED = (MonsterAI.COLLECT_EXTENDED == nil) and true or MonsterAI.COLLECT_EXTENDED
MonsterAI.DPS_WINDOW = MonsterAI.DPS_WINDOW or 5000 -- ms window for DPS calculation
MonsterAI.AUTO_TUNE_ENABLED = (MonsterAI.AUTO_TUNE_ENABLED == nil) and true or MonsterAI.AUTO_TUNE_ENABLED
MonsterAI.TELEMETRY_INTERVAL = MonsterAI.TELEMETRY_INTERVAL or 200 -- ms between telemetry samples

-- ============================================================================
-- VOLUME ADAPTATION MODULE (NEW in v2.2)
-- Automatically adjusts processing parameters based on monster count
-- Optimizes CPU usage while maintaining responsiveness
-- ============================================================================

MonsterAI.VolumeAdaptation = MonsterAI.VolumeAdaptation or {
  -- Current adaptation state
  currentVolume = "normal",  -- "low", "normal", "high", "extreme"
  lastVolumeChange = 0,
  
  -- Volume thresholds
  THRESHOLDS = {
    LOW = 2,       -- 1-2 monsters = low volume
    NORMAL = 5,    -- 3-5 monsters = normal
    HIGH = 10,     -- 6-10 monsters = high
    EXTREME = 15   -- 11+ monsters = extreme
  },
  
  -- Adaptation parameters per volume level
  PARAMS = {
    low = {
      description = "Few monsters - high precision mode",
      telemetryInterval = 100,      -- ms (more frequent sampling)
      threatCacheTTL = 50,          -- ms (fresher cache)
      updatePriority = "precision", -- Focus on accuracy
      ewmaAlpha = 0.35,             -- More responsive EWMA
      minSamplesForPrediction = 3,
      maxTrackedPerCycle = 10
    },
    normal = {
      description = "Normal load - balanced mode",
      telemetryInterval = 200,
      threatCacheTTL = 100,
      updatePriority = "balanced",
      ewmaAlpha = 0.25,
      minSamplesForPrediction = 5,
      maxTrackedPerCycle = 8
    },
    high = {
      description = "Many monsters - efficiency mode",
      telemetryInterval = 350,
      threatCacheTTL = 150,
      updatePriority = "efficiency",
      ewmaAlpha = 0.20,
      minSamplesForPrediction = 7,
      maxTrackedPerCycle = 6
    },
    extreme = {
      description = "Overload - survival mode",
      telemetryInterval = 500,
      threatCacheTTL = 200,
      updatePriority = "survival",
      ewmaAlpha = 0.15,             -- Smoother, less CPU
      minSamplesForPrediction = 10,
      maxTrackedPerCycle = 4        -- Process fewer per cycle
    }
  },
  
  -- Performance metrics
  metrics = {
    volumeChanges = 0,
    avgMonsterCount = 0,
    peakMonsterCount = 0,
    adaptationsSaved = 0   -- Estimated CPU cycles saved
  }
}

-- Determine volume level from monster count
function MonsterAI.VolumeAdaptation.getVolumeLevel(monsterCount)
  local th = MonsterAI.VolumeAdaptation.THRESHOLDS
  if monsterCount <= th.LOW then
    return "low"
  elseif monsterCount <= th.NORMAL then
    return "normal"
  elseif monsterCount <= th.HIGH then
    return "high"
  else
    return "extreme"
  end
end

-- Get current adaptation parameters
function MonsterAI.VolumeAdaptation.getParams()
  local volume = MonsterAI.VolumeAdaptation.currentVolume
  return MonsterAI.VolumeAdaptation.PARAMS[volume] or MonsterAI.VolumeAdaptation.PARAMS.normal
end

-- Update volume state based on current monster count
function MonsterAI.VolumeAdaptation.update()
  local va = MonsterAI.VolumeAdaptation
  local nowt = nowMs()
  
  -- Count currently tracked monsters
  local monsterCount = 0
  if MonsterAI.Tracker and MonsterAI.Tracker.monsters then
    for _ in pairs(MonsterAI.Tracker.monsters) do
      monsterCount = monsterCount + 1
    end
  end
  
  -- Update metrics
  va.metrics.avgMonsterCount = (va.metrics.avgMonsterCount or 0) * 0.95 + monsterCount * 0.05
  if monsterCount > (va.metrics.peakMonsterCount or 0) then
    va.metrics.peakMonsterCount = monsterCount
  end
  
  -- Determine new volume level
  local newVolume = va.getVolumeLevel(monsterCount)
  
  -- Apply hysteresis to prevent rapid switching
  -- Only change if we've been in current state for at least 500ms
  if newVolume ~= va.currentVolume then
    if (nowt - (va.lastVolumeChange or 0)) > 500 then
      local oldVolume = va.currentVolume
      va.currentVolume = newVolume
      va.lastVolumeChange = nowt
      va.metrics.volumeChanges = (va.metrics.volumeChanges or 0) + 1
      
      -- Apply new parameters
      local params = va.PARAMS[newVolume]
      if params then
        -- Update global settings
        MonsterAI.TELEMETRY_INTERVAL = params.telemetryInterval
        
        -- Update EWMA alpha in constants
        if MonsterAI.CONSTANTS and MonsterAI.CONSTANTS.EWMA then
          MonsterAI.CONSTANTS.EWMA.ALPHA_DEFAULT = params.ewmaAlpha
        end
        
        -- Update threat cache TTL
        if MonsterAI.CONSTANTS and MonsterAI.CONSTANTS.EVENT_DRIVEN then
          MonsterAI.CONSTANTS.EVENT_DRIVEN.THREAT_CACHE_TTL = params.threatCacheTTL
        end
      end
      
      -- Emit volume change event
      if EventBus and EventBus.emit then
        EventBus.emit("monsterai:volume_changed", {
          oldVolume = oldVolume,
          newVolume = newVolume,
          monsterCount = monsterCount,
          params = params
        })
      end
      
      if MonsterAI.DEBUG then
        print(string.format("[MonsterAI] Volume adapted: %s -> %s (%d monsters) - %s",
          oldVolume, newVolume, monsterCount, params and params.description or ""))
      end
    end
  end
  
  return va.currentVolume, va.getParams()
end

-- Check if we should process this monster in current cycle (load balancing)
function MonsterAI.VolumeAdaptation.shouldProcessMonster(monsterId)
  local va = MonsterAI.VolumeAdaptation
  local params = va.getParams()
  
  -- In low/normal volume, always process
  if va.currentVolume == "low" or va.currentVolume == "normal" then
    return true
  end
  
  -- In high/extreme, use round-robin based on monster ID
  -- This distributes processing across multiple cycles
  local cycleNumber = math.floor(nowMs() / 100) -- 100ms cycles
  local hash = monsterId % (params.maxTrackedPerCycle * 2)
  local slot = cycleNumber % (params.maxTrackedPerCycle * 2)
  
  return hash <= slot and hash > (slot - params.maxTrackedPerCycle)
end

-- Get volume adaptation stats for UI
function MonsterAI.VolumeAdaptation.getStats()
  local va = MonsterAI.VolumeAdaptation
  return {
    currentVolume = va.currentVolume,
    params = va.getParams(),
    metrics = va.metrics
  }
end

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
-- Use the module-level safeCreatureCall helper for all method calls
function MonsterAI.Telemetry.collectSnapshot(creature)
  if not creature then return nil end
  
  -- Validate creature before any operations
  if not isCreatureValid(creature) then return nil end
  
  local id = safeGetId(creature)
  if not id then return nil end
  
  local nowt = nowMs()
  local snapshot = {
    timestamp = nowt,
    
    -- Basic creature info
    id = id,
    name = safeCreatureCall(creature, "getName", "Unknown"),
    healthPercent = safeCreatureCall(creature, "getHealthPercent", 100),
    
    -- Position and movement (OTClient API)
    position = safeCreatureCall(creature, "getPosition", nil),
    direction = safeCreatureCall(creature, "getDirection", 0),
    isWalking = safeCreatureCall(creature, "isWalking", false),
    
    -- Speed telemetry (OTClient API)
    speed = safeCreatureCall(creature, "getSpeed", 0),
    baseSpeed = safeCreatureCall(creature, "getBaseSpeed", 0),
    
    -- Walk timing (OTClient API) - These can fail on some creatures
    stepDuration = safeCreatureCall(creature, "getStepDuration", 0),
    stepProgress = safeCreatureCall(creature, "getStepProgress", 0),
    stepTicksLeft = safeCreatureCall(creature, "getStepTicksLeft", 0),
    walkTicksElapsed = safeCreatureCall(creature, "getWalkTicksElapsed", 0),
    
    -- Walk direction (can differ from facing direction)
    walkDirection = safeCreatureCall(creature, "getWalkDirection", nil) or safeCreatureCall(creature, "getDirection", 0),
    
    -- State flags
    isDead = safeCreatureCall(creature, "isDead", false),
    isRemoved = safeCreatureCall(creature, "isRemoved", false),
    isInvisible = safeCreatureCall(creature, "isInvisible", false),
    
    -- Creature type classification (OTClient API)
    creatureType = safeCreatureCall(creature, "getType", 0),
    skull = safeCreatureCall(creature, "getSkull", 0),
    shield = safeCreatureCall(creature, "getShield", 0),
    icon = safeCreatureCall(creature, "getIcon", 0),
    
    -- Outfit info (can indicate monster variant)
    outfit = safeCreatureCall(creature, "getOutfit", nil),
    
    -- Step history for trajectory prediction
    lastStepFrom = safeCreatureCall(creature, "getLastStepFromPosition", nil),
    lastStepTo = safeCreatureCall(creature, "getLastStepToPosition", nil),
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- ENHANCED METRICS (NEW in v2.2)
    -- ═══════════════════════════════════════════════════════════════════════
    
    -- Animation state (useful for attack detection)
    isAnimating = safeCreatureCall(creature, "isAnimating", false),
    animationPhase = safeCreatureCall(creature, "getAnimationPhase", 0),
    
    -- Light emission (some monsters glow when attacking)
    light = safeCreatureCall(creature, "getLight", nil),
    
    -- Name color (can indicate status effects)
    nameColor = safeCreatureCall(creature, "getNameColor", nil),
    
    -- Marks/emblems
    emblem = safeCreatureCall(creature, "getEmblem", 0),
    
    -- Static square (attack indicator in game)
    hasStaticSquare = safeCreatureCall(creature, "hasStaticSquare", false),
    
    -- Distance from player (computed metric)
    distanceFromPlayer = 0
  }
  
  -- Early exit if we couldn't get position
  if not snapshot.position then return nil end
  
  -- Calculate distance from player (safely)
  local playerPos = nil
  if player then
    local okPlayer, pPos = pcall(function() return player:getPosition() end)
    if okPlayer then playerPos = pPos end
  end
  
  if playerPos and snapshot.position then
    snapshot.distanceFromPlayer = math.max(
      math.abs(snapshot.position.x - playerPos.x),
      math.abs(snapshot.position.y - playerPos.y)
    )
    
    -- Calculate direction to player (useful for dodge prediction)
    local dx = playerPos.x - snapshot.position.x
    local dy = playerPos.y - snapshot.position.y
    if dx ~= 0 or dy ~= 0 then
      snapshot.directionToPlayer = {x = dx, y = dy}
      -- Check if facing player
      snapshot.isFacingPlayer = MonsterAI.Predictor and MonsterAI.Predictor.isFacingPosition
        and MonsterAI.Predictor.isFacingPosition(snapshot.position, snapshot.direction, playerPos) or false
    end
  end
  
  -- Calculate derived metrics
  if snapshot.baseSpeed > 0 and snapshot.speed > 0 then
    snapshot.speedMultiplier = snapshot.speed / snapshot.baseSpeed
    snapshot.isHasted = snapshot.speedMultiplier > 1.15
    snapshot.isSlowed = snapshot.speedMultiplier < 0.85
  end
  
  -- Detect if monster might be casting (stopped walking but recently moved, or animating)
  snapshot.mightBeCasting = (not snapshot.isWalking and snapshot.isAnimating) or
                            (not snapshot.isWalking and snapshot.isFacingPlayer and snapshot.distanceFromPlayer <= 6)
  
  -- Store snapshot
  MonsterAI.Telemetry.snapshots[id] = snapshot
  MonsterAI.RealTime.metrics.telemetrySamples = (MonsterAI.RealTime.metrics.telemetrySamples or 0) + 1
  
  return snapshot
end

-- ============================================================================
-- METRICS AGGREGATOR (NEW in v2.2)
-- Centralized metrics collection for analysis and debugging
-- ============================================================================

MonsterAI.Metrics = MonsterAI.Metrics or {
  -- Aggregate metrics across all subsystems
  aggregate = {
    -- Combat metrics
    totalDamageReceived = 0,
    totalDamageDealt = 0,
    totalKills = 0,
    totalDeaths = 0,
    
    -- Prediction metrics
    predictionsTotal = 0,
    predictionsCorrect = 0,
    predictionsMissed = 0,
    predictionAccuracy = 0,
    
    -- Performance metrics
    updateCyclesTotal = 0,
    avgUpdateTimeMs = 0,
    peakUpdateTimeMs = 0,
    
    -- Session info
    sessionStartTime = nowMs(),
    lastUpdateTime = 0
  },
  
  -- Historical metrics for trend analysis
  history = {
    dpsReceived = {},      -- {time, value}
    monsterCounts = {},    -- {time, count}
    threatLevels = {}      -- {time, level}
  },
  
  MAX_HISTORY = 100
}

-- Collect all metrics from various subsystems
function MonsterAI.Metrics.collect()
  local nowt = nowMs()
  local m = MonsterAI.Metrics.aggregate
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- COLLECT FROM TRACKER
  -- ═══════════════════════════════════════════════════════════════════════════
  if MonsterAI.Tracker and MonsterAI.Tracker.stats then
    m.totalDamageReceived = MonsterAI.Tracker.stats.totalDamageReceived or 0
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- COLLECT FROM TELEMETRY SESSION
  -- ═══════════════════════════════════════════════════════════════════════════
  if MonsterAI.Telemetry and MonsterAI.Telemetry.session then
    local session = MonsterAI.Telemetry.session
    m.totalKills = session.killCount or 0
    m.totalDeaths = session.deathCount or 0
    m.totalDamageDealt = session.totalDamageDealt or 0
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- COLLECT FROM REALTIME METRICS
  -- ═══════════════════════════════════════════════════════════════════════════
  if MonsterAI.RealTime and MonsterAI.RealTime.metrics then
    local rt = MonsterAI.RealTime.metrics
    m.predictionsCorrect = rt.predictionsCorrect or 0
    m.predictionsMissed = rt.predictionsMissed or 0
    m.predictionsTotal = m.predictionsCorrect + m.predictionsMissed
    
    if m.predictionsTotal > 0 then
      m.predictionAccuracy = m.predictionsCorrect / m.predictionsTotal
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- COLLECT FROM COMBAT FEEDBACK
  -- ═══════════════════════════════════════════════════════════════════════════
  if MonsterAI.CombatFeedback and MonsterAI.CombatFeedback.getAccuracy then
    local acc = MonsterAI.CombatFeedback.getAccuracy()
    if acc then
      m.combatFeedbackAccuracy = acc.overall or 0
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- COLLECT FROM SPELL TRACKER
  -- ═══════════════════════════════════════════════════════════════════════════
  if MonsterAI.SpellTracker and MonsterAI.SpellTracker.getStats then
    local st = MonsterAI.SpellTracker.getStats()
    m.totalSpellsObserved = st.totalSpellsCast or 0
    m.spellsPerMinute = st.spellsPerMinute or 0
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- COLLECT FROM VOLUME ADAPTATION
  -- ═══════════════════════════════════════════════════════════════════════════
  if MonsterAI.VolumeAdaptation and MonsterAI.VolumeAdaptation.getStats then
    local va = MonsterAI.VolumeAdaptation.getStats()
    m.currentVolume = va.currentVolume
    m.avgMonsterCount = va.metrics and va.metrics.avgMonsterCount or 0
    m.cpuCyclesSaved = va.metrics and va.metrics.adaptationsSaved or 0
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- UPDATE HISTORY
  -- ═══════════════════════════════════════════════════════════════════════════
  local history = MonsterAI.Metrics.history
  
  -- Track monster count over time
  local monsterCount = 0
  if MonsterAI.Tracker and MonsterAI.Tracker.monsters then
    for _ in pairs(MonsterAI.Tracker.monsters) do
      monsterCount = monsterCount + 1
    end
  end
  table.insert(history.monsterCounts, {time = nowt, value = monsterCount})
  while #history.monsterCounts > MonsterAI.Metrics.MAX_HISTORY do
    table.remove(history.monsterCounts, 1)
  end
  
  -- Track threat level over time
  local threatLevel = 0
  if MonsterAI.RealTime and MonsterAI.RealTime.threatCache then
    threatLevel = MonsterAI.RealTime.threatCache.totalThreat or 0
  end
  table.insert(history.threatLevels, {time = nowt, value = threatLevel})
  while #history.threatLevels > MonsterAI.Metrics.MAX_HISTORY do
    table.remove(history.threatLevels, 1)
  end
  
  m.lastUpdateTime = nowt
  m.updateCyclesTotal = (m.updateCyclesTotal or 0) + 1
  
  return m
end

-- Get comprehensive metrics summary
function MonsterAI.Metrics.getSummary()
  MonsterAI.Metrics.collect()
  
  local m = MonsterAI.Metrics.aggregate
  local sessionDurationSec = math.max(1, (nowMs() - m.sessionStartTime) / 1000)
  
  return {
    -- Combat summary
    combat = {
      dpsReceived = m.totalDamageReceived / sessionDurationSec,
      damageReceived = m.totalDamageReceived,
      kills = m.totalKills,
      deaths = m.totalDeaths,
      kdr = m.totalDeaths > 0 and (m.totalKills / m.totalDeaths) or m.totalKills
    },
    
    -- Prediction summary
    prediction = {
      accuracy = m.predictionAccuracy,
      total = m.predictionsTotal,
      correct = m.predictionsCorrect,
      missed = m.predictionsMissed
    },
    
    -- Spell summary
    spells = {
      total = m.totalSpellsObserved or 0,
      perMinute = m.spellsPerMinute or 0
    },
    
    -- Volume/performance summary
    performance = {
      volume = m.currentVolume or "normal",
      avgMonsters = m.avgMonsterCount or 0,
      cyclesSaved = m.cpuCyclesSaved or 0,
      updateCycles = m.updateCyclesTotal or 0
    },
    
    -- Session info
    session = {
      durationSeconds = sessionDurationSec,
      startTime = m.sessionStartTime
    }
  }
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
  if not isCreatureValid(creature) then return end
  local id = safeGetId(creature)
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
  local playerPos = nil
  if player then
    local okP, pPos = pcall(function() return player:getPosition() end)
    if okP then playerPos = pPos end
  end
  local monsterPos = safeCreatureCall(creature, "getPosition", nil)
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
  if not isCreatureValid(creature) then return end
  local id = safeGetId(creature)
  if not id then return end
  
  local nowt = nowMs()
  local pos = safeCreatureCall(creature, "getPosition", nil)
  local dir = safeCreatureCall(creature, "getDirection", 0)
  
  -- Get learned cooldown for prediction
  local data = MonsterAI.Tracker.monsters[id]
  local pattern = MonsterAI.Patterns.get(safeCreatureCall(creature, "getName", "Unknown"))
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
        local Client = getClient()
        if Client and Client.isTileWalkable then
          local ok, result = pcall(Client.isTileWalkable, tile)
          walkable = ok and result
        elseif Client and Client.getTile then
          local ok, mapTile = pcall(Client.getTile, tile)
          walkable = ok and mapTile and mapTile:isWalkable()
        elseif g_map and g_map.isTileWalkable then
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
          local Client2 = getClient()
          if Client2 and Client2.getTile then
            local ok, mapTile = pcall(Client2.getTile, tile)
            walkable = ok and mapTile and mapTile:isWalkable()
          elseif g_map and g_map.getTile then
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
    if data and data.creature and not safeIsDead(data.creature) then
      local monsterPos = safeCreatureCall(data.creature, "getPosition", nil)
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
  -- Use safe validation instead of direct calls
  if not creature then return end
  if not isCreatureValid(creature) then return end
  if safeIsDead(creature) then return end
  
  local id = safeGetId(creature)
  if not id then return end  -- Creature ID unavailable (invalid creature or getId() failed)
  if MonsterAI.Tracker.monsters[id] then return end  -- Already tracking
  
  local pos = safeCreatureCall(creature, "getPosition", nil)
  if not pos then return end  -- Creature position unavailable (teleporting/disappearing)
  
  local nowt = nowMs()
  
  -- Collect initial telemetry snapshot (already uses safe calls internally)
  local initialSnapshot = MonsterAI.Telemetry.collectSnapshot(creature)
  
  MonsterAI.Tracker.monsters[id] = {
    creature = creature,
    id = id,
    name = safeCreatureCall(creature, "getName", "Unknown"),
    samples = {},           -- {time, pos, dir, health, isAttacking}
    lastDirection = safeCreatureCall(creature, "getDirection", 0),
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
    lastHealthPercent = safeCreatureCall(creature, "getHealthPercent", 100),
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
    pcall(function() EventBus.emit("monsterai:tracking_started", creature, id) end)
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
    if data.creature and safeIsDead(data.creature) then
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
  -- Use safe validation
  if not creature then return end
  if not isCreatureValid(creature) then return end
  if safeIsDead(creature) then return end
  
  local id = safeGetId(creature)
  if not id then return end  -- Invalid creature
  
  local data = MonsterAI.Tracker.monsters[id]
  if not data then
    MonsterAI.Tracker.track(creature)
    return
  end
  
  local currentTime = now
  local nowt = nowMs()
  local pos = safeCreatureCall(creature, "getPosition", nil)
  if not pos then return end  -- Creature position unavailable
  
  local dir = safeCreatureCall(creature, "getDirection", 0)
  local hp = safeCreatureCall(creature, "getHealthPercent", 100)
  
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
  if not creature then return false, 0, 999999 end
  if not isCreatureValid(creature) then return false, 0, 999999 end
  if safeIsDead(creature) then return false, 0, 999999 end
  
  local id = safeGetId(creature)
  if not id then return false, 0, 999999 end
  local data = MonsterAI.Tracker.monsters[id]
  local pattern = MonsterAI.Patterns.get(safeCreatureCall(creature, "getName", "Unknown"))

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
  local monsterPos = safeCreatureCall(creature, "getPosition", nil)
  local monsterDir = safeCreatureCall(creature, "getDirection", 0)
  if not monsterPos then return false, 0, 999999 end
  
  local playerPos = nil
  if player then
    local okP, pPos = pcall(function() return player:getPosition() end)
    if okP then playerPos = pPos end
  end
  if not playerPos then return false, 0, 999999 end
  
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
    if monster and not safeIsDead(monster) then
      local isPredicted, confidence, timeToAttack = 
        MonsterAI.Predictor.predictWaveAttack(monster)
      
      -- Emit wave prediction event for other modules (Exeta Amp, etc.)
      if isPredicted and confidence >= 0.5 and EventBus then
        pcall(function() EventBus.emit("monsterai:wave_predicted", monster, confidence, timeToAttack) end)
      end
      
      if isPredicted and timeToAttack < 1000 then
        -- Check if position is in attack path
        local mpos = safeCreatureCall(monster, "getPosition", nil)
        local mdir = safeCreatureCall(monster, "getDirection", 0)
        local pattern = MonsterAI.Patterns.get(safeCreatureCall(monster, "getName", "Unknown"))
        
        if mpos then
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
-- SPELL TRACKER MODULE (NEW in v2.2)
-- Comprehensive spell/missile tracking for monster attack analysis
-- Tracks: projectile types, cast frequency, target patterns, cooldowns
-- ============================================================================

MonsterAI.SpellTracker = MonsterAI.SpellTracker or {
  -- Global spell statistics
  stats = {
    totalSpellsCast = 0,
    totalMissiles = 0,
    uniqueMissileTypes = 0,
    spellsPerMinute = 0,
    lastMinuteSpells = 0,
    sessionStartTime = nowMs()
  },
  
  -- Per-monster spell data: monsterId -> spellData
  monsterSpells = {},
  
  -- Spell type catalog: missileTypeId -> spellInfo
  spellCatalog = {},
  
  -- Recent spells for reactivity analysis (bounded FIFO)
  recentSpells = {},
  MAX_RECENT_SPELLS = 100,
  
  -- Per-monster-type aggregated spell stats: monsterName -> aggregatedStats
  typeSpellStats = {}
}

-- Initialize spell tracking for a monster
function MonsterAI.SpellTracker.initMonster(creature)
  if not creature then return nil end
  if not isCreatureValid(creature) then return nil end
  local id = safeGetId(creature)
  if not id then return nil end
  
  if MonsterAI.SpellTracker.monsterSpells[id] then
    return MonsterAI.SpellTracker.monsterSpells[id]
  end
  
  local data = {
    id = id,
    name = safeCreatureCall(creature, "getName", "Unknown"),
    
    -- Spell counts and timing
    totalSpellsCast = 0,
    missilesByType = {},       -- missileTypeId -> count
    spellHistory = {},          -- { time, missileType, targetPos, sourcePos }
    
    -- EWMA-based spell cooldown tracking
    ewmaSpellCooldown = nil,
    ewmaSpellVariance = 0,
    lastSpellTime = 0,
    spellCooldownSamples = {},
    
    -- Spell pattern detection
    spellSequence = {},         -- Recent spell types in order
    detectedPatterns = {},      -- Recognized spell patterns/rotations
    
    -- Target analysis
    spellsAtPlayer = 0,
    spellsAtOthers = 0,
    avgSpellRange = 0,
    
    -- Spell frequency (casts per minute)
    castFrequency = 0,
    frequencyWindow = {},       -- { time } for rolling window
    
    -- First and last observed spell
    firstSpellTime = nil,
    lastObservedMissileType = nil
  }
  
  MonsterAI.SpellTracker.monsterSpells[id] = data
  return data
end

-- Record a spell cast by a monster
function MonsterAI.SpellTracker.recordSpell(creatureId, missileType, sourcePos, targetPos)
  local nowt = nowMs()
  local data = MonsterAI.SpellTracker.monsterSpells[creatureId]
  
  if not data then
    -- Try to find creature and init
    local trackerData = MonsterAI.Tracker.monsters[creatureId]
    if trackerData and trackerData.creature then
      data = MonsterAI.SpellTracker.initMonster(trackerData.creature)
    end
  end
  
  if not data then return end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- UPDATE SPELL COUNTS
  -- ═══════════════════════════════════════════════════════════════════════════
  data.totalSpellsCast = (data.totalSpellsCast or 0) + 1
  data.missilesByType[missileType] = (data.missilesByType[missileType] or 0) + 1
  
  -- Track first spell time
  if not data.firstSpellTime then
    data.firstSpellTime = nowt
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- SPELL COOLDOWN TRACKING (EWMA)
  -- ═══════════════════════════════════════════════════════════════════════════
  if data.lastSpellTime > 0 then
    local interval = nowt - data.lastSpellTime
    
    -- Ignore very short intervals (likely multi-projectile spells)
    if interval > 200 then
      -- Record sample
      table.insert(data.spellCooldownSamples, interval)
      while #data.spellCooldownSamples > 30 do
        table.remove(data.spellCooldownSamples, 1)
      end
      
      -- Update EWMA
      local alpha = CONST.EWMA.ALPHA_DEFAULT
      if data.ewmaSpellCooldown then
        local diff = interval - data.ewmaSpellCooldown
        data.ewmaSpellCooldown = data.ewmaSpellCooldown * (1 - alpha) + interval * alpha
        data.ewmaSpellVariance = data.ewmaSpellVariance * (1 - alpha) + (diff * diff) * alpha
      else
        data.ewmaSpellCooldown = interval
        data.ewmaSpellVariance = 0
      end
    end
  end
  data.lastSpellTime = nowt
  data.lastObservedMissileType = missileType
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- SPELL HISTORY & SEQUENCE TRACKING
  -- ═══════════════════════════════════════════════════════════════════════════
  local spellRecord = {
    time = nowt,
    missileType = missileType,
    sourcePos = sourcePos,
    targetPos = targetPos
  }
  table.insert(data.spellHistory, spellRecord)
  while #data.spellHistory > 50 do
    table.remove(data.spellHistory, 1)
  end
  
  -- Track spell sequence for pattern detection
  table.insert(data.spellSequence, missileType)
  while #data.spellSequence > 10 do
    table.remove(data.spellSequence, 1)
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- TARGET ANALYSIS
  -- ═══════════════════════════════════════════════════════════════════════════
  local playerPos = player and player:getPosition()
  if playerPos and targetPos then
    local distToPlayer = math.max(
      math.abs(targetPos.x - playerPos.x),
      math.abs(targetPos.y - playerPos.y)
    )
    
    if distToPlayer <= 1 then
      data.spellsAtPlayer = (data.spellsAtPlayer or 0) + 1
    else
      data.spellsAtOthers = (data.spellsAtOthers or 0) + 1
    end
    
    -- Update average spell range
    if sourcePos then
      local range = math.max(
        math.abs(targetPos.x - sourcePos.x),
        math.abs(targetPos.y - sourcePos.y)
      )
      data.avgSpellRange = (data.avgSpellRange or 0) * 0.8 + range * 0.2
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- FREQUENCY TRACKING (rolling 60-second window)
  -- ═══════════════════════════════════════════════════════════════════════════
  data.frequencyWindow = data.frequencyWindow or {}
  table.insert(data.frequencyWindow, nowt)
  
  -- Prune entries older than 60 seconds
  while #data.frequencyWindow > 0 and (nowt - data.frequencyWindow[1]) > 60000 do
    table.remove(data.frequencyWindow, 1)
  end
  data.castFrequency = #data.frequencyWindow
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- GLOBAL STATS UPDATE
  -- ═══════════════════════════════════════════════════════════════════════════
  local stats = MonsterAI.SpellTracker.stats
  stats.totalSpellsCast = (stats.totalSpellsCast or 0) + 1
  stats.totalMissiles = (stats.totalMissiles or 0) + 1
  
  -- Add to recent spells
  table.insert(MonsterAI.SpellTracker.recentSpells, {
    time = nowt,
    monsterId = creatureId,
    monsterName = data.name,
    missileType = missileType,
    targetedPlayer = playerPos and targetPos and 
      math.max(math.abs(targetPos.x - playerPos.x), math.abs(targetPos.y - playerPos.y)) <= 1
  })
  while #MonsterAI.SpellTracker.recentSpells > MonsterAI.SpellTracker.MAX_RECENT_SPELLS do
    table.remove(MonsterAI.SpellTracker.recentSpells, 1)
  end
  
  -- Update spell catalog
  if not MonsterAI.SpellTracker.spellCatalog[missileType] then
    MonsterAI.SpellTracker.spellCatalog[missileType] = {
      typeId = missileType,
      firstSeen = nowt,
      totalCasts = 0,
      monstersSeen = {}
    }
    stats.uniqueMissileTypes = (stats.uniqueMissileTypes or 0) + 1
  end
  local catalogEntry = MonsterAI.SpellTracker.spellCatalog[missileType]
  catalogEntry.totalCasts = catalogEntry.totalCasts + 1
  catalogEntry.lastSeen = nowt
  catalogEntry.monstersSeen[data.name:lower()] = true
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- UPDATE TYPE AGGREGATED STATS
  -- ═══════════════════════════════════════════════════════════════════════════
  local nameLower = data.name:lower()
  local typeStats = MonsterAI.SpellTracker.typeSpellStats[nameLower]
  if not typeStats then
    typeStats = {
      name = data.name,
      totalSpells = 0,
      avgCooldown = nil,
      missileTypes = {},
      spellsPerEncounter = 0,
      encounterCount = 0
    }
    MonsterAI.SpellTracker.typeSpellStats[nameLower] = typeStats
  end
  typeStats.totalSpells = typeStats.totalSpells + 1
  typeStats.missileTypes[missileType] = (typeStats.missileTypes[missileType] or 0) + 1
  
  -- Update avg cooldown
  if data.ewmaSpellCooldown then
    if typeStats.avgCooldown then
      typeStats.avgCooldown = typeStats.avgCooldown * 0.9 + data.ewmaSpellCooldown * 0.1
    else
      typeStats.avgCooldown = data.ewmaSpellCooldown
    end
  end
  
  -- Emit spell cast event
  if EventBus and EventBus.emit then
    EventBus.emit("monsterai:spell_cast", {
      creatureId = creatureId,
      monsterName = data.name,
      missileType = missileType,
      totalSpells = data.totalSpellsCast,
      cooldown = data.ewmaSpellCooldown,
      frequency = data.castFrequency,
      targetedPlayer = playerPos and targetPos and 
        math.max(math.abs(targetPos.x - playerPos.x), math.abs(targetPos.y - playerPos.y)) <= 1
    })
  end
end

-- Get spell statistics for a specific monster
function MonsterAI.SpellTracker.getMonsterSpells(creatureId)
  return MonsterAI.SpellTracker.monsterSpells[creatureId]
end

-- Get aggregated spell stats for a monster type
function MonsterAI.SpellTracker.getTypeSpellStats(monsterName)
  if not monsterName then return nil end
  return MonsterAI.SpellTracker.typeSpellStats[monsterName:lower()]
end

-- Get global spell statistics
function MonsterAI.SpellTracker.getStats()
  local stats = MonsterAI.SpellTracker.stats
  local nowt = nowMs()
  
  -- Calculate spells per minute
  local sessionDurationMin = math.max(1, (nowt - stats.sessionStartTime) / 60000)
  stats.spellsPerMinute = stats.totalSpellsCast / sessionDurationMin
  
  -- Count spells in last minute
  local recentCount = 0
  for i = #MonsterAI.SpellTracker.recentSpells, 1, -1 do
    if (nowt - MonsterAI.SpellTracker.recentSpells[i].time) <= 60000 then
      recentCount = recentCount + 1
    else
      break
    end
  end
  stats.lastMinuteSpells = recentCount
  
  return stats
end

-- Analyze spell reactivity (how fast monsters cast in response to player)
function MonsterAI.SpellTracker.analyzeReactivity()
  local result = {
    avgTimeBetweenSpells = 0,
    spellBurstDetected = false,
    highVolumeThreshold = false,
    lowVolumeThreshold = false,
    activeMonsterCount = 0,
    totalRecentSpells = #MonsterAI.SpellTracker.recentSpells
  }
  
  local nowt = nowMs()
  local recentWindow = 10000 -- 10 seconds
  local recentSpells = {}
  
  for i = #MonsterAI.SpellTracker.recentSpells, 1, -1 do
    local spell = MonsterAI.SpellTracker.recentSpells[i]
    if (nowt - spell.time) <= recentWindow then
      table.insert(recentSpells, spell)
    else
      break
    end
  end
  
  result.totalRecentSpells = #recentSpells
  
  -- Count unique monsters casting
  local uniqueMonsters = {}
  for _, spell in ipairs(recentSpells) do
    uniqueMonsters[spell.monsterId] = true
  end
  for _ in pairs(uniqueMonsters) do
    result.activeMonsterCount = result.activeMonsterCount + 1
  end
  
  -- Calculate average time between spells
  if #recentSpells >= 2 then
    local totalInterval = 0
    for i = 2, #recentSpells do
      totalInterval = totalInterval + (recentSpells[i-1].time - recentSpells[i].time)
    end
    result.avgTimeBetweenSpells = totalInterval / (#recentSpells - 1)
  end
  
  -- Detect spell burst (many spells in short time)
  if #recentSpells >= 5 and result.avgTimeBetweenSpells < 500 then
    result.spellBurstDetected = true
  end
  
  -- Volume thresholds
  result.highVolumeThreshold = result.activeMonsterCount >= 4 or #recentSpells >= 15
  result.lowVolumeThreshold = result.activeMonsterCount <= 1 and #recentSpells <= 3
  
  return result
end

-- Clean up spell data for removed monsters
function MonsterAI.SpellTracker.cleanup(creatureId)
  if creatureId then
    local data = MonsterAI.SpellTracker.monsterSpells[creatureId]
    if data then
      -- Update type stats before removing
      local nameLower = data.name:lower()
      local typeStats = MonsterAI.SpellTracker.typeSpellStats[nameLower]
      if typeStats then
        typeStats.encounterCount = (typeStats.encounterCount or 0) + 1
        if data.totalSpellsCast > 0 then
          local prevAvg = typeStats.spellsPerEncounter or 0
          typeStats.spellsPerEncounter = prevAvg * 0.8 + data.totalSpellsCast * 0.2
        end
      end
    end
    MonsterAI.SpellTracker.monsterSpells[creatureId] = nil
  end
end

-- Get summary for UI display
function MonsterAI.SpellTracker.getSummary()
  local stats = MonsterAI.SpellTracker.getStats()
  local reactivity = MonsterAI.SpellTracker.analyzeReactivity()
  
  return {
    stats = stats,
    reactivity = reactivity,
    catalogSize = 0, -- Will be calculated below
    trackedMonsters = 0
  }, function(summary)
    for _ in pairs(MonsterAI.SpellTracker.spellCatalog) do
      summary.catalogSize = summary.catalogSize + 1
    end
    for _ in pairs(MonsterAI.SpellTracker.monsterSpells) do
      summary.trackedMonsters = summary.trackedMonsters + 1
    end
    return summary
  end
end

-- ============================================================================
-- EVENTBUS INTEGRATION (Enhanced for Real-Time Threat Detection)
-- ============================================================================

if EventBus then
  -- Track monsters when they appear
  EventBus.on("monster:appear", function(creature)
    MonsterAI.Tracker.track(creature)
    
    -- Initialize direction tracking immediately
    local id = safeGetId(creature)
    if id then
      local dir = safeCreatureCall(creature, "getDirection", 0)
      MonsterAI.RealTime.directions[id] = {
        dir = dir,
        lastChangeTime = nowMs(),
        consecutiveChanges = 0,
        turnRate = 0
      }
      
      -- Check if already facing player (instant threat check)
      local playerPos = nil
      if player then
        local okP, pPos = pcall(function() return player:getPosition() end)
        if okP then playerPos = pPos end
      end
      local monsterPos = safeCreatureCall(creature, "getPosition", nil)
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
      local id = safeGetId(creature)
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
    if not creature then return end
    if not safeIsMonster(creature) then return end
    
    local id = safeGetId(creature)
    if not id then return end
    
    local newDir = safeCreatureCall(creature, "getDirection", 0)
    local rt = MonsterAI.RealTime.directions[id]
    local oldDir = rt and rt.dir or newDir
    
    -- Direction changed - this is a key attack indicator
    if oldDir ~= newDir then
      MonsterAI.RealTime.onDirectionChange(creature, oldDir, newDir)
    else
      -- Position changed but direction same - update position tracking
      if rt then
        rt.positions = rt.positions or {}
        local pos = safeCreatureCall(creature, "getPosition", nil)
        if pos then
          table.insert(rt.positions, { pos = pos, time = nowMs() })
          -- Keep last 10 positions
          while #rt.positions > 10 do table.remove(rt.positions, 1) end
        end
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
      local id = safeGetId(creature)
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
    local playerPos = nil
    if player then
      local okP, pPos = pcall(function() return player:getPosition() end)
      if okP then playerPos = pPos end
    end
    if not playerPos then return end

    local function scoreMonsterForDamage(m, playerPos, nowt)
      if not m then return 0, nil end
      local mpos = safeCreatureCall(m, "getPosition", nil)
      if not mpos then return 0, nil end
      if safeIsDead(m) or not safeIsMonster(m) then return 0, nil end
      local dist = math.max(math.abs(playerPos.x - mpos.x), math.abs(playerPos.y - mpos.y))
      local score = 1 / (1 + dist)
      local id = safeGetId(m)
      local data = id and MonsterAI.Tracker.monsters[id]

      -- Prefer recently active/visible attackers
      if data and data.lastWaveTime and math.abs(nowt - data.lastWaveTime) < 800 then score = score + 1.2 end
      if data and data.lastAttackTime and math.abs(nowt - data.lastAttackTime) < 1500 then score = score + 0.8 end
      -- Prefer ones facing the player
      if data and MonsterAI.Predictor.isFacingPosition then
        local mdir = safeCreatureCall(m, "getDirection", 0)
        local facing = MonsterAI.Predictor.isFacingPosition(mpos, mdir, playerPos)
        if facing then score = score + 0.6 end
      end
      return score, data
    end

    local Client = getClient()
    local creatures = (MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby)
      and MovementCoordinator.MonsterCache.getNearby(CONST.DAMAGE.CORRELATION_RADIUS)
      or ((Client and Client.getSpectatorsInRange) and Client.getSpectatorsInRange(playerPos, false, CONST.DAMAGE.CORRELATION_RADIUS, CONST.DAMAGE.CORRELATION_RADIUS) or (g_map and g_map.getSpectatorsInRange and g_map.getSpectatorsInRange(playerPos, false, CONST.DAMAGE.CORRELATION_RADIUS, CONST.DAMAGE.CORRELATION_RADIUS)))

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
        local attributedId = safeGetId(bestMonster)
        local attributedName = bestData.name
        pcall(function() MonsterAI.CombatFeedback.recordDamage(damage, attributedId, attributedName) end)
      end

      -- Persist small bump
      local pname = (bestData.name or ""):lower()
      MonsterAI.Patterns.persist(pname, { lastSeen = nowMs(), confidence = math.min((MonsterAI.Patterns.knownMonsters[pname] and MonsterAI.Patterns.knownMonsters[pname].confidence or 0.5) + 0.03, 0.99) })
    end
  end, 30)

  -- Projectile/missile events: observe attacks originating from monsters
  -- Enhanced with SpellTracker integration (v2.2)
  if onMissle then
    onMissle(function(missle)
      if not missle then return end
      
      local srcPos = missle:getSource()
      local destPos = missle:getDestination()
      
      if not srcPos or not destPos then return end
      
      -- Get the source tile and find creatures on it
      local Client = getClient()
      local srcTile = (Client and Client.getTile) and Client.getTile(srcPos) or (g_map and g_map.getTile and g_map.getTile(srcPos))
      if not srcTile then return end
      
      local creatures = srcTile:getCreatures()
      if not creatures or #creatures == 0 then return end
      
      -- Find a monster on the source tile (the caster)
      local src = nil
      for i = 1, #creatures do
        local c = creatures[i]
        if c and safeIsMonster(c) and not safeIsDead(c) then
          src = c
          break
        end
      end
      
      if not src then return end

      local id = safeGetId(src)
      if not id then return end

      if not MonsterAI.Tracker.monsters[id] then MonsterAI.Tracker.track(src) end
      local data = MonsterAI.Tracker.monsters[id]
      if not data then return end

      local nowt = nowMs()
      
      -- ═══════════════════════════════════════════════════════════════════════
      -- SPELL TRACKER INTEGRATION (NEW in v2.2)
      -- Record spell with missile type for detailed analytics
      -- ═══════════════════════════════════════════════════════════════════════
      local missileType = missle.getId and missle:getId() or 0
      if MonsterAI.SpellTracker and MonsterAI.SpellTracker.recordSpell then
        MonsterAI.SpellTracker.recordSpell(id, missileType, srcPos, destPos)
      end
      
      -- Record the attack timestamp for wave prediction
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
      
      -- Emit wave observed event for other modules
      if EventBus and EventBus.emit then
        EventBus.emit("monsterai:wave_observed", src, {
          missileType = missileType,
          sourcePos = srcPos,
          destPos = destPos,
          totalMissiles = data.missileCount
        })
      end
    end)
  end
  
  -- Also listen for effect:missile EventBus event for additional coverage
  if EventBus then
    EventBus.on("effect:missile", function(missile)
      if not missile then return end
      
      local srcPos = missile.getSource and missile:getSource()
      local destPos = missile.getDestination and missile:getDestination()
      
      if not srcPos then return end
      
      -- Get source tile
      local Client2 = getClient()
      local srcTile = (Client2 and Client2.getTile) and Client2.getTile(srcPos) or (g_map and g_map.getTile and g_map.getTile(srcPos))
      if not srcTile then return end
      
      local creatures = srcTile.getCreatures and srcTile:getCreatures()
      if not creatures then return end
      
      -- Find monster caster
      for i = 1, #creatures do
        local c = creatures[i]
        if c and safeIsMonster(c) and not safeIsDead(c) then
          local id = safeGetId(c)
          if id and MonsterAI.SpellTracker then
            local missileType = missile.getId and missile:getId() or 0
            pcall(function() MonsterAI.SpellTracker.recordSpell(id, missileType, srcPos, destPos) end)
          end
          break
        end
      end
    end, 25)
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- NATIVE OTCLIENT TURN CALLBACK
  -- Direct hook into OTClient's onCreatureTurn for fastest direction change detection
  -- This is critical for wave attack prediction as monsters turn before attacking
  -- ═══════════════════════════════════════════════════════════════════════════
  if onCreatureTurn then
    onCreatureTurn(function(creature, direction)
      if not creature then return end
      if not safeIsMonster(creature) then return end
      if safeIsDead(creature) then return end
      
      local id = safeGetId(creature)
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
        pcall(function() EventBus.emit("creature:turn", creature, direction, oldDir) end)
      end
      
      -- Check if now facing player
      local playerPos = nil
      if player then
        local okP, pPos = pcall(function() return player:getPosition() end)
        if okP then playerPos = pPos end
      end
      local monsterPos = safeCreatureCall(creature, "getPosition", nil)
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
                local name = safeCreatureCall(creature, "getName", "Unknown")
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
    if not target then return end
    if not safeIsMonster(target) then return end
    
    local id = safeGetId(target)
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
        pcall(function()
          EventBus.emit("monsterai:engagement_started", target, id, {
            name = data.name,
            healthPercent = safeCreatureCall(target, "getHealthPercent", 100)
          })
        end)
      end
    end
  end, 25)
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- CREATURE DEATH EVENT - Finalize tracking and collect kill stats
  -- ═══════════════════════════════════════════════════════════════════════════
  EventBus.on("creature:death", function(creature)
    if not creature then return end
    if not safeIsMonster(creature) then return end
    
    local id = safeGetId(creature)
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
      if data.creature and not safeIsDead(data.creature) then
        local pos = safeCreatureCall(data.creature, "getPosition", nil)
        local playerPos = nil
        if player then
          local okP, pPos = pcall(function() return player:getPosition() end)
          if okP then playerPos = pPos end
        end
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

  -- ═══════════════════════════════════════════════════════════════════════════
  -- VOLUME ADAPTATION UPDATE (NEW in v2.2)
  -- Adjust processing parameters based on monster count
  -- ═══════════════════════════════════════════════════════════════════════════
  if MonsterAI.VolumeAdaptation and MonsterAI.VolumeAdaptation.update then
    pcall(function() MonsterAI.VolumeAdaptation.update() end)
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
      local Client = getClient()
      local ok, result = pcall(function()
        if Client and Client.getSpectatorsInRange then
          return Client.getSpectatorsInRange(playerPos, false, 8, 8)
        elseif g_map and g_map.getSpectatorsInRange then
          return g_map.getSpectatorsInRange(playerPos, false, 8, 8)
        end
        return {}
      end)
      creatures = ok and result or {}
    end
  end

  if not creatures then
    return
  end

  local processed = 0
  local skipped = 0
  local vaParams = MonsterAI.VolumeAdaptation and MonsterAI.VolumeAdaptation.getParams() or {}
  local maxPerCycle = vaParams.maxTrackedPerCycle or 10
  
  for i = 1, #creatures do
    local creature = creatures[i]
    -- Use safe checks instead of direct creature method calls
    if creature and isValidAliveMonster(creature) then
      local id = safeGetId(creature)
      
      -- Volume-based load balancing: in high load, skip some monsters per cycle
      local shouldProcess = true
      if MonsterAI.VolumeAdaptation and MonsterAI.VolumeAdaptation.shouldProcessMonster and id then
        shouldProcess = MonsterAI.VolumeAdaptation.shouldProcessMonster(id)
      end
      
      -- Also respect max per cycle limit
      if processed >= maxPerCycle then
        shouldProcess = false
      end
      
      if shouldProcess then
        local ok, err = pcall(function() MonsterAI.Tracker.update(creature) end)
        if not ok then
          -- Tracker.update failed (silent)
        end
        processed = processed + 1
      else
        skipped = skipped + 1
      end
    end
  end
  
  -- Track adaptation metrics
  if MonsterAI.VolumeAdaptation and skipped > 0 then
    MonsterAI.VolumeAdaptation.metrics.adaptationsSaved = 
      (MonsterAI.VolumeAdaptation.metrics.adaptationsSaved or 0) + skipped
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
-- IMPROVED v3.0: Added engagement lock for linear targeting
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
  lastMoveRecord = 0,           -- Last movement record timestamp
  scenarioStartTime = 0,        -- When current scenario started
  avgDangerLevel = 0,           -- Average threat level of nearby monsters
  clusterInfo = nil,            -- Monster clustering analysis
  -- NEW: Engagement lock system (prevents ANY switching once attack started)
  engagementLockId = nil,       -- ID of monster we are engaged with (attack started)
  engagementLockTime = 0,       -- When engagement started
  engagementLockHealth = 100,   -- Health when engagement started
  isEngaged = false,            -- TRUE = currently in combat with engagementLockId
  lastAttackCommandTime = 0     -- When we last sent attack command (for engagement detection)
}

-- Configuration for each scenario type
-- IMPROVED v3.0: Much stricter anti-zigzag with engagement locking
Scenario.configs = {
  [Scenario.TYPES.IDLE] = {
    switchCooldownMs = 0,
    targetStickiness = 0,
    prioritizeFinishingKills = false,
    allowZigzag = true,
    description = "No combat"
  },
  
  [Scenario.TYPES.SINGLE] = {
    switchCooldownMs = 1000,      -- INCREASED: 1 second minimum
    targetStickiness = 80,        -- INCREASED: High stickiness even for single
    prioritizeFinishingKills = true,
    allowZigzag = false,          -- CHANGED: No zigzag even on single target
    requireEngagementLock = true, -- NEW: Must finish current target
    description = "Single target - focused"
  },
  
  [Scenario.TYPES.FEW] = {
    switchCooldownMs = 5000,      -- INCREASED: 5 second minimum (was 2s)
    targetStickiness = 150,       -- INCREASED: Very high stickiness (was 50)
    prioritizeFinishingKills = true,
    allowZigzag = false,          -- STRICT: No zigzag allowed
    maxSwitchesPerMinute = 3,     -- REDUCED: Max 3 switches per minute (was 6)
    healthThresholdForSwitch = 15, -- REDUCED: Only switch if target above 15% (was 40%)
    requireEngagementLock = true, -- NEW: Must finish current target
    description = "Few targets - LINEAR targeting, anti-zigzag"
  },
  
  [Scenario.TYPES.MODERATE] = {
    switchCooldownMs = 4000,      -- INCREASED: 4 second cooldown (was 1.5s)
    targetStickiness = 100,       -- INCREASED: High stickiness (was 35)
    prioritizeFinishingKills = true,
    allowZigzag = false,          -- Still prevent zigzag
    maxSwitchesPerMinute = 5,     -- REDUCED (was 10)
    healthThresholdForSwitch = 20, -- REDUCED (was 30%)
    requireEngagementLock = true, -- NEW: Must finish current target
    description = "Moderate - stable targeting"
  },
  
  [Scenario.TYPES.SWARM] = {
    switchCooldownMs = 2500,      -- INCREASED (was 1s)
    targetStickiness = 60,        -- INCREASED (was 20)
    prioritizeFinishingKills = true, -- CHANGED: Focus on finishing kills
    allowZigzag = false,          -- Prevent erratic movement
    maxSwitchesPerMinute = 8,     -- REDUCED (was 15)
    healthThresholdForSwitch = 15,
    focusLowestHealth = true,     -- Prioritize finishing any monster
    requireEngagementLock = false, -- Allow some switching in swarm
    description = "Swarm - focused survival"
  },
  
  [Scenario.TYPES.OVERWHELMING] = {
    switchCooldownMs = 1500,      -- INCREASED (was 500ms)
    targetStickiness = 40,        -- INCREASED (was 10)
    prioritizeFinishingKills = true, -- CHANGED: Still try to finish
    allowZigzag = false,          -- CHANGED: Prevent zigzag even here
    focusLowestHealth = true,
    emergencyMode = true,         -- Special handling
    requireEngagementLock = false, -- Allow reactivity in emergency
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
  -- IMPROVED v3.0: Increased range from 10 to 14 for better detection
  local monsters = {}
  local totalDanger = 0
  local monsterCount = 0
  
  local Client = getClient()
  local creatures = (Client and Client.getSpectators) and Client.getSpectators(playerPos, false) or (g_map and g_map.getSpectators and g_map.getSpectators(playerPos, false)) or {}
  
  for _, creature in ipairs(creatures) do
    if creature and isValidAliveMonster(creature) then
      local creaturePos = safeCreatureCall(creature, "getPosition", nil)
      if creaturePos and creaturePos.z == playerPos.z then
        local dx = math.abs(creaturePos.x - playerPos.x)
        local dy = math.abs(creaturePos.y - playerPos.y)
        local dist = math.max(dx, dy)
        
        if dist <= 14 then  -- INCREASED from 10 to 14 for full screen coverage
          monsterCount = monsterCount + 1
          
          local danger = 1
          local id = safeGetId(creature)
          local trackerData = MonsterAI.Tracker and id and MonsterAI.Tracker.monsters[id]
          if trackerData then
            danger = (trackerData.ewmaDps or 1) / 10 + 1
          end
          totalDanger = totalDanger + danger
          
          table.insert(monsters, {
            creature = creature,
            id = id,
            distance = dist,
            health = safeCreatureCall(creature, "getHealthPercent", 100),
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
-- TARGET LOCK SYSTEM (Anti-Zigzag) - IMPROVED v2.0
-- Now enforces LINEAR targeting: one target until death
-- ============================================================================

-- Check if we should allow a target switch
-- IMPROVED v3.0: MUCH stricter with engagement lock - LINEAR targeting
function Scenario.shouldAllowTargetSwitch(newTargetId, newTargetPriority, newTargetHealth)
  local nowt = nowMs()
  local cfg = Scenario.configs[Scenario.state.type] or Scenario.configs[Scenario.TYPES.FEW]
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- ENGAGEMENT LOCK CHECK (HIGHEST PRIORITY)
  -- If engaged, NEVER switch unless target is dead/gone/unreachable
  -- ═══════════════════════════════════════════════════════════════════════════
  if cfg.requireEngagementLock and Scenario.state.isEngaged and Scenario.state.engagementLockId then
    -- Check if engaged target is still valid
    local engagedCreature = nil
    if MonsterAI.Tracker and MonsterAI.Tracker.monsters[Scenario.state.engagementLockId] then
      engagedCreature = MonsterAI.Tracker.monsters[Scenario.state.engagementLockId].creature
    end
    
    if engagedCreature and not safeIsDead(engagedCreature) and not safeIsRemoved(engagedCreature) then
      -- Engaged target is still alive - ONLY allow if trying to switch TO the engaged target
      if newTargetId == Scenario.state.engagementLockId then
        return true, "engaged_target"
      end
      -- BLOCK any other switch while engaged
      return false, "engagement_locked"
    else
      -- Engaged target is dead/gone - end engagement and allow switch
      Scenario.endEngagement("target_dead")
    end
  end
  
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
  
  if not lockedCreature then
    Scenario.clearTargetLock()
    return true, "target_gone"
  end
  
  -- Safe dead check
  local okDead, isDead = pcall(function() return lockedCreature:isDead() end)
  local okRemoved, isRemoved = pcall(function() return lockedCreature:isRemoved() end)
  if (okDead and isDead) or (okRemoved and isRemoved) then
    Scenario.clearTargetLock()
    return true, "target_dead"
  end
  
  -- Same target - always allow
  if newTargetId == Scenario.state.targetLockId then
    return true, "same_target"
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- STRICT LINEAR TARGETING v3.0: Finish current target before switching
  -- MUCH stricter thresholds - effectively prevents ALL switching once attacking
  -- ═══════════════════════════════════════════════════════════════════════════
  
  -- Get current target health
  local okHp, lockedHealth = pcall(function() return lockedCreature:getHealthPercent() end)
  lockedHealth = okHp and lockedHealth or 100
  
  -- CRITICAL HP (≤30%): NEVER switch when target is low health
  -- INCREASED from 20% to 30% for more consistent targeting
  if lockedHealth <= 30 then
    return false, "finishing_kill_30"
  end
  
  -- LOW HP (≤50%): Only switch for EXTREMELY high priority (emergency only)
  -- INCREASED from 40% to 50%
  if lockedHealth <= 50 then
    local requiredAdvantage = 500  -- INCREASED: Need 500+ priority advantage (nearly impossible)
    if (newTargetPriority or 0) < (Scenario.state.targetLockHealth or 0) + requiredAdvantage then
      return false, "finishing_kill_50"
    end
  end
  
  -- WOUNDED (≤80%): Require very significant priority advantage
  -- INCREASED from 70% to 80%
  if lockedHealth <= 80 then
    local requiredAdvantage = 300  -- INCREASED: Need 300+ priority advantage
    local healthDrop = (Scenario.state.targetLockHealth or 100) - lockedHealth
    -- If making progress (health dropped), require even more advantage
    if healthDrop > 10 then
      requiredAdvantage = 400  -- INCREASED
    end
    if (newTargetPriority or 0) < requiredAdvantage then
      return false, "making_progress"
    end
  end
  
  -- Check switch cooldown (SIGNIFICANTLY increased for stability)
  local timeSinceSwitch = nowt - Scenario.state.lastSwitchTime
  local switchCooldown = cfg.switchCooldownMs or 5000  -- INCREASED default to 5 seconds
  if timeSinceSwitch < switchCooldown then
    return false, "cooldown"
  end
  
  -- Check switches per minute limit (MUCH stricter)
  if cfg.maxSwitchesPerMinute then
    local maxSwitches = math.max(2, cfg.maxSwitchesPerMinute - 1)  -- REDUCED: subtract 1 instead of 2
    local switchInterval = 60000 / maxSwitches
    if timeSinceSwitch < switchInterval and Scenario.state.consecutiveSwitches > 0 then  -- STRICTER: > 0 instead of > 1
      return false, "rate_limit"
    end
  end
  
  -- Calculate locked target's current state
  local lockedHealthDrop = (Scenario.state.targetLockHealth or 100) - lockedHealth
  
  -- If we're making ANY progress on current target, stay focused
  -- REDUCED threshold from 10% to 5%
  if lockedHealthDrop > 5 and lockedHealth > 5 then
    -- Making progress - require MUCH higher priority to switch
    local progressBonus = math.min(100, lockedHealthDrop * 2)  -- INCREASED multiplier
    local requiredAdvantage = 300 + progressBonus  -- INCREASED base from 150 to 300
    if (newTargetPriority or 0) < requiredAdvantage then
      return false, "making_progress"
    end
  end
  
  -- Zigzag detection - MUCH stricter (fewer switches trigger prevention)
  if not cfg.allowZigzag and Scenario.state.consecutiveSwitches >= 2 then  -- REDUCED from 3 to 2
    local avgSwitchTime = (nowt - Scenario.state.scenarioStartTime) / math.max(1, Scenario.state.consecutiveSwitches)
    if avgSwitchTime < 5000 then  -- INCREASED from 3s to 5s per switch on average
      -- Force lock on current target
      return false, "zigzag_prevention"
    end
  end
  
  return true, "allowed"
end

-- Lock onto a target
-- IMPROVED: More comprehensive state tracking for linear targeting
function Scenario.lockTarget(creatureId, health)
  local nowt = nowMs()
  local prevLock = Scenario.state.targetLockId
  
  -- Update lock state
  Scenario.state.targetLockId = creatureId
  Scenario.state.targetLockTime = nowt
  Scenario.state.targetLockHealth = health or 100
  
  -- Track switches (for rate limiting and zigzag detection)
  if prevLock and prevLock ~= creatureId then
    Scenario.state.lastSwitchTime = nowt
    Scenario.state.consecutiveSwitches = Scenario.state.consecutiveSwitches + 1
    
    -- Record movement for zigzag detection
    Scenario.recordMovement()
    
    -- Emit target switch event for other modules
    if EventBus and EventBus.emit then
      pcall(function()
        EventBus.emit("monsterai:target_switched", creatureId, prevLock)
      end)
    end
  elseif not prevLock then
    -- New lock (not a switch)
    Scenario.state.consecutiveSwitches = 0
    
    -- Emit target acquired event
    if EventBus and EventBus.emit then
      pcall(function()
        EventBus.emit("monsterai:target_locked", creatureId, health)
      end)
    end
  end
  
  -- Reset switch counter periodically (every 10 seconds of stable targeting)
  if (nowt - Scenario.state.lastSwitchTime) > 10000 then
    Scenario.state.consecutiveSwitches = 0
  end
end

-- Clear target lock
function Scenario.clearTargetLock()
  Scenario.state.targetLockId = nil
  Scenario.state.targetLockTime = 0
  Scenario.state.targetLockHealth = 100
end

-- ============================================================================
-- ENGAGEMENT LOCK SYSTEM (v3.0) - LINEAR TARGETING
-- Once we start attacking a monster, we STAY on it until it dies or becomes unreachable
-- This prevents the zig-zag behavior completely
-- ============================================================================

-- Start engagement with a monster (called when attack command is sent)
function Scenario.startEngagement(creatureId, health)
  if not creatureId then return end
  
  local nowt = nowMs()
  local cfg = Scenario.configs[Scenario.state.type] or Scenario.configs[Scenario.TYPES.FEW]
  
  -- Check if engagement lock is required for current scenario
  if not cfg.requireEngagementLock then
    -- Still use regular target lock
    Scenario.lockTarget(creatureId, health)
    return
  end
  
  -- If already engaged with same target, just update health
  if Scenario.state.engagementLockId == creatureId then
    Scenario.state.lastAttackCommandTime = nowt
    return
  end
  
  -- Only allow new engagement if not already engaged OR current engagement is invalid
  if Scenario.state.isEngaged and Scenario.state.engagementLockId then
    -- Check if currently engaged target is still valid
    local engagedCreature = nil
    if MonsterAI.Tracker and MonsterAI.Tracker.monsters[Scenario.state.engagementLockId] then
      engagedCreature = MonsterAI.Tracker.monsters[Scenario.state.engagementLockId].creature
    end
    
    if engagedCreature and not safeIsDead(engagedCreature) and not safeIsRemoved(engagedCreature) then
      -- Current engagement is still valid - DO NOT allow new engagement
      return
    end
  end
  
  -- Start new engagement
  Scenario.state.engagementLockId = creatureId
  Scenario.state.engagementLockTime = nowt
  Scenario.state.engagementLockHealth = health or 100
  Scenario.state.isEngaged = true
  Scenario.state.lastAttackCommandTime = nowt
  
  -- Also set regular target lock
  Scenario.lockTarget(creatureId, health)
  
  -- Emit engagement event
  if EventBus and EventBus.emit then
    pcall(function()
      EventBus.emit("monsterai:engagement_started", creatureId, health)
    end)
  end
end

-- Check if currently engaged
function Scenario.isEngaged()
  if not Scenario.state.isEngaged or not Scenario.state.engagementLockId then
    return false, nil
  end
  
  -- Validate engaged target is still alive
  local engagedCreature = nil
  if MonsterAI.Tracker and MonsterAI.Tracker.monsters[Scenario.state.engagementLockId] then
    engagedCreature = MonsterAI.Tracker.monsters[Scenario.state.engagementLockId].creature
  end
  
  if not engagedCreature or safeIsDead(engagedCreature) or safeIsRemoved(engagedCreature) then
    Scenario.endEngagement("target_gone")
    return false, nil
  end
  
  return true, Scenario.state.engagementLockId
end

-- End engagement (called when target dies, becomes unreachable, or explicitly cleared)
function Scenario.endEngagement(reason)
  local prevEngagement = Scenario.state.engagementLockId
  
  Scenario.state.engagementLockId = nil
  Scenario.state.engagementLockTime = 0
  Scenario.state.engagementLockHealth = 100
  Scenario.state.isEngaged = false
  
  -- Also clear target lock
  Scenario.clearTargetLock()
  
  -- Emit event
  if EventBus and EventBus.emit and prevEngagement then
    pcall(function()
      EventBus.emit("monsterai:engagement_ended", prevEngagement, reason or "unknown")
    end)
  end
end

-- Get the engaged target (or nil if not engaged)
function Scenario.getEngagedTarget()
  local isEngaged, engagedId = Scenario.isEngaged()
  if not isEngaged then return nil end
  
  if MonsterAI.Tracker and MonsterAI.Tracker.monsters[engagedId] then
    return MonsterAI.Tracker.monsters[engagedId].creature
  end
  return nil
end

-- ============================================================================
-- ZIGZAG MOVEMENT DETECTION
-- ============================================================================

function Scenario.recordMovement()
  local playerPos = player and player:getPosition()
  if not playerPos then return end
  
  local nowt = nowMs()
  local history = Scenario.state.movementHistory
  local lastRecord = Scenario.state.lastMoveRecord or 0
  if (nowt - lastRecord) < 120 then
    return
  end
  -- Avoid recording duplicate positions
  local lastEntry = history[#history]
  if lastEntry and lastEntry.x == playerPos.x and lastEntry.y == playerPos.y then
    return
  end
  
  -- Add current position
  table.insert(history, {
    x = playerPos.x,
    y = playerPos.y,
    time = nowt
  })
  Scenario.state.lastMoveRecord = nowt
  
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

-- Record movement history on player movement (improves zigzag detection accuracy)
if EventBus then
  EventBus.on("player:move", function()
    Scenario.recordMovement()
  end, 60)
end

-- ============================================================================
-- SCENARIO-AWARE PRIORITY MODIFIER (v3.0)
-- IMPROVED: Much higher stickiness bonuses for linear targeting
-- ============================================================================

-- Apply scenario-based priority modifications
function Scenario.modifyPriority(creatureId, basePriority, creatureHealth)
  local cfg = Scenario.configs[Scenario.state.type] or Scenario.configs[Scenario.TYPES.FEW]
  local modifiedPriority = basePriority
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- ENGAGEMENT LOCK BONUS (HIGHEST PRIORITY)
  -- If engaged with this target, give MASSIVE bonus
  -- ═══════════════════════════════════════════════════════════════════════════
  if creatureId == Scenario.state.engagementLockId and Scenario.state.isEngaged then
    modifiedPriority = modifiedPriority + 1000  -- MASSIVE bonus - effectively unbeatable
    
    -- Additional bonus based on health progress
    local healthDrop = (Scenario.state.engagementLockHealth or 100) - (creatureHealth or 100)
    if healthDrop > 0 then
      modifiedPriority = modifiedPriority + healthDrop * 5  -- 5 points per % health lost
    end
  end
  
  -- Target stickiness: Current target gets bonus
  if creatureId == Scenario.state.targetLockId then
    modifiedPriority = modifiedPriority + cfg.targetStickiness
    
    -- IMPROVED: Higher bonuses for low health targets (finish the kill!)
    if cfg.prioritizeFinishingKills and creatureHealth then
      if creatureHealth < 20 then
        modifiedPriority = modifiedPriority + 200  -- INCREASED from 50 to 200
      elseif creatureHealth < 35 then
        modifiedPriority = modifiedPriority + 120  -- INCREASED from 30 to 120
      elseif creatureHealth < 50 then
        modifiedPriority = modifiedPriority + 80   -- INCREASED from 15 to 80
      elseif creatureHealth < 70 then
        modifiedPriority = modifiedPriority + 40   -- NEW: bonus for wounded targets
      end
    end
    
    -- IMPROVED: Time-based stickiness (longer we've been attacking, harder to switch)
    local timeLocked = (nowMs() - (Scenario.state.targetLockTime or 0))
    if timeLocked > 2000 then
      local timeBonus = math.min(100, timeLocked / 100)  -- Up to 100 bonus after 10 seconds
      modifiedPriority = modifiedPriority + timeBonus
    end
  end
  
  -- Swarm mode: Focus lowest health to reduce mob count
  if cfg.focusLowestHealth and creatureHealth then
    local healthBonus = (100 - creatureHealth) * 0.5  -- INCREASED from 0.3 to 0.5
    modifiedPriority = modifiedPriority + healthBonus
  end
  
  -- Emergency mode: Prioritize closest high-damage monster
  if cfg.emergencyMode then
    -- Additional handling in emergency situations
    local trackerData = MonsterAI.Tracker and MonsterAI.Tracker.monsters[creatureId]
    if trackerData and trackerData.ewmaDps and trackerData.ewmaDps > 50 then
      modifiedPriority = modifiedPriority + 40  -- INCREASED from 20 to 40
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
    if lockData and lockData.creature and not safeIsDead(lockData.creature) then
      local lockedHealth = safeCreatureCall(lockData.creature, "getHealthPercent", 100)
      
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
  -- IMPROVED v3.0: Increased range from 10 to 12 for better targeting
  if MonsterAI.TargetBot and MonsterAI.TargetBot.getSortedTargets then
    candidates = MonsterAI.TargetBot.getSortedTargets({maxRange = 12})
  else
    -- Fallback to basic targeting
    local Client2 = getClient()
    local creatures = (Client2 and Client2.getSpectators) and Client2.getSpectators(playerPos, false) or (g_map and g_map.getSpectators and g_map.getSpectators(playerPos, false)) or {}
    for _, creature in ipairs(creatures) do
      if creature and isValidAliveMonster(creature) then
        local pos = safeCreatureCall(creature, "getPosition", nil)
        if pos and pos.z == playerPos.z then
          local dist = math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y))
          if dist <= 12 then  -- INCREASED from 10 to 12
            table.insert(candidates, {
              creature = creature,
              id = safeGetId(creature),
              priority = 100 - dist + (100 - safeCreatureCall(creature, "getHealthPercent", 100)) * 0.5,
              distance = dist,
              name = safeCreatureCall(creature, "getName", "unknown")
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
    local health = safeCreatureCall(candidate.creature, "getHealthPercent", 100)
    candidate.priority = Scenario.modifyPriority(candidate.id, candidate.priority, health)
  end
  
  -- Re-sort after modifications
  table.sort(candidates, function(a, b) return a.priority > b.priority end)
  
  local bestTarget = candidates[1]
  local bestHealth = safeCreatureCall(bestTarget.creature, "getHealthPercent", 100)
  
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
    if lockData and lockData.creature and not safeIsDead(lockData.creature) then
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
  if not creature then return false, "invalid", nil end
  if safeIsDead(creature) or safeIsRemoved(creature) then
    return false, "invalid", nil
  end
  
  local id = safeGetId(creature)
  if not id then return false, "invalid", nil end
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
  
  local playerPos = nil
  if player then
    local okP, pPos = pcall(function() return player:getPosition() end)
    if okP then playerPos = pPos end
  end
  local creaturePos = safeCreatureCall(creature, "getPosition", nil)
  
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
      
      local Client3 = getClient()
      local tile = (Client3 and Client3.getTile) and Client3.getTile(probe) or (g_map and g_map.getTile and g_map.getTile(probe))
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
      local Client4 = getClient()
      if Client4 and Client4.isSightClear then
        return Client4.isSightClear(playerPos, creaturePos)
      elseif g_map and g_map.isSightClear then
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
    if creature and safeIsMonster(creature) then
      local id = safeGetId(creature)
      if id and Reachability.blockedCreatures[id] then
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
  if not creature then return 0, {} end
  if safeIsDead(creature) or safeIsRemoved(creature) then
    return 0, {}
  end
  
  options = options or {}
  local cfg = TBI.config
  local breakdown = {} -- For debugging
  
  local creatureId = safeGetId(creature)
  local creatureName = safeCreatureCall(creature, "getName", "unknown")
  local creaturePos = safeCreatureCall(creature, "getPosition", nil)
  local playerPos = nil
  if player then
    local okP, pPos = pcall(function() return player:getPosition() end)
    if okP then playerPos = pPos end
  end
  
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
  local healthPct = safeCreatureCall(creature, "getHealthPercent", 100)
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
  
  local isWalking = safeCreatureCall(creature, "isWalking", false)
  if isWalking then
    local walkDir = safeCreatureCall(creature, "getWalkDirection", nil)
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
    local speed = safeCreatureCall(creature, "getSpeed", 100)
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
  local Client = getClient()
  local creatures = (Client and Client.getSpectators) and Client.getSpectators(playerPos, false) or (g_map and g_map.getSpectators and g_map.getSpectators(playerPos, false)) or {}
  
  for _, creature in ipairs(creatures) do
    if creature and isValidAliveMonster(creature) then
      local creaturePos = safeCreatureCall(creature, "getPosition", nil)
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
            id = safeGetId(creature),
            name = safeCreatureCall(creature, "getName", "unknown")
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
