--[[
  BotCore: Cooldown Manager
  
  Unified cooldown tracking with memoization for OTClient exhausted system.
  Single source of truth for spell and item cooldowns.
  
  Cooldown Groups (OTClient standard):
    1 = Attack spells
    2 = Healing spells  
    3 = Support spells
    4 = Special spells
  
  Principles: SRP, Memoization, Event-Driven
]]

local CooldownManager = {}

-- Private state with TTL-based caching
local _cache = {
  -- Group cooldown states (1=Attack, 2=Healing, 3=Support, 4=Special)
  groups = { false, false, false, false },
  
  -- Individual spell cooldowns { [spellId] = true/false }
  spells = {},
  
  -- Potion exhausted timestamp
  potionExhaustedUntil = 0,
  
  -- Cache metadata
  lastGroupUpdate = 0,
  lastSpellUpdate = {},
  
  -- TTL for cache validity (ms)
  groupTTL = 50,   -- Group cooldowns refresh every 50ms
  spellTTL = 100,  -- Individual spells refresh every 100ms
}

-- Reference to OTClient cooldown module
local _cooldownModule = nil

-- ============================================================================
-- PRIVATE FUNCTIONS
-- ============================================================================

-- Lazy load cooldown module
local function getCooldownModule()
  if not _cooldownModule then
    _cooldownModule = modules and modules.game_cooldown
  end
  return _cooldownModule
end

-- Update group cooldown states (memoized)
local function updateGroupCooldowns()
  local currentTime = now or os.time() * 1000
  
  -- Skip if cache is fresh
  if (currentTime - _cache.lastGroupUpdate) < _cache.groupTTL then
    return
  end
  
  local cooldownMod = getCooldownModule()
  if not cooldownMod or not cooldownMod.isGroupCooldownIconActive then
    return
  end
  
  -- Update all groups at once
  for i = 1, 4 do
    _cache.groups[i] = cooldownMod.isGroupCooldownIconActive(i) or false
  end
  
  _cache.lastGroupUpdate = currentTime
end

-- Update individual spell cooldown (memoized)
local function updateSpellCooldown(spellId)
  if not spellId then return false end
  
  local currentTime = now or os.time() * 1000
  local lastUpdate = _cache.lastSpellUpdate[spellId] or 0
  
  -- Skip if cache is fresh
  if (currentTime - lastUpdate) < _cache.spellTTL then
    return _cache.spells[spellId] or false
  end
  
  local cooldownMod = getCooldownModule()
  if not cooldownMod or not cooldownMod.isCooldownIconActive then
    return false
  end
  
  local isOnCooldown = cooldownMod.isCooldownIconActive(spellId) or false
  _cache.spells[spellId] = isOnCooldown
  _cache.lastSpellUpdate[spellId] = currentTime
  
  return isOnCooldown
end

-- ============================================================================
-- PUBLIC API: Group Cooldowns
-- ============================================================================

-- Check if attack group (1) is on cooldown
function CooldownManager.isAttackOnCooldown()
  updateGroupCooldowns()
  return _cache.groups[1]
end

-- Check if healing group (2) is on cooldown
function CooldownManager.isHealingOnCooldown()
  updateGroupCooldowns()
  return _cache.groups[2]
end

-- Check if support group (3) is on cooldown
function CooldownManager.isSupportOnCooldown()
  updateGroupCooldowns()
  return _cache.groups[3]
end

-- Check if special group (4) is on cooldown
function CooldownManager.isSpecialOnCooldown()
  updateGroupCooldowns()
  return _cache.groups[4]
end

-- Check specific group by ID (1-4)
function CooldownManager.isGroupOnCooldown(groupId)
  if not groupId or groupId < 1 or groupId > 4 then return false end
  updateGroupCooldowns()
  return _cache.groups[groupId]
end

-- ============================================================================
-- PUBLIC API: Spell Cooldowns
-- ============================================================================

-- Check if specific spell is on cooldown
function CooldownManager.isSpellOnCooldown(spellId)
  return updateSpellCooldown(spellId)
end

-- Check if can cast spell (combines group + individual cooldown)
function CooldownManager.canCastSpell(spellId, groupId)
  -- Check group first (faster, cached)
  if groupId then
    updateGroupCooldowns()
    if _cache.groups[groupId] then return false end
  end
  
  -- Check individual spell cooldown
  if spellId and updateSpellCooldown(spellId) then
    return false
  end
  
  return true
end

-- ============================================================================
-- PUBLIC API: Potion/Item Exhausted
-- ============================================================================

-- Mark potion as used (start 1s exhausted)
function CooldownManager.markPotionUsed()
  local currentTime = now or os.time() * 1000
  _cache.potionExhaustedUntil = currentTime + 1000
end

-- Check if can use potion
function CooldownManager.canUsePotion()
  local currentTime = now or os.time() * 1000
  return currentTime >= _cache.potionExhaustedUntil
end

-- Get remaining potion cooldown (ms)
function CooldownManager.getPotionCooldown()
  local currentTime = now or os.time() * 1000
  local remaining = _cache.potionExhaustedUntil - currentTime
  return remaining > 0 and remaining or 0
end

-- ============================================================================
-- PUBLIC API: Generic Action Check
-- ============================================================================

-- Unified check for any action type
-- actionType: "spell", "potion", "rune"
-- options: { spellId, groupId, ignoreCooldown }
function CooldownManager.canPerformAction(actionType, options)
  options = options or {}
  
  if options.ignoreCooldown then
    return true
  end
  
  if actionType == "potion" then
    return CooldownManager.canUsePotion()
  end
  
  if actionType == "spell" or actionType == "rune" then
    return CooldownManager.canCastSpell(options.spellId, options.groupId)
  end
  
  return true
end

-- ============================================================================
-- EVENT HANDLERS: React to OTClient events
-- ============================================================================

-- Hook into cooldown events for instant updates (if available)
function CooldownManager.init()
  -- Hook spell cooldown events
  if onSpellCooldown then
    onSpellCooldown(function(iconId, duration)
      _cache.spells[iconId] = true
      _cache.lastSpellUpdate[iconId] = now or os.time() * 1000
      
      -- Schedule cooldown end
      if duration and duration > 0 then
        schedule(duration, function()
          _cache.spells[iconId] = false
        end)
      end
    end)
  end
  
  -- Hook group cooldown events
  if onGroupSpellCooldown then
    onGroupSpellCooldown(function(groupId, duration)
      if groupId >= 1 and groupId <= 4 then
        _cache.groups[groupId] = true
        
        -- Schedule cooldown end
        if duration and duration > 0 then
          schedule(duration, function()
            _cache.groups[groupId] = false
          end)
        end
      end
    end)
  end
end

-- Force cache invalidation
function CooldownManager.invalidate()
  _cache.lastGroupUpdate = 0
  _cache.lastSpellUpdate = {}
end

-- Get cache stats (for debugging)
function CooldownManager.getDebugInfo()
  return {
    groups = _cache.groups,
    spellCount = 0, -- Count would iterate
    potionCooldown = CooldownManager.getPotionCooldown(),
    lastGroupUpdate = _cache.lastGroupUpdate
  }
end

-- Export for global access
BotCore = BotCore or {}
BotCore.Cooldown = CooldownManager

return CooldownManager
