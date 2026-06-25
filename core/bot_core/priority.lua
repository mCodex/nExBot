--[[
  BotCore: Priority Engine (simplified)
  
  HealEngine handles all healing priority decisions independently.
  This module only manages action exhaustion/cooldowns for attack vs support.
]]

local PriorityEngine = {}

-- Priority levels (lower = higher priority)
-- Healing priority is managed internally by HealEngine
local PRIORITY = {
  ATTACK = 1,
  SUPPORT = 2
}

-- Exhausted state tracking
local _exhaustedState = {
  healing = {
    until_time = 0,
    lastAttempt = 0,
    consecutiveFails = 0
  },
  attack = {
    until_time = 0,
    lastAttempt = 0,
    consecutiveFails = 0
  },
  potion = {
    until_time = 0,
    lastAttempt = 0
  }
}

-- Action queue for current tick
local _actionQueue = {}

-- ============================================================================
-- EXHAUSTED HANDLING
-- ============================================================================

-- Check if action type is exhausted
function PriorityEngine.isExhausted(actionType)
  local state = _exhaustedState[actionType]
  if not state then return false end
  
  local currentTime = now or os.time() * 1000
  return currentTime < state.until_time
end

-- Mark action as exhausted
function PriorityEngine.markExhausted(actionType, durationMs)
  local state = _exhaustedState[actionType]
  if not state then return end
  
  local currentTime = now or os.time() * 1000
  state.until_time = currentTime + (durationMs or 1000)
  state.lastAttempt = currentTime
end

-- Get remaining exhausted time
function PriorityEngine.getExhaustedRemaining(actionType)
  local state = _exhaustedState[actionType]
  if not state then return 0 end
  
  local currentTime = now or os.time() * 1000
  local remaining = state.until_time - currentTime
  return remaining > 0 and remaining or 0
end

-- Track failed action (for backoff)
function PriorityEngine.trackFailedAction(actionType)
  local state = _exhaustedState[actionType]
  if not state then return end
  
  state.consecutiveFails = (state.consecutiveFails or 0) + 1
  
  -- Exponential backoff: 100ms, 200ms, 400ms, 800ms (max)
  local backoffMs = math.min(100 * (2 ^ state.consecutiveFails), 800)
  PriorityEngine.markExhausted(actionType, backoffMs)
end

-- Reset failed counter on success
function PriorityEngine.trackSuccessAction(actionType)
  local state = _exhaustedState[actionType]
  if state then
    state.consecutiveFails = 0
  end
end

-- ============================================================================
-- EXHAUSTION / COOLDOWN CHECKS
-- ============================================================================

-- Check if can perform attack
function PriorityEngine.canAttack()
  if PriorityEngine.isExhausted("attack") then
    return false
  end
  if BotCore and BotCore.Cooldown then
    if BotCore.Cooldown.isAttackOnCooldown() then
      return false
    end
  end
  return true
end

-- Check if can use healing (HealEngine handles priority, we just check exhaustion)
function PriorityEngine.canHeal()
  if PriorityEngine.isExhausted("healing") then
    return false
  end
  if BotCore and BotCore.Cooldown then
    if BotCore.Cooldown.isHealingOnCooldown() then
      return false
    end
  end
  return true
end

-- Check if can use potion
function PriorityEngine.canUsePotion()
  if PriorityEngine.isExhausted("potion") then
    return false
  end
  if BotCore and BotCore.Cooldown then
    if not BotCore.Cooldown.canUsePotion() then
      return false
    end
  end
  return true
end

-- ============================================================================
-- ACTION EXECUTION WITH PRIORITY
-- ============================================================================

-- Execute action with priority check
function PriorityEngine.executeWithPriority(actionType, actionFn)
  if actionType == "heal" or actionType == "healing" then
    if not PriorityEngine.canHeal() then
      return false
    end
    local success = actionFn()
    if success then PriorityEngine.trackSuccessAction("healing")
    else PriorityEngine.trackFailedAction("healing") end
    return success
  end
  if actionType == "potion" then
    if not PriorityEngine.canUsePotion() then return false end
    local success = actionFn()
    if success then PriorityEngine.markExhausted("potion", 1000) end
    return success
  end
  if actionType == "attack" then
    if not PriorityEngine.canAttack() then return false end
    local success = actionFn()
    if success then PriorityEngine.trackSuccessAction("attack")
    else PriorityEngine.trackFailedAction("attack") end
    return success
  end
  return actionFn()
end

-- ============================================================================
-- GRACEFUL EXHAUSTED RECOVERY
-- ============================================================================

-- Handle exhausted event from OTClient
function PriorityEngine.onExhausted(groupId, remainingMs)
  if groupId == 1 then
    PriorityEngine.markExhausted("attack", remainingMs or 500)
  elseif groupId == 2 then
    PriorityEngine.markExhausted("healing", remainingMs or 500)
  end
end

-- Get status for debugging
function PriorityEngine.getStatus()
  return {
    exhausted = {
      healing = PriorityEngine.getExhaustedRemaining("healing"),
      attack = PriorityEngine.getExhaustedRemaining("attack"),
      potion = PriorityEngine.getExhaustedRemaining("potion")
    }
  }
end

-- ============================================================================
-- CONSTANTS EXPORT (read-only)
-- ============================================================================

PriorityEngine.PRIORITY = PRIORITY

-- Export for global access
BotCore = BotCore or {}
BotCore.Priority = PriorityEngine

return PriorityEngine
