--[[
  Monster Prediction Module v3.0 — Real Implementation
  
  Single Responsibility: Wave/beam attack prediction, position danger
  assessment, and confidence aggregation.
  
  Replaces the dead-code v1.0 extraction that was never wired in.
  Populates: MonsterAI.Predictor, MonsterAI.Confidence
  
  Depends on: monster_ai_core.lua, monster_patterns.lua, monster_tracking.lua
]]

-- ============================================================================
-- HELPERS (from core)
-- ============================================================================

local H = MonsterAI._helpers
local nowMs            = H.nowMs
local isCreatureValid  = H.isCreatureValid
local safeCreatureCall = H.safeCreatureCall
local safeGetId        = H.safeGetId
local safeIsDead       = H.safeIsDead

local CONST = MonsterAI.CONSTANTS

-- ============================================================================
-- PREDICTOR
-- ============================================================================

MonsterAI.Predictor = MonsterAI.Predictor or {}

--- Predict if a monster is about to use a wave attack.
-- @return isPredicted, confidence, timeToAttack
function MonsterAI.Predictor.predictWaveAttack(creature)
  if not creature then return false, 0, 999999 end
  if not isCreatureValid(creature) then return false, 0, 999999 end
  if safeIsDead(creature) then return false, 0, 999999 end

  local id = safeGetId(creature)
  if not id then return false, 0, 999999 end

  local data    = MonsterAI.Tracker.monsters[id]
  local pattern = MonsterAI.Patterns.get(safeCreatureCall(creature, "getName", "Unknown"))

  -- No wave attacks known for this species
  if not pattern.hasWaveAttack then
    return false, 0.8, 999999
  end

  -- Check if monster is facing the player (primary indicator)
  local monsterPos = safeCreatureCall(creature, "getPosition", nil)
  local monsterDir = safeCreatureCall(creature, "getDirection", 0)
  if not monsterPos then return false, 0, 999999 end

  local playerPos = nil
  if player then
    local okP, pPos = pcall(function() return player:getPosition() end)
    if okP then playerPos = pPos end
  end
  if not playerPos then return false, 0, 999999 end

  local isFacingPlayer = MonsterAI.Predictor.isFacingPosition(monsterPos, monsterDir, playerPos)
  if not isFacingPlayer then
    return false, 0.7, 999999
  end

  -- Time since last observed wave attack
  local timeSinceLastWave = 999999
  if data and data.lastAttackTime > 0 then
    timeSinceLastWave = now - data.lastAttackTime
  end

  -- Predicted cooldown
  local cooldown    = data and data.predictedWaveCooldown or pattern.waveCooldown
  local timeToAttack = math.max(0, cooldown - timeSinceLastWave)

  -- ─── CONFIDENCE CALCULATION ────────────────────────────────────────────
  local confidence = 0.5 -- base
  if data then confidence = confidence + data.confidence * 0.3 end
  if isFacingPlayer then confidence = confidence + 0.2 end
  if timeSinceLastWave > cooldown * 0.8 then confidence = confidence + 0.15 end

  -- Variance penalty (noisy observations → lower confidence)
  local function variancePenalty(d)
    if not d or not d.ewmaVariance or not d.ewmaCooldown or d.ewmaCooldown <= 0 then return 0 end
    local std   = math.sqrt(d.ewmaVariance or 0)
    local ratio = std / (d.ewmaCooldown + 1e-6)
    return math.min(CONST.EWMA.VARIANCE_PENALTY_MAX, ratio * CONST.EWMA.VARIANCE_PENALTY_SCALE)
  end

  local vp = variancePenalty(data)
  if vp > 0 then confidence = confidence * (1 - vp) end

  confidence = math.max(math.min(confidence, 0.95), 0.05)

  return timeToAttack < 500, confidence, timeToAttack
end

-- ============================================================================
-- DIRECTION HELPERS (pure functions)
-- ============================================================================

local FALLBACK_DIRS = {
  [0] = { x =  0, y = -1 },
  [1] = { x =  1, y =  0 },
  [2] = { x =  0, y =  1 },
  [3] = { x = -1, y =  0 },
  [4] = { x =  1, y = -1 },
  [5] = { x =  1, y =  1 },
  [6] = { x = -1, y =  1 },
  [7] = { x = -1, y = -1 }
}

--- Check if monster is facing a position.
function MonsterAI.Predictor.isFacingPosition(monsterPos, monsterDir, targetPos)
  local dirVec = TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.DIR_VECTORS
    and TargetCore.CONSTANTS.DIR_VECTORS[monsterDir]
  if not dirVec then dirVec = FALLBACK_DIRS[monsterDir] end
  if not dirVec then return false end

  local dx = targetPos.x - monsterPos.x
  local dy = targetPos.y - monsterPos.y

  if dirVec.x == 0 then
    return (dy * dirVec.y) > 0 and math.abs(dx) <= 1
  elseif dirVec.y == 0 then
    return (dx * dirVec.x) > 0 and math.abs(dy) <= 1
  else
    local inX = (dirVec.x > 0 and dx > 0) or (dirVec.x < 0 and dx < 0)
    local inY = (dirVec.y > 0 and dy > 0) or (dirVec.y < 0 and dy < 0)
    return inX and inY
  end
end

-- ============================================================================
-- POSITION DANGER ASSESSMENT
-- ============================================================================

--- Predict danger level for a position given nearby monsters.
-- @return dangerLevel (WAVE_DANGER enum), confidence
function MonsterAI.Predictor.predictPositionDanger(position, monsters)
  local totalDanger     = 0
  local totalConfidence = 0
  local count           = 0

  for i = 1, #monsters do
    local monster = monsters[i]
    if monster and not safeIsDead(monster) then
      local isPredicted, conf, timeToAttack = MonsterAI.Predictor.predictWaveAttack(monster)

      -- Emit wave prediction for other modules (Exeta Amp, etc.)
      if isPredicted and conf >= 0.5 and EventBus and EventBus.emit then
        pcall(function() EventBus.emit("monsterai:wave_predicted", monster, conf, timeToAttack) end)
      end

      if isPredicted and timeToAttack < 1000 then
        local mpos    = safeCreatureCall(monster, "getPosition", nil)
        local mdir    = safeCreatureCall(monster, "getDirection", 0)
        local pattern = MonsterAI.Patterns.get(safeCreatureCall(monster, "getName", "Unknown"))

        if mpos then
          local inDanger = MonsterAI.Predictor.isPositionInWavePath(
            position, mpos, mdir, pattern.waveRange, pattern.waveWidth
          )
          if inDanger then
            local urgency    = 1 - (timeToAttack / 1000)
            totalDanger     = totalDanger + (pattern.dangerLevel * urgency)
            totalConfidence = totalConfidence + conf
            count           = count + 1
          end
        end
      end
    end
  end

  if count == 0 then return CONST.WAVE_DANGER.NONE, 0.8 end

  local avgDanger     = totalDanger / count
  local avgConfidence = totalConfidence / count

  local level = CONST.WAVE_DANGER.NONE
  if avgDanger >= 3 then     level = CONST.WAVE_DANGER.CRITICAL
  elseif avgDanger >= 2 then level = CONST.WAVE_DANGER.HIGH
  elseif avgDanger >= 1 then level = CONST.WAVE_DANGER.MEDIUM
  elseif avgDanger > 0 then  level = CONST.WAVE_DANGER.LOW
  end

  return level, avgConfidence
end

--- Check if a position is in wave attack path (pure function).
function MonsterAI.Predictor.isPositionInWavePath(pos, monsterPos, monsterDir, range, width)
  range = range or 5
  width = width or 1

  local dirVec = TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.DIR_VECTORS
    and TargetCore.CONSTANTS.DIR_VECTORS[monsterDir]
  if not dirVec then dirVec = FALLBACK_DIRS[monsterDir] end
  if not dirVec then return false end

  local dx   = pos.x - monsterPos.x
  local dy   = pos.y - monsterPos.y
  local dist = math.max(math.abs(dx), math.abs(dy))

  if dist == 0 or dist > range then return false end

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
-- Aggregates confidence from multiple sources for decision making.
-- ============================================================================

MonsterAI.Confidence = MonsterAI.Confidence or {}

--- Weighted aggregation of confidence sources.
-- @param sources: array of {name, confidence, weight}
-- @return aggregated confidence (0-1)
function MonsterAI.Confidence.aggregate(sources)
  if not sources or #sources == 0 then return 0.5 end
  local weightedSum, totalWeight = 0, 0
  for i = 1, #sources do
    local s = sources[i]
    weightedSum = weightedSum + (s.confidence * s.weight)
    totalWeight = totalWeight + s.weight
  end
  if totalWeight == 0 then return 0.5 end
  return weightedSum / totalWeight
end

--- Determine if we should act based on a confidence threshold.
function MonsterAI.Confidence.shouldAct(confidence, threshold)
  threshold = threshold or CONST.CONFIDENCE.MEDIUM
  return confidence >= threshold
end

--- Map a numeric confidence to a category string.
function MonsterAI.Confidence.getCategory(confidence)
  if confidence >= CONST.CONFIDENCE.VERY_HIGH then return "VERY_HIGH"
  elseif confidence >= CONST.CONFIDENCE.HIGH   then return "HIGH"
  elseif confidence >= CONST.CONFIDENCE.MEDIUM then return "MEDIUM"
  elseif confidence >= CONST.CONFIDENCE.LOW    then return "LOW"
  else return "VERY_LOW" end
end

if MonsterAI.DEBUG then
  print("[MonsterAI] Prediction module v3.0 loaded")
end
