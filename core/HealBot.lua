local standBySpells = false
local standByItems = false

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

if not HealBotConfig.currentHealBotProfile or HealBotConfig.currentHealBotProfile == 0 or HealBotConfig.currentHealBotProfile > 5 then 
  HealBotConfig.currentHealBotProfile = 1
end

-- finding correct table, manual unfortunately
local currentSettings
local setActiveProfile = function()
  local n = HealBotConfig.currentHealBotProfile
  currentSettings = HealBotConfig[healPanelName][n]
end
setActiveProfile()

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
  nExBotConfigSave("heal")
end

ui.settings.onClick = function(widget)
  healWindow:show()
  healWindow:raise()
  healWindow:focus()
end

rootWidget = g_ui.getRootWidget()
if rootWidget then
  healWindow = UI.createWindow('HealWindow', rootWidget)
  healWindow:hide()

  healWindow.onVisibilityChange = function(widget, visible)
    if not visible then
      nExBotConfigSave("heal")
      healWindow.healer:show()
      healWindow.settings:hide()
      healWindow.settingsButton:setText("Settings")
    end
  end

  healWindow.settingsButton.onClick = function(widget)
    if healWindow.healer:isVisible() then
      healWindow.healer:hide()
      healWindow.settings:show()
      widget:setText("Back")
    else
      healWindow.healer:show()
      healWindow.settings:hide()
      widget:setText("Settings")
    end
  end

  local setProfileName = function()
    ui.name:setText(currentSettings.name)
  end
  healWindow.settings.profiles.Name.onTextChange = function(widget, text)
    currentSettings.name = text
    setProfileName()
  end
  healWindow.settings.list.Visible.onClick = function(widget)
    currentSettings.Visible = not currentSettings.Visible
    healWindow.settings.list.Visible:setChecked(currentSettings.Visible)
  end
  healWindow.settings.list.Cooldown.onClick = function(widget)
    currentSettings.Cooldown = not currentSettings.Cooldown
    healWindow.settings.list.Cooldown:setChecked(currentSettings.Cooldown)
  end
  healWindow.settings.list.Interval.onClick = function(widget)
    currentSettings.Interval = not currentSettings.Interval
    healWindow.settings.list.Interval:setChecked(currentSettings.Interval)
  end
  healWindow.settings.list.Conditions.onClick = function(widget)
    currentSettings.Conditions = not currentSettings.Conditions
    healWindow.settings.list.Conditions:setChecked(currentSettings.Conditions)
  end
  healWindow.settings.list.Delay.onClick = function(widget)
    currentSettings.Delay = not currentSettings.Delay
    healWindow.settings.list.Delay:setChecked(currentSettings.Delay)
  end
  healWindow.settings.list.MessageDelay.onClick = function(widget)
    currentSettings.MessageDelay = not currentSettings.MessageDelay
    healWindow.settings.list.MessageDelay:setChecked(currentSettings.MessageDelay)
  end

  local refreshSpells = function()
    if currentSettings.spellTable then
      healWindow.healer.spells.spellList:destroyChildren()
      for _, entry in pairs(currentSettings.spellTable) do
        local label = UI.createWidget("SpellEntry", healWindow.healer.spells.spellList)
        label.enabled:setChecked(entry.enabled)
        label.enabled.onClick = function(widget)
          standBySpells = false
          standByItems = false
          entry.enabled = not entry.enabled
          label.enabled:setChecked(entry.enabled)
        end
        label.remove.onClick = function(widget)
          standBySpells = false
          standByItems = false
          table.removevalue(currentSettings.spellTable, entry)
          reindexTable(currentSettings.spellTable)
          label:destroy()
        end
        label:setText("(MP>" .. entry.cost .. ") " .. entry.origin .. entry.sign .. entry.value .. ": " .. entry.spell)
      end
    end
  end
  refreshSpells()

  local refreshItems = function()
    if currentSettings.itemTable then
      healWindow.healer.items.itemList:destroyChildren()
      for _, entry in pairs(currentSettings.itemTable) do
        local label = UI.createWidget("ItemEntry", healWindow.healer.items.itemList)
        label.enabled:setChecked(entry.enabled)
        label.enabled.onClick = function(widget)
          standBySpells = false
          standByItems = false
          entry.enabled = not entry.enabled
          label.enabled:setChecked(entry.enabled)
        end
        label.remove.onClick = function(widget)
          standBySpells = false
          standByItems = false
          table.removevalue(currentSettings.itemTable, entry)
          reindexTable(currentSettings.itemTable)
          label:destroy()
        end
        label.id:setItemId(entry.item)
        label:setText(entry.origin .. entry.sign .. entry.value .. ": " .. entry.item)
      end
    end
  end
  refreshItems()

  healWindow.healer.spells.MoveUp.onClick = function(widget)
    local input = healWindow.healer.spells.spellList:getFocusedChild()
    if not input then return end
    local index = healWindow.healer.spells.spellList:getChildIndex(input)
    if index < 2 then return end

    local t = currentSettings.spellTable

    t[index],t[index-1] = t[index-1], t[index]
    healWindow.healer.spells.spellList:moveChildToIndex(input, index - 1)
    healWindow.healer.spells.spellList:ensureChildVisible(input)
  end

  healWindow.healer.spells.MoveDown.onClick = function(widget)
    local input = healWindow.healer.spells.spellList:getFocusedChild()
    if not input then return end
    local index = healWindow.healer.spells.spellList:getChildIndex(input)
    if index >= healWindow.healer.spells.spellList:getChildCount() then return end

    local t = currentSettings.spellTable

    t[index],t[index+1] = t[index+1],t[index]
    healWindow.healer.spells.spellList:moveChildToIndex(input, index + 1)
    healWindow.healer.spells.spellList:ensureChildVisible(input)
  end

  healWindow.healer.items.MoveUp.onClick = function(widget)
    local input = healWindow.healer.items.itemList:getFocusedChild()
    if not input then return end
    local index = healWindow.healer.items.itemList:getChildIndex(input)
    if index < 2 then return end

    local t = currentSettings.itemTable

    t[index],t[index-1] = t[index-1], t[index]
    healWindow.healer.items.itemList:moveChildToIndex(input, index - 1)
    healWindow.healer.items.itemList:ensureChildVisible(input)
  end

  healWindow.healer.items.MoveDown.onClick = function(widget)
    local input = healWindow.healer.items.itemList:getFocusedChild()
    if not input then return end
    local index = healWindow.healer.items.itemList:getChildIndex(input)
    if index >= healWindow.healer.items.itemList:getChildCount() then return end

    local t = currentSettings.itemTable

    t[index],t[index+1] = t[index+1],t[index]
    healWindow.healer.items.itemList:moveChildToIndex(input, index + 1)
    healWindow.healer.items.itemList:ensureChildVisible(input)
  end

  healWindow.healer.spells.addSpell.onClick = function(widget)
 
    local spellFormula = healWindow.healer.spells.spellFormula:getText():trim()
    local manaCost = tonumber(healWindow.healer.spells.manaCost:getText())
    local spellTrigger = tonumber(healWindow.healer.spells.spellValue:getText())
    local spellSource = healWindow.healer.spells.spellSource:getCurrentOption().text
    local spellEquasion = healWindow.healer.spells.spellCondition:getCurrentOption().text
    local source
    local equasion

    if not manaCost then  
      warn("HealBot: incorrect mana cost value!")       
      healWindow.healer.spells.spellFormula:setText('')
      healWindow.healer.spells.spellValue:setText('')
      healWindow.healer.spells.manaCost:setText('') 
      return 
    end
    if not spellTrigger then  
      warn("HealBot: incorrect condition value!") 
      healWindow.healer.spells.spellFormula:setText('')
      healWindow.healer.spells.spellValue:setText('')
      healWindow.healer.spells.manaCost:setText('')
      return 
    end

    if spellSource == "Current Mana" then
      source = "MP"
    elseif spellSource == "Current Health" then
      source = "HP"
    elseif spellSource == "Mana Percent" then
      source = "MP%"
    elseif spellSource == "Health Percent" then
      source = "HP%"
    else
      source = "burst"
    end
    
    if spellEquasion == "Above" then
      equasion = ">"
    elseif spellEquasion == "Below" then
      equasion = "<"
    else
      equasion = "="
    end

    if spellFormula:len() > 0 then
      table.insert(currentSettings.spellTable,  {index = #currentSettings.spellTable+1, spell = spellFormula, sign = equasion, origin = source, cost = manaCost, value = spellTrigger, enabled = true})
      healWindow.healer.spells.spellFormula:setText('')
      healWindow.healer.spells.spellValue:setText('')
      healWindow.healer.spells.manaCost:setText('')
    end
    standBySpells = false
    standByItems = false
    refreshSpells()
  end

  healWindow.healer.items.addItem.onClick = function(widget)
 
    local id = healWindow.healer.items.itemId:getItemId()
    local trigger = tonumber(healWindow.healer.items.itemValue:getText())
    local src = healWindow.healer.items.itemSource:getCurrentOption().text
    local eq = healWindow.healer.items.itemCondition:getCurrentOption().text
    local source
    local equasion

    if not trigger then
      warn("HealBot: incorrect trigger value!")
      healWindow.healer.items.itemId:setItemId(0)
      healWindow.healer.items.itemValue:setText('')
      return
    end

    if src == "Current Mana" then
      source = "MP"
    elseif src == "Current Health" then
      source = "HP"
    elseif src == "Mana Percent" then
      source = "MP%"
    elseif src == "Health Percent" then
      source = "HP%"
    else
      source = "burst"
    end
    
    if eq == "Above" then
      equasion = ">"
    elseif eq == "Below" then
      equasion = "<"
    else
      equasion = "="
    end

    if id > 100 then
      table.insert(currentSettings.itemTable, {index = #currentSettings.itemTable+1,item = id, sign = equasion, origin = source, value = trigger, enabled = true})
      standBySpells = false
      standByItems = false
      refreshItems()
      healWindow.healer.items.itemId:setItemId(0)
      healWindow.healer.items.itemValue:setText('')
    end
  end

  healWindow.closeButton.onClick = function(widget)
    healWindow:hide()
  end

  local loadSettings = function()
    ui.title:setOn(currentSettings.enabled)
    setProfileName()
    healWindow.settings.profiles.Name:setText(currentSettings.name)
    refreshSpells()
    refreshItems()
    healWindow.settings.list.Visible:setChecked(currentSettings.Visible)
    healWindow.settings.list.Cooldown:setChecked(currentSettings.Cooldown)
    healWindow.settings.list.Delay:setChecked(currentSettings.Delay)
    healWindow.settings.list.MessageDelay:setChecked(currentSettings.MessageDelay)
    healWindow.settings.list.Interval:setChecked(currentSettings.Interval)
    healWindow.settings.list.Conditions:setChecked(currentSettings.Conditions)
  end
  loadSettings()

  local profileChange = function()
    setActiveProfile()
    activeProfileColor()
    loadSettings()
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
    nExBotConfigSave("atk")
  end

  HealBot.setOn = function()
    currentSettings.enabled = true
    ui.title:setOn(currentSettings.enabled)
    nExBotConfigSave("atk")
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
  
  Uses EventBus for event-driven healing instead of polling.
  Pre-caches stat functions and uses O(1) condition lookups.
]]

-- Cached player stats (updated on change events)
local cachedStats = {
  hp = 0,
  maxHp = 0,
  hpPercent = 0,
  mp = 0,
  maxMp = 0,
  mpPercent = 0,
  burst = 0,
  lastUpdate = 0
}

-- Flag to trigger immediate heal check
local needsHealCheck = true
local needsItemCheck = true

-- Pre-built condition checkers for O(1) evaluation
local conditionCheckers = {
  ["HP%"] = function(sign, value)
    if sign == "=" then return cachedStats.hpPercent == value
    elseif sign == ">" then return cachedStats.hpPercent >= value
    else return cachedStats.hpPercent <= value end
  end,
  ["HP"] = function(sign, value)
    if sign == "=" then return cachedStats.hp == value
    elseif sign == ">" then return cachedStats.hp >= value
    else return cachedStats.hp <= value end
  end,
  ["MP%"] = function(sign, value)
    if sign == "=" then return cachedStats.mpPercent == value
    elseif sign == ">" then return cachedStats.mpPercent >= value
    else return cachedStats.mpPercent <= value end
  end,
  ["MP"] = function(sign, value)
    if sign == "=" then return cachedStats.mp == value
    elseif sign == ">" then return cachedStats.mp >= value
    else return cachedStats.mp <= value end
  end,
  ["burst"] = function(sign, value)
    if sign == "=" then return cachedStats.burst == value
    elseif sign == ">" then return cachedStats.burst >= value
    else return cachedStats.burst <= value end
  end
}

-- Update cached stats using correct OTClient API
local function updateCachedStats()
  -- Use player object methods (OTClient native API)
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end
  
  local currentHp = localPlayer:getHealth()
  local currentMaxHp = localPlayer:getMaxHealth()
  local currentMp = localPlayer:getMana()
  local currentMaxMp = localPlayer:getMaxMana()
  
  cachedStats.hp = currentHp
  cachedStats.maxHp = currentMaxHp
  cachedStats.hpPercent = currentMaxHp > 0 and math.floor((currentHp / currentMaxHp) * 100) or 0
  cachedStats.mp = currentMp
  cachedStats.maxMp = currentMaxMp
  cachedStats.mpPercent = currentMaxMp > 0 and math.floor((currentMp / currentMaxMp) * 100) or 0
  cachedStats.burst = burstDamageValue and burstDamageValue() or 0
  cachedStats.lastUpdate = now
end

-- Check if condition is met using cached stats
local function checkCondition(origin, sign, value)
  local checker = conditionCheckers[origin]
  if checker then
    return checker(sign, value)
  end
  return false
end

-- Process spell healing (high priority, runs on events)
local function processSpellHealing()
  if standBySpells then return false end
  if not currentSettings.enabled then return false end
  
  local somethingIsOnCooldown = false
  local currentMp = cachedStats.mp
  
  for i = 1, #currentSettings.spellTable do
    local entry = currentSettings.spellTable[i]
    if entry.enabled and entry.cost < currentMp then
      if canCast(entry.spell, not currentSettings.Conditions, not currentSettings.Cooldown) then
        if checkCondition(entry.origin, entry.sign, entry.value) then
          say(entry.spell)
          return true
        end
      else
        somethingIsOnCooldown = true
      end
    end
  end
  
  if not somethingIsOnCooldown then
    standBySpells = true
  end
  return false
end

-- Use item for healing - works even with closed backpack
local function useItemLikeHotkey(itemId)
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return false end
  
  -- Method 1: Use inventory item with player (works without open backpack - like hotkeys)
  -- This is the preferred method as it works exactly like hotkey usage
  if g_game.useInventoryItemWith then
    g_game.useInventoryItemWith(itemId, localPlayer)
    return true
  end
  
  -- Method 2: Fallback - find item in open containers and use WITH player
  local item = findItem(itemId)
  if item then
    g_game.useWith(item, localPlayer)
    return true
  end
  
  -- Method 3: Try simple inventory use (some items don't need target)
  if g_game.useInventoryItem then
    g_game.useInventoryItem(itemId)
    return true
  end
  
  return false
end

-- Process item healing (slightly lower priority)
local function processItemHealing()
  if standByItems then return false end
  if not currentSettings.enabled then return false end
  if not currentSettings.itemTable or #currentSettings.itemTable == 0 then return false end
  if currentSettings.Delay and nExBot.isUsing then return false end
  if currentSettings.MessageDelay and nExBot.isUsingPotion then return false end
  
  -- Check if looting (delay if needed)
  if TargetBot and TargetBot.isOn and TargetBot.isOn() and 
     TargetBot.Looting and TargetBot.Looting.getStatus and 
     TargetBot.Looting.getStatus():len() > 0 and currentSettings.Interval then
    return false -- Skip this tick, let looting finish
  end
  
  for i = 1, #currentSettings.itemTable do
    local entry = currentSettings.itemTable[i]
    if entry and entry.enabled then
      -- Skip visibility check entirely when using inventory methods (works without open BP)
      -- Only check visibility if the setting requires it AND we must use findItem fallback
      local canUse = true
      if currentSettings.Visible and not g_game.useInventoryItemWith then
        canUse = findItem(entry.item) ~= nil
      end
      
      if canUse and checkCondition(entry.origin, entry.sign, entry.value) then
        if useItemLikeHotkey(entry.item) then
          return true
        end
      end
    end
  end
  
  standByItems = true
  return false
end

-- Subscribe to EventBus for instant reaction to stat changes
if EventBus then
  -- High priority health change handler (priority 100 = runs first)
  EventBus.on("player:health", function(health, maxHealth, oldHealth, oldMaxHealth)
    cachedStats.hp = health
    cachedStats.maxHp = maxHealth
    cachedStats.hpPercent = math.floor((health / maxHealth) * 100)
    
    -- Reset standby flags - health changed, need to recheck
    standByItems = false
    standBySpells = false
    needsHealCheck = true
    needsItemCheck = true
    
    -- CRITICAL: If health dropped significantly, process immediately
    if health < oldHealth then
      -- Immediate spell check for emergency healing
      processSpellHealing()
    end
  end, 100)
  
  -- Mana change handler
  EventBus.on("player:mana", function(mp, maxMp, oldMp, oldMaxMp)
    cachedStats.mp = mp
    cachedStats.maxMp = maxMp
    cachedStats.mpPercent = math.floor((mp / maxMp) * 100)
    
    standByItems = false
    standBySpells = false
    needsHealCheck = true
    needsItemCheck = true
  end, 90)
  end

-- Fast spell macro (50ms for critical healing response)
macro(50, function()
  if not currentSettings.enabled then return end
  
  -- Always update stats to ensure accuracy
  updateCachedStats()
  
  -- Reset standby on each tick (simple polling approach)
  standBySpells = false
  
  processSpellHealing()
end)

-- Item macro (100ms - potions have 1s cooldown anyway)
macro(100, function()
  if not currentSettings.enabled then return end
  if not currentSettings.itemTable or #currentSettings.itemTable == 0 then return end
  if currentSettings.Delay and nExBot.isUsing then return end
  if currentSettings.MessageDelay and nExBot.isUsingPotion then return end
  
  -- Always update stats
  updateCachedStats()
  
  -- Reset standby on each tick
  standByItems = false
  
  processItemHealing()
end)

-- Keep the original event handlers as fallback (they just set flags now)
onPlayerHealthChange(function(healthPercent)
  standByItems = false
  standBySpells = false
  needsHealCheck = true
  needsItemCheck = true
end)

onManaChange(function(localPlayer, mp, maxMp, oldMp, oldMaxMp)
  standByItems = false
  standBySpells = false
  needsHealCheck = true
  needsItemCheck = true
end)

-- Initialize cached stats on load
updateCachedStats()

UI.Separator()