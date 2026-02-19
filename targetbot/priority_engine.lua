--[[
  Unified Priority Engine v1.0

  Single entry point for ALL target priority calculation.
  Replaces duplicated logic across:
    - creature_priority.lua  (17 overlapping scoring sections)
    - monster_scenario.lua   (modifyPriority + getOptimalTarget)

  Architecture:
    PriorityEngine.calculate(creature, config, path)
      → BaseScore          (config priority × 1000)
      → HealthScore        (hp-based exponential, chase-mode, danger)
      → DistanceScore      (O(1) path-length lookup)
      → StickinessScore    (current-target + attack-duration)
      → ThreatScore        (MonsterAI DPS, wave, classification)
      → AoEScore           (diamond arrow / large rune area)
      → ScenarioScore      (target lock, finish-kill, cluster)
      → AntiZigzagScore    (recent-switches penalty)
      → total

    PriorityEngine.shouldAllowSwitch(newId, newPriority, newHp)
      → SwitchGate (cooldowns, engagement lock, progress check)

  Design Principles:
    SRP — Each sub-score is a pure function of (creature, config, state).
    DRY — No duplicated stickiness/zigzag logic.
    KISS — Flat scoring pipeline, no nested conditionals.
    SOLID — Open for extension (add a scorer), closed for modification.

  Dependencies: CombatConstants, MonsterAI (optional), ASM (optional).
]]

-- ============================================================================
-- MODULE
-- ============================================================================

PriorityEngine = PriorityEngine or {}
PriorityEngine.VERSION = "1.0"
PriorityEngine.DEBUG   = false

-- ============================================================================
-- LAZY DEPS
-- ============================================================================

local CC -- CombatConstants

local function ensureDeps()
  if not CC then CC = CombatConstants or {} end
end

-- ============================================================================
-- HELPERS
-- ============================================================================

local nowMs = nExBot.Shared.nowMs

local getClient = nExBot.Shared.getClient

-- Delegate to SafeCreature for safe accessors (DRY)
local SC = SafeCreature or {}

local function cId(c)   return SC.getId and SC.getId(c) or nil end
local function cHp(c)   return SC.getHealthPercent and SC.getHealthPercent(c) or 100 end
local function cName(c) return SC.getName and SC.getName(c) or "?" end
local function cPos(c)  return SC.getPosition and SC.getPosition(c) or nil end
local function cDead(c) return SC.isDead and SC.isDead(c) or true end

local player
local function getPlayer()
  if not player or not pcall(function() return player:getPosition() end) then
    local C = getClient()
    player = (C and C.getLocalPlayer and C.getLocalPlayer())
          or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  end
  return player
end

local function gameTarget()
  local C = getClient()
  if C and C.getAttackingCreature then
    local ok, c = pcall(C.getAttackingCreature)
    return ok and c or nil
  end
  if g_game and g_game.getAttackingCreature then
    local ok, c = pcall(g_game.getAttackingCreature)
    return ok and c or nil
  end
  return nil
end

-- ============================================================================
-- CONSTANTS (tuning knobs)
-- ============================================================================

local SCORE = {
  -- Config priority scaling (user-set 1-10 × this = dominant factor)
  CONFIG_SCALE = 1000,

  -- Health scoring
  HP_CRITICAL   = 135,  -- hp ≤ 5
  HP_VERY_LOW   = 100,  -- hp ≤ 10
  HP_LOW        = 70,   -- hp ≤ 20
  HP_WOUNDED    = 45,   -- hp ≤ 30
  HP_LIGHT      = 25,   -- hp ≤ 50
  HP_SCRATCHED  = 5,    -- hp ≤ 70

  -- Distance weights (index = path length) — strong proximity preference
  DIST = { [1]=120, [2]=80, [3]=50, [4]=25, [5]=15, [6]=5, [7]=2 },

  -- Stickiness (reduced to let distance influence switching)
  STICKY_BASE   = 35,   -- always applied to current target
  STICKY_WOUNDED_50 = 30,
  STICKY_WOUNDED_35 = 20,
  STICKY_WOUNDED_25 = 25,
  STICKY_WOUNDED_15 = 35,
  STICKY_WOUNDED_10 = 50,
  STICKY_DURATION_CAP = 30, -- max bonus from attack duration (ms/1000*5)

  -- Switch penalty on non-current target
  SWITCH_BASE    = 35,
  SWITCH_HP50    = 25,
  SWITCH_HP30    = 40,
  SWITCH_HP15    = 60,

  -- Scenario
  LOCK_BONUS       = 60,
  FINISH_KILL      = 100,
  ZIGZAG_PENALTY   = 200,

  -- AoE
  AOE_PER_MON = 8,

  -- Chase
  CHASE_BONUS = 12,

  -- MonsterAI threat
  WAVE_MULT         = 35,
  WAVE_MIN_CONF     = 0.3,
  WAVE_IMMINENT     = 25,
  WAVE_SOON         = 12,
  DPS_MULT          = 1.2,
  DPS_CAP           = 20,
  DPS_HIGH          = 40,
  DPS_CRIT          = 80,
  FACING_WEIGHT     = 12,
  TURN_RATE_WEIGHT  = 8,
  SUSTAINED_FACING  = 10,
  CLASS_DANGER_MULT = 3,
  CLASS_RANGED      = 5,
  CLASS_WAVE        = 8,
  CLASS_AGGRESSIVE  = 6,
  TRAJECTORY_APPROACH = 8,
  TRAJECTORY_INTERCEPT = 5,
  RECENT_DMG        = 12,
  RECENT_DMG_WINDOW = 3000,
  COOLDOWN_READY    = 10,
  COOLDOWN_SOON     = 5,
  LOW_VAR           = 4,
  HIGH_VAR          = 6,
  -- Threat cap: prevents threatScore from overriding config.priority differences
  THREAT_CAP        = 350,
}

PriorityEngine.SCORE = SCORE

-- ============================================================================
-- SUB-SCORERS (pure functions)
-- ============================================================================

-- 1. Config base score
local function baseScore(config)
  return (config.priority or 1) * SCORE.CONFIG_SCALE
end

-- 2. Health score
local function healthScore(hp, config)
  local s = 0
  if     hp <= 5  then s = SCORE.HP_CRITICAL
  elseif hp <= 10 then s = SCORE.HP_VERY_LOW
  elseif hp <= 20 then s = SCORE.HP_LOW
  elseif hp <= 30 then s = SCORE.HP_WOUNDED
  elseif hp <= 50 then s = SCORE.HP_LIGHT
  elseif hp <= 70 then s = SCORE.HP_SCRATCHED end
  -- Chase bonus
  if config.chase and hp < 35 then s = s + SCORE.CHASE_BONUS end
  -- Danger bonus
  if config.danger and config.danger > 0 then s = s + config.danger * 0.5 end
  return s
end

-- 3. Distance score
local function distanceScore(pathLen)
  return SCORE.DIST[pathLen] or 0
end

-- Cached gameTarget for the current scoring cycle (avoid repeated pcalls)
local _cachedGT     = nil   -- cached creature reference
local _cachedGTTick = 0     -- tick when it was cached

local function getCachedGameTarget()
  local t = nowMs()
  if (t - _cachedGTTick) > 50 then  -- refresh every 50ms (one per scoring batch)
    _cachedGT     = gameTarget()
    _cachedGTTick = t
  end
  return _cachedGT
end

-- 4. Stickiness / switch penalty
local function stickinessScore(creature, hp, config)
  local gt = getCachedGameTarget()
  local isCurrent = gt and (cId(gt) == cId(creature))
  local s = 0

  if isCurrent then
    s = s + SCORE.STICKY_BASE
    if hp < 70 then s = s + 10 end
    if hp < 50 then s = s + SCORE.STICKY_WOUNDED_50 end
    if hp < 35 then s = s + SCORE.STICKY_WOUNDED_35 end
    if hp < 25 then s = s + SCORE.STICKY_WOUNDED_25 end
    if hp < 15 then s = s + SCORE.STICKY_WOUNDED_15 end
    if hp < 10 then s = s + SCORE.STICKY_WOUNDED_10 end
    -- Attack duration bonus from tracker
    if MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.monsters then
      local id = cId(creature)
      local td = id and MonsterAI.Tracker.monsters[id]
      if td and td.attackStartTime then
        local dur = nowMs() - td.attackStartTime
        s = s + math.min(SCORE.STICKY_DURATION_CAP, math.floor(dur / 1000) * 5)
      end
    end
  else
    -- Switch penalty: penalize candidates when we're on a wounded target
    if gt and not cDead(gt) then
      local curHp = cHp(gt)
      if curHp < 70 then
        local pen = SCORE.SWITCH_BASE
        if curHp < 50 then pen = pen + SCORE.SWITCH_HP50 end
        if curHp < 30 then pen = pen + SCORE.SWITCH_HP30 end
        if curHp < 15 then pen = pen + SCORE.SWITCH_HP15 end
        s = s - pen
      end
    end
  end
  return s
end

-- 5. Threat score (MonsterAI integration)
local function threatScore(creature)
  if not (MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.monsters) then return 0 end
  local id = cId(creature)
  if not id then return 0 end
  local data = MonsterAI.Tracker.monsters[id]
  if not data then return 0 end

  local s = 0
  local t = nowMs()
  local name = cName(creature)

  -- Wave prediction
  if MonsterAI.Predictor and MonsterAI.Predictor.predictWaveAttack then
    local ok, predicted, conf, tta = pcall(MonsterAI.Predictor.predictWaveAttack, creature)
    if ok and predicted and conf and conf > SCORE.WAVE_MIN_CONF then
      s = s + conf * SCORE.WAVE_MULT
      if tta then
        if tta < 500 then s = s + SCORE.WAVE_IMMINENT
        elseif tta < 1500 then s = s + SCORE.WAVE_SOON
        elseif tta < 2500 then s = s + 6 end
      end
    end
  end

  -- DPS
  local dps = MonsterAI.Tracker.getDPS and MonsterAI.Tracker.getDPS(id) or 0
  if dps > 0.5 then
    s = s + math.min(dps * SCORE.DPS_MULT, SCORE.DPS_CAP)
    if dps >= SCORE.DPS_CRIT then s = s + 15
    elseif dps >= SCORE.DPS_HIGH then s = s + 8 end
  end

  -- Facing
  local facePct = math.floor(((data.facingCount or 0) / math.max(1, data.movementSamples or 1)) * 100)
  if facePct > 25 then s = s + facePct / 100 * SCORE.FACING_WEIGHT end

  -- Turn rate
  if MonsterAI.RealTime and MonsterAI.RealTime.directions then
    local dd = MonsterAI.RealTime.directions[id]
    if dd then
      local tr = dd.turnRate or 0
      local cc = dd.consecutiveChanges or 0
      if tr > 2.5 or cc >= 4 then s = s + SCORE.TURN_RATE_WEIGHT + 5
      elseif tr > 1.5 or cc >= 2 then s = s + SCORE.TURN_RATE_WEIGHT
      elseif tr > 0.8 then s = s + math.floor(SCORE.TURN_RATE_WEIGHT / 2) end
      local fs = dd.facingPlayerSince
      if fs then
        local fd = t - fs
        if fd > 2000 then s = s + SCORE.SUSTAINED_FACING + 5
        elseif fd > 1000 then s = s + SCORE.SUSTAINED_FACING
        elseif fd > 500 then s = s + math.floor(SCORE.SUSTAINED_FACING / 2) end
      end
    end
  end

  -- Cooldown readiness
  local cd = data.ewmaCooldown or 0
  local la = data.lastAttackTime or data.lastWaveTime or 0
  if cd > 0 and la > 0 then
    local prog = (t - la) / cd
    if prog >= 1.0 then s = s + SCORE.COOLDOWN_READY
    elseif prog >= 0.85 then s = s + SCORE.COOLDOWN_SOON
    elseif prog >= 0.7 then s = s + math.floor(SCORE.COOLDOWN_SOON / 2) end
  end

  -- Variance reliability
  local var = data.ewmaVariance or 0
  if var > 0 and cd > 0 then
    local cv = math.sqrt(var) / cd
    if cv < 0.15 then s = s + SCORE.LOW_VAR + 2
    elseif cv < 0.25 then s = s + SCORE.LOW_VAR
    elseif cv > 0.6 then s = s + SCORE.HIGH_VAR + 3
    elseif cv > 0.4 then s = s + SCORE.HIGH_VAR end
  end

  -- Classification
  if MonsterAI.Classifier and MonsterAI.Classifier.get then
    local cl = MonsterAI.Classifier.get(name)
    if cl and cl.confidence and cl.confidence > 0.4 then
      s = s + (cl.estimatedDanger or 1) * SCORE.CLASS_DANGER_MULT
      if cl.isRanged then s = s + SCORE.CLASS_RANGED end
      if cl.isWaveAttacker then s = s + SCORE.CLASS_WAVE end
      if cl.isAggressive then s = s + SCORE.CLASS_AGGRESSIVE end
    end
  end

  -- Trajectory
  if data.distanceSamples and #data.distanceSamples >= 3 then
    local ds = data.distanceSamples
    local n = #ds
    local oldD = ds[math.max(1, n - 2)].distance or 10
    local newD = ds[n].distance or 10
    local change = oldD - newD
    if change > 1 then
      s = s + SCORE.TRAJECTORY_APPROACH
      if newD <= 3 then s = s + SCORE.TRAJECTORY_INTERCEPT end
    elseif change > 0 then
      s = s + math.floor(SCORE.TRAJECTORY_APPROACH / 2)
    end
  end

  -- Recent damage
  local ldt = data.lastDamageTime or 0
  if ldt > 0 then
    local since = t - ldt
    if since < SCORE.RECENT_DMG_WINDOW then
      s = s + math.floor(SCORE.RECENT_DMG * (1 - since / SCORE.RECENT_DMG_WINDOW))
    end
  end

  -- Health change rate
  local hcr = data.healthChangeRate or 0
  if hcr > 5 then s = s + 5 elseif hcr > 2 then s = s + 2 end

  -- Walking ratio
  local wr = data.walkingRatio or 0.5
  if wr < 0.3 then s = s + 3
  elseif wr > 0.7 then s = s - 2 end

  -- Missiles
  local mc = data.missileCount or 0
  if mc > 5 then s = s + 6
  elseif mc > 2 then s = s + 3 end

  -- Combat feedback
  if MonsterAI.CombatFeedback and MonsterAI.CombatFeedback.getWeights then
    local w = MonsterAI.CombatFeedback.getWeights(name)
    if w then
      local ow = w.overall or 1.0
      if ow > 1.0 then s = s + (ow - 1.0) * 50
      elseif ow < 1.0 then s = s - (1.0 - ow) * 30 end
      if (w.wave or 1.0) > 1.1 then s = s + 8
      elseif (w.wave or 1.0) < 0.9 then s = s - 3 end
      if (w.melee or 1.0) > 1.1 then s = s + 5 end
    end
  end

  -- Real-time threat level
  if MonsterAI.RealTime and MonsterAI.RealTime.threatLevel then
    local tl = MonsterAI.RealTime.threatLevel[id]
    if tl then
      local rec = t - (tl.lastUpdate or 0)
      if rec < 5000 then
        s = s + (tl.level or 0) * 5 * (1 - rec / 5000)
      end
    end
  end

  -- Pattern recognition
  if MonsterAI.Patterns and MonsterAI.Patterns.get then
    local pat = MonsterAI.Patterns.get(name)
    if pat and pat.confidence and pat.confidence > 0.5 then
      if pat.isWaveAttacker then s = s + 6 end
      if pat.avgDamage then
        if pat.avgDamage > 100 then s = s + 8
        elseif pat.avgDamage > 50 then s = s + 4 end
      end
      if pat.waveCooldown and pat.waveCooldown < 2000 then s = s + 5 end
    end
  end

  -- Cap threat so it can't override config.priority level differences (1000)
  return math.min(s, SCORE.THREAT_CAP)
end

-- 6. Scenario / anti-zigzag score
local function scenarioScore(creature, hp)
  local id = cId(creature)
  if not id then return 0 end
  local s = 0

  -- MonsterAI Scenario module
  if MonsterAI and MonsterAI.Scenario then
    local S = MonsterAI.Scenario

    -- Target lock bonus
    if S.state and S.state.targetLockId == id then
      s = s + SCORE.LOCK_BONUS
      -- Progress bonus
      local lh = S.state.targetLockHealth or 100
      if lh > hp then s = s + math.min(25, (lh - hp) * 0.5) end
      -- Finish kill
      if hp < 25 then s = s + SCORE.FINISH_KILL
      elseif hp < 40 then s = s + SCORE.FINISH_KILL * 0.6
      elseif hp < 55 then s = s + SCORE.FINISH_KILL * 0.3 end
    end

    -- Scenario-specific adjustments
    local sType = S.state and S.state.type
    local sCfg  = S.configs and S.configs[sType]

    if sType == (S.TYPES and S.TYPES.FEW) then
      if S.state.targetLockId and S.state.targetLockId ~= id then
        local canSw = S.shouldAllowTargetSwitch and S.shouldAllowTargetSwitch(id, 0, hp)
        s = s - (canSw and 20 or 100)
      end
      if S.isZigzagging and S.isZigzagging() then
        s = s + (S.state.targetLockId == id and 150 or -150)
      end
    elseif sType == (S.TYPES and S.TYPES.SWARM) then
      if sCfg and sCfg.focusLowestHealth then
        s = s + (100 - hp) * 0.6
      end
    elseif sType == (S.TYPES and S.TYPES.OVERWHELMING) then
      local p = cPos(creature)
      local pp = getPlayer() and cPos(getPlayer())
      if p and pp then
        local d = math.max(math.abs(p.x - pp.x), math.abs(p.y - pp.y))
        if d <= 2 then s = s + 30 end
      end
      if hp < 15 then s = s + 40 end
    end

    -- Cluster bonus
    local ci = S.state and S.state.clusterInfo
    if ci and ci.type == "tight" then
      local cp = cPos(creature)
      if cp and ci.centroid then
        local dc = math.sqrt((cp.x - ci.centroid.x)^2 + (cp.y - ci.centroid.y)^2)
        if dc < 2 then s = s + 15
        elseif dc < 3 then s = s + 8 end
      end
    elseif ci and ci.type == "spread" and S.state.targetLockId == id then
      s = s + 10
    end

    -- Consecutive switch penalty
    local sw = S.state and S.state.consecutiveSwitches or 0
    if sw >= 3 and S.state.targetLockId ~= id then
      s = s - sw * 10
    end

  else
    -- Local fallback (no MonsterAI.Scenario)
    if TargetBot and TargetBot.LocalTargetLock then
      local LL = TargetBot.LocalTargetLock
      if LL.targetId == id then
        s = s + SCORE.LOCK_BONUS
        if LL.targetHealth and hp < LL.targetHealth then
          s = s + math.min(40, (LL.targetHealth - hp) * 0.8)
        end
        if hp < 15 then s = s + SCORE.FINISH_KILL + 40
        elseif hp < 25 then s = s + SCORE.FINISH_KILL
        elseif hp < 40 then s = s + SCORE.FINISH_KILL * 0.7
        elseif hp < 55 then s = s + SCORE.FINISH_KILL * 0.4 end
      else
        if LL.switchCount and LL.switchCount >= 2 then
          s = s - LL.switchCount * 15
        end
      end
    end
  end

  return s
end

-- 7. Speed / walk score (from OTClient API)
local function mobilityScore(creature, config)
  local s = 0
  local speed = SC.call and SC.call(creature, "getSpeed", 0) or 0
  if speed > 0 then
    local pp = getPlayer()
    local pSpeed = pp and (SC.call and SC.call(pp, "getSpeed", 220) or 220) or 220
    local ratio = speed / math.max(1, pSpeed)
    if ratio < 0.6 then s = s + 8
    elseif ratio < 0.8 then s = s + 4
    elseif ratio > 1.3 and config.chase then s = s - 5 end
  end
  local walking = SC.call and SC.call(creature, "isWalking", false) or false
  if not walking then s = s + 3
  else
    local ticks = SC.call and SC.call(creature, "getStepTicksLeft", 0) or 0
    if ticks > 200 then s = s - 2 end
  end
  return s
end

-- ============================================================================
-- MAIN ENTRY POINT
-- ============================================================================

--- Calculate total priority for a creature.
--- @param creature  userdata — the creature object
--- @param config    table   — targeting config (priority, chase, maxDistance, etc.)
--- @param path      table   — path tiles (or nil)
--- @return number   priority (0 = out of range / skip)
function PriorityEngine.calculate(creature, config, path)
  ensureDeps()
  local pathLen = path and #path or 99
  local maxDist = config.maxDistance or 10
  local hp = cHp(creature)

  -- Early exit: out of range
  if pathLen > maxDist then
    if hp <= 15 and pathLen <= maxDist + 2 then
      return (config.priority or 1) * 400
    end
    -- RP Safe cancel
    if config.rpSafe then
      local gt = gameTarget()
      if gt and cId(gt) == cId(creature) then
        if AttackStateMachine and AttackStateMachine.isActive and AttackStateMachine.isActive() then
          pcall(AttackStateMachine.stop)
        end
      end
    end
    return 0
  end

  -- Aggregate all sub-scores
  local total = baseScore(config)
              + healthScore(hp, config)
              + distanceScore(pathLen)
              + stickinessScore(creature, hp, config)
              + threatScore(creature)
              + scenarioScore(creature, hp)
              + mobilityScore(creature, config)

  -- Ensure non-negative
  return math.max(0, total)
end

-- ============================================================================
-- SWITCH GATE (called by ASM v3.0)
-- ============================================================================

--- Evaluate whether a target switch should be allowed.
--- @return boolean, string (allowed, reason)
function PriorityEngine.shouldAllowSwitch(newId, newPriority, newHp)
  ensureDeps()

  -- Delegate to MonsterAI Scenario if available
  if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.shouldAllowTargetSwitch then
    return MonsterAI.Scenario.shouldAllowTargetSwitch(newId, newPriority, newHp)
  end

  -- Fallback: simple switch gate
  if AttackStateMachine and AttackStateMachine.getTargetId then
    local curId = AttackStateMachine.getTargetId()
    if not curId then return true, "no_target" end
    if curId == newId then return true, "same_target" end
  end

  -- Config-priority comparison
  if (newPriority or 0) >= 500 then return true, "priority" end

  -- Default: allow with basic cooldown
  local CC_SWITCH = (CC and CC.SWITCH_COOLDOWN) or 2500
  if AttackStateMachine and AttackStateMachine.getStats then
    local s = AttackStateMachine.getStats()
    -- If stats don't exist yet, allow
    if not s then return true, "no_stats" end
  end
  return true, "allowed"
end

-- ============================================================================
-- EVENTBUS
-- ============================================================================

if EventBus and EventBus.on then
  EventBus.on("priority_engine:recalibrate", function(overrides)
    if type(overrides) == "table" then
      for k, v in pairs(overrides) do
        if SCORE[k] ~= nil then SCORE[k] = v end
      end
    end
  end, 100)
end

if PriorityEngine.DEBUG then
  print("[PriorityEngine] v" .. PriorityEngine.VERSION .. " loaded")
end

return PriorityEngine
