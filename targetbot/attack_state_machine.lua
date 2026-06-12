AttackStateMachine = AttackStateMachine or {}
AttackStateMachine.VERSION = "4.0"

local STATE = { IDLE = "IDLE", ENGAGING = "ENGAGING", LOCKED = "LOCKED" }
AttackStateMachine.STATE = STATE

local state = {
  current = STATE.IDLE, enteredAt = 0,
  creature = nil, targetId = nil, hp = 100, priority = 0,
  lastCommandAt = 0, lastConfirmedAt = 0, retries = 0,
  lastStopAt = 0, lastSwitchAt = 0,
  skipList = {},
}

local nowMs = nExBot.Shared.nowMs
local getClient = nExBot.Shared.getClient

local function cId(c)
  if not c then return nil end
  local ok, v = pcall(function() return c:getId() end)
  return ok and v or nil
end

local function cDead(c)
  if not c then return true end
  local ok, v = pcall(function() return c:isDead() end)
  return ok and v
end

local function cHp(c)
  if not c then return 0 end
  local ok, v = pcall(function() return c:getHealthPercent() end)
  return ok and v or 0
end

local function cName(c)
  if not c then return "?" end
  local ok, v = pcall(function() return c:getName() end)
  return ok and v or "?"
end

local COOLDOWN = 300
local CONFIRM_TIMEOUT = 1200
local GRACE_PERIOD = 1500
local STOP_DEBOUNCE = 150
local SWITCH_COOLDOWN = 2500
local MAX_RETRIES = 2
local SKIP_DURATION = 10000

local function transition(to)
  if state.current == to then return end
  state.current = to
  state.enteredAt = nowMs()
  if to == STATE.IDLE then
    state.lastStopAt = nowMs()
    state.retries = 0
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

local function isConfirmed()
  local gt = gameTarget()
  return gt and cId(gt) == state.targetId
end

local function sendAttack(creature)
  if not creature or cDead(creature) then return false end
  local t = nowMs()
  if (t - state.lastCommandAt) < COOLDOWN then return false end
  if (t - state.lastStopAt) < STOP_DEBOUNCE then return false end
  local gt = gameTarget()
  if gt and cId(gt) == cId(creature) then
    state.lastCommandAt = t
    return true
  end
  local C = getClient()
  local ok = false
  if C and C.attack then
    ok = pcall(C.attack, creature)
  elseif g_game and g_game.attack then
    ok = pcall(g_game.attack, creature)
  end
  if ok then state.lastCommandAt = t end
  return ok
end

local function cancelAttack()
  local C = getClient()
  if C and C.cancelAttackAndFollow then pcall(C.cancelAttackAndFollow)
  elseif g_game and g_game.cancelAttackAndFollow then pcall(g_game.cancelAttackAndFollow) end
end

local function clearTarget()
  state.creature = nil
  state.targetId = nil
  state.hp = 100
  state.priority = 0
end

local function setTarget(creature, priority)
  state.creature = creature
  state.targetId = cId(creature)
  state.hp = cHp(creature)
  state.priority = priority or 0
  state.retries = 0
  state.lastSwitchAt = nowMs()
  transition(STATE.ENGAGING)
  sendAttack(creature)
end

local function handleIdle()
  if (nowMs() - state.lastStopAt) < STOP_DEBOUNCE then return end
  local gt = gameTarget()
  if gt and not cDead(gt) then
    state.creature = gt
    state.targetId = cId(gt)
    state.hp = cHp(gt)
    state.lastConfirmedAt = nowMs()
    transition(STATE.LOCKED)
  end
end

local function handleEngaging()
  if not state.creature or cDead(state.creature) then
    clearTarget()
    transition(STATE.IDLE)
    return
  end
  if isConfirmed() then
    state.lastConfirmedAt = nowMs()
    transition(STATE.LOCKED)
    return
  end
  if (nowMs() - state.enteredAt) > CONFIRM_TIMEOUT then
    state.retries = state.retries + 1
    if state.retries > MAX_RETRIES then
      clearTarget()
      transition(STATE.IDLE)
      return
    end
    state.enteredAt = nowMs()
    sendAttack(state.creature)
  end
end

local function handleLocked()
  if not state.creature or cDead(state.creature) then
    clearTarget()
    transition(STATE.IDLE)
    return
  end
  state.hp = cHp(state.creature)
  if isConfirmed() then
    state.lastConfirmedAt = nowMs()
  elseif (nowMs() - state.lastConfirmedAt) > GRACE_PERIOD then
    state.retries = 0
    transition(STATE.ENGAGING)
  end
end

function AttackStateMachine.update()
  if TargetBot and TargetBot.isOn and not TargetBot.isOn() then
    if state.current ~= STATE.IDLE then
      clearTarget()
      transition(STATE.IDLE)
    end
    return
  end
  if state.current == STATE.IDLE then handleIdle()
  elseif state.current == STATE.ENGAGING then handleEngaging()
  elseif state.current == STATE.LOCKED then handleLocked() end
end

function AttackStateMachine.getState() return state.current end
function AttackStateMachine.getTarget() return state.creature end
function AttackStateMachine.getTargetId() return state.targetId end
function AttackStateMachine.isActive() return state.current ~= STATE.IDLE end
AttackStateMachine.isAttacking = AttackStateMachine.isActive
function AttackStateMachine.isLocked() return state.current == STATE.LOCKED end
function AttackStateMachine.isConfirmed() return state.current == STATE.LOCKED and isConfirmed() end
function AttackStateMachine.wasRecentlyStopped() return (nowMs() - state.lastStopAt) < STOP_DEBOUNCE end

function AttackStateMachine.requestAttack(creature, priority)
  if not creature or cDead(creature) then return false end
  if (nowMs() - state.lastStopAt) < STOP_DEBOUNCE then return false end
  local id = cId(creature)
  if id and state.skipList[id] and nowMs() < state.skipList[id] then return false end
  if id == state.targetId then return true end
  if state.current == STATE.IDLE then
    setTarget(creature, priority)
    return true
  end
  if (nowMs() - state.lastSwitchAt) >= SWITCH_COOLDOWN then
    setTarget(creature, priority)
    return true
  end
  return false
end

function AttackStateMachine.forceAttack(creature)
  if not creature or cDead(creature) then return false end
  local id = cId(creature)
  if id and state.skipList[id] and nowMs() < state.skipList[id] then return false end
  state.lastStopAt = 0
  setTarget(creature, 9999)
  return true
end

function AttackStateMachine.stop()
  clearTarget()
  transition(STATE.IDLE)
  cancelAttack()
end

function AttackStateMachine.skipCreature(cid, duration)
  if not cid then return end
  state.skipList[cid] = nowMs() + (duration or SKIP_DURATION)
end

function AttackStateMachine.isSkipped(cid)
  if not cid then return false end
  local exp = state.skipList[cid]
  if not exp then return false end
  if nowMs() >= exp then state.skipList[cid] = nil; return false end
  return true
end

AttackStateMachine.requestSwitch = AttackStateMachine.requestAttack
AttackStateMachine.forceSwitch = AttackStateMachine.forceAttack

function AttackStateMachine.isPathBlocked() return false end
function AttackStateMachine.findBestTarget() return nil, 0 end
function AttackStateMachine.clearSkipList() state.skipList = {} end
function AttackStateMachine.getStats()
  return { state = state.current, targetId = state.targetId, targetHealth = state.hp }
end
function AttackStateMachine.reset()
  state.current = STATE.IDLE; state.creature = nil; state.targetId = nil
  state.skipList = {}; state.retries = 0; state.lastStopAt = 0; state.lastSwitchAt = 0
end

return AttackStateMachine
