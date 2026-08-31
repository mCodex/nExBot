AttackFSM = AttackFSM or {}
AttackFSM.VERSION = "1.0"

local S = {
  IDLE               = "IDLE",
  ACQUIRING          = "ACQUIRING",
  ATTACKING          = "ATTACKING",
  CONFIRMING_ATTACK  = "CONFIRMING_ATTACK",
  LOCKED             = "LOCKED",
  REPOSITIONING      = "REPOSITIONING",
  TEMPORARILY_BLOCKED = "TEMPORARILY_BLOCKED",
  RECOVERING_TARGET  = "RECOVERING_TARGET",
  STALLED            = "STALLED",
  RELEASING          = "RELEASING",
}

AttackFSM.STATE = S

local SC
local CC

local function ensureDeps()
  if not SC then SC = SafeCreature or SC or {} end
  if not CC then
    CC = CombatConstants or {
      TICK_INTERVAL = 100, COMMAND_COOLDOWN = 350, CONFIRM_TIMEOUT = 1200,
      GRACE_PERIOD = 1500, STOP_DEBOUNCE = 150,
      REAFFIRM_RETRY_MAX = 5, ENGAGE_BACKOFF_BASE = 1500,
      ENGAGE_BACKOFF_GROWTH = 1.5, SWITCH_COOLDOWN = 2500,
      CONFIG_SWITCH_COOLDOWN = 400, CRITICAL_HP = 25,
      PATH_SKIP_DURATION = 10000,
    }
  end
end

local nowMs = nExBot.Shared.nowMs
local getClient = nExBot.Shared.getClient

local function cId(c)
  if not c then return nil end
  ensureDeps()
  if SC.getId then return SC.getId(c) end
  local ok, v = pcall(function() return c:getId() end)
  return ok and v or nil
end

local function cHp(c)
  if not c then return 0 end
  ensureDeps()
  if SC.getHealthPercent then return SC.getHealthPercent(c) end
  local ok, v = pcall(function() return c:getHealthPercent() end)
  return ok and v or 0
end

local function cDead(c)
  if not c then return true end
  ensureDeps()
  if SC.isDead then return SC.isDead(c) end
  local ok, v = pcall(function() return c:isDead() end)
  return (ok and v == true) or cHp(c) <= 0
end

local function cName(c)
  if not c then return "?" end
  ensureDeps()
  if SC.getName then return SC.getName(c) end
  local ok, v = pcall(function() return c:getName() end)
  return ok and v or "?"
end

local st = {
  current         = S.IDLE,
  previous        = nil,
  enteredAt       = 0,
  generation      = 0,
  connectionGeneration = 0,

  targetId        = nil,
  selectedTarget  = nil,
  creature        = nil,
  hp              = 100,
  priority        = 0,

  lastCommandAt   = 0,
  lastConfirmedAt = 0,
  commandSentAt   = 0,
  clientTargetConfirmedAt = 0,
  lastProgressAt  = 0,
  recoveryAttempt = 0,
  recoveryAttemptAt = 0,
  retries         = 0,
  currentTimeout  = 0,

  lastStopAt      = 0,
  lastSwitchAt    = 0,

  holdTargetId    = nil,
  holdTargetName  = nil,

  _pendingSwitch  = nil,
  _holdAcquiredAt = 0,

  stats = {
    commands   = 0,
    confirms   = 0,
    kills      = 0,
    switches   = 0,
    cancellations = 0,
  },
}

local lastTick = 0

local function transition(to, reason)
  if st.current == to then return end
  st.previous  = st.current
  st.current   = to
  st.enteredAt = nowMs()
  st.generation = st.generation + 1

  if to == S.IDLE then
    st.retries = 0
    st.currentTimeout = 0
  end
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

local function isConfirmedInternal()
  if st.commandSentAt == 0 then return false end
  local gt = gameTarget()
  if not gt then return false end
  local gtId = cId(gt)
  return gtId ~= nil and gtId == st.targetId
end

local function sendAttack(creature, forceDispatch)
  if not creature or cDead(creature) then return false end
  ensureDeps()

  if ReachabilityService and ReachabilityService.evaluate then
    local result = ReachabilityService.evaluate(creature, { source = "attack_boundary" })
    if not result.attackable then return false end
  end

  local t = nowMs()
  if (t - st.lastCommandAt) < CC.COMMAND_COOLDOWN then return false end
  if (t - st.lastStopAt) < CC.STOP_DEBOUNCE then return false end

  local gt = gameTarget()
  if gt then
    local gtId = cId(gt)
    if gtId and gtId == cId(creature) and not forceDispatch then
      st.lastCommandAt = t
      return true
    end
  end

  local ok = false
  local C = getClient()
  if C and C.attack then
    local called, result = pcall(C.attack, creature)
    ok = called and result ~= false
  elseif g_game and g_game.attack then
    local called, result = pcall(g_game.attack, creature)
    ok = called and result ~= false
  end

  if ok then
    st.lastCommandAt = t
    st.commandSentAt = t
    st.stats.commands = st.stats.commands + 1
  end
  return ok
end

local function cancelAttack()
  local C = getClient()
  if C and C.cancelAttackAndFollow then
    pcall(C.cancelAttackAndFollow)
  elseif g_game and g_game.cancelAttackAndFollow then
    pcall(g_game.cancelAttackAndFollow)
  end
  st.stats.cancellations = st.stats.cancellations + 1
end

local function clearTarget()
  st.creature    = nil
  st.selectedTarget = nil
  st.targetId    = nil
  st.hp          = 100
  st.priority    = 0
  st.currentTimeout = 0
  st._pendingSwitch = nil
  st.commandSentAt = 0
  st.clientTargetConfirmedAt = 0
  st.lastProgressAt = 0
  st.recoveryAttempt = 0
  st.recoveryAttemptAt = 0
end

local function setTarget(creature, priority, reason)
  st.creature    = creature
  st.selectedTarget = creature
  st.targetId    = cId(creature)
  st.hp          = cHp(creature)
  st.priority    = priority or 0
  st.retries     = 0
  st.currentTimeout = 0
  st.commandSentAt = 0
  st.clientTargetConfirmedAt = 0
  st.lastProgressAt = 0
  st.recoveryAttempt = 0
  st.recoveryAttemptAt = 0
  st._pendingSwitch = nil
  st.lastSwitchAt = nowMs()
  st.stats.switches = st.stats.switches + 1
  st.holdTargetId   = st.targetId
  st.holdTargetName = cName(creature)
  st._holdAcquiredAt = 0
  transition(S.ACQUIRING, reason or "new_target")
  return sendAttack(creature)
end

local function evaluateReachability(creature)
  if not ReachabilityService or not ReachabilityService.evaluate then
    return { state = ReachabilityState and ReachabilityState.ATTACKABLE_NOW or "ATTACKABLE_NOW", attackable = true }
  end
  return ReachabilityService.evaluate(creature, { source = "fsm" })
end

local function isHardReleaseState(rState)
  if ReachabilityState and ReachabilityState.isHardRelease then
    return ReachabilityState.isHardRelease(rState)
  end
  return false
end

local function isTemporaryState(rState)
  if ReachabilityState and ReachabilityState.isTemporary then
    return ReachabilityState.isTemporary(rState)
  end
  return false
end

local function commitmentBlocksRelease()
  if not st.targetId then return false end
  if TargetCommitmentManager and TargetCommitmentManager.blocksRelease then
    return TargetCommitmentManager.blocksRelease(st.targetId, "STRICT_FOLLOW_OVERRIDE")
  end
  return false
end

local function handleAcquiring()
  if not st.creature or cDead(st.creature) then
    st.stats.kills = st.stats.kills + 1
    clearTarget()
    transition(S.IDLE, "target_died")
    return
  end

  if st.currentTimeout > 0 and (nowMs() - st.enteredAt) < st.currentTimeout then return end

  if sendAttack(st.creature) and isConfirmedInternal() then
    st.clientTargetConfirmedAt = nowMs()
    st.lastConfirmedAt = st.clientTargetConfirmedAt
    st.lastProgressAt = st.clientTargetConfirmedAt
    st.stats.confirms = st.stats.confirms + 1
    transition(S.ATTACKING, "attack_confirmed")
  else
    if st.currentTimeout == 0 then st.currentTimeout = 200 end
    if (nowMs() - st.enteredAt) < st.currentTimeout then return end
    st.enteredAt = nowMs()
    st.currentTimeout = math.min(st.currentTimeout * 2, 3000)
  end
end

local function handleAttacking()
  if not st.creature or cDead(st.creature) then
    st.stats.kills = st.stats.kills + 1
    clearTarget()
    transition(S.IDLE, "target_died")
    return
  end

  if isConfirmedInternal() then
    st.clientTargetConfirmedAt = st.clientTargetConfirmedAt ~= 0 and st.clientTargetConfirmedAt or nowMs()
    transition(S.LOCKED, "confirmed")
    return
  end

  if st.currentTimeout == 0 then
    st.currentTimeout = CC.ENGAGE_BACKOFF_BASE
  end

  if (nowMs() - st.enteredAt) > st.currentTimeout then
    st.retries = st.retries + 1
    if st.retries >= CC.REAFFIRM_RETRY_MAX then
      if commitmentBlocksRelease() then
        transition(S.TEMPORARILY_BLOCKED, "max_retries_committed")
      else
        clearTarget()
        transition(S.IDLE, "max_retries")
      end
      return
    end
    st.currentTimeout = math.min(st.currentTimeout * CC.ENGAGE_BACKOFF_GROWTH, 5000)
    st.enteredAt = nowMs()
    transition(S.CONFIRMING_ATTACK, "retry")
  end
end

local function handleConfirmingAttack()
  if not st.creature or cDead(st.creature) then
    st.stats.kills = st.stats.kills + 1
    clearTarget()
    transition(S.IDLE, "target_died")
    return
  end

  if isConfirmedInternal() then
    st.lastConfirmedAt = nowMs()
    st.stats.confirms = st.stats.confirms + 1
    transition(S.LOCKED, "late_confirmed")
    return
  end

  if st.currentTimeout == 0 then
    st.currentTimeout = CC.ENGAGE_BACKOFF_BASE
  end

  if (nowMs() - st.enteredAt) > st.currentTimeout then
    st.retries = st.retries + 1
    if st.retries >= CC.REAFFIRM_RETRY_MAX then
      if commitmentBlocksRelease() then
        transition(S.TEMPORARILY_BLOCKED, "confirm_max_committed")
      else
        clearTarget()
        transition(S.IDLE, "confirm_max")
      end
      return
    end
    st.currentTimeout = math.min(st.currentTimeout * CC.ENGAGE_BACKOFF_GROWTH, 5000)
    st.enteredAt = nowMs()
    sendAttack(st.creature)
  end
end

local function handleLocked()
  if not st.creature or cDead(st.creature) then
    st.stats.kills = st.stats.kills + 1
    clearTarget()
    transition(S.IDLE, "target_killed")
    return
  end

  local currentHp = cHp(st.creature)
  if currentHp < st.hp then
    st.lastProgressAt = nowMs()
    st.recoveryAttempt = 0
  end
  st.hp = currentHp

  if st._pendingSwitch then
    local ps = st._pendingSwitch
    st._pendingSwitch = nil
    if TargetCandidateEvaluator and TargetCandidateEvaluator.compare then
      local curScore = {
        safetyTier = 2, commitmentTier = 0,
        configuredPriority = st.priority, killCompletionScore = (100 - st.hp) / 100,
        attackContinuityScore = 1.0, reachabilityConfidence = 1.0,
        pathCost = 1, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local candScore = {
        safetyTier = 2, commitmentTier = 0,
        configuredPriority = ps.priority, killCompletionScore = (100 - cHp(ps.creature)) / 100,
        attackContinuityScore = 0.0, reachabilityConfidence = 1.0,
        pathCost = 1, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local winner = TargetCandidateEvaluator.compare(curScore, candScore)
      if winner == "B" then
        local blocked = TargetCommitmentManager and TargetCommitmentManager.blocksRelease
          and TargetCommitmentManager.blocksRelease(st.targetId, "STRICT_FOLLOW_OVERRIDE")
        if not blocked then
          setTarget(ps.creature, ps.priority, "pending_switch")
          return
        end
      end
    end
  end

  local r = evaluateReachability(st.creature)
  if not r.attackable then
    if isHardReleaseState(r.state) then
      if commitmentBlocksRelease() then
        transition(S.TEMPORARILY_BLOCKED, "hard_failure_committed")
      else
        transition(S.RELEASING, "hard_failure")
      end
    elseif isTemporaryState(r.state) then
      transition(S.TEMPORARILY_BLOCKED, "temporary_failure")
    else
      if commitmentBlocksRelease() then
        transition(S.TEMPORARILY_BLOCKED, "unknown_failure_committed")
      else
        transition(S.RELEASING, "unknown_failure")
      end
    end
    return
  end

  if (nowMs() - (st.lastProgressAt > 0 and st.lastProgressAt or st.clientTargetConfirmedAt)) > CC.GRACE_PERIOD then
    st.retries = 0
    st.currentTimeout = 0
    st.recoveryAttempt = 0
    st.recoveryAttemptAt = nowMs()
    transition(S.STALLED, "progress_stalled")
  end
end

local function handleStalled()
  if not st.creature or cDead(st.creature) then
    clearTarget()
    transition(S.IDLE, "target_gone")
    return
  end

  local elapsed = nowMs() - st.recoveryAttemptAt
  local retryAt = ({ 200, 1000, 3000 })[st.recoveryAttempt + 1]
  if st.recoveryAttempt >= 3 then
    if elapsed < 3000 then return end
    transition(S.RELEASING, "stall_recovery_exhausted")
    return
  end
  if elapsed < retryAt then return end

  st.recoveryAttempt = st.recoveryAttempt + 1
  st.recoveryAttemptAt = nowMs()
  st.commandSentAt = 0
  if sendAttack(st.creature, true) then
    if isConfirmedInternal() then
      st.clientTargetConfirmedAt = nowMs()
      st.lastConfirmedAt = st.clientTargetConfirmedAt
      st.lastProgressAt = nowMs()
      st.currentTimeout = 0
      transition(S.LOCKED, "stall_recovery_confirmed")
    else
      transition(S.RECOVERING_TARGET, "stall_retry_sent")
    end
  end
end

local function handleTemporarilyBlocked()
  if not st.creature then
    transition(S.IDLE, "no_target")
    return
  end

  if cDead(st.creature) then
    st.stats.kills = st.stats.kills + 1
    clearTarget()
    transition(S.IDLE, "target_died")
    return
  end

  local r = evaluateReachability(st.creature)
  if r.attackable then
    transition(S.RECOVERING_TARGET, "reachable_again")
    return
  end

  if isHardReleaseState(r.state) then
    if commitmentBlocksRelease() then
      return
    end
    transition(S.RELEASING, "hard_release_from_blocked")
    return
  end

  local retryInterval = CC.ENGAGE_BACKOFF_BASE
  if (nowMs() - st.enteredAt) > retryInterval then
    st.retries = st.retries + 1
    if st.retries >= CC.REAFFIRM_RETRY_MAX then
      if commitmentBlocksRelease() then
        st.enteredAt = nowMs()
        st.retries = 0
        return
      end
      clearTarget()
      transition(S.IDLE, "blocked_max_retries")
      return
    end
    st.enteredAt = nowMs()
    transition(S.RECOVERING_TARGET, "retry_from_blocked")
  end
end

local function handleRecoveringTarget()
  if not st.creature or cDead(st.creature) then
    st.stats.kills = st.stats.kills + 1
    clearTarget()
    transition(S.IDLE, "target_died")
    return
  end

  if isConfirmedInternal() then
    st.lastConfirmedAt = nowMs()
    st.stats.confirms = st.stats.confirms + 1
    st.retries = 0
    transition(S.LOCKED, "recovered")
    return
  end

  local r = evaluateReachability(st.creature)
  if r.attackable and sendAttack(st.creature) then
    if isConfirmedInternal() then
      st.lastConfirmedAt = nowMs()
      st.retries = 0
      transition(S.LOCKED, "recovered_after_send")
      return
    end
    st.retries = 0
    transition(S.ATTACKING, "reacquire_sent")
    return
  end

  if (nowMs() - st.enteredAt) > CC.ENGAGE_BACKOFF_BASE then
    st.retries = st.retries + 1
    if st.retries >= CC.REAFFIRM_RETRY_MAX then
      if commitmentBlocksRelease() then
        transition(S.TEMPORARILY_BLOCKED, "recovery_max_committed")
      else
        clearTarget()
        transition(S.IDLE, "recovery_max")
      end
      return
    end
    st.enteredAt = nowMs()
  end
end

local function handleReleasing()
  cancelAttack()
  clearTarget()
  transition(S.IDLE, "released")
end

local function update()
  ensureDeps()

  if TargetBot and TargetBot.isOn and not TargetBot.isOn() then
    if st.current ~= S.IDLE then
      cancelAttack()
      clearTarget()
      transition(S.IDLE, "targetbot_off")
    end
    return
  end

  local t = nowMs()
  if (t - lastTick) < CC.TICK_INTERVAL then return end
  lastTick = t

  if st.current == S.IDLE then
    if (t - st.lastStopAt) < CC.STOP_DEBOUNCE then return end

    if st.holdTargetId then
      if st._holdAcquiredAt == 0 then st._holdAcquiredAt = t end
      local ok, specs = pcall(BotCore.Creatures.getNearby, 7, 5)
      specs = ok and specs or {}
      for _, spec in ipairs(specs) do
        local quarantined = TargetReachability and TargetReachability.isQuarantined
          and TargetReachability.isQuarantined(spec)
        if cId(spec) == st.holdTargetId and not cDead(spec) and not quarantined then
          setTarget(spec, st.priority, "hold_reacquire")
          return
        end
      end
      if (t - st._holdAcquiredAt) > 10000 then
        st.holdTargetId   = nil
        st.holdTargetName = nil
        st._holdAcquiredAt = 0
      end
    end
  elseif st.current == S.ACQUIRING then
    handleAcquiring()
  elseif st.current == S.ATTACKING then
    handleAttacking()
  elseif st.current == S.CONFIRMING_ATTACK then
    handleConfirmingAttack()
  elseif st.current == S.LOCKED then
    handleLocked()
  elseif st.current == S.REPOSITIONING then
  elseif st.current == S.TEMPORARILY_BLOCKED then
    handleTemporarilyBlocked()
  elseif st.current == S.RECOVERING_TARGET then
    handleRecoveringTarget()
  elseif st.current == S.STALLED then
    handleStalled()
  elseif st.current == S.RELEASING then
    handleReleasing()
  end
end

function AttackFSM.requestAttack(creature, priority)
  if not creature or cDead(creature) then return false end
  ensureDeps()
  if (nowMs() - st.lastStopAt) < CC.STOP_DEBOUNCE then return false end

  local id = cId(creature)

  if id == st.targetId then
    if priority and priority > st.priority then
      st.priority = priority
    end
    if st.current == S.IDLE or not isConfirmedInternal() then
      st.commandSentAt = 0
      return sendAttack(creature)
    end
    return true
  end

  local r = evaluateReachability(creature)
  if not r.attackable then
    return false
  end

  if st.current == S.IDLE then
    return setTarget(creature, priority, "request")
  end

  st._pendingSwitch = { creature = creature, priority = priority or 0 }
  return true
end

function AttackFSM.forceAttack(creature)
  if not creature or cDead(creature) then return false end
  ensureDeps()

  local id = cId(creature)
  if id == st.targetId and st.current ~= S.IDLE then
    st.creature = creature
    st.retries = 0
    st.currentTimeout = 0
    return sendAttack(creature)
  end

  local r = evaluateReachability(creature)
  if not r.attackable then return false end

  st.lastStopAt = 0
  st.creature    = creature
  st.targetId    = id
  st.hp          = cHp(creature)
  st.priority    = 0
  st.retries     = 0
  st.currentTimeout = 0
  st.lastSwitchAt = nowMs()
  st.stats.switches = st.stats.switches + 1
  st.holdTargetId   = id
  st.holdTargetName = cName(creature)
  transition(S.ACQUIRING, "force")
  return true
end

function AttackFSM.stop()
  st.lastStopAt = nowMs()
  transition(S.RELEASING, "stop")
end

function AttackFSM.reset()
  st.current         = S.IDLE
  st.previous        = nil
  st.enteredAt       = 0
  st.generation      = 0
  st.connectionGeneration = 0
  st.targetId        = nil
  st.selectedTarget  = nil
  st.creature        = nil
  st.hp              = 100
  st.priority        = 0
  st.lastCommandAt   = 0
  st.lastConfirmedAt = 0
  st.commandSentAt   = 0
  st.clientTargetConfirmedAt = 0
  st.lastProgressAt  = 0
  st.recoveryAttempt = 0
  st.recoveryAttemptAt = 0
  st.retries         = 0
  st.currentTimeout  = 0
  st.lastStopAt      = 0
  st.lastSwitchAt    = 0
  st.holdTargetId    = nil
  st.holdTargetName  = nil
  st._pendingSwitch  = nil
  st._holdAcquiredAt = 0
  st.stats = { commands = 0, confirms = 0, kills = 0, switches = 0, cancellations = 0 }
end

function AttackFSM.getState()    return st.current end
function AttackFSM.getTarget()   return st.creature end
function AttackFSM.getTargetId() return st.targetId end
function AttackFSM.isProgressing()
  return st.lastProgressAt > 0 and (nowMs() - st.lastProgressAt) <= CC.GRACE_PERIOD
end

function AttackFSM.onConnectionGeneration(generation)
  if generation ~= nil then st.connectionGeneration = generation end
  if st.current == S.IDLE and not st.targetId then return end
  if st.targetId then
    st.holdTargetId = st.targetId
    st.holdTargetName = cName(st.creature)
  end
  cancelAttack()
  clearTarget()
  st.lastCommandAt = 0
  st.lastConfirmedAt = 0
  transition(S.IDLE, "connection_generation")
end

function AttackFSM.onTargetDisappeared(creature)
  if creature and cId(creature) ~= st.targetId then return false end
  if not st.targetId then return false end
  cancelAttack()
  clearTarget()
  transition(S.IDLE, "target_disappeared")
  return true
end

function AttackFSM.onHealthProgress(creature, percent)
  if not creature or cId(creature) ~= st.targetId or percent == nil then return false end
  if percent < st.hp then st.lastProgressAt = nowMs() end
  st.hp = percent
  return true
end

function AttackFSM.isActive()
  return st.current ~= S.IDLE
end

function AttackFSM.isLocked()
  return st.current == S.LOCKED
end

function AttackFSM.isConfirmed()
  return st.current == S.LOCKED and isConfirmedInternal()
end

function AttackFSM.getGeneration()
  return st.generation
end

function AttackFSM.wasRecentlyStopped()
  ensureDeps()
  return (nowMs() - st.lastStopAt) < CC.STOP_DEBOUNCE
end

function AttackFSM.setHoldTarget(creatureId, name)
  st.holdTargetId   = creatureId
  st.holdTargetName = name or "?"
end

function AttackFSM.getHoldTargetId()
  return st.holdTargetId
end

function AttackFSM.clearHoldTarget()
  st.holdTargetId   = nil
  st.holdTargetName = nil
end

function AttackFSM.getStats()
  return {
    state        = st.current,
    targetId     = st.targetId,
    targetHealth = st.hp,
    holdTargetId = st.holdTargetId,
    generation   = st.generation,
    connectionGeneration = st.connectionGeneration,
    commandSentAt = st.commandSentAt,
    clientTargetConfirmedAt = st.clientTargetConfirmedAt,
    lastProgressAt = st.lastProgressAt,
    recoveryAttempt = st.recoveryAttempt,
    stats        = st.stats,
  }
end

AttackFSM.update = update

return AttackFSM
