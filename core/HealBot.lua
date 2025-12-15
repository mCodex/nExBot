local standBySpells, standByItems = false, false

-- Load heal modules using simple dofile; they set globals directly
-- Try multiple paths in order of likelihood
local function tryLoadModule(name)
  local paths = {
    "core/" .. name .. ".lua",
    "/core/" .. name .. ".lua"
  }
  for _, path in ipairs(paths) do
    local ok = pcall(dofile, path)
    if ok then return true end
  end
  return false
end

-- Load heal_context (sets global HealContext)
if not HealContext then
  tryLoadModule("heal_context")
end
if not HealContext or not HealContext.get then
  warn("[HealBot] HealContext not loaded")
end

-- Load heal_engine (sets global HealEngine)
if not HealEngine then
  tryLoadModule("heal_engine")
end
if not HealEngine then
  warn("[HealBot] HealEngine not loaded")
end
HealBot = HealBot or {}

local red = "#ff0800" -- "#ff0800" / #ea3c53 best
local blue = "#7ef9ff"

setDefaultTab("HP")
local healPanelName = "healbot"
local ui = setupUI([[
Panel
  height: 38

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('HealBot')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

  Button
    id: 1
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: 1
    margin-right: 2
    margin-top: 4
    size: 17 17

  Button
    id: 2
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    text: 2
    margin-left: 4
    size: 17 17
    
  Button
    id: 3
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    text: 3
    margin-left: 4
    size: 17 17

  Button
    id: 4
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    text: 4
    margin-left: 4
    size: 17 17 
    
  Button
    id: 5
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    text: 5
    margin-left: 4
    size: 17 17
    
  Label
    id: name
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    anchors.right: parent.right
    text-align: center
    margin-left: 4
    height: 17
    text: Profile #1
    background: #292A2A
]])
ui:setId(healPanelName)

if not HealBotConfig[healPanelName] or not HealBotConfig[healPanelName][1] or #HealBotConfig[healPanelName] ~= 5 then
  HealBotConfig[healPanelName] = {
    [1] = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Profile #1",
      Visible = true,
      Cooldown = true,
      Interval = true,
      Conditions = true,
      Delay = true,
      MessageDelay = false
    },
    [2] = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Profile #2",
      Visible = true,
      Cooldown = true,
      Interval = true,
      Conditions = true,
      Delay = true,
      MessageDelay = false
    },
    [3] = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Profile #3",
      Visible = true,
      Cooldown = true,
      Interval = true,
      Conditions = true,
      Delay = true,
      MessageDelay = false
    },
    [4] = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Profile #4",
      Visible = true,
      Cooldown = true,
      Interval = true,
      Conditions = true,
      Delay = true,
      MessageDelay = false
    },
    [5] = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Profile #5",
      Visible = true,
      Cooldown = true,
      Interval = true,
      Conditions = true,
      Delay = true,
      MessageDelay = false
    },
  }
end

-- Load character-specific profile if available
local charProfile = getCharacterProfile("healProfile")
if charProfile and charProfile >= 1 and charProfile <= 5 then
  HealBotConfig.currentHealBotProfile = charProfile
elseif not HealBotConfig.currentHealBotProfile or HealBotConfig.currentHealBotProfile == 0 or HealBotConfig.currentHealBotProfile > 5 then 
  HealBotConfig.currentHealBotProfile = 1
end

-- finding correct table, manual unfortunately
local currentSettings
local setActiveProfile = function()
  local n = HealBotConfig.currentHealBotProfile
  currentSettings = HealBotConfig[healPanelName][n]
  -- Save character's profile preference
  setCharacterProfile("healProfile", n)
end
setActiveProfile()

-- Macro handle so we can fully stop/start execution with the UI toggle
local healMacro = nil
local function syncHealMacro()
  if healMacro and healMacro.setOn then
    healMacro:setOn(currentSettings.enabled)
  end
end

local setProfileName = function()
  local name = (currentSettings and currentSettings.name) or ("Profile #" .. HealBotConfig.currentHealBotProfile)
  ui.name:setText(name)
  if healWindow and healWindow.settings and healWindow.settings.profiles then
    healWindow.settings.profiles.Name:setText(name)
  end
end

local activeProfileColor = function()
  for i=1,5 do
    if i == HealBotConfig.currentHealBotProfile then
      ui[i]:setColor("green")
    else
      ui[i]:setColor("white")
    end
  end
end
activeProfileColor()

ui.title:setOn(currentSettings.enabled)
ui.title.onClick = function(widget)
  currentSettings.enabled = not currentSettings.enabled
  widget:setOn(currentSettings.enabled)
  syncHealMacro()
  applyHealEngineToggles()  -- Update HealEngine when toggling on/off
  nExBotConfigSave("heal")
end

ui.settings.onClick = function(widget)
  if healWindow then
    healWindow:show()
    healWindow:raise()
    healWindow:focus()
  end
end

-- Convert HealBot spell format to HealEngine format
local function convertSpellsToEngineFormat(spellTable)
  if not spellTable then return {} end
  local converted = {}
  for i, spell in ipairs(spellTable) do
    if spell.enabled ~= false and spell.spell then  -- Only include enabled spells with valid spell name
      -- Determine HP/MP trigger based on origin and sign
      -- sign field indicates "<" (Below) or ">" (Above)
      local hp, mp = nil, nil
      local isBelow = spell.sign == "<" or spell.sign == nil  -- Default to "Below" if not set
      
      if spell.origin == "HP" or spell.origin == "HP%" then
        -- For HP spells with "Below" condition: trigger when HP <= value
        if isBelow then
          hp = spell.value or 50
        end
      elseif spell.origin == "MP" or spell.origin == "MP%" then
        -- For MP spells with "Below" condition: trigger when MP <= value
        -- This is for spells like mana shield that trigger on low mana
        if isBelow then
          mp = spell.value or 50
        end
      end
      
      -- Only add if we have a valid trigger threshold
      if hp or mp then
        table.insert(converted, {
          name = spell.spell,
          key = spell.spell:lower(),
          hp = hp,
          mp = mp,
          cd = 1100,  -- Default cooldown, can be customized per spell
          prio = #converted + 1    -- Priority based on insertion order
        })
      end
    end
  end
  return converted
end

-- Convert HealBot potion format to HealEngine format
local function convertPotionsToEngineFormat(itemTable)
  if not itemTable then return {} end
  local converted = {}
  for i, item in ipairs(itemTable) do
    if item.enabled ~= false and item.item and item.item > 0 then  -- Only include enabled potions with valid item ID
      -- Determine HP/MP trigger based on origin
      -- Note: sign field indicates "<" (Below) or ">" (Above)
      -- For "Below" (sign="<"), we want to use when stat <= threshold
      -- For "Above" (sign=">"), we invert: use when stat >= threshold (but this is unusual for potions)
      local hp, mp = nil, nil
      local isBelow = item.sign == "<" or item.sign == nil  -- Default to "Below" if not set
      
      if item.origin == "HP" or item.origin == "HP%" then
        -- For HP potions with "Below" condition: trigger when HP <= value
        -- For HP potions with "Above" condition: this is unusual, but we'd skip (set nil)
        if isBelow then
          hp = item.value or 50
        end
      elseif item.origin == "MP" or item.origin == "MP%" then
        -- For MP potions with "Below" condition: trigger when MP <= value
        if isBelow then
          mp = item.value or 50
        end
      end
      
      -- Get the actual item name from the game data
      local itemName = nil
      if g_things and g_things.getThingType then
        local thing = g_things.getThingType(item.item, ThingCategoryItem)
        if thing and thing.getName then
          local name = thing:getName()
          if name and name ~= "" then
            itemName = name:lower()
          end
        elseif thing and thing.getMarketData then
          local marketData = thing:getMarketData()
          if marketData and marketData.name and marketData.name ~= "" then
            itemName = marketData.name:lower()
          end
        end
      end
      -- Fallback name based on item ID if we couldn't get the real name
      if not itemName then
        itemName = "potion #" .. item.item
      end
      
      -- Only add if we have a valid trigger threshold
      if hp or mp then
        table.insert(converted, {
          id = item.item,
          key = "potion_" .. item.item,
          hp = hp,
          mp = mp,
          cd = 1000,  -- Potion cooldown
          prio = #converted + 1,    -- Priority based on insertion order
          name = itemName
        })
      end
    end
  end
  return converted
end

-- Module-level helper so validateStartup can access it
local function applyHealEngineToggles()
  if not HealEngine or not HealEngine.configure or not currentSettings then return end
  local isOn = not not currentSettings.enabled
  local hasSpells = currentSettings.spellTable and #currentSettings.spellTable > 0
  local hasItems = currentSettings.itemTable and #currentSettings.itemTable > 0
  
  -- Debug: uncomment to debug configuration
  -- print(string.format("[HealBot] applyHealEngineToggles: enabled=%s hasSpells=%s hasItems=%s", tostring(isOn), tostring(hasSpells), tostring(hasItems)))
  
  -- Enable/disable the healing features
  HealEngine.configure({
    selfSpells = isOn and hasSpells,
    potions = isOn and hasItems,
    friendHeals = false -- Friend healing only enabled by FriendHealer
  })
  
  -- Pass the custom configured spells and potions to the engine (converted to engine format)
  if HealEngine.setCustomSpells and hasSpells then
    HealEngine.setCustomSpells(convertSpellsToEngineFormat(currentSettings.spellTable))
  end
  if HealEngine.setCustomPotions and hasItems then
    local converted = convertPotionsToEngineFormat(currentSettings.itemTable)
    -- Debug: uncomment to debug potions
    -- print(string.format("[HealBot] Setting %d potions to HealEngine", #converted))
    -- for i, pot in ipairs(converted) do
    --   print(string.format("[HealBot]   Potion %d: id=%s hp=%s mp=%s", i, tostring(pot.id), tostring(pot.hp), tostring(pot.mp)))
    -- end
    HealEngine.setCustomPotions(converted)
  end
end

local rootWidget = g_ui.getRootWidget()
if rootWidget then
  healWindow = UI.createWindow('HealWindow', rootWidget)
  healWindow:hide()

  healWindow.closeButton.onClick = function(widget)
    healWindow:hide()
  end

  local refreshSpells
  local refreshItems

  local loadSettings = function()
    ui.title:setOn(currentSettings.enabled)
    syncHealMacro()
    setProfileName()
    refreshSpells()
    refreshItems()
    applyHealEngineToggles()
    healWindow.settings.list.Visible:setChecked(currentSettings.Visible)
    healWindow.settings.list.Cooldown:setChecked(currentSettings.Cooldown)
    healWindow.settings.list.Delay:setChecked(currentSettings.Delay)
    healWindow.settings.list.MessageDelay:setChecked(currentSettings.MessageDelay)
    healWindow.settings.list.Interval:setChecked(currentSettings.Interval)
    healWindow.settings.list.Conditions:setChecked(currentSettings.Conditions)
  end

    refreshSpells = function()
      if not currentSettings.spellTable then return end
      healWindow.healer.spells.spellList:destroyChildren()
      for _, entry in pairs(currentSettings.spellTable) do
        local label = UI.createWidget("SpellEntry", healWindow.healer.spells.spellList)
        label.enabled:setChecked(entry.enabled)
        label.enabled.onClick = function()
          entry.enabled = not entry.enabled
          label.enabled:setChecked(entry.enabled)
          applyHealEngineToggles()
          nExBotConfigSave("heal")
        end
        label.remove.onClick = function()
          table.removevalue(currentSettings.spellTable, entry)
          refreshSpells()
          applyHealEngineToggles()
          nExBotConfigSave("heal")
        end
        label:setText("(MP>" .. entry.cost .. ") " .. entry.origin .. entry.sign .. entry.value .. ": " .. entry.spell)
      end
    end

    refreshItems = function()
      if not currentSettings.itemTable then return end
      healWindow.healer.items.itemList:destroyChildren()
      for _, entry in pairs(currentSettings.itemTable) do
        local label = UI.createWidget("ItemEntry", healWindow.healer.items.itemList)
        label.enabled:setChecked(entry.enabled)
        label.enabled.onClick = function()
          entry.enabled = not entry.enabled
          label.enabled:setChecked(entry.enabled)
          applyHealEngineToggles()
          nExBotConfigSave("heal")
        end
        label.remove.onClick = function()
          table.removevalue(currentSettings.itemTable, entry)
          refreshItems()
          applyHealEngineToggles()
          nExBotConfigSave("heal")
        end
        label.id:setItemId(entry.item)
        label:setText(entry.origin .. entry.sign .. entry.value .. ": " .. entry.item)
      end
    end

    healWindow.healer.spells.MoveUp.onClick = function()
      local input = healWindow.healer.spells.spellList:getFocusedChild()
      if not input then return end
      local index = healWindow.healer.spells.spellList:getChildIndex(input)
      if index < 2 then return end
      local t = currentSettings.spellTable
      t[index], t[index-1] = t[index-1], t[index]
      healWindow.healer.spells.spellList:moveChildToIndex(input, index - 1)
      healWindow.healer.spells.spellList:ensureChildVisible(input)
      nExBotConfigSave("heal")
    end

    healWindow.healer.spells.MoveDown.onClick = function()
      local input = healWindow.healer.spells.spellList:getFocusedChild()
      if not input then return end
      local index = healWindow.healer.spells.spellList:getChildIndex(input)
      if index >= healWindow.healer.spells.spellList:getChildCount() then return end
      local t = currentSettings.spellTable
      t[index], t[index+1] = t[index+1], t[index]
      healWindow.healer.spells.spellList:moveChildToIndex(input, index + 1)
      healWindow.healer.spells.spellList:ensureChildVisible(input)
      nExBotConfigSave("heal")
    end

    healWindow.healer.items.MoveUp.onClick = function()
      local input = healWindow.healer.items.itemList:getFocusedChild()
      if not input then return end
      local index = healWindow.healer.items.itemList:getChildIndex(input)
      if index < 2 then return end
      local t = currentSettings.itemTable
      t[index], t[index-1] = t[index-1], t[index]
      healWindow.healer.items.itemList:moveChildToIndex(input, index - 1)
      healWindow.healer.items.itemList:ensureChildVisible(input)
      nExBotConfigSave("heal")
    end

    healWindow.healer.items.MoveDown.onClick = function()
      local input = healWindow.healer.items.itemList:getFocusedChild()
      if not input then return end
      local index = healWindow.healer.items.itemList:getChildIndex(input)
      if index >= healWindow.healer.items.itemList:getChildCount() then return end
      local t = currentSettings.itemTable
      t[index], t[index+1] = t[index+1], t[index]
      healWindow.healer.items.itemList:moveChildToIndex(input, index + 1)
      healWindow.healer.items.itemList:ensureChildVisible(input)
      nExBotConfigSave("heal")
    end

    healWindow.healer.spells.addSpell.onClick = function()
      local spellFormula = healWindow.healer.spells.spellFormula:getText():trim()
      local manaCost = tonumber(healWindow.healer.spells.manaCost:getText())
      local trigger = tonumber(healWindow.healer.spells.spellValue:getText())
      local src = healWindow.healer.spells.spellSource:getCurrentOption().text
      local eq = healWindow.healer.spells.spellCondition:getCurrentOption().text
      if not manaCost or not trigger or spellFormula:len() == 0 then return end
      local origin = (src == "Current Mana" and "MP") or (src == "Current Health" and "HP") or (src == "Mana Percent" and "MP%") or (src == "Health Percent" and "HP%") or "burst"
      local sign = (eq == "Above" and ">") or (eq == "Below" and "<") or "="
      table.insert(currentSettings.spellTable, {index = #currentSettings.spellTable+1, spell = spellFormula, sign = sign, origin = origin, cost = manaCost, value = trigger, enabled = true})
      healWindow.healer.spells.spellFormula:setText('')
      healWindow.healer.spells.spellValue:setText('')
      healWindow.healer.spells.manaCost:setText('')
      refreshSpells()
      applyHealEngineToggles()
      nExBotConfigSave("heal")
    end

    healWindow.healer.items.addItem.onClick = function()
      local id = healWindow.healer.items.itemId:getItemId()
      local trigger = tonumber(healWindow.healer.items.itemValue:getText())
      local src = healWindow.healer.items.itemSource:getCurrentOption().text
      local eq = healWindow.healer.items.itemCondition:getCurrentOption().text
      if not trigger or id <= 100 then return end
      local origin = (src == "Current Mana" and "MP") or (src == "Current Health" and "HP") or (src == "Mana Percent" and "MP%") or (src == "Health Percent" and "HP%") or "burst"
      local sign = (eq == "Above" and ">") or (eq == "Below" and "<") or "="
      table.insert(currentSettings.itemTable, {index = #currentSettings.itemTable+1, item = id, sign = sign, origin = origin, value = trigger, enabled = true})
      healWindow.healer.items.itemId:setItemId(0)
      healWindow.healer.items.itemValue:setText('')
      refreshItems()
      applyHealEngineToggles()
      nExBotConfigSave("heal")
    end
  loadSettings()

  local profileChange = function()
    setActiveProfile()
    activeProfileColor()
    loadSettings()
    applyHealEngineToggles()  -- Update HealEngine with new profile's spells/potions
    nExBotConfigSave("heal")
  end

  local resetSettings = function()
    currentSettings.enabled = false
    currentSettings.spellTable = {}
    currentSettings.itemTable = {}
    currentSettings.Visible = true
    currentSettings.Cooldown = true
    currentSettings.Delay = true
    currentSettings.MessageDelay = false
    currentSettings.Interval = true
    currentSettings.Conditions = true
    currentSettings.name = "Profile #" .. HealBotConfig.currentBotProfile
  end

  -- profile buttons
  for i=1,5 do
    local button = ui[i]
      button.onClick = function()
      HealBotConfig.currentHealBotProfile = i
      profileChange()
    end
  end

  healWindow.settings.profiles.ResetSettings.onClick = function()
    resetSettings()
    loadSettings()
  end


  -- public functions
  HealBot = {} -- global table

  HealBot.isOn = function()
    return currentSettings.enabled
  end

  HealBot.isOff = function()
    return not currentSettings.enabled
  end

  HealBot.setOff = function()
    currentSettings.enabled = false
    ui.title:setOn(currentSettings.enabled)
    syncHealMacro()
    applyHealEngineToggles()
    nExBotConfigSave("heal")
  end

  HealBot.setOn = function()
    currentSettings.enabled = true
    ui.title:setOn(currentSettings.enabled)
    syncHealMacro()
    applyHealEngineToggles()
    nExBotConfigSave("heal")
  end

  HealBot.getActiveProfile = function()
    return HealBotConfig.currentHealBotProfile -- returns number 1-5
  end

  HealBot.setActiveProfile = function(n)
    if not n or not tonumber(n) or n < 1 or n > 5 then
      return error("[HealBot] wrong profile parameter! should be 1 to 5 is " .. n)
    else
      HealBotConfig.currentHealBotProfile = n
      profileChange()
    end
  end

  HealBot.show = function()
    healWindow:show()
    healWindow:raise()
    healWindow:focus()
  end
end

--[[
  Optimized HealBot Engine
  
  Uses BotCore for unified stats, conditions, and analytics.
  Pre-caches stat functions and uses O(1) condition lookups.
]]

-- ============================================================================
-- BOTCORE INTEGRATION
-- ============================================================================

-- Use BotCore for stats (single source of truth)
local function getStats()
  if BotCore and BotCore.Stats then
    return BotCore.Stats.getAll()
  end
  -- Fallback for standalone testing
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return { hp = 0, maxHp = 1, hpPercent = 0, mp = 0, maxMp = 1, mpPercent = 0, burst = 0 } end
  local hp = localPlayer:getHealth()
  local maxHp = localPlayer:getMaxHealth()
  local mp = localPlayer:getMana()
  local maxMp = localPlayer:getMaxMana()
  return {
    hp = hp, maxHp = maxHp, hpPercent = math.floor((hp / maxHp) * 100),
    mp = mp, maxMp = maxMp, mpPercent = math.floor((mp / maxMp) * 100),
    burst = burstDamageValue and burstDamageValue() or 0
  }
end

-- Legacy analytics wrapper (redirects to BotCore.Analytics)
local analytics = {
  spellCasts = 0,
  potionUses = 0,
  potionWaste = 0,
  manaWaste = 0,
  spells = {},
  potions = {},
  log = {}
}

-- Flag to trigger immediate heal check
local needsHealCheck = true
local needsItemCheck = true

-- Use BotCore.Condition for checks (pure functions)
local function checkCondition(origin, sign, value)
  if BotCore and BotCore.Condition then
    return BotCore.Condition.check(origin, sign, value, getStats())
  end
  -- Fallback
  local stats = getStats()
  local current = nil
  if origin == "HP%" then current = stats.hpPercent
  elseif origin == "HP" then current = stats.hp
  elseif origin == "MP%" then current = stats.mpPercent
  elseif origin == "MP" then current = stats.mp
  elseif origin == "burst" then current = stats.burst end
  if not current then return false end
  if sign == "=" then return current == value end
  if sign == ">" then return current >= value end
  return current <= value
end

-- Cached player reference (avoid repeated lookups)
local cachedLocalPlayer = nil
local lastPlayerCheck = 0
local PLAYER_CHECK_INTERVAL = 1000  -- Revalidate player reference every 1s

-- Get cached local player (with periodic revalidation)
local function getLocalPlayerCached()
  if not cachedLocalPlayer or (now - lastPlayerCheck) > PLAYER_CHECK_INTERVAL then
    cachedLocalPlayer = g_game.getLocalPlayer()
    lastPlayerCheck = now
  end
  return cachedLocalPlayer
end

-- Update stats (delegates to BotCore if available)
local function updateCachedStats()
  if BotCore and BotCore.Stats then
    BotCore.Stats.update()
    return
  end
  -- Fallback handled by getStats()
end

-- Analytics helpers (redirect to BotCore.Analytics if available)
local function appendLog(entry)
  if BotCore and BotCore.Analytics then
    -- BotCore handles logging internally
    return
  end
  local log = analytics.log
  if #log >= 50 then
    table.remove(log, 1)
  end
  table.insert(log, entry)
end

local function recordSpell(entry, hpPercent, mpPercent)
  -- Use BotCore.Analytics if available
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.recordHealSpell(entry.spell, entry.cost, hpPercent, mpPercent)
    return
  end
  
  -- Fallback to local analytics
  analytics.spellCasts = analytics.spellCasts + 1
  
  -- Track individual spell usage
  local spellName = entry.spell or "unknown"
  analytics.spells[spellName] = (analytics.spells[spellName] or 0) + 1
  
  local wasted = false
  if entry.cost and hpPercent and entry.value then
    -- If we cast while already above the trigger threshold by 10%, count as waste
    if hpPercent > (entry.value + 10) then
      analytics.manaWaste = analytics.manaWaste + entry.cost
      wasted = true
    end
  end
  appendLog({
    t = now,
    kind = "spell",
    name = entry.spell,
    hp = hpPercent,
    mp = mpPercent,
    cost = entry.cost,
    wasted = wasted
  })
end

local function recordPotion(entry, hpPercent, mpPercent)
  -- Use BotCore.Analytics if available
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.recordPotion(entry.item, hpPercent, mpPercent)
    return
  end
  
  -- Fallback to local analytics
  analytics.potionUses = analytics.potionUses + 1
  
  -- Track individual potion usage (use string key to prevent sparse array issues)
  local itemKey = tostring(entry.item or 0)
  analytics.potions[itemKey] = (analytics.potions[itemKey] or 0) + 1
  
  local wasted = false
  if entry.value then
    -- If we potion when HP is already 10% above trigger, count as waste
    if hpPercent > (entry.value + 10) then
      analytics.potionWaste = analytics.potionWaste + 1
      wasted = true
    end
  end
  appendLog({
    t = now,
    kind = "potion",
    name = entry.item,
    hp = hpPercent,
    mp = mpPercent,
    wasted = wasted
  })
end

HealBot = HealBot or {}

-- Redirect to BotCore.Analytics if available
HealBot.getAnalytics = function()
  if BotCore and BotCore.Analytics then
    return BotCore.Analytics.HealBot.getAnalytics()
  end
  return analytics
end

HealBot.resetAnalytics = function()
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.HealBot.resetAnalytics()
    return
  end
  analytics.spellCasts = 0
  analytics.potionUses = 0
  analytics.potionWaste = 0
  analytics.manaWaste = 0
  analytics.spells = {}
  analytics.potions = {}
  analytics.log = {}
end

-- Legacy healer removed; new engine is the single path

-- Subscribe to EventBus for instant reaction to stat changes
-- Note: BotCore handles event-driven stat updates, we just need to reset flags
-- Legacy event hooks removed; HealEngine runs on macro tick only

-- Fast spell macro (driven by HealBot on/off state)
healMacro = macro(150, function()
  if not currentSettings.enabled then return end

  if not HealContext or not HealContext.get then
    return
  end

  local snap = HealContext.get()
  local action = HealEngine.planSelf(snap)
  if action then
    HealEngine.execute(action)
    return
  end
end)

syncHealMacro()


-- Initialize stats on load (BotCore handles this if available)
if BotCore and BotCore.Stats then
  BotCore.Stats.update()
end

local function validateStartup()
  if not HealContext or not HealContext.get then
    warn("[HealBot] HealContext missing or failed to load")
  end
  if not HealEngine then
    warn("[HealBot] HealEngine missing or failed to load")
  else
    applyHealEngineToggles()
  end
end

validateStartup()

UI.Separator()