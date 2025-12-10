--[[
  BotCore: Initialization Module
  
  High-performance unified bot system with safety-first design.
  Healing priority is ALWAYS active and cannot be disabled.
  
  Core Components:
    - Stats: Cached player stats with memoization
    - Cooldown: Unified cooldown tracking with graceful exhausted handling
    - Condition: Pure condition checking functions
    - Analytics: Unified action tracking
    - Priority: Safety-first priority engine (healing > attacks)
    - Actions: Unified spell/item execution
  
  Utility Modules:
    - Creatures: Monster/player counting, target utilities
    - Items: Hotkey-style item usage, container utilities
    - Position: Tile/distance utilities, pathfinding
    
  Design Principles:
    - Performance: Single tick updates, memoization, lazy evaluation
    - Safety: Healing always takes priority (non-configurable)
    - Graceful: Exhausted states handled with exponential backoff
    - DRY: Common functions consolidated, single source of truth
]]

-- Initialize global namespace
BotCore = BotCore or {}
BotCore.version = "2.1.0"
BotCore.initialized = false

-- ============================================================================
-- COMPONENT LOADING (order matters for dependencies)
-- ============================================================================

local basePath = "core/bot_core/"

-- Core managers (no dependencies)
dofile(basePath .. "stats.lua")
dofile(basePath .. "cooldown.lua")

-- Condition checker (depends on Stats)
dofile(basePath .. "conditions.lua")

-- Analytics (no dependencies)
dofile(basePath .. "analytics.lua")

-- Priority engine (depends on Stats, Cooldown) - SAFETY CRITICAL
dofile(basePath .. "priority.lua")

-- Actions (depends on Cooldown, Analytics, Priority)
dofile(basePath .. "actions.lua")

-- Utility modules (high-level helpers)
dofile(basePath .. "creatures.lua")
dofile(basePath .. "items.lua")
dofile(basePath .. "position.lua")

-- Friend Healer (depends on Stats, Cooldown, Priority)
dofile(basePath .. "friend_healer.lua")

-- ============================================================================
-- HIGH-PERFORMANCE TICK HANDLER
-- ============================================================================

-- Single tick handler - runs at 50ms for critical healing response
local function onBotCoreTick()
  -- Update stats once per tick (memoized, skips if already updated)
  if BotCore.Stats then
    BotCore.Stats.update()
  end
end

-- Register tick handler (hidden - no UI button)
if macro then
  macro(50, onBotCoreTick)
end

-- ============================================================================
-- EVENT-DRIVEN UPDATES (instant response)
-- ============================================================================

-- Hook into EventBus for instant stat updates
if EventBus then
  -- Health changes - highest priority (200)
  EventBus.on("player:health", function(hp, maxHp, oldHp, oldMaxHp)
    if BotCore.Stats then
      BotCore.Stats.setHealth(hp, maxHp)
    end
    -- Check if emergency heal needed
    if BotCore.Priority and hp < oldHp then
      -- Health dropped - priority engine will handle
    end
  end, 200)
  
  -- Mana changes
  EventBus.on("player:mana", function(mp, maxMp, oldMp, oldMaxMp)
    if BotCore.Stats then
      BotCore.Stats.setMana(mp, maxMp)
    end
  end, 200)
end

-- Fallback event handlers (for compatibility)
if onPlayerHealthChange then
  onPlayerHealthChange(function(healthPercent)
    if BotCore.Stats then
      BotCore.Stats.invalidate()
    end
  end)
end

if onManaChange then
  onManaChange(function(localPlayer, mp, maxMp, oldMp, oldMaxMp)
    if BotCore.Stats then
      BotCore.Stats.setMana(mp, maxMp)
    end
  end)
end

-- ============================================================================
-- EXHAUSTED EVENT HANDLING
-- ============================================================================

-- Hook into exhausted events for graceful handling
if onSpellCooldown then
  onSpellCooldown(function(iconId, duration)
    -- Forward to cooldown manager
    if BotCore.Cooldown then
      -- Cooldown manager handles this internally
    end
  end)
end

if onGroupSpellCooldown then
  onGroupSpellCooldown(function(groupId, duration)
    -- Forward to priority engine for graceful handling
    if BotCore.Priority then
      BotCore.Priority.onExhausted(groupId, duration)
    end
  end)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Initialize cooldown event hooks
if BotCore.Cooldown and BotCore.Cooldown.init then
  BotCore.Cooldown.init()
end

-- Mark as initialized
BotCore.initialized = true

-- ============================================================================
-- PUBLIC HELPERS (convenience functions)
-- ============================================================================

-- Quick access using Priority engine (safety-first)
function BotCore.canHeal()
  if BotCore.Priority then
    return BotCore.Priority.canHeal()
  end
  if BotCore.Cooldown then
    return not BotCore.Cooldown.isHealingOnCooldown()
  end
  return true
end

function BotCore.canAttack()
  -- Use Priority engine (respects healing priority)
  if BotCore.Priority then
    return BotCore.Priority.canAttack()
  end
  if BotCore.Cooldown then
    return not BotCore.Cooldown.isAttackOnCooldown()
  end
  return true
end

function BotCore.canSupport()
  if BotCore.Cooldown then
    return not BotCore.Cooldown.isSupportOnCooldown()
  end
  return true
end

-- Get current HP/MP percent quickly
function BotCore.hpPercent()
  return BotCore.Stats and BotCore.Stats.getHpPercent() or 0
end

function BotCore.mpPercent()
  return BotCore.Stats and BotCore.Stats.getMpPercent() or 0
end

-- Check condition shorthand
function BotCore.checkCondition(origin, sign, value)
  if BotCore.Condition then
    return BotCore.Condition.checkWithStats(origin, sign, value)
  end
  return false
end

-- Safety check: Should heal immediately? (non-configurable)
function BotCore.shouldHealNow()
  if BotCore.Priority then
    return BotCore.Priority.shouldHealNow()
  end
  -- Fallback: heal if HP < 50%
  return BotCore.hpPercent() < 50
end

-- Is emergency healing needed? (HP < 30%)
function BotCore.isEmergency()
  if BotCore.Priority then
    return BotCore.Priority.getCurrentPriority() == BotCore.Priority.PRIORITY.EMERGENCY_HEAL
  end
  return BotCore.hpPercent() < 30
end

return BotCore
