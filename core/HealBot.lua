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

-- Process spell healing (high priority, runs on events)
local function processSpellHealing()
  if standBySpells then return false end
  if not currentSettings.enabled then return false end
  
  local spellTable = currentSettings.spellTable
  local spellCount = spellTable and #spellTable or 0
  if spellCount == 0 then return false end
  
  -- Get stats from BotCore (single source of truth)
  local stats = getStats()
  
  local somethingIsOnCooldown = false
  local currentMp = stats.mp
  local ignoreConditions = not currentSettings.Conditions
  local ignoreCooldown = not currentSettings.Cooldown
  
  for i = 1, spellCount do
    local entry = spellTable[i]
    if entry.enabled and entry.cost < currentMp then
      if canCast(entry.spell, ignoreConditions, ignoreCooldown) then
        if checkCondition(entry.origin, entry.sign, entry.value) then
          local beforeHp = stats.hpPercent
          local beforeMp = stats.mpPercent
          say(entry.spell)
          recordSpell(entry, beforeHp, beforeMp)
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

-- Use BotCore.Items for hotkey-style item usage (works even with closed backpack)
local function useItemLikeHotkey(itemId)
  -- Use BotCore.Items if available
  if BotCore and BotCore.Items and BotCore.Items.useSelf then
    return BotCore.Items.useSelf(itemId)
  end
  
  -- Fallback: direct implementation
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return false end
  
  if g_game.useInventoryItemWith then
    g_game.useInventoryItemWith(itemId, localPlayer)
    return true
  end
  
  local item = findItem(itemId)
  if item then
    g_game.useWith(item, localPlayer)
    return true
  end
  
  return false
end

-- Process item healing (slightly lower priority) - optimized
local function processItemHealing()
  if standByItems then return false end
  if not currentSettings.enabled then return false end
  
  local itemTable = currentSettings.itemTable
  local itemCount = itemTable and #itemTable or 0
  if itemCount == 0 then return false end
  
  if currentSettings.Delay and nExBot.isUsing then return false end
  if currentSettings.MessageDelay and nExBot.isUsingPotion then return false end
  
  -- Check if looting (delay if needed) - cache TargetBot references
  if TargetBot and TargetBot.isOn and TargetBot.isOn() and currentSettings.Interval then
    local looting = TargetBot.Looting
    if looting and looting.getStatus then
      local status = looting.getStatus()
      if status and status:len() > 0 then
        return false -- Skip this tick, let looting finish
      end
    end
  end
  
  -- Get stats from BotCore (single source of truth)
  local stats = getStats()
  local checkVisibility = currentSettings.Visible and not g_game.useInventoryItemWith
  
  for i = 1, itemCount do
    local entry = itemTable[i]
    if entry and entry.enabled then
      -- Only check visibility if required and no inventory method available
      local canUse = not checkVisibility or findItem(entry.item) ~= nil
      
      if canUse and checkCondition(entry.origin, entry.sign, entry.value) then
        if useItemLikeHotkey(entry.item) then
          local beforeHp = stats.hpPercent
          local beforeMp = stats.mpPercent
          recordPotion(entry, beforeHp, beforeMp)
          return true
        end
      end
    end
  end
  
  standByItems = true
  return false
end

-- Subscribe to EventBus for instant reaction to stat changes
-- Note: BotCore handles event-driven stat updates, we just need to reset flags
if EventBus then
  -- High priority health change handler (priority 100 = runs first)
  EventBus.on("player:health", function(health, maxHealth, oldHealth, oldMaxHealth)
    -- BotCore.Stats handles the actual stat update
    -- We just reset standby flags
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
    -- BotCore.Stats handles the actual stat update
    standByItems = false
    standBySpells = false
    needsHealCheck = true
    needsItemCheck = true
  end, 90)
end

-- Fast spell macro (75ms for critical healing response)
macro(75, function()
  if not currentSettings.enabled then return end
  
  -- BotCore.Stats.update() is called by BotCore tick handler
  -- Just reset standby and process
  standBySpells = false
  
  processSpellHealing()
end)

-- Item macro (100ms - potions have 1s cooldown anyway)
macro(100, function()
  if not currentSettings.enabled then return end
  if not currentSettings.itemTable or #currentSettings.itemTable == 0 then return end
  if currentSettings.Delay and nExBot.isUsing then return end
  if currentSettings.MessageDelay and nExBot.isUsingPotion then return end
  
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

-- Initialize stats on load (BotCore handles this if available)
if BotCore and BotCore.Stats then
  BotCore.Stats.update()
end

UI.Separator()