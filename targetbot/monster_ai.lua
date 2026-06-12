--[[
  Monster AI Analysis Module v3.0 — Orchestrator / Glue
  
  This file is the central orchestrator for the MonsterAI subsystem.
  All domain-specific logic has been decomposed into dedicated SRP modules
  (loaded via cavebot.lua BEFORE this file):
  
    monster_ai_core.lua      → Namespace, helpers, constants
    monster_patterns.lua     → Pattern persistence and lookup
    monster_tracking.lua     → Per-creature data collection and EWMA learning
    monster_prediction.lua   → Wave/beam prediction and confidence scoring
    monster_combat_feedback.lua → Adaptive targeting weight adjustment
    monster_spell_tracker.lua   → Spell/missile tracking and cooldown analysis
    auto_tuner.lua           → Behaviour classification and danger tuning
    monster_scenario.lua     → Scenario detection, engagement locks, anti-zigzag
    monster_reachability.lua → Smart unreachable creature detection
    monster_tbi.lua          → 9-stage TargetBot Intelligence priority scoring
  
  What remains in THIS file:
    - VolumeAdaptation   (load-dependent tick tuning)
    - RealTime state     (direction tracking, threat cache, prediction queue)
    - Telemetry          (OTClient extended creature snapshots)
    - Metrics            (centralized aggregator across all subsystems)
    - EventBus wiring    (connects OTClient events → MonsterAI subsystems)
    - updateAll()        (periodic tick entry-point)
    - Public API         (convenience getters for UI / debug)
    - Tick registration  (UnifiedTick / macro fallback)
  
  Architecture principles: DRY, KISS, SRP, SOLID
  See docs/TARGETBOT.md for the full design rationale.
]]

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

MonsterAI = MonsterAI or {}
MonsterAI.VERSION = "3.0"

-- BoundedPush/TrimArray are set as globals by utils/ring_buffer.lua (Phase 3)
local BoundedPush = BoundedPush
local TrimArray = TrimArray

--------------------------------------------------------------------------------
-- CLIENTSERVICE HELPERS (shared aliases)
--------------------------------------------------------------------------------
local getClient = nExBot.Shared.getClient
local getClientVersion = nExBot.Shared.getClientVersion

-- Time helper (use ClientHelper for DRY)
local nowMs = ClientHelper and ClientHelper.nowMs or function()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

-- ============================================================================
-- SAFE CREATURE VALIDATION (Prevents C++ crashes)
-- The OTClient C++ layer can crash even when methods exist if the creature
-- object is in an invalid internal state. These helpers prevent that.
-- ============================================================================

-- Delegate all safe-creature helpers to monster_ai_core (single source of truth, DRY)
local _H               = MonsterAI._helpers
local isCreatureValid  = _H.isCreatureValid
local safeCreatureCall = _H.safeCreatureCall
local safeGetId        = _H.safeGetId
local safeIsDead       = _H.safeIsDead
local safeIsMonster    = _H.safeIsMonster
local safeIsRemoved    = _H.safeIsRemoved
local isValidAliveMonster = _H.isValidAliveMonster

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
    
    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    -- ENHANCED METRICS (NEW in v2.2)
    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    
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
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- COLLECT FROM TRACKER
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  if MonsterAI.Tracker and MonsterAI.Tracker.stats then
    m.totalDamageReceived = MonsterAI.Tracker.stats.totalDamageReceived or 0
  end
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- COLLECT FROM TELEMETRY SESSION
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  if MonsterAI.Telemetry and MonsterAI.Telemetry.session then
    local session = MonsterAI.Telemetry.session
    m.totalKills = session.killCount or 0
    m.totalDeaths = session.deathCount or 0
    m.totalDamageDealt = session.totalDamageDealt or 0
  end
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- COLLECT FROM REALTIME METRICS
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  if MonsterAI.RealTime and MonsterAI.RealTime.metrics then
    local rt = MonsterAI.RealTime.metrics
    m.predictionsCorrect = rt.predictionsCorrect or 0
    m.predictionsMissed = rt.predictionsMissed or 0
    m.predictionsTotal = m.predictionsCorrect + m.predictionsMissed
    
    if m.predictionsTotal > 0 then
      m.predictionAccuracy = m.predictionsCorrect / m.predictionsTotal
    end
  end
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- COLLECT FROM COMBAT FEEDBACK
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  if MonsterAI.CombatFeedback and MonsterAI.CombatFeedback.getAccuracy then
    local acc = MonsterAI.CombatFeedback.getAccuracy()
    if acc then
      m.combatFeedbackAccuracy = acc.overall or 0
    end
  end
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- COLLECT FROM SPELL TRACKER
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  if MonsterAI.SpellTracker and MonsterAI.SpellTracker.getStats then
    local st = MonsterAI.SpellTracker.getStats()
    m.totalSpellsObserved = st.totalSpellsCast or 0
    m.spellsPerMinute = st.spellsPerMinute or 0
  end
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- COLLECT FROM VOLUME ADAPTATION
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  if MonsterAI.VolumeAdaptation and MonsterAI.VolumeAdaptation.getStats then
    local va = MonsterAI.VolumeAdaptation.getStats()
    m.currentVolume = va.currentVolume
    m.avgMonsterCount = va.metrics and va.metrics.avgMonsterCount or 0
    m.cpuCyclesSaved = va.metrics and va.metrics.adaptationsSaved or 0
  end
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- UPDATE HISTORY
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  local history = MonsterAI.Metrics.history
  
  -- Track monster count over time
  local monsterCount = 0
  if MonsterAI.Tracker and MonsterAI.Tracker.monsters then
    for _ in pairs(MonsterAI.Tracker.monsters) do
      monsterCount = monsterCount + 1
    end
  end
  BoundedPush(history.monsterCounts, {time = nowt, value = monsterCount}, MonsterAI.Metrics.MAX_HISTORY)
  
  -- Track threat level over time
  local threatLevel = 0
  if MonsterAI.RealTime and MonsterAI.RealTime.threatCache then
    threatLevel = MonsterAI.RealTime.threatCache.totalThreat or 0
  end
  BoundedPush(history.threatLevels, {time = nowt, value = threatLevel}, MonsterAI.Metrics.MAX_HISTORY)
  
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

-- ============================================================================
-- PER-CHARACTER METRICS PERSISTENCE (via UnifiedStorage)
-- Cumulative metrics survive across sessions for each character.
-- ============================================================================

local METRICS_KEY       = "targetbot.monsterMetrics.aggregate"
local TYPE_STATS_KEY    = "targetbot.monsterMetrics.typeStats"
local METRICS_SAVE_INTERVAL = 30000  -- ms between saves

-- Merge persisted cumulative metrics into current session on load
function MonsterAI.Metrics.loadPersisted()
  if not UnifiedStorage or not UnifiedStorage.get then return end
  if not UnifiedStorage.isReady or not UnifiedStorage.isReady() then return end

  local saved = UnifiedStorage.get(METRICS_KEY)
  if saved and type(saved) == "table" then
    local m = MonsterAI.Metrics.aggregate
    -- Accumulate counters from prior sessions
    m.totalDamageReceived = (m.totalDamageReceived or 0) + (saved.totalDamageReceived or 0)
    m.totalDamageDealt    = (m.totalDamageDealt or 0)    + (saved.totalDamageDealt or 0)
    m.totalKills          = (m.totalKills or 0)          + (saved.totalKills or 0)
    m.totalDeaths         = (m.totalDeaths or 0)         + (saved.totalDeaths or 0)
    m.predictionsTotal    = (m.predictionsTotal or 0)    + (saved.predictionsTotal or 0)
    m.predictionsCorrect  = (m.predictionsCorrect or 0)  + (saved.predictionsCorrect or 0)
    m.predictionsMissed   = (m.predictionsMissed or 0)   + (saved.predictionsMissed or 0)
    m.updateCyclesTotal   = (m.updateCyclesTotal or 0)   + (saved.updateCyclesTotal or 0)
    -- Recalculate derived accuracy
    if m.predictionsTotal > 0 then
      m.predictionAccuracy = m.predictionsCorrect / m.predictionsTotal
    end
  end

  -- Load typeStats
  local savedTypes = UnifiedStorage.get(TYPE_STATS_KEY)
  if savedTypes and type(savedTypes) == "table" then
    for nameLower, stats in pairs(savedTypes) do
      local existing = MonsterAI.Telemetry.typeStats[nameLower]
      if existing then
        -- Merge: accumulate counters, coerce loaded values to numbers
        existing.sampleCount      = (existing.sampleCount or 0) + (tonumber(stats.sampleCount) or 0)
        existing.killCount        = (existing.killCount or 0) + (tonumber(stats.killCount) or 0)
        existing.totalDamageDealt = (existing.totalDamageDealt or 0) + (tonumber(stats.totalDamageDealt) or 0)
        existing.totalKillTime    = (existing.totalKillTime or 0) + (tonumber(stats.totalKillTime) or 0)
        existing.waveAttackCount  = (existing.waveAttackCount or 0) + (tonumber(stats.waveAttackCount) or 0)
        -- Coerce EWMA/metadata fields to prevent nil arithmetic
        existing.avgSpeed       = tonumber(existing.avgSpeed) or 0
        existing.avgDPS         = tonumber(existing.avgDPS) or 0
        existing.avgHealthDrain = tonumber(existing.avgHealthDrain) or 0
        existing.lastSeen       = tonumber(existing.lastSeen) or 0
      else
        -- Normalize numeric fields before assigning to prevent arithmetic errors
        stats.sampleCount      = tonumber(stats.sampleCount) or 0
        stats.killCount        = tonumber(stats.killCount) or 0
        stats.totalDamageDealt = tonumber(stats.totalDamageDealt) or 0
        stats.totalKillTime    = tonumber(stats.totalKillTime) or 0
        stats.waveAttackCount  = tonumber(stats.waveAttackCount) or 0
        stats.avgSpeed         = tonumber(stats.avgSpeed) or 0
        stats.avgDPS           = tonumber(stats.avgDPS) or 0
        stats.avgHealthDrain   = tonumber(stats.avgHealthDrain) or 0
        stats.lastSeen         = tonumber(stats.lastSeen) or 0
        MonsterAI.Telemetry.typeStats[nameLower] = stats
      end
    end
  end
end

-- Save current cumulative metrics to per-character storage
function MonsterAI.Metrics.persist()
  if not UnifiedStorage or not UnifiedStorage.set then return end
  if not UnifiedStorage.isReady or not UnifiedStorage.isReady() then return end

  MonsterAI.Metrics.collect()  -- refresh aggregate first
  local m = MonsterAI.Metrics.aggregate

  local toSave = {
    totalDamageReceived = m.totalDamageReceived or 0,
    totalDamageDealt    = m.totalDamageDealt or 0,
    totalKills          = m.totalKills or 0,
    totalDeaths         = m.totalDeaths or 0,
    predictionsTotal    = m.predictionsTotal or 0,
    predictionsCorrect  = m.predictionsCorrect or 0,
    predictionsMissed   = m.predictionsMissed or 0,
    updateCyclesTotal   = m.updateCyclesTotal or 0,
    lastSaveTime        = nowMs(),
  }
  UnifiedStorage.set(METRICS_KEY, toSave)

  -- Save typeStats (strip ephemeral fields)
  local typeSnapshot = {}
  for nameLower, stats in pairs(MonsterAI.Telemetry.typeStats) do
    typeSnapshot[nameLower] = {
      name              = stats.name,
      sampleCount       = stats.sampleCount or 0,
      avgSpeed          = stats.avgSpeed or 0,
      avgDPS            = stats.avgDPS or 0,
      avgHealthDrain    = stats.avgHealthDrain or 0,
      totalDamageDealt  = stats.totalDamageDealt or 0,
      killCount         = stats.killCount or 0,
      totalKillTime     = stats.totalKillTime or 0,
      waveAttackCount   = stats.waveAttackCount or 0,
      lastSeen          = stats.lastSeen or 0,
      isRanged          = stats.isRanged,
      isMelee           = stats.isMelee,
      isAOE             = stats.isAOE,
      isSummoner        = stats.isSummoner,
      estimatedDanger   = stats.estimatedDanger,
    }
  end
  UnifiedStorage.set(TYPE_STATS_KEY, typeSnapshot)
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
-- CONST alias for remaining code (full definition in monster_ai_core.lua)
-- ============================================================================
local CONST = MonsterAI.CONSTANTS

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

-- Guard: returns true when TargetBot is disabled (used by EventBus handlers)
local function tbOff() return not TargetBot or not TargetBot.isOn or not TargetBot.isOn() end

if EventBus then
  -- Track monsters when they appear
  EventBus.on("monster:appear", function(creature)
    if tbOff() then return end
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
    if tbOff() then return end
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
    if tbOff() then return end
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
          -- Keep last 10 positions (using BoundedPush)
          BoundedPush(rt.positions, { pos = pos, time = nowMs() }, 10)
        end
      end
    end
    
    -- Also update the general tracker
    MonsterAI.Tracker.update(creature)
  end, 40)  -- High priority for instant response
  
  -- Update tracking on monster health change (potential attack indicator)
  EventBus.on("monster:health", function(creature, percent)
    if tbOff() then return end
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
    if tbOff() then return end
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

    -- Track the best monster if it wasn't already tracked (monster:appear may have been missed)
    if bestScore and bestScore > CONST.DAMAGE.CORRELATION_THRESHOLD and bestMonster and not bestData then
      MonsterAI.Tracker.track(bestMonster)
      local bid = safeGetId(bestMonster)
      bestData = bid and MonsterAI.Tracker.monsters[bid]
    end

    if bestScore and bestScore > CONST.DAMAGE.CORRELATION_THRESHOLD and bestData then
      -- Attribute this damage
      bestData.lastDamageTime = nowt
      bestData.lastAttackTime = nowt
      bestData.waveCount = (bestData.waveCount or 0) + 1
      MonsterAI.Tracker.stats.areaAttacksObserved = MonsterAI.Tracker.stats.areaAttacksObserved + 1

      -- Record damage sample for DPS calculation
      bestData.damageSamples = bestData.damageSamples or {}
      bestData.damageSamples[#bestData.damageSamples + 1] = { time = nowt, amount = damage }
      -- Trim samples older than DPS window (batch trim)
      if #bestData.damageSamples > 0 then
        local cutoff = 1
        while cutoff <= #bestData.damageSamples and (nowt - bestData.damageSamples[cutoff].time) > MonsterAI.DPS_WINDOW do
          cutoff = cutoff + 1
        end
        if cutoff > 1 then
          for i = 1, #bestData.damageSamples - cutoff + 1 do
            bestData.damageSamples[i] = bestData.damageSamples[i + cutoff - 1]
          end
          for i = #bestData.damageSamples - cutoff + 2, #bestData.damageSamples do
            bestData.damageSamples[i] = nil
          end
        end
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
      
      -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      -- COMBAT FEEDBACK INTEGRATION (NEW in v2.0)
      -- Record damage for accuracy tracking and weight adjustment
      -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
      if zChanging() then return end
      if not missle then return end
      
      local srcPos = missle:getSource()
      local destPos = missle:getDestination()
      
      if not srcPos or not destPos then return end
      
      -- Find the monster that fired (check source tile first, then nearby tiles as fallback)
      local Client = getClient()
      local srcTile = (Client and Client.getTile) and Client.getTile(srcPos) or (g_map and g_map.getTile and g_map.getTile(srcPos))
      local src = nil

      if srcTile then
        local creatures = srcTile:getCreatures()
        if creatures then
          for i = 1, #creatures do
            local c = creatures[i]
            if c and safeIsMonster(c) and not safeIsDead(c) then
              src = c; break
            end
          end
        end
      end

      -- Fallback: monster may have moved off the source tile between firing and callback
      if not src then
        local specs = g_map and g_map.getSpectatorsInRange and g_map.getSpectatorsInRange(srcPos, false, 2, 2) or {}
        local bestDist = math.huge
        for _, c in ipairs(specs) do
          if safeIsMonster(c) and not safeIsDead(c) then
            local cpos = safeCreatureCall(c, "getPosition", nil)
            if cpos then
              local d = math.max(math.abs(cpos.x - srcPos.x), math.abs(cpos.y - srcPos.y))
              if d < bestDist then bestDist = d; src = c end
            end
          end
        end
      end

      if not src then return end

      local id = safeGetId(src)
      if not id then return end

      if not MonsterAI.Tracker.monsters[id] then MonsterAI.Tracker.track(src) end
      local data = MonsterAI.Tracker.monsters[id]
      if not data then return end

      local nowt = nowMs()
      
      -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      -- SPELL TRACKER INTEGRATION (NEW in v2.2)
      -- Record spell with missile type for detailed analytics
      -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
          -- keep only last N samples (trim from end since newest is at front)
          while #pattern.samples > 30 do pattern.samples[#pattern.samples] = nil end
          MonsterAI.Patterns.persist(pname, { waveCooldown = data.ewmaCooldown, waveVariance = data.ewmaVariance, samples = pattern.samples, lastSeen = nowMs() })
        end
      end

      data.lastWaveTime = nowt
      data.observedWaveAttacks = data.observedWaveAttacks or {}
      data.observedWaveAttacks[#data.observedWaveAttacks + 1] = nowt
      -- Bound the sample history to avoid unbounded growth
      TrimArray(data.observedWaveAttacks, 100)
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
      if tbOff() then return end
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
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- NATIVE OTCLIENT TURN CALLBACK
  -- Direct hook into OTClient's onCreatureTurn for fastest direction change detection
  -- This is critical for wave attack prediction as monsters turn before attacking
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  if onCreatureTurn then
    onCreatureTurn(function(creature, direction)
      if zChanging() then return end
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
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- PLAYER ATTACK EVENT - Track engagement with monsters
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  EventBus.on("player:attack", function(target)
    if tbOff() then return end
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
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- CREATURE DEATH EVENT - Finalize tracking and collect kill stats
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  EventBus.on("creature:death", function(creature)
    if tbOff() then return end
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
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- PLAYER DEATH EVENT - Track session death stats
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  EventBus.on("player:death", function()
    if tbOff() then return end
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
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- SPELL CAST EVENT - Track player damage output for kill time calculation
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  EventBus.on("player:spell", function(spellName, target)
    if tbOff() then return end
    if not target or not target:isMonster() then return end
    
    local id = target:getId()
    if not id then return end
    
    local data = MonsterAI.Tracker.monsters[id]
    if data then
      -- Record spell usage against this monster (for DPS analysis)
      data.spellsReceived = (data.spellsReceived or 0) + 1
    end
  end, 20)
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- COMBAT STATUS CHANGES - Track when entering/leaving combat
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  EventBus.on("player:combat_start", function()
    if tbOff() then return end
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
    if tbOff() then return end
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

  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- VOLUME ADAPTATION UPDATE (NEW in v2.2)
  -- Adjust processing parameters based on monster count
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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

  -- Checksum guard: emit monsterai:state_updated only when tracked state changes.
  -- Prevents Monster Inspector (and any other subscriber) from rebuilding on silent ticks.
  local nowt = nowMs()
  local chk = 0
  if MonsterAI.Tracker and MonsterAI.Tracker.monsters then
    for id, d in pairs(MonsterAI.Tracker.monsters) do
      -- Cheap XOR-style accumulation — avoids heavy string hashing
      chk = (chk + (id % 997) + ((d.lastAttackTime or 0) % 997)) % 65521
    end
  end
  if MonsterAI.RealTime and MonsterAI.RealTime.threatCache then
    chk = (chk + math.floor((MonsterAI.RealTime.threatCache.totalThreat or 0) * 100) % 997) % 65521
  end
  if chk ~= MonsterAI._stateChecksum then
    MonsterAI._stateChecksum = chk
    if EventBus then
      pcall(function() EventBus.emit("monsterai:state_updated") end)
    end
  end

  MonsterAI.lastUpdate = nowt
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

-- Emit periodic stats update for interested modules (gated by TargetBot state)
if EventBus then
  schedule(5000, function()
    local function emitStatsUpdate()
      if not tbOff() and EventBus and EventBus.emit then
        local stats = MonsterAI.getStatsSummary()
        EventBus.emit("monsterai:stats_update", stats)
      end
      schedule(10000, emitStatsUpdate) -- Every 10 seconds
    end
    emitStatsUpdate()
  end)
end

-- Enable automatic collection by default so Monster Insights shows data without console commands
-- Collection is now gated by TargetBot.isOn() to prevent CPU waste when targeting is off
MonsterAI.COLLECT_ENABLED = (MonsterAI.COLLECT_ENABLED == nil) and true or MonsterAI.COLLECT_ENABLED

-- Helper: check if MonsterAI should actively process (respects TargetBot state)
local function shouldCollect()
  if not MonsterAI.COLLECT_ENABLED then return false end
  -- Gate by TargetBot state: no point collecting data if targeting is off
  if TargetBot and TargetBot.isOn and not TargetBot.isOn() then return false end
  return true
end

-- ============================================================================
-- UNIFIED TICK INTEGRATION (Performance: consolidates macro overhead)
-- Uses UnifiedTick system if available, falls back to individual macros
-- ============================================================================

if UnifiedTick and UnifiedTick.register then
  -- Periodic background updater (500ms) - NORMAL priority
  UnifiedTick.register({
    id = "monsterai_update",
    interval = 500,
    priority = UnifiedTick.PRIORITY and UnifiedTick.PRIORITY.NORMAL or 50,
    callback = function()
      if shouldCollect() and MonsterAI.updateAll then
        pcall(function() MonsterAI.updateAll() end)
      end
    end
  })
  
  -- Auto-tuner periodic pass (30000ms) - IDLE priority
  UnifiedTick.register({
    id = "monsterai_autotune",
    interval = 30000,
    priority = UnifiedTick.PRIORITY and UnifiedTick.PRIORITY.IDLE or 10,
    callback = function()
      if not shouldCollect() then return end
      if MonsterAI.AUTO_TUNE_ENABLED and MonsterAI.AutoTuner and MonsterAI.AutoTuner.runPass then
        pcall(function() MonsterAI.AutoTuner.runPass() end)
      end
      pcall(function() MonsterAI.Metrics.persist() end)
    end
  })
else
  -- Fallback to traditional macros if UnifiedTick not loaded
  macro(500, function()
    if zChanging() then
      return
    end
    if shouldCollect() and MonsterAI.updateAll then
      pcall(function() MonsterAI.updateAll() end)
    end
  end)
  
  macro(30000, function()
    if zChanging() then
      return
    end
    if not shouldCollect() then return end
    if MonsterAI.AUTO_TUNE_ENABLED and MonsterAI.AutoTuner and MonsterAI.AutoTuner.runPass then
      pcall(function() MonsterAI.AutoTuner.runPass() end)
    end
    pcall(function() MonsterAI.Metrics.persist() end)
  end)
end

-- NOTE: TBI.getBestTarget emission is handled exclusively in monster_tbi.lua
-- Removed duplicate schedule chain that was here (Phase 1.3 fix)

-- Toggle to enable debug prints
MonsterAI.DEBUG = MonsterAI.DEBUG or false
if MonsterAI.DEBUG then print("[MonsterAI] Monster AI Analysis Module v" .. MonsterAI.VERSION .. " loaded; automatic collection=" .. tostring(MonsterAI.COLLECT_ENABLED) .. "; auto-tune=" .. tostring(MonsterAI.AUTO_TUNE_ENABLED)) end

-- Load persisted per-character metrics (deferred until UnifiedStorage is ready)
if UnifiedStorage and UnifiedStorage.onReady then
  UnifiedStorage.onReady(function()
    pcall(function() MonsterAI.Metrics.loadPersisted() end)
  end)
else
  schedule(3000, function()
    pcall(function() MonsterAI.Metrics.loadPersisted() end)
  end)
end
