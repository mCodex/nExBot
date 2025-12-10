--[[
  BotCore: Condition Checker
  
  Pure functions for evaluating conditions against player stats.
  No side effects, deterministic outputs.
  
  Principles: Pure Functions, KISS
]]

local ConditionChecker = {}

-- ============================================================================
-- PURE COMPARISON FUNCTIONS
-- ============================================================================

-- Compare value with sign (pure function)
local function compare(current, sign, target)
  if sign == "=" or sign == "==" then
    return current == target
  elseif sign == ">" or sign == ">=" then
    return current >= target
  elseif sign == "<" or sign == "<=" then
    return current <= target
  elseif sign == "!=" or sign == "<>" then
    return current ~= target
  end
  return false
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Check single condition against stats cache
-- origin: "HP%", "HP", "MP%", "MP", "burst"
-- sign: ">", "<", "="
-- value: number to compare against
-- stats: stats table from StatsManager.getAll() or direct values
function ConditionChecker.check(origin, sign, value, stats)
  if not origin or not sign or not value then return false end
  
  local current = nil
  
  -- Support both table and direct StatsManager access
  if type(stats) == "table" then
    if origin == "HP%" then current = stats.hpPercent
    elseif origin == "HP" then current = stats.hp
    elseif origin == "MP%" then current = stats.mpPercent
    elseif origin == "MP" then current = stats.mp
    elseif origin == "burst" then current = stats.burst
    elseif origin == "level" then current = stats.level
    elseif origin == "soul" then current = stats.soul
    else current = stats[origin] end
  elseif BotCore and BotCore.Stats then
    current = BotCore.Stats.get(origin)
  end
  
  if current == nil then return false end
  
  return compare(current, sign, value)
end

-- Check condition using global StatsManager
function ConditionChecker.checkWithStats(origin, sign, value)
  if not BotCore or not BotCore.Stats then return false end
  local stats = BotCore.Stats.getAll()
  return ConditionChecker.check(origin, sign, value, stats)
end

-- Check multiple conditions (AND logic)
-- conditions: { {origin, sign, value}, ... }
function ConditionChecker.checkAll(conditions, stats)
  if not conditions or #conditions == 0 then return true end
  
  for _, cond in ipairs(conditions) do
    if not ConditionChecker.check(cond[1], cond[2], cond[3], stats) then
      return false
    end
  end
  return true
end

-- Check multiple conditions (OR logic)
function ConditionChecker.checkAny(conditions, stats)
  if not conditions or #conditions == 0 then return false end
  
  for _, cond in ipairs(conditions) do
    if ConditionChecker.check(cond[1], cond[2], cond[3], stats) then
      return true
    end
  end
  return false
end

-- Check HP condition shorthand
function ConditionChecker.hpBelow(percent, stats)
  return ConditionChecker.check("HP%", "<", percent, stats)
end

function ConditionChecker.hpAbove(percent, stats)
  return ConditionChecker.check("HP%", ">", percent, stats)
end

-- Check MP condition shorthand
function ConditionChecker.mpBelow(percent, stats)
  return ConditionChecker.check("MP%", "<", percent, stats)
end

function ConditionChecker.mpAbove(percent, stats)
  return ConditionChecker.check("MP%", ">", percent, stats)
end

-- Check mana amount (for spell costs)
function ConditionChecker.hasMana(amount, stats)
  if type(stats) == "table" then
    return (stats.mp or 0) >= amount
  elseif BotCore and BotCore.Stats then
    return BotCore.Stats.getMp() >= amount
  end
  return false
end

-- ============================================================================
-- CONDITION ENTRY EVALUATION
-- ============================================================================

-- Evaluate a heal/attack entry condition
-- entry: { origin, sign, value, enabled, cost, ... }
function ConditionChecker.evaluateEntry(entry, stats)
  if not entry then return false end
  if entry.enabled == false then return false end
  
  -- Check mana cost first (fast fail)
  if entry.cost and not ConditionChecker.hasMana(entry.cost, stats) then
    return false
  end
  
  -- Check main condition
  return ConditionChecker.check(entry.origin, entry.sign, entry.value, stats)
end

-- Export for global access
BotCore = BotCore or {}
BotCore.Condition = ConditionChecker

return ConditionChecker
