--[[
  Monster Tracking Module v3.0 — Real Implementation
  
  Single Responsibility: Per-creature data collection, EWMA learning,
  DPS calculation, and sample management.
  
  This replaces the dead-code v1.0 extraction that was never wired in.
  All code now writes directly to MonsterAI.Tracker (the REAL tracker).
  
  Depends on: monster_ai_core.lua, monster_patterns.lua
  Populates: MonsterAI.Tracker
]]

-- ============================================================================
-- HELPERS (from core)
-- ============================================================================

-- BoundedPush/TrimArray are set as globals by utils/ring_buffer.lua (Phase 3)
local BoundedPush = BoundedPush
local TrimArray = TrimArray

local H = MonsterAI._helpers
local nowMs            = H.nowMs
local getClient        = H.getClient
local isCreatureValid  = H.isCreatureValid
local safeCreatureCall = H.safeCreatureCall
local safeGetId        = H.safeGetId
local safeIsDead       = H.safeIsDead
local safeIsRemoved    = H.safeIsRemoved

local CONST = MonsterAI.CONSTANTS

-- ============================================================================
-- TRACKER STATE
-- ============================================================================

MonsterAI.Tracker = MonsterAI.Tracker or {
  monsters = {},
  stats = {
    waveAttacksObserved = 0,
    areaAttacksObserved = 0,
    totalDamageReceived = 0,
    avoidanceSuccesses  = 0,
    avoidanceFailures   = 0
  }
}

-- ============================================================================
-- TRACK / UNTRACK
-- ============================================================================

function MonsterAI.Tracker.track(creature)
  if not creature then return end
  if not isCreatureValid(creature) then return end
  if safeIsDead(creature) then return end

  local id = safeGetId(creature)
  if not id then return end
  if MonsterAI.Tracker.monsters[id] then return end

  local pos = safeCreatureCall(creature, "getPosition", nil)
  if not pos then return end

  local nowt = nowMs()

  -- Collect initial telemetry snapshot if available
  local initialSnapshot = MonsterAI.Telemetry
    and MonsterAI.Telemetry.collectSnapshot
    and MonsterAI.Telemetry.collectSnapshot(creature) or nil

  MonsterAI.Tracker.monsters[id] = {
    creature       = creature,
    id             = id,
    name           = safeCreatureCall(creature, "getName", "Unknown"),
    samples        = {},
    lastDirection  = safeCreatureCall(creature, "getDirection", 0),
    lastPosition   = { x = pos.x, y = pos.y, z = pos.z },
    lastSampleTime = nowt,
    lastAttackTime = 0,
    lastWaveTime   = 0,
    attackCount    = 0,
    directionChanges  = 0,
    movementSamples   = 0,
    stationaryCount   = 0,
    chaseCount        = 0,
    observedWaveAttacks = {},
    waveCount          = 0,
    trackingStartTime  = nowt,

    -- Telemetry
    damageSamples = {},
    totalDamage   = 0,
    missileCount  = 0,
    facingCount   = 0,
    avgSpeed      = initialSnapshot and initialSnapshot.speed or 0,
    baseSpeed     = initialSnapshot and initialSnapshot.baseSpeed or 0,

    -- Walk pattern tracking
    walkSamples     = {},
    avgStepDuration = 0,
    walkingRatio    = 0,

    -- Health tracking
    healthSamples    = {},
    lastHealthPercent = safeCreatureCall(creature, "getHealthPercent", 100),
    healthChangeRate  = 0,

    -- Direction pattern tracking
    directionHistory = {},
    turnFrequency    = 0,

    -- Distance tracking
    distanceSamples        = {},
    avgDistanceFromPlayer  = 0,
    preferredDistance       = nil,

    -- Engagement metrics
    engagementStart      = nil,
    engagementDuration   = 0,
    damageDealtToMonster = 0,

    -- EWMA estimator for wave cooldown
    ewmaCooldown          = nil,
    ewmaVariance          = 0,
    ewmaAlpha             = 0.3,
    predictedWaveCooldown = nil,
    confidence            = 0.1
  }

  -- Update session stats
  if MonsterAI.Telemetry and MonsterAI.Telemetry.session then
    MonsterAI.Telemetry.session.totalMonstersTracked =
      (MonsterAI.Telemetry.session.totalMonstersTracked or 0) + 1
  end

  if EventBus and EventBus.emit then
    pcall(function() EventBus.emit("monsterai:tracking_started", creature, id) end)
  end
end

function MonsterAI.Tracker.untrack(creatureId)
  local data = MonsterAI.Tracker.monsters[creatureId]

  if data then
    -- Update type statistics before removing
    if MonsterAI.Telemetry and MonsterAI.Telemetry.updateTypeStats then
      MonsterAI.Telemetry.updateTypeStats(data.name, {
        avgSpeed    = data.avgSpeed,
        dps         = MonsterAI.Tracker.getDPS and MonsterAI.Tracker.getDPS(creatureId) or 0,
        totalDamage = data.totalDamage,
        waveCount   = data.waveCount
      })
    end

    -- Classify monster if enough data
    if data.movementSamples >= 10 and MonsterAI.Classifier and MonsterAI.Classifier.classify then
      MonsterAI.Classifier.classify(data.name, data)
    end

    -- Check if this was a kill
    if data.creature and safeIsDead(data.creature) then
      if MonsterAI.Telemetry and MonsterAI.Telemetry.session then
        MonsterAI.Telemetry.session.killCount =
          (MonsterAI.Telemetry.session.killCount or 0) + 1

        if data.engagementStart then
          local killTime = nowMs() - data.engagementStart
          local session  = MonsterAI.Telemetry.session
          session.avgKillTime = session.avgKillTime * 0.8 + killTime * 0.2
        end
      end

      if EventBus and EventBus.emit then
        EventBus.emit("monsterai:monster_killed", data.name, creatureId, {
          engagementDuration = data.engagementDuration,
          damageReceived     = data.totalDamage,
          waveAttacks        = data.waveCount
        })
      end
    end

    -- Clean up SpellTracker data
    if MonsterAI.SpellTracker and MonsterAI.SpellTracker.cleanup then
      MonsterAI.SpellTracker.cleanup(creatureId)
    end
  end

  MonsterAI.Tracker.monsters[creatureId] = nil
  if MonsterAI.Telemetry and MonsterAI.Telemetry.snapshots then
    MonsterAI.Telemetry.snapshots[creatureId] = nil
  end
end

-- ============================================================================
-- UPDATE (per-creature tick)
-- ============================================================================

function MonsterAI.Tracker.update(creature)
  if not creature then return end
  if not isCreatureValid(creature) then return end
  if safeIsDead(creature) then return end

  local id = safeGetId(creature)
  if not id then return end

  local data = MonsterAI.Tracker.monsters[id]
  if not data then
    MonsterAI.Tracker.track(creature)
    return
  end

  local currentTime = now
  local nowt = nowMs()
  local pos  = safeCreatureCall(creature, "getPosition", nil)
  if not pos then return end

  local dir = safeCreatureCall(creature, "getDirection", 0)
  local hp  = safeCreatureCall(creature, "getHealthPercent", 100)

  -- ─── CORE SAMPLE COLLECTION ───────────────────────────────────────────
  local sample = {
    time   = currentTime,
    pos    = { x = pos.x, y = pos.y, z = pos.z },
    dir    = dir,
    health = hp
  }

  data.samples[#data.samples + 1] = sample
  if #data.samples > 0 and (currentTime - data.samples[1].time) > CONST.ANALYSIS_WINDOW then
    local cutoff = 1
    while cutoff <= #data.samples and (currentTime - data.samples[cutoff].time) > CONST.ANALYSIS_WINDOW do
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

  -- ─── EXTENDED TELEMETRY ────────────────────────────────────────────────
  local timeSinceLastTelemetry = nowt - (data.lastTelemetryTime or 0)
  if timeSinceLastTelemetry >= (MonsterAI.TELEMETRY_INTERVAL or 500) then
    local snapshot = MonsterAI.Telemetry
      and MonsterAI.Telemetry.collectSnapshot
      and MonsterAI.Telemetry.collectSnapshot(creature) or nil
    data.lastTelemetryTime = nowt

    if snapshot then
      if snapshot.speed and snapshot.speed > 0 then
        data.avgSpeed  = (data.avgSpeed or 0) * 0.85 + snapshot.speed * 0.15
        data.baseSpeed = snapshot.baseSpeed or data.baseSpeed
      end

      BoundedPush(data.walkSamples, {
        time         = nowt,
        isWalking    = snapshot.isWalking,
        stepDuration = snapshot.stepDuration,
        direction    = snapshot.walkDirection
      }, 50)

      local walkingCount = 0
      for i = 1, #data.walkSamples do
        if data.walkSamples[i].isWalking then walkingCount = walkingCount + 1 end
      end
      data.walkingRatio = walkingCount / math.max(1, #data.walkSamples)

      if snapshot.stepDuration and snapshot.stepDuration > 0 then
        data.avgStepDuration = (data.avgStepDuration or 0) * 0.8 + snapshot.stepDuration * 0.2
      end
    end
  end

  -- ─── DIRECTION TRACKING ────────────────────────────────────────────────
  if dir ~= data.lastDirection then
    data.directionChanges = data.directionChanges + 1
    BoundedPush(data.directionHistory, { time = nowt, direction = dir }, 30)

    if #data.directionHistory >= 2 then
      local firstTurn  = data.directionHistory[1]
      local timeWindow = (nowt - firstTurn.time) / 1000
      if timeWindow > 0 then
        data.turnFrequency = (#data.directionHistory - 1) / timeWindow
      end
    end
    data.lastDirection = dir
  end

  -- ─── HEALTH CHANGE TRACKING ────────────────────────────────────────────
  if hp ~= data.lastHealthPercent then
    local healthChange = data.lastHealthPercent - hp
    BoundedPush(data.healthSamples, { time = nowt, percent = hp, change = healthChange }, 30)

    if #data.healthSamples >= 2 then
      local totalChange, totalTime = 0, 0
      for i = 2, #data.healthSamples do
        totalChange = totalChange + (data.healthSamples[i].change or 0)
        totalTime   = totalTime + (data.healthSamples[i].time - data.healthSamples[i - 1].time)
      end
      if totalTime > 0 then
        data.healthChangeRate = totalChange / (totalTime / 1000)
      end
    end

    if healthChange > 0 then
      data.damageDealtToMonster = (data.damageDealtToMonster or 0) + healthChange
      if not data.engagementStart then
        data.engagementStart = nowt
      end
    end
    data.lastHealthPercent = hp
  end

  -- ─── MOVEMENT & DISTANCE TRACKING ─────────────────────────────────────
  data.movementSamples = data.movementSamples + 1
  local moved = not (pos.x == data.lastPosition.x and pos.y == data.lastPosition.y)

  local playerPos = player and player:getPosition()
  if playerPos then
    local dist = math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y))
    BoundedPush(data.distanceSamples, { time = nowt, distance = dist }, 30)

    local totalDist = 0
    for i = 1, #data.distanceSamples do
      totalDist = totalDist + data.distanceSamples[i].distance
    end
    data.avgDistanceFromPlayer = totalDist / math.max(1, #data.distanceSamples)

    if #data.distanceSamples >= 10 then
      local distCounts = {}
      for i = 1, #data.distanceSamples do
        local d = data.distanceSamples[i].distance
        distCounts[d] = (distCounts[d] or 0) + 1
      end
      local maxCount, modeDistance = 0, 1
      for d, count in pairs(distCounts) do
        if count > maxCount then maxCount = count; modeDistance = d end
      end
      data.preferredDistance = modeDistance
    end
  end

  if not moved then
    data.stationaryCount = data.stationaryCount + 1
  else
    local dt = nowt - (data.lastSampleTime or nowt)
    local dx = math.max(math.abs(pos.x - data.lastPosition.x), math.abs(pos.y - data.lastPosition.y))
    if dt > 0 and dx > 0 then
      local instSpeed = dx / (dt / 1000)
      data.avgSpeed = (data.avgSpeed or 0) * 0.8 + instSpeed * 0.2
    end
    data.lastSampleTime = nowt

    if playerPos then
      local oldDist = math.max(math.abs(data.lastPosition.x - playerPos.x), math.abs(data.lastPosition.y - playerPos.y))
      local newDist = math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y))
      if newDist < oldDist then data.chaseCount = data.chaseCount + 1 end
    end

    if playerPos and MonsterAI.Predictor and MonsterAI.Predictor.isFacingPosition then
      local ok, isFacing = pcall(function()
        return MonsterAI.Predictor.isFacingPosition(pos, creature:getDirection(), playerPos)
      end)
      if ok and isFacing then data.facingCount = (data.facingCount or 0) + 1 end
    end

    data.lastPosition = { x = pos.x, y = pos.y, z = pos.z }
  end

  -- Update confidence based on sample count
  local sampleRatio = math.min(#data.samples / 50, 1)
  data.confidence = 0.1 + 0.6 * sampleRatio
end

-- ============================================================================
-- EWMA LEARNING
-- ============================================================================

function MonsterAI.Tracker.updateEWMA(data, observed)
  if not data or not observed or observed <= 0 then return end
  local alpha = data.ewmaAlpha or CONST.EWMA.ALPHA_DEFAULT
  if not data.ewmaCooldown then
    data.ewmaCooldown  = observed
    data.ewmaVariance  = 0
  else
    local err = observed - data.ewmaCooldown
    data.ewmaCooldown = alpha * observed + (1 - alpha) * data.ewmaCooldown
    data.ewmaVariance = (1 - alpha) * (data.ewmaVariance or 0) + alpha * (err * err)
  end
  data.predictedWaveCooldown = data.ewmaCooldown

  local pname = (data.name or ""):lower()
  MonsterAI.Patterns.persist(pname, {
    waveCooldown = data.ewmaCooldown,
    waveVariance = data.ewmaVariance,
    lastSeen     = nowMs(),
    confidence   = math.min(
      (MonsterAI.Patterns.knownMonsters[pname]
        and MonsterAI.Patterns.knownMonsters[pname].confidence or 0.5) + 0.02,
      0.99)
  })
end

-- ============================================================================
-- UTILITY: DPS + PREDICTED PATTERN
-- ============================================================================

function MonsterAI.Tracker.getDPS(creatureId, windowMs)
  windowMs = windowMs or (MonsterAI.DPS_WINDOW or 5000)
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
  return sum / math.max(windowMs / 1000, 0.001)
end

function MonsterAI.Tracker.getPredictedPattern(creatureId)
  local data = MonsterAI.Tracker.monsters[creatureId]
  if not data or data.movementSamples < 10 then
    return CONST.MOVEMENT_PATTERN.CHASE, 0.2
  end

  local stationaryRatio = data.stationaryCount / data.movementSamples
  local chaseRatio      = data.chaseCount / (data.movementSamples - data.stationaryCount + 1)

  if stationaryRatio > 0.8 then
    return CONST.MOVEMENT_PATTERN.STATIC, data.confidence
  elseif chaseRatio > 0.6 then
    return CONST.MOVEMENT_PATTERN.CHASE, data.confidence
  elseif chaseRatio < 0.3 and stationaryRatio < 0.3 then
    return CONST.MOVEMENT_PATTERN.ERRATIC, data.confidence * 0.8
  else
    return CONST.MOVEMENT_PATTERN.CHASE, data.confidence * 0.7
  end
end

if MonsterAI.DEBUG then
  print("[MonsterAI] Tracking module v3.0 loaded")
end
