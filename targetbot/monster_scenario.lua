--[[
  Monster Scenario Module v3.0
  
  Single Responsibility: Multi-monster scenario detection, anti-zigzag
  movement system, engagement locks, and cluster analysis.
  
  KEY FIX (v3.0): endEngagement() is DECOUPLED from clearTargetLock().
  Previously endEngagement cleared the target lock from 6+ call-sites,
  causing the attack-once-then-stop cycle.
  
  isEngaged() now validates via g_game.getAttackingCreature() + grace
  period, not just internal state. This prevents false negatives when
  a creature hasn't been processed by the Tracker yet.
  
  Depends on: monster_ai_core.lua, monster_tracking.lua
  Populates: MonsterAI.Scenario
]]

-- Safe resolve ring_buffer utilities (may not be in global scope in all sandboxes)
local BoundedPush = BoundedPush or (RingBuffer and RingBuffer.boundedPush) or function(arr, item, max)
  arr[#arr + 1] = item
  while #arr > (max or 50) do table.remove(arr, 1) end
end
local TrimArray = TrimArray or (RingBuffer and RingBuffer.trimArray) or function(arr, max)
  while #arr > (max or 50) do table.remove(arr, 1) end
end

local H = MonsterAI._helpers
local nowMs            = H.nowMs
local safeGetId        = H.safeGetId
local safeIsDead       = H.safeIsDead
local safeIsRemoved    = H.safeIsRemoved

-- Guard: returns true when TargetBot is disabled
local function tbOff() return not TargetBot or not TargetBot.isOn or not TargetBot.isOn() end
local safeCreatureCall = H.safeCreatureCall
local getClient        = H.getClient
local isValidAliveMonster = H.isValidAliveMonster

-- ============================================================================
-- SCENARIO TYPES & STATE
-- ============================================================================

MonsterAI.Scenario = MonsterAI.Scenario or {}
local S = MonsterAI.Scenario

S.TYPES = {
  IDLE          = "idle",
  SINGLE        = "single",
  FEW           = "few",
  MODERATE      = "moderate",
  SWARM         = "swarm",
  OVERWHELMING  = "overwhelming"
}

S.state = {
  type              = S.TYPES.IDLE,
  monsterCount      = 0,
  lastUpdate        = 0,
  targetLockId      = nil,
  targetLockTime    = 0,
  targetLockHealth  = 100,
  switchCooldown    = 0,
  lastSwitchTime    = 0,
  consecutiveSwitches = 0,
  movementHistory   = {},
  lastMoveRecord    = 0,
  scenarioStartTime = 0,
  avgDangerLevel    = 0,
  clusterInfo       = nil,
  -- Engagement lock (v3.0)
  engagementLockId      = nil,
  engagementLockTime    = 0,
  engagementLockHealth  = 100,
  isEngaged             = false,
  lastAttackCommandTime = 0,
  -- Grace period: keep engagement valid for this long after losing
  -- the attacking-creature signal (covers animation/server lag)
  -- v3.1: aligned with CombatConstants.GRACE_PERIOD
  ENGAGEMENT_GRACE_MS   = (CombatConstants and CombatConstants.GRACE_PERIOD) or 1500
}

-- ============================================================================
-- SCENARIO CONFIGS (v3.0 — stricter anti-zigzag)
-- ============================================================================

S.configs = {
  [S.TYPES.IDLE] = {
    switchCooldownMs = 0, targetStickiness = 0,
    prioritizeFinishingKills = false, allowZigzag = true,
    description = "No combat"
  },
  [S.TYPES.SINGLE] = {
    switchCooldownMs = 1000, targetStickiness = 80,
    prioritizeFinishingKills = true, allowZigzag = false,
    requireEngagementLock = true,
    description = "Single target - focused"
  },
  [S.TYPES.FEW] = {
    switchCooldownMs = 5000, targetStickiness = 150,
    prioritizeFinishingKills = true, allowZigzag = false,
    maxSwitchesPerMinute = 3, healthThresholdForSwitch = 15,
    requireEngagementLock = true,
    description = "Few targets - LINEAR targeting"
  },
  [S.TYPES.MODERATE] = {
    switchCooldownMs = 4000, targetStickiness = 100,
    prioritizeFinishingKills = true, allowZigzag = false,
    maxSwitchesPerMinute = 5, healthThresholdForSwitch = 20,
    requireEngagementLock = true,
    description = "Moderate - stable targeting"
  },
  [S.TYPES.SWARM] = {
    switchCooldownMs = 2500, targetStickiness = 60,
    prioritizeFinishingKills = true, allowZigzag = false,
    maxSwitchesPerMinute = 8, healthThresholdForSwitch = 15,
    focusLowestHealth = true, requireEngagementLock = false,
    description = "Swarm - focused survival"
  },
  [S.TYPES.OVERWHELMING] = {
    switchCooldownMs = 1500, targetStickiness = 40,
    prioritizeFinishingKills = true, allowZigzag = false,
    focusLowestHealth = true, emergencyMode = true,
    requireEngagementLock = false,
    description = "Overwhelming - emergency"
  }
}

-- ============================================================================
-- SCENARIO DETECTION
-- ============================================================================

function S.detectScenario()
  local ppos = player and player:getPosition()
  if not ppos then S.state.type = S.TYPES.IDLE; S.state.monsterCount = 0; return S.state.type end

  local nowt = nowMs()
  if nowt - S.state.lastUpdate < 200 then return S.state.type end
  S.state.lastUpdate = nowt

  local monsters, totalDanger, mc = {}, 0, 0
  local C = getClient()
  local creatures = (C and C.getSpectators) and C.getSpectators(ppos, false)
    or (g_map and g_map.getSpectators and g_map.getSpectators(ppos, false)) or {}

  for _, cr in ipairs(creatures) do
    if cr and isValidAliveMonster(cr) then
      local cp = safeCreatureCall(cr, "getPosition", nil)
      if cp and cp.z == ppos.z then
        local d = math.max(math.abs(cp.x - ppos.x), math.abs(cp.y - ppos.y))
        if d <= 14 then
          mc = mc + 1
          local danger = 1
          local id = safeGetId(cr)
          local td = MonsterAI.Tracker and id and MonsterAI.Tracker.monsters[id]
          if td then danger = (td.ewmaDps or 1) / 10 + 1 end
          totalDanger = totalDanger + danger
          monsters[#monsters+1] = { creature = cr, id = id, distance = d,
            health = safeCreatureCall(cr, "getHealthPercent", 100), danger = danger, pos = cp }
        end
      end
    end
  end

  local prev = S.state.type
  S.state.monsterCount  = mc
  S.state.avgDangerLevel = mc > 0 and (totalDanger / mc) or 0

  local nt
  if mc == 0 then nt = S.TYPES.IDLE
  elseif mc == 1 then nt = S.TYPES.SINGLE
  elseif mc <= 3 then nt = S.TYPES.FEW
  elseif mc <= 6 then nt = S.TYPES.MODERATE
  elseif mc <= 10 then nt = S.TYPES.SWARM
  else nt = S.TYPES.OVERWHELMING end

  S.state.type = nt
  if nt ~= prev then
    S.state.scenarioStartTime   = nowt
    S.state.consecutiveSwitches = 0
    if EventBus and EventBus.emit then EventBus.emit("scenario:changed", nt, prev, mc) end
  end

  S.analyzeCluster(monsters)
  return nt
end

-- ============================================================================
-- CLUSTER ANALYSIS
-- ============================================================================

function S.analyzeCluster(monsters)
  if #monsters < 2 then S.state.clusterInfo = nil; return end
  local sx, sy = 0, 0
  for _, m in ipairs(monsters) do sx = sx + m.pos.x; sy = sy + m.pos.y end
  local cx, cy = sx / #monsters, sy / #monsters
  local ts = 0
  for _, m in ipairs(monsters) do
    local dx, dy = m.pos.x - cx, m.pos.y - cy
    ts = ts + math.sqrt(dx*dx + dy*dy)
  end
  local avg = ts / #monsters
  local ct = avg < 2 and "tight" or (avg < 4 and "medium" or "spread")
  S.state.clusterInfo = { centroid = {x=cx, y=cy}, spread = avg, type = ct, monsters = monsters }
end

-- ============================================================================
-- TARGET LOCK (prevents rapid switching)
-- ============================================================================

function S.lockTarget(creatureId, health)
  local nowt    = nowMs()
  local prevId  = S.state.targetLockId
  S.state.targetLockId     = creatureId
  S.state.targetLockTime   = nowt
  S.state.targetLockHealth = health or 100

  if prevId and prevId ~= creatureId then
    S.state.lastSwitchTime      = nowt
    S.state.consecutiveSwitches = S.state.consecutiveSwitches + 1
    S.recordMovement()
    if EventBus and EventBus.emit then pcall(function() EventBus.emit("monsterai:target_switched", creatureId, prevId) end) end
  elseif not prevId then
    S.state.consecutiveSwitches = 0
    if EventBus and EventBus.emit then pcall(function() EventBus.emit("monsterai:target_locked", creatureId, health) end) end
  end

  if (nowt - S.state.lastSwitchTime) > 10000 then S.state.consecutiveSwitches = 0 end
end

function S.clearTargetLock()
  S.state.targetLockId     = nil
  S.state.targetLockTime   = 0
  S.state.targetLockHealth = 100
end

-- ============================================================================
-- ENGAGEMENT LOCK (v3.0 — LINEAR TARGETING)
-- Once we start attacking, we STAY on it until it dies or becomes
-- unreachable. endEngagement does NOT clear the target lock.
-- ============================================================================

function S.startEngagement(creatureId, health)
  if not creatureId then return end
  local nowt = nowMs()
  local cfg  = S.configs[S.state.type] or S.configs[S.TYPES.FEW]

  if not cfg.requireEngagementLock then
    S.lockTarget(creatureId, health)
    return
  end

  if S.state.engagementLockId == creatureId then
    S.state.lastAttackCommandTime = nowt
    return
  end

  -- Only allow new engagement if NOT already engaged with a live target
  if S.state.isEngaged and S.state.engagementLockId then
    local ec = MonsterAI.Tracker and MonsterAI.Tracker.monsters[S.state.engagementLockId]
    ec = ec and ec.creature
    if ec and not safeIsDead(ec) and not safeIsRemoved(ec) then return end
  end

  S.state.engagementLockId      = creatureId
  S.state.engagementLockTime    = nowt
  S.state.engagementLockHealth  = health or 100
  S.state.isEngaged             = true
  S.state.lastAttackCommandTime = nowt
  S.lockTarget(creatureId, health)
  if EventBus and EventBus.emit then pcall(function() EventBus.emit("monsterai:engagement_started", creatureId, health) end) end
end

--- Check if currently engaged.
-- v3.0 FIX: also validates via g_game.getAttackingCreature() + grace.
function S.isEngaged()
  if not S.state.isEngaged or not S.state.engagementLockId then return false, nil end

  -- Check internal state
  local ec = MonsterAI.Tracker and MonsterAI.Tracker.monsters[S.state.engagementLockId]
  ec = ec and ec.creature
  if not ec or safeIsDead(ec) or safeIsRemoved(ec) then
    S.endEngagement("target_gone"); return false, nil
  end

  -- v3.0 FIX: Also check the CLIENT attacking creature.
  -- If the client says we're attacking the same creature — we're engaged.
  -- Otherwise allow a grace period (animation / server-round-trip lag).
  local attackingCreature = g_game and g_game.getAttackingCreature and g_game.getAttackingCreature()
  if attackingCreature then
    local aid = safeGetId(attackingCreature)
    if aid == S.state.engagementLockId then
      -- Confirmed engagement
      return true, S.state.engagementLockId
    end
  end

  -- Grace period: if attack command was sent recently, still consider engaged
  local nowt   = nowMs()
  local grace  = nowt - S.state.lastAttackCommandTime
  if grace <= S.state.ENGAGEMENT_GRACE_MS then
    return true, S.state.engagementLockId
  end

  -- Grace expired and client doesn't confirm → end engagement
  S.endEngagement("grace_expired")
  return false, nil
end

--- End engagement.
-- v3.0 KEY FIX: Does NOT call clearTargetLock(). The target lock
-- remains so that shouldAllowTargetSwitch() can still evaluate the
-- previous target's health / progress before allowing a new switch.
function S.endEngagement(reason)
  local prev = S.state.engagementLockId
  S.state.engagementLockId     = nil
  S.state.engagementLockTime   = 0
  S.state.engagementLockHealth = 100
  S.state.isEngaged            = false

  -- NOTE: intentionally NOT calling S.clearTargetLock() here.
  -- Target lock is cleared separately when shouldAllowTargetSwitch
  -- determines the target is dead/gone or a new target is locked.

  if EventBus and EventBus.emit and prev then
    pcall(function() EventBus.emit("monsterai:engagement_ended", prev, reason or "unknown") end)
  end
end

function S.getEngagedTarget()
  local ok, eid = S.isEngaged()
  if not ok then return nil end
  local d = MonsterAI.Tracker and MonsterAI.Tracker.monsters[eid]
  return d and d.creature or nil
end

-- ============================================================================
-- TARGET SWITCH EVALUATION (v3.0 — strict linear targeting)
-- ============================================================================

function S.shouldAllowTargetSwitch(newId, newPri, newHp)
  local nowt = nowMs()
  local cfg  = S.configs[S.state.type] or S.configs[S.TYPES.FEW]

  -- Engagement lock check (highest priority)
  if cfg.requireEngagementLock and S.state.isEngaged and S.state.engagementLockId then
    local ec = MonsterAI.Tracker and MonsterAI.Tracker.monsters[S.state.engagementLockId]
    ec = ec and ec.creature
    if ec and not safeIsDead(ec) and not safeIsRemoved(ec) then
      if newId == S.state.engagementLockId then return true, "engaged_target" end
      return false, "engagement_locked"
    else S.endEngagement("target_dead") end
  end

  if not S.state.targetLockId then return true, "no_lock" end

  -- Validate lock
  local ld = MonsterAI.Tracker and MonsterAI.Tracker.monsters[S.state.targetLockId]
  local lc = ld and ld.creature
  if not lc then S.clearTargetLock(); return true, "target_gone" end
  local okD, dead = pcall(function() return lc:isDead() end)
  local okR, rem  = pcall(function() return lc:isRemoved() end)
  if (okD and dead) or (okR and rem) then S.clearTargetLock(); return true, "target_dead" end
  if newId == S.state.targetLockId then return true, "same_target" end

  -- Locked target's health
  local okH, lHp = pcall(function() return lc:getHealthPercent() end)
  lHp = okH and lHp or 100

  if lHp <= 30 then return false, "finishing_kill_30" end
  if lHp <= 50 then
    if (newPri or 0) < (S.state.targetLockHealth or 0) + 500 then return false, "finishing_kill_50" end
  end
  if lHp <= 80 then
    local req = 300
    local drop = (S.state.targetLockHealth or 100) - lHp
    if drop > 10 then req = 400 end
    if (newPri or 0) < req then return false, "making_progress" end
  end

  -- Cooldown
  local tss = nowt - S.state.lastSwitchTime
  if tss < (cfg.switchCooldownMs or 5000) then return false, "cooldown" end
  if cfg.maxSwitchesPerMinute then
    local mx = math.max(2, cfg.maxSwitchesPerMinute - 1)
    if tss < 60000/mx and S.state.consecutiveSwitches > 0 then return false, "rate_limit" end
  end

  -- Progress stickiness
  local drop = (S.state.targetLockHealth or 100) - lHp
  if drop > 5 and lHp > 5 then
    local bonus = math.min(100, drop * 2)
    if (newPri or 0) < 300 + bonus then return false, "making_progress" end
  end

  -- Zigzag prevention
  if not cfg.allowZigzag and S.state.consecutiveSwitches >= 2 then
    local avg = (nowt - S.state.scenarioStartTime) / math.max(1, S.state.consecutiveSwitches)
    if avg < 5000 then return false, "zigzag_prevention" end
  end

  return true, "allowed"
end

-- ============================================================================
-- ZIGZAG DETECTION
-- ============================================================================

function S.recordMovement()
  local pp = player and player:getPosition()
  if not pp then return end
  local nowt = nowMs()
  if (nowt - (S.state.lastMoveRecord or 0)) < 120 then return end
  local last = S.state.movementHistory[#S.state.movementHistory]
  if last and last.x == pp.x and last.y == pp.y then return end
  BoundedPush(S.state.movementHistory, { x = pp.x, y = pp.y, time = nowt }, 10)
  S.state.lastMoveRecord = nowt
end

function S.isZigzagging()
  local h = S.state.movementHistory
  if #h < 4 then return false end
  local rev, pdx, pdy = 0, 0, 0
  for i = 2, #h do
    local dx, dy = h[i].x - h[i-1].x, h[i].y - h[i-1].y
    if (dx * pdx < 0) or (dy * pdy < 0) then rev = rev + 1 end
    pdx, pdy = dx, dy
  end
  return rev >= (#h - 1) * 0.5
end

if EventBus and EventBus.on then
  EventBus.on("player:move", function() if tbOff() then return end; S.recordMovement() end, 60)
end

-- ============================================================================
-- OPTIMAL TARGET SELECTION — Removed (PriorityEngine is the sole authority)
-- ============================================================================

function S.getOptimalTarget()
  return nil
end

-- ============================================================================
-- STATS
-- ============================================================================

function S.getStats()
  return { currentScenario = S.state.type, monsterCount = S.state.monsterCount,
    avgDangerLevel = S.state.avgDangerLevel, targetLockId = S.state.targetLockId,
    consecutiveSwitches = S.state.consecutiveSwitches, isZigzagging = S.isZigzagging(),
    clusterType = S.state.clusterInfo and S.state.clusterInfo.type or "none",
    config = S.configs[S.state.type] or {} }
end

-- ============================================================================
-- EVENTBUS INTEGRATION
-- ============================================================================

if EventBus and EventBus.on then
  EventBus.on("targetbot:target_changed", function(creature)
    if tbOff() then return end
    if creature then S.lockTarget(creature:getId(), creature:getHealthPercent() or 100)
    else S.clearTargetLock() end
  end)
  EventBus.on("creature:death", function(creature)
    if tbOff() then return end
    if creature and creature:getId() == S.state.targetLockId then S.clearTargetLock() end
    if creature and creature:getId() == S.state.engagementLockId then S.endEngagement("target_dead") end
  end)
end

-- Tick
if UnifiedTick and UnifiedTick.register then
  UnifiedTick.register({ id = "monsterai_scenario", interval = 500,
    priority = UnifiedTick.PRIORITY and UnifiedTick.PRIORITY.NORMAL or 50,
    callback = function() if MonsterAI.COLLECT_ENABLED then pcall(S.detectScenario) end end })
else
  macro(500, function()
    if nExBot and nExBot.ZChangeGuard and nExBot.ZChangeGuard.isActive and nExBot.ZChangeGuard.isActive() then
      return
    end
    if MonsterAI.COLLECT_ENABLED then pcall(S.detectScenario) end
  end)
end

if MonsterAI.DEBUG then print("[MonsterAI] Scenario module v3.0 loaded") end
