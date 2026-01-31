--[[
  Monster Auto-Tuner Module - Extracted from monster_ai.lua
  
  Single Responsibility: Classify monsters and auto-tune danger levels.
  
  This module handles:
  - Monster behavior classification
  - Danger level suggestions
  - Automatic TargetBot configuration tuning
  - Pattern learning and persistence
  
  Depends on: monster_tracking.lua, EventBus
  Used by: targetbot/target.lua
]]

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

local AutoTuner = {}
AutoTuner.VERSION = "1.0"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

AutoTuner.CONFIG = {
  TUNE_INTERVAL = 30000,       -- 30 seconds between auto-tunes
  MIN_SAMPLES = 15,            -- Minimum samples for classification
  MIN_CONFIDENCE = 0.5,        -- Minimum confidence to apply suggestion
  HIGH_CONFIDENCE = 0.7,       -- High confidence auto-apply threshold
  HISTORY_MAX = 100,           -- Max tuning history entries
  
  -- Classification thresholds
  THRESHOLDS = {
    RANGED_DISTANCE = 4,
    MELEE_DISTANCE = 2,
    HIGH_DPS = 50,
    FAST_SPEED = 250,
    SLOW_SPEED = 120,
    WAVE_FREQUENT = 0.3,
    SUMMON_THRESHOLD = 2
  },
  
  -- Movement patterns
  MOVEMENT_PATTERN = {
    STATIC = 1,
    CHASE = 2,
    KITE = 3,
    ERRATIC = 4,
    PATROL = 5
  },
  
  -- Danger levels
  DANGER = {
    NONE = 0,
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3,
    CRITICAL = 4
  }
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
-- STATE
-- ============================================================================

AutoTuner.enabled = true
AutoTuner.lastTuneTime = 0

-- Classification cache: monsterName -> classification
AutoTuner.classifications = {}

-- Danger suggestions: monsterName -> suggestion
AutoTuner.suggestions = {}

-- Tuning history
AutoTuner.history = {}

-- Known monster patterns (persisted)
AutoTuner.patterns = {}

-- ============================================================================
-- PATTERN STORAGE
-- ============================================================================

-- Get patterns from storage
local function getStoredPatterns()
  if UnifiedStorage and UnifiedStorage.isReady and UnifiedStorage.isReady() then
    return UnifiedStorage.get("targetbot.monsterPatterns") or {}
  end
  return storage and storage.monsterPatterns or {}
end

-- Save patterns to storage
local function setStoredPatterns(patterns)
  if UnifiedStorage and UnifiedStorage.isReady and UnifiedStorage.isReady() then
    UnifiedStorage.set("targetbot.monsterPatterns", patterns)
    if EventBus and EventBus.emit then
      EventBus.emit("autoTuner:patternsUpdated", patterns)
    end
  end
  if storage then
    storage.monsterPatterns = patterns
  end
end

-- Initialize patterns from storage
function AutoTuner.loadPatterns()
  AutoTuner.patterns = getStoredPatterns()
end

-- Get pattern for a monster
function AutoTuner.getPattern(monsterName)
  if not monsterName then return nil end
  return AutoTuner.patterns[monsterName:lower()]
end

-- Save pattern for a monster
function AutoTuner.savePattern(monsterName, pattern)
  if not monsterName then return end
  
  local nameLower = monsterName:lower()
  AutoTuner.patterns[nameLower] = pattern
  
  local storedPatterns = getStoredPatterns()
  storedPatterns[nameLower] = pattern
  setStoredPatterns(storedPatterns)
  
  if EventBus and EventBus.emit then
    EventBus.emit("autoTuner:patternSaved", monsterName, pattern)
  end
end

-- Partial update to a pattern
function AutoTuner.updatePattern(monsterName, updates)
  if not monsterName then return end
  
  local nameLower = monsterName:lower()
  AutoTuner.patterns[nameLower] = AutoTuner.patterns[nameLower] or {}
  
  for k, v in pairs(updates) do
    AutoTuner.patterns[nameLower][k] = v
  end
  
  AutoTuner.savePattern(monsterName, AutoTuner.patterns[nameLower])
end

-- ============================================================================
-- CLASSIFICATION
-- ============================================================================

--[[
  Classify monster behavior based on tracking data
  @param monsterName string Monster name
  @param trackingData table Tracking data from MonsterTracking
  @return table classification or nil
]]
function AutoTuner.classify(monsterName, trackingData)
  if not monsterName or not trackingData then return nil end
  
  local nameLower = monsterName:lower()
  local existing = AutoTuner.classifications[nameLower]
  
  -- Require minimum samples
  if (trackingData.movementSamples or 0) < AutoTuner.CONFIG.MIN_SAMPLES then
    return existing
  end
  
  local config = AutoTuner.CONFIG
  local thresholds = config.THRESHOLDS
  local MOVE = config.MOVEMENT_PATTERN
  local nowt = nowMs()
  
  local classification = existing or {
    name = monsterName,
    confidence = 0,
    lastUpdated = 0,
    
    -- Behavior types
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
    movementPattern = MOVE.CHASE,
    
    scores = {}
  }
  
  -- Speed classification
  local avgSpeed = trackingData.avgSpeed or 0
  classification.isFast = avgSpeed >= thresholds.FAST_SPEED
  classification.isSlow = avgSpeed <= thresholds.SLOW_SPEED and avgSpeed > 0
  
  -- Distance preference
  local stationaryRatio = (trackingData.stationaryCount or 0) / math.max(1, trackingData.movementSamples)
  local chaseRatio = (trackingData.chaseCount or 0) / math.max(1, trackingData.movementSamples - (trackingData.stationaryCount or 0))
  
  if stationaryRatio > 0.5 and (trackingData.waveCount or 0) > 3 then
    classification.isRanged = true
    classification.isMelee = false
    classification.preferredDistance = 4
  elseif stationaryRatio > 0.6 and chaseRatio < 0.3 then
    classification.isRanged = true
    classification.isMelee = false
    classification.preferredDistance = 5
  elseif chaseRatio > 0.6 then
    classification.isMelee = true
    classification.isRanged = false
    classification.preferredDistance = 1
  end
  
  -- Wave attack classification
  local observationTime = (nowt - (trackingData.trackingStartTime or nowt)) / 1000
  local waveRate = (trackingData.waveCount or 0) / math.max(1, observationTime)
  
  if waveRate >= thresholds.WAVE_FREQUENT or (trackingData.waveCount or 0) >= 3 then
    classification.isWaveAttacker = true
    classification.isAOE = true
  end
  
  if trackingData.ewmaCooldown and trackingData.ewmaCooldown > 0 then
    classification.attackCooldown = trackingData.ewmaCooldown
  end
  
  -- Aggressiveness
  local facingRatio = (trackingData.facingCount or 0) / math.max(1, trackingData.movementSamples)
  
  if facingRatio > 0.4 and (trackingData.waveCount or 0) > 2 then
    classification.isAggressive = true
    classification.isPassive = false
  elseif facingRatio < 0.2 and (trackingData.waveCount or 0) == 0 then
    classification.isPassive = true
    classification.isAggressive = false
  end
  
  -- Movement pattern
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
  
  -- Danger estimation
  local danger = 1
  
  local dps = trackingData.totalDamage / math.max(1, observationTime)
  if dps > thresholds.HIGH_DPS then
    danger = danger + 2
  elseif dps > thresholds.HIGH_DPS / 2 then
    danger = danger + 1
  end
  
  if classification.isWaveAttacker then
    danger = danger + 1
    if waveRate > 0.5 then danger = danger + 1 end
  end
  
  if classification.isFast then danger = danger + 0.5 end
  if classification.isAggressive then danger = danger + 0.5 end
  
  classification.estimatedDanger = math.min(danger, config.DANGER.CRITICAL)
  
  -- Confidence based on sample count
  classification.confidence = math.min(0.95, 0.3 + (trackingData.movementSamples / 100) * 0.65)
  classification.lastUpdated = nowt
  
  -- Scores for debugging
  classification.scores = {
    stationaryRatio = stationaryRatio,
    chaseRatio = chaseRatio,
    facingRatio = facingRatio,
    waveRate = waveRate,
    dps = dps,
    avgSpeed = avgSpeed
  }
  
  -- Cache
  AutoTuner.classifications[nameLower] = classification
  
  -- Emit event
  if EventBus and EventBus.emit then
    EventBus.emit("autoTuner:classified", monsterName, classification)
  end
  
  return classification
end

-- Get cached classification
function AutoTuner.getClassification(monsterName)
  if not monsterName then return nil end
  return AutoTuner.classifications[monsterName:lower()]
end

-- ============================================================================
-- DANGER SUGGESTIONS
-- ============================================================================

--[[
  Generate danger level suggestion for a monster
  @param monsterName string Monster name
  @param trackingData table (optional) Tracking data
  @return table suggestion or nil
]]
function AutoTuner.suggestDanger(monsterName, trackingData)
  if not monsterName then return nil end
  
  local nameLower = monsterName:lower()
  local classification = AutoTuner.getClassification(monsterName)
  local pattern = AutoTuner.getPattern(monsterName)
  local config = AutoTuner.CONFIG
  
  if not classification and not trackingData then return nil end
  
  local suggestion = {
    name = monsterName,
    timestamp = nowMs(),
    currentDanger = (pattern and pattern.dangerLevel) or config.DANGER.MEDIUM,
    suggestedDanger = config.DANGER.MEDIUM,
    confidence = 0,
    reasons = {}
  }
  
  local danger = config.DANGER.MEDIUM
  local reasons = {}
  
  -- Classification-based danger
  if classification then
    danger = classification.estimatedDanger or config.DANGER.MEDIUM
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
  
  -- Tracking data DPS
  if trackingData and trackingData.totalDamage then
    local observationTime = (nowMs() - (trackingData.trackingStartTime or nowMs())) / 1000
    local dps = trackingData.totalDamage / math.max(1, observationTime)
    
    if dps > 80 then
      danger = math.max(danger, config.DANGER.CRITICAL)
      table.insert(reasons, string.format("Very high DPS (%.0f)", dps))
    elseif dps > 50 then
      danger = math.max(danger, config.DANGER.HIGH)
      table.insert(reasons, string.format("High DPS (%.0f)", dps))
    end
  end
  
  -- Pattern-based factors
  if pattern and pattern.waveCooldown and pattern.waveCooldown < 2000 then
    danger = math.max(danger, config.DANGER.HIGH)
    table.insert(reasons, string.format("Fast wave cooldown (%dms)", math.floor(pattern.waveCooldown)))
  end
  
  suggestion.suggestedDanger = math.min(config.DANGER.CRITICAL, math.max(config.DANGER.LOW, math.floor(danger + 0.5)))
  suggestion.reasons = reasons
  suggestion.confidence = math.min(0.95, (suggestion.confidence or 0.5) + #reasons * 0.1)
  
  -- Store suggestion
  AutoTuner.suggestions[nameLower] = suggestion
  
  -- Emit event
  if EventBus and EventBus.emit then
    EventBus.emit("autoTuner:dangerSuggestion", monsterName, suggestion)
  end
  
  return suggestion
end

--[[
  Apply a danger suggestion
  @param monsterName string Monster name
  @param force boolean Force apply even with low confidence
  @return boolean success
]]
function AutoTuner.applySuggestion(monsterName, force)
  if not monsterName then return false end
  
  local nameLower = monsterName:lower()
  local suggestion = AutoTuner.suggestions[nameLower]
  
  if not suggestion then
    suggestion = AutoTuner.suggestDanger(monsterName)
  end
  
  if not suggestion then return false end
  
  -- Check confidence
  if suggestion.confidence < AutoTuner.CONFIG.MIN_CONFIDENCE and not force then
    return false
  end
  
  -- Apply to pattern
  AutoTuner.updatePattern(monsterName, {
    dangerLevel = suggestion.suggestedDanger,
    autoTuned = true,
    autoTuneTime = nowMs()
  })
  
  -- Record in history
  table.insert(AutoTuner.history, {
    name = monsterName,
    oldDanger = suggestion.currentDanger,
    newDanger = suggestion.suggestedDanger,
    timestamp = nowMs(),
    reasons = suggestion.reasons
  })
  
  -- Trim history (using TrimArray for O(1) amortized)
  TrimArray(AutoTuner.history, AutoTuner.CONFIG.HISTORY_MAX)
  
  return true
end

-- ============================================================================
-- AUTO-TUNING PASS
-- ============================================================================

--[[
  Run auto-tuning on tracked monsters
  @param trackingData table All monster tracking data
]]
function AutoTuner.runPass(trackingData)
  if not AutoTuner.enabled then return end
  
  local nowt = nowMs()
  if (nowt - AutoTuner.lastTuneTime) < AutoTuner.CONFIG.TUNE_INTERVAL then
    return
  end
  
  AutoTuner.lastTuneTime = nowt
  trackingData = trackingData or {}
  
  local processedNames = {}
  
  for id, data in pairs(trackingData) do
    if data.name and not processedNames[data.name:lower()] then
      processedNames[data.name:lower()] = true
      
      -- Classify
      AutoTuner.classify(data.name, data)
      
      -- Suggest danger
      local suggestion = AutoTuner.suggestDanger(data.name, data)
      
      -- Auto-apply if high confidence and significant change
      if suggestion and suggestion.confidence >= AutoTuner.CONFIG.HIGH_CONFIDENCE then
        local changeMagnitude = math.abs(suggestion.suggestedDanger - suggestion.currentDanger)
        if changeMagnitude >= 1 then
          AutoTuner.applySuggestion(data.name, false)
        end
      end
    end
  end
end

-- ============================================================================
-- STATISTICS
-- ============================================================================

function AutoTuner.getStats()
  local classificationCount = 0
  for _ in pairs(AutoTuner.classifications) do
    classificationCount = classificationCount + 1
  end
  
  local suggestionCount = 0
  for _ in pairs(AutoTuner.suggestions) do
    suggestionCount = suggestionCount + 1
  end
  
  return {
    enabled = AutoTuner.enabled,
    classificationCount = classificationCount,
    suggestionCount = suggestionCount,
    historyCount = #AutoTuner.history,
    lastTuneTime = AutoTuner.lastTuneTime
  }
end

function AutoTuner.getSuggestions()
  return AutoTuner.suggestions
end

function AutoTuner.getHistory()
  return AutoTuner.history
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Load patterns on module load
AutoTuner.loadPatterns()

return AutoTuner
