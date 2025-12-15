-- Shared heal planning/exec engine for self/friend healing
-- Deterministic, one-action-per-tick planner used by HealBot and FriendHealer

HealEngine = {}

local cooldowns = {}

-- Feature toggles so idle paths stay dormant
local options = {
  selfSpells = false,
  potions = false,
  friendHeals = false,
}

local function healingGroupReady()
  if BotCore and BotCore.Cooldown and BotCore.Cooldown.isHealingOnCooldown then
    if BotCore.Cooldown.isHealingOnCooldown() then return false end
  end
  if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
    if modules.game_cooldown.isGroupCooldownIconActive(2) then return false end
  end
  return true
end

local function potionReady()
  if BotCore and BotCore.Cooldown and BotCore.Cooldown.canUsePotion then
    if not BotCore.Cooldown.canUsePotion() then return false end
  end
  if nExBot and nExBot.isUsingPotion then return false end
  if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
    if modules.game_cooldown.isGroupCooldownIconActive(6) then return false end
  end
  return true
end

local function nowMs()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

local function ready(key, cd)
  local last = cooldowns[key] or 0
  return (nowMs() - last) >= cd
end

local function stamp(key)
  cooldowns[key] = nowMs()
end

-- Safe wrapper for using potions/items on self
-- Uses the global useWith function which is standard in OTClientV8
local function useItemSafe(itemId)
  if not itemId or itemId <= 0 then return false end
  
  -- First try the global useWith(itemId, player) pattern commonly used
  if useWith and player then
    local item = findItem and findItem(itemId)
    if item then
      useWith(item, player)
      return true
    end
  end
  
  -- Alternative: try g_game.useInventoryItemWith
  if g_game and g_game.useInventoryItemWith and player then
    g_game.useInventoryItemWith(itemId, player, 0)
    return true
  end
  
  -- Alternative: try g_game.useInventoryItem (uses on self)
  if g_game and g_game.useInventoryItem then
    g_game.useInventoryItem(itemId)
    return true
  end
  
  return false
end

local function canUseItem()
  return potionReady()
end

local selfSpells = {
  {name = "exura vita", key = "exura vita", hp = 45, mp = 160, cd = 1100, prio = 1},
  {name = "exura gran", key = "exura gran", hp = 65, mp = 60, cd = 1100, prio = 2},
  {name = "exura", key = "exura", hp = 85, mp = 20, cd = 1100, prio = 3},
}

local selfPotions = {
  {id = 238, hp = 55, key = "ultimate_heal_potion", cd = 1000, prio = 1},
  {id = 237, hp = 65, key = "great_heal_potion", cd = 1000, prio = 2},
  {id = 268, mp = 60, key = "mana_potion", cd = 1000, prio = 3},
}

local friendSpells = {
  {name = "exura gran sio", key = "exura gran sio", hp = 50, mp = 140, cd = 1100, prio = 1},
  {name = "exura sio", key = "exura sio", hp = 80, mp = 140, cd = 1100, prio = 2},
}

local function sortByPrio(list)
  table.sort(list, function(a, b)
    if a.hp and b.hp and a.hp ~= b.hp then
      return a.hp < b.hp
    end
    return (a.prio or 999) < (b.prio or 999)
  end)
end
sortByPrio(selfSpells)
sortByPrio(selfPotions)
sortByPrio(friendSpells)

-- Configure feature usage; accepts partial table {selfSpells?, potions?, friendHeals?}
function HealEngine.configure(opts)
  if not opts then return end
  if opts.selfSpells ~= nil then options.selfSpells = opts.selfSpells end
  if opts.potions ~= nil then options.potions = opts.potions end
  if opts.friendHeals ~= nil then options.friendHeals = opts.friendHeals end
end

-- Set custom spell list (from HealBot configuration)
function HealEngine.setCustomSpells(spellList)
  if spellList and type(spellList) == "table" then
    selfSpells = spellList
    sortByPrio(selfSpells)
  end
end

-- Set custom potion list (from HealBot configuration)  
function HealEngine.setCustomPotions(potionList)
  if potionList and type(potionList) == "table" then
    selfPotions = potionList
    sortByPrio(selfPotions)
  end
end

function HealEngine.setSelfSpellsEnabled(flag)
  options.selfSpells = not not flag
end

function HealEngine.setPotionsEnabled(flag)
  options.potions = not not flag
end

function HealEngine.setFriendHealingEnabled(flag)
  options.friendHeals = not not flag
end

-- Select best self action based on snapshot
function HealEngine.planSelf(snap)
  local hp = snap.hp or hppercent()
  local mp = snap.mp or manapercent()
  local inPz = snap.inPz or isInPz()

  -- Skip potions in PZ to avoid waste unless HP is critical
  local allowPotion = not inPz or hp <= 30

  if options.selfSpells then
    for _, spell in ipairs(selfSpells) do
      local hpMatch = (spell.hp == nil) or (hp <= spell.hp)
      local mpMatch = (spell.mp == nil) or (mp >= spell.mp)
      local mpThresholdMet = (spell.mp == nil) or true  -- Always allow if no mp cost defined
      -- For HP spells: check HP threshold. For MP spells: check MP threshold
      local shouldHeal = false
      if spell.hp and hp <= spell.hp then
        shouldHeal = true
      elseif spell.mp and not spell.hp and mp <= spell.mp then
        -- MP-triggered spell (e.g., mana shield, utana vid)
        shouldHeal = true
      end
      if shouldHeal and healingGroupReady() and ready(spell.key, spell.cd) then
        return {kind = "spell", name = spell.name, key = spell.key, cd = spell.cd, mana = spell.mana or 0}
      end
    end
  end

  if options.potions then
    for _, pot in ipairs(selfPotions) do
      -- Debug: uncomment to diagnose potion issues
      -- print(string.format("[HealEngine] Checking potion id=%s hp=%s mp=%s | current hp=%d mp=%d allowPotion=%s ready=%s canUse=%s", 
      --   tostring(pot.id), tostring(pot.hp), tostring(pot.mp), hp, mp, tostring(allowPotion), tostring(ready(pot.key, pot.cd)), tostring(canUseItem())))
      
      -- Get the actual potion name - prefer pot.name, then try to look up by ID
      local potionName = pot.name
      if not potionName and pot.id then
        -- Try to get item name from game data
        if g_things and g_things.getThingType then
          local thing = g_things.getThingType(pot.id, ThingCategoryItem)
          if thing then
            if thing.getName then
              local name = thing:getName()
              if name and name ~= "" then potionName = name:lower() end
            elseif thing.getMarketData then
              local marketData = thing:getMarketData()
              if marketData and marketData.name and marketData.name ~= "" then
                potionName = marketData.name:lower()
              end
            end
          end
        end
      end
      -- Final fallback
      potionName = potionName or ("potion #" .. (pot.id or 0))
      
      if pot.hp and hp <= pot.hp and allowPotion and ready(pot.key, pot.cd) and canUseItem() then
        return {kind = "potion", id = pot.id, key = pot.key, cd = pot.cd, name = potionName, potionType = "heal"}
      end
      if pot.mp and mp <= pot.mp and allowPotion and ready(pot.key, pot.cd) and canUseItem() then
        return {kind = "potion", id = pot.id, key = pot.key, cd = pot.cd, name = potionName, potionType = "mana"}
      end
    end
  end

  return nil
end

-- Select best friend action; target must include name and hp
function HealEngine.planFriend(snap, target)
  if not options.friendHeals then return nil end
  if not target or not target.name then return nil end
  local hp = target.hp or 100
  local mp = snap.mp or manapercent()
  local inPz = snap.inPz or isInPz()
  if inPz then return nil end
  for _, spell in ipairs(friendSpells) do
    local hpThreshold = spell.hp or 0
    local mpCost = spell.mp or 0
    if hp <= hpThreshold and mp >= mpCost and healingGroupReady() and ready(spell.key, spell.cd) then
      return {
        kind = "spell",
        name = string.format('%s "%s"', spell.name, target.name),
        key = spell.key,
        cd = spell.cd
      }
    end
  end
  return nil
end

function HealEngine.execute(action)
  if not action then return false end
  if action.kind == "spell" then
    say(action.name)
    stamp(action.key)
    if BotCore and BotCore.Cooldown and BotCore.Cooldown.markHealingUsed then
      BotCore.Cooldown.markHealingUsed(action.cd)
    end
    -- Track spell usage for Hunt Analyzer
    if HuntAnalytics and HuntAnalytics.trackHealSpell then
      HuntAnalytics.trackHealSpell(action.name, action.mana or 0)
    end
    return true
  elseif action.kind == "potion" then
    useItemSafe(action.id)
    stamp(action.key)
    if BotCore and BotCore.Cooldown and BotCore.Cooldown.markPotionUsed then
      BotCore.Cooldown.markPotionUsed(action.cd)
    end
    -- Track potion usage for Hunt Analyzer
    if HuntAnalytics and HuntAnalytics.trackPotion then
      local potionType = action.potionType or "other"
      HuntAnalytics.trackPotion(action.name or "potion", potionType)
    end
    return true
  end
  return false
end

return HealEngine
