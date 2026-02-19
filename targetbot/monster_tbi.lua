--[[
  Monster TargetBot Integration (TBI) Module v3.0
  
  Single Responsibility: Enhanced priority calculation for targeting,
  9-stage scoring, sorted target lists, and danger assessment.
  
  Depends on: monster_ai_core.lua, monster_tracking.lua,
              monster_patterns.lua, monster_prediction.lua,
              monster_combat_feedback.lua
  Populates: MonsterAI.TargetBot (TBI)
]]

local H = MonsterAI._helpers
local nowMs            = H.nowMs
local safeGetId        = H.safeGetId
local safeIsDead       = H.safeIsDead

-- Guard: returns true when TargetBot is disabled
local function tbOff() return not TargetBot or not TargetBot.isOn or not TargetBot.isOn() end
local safeIsRemoved    = H.safeIsRemoved
local safeCreatureCall = H.safeCreatureCall
local getClient        = H.getClient
local isValidAliveMonster = H.isValidAliveMonster

-- ============================================================================
-- STATE & CONFIG
-- ============================================================================

MonsterAI.TargetBot = MonsterAI.TargetBot or {}
local TBI = MonsterAI.TargetBot

TBI.config = {
  baseWeight        = 1.0,
  distanceWeight    = 0.8,
  healthWeight      = 0.7,
  dangerWeight      = 1.5,
  waveWeight        = 2.0,
  imminentWeight    = 3.0,
  imminentThresholdMs    = 600,
  dangerousCooldownRatio = 0.7,
  lowHealthThreshold     = 30,
  criticalHealthThreshold = 15,
  meleeRange  = 1,
  closeRange  = 3,
  mediumRange = 6,
  fastMonsterThreshold = 250,
  slowMonsterThreshold = 100
}

-- ============================================================================
-- PRIORITY CALCULATION (9-STAGE)
-- ============================================================================

function TBI.calculatePriority(creature, options)
  if not creature then return 0, {} end
  if safeIsDead(creature) or safeIsRemoved(creature) then return 0, {} end

  options = options or {}
  local cfg = TBI.config
  local bk  = {}

  local cid  = safeGetId(creature)
  local cname = safeCreatureCall(creature, "getName", "unknown")
  local cpos  = safeCreatureCall(creature, "getPosition", nil)
  local ppos  = player and (function() local ok,p = pcall(function() return player:getPosition() end); return ok and p end)()
  if not ppos or not cpos then return 0, bk end

  local priority = 100 * cfg.baseWeight
  bk.base = priority

  -- 1. DISTANCE
  local dx   = math.abs(cpos.x - ppos.x)
  local dy   = math.abs(cpos.y - ppos.y)
  local dist = math.max(dx, dy)
  local ds = 0
  if dist <= cfg.meleeRange then ds = 50
  elseif dist <= cfg.closeRange then ds = 35
  elseif dist <= cfg.mediumRange then ds = 20
  else ds = math.max(0, 15 - (dist - cfg.mediumRange) * 2) end
  ds = ds * cfg.distanceWeight; priority = priority + ds; bk.distance = ds

  -- 2. HEALTH
  local hp = safeCreatureCall(creature, "getHealthPercent", 100)
  local hs = 0
  if hp <= cfg.criticalHealthThreshold then hs = 30
  elseif hp <= cfg.lowHealthThreshold then hs = 20
  elseif hp <= 50 then hs = 10 end
  hs = hs * cfg.healthWeight; priority = priority + hs; bk.health = hs

  -- 3. TRACKER DATA
  local td = MonsterAI.Tracker and MonsterAI.Tracker.monsters[cid]
  local ts = 0
  if td then
    local dps = td.ewmaDps or 0
    if dps >= 80 then ts = ts + 40 elseif dps >= 40 then ts = ts + 25 elseif dps >= 20 then ts = ts + 10 end
    bk.dps = dps
    local hc = td.hitCount or 0
    if hc >= 10 then ts = ts + 15 elseif hc >= 5 then ts = ts + 8 elseif hc >= 2 then ts = ts + 3 end
    local rd = td.recentDamage or 0
    if rd > 0 then ts = ts + math.min(30, rd / 5); bk.recentDamage = rd end
    if (td.waveCount or 0) >= 3 then ts = ts + 20 elseif (td.waveCount or 0) >= 1 then ts = ts + 10 end
    local la = td.lastAttackTime or td.firstSeen or 0
    local tsa = nowMs() - la
    if tsa < 2000 then ts = ts + 20 elseif tsa < 5000 then ts = ts + 10 end
  end
  ts = ts * cfg.dangerWeight; priority = priority + ts; bk.tracker = ts

  -- 4. WAVE PREDICTION
  local ws = 0
  if MonsterAI.RealTime and MonsterAI.RealTime.directions then
    local rt = MonsterAI.RealTime.directions[cid]
    if rt then
      local pat = MonsterAI.Patterns and MonsterAI.Patterns.get(cname) or {}
      local wCd = pat.waveCooldown or 2000
      local lw  = td and (td.lastWaveTime or td.lastAttackTime) or 0
      local el  = nowMs() - lw
      local rem = math.max(0, wCd - el)
      local ratio = el / wCd
      if rem <= cfg.imminentThresholdMs and ratio >= cfg.dangerousCooldownRatio then
        ws = 60 * cfg.imminentWeight; bk.imminent = true
      elseif rem <= 1500 then ws = 40 * cfg.waveWeight
      elseif rem <= 2500 then ws = 20 * cfg.waveWeight end

      if rt.dir and ppos then
        if TBI.isCreatureFacingPosition(cpos, rt.dir, ppos) then ws = ws + 15; bk.facing = true end
        if MonsterAI.Predictor and MonsterAI.Predictor.isPositionInWavePath then
          if MonsterAI.Predictor.isPositionInWavePath(ppos, cpos, rt.dir, pat.waveRange or 5, pat.waveWidth or 3) then
            ws = ws + 25; bk.inWavePath = true
          end
        end
      end
    end
  end
  priority = priority + ws; bk.wave = ws

  -- 5. CLASSIFICATION
  local cs = 0
  if MonsterAI.Classifier then
    local cl = MonsterAI.Classifier.get(cname)
    if cl then
      if cl.dangerLevel == "critical" then cs = 50
      elseif cl.dangerLevel == "high" then cs = 30
      elseif cl.dangerLevel == "medium" then cs = 15 end
      if cl.isWaveCaster then cs = cs + 20 end
      if cl.isRanged then cs = cs + 10 end
      bk.classification = cl.dangerLevel
    end
  end
  priority = priority + cs; bk.class = cs

  -- 6. MOVEMENT / TRAJECTORY
  local ms = 0
  local iw = safeCreatureCall(creature, "isWalking", false)
  if iw then
    local wd = safeCreatureCall(creature, "getWalkDirection", nil)
    if wd then
      local pp = TBI.predictPosition(cpos, wd, 1)
      if pp then
        local fd = math.max(math.abs(pp.x - ppos.x), math.abs(pp.y - ppos.y))
        if fd < dist then ms = 15; bk.approaching = true
        elseif fd > dist then ms = -5; bk.fleeing = true end
      end
    end
    local spd = safeCreatureCall(creature, "getSpeed", 100)
    if spd >= cfg.fastMonsterThreshold then ms = ms + 10; bk.fast = true end
  end
  priority = priority + ms; bk.movement = ms

  -- 7. ADAPTIVE WEIGHTS (CombatFeedback)
  local fs = 0
  if MonsterAI.CombatFeedback and MonsterAI.CombatFeedback.getWeights then
    local w = MonsterAI.CombatFeedback.getWeights(cname)
    if w then
      local am = w.overall or 1.0; priority = priority * am; bk.adaptiveMultiplier = am
      if w.wave  and w.wave  > 1.1 then fs = fs + 15 end
      if w.melee and w.melee > 1.1 then fs = fs + 10 end
    end
  end
  priority = priority + fs; bk.feedback = fs

  -- 8. TELEMETRY BONUSES
  local tels = 0
  if MonsterAI.Telemetry and MonsterAI.Telemetry.get then
    local tel = MonsterAI.Telemetry.get(cid)
    if tel then
      if (tel.damageVariance or 0) > 50 then tels = tels + 10 end
      if (tel.stepConsistency or 0) < 0.5 then tels = tels + 5 end
    end
  end
  priority = priority + tels; bk.telemetry = tels

  -- 9. CLAMP
  priority = math.max(0, math.min(1000, priority))
  bk.final = priority
  return priority, bk
end

-- ============================================================================
-- HELPERS
-- ============================================================================

function TBI.isCreatureFacingPosition(cpos, dir, tpos)
  if not cpos or not dir or not tpos then return false end
  local dx, dy = tpos.x - cpos.x, tpos.y - cpos.y
  if dir == 0 then return dy < 0 and math.abs(dx) <= math.abs(dy)
  elseif dir == 1 then return dx > 0 and math.abs(dy) <= math.abs(dx)
  elseif dir == 2 then return dy > 0 and math.abs(dx) <= math.abs(dy)
  elseif dir == 3 then return dx < 0 and math.abs(dy) <= math.abs(dx) end
  return false
end

function TBI.predictPosition(pos, dir, steps)
  if not pos or not dir then return nil end
  steps = steps or 1
  local m = {
    [0]={0,-1},[1]={1,0},[2]={0,1},[3]={-1,0},
    [4]={1,-1},[5]={1,1},[6]={-1,1},[7]={-1,-1}
  }
  local d = m[dir]
  if not d then return nil end
  return { x = pos.x + d[1]*steps, y = pos.y + d[2]*steps, z = pos.z }
end

-- ============================================================================
-- SORTED TARGETS
-- ============================================================================

function TBI.getSortedTargets(options)
  options = options or {}
  local targets = {}
  local ppos = player and player:getPosition()
  if not ppos then return targets end
  local maxR = options.maxRange or 10
  local C = getClient()
  local creatures = (C and C.getSpectators) and C.getSpectators(ppos, false)
    or (g_map and g_map.getSpectators and g_map.getSpectators(ppos, false)) or {}

  for _, cr in ipairs(creatures) do
    if cr and isValidAliveMonster(cr) then
      local cp = safeCreatureCall(cr, "getPosition", nil)
      if cp and cp.z == ppos.z then
        local d = math.max(math.abs(cp.x - ppos.x), math.abs(cp.y - ppos.y))
        if d <= maxR then
          local pri, bk = TBI.calculatePriority(cr, options)
          targets[#targets+1] = { creature = cr, priority = pri, distance = d,
            breakdown = bk, id = safeGetId(cr), name = safeCreatureCall(cr, "getName", "unknown") }
        end
      end
    end
  end
  table.sort(targets, function(a,b) return a.priority > b.priority end)
  return targets
end

function TBI.getBestTarget(options)
  local t = TBI.getSortedTargets(options)
  return t[1]
end

-- ============================================================================
-- DANGER LEVEL
-- ============================================================================

function TBI.getDangerLevel()
  local ppos = player and player:getPosition()
  if not ppos then return 0, {} end
  local level, threats = 0, {}
  for _, t in ipairs(TBI.getSortedTargets({maxRange = 8})) do
    local tl = t.priority / 200
    level = level + tl
    if tl >= 1.0 then threats[#threats+1] = { name = t.name, level = tl, imminent = t.breakdown and t.breakdown.imminent } end
  end
  return math.min(10, level), threats
end

-- ============================================================================
-- STATS / DEBUG
-- ============================================================================

function TBI.getStats()
  local s = { config = TBI.config,
    feedbackActive = MonsterAI.CombatFeedback ~= nil,
    trackerActive  = MonsterAI.Tracker ~= nil,
    realTimeActive = MonsterAI.RealTime ~= nil }
  if MonsterAI.CombatFeedback and MonsterAI.CombatFeedback.getStats then
    s.feedback = MonsterAI.CombatFeedback.getStats()
  end
  return s
end

function TBI.debugCreature(creature)
  if not creature then print("[TBI] No creature specified"); return end
  local pri, bk = TBI.calculatePriority(creature)
  print("[TBI] Priority breakdown for " .. (creature:getName() or "unknown") .. ":")
  print("  Final Priority: " .. pri)
  for k, v in pairs(bk) do print("  " .. k .. ": " .. tostring(v)) end
end

-- ============================================================================
-- EVENTBUS
-- ============================================================================

if EventBus and EventBus.on then
  EventBus.on("targetbot:request_priority", function(creature, callback)
    if tbOff() then return end
    if creature and callback then
      local p, bk = TBI.calculatePriority(creature)
      callback(p, bk)
    end
  end)

  -- Canonical emitBestTarget chain (gated by TargetBot state to prevent CPU waste)
  schedule(2000, function()
    local function emit()
      if TargetBot and TargetBot.isOn and TargetBot.isOn() then
        if EventBus and EventBus.emit then
          local best = TBI.getBestTarget()
          if best then EventBus.emit("targetbot:ai_recommendation", best.creature, best.priority, best.breakdown) end
        end
      end
      schedule(1000, emit)
    end
    emit()
  end)
end

if MonsterAI.DEBUG then print("[MonsterAI] TBI module v3.0 loaded") end
