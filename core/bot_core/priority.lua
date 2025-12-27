--[[
  BotCore: Priority Engine
  
  High-performance action priority system with built-in healing priority.
  Healing ALWAYS takes precedence over attacks - this is non-configurable
  for player safety.
  
  Priority Order (hardcoded, cannot be disabled):
    1. Emergency Healing (HP < 30%)
    2. Critical Healing (HP < 50%)
    3. Normal Healing
    4. Mana Recovery
    5. Attack Actions
    6. Support Actions
  
  Principles: Performance, Safety-First, Non-Configurable Priority
]]

local PriorityEngine = {}

-- ============================================================================
-- CONSTANTS (hardcoded for safety)
-- ============================================================================

-- Emergency thresholds disabled per user request
local EMERGENCY_HP_THRESHOLD = 0  -- HP% below this = emergency (disabled)
local CRITICAL_HP_THRESHOLD = 0   -- HP% below this = critical (disabled)
local LOW_MANA_THRESHOLD = 20      -- MP% below this = need mana

-- Priority levels (lower = higher priority)
local PRIORITY = {
  EMERGENCY_HEAL = 1,
  CRITICAL_HEAL = 2,
  NORMAL_HEAL = 3,
  MANA_RECOVERY = 4,
  ATTACK = 5,
  SUPPORT = 6
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
-- PRIORITY DETERMINATION
-- ============================================================================

-- Get current priority based on player state (pure function)
function PriorityEngine.getCurrentPriority()
  if not BotCore or not BotCore.Stats then
    return PRIORITY.SUPPORT  -- Safe default
  end
  
  local hpPercent = BotCore.Stats.getHpPercent()
  local mpPercent = BotCore.Stats.getMpPercent()
  
  -- Health-based healing priority disabled by user request; skip emergency/critical checks
  -- (HP checks intentionally removed to prevent auto-stop of attacks)
  
  -- LOW MANA: Need mana for heals
  if mpPercent < LOW_MANA_THRESHOLD then
    return PRIORITY.MANA_RECOVERY
  end
  
  -- Normal operation
  return PRIORITY.ATTACK
end

-- Check if healing should be attempted NOW (ignores other actions)
function PriorityEngine.shouldHealNow()
  local priority = PriorityEngine.getCurrentPriority()
  return priority <= PRIORITY.CRITICAL_HEAL
end

-- Check if can perform attack (only if healing not urgent)
function PriorityEngine.canAttack()
  local priority = PriorityEngine.getCurrentPriority()
  
  -- Never attack if healing is critical
  if priority < PRIORITY.ATTACK then
    return false
  end
  
  -- Check exhausted
  if PriorityEngine.isExhausted("attack") then
    return false
  end
  
  -- Check cooldown via BotCore
  if BotCore and BotCore.Cooldown then
    if BotCore.Cooldown.isAttackOnCooldown() then
      return false
    end
  end
  
  return true
end

-- Check if can use healing (always allowed if not exhausted)
function PriorityEngine.canHeal()
  -- Healing is NEVER blocked by priority (safety first)
  
  -- Only check exhausted
  if PriorityEngine.isExhausted("healing") then
    return false
  end
  
  -- Check cooldown via BotCore
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
-- Returns: true if executed, false if blocked
function PriorityEngine.executeWithPriority(actionType, actionFn)
  -- Healing always executes (safety)
  if actionType == "heal" or actionType == "healing" then
    if not PriorityEngine.canHeal() then
      return false
    end
    
    local success = actionFn()
    if success then
      PriorityEngine.trackSuccessAction("healing")
    else
      PriorityEngine.trackFailedAction("healing")
    end
    return success
  end
  
  -- Potions
  if actionType == "potion" then
    if not PriorityEngine.canUsePotion() then
      return false
    end
    
    local success = actionFn()
    if success then
      PriorityEngine.markExhausted("potion", 1000)  -- 1s potion cooldown
    end
    return success
  end
  
  -- Attacks - check priority first
  if actionType == "attack" then
    if not PriorityEngine.canAttack() then
      return false
    end
    
    local success = actionFn()
    if success then
      PriorityEngine.trackSuccessAction("attack")
    else
      PriorityEngine.trackFailedAction("attack")
    end
    return success
  end
  
  -- Default: just execute
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
    currentPriority = PriorityEngine.getCurrentPriority(),
    exhausted = {
      healing = PriorityEngine.getExhaustedRemaining("healing"),
      attack = PriorityEngine.getExhaustedRemaining("attack"),
      potion = PriorityEngine.getExhaustedRemaining("potion")
    },
    thresholds = {
      emergency = EMERGENCY_HP_THRESHOLD,
      critical = CRITICAL_HP_THRESHOLD,
      lowMana = LOW_MANA_THRESHOLD
    }
  }
end

-- ============================================================================
-- CONSTANTS EXPORT (read-only)
-- ============================================================================

PriorityEngine.PRIORITY = PRIORITY
PriorityEngine.EMERGENCY_HP = EMERGENCY_HP_THRESHOLD
PriorityEngine.CRITICAL_HP = CRITICAL_HP_THRESHOLD

-- Export for global access
BotCore = BotCore or {}
BotCore.Priority = PriorityEngine

return PriorityEngine
