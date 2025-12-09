--[[
  BotCore: Actions
  
  Unified action execution for spells and items.
  Handles cooldowns, visibility checks, and inventory methods.
  
  Principles: SRP, DRY
]]

local Actions = {}

-- ============================================================================
-- SPELL EXECUTION
-- ============================================================================

-- Cast a spell with optional delay tracking
-- spell: spell words (string)
-- delay: minimum delay between casts (ms)
-- options: { ignoreCooldown, ignoreConditions, trackAnalytics }
function Actions.castSpell(spell, delay, options)
  options = options or {}
  
  if type(spell) ~= "string" then return false end
  spell = spell:lower()
  
  -- Check cooldown unless ignored
  if not options.ignoreCooldown then
    if BotCore and BotCore.Cooldown then
      -- Use unified cooldown manager
      if not BotCore.Cooldown.canCastSpell(nil, nil) then
        return false
      end
    elseif canCast then
      -- Fallback to legacy canCast
      if not canCast(spell, options.ignoreConditions, options.ignoreCooldown) then
        return false
      end
    end
  end
  
  -- Execute spell
  if cast then
    cast(spell, delay)
  elseif say then
    say(spell)
  else
    return false
  end
  
  return true
end

-- ============================================================================
-- ITEM/POTION EXECUTION
-- ============================================================================

-- Use an item like a hotkey (works without open backpack)
-- itemId: item ID to use
-- target: optional target (creature or tile), defaults to player
function Actions.useItem(itemId, target)
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return false end
  
  target = target or localPlayer
  
  -- Method 1: Use inventory item with target (works without open backpack)
  if g_game.useInventoryItemWith then
    g_game.useInventoryItemWith(itemId, target)
    return true
  end
  
  -- Method 2: Find item in open containers and use with target
  if findItem then
    local item = findItem(itemId)
    if item then
      g_game.useWith(item, target)
      return true
    end
  end
  
  -- Method 3: Simple inventory use (some items don't need target)
  if g_game.useInventoryItem then
    g_game.useInventoryItem(itemId)
    return true
  end
  
  return false
end

-- Use a potion (self-target)
function Actions.usePotion(itemId)
  -- Check potion cooldown
  if BotCore and BotCore.Cooldown then
    if not BotCore.Cooldown.canUsePotion() then
      return false
    end
  end
  
  local result = Actions.useItem(itemId, g_game.getLocalPlayer())
  
  -- Mark potion as used for cooldown tracking
  if result and BotCore and BotCore.Cooldown then
    BotCore.Cooldown.markPotionUsed()
  end
  
  return result
end

-- Use a rune on target
-- runeId: rune item ID
-- target: creature or tile to use rune on
function Actions.useRune(runeId, target)
  if not target then return false end
  
  -- Method 1: Use inventory item with target
  if g_game.useInventoryItemWith then
    g_game.useInventoryItemWith(runeId, target)
    return true
  end
  
  -- Method 2: Find rune in containers
  if findItem then
    local rune = findItem(runeId)
    if rune then
      g_game.useWith(rune, target)
      return true
    end
  end
  
  return false
end

-- ============================================================================
-- ITEM VISIBILITY
-- ============================================================================

-- Check if item is visible (in open container)
function Actions.isItemVisible(itemId)
  if findItem then
    return findItem(itemId) ~= nil
  end
  return false
end

-- Check if can use item (visible or has inventory method)
function Actions.canUseItem(itemId, requireVisible)
  -- If we have inventory method, always can use
  if g_game.useInventoryItemWith then
    return true
  end
  
  -- Otherwise need visibility
  if requireVisible then
    return Actions.isItemVisible(itemId)
  end
  
  return true
end

-- ============================================================================
-- UNIFIED ACTION EXECUTION
-- ============================================================================

-- Execute an action (spell or item)
-- action: { type = "spell"|"potion"|"rune", id = ..., target = ... }
function Actions.execute(action)
  if not action or not action.type then return false end
  
  if action.type == "spell" then
    return Actions.castSpell(action.spell or action.id, action.delay)
  elseif action.type == "potion" then
    return Actions.usePotion(action.id)
  elseif action.type == "rune" then
    return Actions.useRune(action.id, action.target)
  elseif action.type == "item" then
    return Actions.useItem(action.id, action.target)
  end
  
  return false
end

-- ============================================================================
-- ATTACK BOT SPECIFIC
-- ============================================================================

-- Execute attack action with category handling
-- category: 1=targeted spell, 2=area rune, 3=targeted rune, 4=empowerment, 5=absolute spell
-- idOrFormula: spell words or rune ID
-- cooldown: delay between uses
-- target: target for runes
function Actions.executeAttack(category, idOrFormula, cooldown, target)
  cooldown = cooldown or 0
  
  -- Record analytics
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.recordAttack(category, idOrFormula)
  end
  
  -- Spells (category 1, 4, 5)
  if category == 1 or category == 4 or category == 5 then
    return Actions.castSpell(idOrFormula, cooldown)
  end
  
  -- Targeted rune (category 3)
  if category == 3 then
    target = target or (target and target() or nil)
    return Actions.useRune(idOrFormula, target)
  end
  
  -- Area rune (category 2) - handled differently, target is tile
  if category == 2 then
    return Actions.useRune(idOrFormula, target)
  end
  
  return false
end

-- Export for global access
BotCore = BotCore or {}
BotCore.Actions = Actions

return Actions
