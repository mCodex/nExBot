--[[
  Monster Auto-Tuner Module v3.0 — Real Implementation
  
  Single Responsibility: Monster behavior classification and
  automatic danger-level tuning based on observed data.
  
  Replaces the dead-code v1.0 extraction that was never wired in.
  Populates: MonsterAI.Classifier, MonsterAI.AutoTuner
  
  Depends on: monster_ai_core.lua, monster_patterns.lua, monster_tracking.lua
]]

local H = MonsterAI._helpers
local nowMs = H.nowMs

local CONST = MonsterAI.CONSTANTS

-- ============================================================================
-- CLASSIFIER
-- ============================================================================

MonsterAI.Classifier = MonsterAI.Classifier or {
  THRESHOLDS = {
    RANGED_DISTANCE   = 4,
    MELEE_DISTANCE    = 2,
    HIGH_DPS          = 50,
    FAST_SPEED        = 250,
    SLOW_SPEED        = 120,
    WAVE_FREQUENT     = 0.3,
    SUMMON_THRESHOLD  = 2
  },
  cache = {}
}

function MonsterAI.Classifier.classify(name, data)
  if not name or not data then return nil end
  local nameLower = name:lower()
  local existing  = MonsterAI.Classifier.cache[nameLower]
  if (data.movementSamples or 0) < 15 then return existing end

  local C = existing or {
    name = name, confidence = 0, lastUpdated = 0,
    isRanged = false, isMelee = true, isWaveAttacker = false,
    isAOE = false, isSummoner = false, isFast = false, isSlow = false,
    isAggressive = false, isPassive = false,
    preferredDistance = 1, estimatedDanger = 1,
    attackCooldown = 2000, movementPattern = 2, scores = {}
  }

  local nowt = nowMs()
  local T    = MonsterAI.Classifier.THRESHOLDS
  local MOVE = CONST.MOVEMENT_PATTERN

  -- Speed
  local spd = data.avgSpeed or 0
  C.isFast = spd >= T.FAST_SPEED
  C.isSlow = spd <= T.SLOW_SPEED and spd > 0

  -- Distance preference
  local stRatio = (data.stationaryCount or 0) / math.max(1, data.movementSamples)
  local chRatio = (data.chaseCount or 0) / math.max(1, data.movementSamples - (data.stationaryCount or 0))

  if stRatio > 0.5 and (data.waveCount or 0) > 3 then
    C.isRanged = true; C.isMelee = false; C.preferredDistance = 4
  elseif stRatio > 0.6 and chRatio < 0.3 then
    C.isRanged = true; C.isMelee = false; C.preferredDistance = 5
  elseif chRatio > 0.6 then
    C.isMelee = true; C.isRanged = false; C.preferredDistance = 1
  end

  -- Wave
  local obsTime  = (nowt - (data.trackingStartTime or nowt)) / 1000
  local waveRate = (data.waveCount or 0) / math.max(1, obsTime)
  if waveRate >= T.WAVE_FREQUENT or (data.waveCount or 0) >= 3 then
    C.isWaveAttacker = true; C.isAOE = true
  end
  if data.ewmaCooldown and data.ewmaCooldown > 0 then C.attackCooldown = data.ewmaCooldown end

  -- Aggressiveness
  local facingR = (data.facingCount or 0) / math.max(1, data.movementSamples)
  if facingR > 0.4 and (data.waveCount or 0) > 2 then C.isAggressive = true; C.isPassive = false
  elseif facingR < 0.2 and (data.waveCount or 0) == 0 then C.isPassive = true; C.isAggressive = false end

  -- Movement pattern
  if stRatio > 0.8 then C.movementPattern = MOVE.STATIC
  elseif chRatio > 0.6 then C.movementPattern = MOVE.CHASE
  elseif stRatio > 0.4 and C.isRanged then C.movementPattern = MOVE.KITE
  elseif chRatio < 0.3 and stRatio < 0.3 then C.movementPattern = MOVE.ERRATIC
  else C.movementPattern = MOVE.CHASE end

  -- Danger
  local danger = 1
  local dps = MonsterAI.Tracker.getDPS and MonsterAI.Tracker.getDPS(data.id) or 0
  if dps > T.HIGH_DPS then danger = danger + 2
  elseif dps > T.HIGH_DPS / 2 then danger = danger + 1 end
  if C.isWaveAttacker then danger = danger + 1; if waveRate > 0.5 then danger = danger + 1 end end
  if C.isFast then danger = danger + 0.5 end
  if C.isAggressive then danger = danger + 0.5 end
  C.estimatedDanger = math.min(danger, 4)

  C.confidence   = math.min(0.95, 0.3 + (data.movementSamples / 100) * 0.65)
  C.lastUpdated  = nowt
  C.scores = { stationaryRatio = stRatio, chaseRatio = chRatio, facingRatio = facingR,
               waveRate = waveRate, dps = dps, avgSpeed = spd }

  MonsterAI.Classifier.cache[nameLower] = C
  if EventBus and EventBus.emit then EventBus.emit("monsterai:classified", name, C) end
  return C
end

function MonsterAI.Classifier.get(name)
  if not name then return nil end
  return MonsterAI.Classifier.cache[name:lower()]
end

-- ============================================================================
-- AUTO-TUNER
-- ============================================================================

MonsterAI.AutoTuner = MonsterAI.AutoTuner or {
  enabled      = true,
  lastTuneTime = 0,
  tuneInterval = 30000,
  suggestions  = {},
  history      = {}
}

function MonsterAI.AutoTuner.suggestDanger(name)
  if not name then return nil end
  local nameLower      = name:lower()
  local classification = MonsterAI.Classifier.get(name)
  local typeStats      = MonsterAI.Telemetry and MonsterAI.Telemetry.getTypeSummary and MonsterAI.Telemetry.getTypeSummary(name) or nil
  local pattern        = MonsterAI.Patterns.get(name)
  if not classification and not typeStats then return nil end

  local suggestion = {
    name = name, timestamp = nowMs(),
    currentDanger   = (pattern and pattern.dangerLevel) or 2,
    suggestedDanger = 2, confidence = 0, reasons = {}
  }

  local danger  = 2
  local reasons = {}

  if classification then
    danger = classification.estimatedDanger or 2
    suggestion.confidence = classification.confidence or 0.5
    if classification.isWaveAttacker then reasons[#reasons+1] = "Uses wave/beam attacks" end
    if classification.isAggressive   then reasons[#reasons+1] = "Aggressive behavior" end
    if classification.isFast         then reasons[#reasons+1] = "High mobility" end
  end

  if typeStats and typeStats.avgDPS then
    if typeStats.avgDPS > 80 then danger = math.max(danger, 4); reasons[#reasons+1] = string.format("Very high DPS (%.0f)", typeStats.avgDPS)
    elseif typeStats.avgDPS > 50 then danger = math.max(danger, 3); reasons[#reasons+1] = string.format("High DPS (%.0f)", typeStats.avgDPS)
    elseif typeStats.avgDPS > 25 then danger = math.max(danger, 2) end
  end

  if pattern and pattern.waveCooldown and pattern.waveCooldown < 2000 then
    danger = math.max(danger, 3)
    reasons[#reasons+1] = string.format("Fast wave cooldown (%dms)", math.floor(pattern.waveCooldown))
  end

  if typeStats and (typeStats.totalDamageDealt or 0) > 0 then
    local avg = typeStats.totalDamageDealt / math.max(1, typeStats.sampleCount or 1)
    if avg > 500 then danger = math.max(danger, 4); reasons[#reasons+1] = string.format("High damage per encounter (%.0f avg)", avg)
    elseif avg > 200 then danger = math.max(danger, 3) end
  end

  suggestion.suggestedDanger = math.min(4, math.max(1, math.floor(danger + 0.5)))
  suggestion.reasons         = reasons
  suggestion.confidence      = math.min(0.95, (suggestion.confidence or 0.5) + #reasons * 0.1)
  MonsterAI.AutoTuner.suggestions[nameLower] = suggestion
  if EventBus and EventBus.emit then EventBus.emit("monsterai:danger_suggestion", name, suggestion) end
  return suggestion
end

function MonsterAI.AutoTuner.applyDangerSuggestion(name, force)
  if not name then return false end
  local nameLower  = name:lower()
  local suggestion = MonsterAI.AutoTuner.suggestions[nameLower]
  if not suggestion then suggestion = MonsterAI.AutoTuner.suggestDanger(name) end
  if not suggestion then return false end
  if suggestion.confidence < 0.5 and not force then return false end

  MonsterAI.Patterns.persist(nameLower, {
    dangerLevel  = suggestion.suggestedDanger,
    autoTuned    = true,
    autoTuneTime = nowMs()
  })

  table.insert(MonsterAI.AutoTuner.history, {
    name = name, oldDanger = suggestion.currentDanger,
    newDanger = suggestion.suggestedDanger, timestamp = nowMs(),
    reasons = suggestion.reasons
  })
  TrimArray(MonsterAI.AutoTuner.history, 100)

  if MonsterAI.RealTime and MonsterAI.RealTime.metrics then
    MonsterAI.RealTime.metrics.autoTuneAdjustments = (MonsterAI.RealTime.metrics.autoTuneAdjustments or 0) + 1
  end
  return true
end

function MonsterAI.AutoTuner.runPass()
  if not MonsterAI.AUTO_TUNE_ENABLED then return end
  local nowt = nowMs()
  if (nowt - MonsterAI.AutoTuner.lastTuneTime) < MonsterAI.AutoTuner.tuneInterval then return end
  MonsterAI.AutoTuner.lastTuneTime = nowt

  local seen = {}
  for _, data in pairs(MonsterAI.Tracker.monsters) do
    if data.name and not seen[data.name:lower()] then
      seen[data.name:lower()] = true
      MonsterAI.Classifier.classify(data.name, data)
      local s = MonsterAI.AutoTuner.suggestDanger(data.name)
      if s and s.confidence >= 0.7 and math.abs(s.suggestedDanger - s.currentDanger) >= 1 then
        MonsterAI.AutoTuner.applyDangerSuggestion(data.name, false)
      end
    end
  end
end

function MonsterAI.AutoTuner.getSuggestions() return MonsterAI.AutoTuner.suggestions end
function MonsterAI.AutoTuner.getHistory()     return MonsterAI.AutoTuner.history end

if MonsterAI.DEBUG then print("[MonsterAI] AutoTuner module v3.0 loaded") end
