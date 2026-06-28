-- Panel name constant (must be defined before ensureCurrentSettings uses it)
local healPanelName = "healbot"

-- Safety: auto-restore currentSettings if nil
local function ensureCurrentSettings()
  if not currentSettings then
    if not HealBotConfig then HealBotConfig = {} end
    -- Ensure profile container exists and has 5 profiles
    if not HealBotConfig[healPanelName] or type(HealBotConfig[healPanelName]) ~= "table" or #HealBotConfig[healPanelName] ~= 5 then
      local profiles = {}
      for i = 1, 5 do
        profiles[i] = {
          enabled = false,
          spellTable = {},
          itemTable = {},
          name = "Profile #" .. i,
          Visible = true,
          Cooldown = true,
          Interval = true,
          Conditions = true,
          Delay = true,
          MessageDelay = false
        }
      end
      HealBotConfig[healPanelName] = profiles
      pcall(saveHeal)
    end
    if not HealBotConfig.currentHealBotProfile or HealBotConfig.currentHealBotProfile < 1 or HealBotConfig.currentHealBotProfile > 5 then
      HealBotConfig.currentHealBotProfile = 1
    end
    -- Use setActiveProfile to properly assign currentSettings
    if setActiveProfile then
      pcall(setActiveProfile)
    else
      currentSettings = HealBotConfig[healPanelName][HealBotConfig.currentHealBotProfile]
    end
  end
end

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

-- Convert HealBot spell format to HealEngine format
-- Must be defined before applyHealEngineToggles which uses it
local function convertSpellsToEngineFormat(spellTable)
  if not spellTable then return {} end
  local converted = {}
  local invalidSpells = {}
  for i, spell in ipairs(spellTable) do
    local valid = true
    if spell.enabled == false or not spell.spell or spell.spell == "" then
      valid = false
      table.insert(invalidSpells, {reason = "Disabled or missing name", spell = spell})
    end
    -- Determine HP/MP trigger based on origin and sign
    local hp, mp = nil, nil
    local isBelow = spell.sign == "<" or spell.sign == nil  -- Default to "Below" if not set
    if spell.origin == "HP" or spell.origin == "HP%" then
      if isBelow then
        hp = spell.value or 50
      else
        valid = false
        table.insert(invalidSpells, {reason = "HP spell set to 'Above' (>) which is not supported", spell = spell})
      end
    elseif spell.origin == "MP" or spell.origin == "MP%" then
      if isBelow then
        mp = spell.value or 50
      else
        valid = false
        table.insert(invalidSpells, {reason = "MP spell set to 'Above' (>) which is not supported", spell = spell})
      end
    else
      valid = false
      table.insert(invalidSpells, {reason = "Unknown origin", spell = spell})
    end
    if (not hp and not mp) then
      valid = false
      table.insert(invalidSpells, {reason = "Missing HP/MP trigger", spell = spell})
    end
    if valid then
        table.insert(converted, {
          name = spell.spell,
          key = (spell.spell or ""):lower(),
          hp = hp,
          mp = mp,
          op = spell.sign or "<",
          mana = spell.cost or spell.mana or 0,
          cd = 1100,
          prio = #converted + 1
        })
    end
  end

  return converted
end

-- Convert HealBot potion format to HealEngine format
-- Must be defined before applyHealEngineToggles which uses it
local function convertPotionsToEngineFormat(itemTable)
  if not itemTable then return {} end
  local converted = {}
  for i, item in ipairs(itemTable) do
    if item.enabled ~= false and item.item and item.item > 0 then
      local hp, mp = nil, nil
      local isBelow = item.sign == "<" or item.sign == nil
      
      if item.origin == "HP" or item.origin == "HP%" then
        if isBelow then
          hp = item.value or 50
        end
      elseif item.origin == "MP" or item.origin == "MP%" then
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
      if not itemName then
        itemName = "potion #" .. item.item
      end
      
      if hp or mp then
        table.insert(converted, {
          id = item.item,
          key = "potion_" .. item.item,
          hp = hp,
          mp = mp,
          cd = 1000,
          prio = #converted + 1,
          name = itemName
        })
      end
    end
  end
  return converted
end

local function applyHealEngineToggles()
  ensureCurrentSettings()
  if not HealEngine or not HealEngine.configure then return end
  if not currentSettings then
    warn("[HealBot] applyHealEngineToggles: currentSettings missing, aborting sync")
    return
  end
  local isOn = not not currentSettings.enabled
  local hasSpells = currentSettings.spellTable and #currentSettings.spellTable > 0
  local hasItems = currentSettings.itemTable and #currentSettings.itemTable > 0

  HealEngine.configure({
    selfSpells = isOn and hasSpells,
    potions = isOn and hasItems,
    friendHeals = false
  })

  -- Sync spell list to engine
  if HealEngine.setCustomSpells then
    local convertedSpells = convertSpellsToEngineFormat(currentSettings.spellTable)
    local ok = pcall(HealEngine.setCustomSpells, convertedSpells)
    if not ok then HealEngine._pendingSpells = convertedSpells
    else HealEngine._pendingSpells = nil end
    nExBot_LastConvertedSpells = convertedSpells
  end

  -- Sync potion list to engine
  if HealEngine.setCustomPotions then
    local convertedPotions = convertPotionsToEngineFormat(currentSettings.itemTable)
    local ok = pcall(HealEngine.setCustomPotions, convertedPotions)
    if not ok then HealEngine._pendingPotions = convertedPotions
    else HealEngine._pendingPotions = nil end
    nExBot_LastConvertedPotions = convertedPotions
  end
end

local red = "#ff0800" -- "#ff0800" / #ea3c53 best
local blue = "#7ef9ff"

setDefaultTab("HP")
-- healPanelName already defined at top of file
local ui = setupUI([[
Panel
  height: 55

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
    margin-left: 3
    height: 17
    width: 55
    text: Self

  Button
    id: allySetup
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 3
    height: 17
    width: 50
    text: Ally

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
  local profiles = {}
  for i = 1, 5 do
    profiles[i] = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Profile #" .. i,
      Visible = true,
      Cooldown = true,
      Interval = true,
      Conditions = true,
      Delay = true,
      MessageDelay = false
    }
  end
  HealBotConfig[healPanelName] = profiles
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

local function saveHeal()
  local ok = false
  local status, res = pcall(function() return nExBotConfigSave("heal") end)
  if status and res == true then
    ok = true
  end
  if not ok then
    warn("[nExBot] Failed to save Heal config")
  end
  return ok
end

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
  saveHeal()
end

ui.settings.onClick = function(widget)
  if healWindow then
    healWindow:show()
    healWindow:raise()
    healWindow:focus()
  end
end

ui.allySetup.onClick = function(widget)
  if friendHealerWindow then
    friendHealerWindow:show()
    friendHealerWindow:raise()
    friendHealerWindow:focus()
  end
end

-- Converter functions already defined at top of file

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
      ensureCurrentSettings()
      if not currentSettings or not currentSettings.spellTable then
        return
      end
      healWindow.healer.spells.spellList:destroyChildren()
      for _, entry in pairs(currentSettings.spellTable) do
        local label = UI.createWidget("SpellEntry", healWindow.healer.spells.spellList)
        label.enabled:setChecked(entry.enabled)
        label.enabled.onClick = function()
          entry.enabled = not entry.enabled
          label.enabled:setChecked(entry.enabled)
          applyHealEngineToggles()
          saveHeal()
        end
        label.remove.onClick = function()
          table.removevalue(currentSettings.spellTable, entry)
          refreshSpells()
          applyHealEngineToggles()
          saveHeal()
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
            saveHeal()
          end
        label.remove.onClick = function()
            table.removevalue(currentSettings.itemTable, entry)
            refreshItems()
            applyHealEngineToggles()
            saveHeal()
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
      saveHeal()
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
      saveHeal()
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
      saveHeal()
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
      saveHeal()
    end

    healWindow.healer.spells.addSpell.onClick = function()
      ensureCurrentSettings()
      if not currentSettings then
        return
      end
      currentSettings.spellTable = currentSettings.spellTable or {}
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
      saveHeal()
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
      saveHeal()
    end
  loadSettings()

  local profileChange = function()
    setActiveProfile()
    activeProfileColor()
    loadSettings()
    applyHealEngineToggles()  -- Update HealEngine with new profile's spells/potions
    saveHeal()
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
    saveHeal()
  end

  HealBot.setOn = function()
    currentSettings.enabled = true
    ui.title:setOn(currentSettings.enabled)
    syncHealMacro()
    applyHealEngineToggles()
    saveHeal()
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

-- BOTCORE INTEGRATION

-- Use BotCore for stats (single source of truth)
local function getStats()
  if BotCore and BotCore.Stats then
    return BotCore.Stats.getAll()
  end
  -- Fallback for standalone testing
  local localPlayer = ClientService.getLocalPlayer()
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
    cachedLocalPlayer = ClientService.getLocalPlayer()
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
  log[#log + 1] = entry
  TrimArray(log, 50)
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

-- Subscribe to EventBus for instant reaction to stat changes
-- Note: BotCore handles event-driven stat updates, we just need to reset flags

-- Fast spell macro (driven by HealBot on/off state)
-- Main healing macro loop (keeps heal engine ticking)
local _lastApplyToggle = 0
local syncDone = false
local SYNC_INTERVAL_MS = 500  -- Reduced from 2000ms for faster profile updates

-- HealBot handler function (shared by UnifiedTick and fallback macro)
local function healBotHandler()
  ensureCurrentSettings()
  if not currentSettings or not currentSettings.enabled then return end
  
  if not HealContext or not HealContext.get then return end
  if not HealEngine or not HealEngine.planSelf then return end

  -- Force sync once on first run to ensure spells are loaded
  if not syncDone then
    applyHealEngineToggles()
    syncDone = true
  end

  -- Periodic sync to catch profile changes
  local nowTime = now or (g_clock and g_clock.millis and g_clock.millis()) or os.time() * 1000
  if (nowTime - _lastApplyToggle) > SYNC_INTERVAL_MS then
    _lastApplyToggle = nowTime
    applyHealEngineToggles()
  end

  -- Get context snapshot (includes currentMana for spell cost checks)
  local snap = HealContext.get()
  
  -- Ensure currentMana is set for proper spell eligibility
  if not snap.currentMana then
    if mana then snap.currentMana = mana() or 0
    elseif player and player.getMana then snap.currentMana = player:getMana() or 0
    else snap.currentMana = 0 end
  end
  
  local action = HealEngine.planSelf(snap)
  if action then
    HealEngine.execute(action)
  end
end

-- Use UnifiedTick if available, fallback to standalone macro
-- Healing uses CRITICAL priority for safety-critical response time
if UnifiedTick and UnifiedTick.register then
  -- Register with UnifiedTick for consolidated tick management
  UnifiedTick.register("healbot_main", {
    interval = 150,
    priority = UnifiedTick.Priority.CRITICAL,
    handler = healBotHandler,
    group = "healing"
  })
  -- Create a dummy macro for syncHealMacro compatibility
  healMacro = macro(150, function() end)
  healMacro:setOn(true)
  -- Sync macro toggle with UnifiedTick handler
  local origSyncHealMacro = syncHealMacro
  syncHealMacro = function()
    if origSyncHealMacro then origSyncHealMacro() end
    if currentSettings then
      UnifiedTick.setEnabled("healbot_main", currentSettings.enabled)
    end
  end
else
  -- Fallback to standalone macro if UnifiedTick not available
  healMacro = macro(150, healBotHandler)
end

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

-- ALLY HEALING UI (merged from new_healer.lua)

local allyPanelName = "newHealer"

if not storage[allyPanelName] or not storage[allyPanelName].priorities then
    storage[allyPanelName] = nil
end

if not storage[allyPanelName] then
    storage[allyPanelName] = {
        enabled = false,
        customPlayers = {},
        vocations = {},
        groups = {},
        priorities = {
            {name="Custom Spell",           enabled=false, custom=true},
            {name="Exura Gran Sio",         enabled=true,              strong = true},
            {name="Exura Tio Sio",          enabled=true,                             medium = true},
            {name="Exura Sio",              enabled=true,                                            normal = true},
            {name="Exura Gran Mas Res",     enabled=true,                                                          area = true},
            {name="Health Item",            enabled=true,                                                                      health=true},
            {name="Mana Item",              enabled=true,                                                                                  mana=true}
        },
        settings = {
            {type="HealItem",       text="Mana Item ",                   value=268},
            {type="HealScroll",     text="Item Range: ",                 value=6},
            {type="HealItem",       text="Health Item ",                 value=3160},
            {type="HealScroll",     text="Mas Res Players: ",            value=2},
            {type="HealScroll",     text="Heal Friend at: ",             value=80},
            {type="HealScroll",     text="Use Gran Sio at: ",            value=40},
            {type="HealScroll",     text="Use Tio Sio at: ",             value=65},
            {type="HealScroll",     text="Min Player HP%: ",             value=80},
            {type="HealScroll",     text="Min Player MP%: ",             value=50},
        },
        conditions = {
            knights = true,
            paladins = true,
            druids = false,
            sorcerers = false,
            monks = false,
            party = true,
            guild = false,
            friends = false
        }
    }
end

local allyConfig = storage[allyPanelName]

local function normalizeAllySettings(settings)
    if type(settings) ~= "table" then
        settings = {}
    end
    local hasTio = false
    for i = 1, #settings do
        local text = settings[i] and settings[i].text
        if text and text:find("Tio Sio") then
            hasTio = true
            break
        end
    end
    if not hasTio then
        table.insert(settings, 7, {type="HealScroll", text="Use Tio Sio at: ", value=65})
    end
    return settings
end

local function getAllySettingValue(idx, default)
    local entry = allyConfig.settings and allyConfig.settings[idx]
    if entry and entry.value ~= nil then
        return entry.value
    end
    return default
end

allyConfig.settings = normalizeAllySettings(allyConfig.settings)

-- CharacterDB integration for ally config
local function loadAllyCustomPlayers()
  if not CharacterDB or not CharacterDB.isReady or not CharacterDB.isReady() then
    return
  end
  local charPlayers = CharacterDB.get("friendHealer.customPlayers")
  if charPlayers and type(charPlayers) == "table" and #charPlayers > 0 then
    allyConfig.customPlayers = charPlayers
  elseif allyConfig.customPlayers and #allyConfig.customPlayers > 0 then
    CharacterDB.set("friendHealer.customPlayers", allyConfig.customPlayers)
  end
  local charConditions = CharacterDB.get("friendHealer.conditions")
  if charConditions and type(charConditions) == "table" then
    for k, v in pairs(charConditions) do
      allyConfig.conditions[k] = v
    end
  end
end

schedule(500, loadAllyCustomPlayers)

local function saveAllyCustomPlayers()
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    CharacterDB.set("friendHealer.customPlayers", allyConfig.customPlayers)
  end
end

-- Build config for BotCore
local function buildAllyBotCoreConfig()
  local bcConfig = {
    enabled = allyConfig.enabled,
    customPlayers = allyConfig.customPlayers or {},
    conditions = allyConfig.conditions or {},
    settings = {
            manaItem = getAllySettingValue(1, 268),
            itemRange = getAllySettingValue(2, 6),
            healthItem = getAllySettingValue(3, 3160),
            masResPlayers = getAllySettingValue(4, 2),
            healAt = getAllySettingValue(5, 80),
            granSioAt = getAllySettingValue(6, 40),
            tioSioAt = getAllySettingValue(7, 65),
            minPlayerHp = getAllySettingValue(8, 80),
            minPlayerMp = getAllySettingValue(9, 50),
    },
    useSio = false,
    useGranSio = false,
    useTioSio = false,
    useMasRes = false,
    useHealthItem = false,
    useManaItem = false,
    customSpell = false,
    customSpellName = nil
  }
  for _, p in ipairs(allyConfig.priorities or {}) do
    if p.enabled then
      if p.strong then bcConfig.useGranSio = true end
      if p.medium then bcConfig.useTioSio = true end
      if p.normal then bcConfig.useSio = true end
      if p.area then bcConfig.useMasRes = true end
      if p.health then bcConfig.useHealthItem = true end
      if p.mana then bcConfig.useManaItem = true end
      if p.custom then
        bcConfig.customSpell = true
        bcConfig.customSpellName = p.name
      end
    end
  end
  return bcConfig
end

local function initAllyBotCoreHealer()
  if BotCore and BotCore.FriendHealer and BotCore.FriendHealer.init then
    local bcConfig = buildAllyBotCoreConfig()
    BotCore.FriendHealer.init(bcConfig)
    if BotCore.FriendHealer.setEnabled then
      BotCore.FriendHealer.setEnabled(allyConfig.enabled)
    end
    return true
  end
  return false
end

local function updateAllyBotCoreConfig()
  if BotCore and BotCore.FriendHealer and BotCore.FriendHealer.init then
    local bcConfig = buildAllyBotCoreConfig()
    BotCore.FriendHealer.init(bcConfig)
    if BotCore.FriendHealer.syncHealEngineSpells then
      BotCore.FriendHealer.syncHealEngineSpells()
    end
  end
end

-- FriendHealer window
local friendHealerMacro = nil
local friendHealerWindow

local function syncAllyHealerState()
    if BotCore and BotCore.FriendHealer and BotCore.FriendHealer.setEnabled then
        BotCore.FriendHealer.setEnabled(allyConfig.enabled)
        if BotCore.FriendHealer.syncHealEngineSpells then
            BotCore.FriendHealer.syncHealEngineSpells()
        end
    end
    if HealEngine and HealEngine.setFriendHealingEnabled then
        HealEngine.setFriendHealingEnabled(allyConfig.enabled)
    end
    if friendHealerMacro and friendHealerMacro.setOn then
        friendHealerMacro:setOn(allyConfig.enabled)
    end
end

local rootW = g_ui.getRootWidget()
if rootW then
  friendHealerWindow = UI.createWindow('FriendHealer', rootW)
  friendHealerWindow:hide()
  friendHealerWindow:setId(allyPanelName)

  friendHealerWindow.closeButton.onClick = function(widget)
    friendHealerWindow:hide()
  end

  initAllyBotCoreHealer()
  syncAllyHealerState()

  local allyConditions = friendHealerWindow.conditions
  local allyTargetSettings = friendHealerWindow.targetSettings
  local allyCustomList = friendHealerWindow.customList
  local allyPriority = friendHealerWindow.priority

  -- Custom players list
  local function createAllyPlayerEntry(name, health)
    local widget = UI.createWidget("HealerPlayerEntry", allyCustomList.playerList.list)
    widget.remove.onClick = function()
        allyConfig.customPlayers[name] = nil
        widget:destroy()
        saveAllyCustomPlayers()
        updateAllyBotCoreConfig()
    end
    widget:setText("["..health.."%]  "..name)
    return widget
  end

  for name, health in pairs(allyConfig.customPlayers) do
    createAllyPlayerEntry(name, health)
  end

  allyCustomList.playerList.onDoubleClick = function()
    allyCustomList.playerList:hide()
  end

  local function clearAllyFields()
    allyCustomList.addPanel.name:setText("friend name")
    allyCustomList.addPanel.health:setText("1")
    allyCustomList.playerList:show()
  end

  local properCase = nExBot and nExBot.Shared and nExBot.Shared.properCase or function(str)
    local words = {}
    for word in str:gmatch("%S+") do
      words[#words + 1] = word:sub(1,1):upper() .. word:sub(2)
    end
    return table.concat(words, " ")
  end

  allyCustomList.addPanel.add.onClick = function()
    local rawName = allyCustomList.addPanel.name:getText()
    local name = properCase(rawName)
    local health = tonumber(allyCustomList.addPanel.health:getText())

    if not health then
        clearAllyFields()
        return warn("[HealBot] Ally: Please enter health percent value!")
    end

    if name:len() == 0 or name:lower() == "friend name" then
        clearAllyFields()
        return warn("[HealBot] Ally: Please enter friend name to be added!")
    end

    if allyConfig.customPlayers[name] or allyConfig.customPlayers[name:lower()] then
        clearAllyFields()
        return warn("[HealBot] Ally: Player already added to custom list.")
    else
        allyConfig.customPlayers[name] = health
        createAllyPlayerEntry(name, health)
        saveAllyCustomPlayers()
        updateAllyBotCoreConfig()
    end
    clearAllyFields()
  end

  -- Validation helper
  local function validateAlly(widget, category)
    local list = widget:getParent()
    local label = list:getParent().title
    category = category or 0
    if category == 2 and not storage.extras.checkPlayer then
        label:setColor("#d9321f")
        label:setTooltip("! WARNING ! Turn on check players in extras to use this feature!")
        return
    else
        label:setColor("#dfdfdf")
        label:setTooltip("")
    end
    local checked = false
    for i, child in ipairs(list:getChildren()) do
        if category == 1 and child.enabled:isChecked() or child:isChecked() then
            checked = true
        end
    end
    if not checked then
        label:setColor("#d9321f")
        label:setTooltip("! WARNING ! No category selected!")
    else
        label:setColor("#dfdfdf")
        label:setTooltip("")
    end
  end

  local function bindAllyConditionCheckbox(widget, conditionKey, category)
    widget:setChecked(allyConfig.conditions[conditionKey])
    widget.onClick = function(w)
      allyConfig.conditions[conditionKey] = not allyConfig.conditions[conditionKey]
      w:setChecked(allyConfig.conditions[conditionKey])
      validateAlly(w, category or 0)
      updateAllyBotCoreConfig()
      if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        CharacterDB.set("friendHealer.conditions", allyConfig.conditions)
      end
    end
  end

  bindAllyConditionCheckbox(allyTargetSettings.vocations.box.knights, "knights", 2)
  bindAllyConditionCheckbox(allyTargetSettings.vocations.box.paladins, "paladins", 2)
  bindAllyConditionCheckbox(allyTargetSettings.vocations.box.druids, "druids", 2)
  bindAllyConditionCheckbox(allyTargetSettings.vocations.box.sorcerers, "sorcerers", 2)
  bindAllyConditionCheckbox(allyTargetSettings.vocations.box.monks, "monks", 2)

  bindAllyConditionCheckbox(allyTargetSettings.groups.box.friends, "friends")
  bindAllyConditionCheckbox(allyTargetSettings.groups.box.party, "party")
  bindAllyConditionCheckbox(allyTargetSettings.groups.box.guild, "guild")

  validateAlly(allyTargetSettings.vocations.box.knights)
  validateAlly(allyTargetSettings.groups.box.friends)
  validateAlly(allyTargetSettings.vocations.box.sorcerers, 2)

  -- Conditions settings
  for i, setting in ipairs(allyConfig.settings) do
    local widget = UI.createWidget(setting.type, allyConditions.box)
    local text = setting.text
    local val = setting.value
    widget.text:setText(text)

    if setting.type == "HealScroll" then
        widget.text:setText(widget.text:getText()..val)
        if not (text:find("Range") or text:find("Mas Res")) then
            widget.text:setText(widget.text:getText().."%")
        end
        widget.scroll:setValue(val)
        widget.scroll.onValueChange = function(scroll, value)
            setting.value = value
            widget.text:setText(text..value)
            if not (text:find("Range") or text:find("Mas Res")) then
                widget.text:setText(widget.text:getText().."%")
            end
            updateAllyBotCoreConfig()
        end
        if text:find("Range") or text:find("Mas Res") then
            widget.scroll:setMaximum(10)
        end
    else
        widget.item:setItemId(val)
        widget.item:setShowCount(false)
        widget.item.onItemChange = function(w)
            setting.value = w:getItemId()
            updateAllyBotCoreConfig()
        end
    end
  end

  -- Priority list
  local function setAllyCrementalButtons()
    local children = allyPriority.list:getChildren()
    local count = #children
    for i, child in ipairs(children) do
        if i == 1 then
            child.increment:disable()
        elseif i == count then
            child.decrement:disable()
        else
            child.increment:enable()
            child.decrement:enable()
        end
    end
  end

  local function createAllyPriorityWidget(action, index)
    local widget = UI.createWidget("PriorityEntry", allyPriority.list)

    widget:setText(action.name)
    widget.increment.onClick = function()
        local idx = allyPriority.list:getChildIndex(widget)
        local tbl = allyConfig.priorities

        allyPriority.list:moveChildToIndex(widget, idx-1)
        tbl[idx], tbl[idx-1] = tbl[idx-1], tbl[idx]
        setAllyCrementalButtons()
        updateAllyBotCoreConfig()
    end
    widget.decrement.onClick = function()
        local idx = allyPriority.list:getChildIndex(widget)
        local tbl = allyConfig.priorities

        allyPriority.list:moveChildToIndex(widget, idx+1)
        tbl[idx], tbl[idx+1] = tbl[idx+1], tbl[idx]
        setAllyCrementalButtons()
        updateAllyBotCoreConfig()
    end
    widget.enabled:setChecked(action.enabled)
    widget:setColor(action.enabled and "#98BF64" or "#dfdfdf")
    widget.enabled.onClick = function()
        action.enabled = not action.enabled
        widget:setColor(action.enabled and "#98BF64" or "#dfdfdf")
        widget.enabled:setChecked(action.enabled)
        validateAlly(widget, 1)
        updateAllyBotCoreConfig()
    end

    if action.custom then
        widget.remove:show()
        widget.remove.onClick = function()
            local idx = allyPriority.list:getChildIndex(widget)
            table.remove(allyConfig.priorities, idx)
            widget:destroy()
            setAllyCrementalButtons()
            validateAlly(allyPriority.list:getFirstChild(), 1)
            updateAllyBotCoreConfig()
        end
        widget.onDoubleClick = function()
            local window = modules.client_textedit.show(widget, {title = "Custom Spell", description = "Enter below formula for a custom healing spell"})
            schedule(50, function()
              window:raise()
              window:focus()
            end)
        end
        widget.onTextChange = function(w, text)
            action.name = text
            updateAllyBotCoreConfig()
        end
        widget:setTooltip("Double click to edit. X to remove.")
    end

    return widget
  end

  for i, action in ipairs(allyConfig.priorities) do
    createAllyPriorityWidget(action, i)

    if i == #allyConfig.priorities then
        validateAlly(allyPriority.list:getFirstChild(), 1)
        setAllyCrementalButtons()
    end
  end

  allyPriority.addSpellButton.onClick = function()
    local newSpell = {
        name = "Custom Spell " .. (#allyConfig.priorities + 1),
        enabled = true,
        custom = true
    }
    table.insert(allyConfig.priorities, newSpell)
    local widget = createAllyPriorityWidget(newSpell, #allyConfig.priorities)
    setAllyCrementalButtons()
    updateAllyBotCoreConfig()

    schedule(100, function()
        local window = modules.client_textedit.show(widget, {title = "Custom Spell", description = "Enter below formula for a custom healing spell"})
        schedule(50, function()
            window:raise()
            window:focus()
        end)
    end)
  end

  -- Sync HealEngine friend spells from config
  schedule(100, function()
    initAllyBotCoreHealer()
    syncAllyHealerState()
    if HealEngine and HealEngine.setFriendSpells then
      local friendSpells = {}
      local healAt = getAllySettingValue(5, 80)
      local granSioAt = getAllySettingValue(6, 40)

      for i, action in ipairs(allyConfig.priorities or {}) do
        if action.enabled then
          if action.strong then
            table.insert(friendSpells, {
              name = "exura gran sio",
              hp = granSioAt,
              mpCost = 140,
              cd = 1100,
              prio = 1
            })
          end
          if action.medium then
            local tioSioAt = getAllySettingValue(7, 65)
            table.insert(friendSpells, {
              name = "exura tio sio",
              hp = tioSioAt,
              mpCost = 120,
              cd = 1100,
              prio = 2
            })
          end
          if action.normal then
            table.insert(friendSpells, {
              name = "exura sio",
              hp = healAt,
              mpCost = 100,
              cd = 1100,
              prio = 3
            })
          end
          if action.custom and action.name and action.name ~= "Custom Spell" then
            table.insert(friendSpells, {
              name = action.name,
              hp = healAt,
              mpCost = 50,
              cd = 1100,
              prio = 3
            })
          end
        end
      end

      if #friendSpells > 0 then
        HealEngine.setFriendSpells(friendSpells)
      end
    end
  end)

  -- Legacy macro for friend healing (only when BotCore unavailable)
  friendHealerMacro = macro(100, function()
    if not allyConfig.enabled then return end

    local useBotCore = BotCore and BotCore.FriendHealer
    if useBotCore and BotCore.FriendHealer then
        local actionTaken = BotCore.FriendHealer.tick()
        if actionTaken then return end
    end
    if useBotCore then return end

    if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive(2) then
        return
    end

    local minHp = getAllySettingValue(8, 80)
    local minMp = getAllySettingValue(9, 50)
    if hppercent() <= minHp or manapercent() <= minMp then return end

    local healTarget = {creature=nil, hp=100}
    local inMasResRange = 0

    local spectators = {}
    if getSpectators then
        local ok, specs = pcall(getSpectators)
        if ok and specs then spectators = specs end
    end

    for _, spec in ipairs(spectators) do
        if spec:isPlayer() and not spec:isLocalPlayer() and spec:canShoot() then
            local name = spec:getName()
            local curHp = spec:getHealthPercent()
            local dist = distanceFromPlayer and distanceFromPlayer(spec:getPosition()) or 99

            if curHp and curHp < 100 then
                local isCustom = allyConfig.customPlayers and allyConfig.customPlayers[name]
                if isCustom and curHp > isCustom then break end

                if dist then
                    inMasResRange = (dist <= 3) and inMasResRange + 1 or inMasResRange
                    if curHp < healTarget.hp then
                        healTarget = {creature = spec, hp = curHp}
                    end
                end
            end
        end
    end

    if healTarget.creature then
        -- Delegate to HealEngine for spell selection
        if HealEngine and HealEngine.evaluateAlly then
          local spellList = {}
          local healAt = getAllySettingValue(5, 80)
          if allyConfig.priorities then
            for _, action in ipairs(allyConfig.priorities) do
              if action.enabled then
                if action.strong then
                  table.insert(spellList, {name="exura gran sio", hp=getAllySettingValue(6, 40), mpCost=140, cd=1100, prio=1})
                elseif action.medium then
                  table.insert(spellList, {name="exura tio sio", hp=getAllySettingValue(7, 65), mpCost=120, cd=1100, prio=2})
                elseif action.normal then
                  table.insert(spellList, {name="exura sio", hp=healAt, mpCost=100, cd=1100, prio=3})
                elseif action.custom and action.name then
                  table.insert(spellList, {name=action.name, hp=healAt, mpCost=50, cd=1100, prio=3})
                end
              end
            end
          end
          local engineAction = HealEngine.evaluateAlly(healTarget.creature, healTarget.hp, spellList)
          if engineAction then
            HealEngine.execute(engineAction)
            return
          end
        end
    end
  end)

  syncAllyHealerState()
end

UI.Separator()