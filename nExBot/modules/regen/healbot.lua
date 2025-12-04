--[[
  HealBot Module
  
  Advanced self-healing with spell and item management.
  Based on vBot 4.8 HealBot patterns.
  
  Author: nExBot Team
  Version: 1.0.0
]]

local standBySpells = false
local standByItems = false

local red = "#ff0800"
local blue = "#7ef9ff"

setDefaultTab("Regen")

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
    anchors.top: prev.top
    anchors.left: prev.right
    text: 2
    margin-left: 2
    size: 17 17

  Button
    id: 3
    anchors.top: prev.top
    anchors.left: prev.right
    text: 3
    margin-left: 2
    size: 17 17

  Button
    id: 4
    anchors.top: prev.top
    anchors.left: prev.right
    text: 4
    margin-left: 2
    size: 17 17

  Button
    id: 5
    anchors.top: prev.top
    anchors.left: prev.right
    text: 5
    margin-left: 2
    size: 17 17

  Button
    id: name
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 4
    height: 17
    text: Profile #1
    background: #292A2A
]])
ui:setId(healPanelName)

-- Initialize HealBot config
if not HealBotConfig then
  HealBotConfig = {}
end

if not HealBotConfig[healPanelName] or not HealBotConfig[healPanelName][1] or #HealBotConfig[healPanelName] ~= 5 then
  HealBotConfig[healPanelName] = {}
  for i = 1, 5 do
    HealBotConfig[healPanelName][i] = {
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
end

if not HealBotConfig.currentHealBotProfile or HealBotConfig.currentHealBotProfile == 0 or HealBotConfig.currentHealBotProfile > 5 then
  HealBotConfig.currentHealBotProfile = 1
end

-- Current settings reference
local currentSettings
local function setActiveProfile()
  local n = HealBotConfig.currentHealBotProfile
  currentSettings = HealBotConfig[healPanelName][n]
end
setActiveProfile()

-- Update profile button colors
local function activeProfileColor()
  for i = 1, 5 do
    if i == HealBotConfig.currentHealBotProfile then
      ui[i]:setColor("green")
    else
      ui[i]:setColor("white")
    end
  end
end
activeProfileColor()

-- Update profile name display
local function setProfileName()
  ui.name:setText(currentSettings.name)
end
setProfileName()

-- UI toggle
ui.title:setOn(currentSettings.enabled)
ui.title.onClick = function(widget)
  currentSettings.enabled = not currentSettings.enabled
  widget:setOn(currentSettings.enabled)
  vBotConfigSave("heal")
end

-- Settings window
local rootWidget = g_ui.getRootWidget()
local healWindow = nil

if rootWidget then
  healWindow = UI.createWindow('HealBotWindow', rootWidget)
  if healWindow then
    healWindow:hide()
    
    healWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        vBotConfigSave("heal")
        if healWindow.healer then healWindow.healer:show() end
        if healWindow.settings then healWindow.settings:hide() end
        if healWindow.settingsButton then healWindow.settingsButton:setText("Settings") end
      end
    end
    
    -- Settings toggle
    if healWindow.settingsButton then
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
    end
  end
end

ui.settings.onClick = function(widget)
  if healWindow then
    healWindow:show()
    healWindow:raise()
    healWindow:focus()
  end
end

-- Profile change handler
local function profileChange()
  setActiveProfile()
  activeProfileColor()
  setProfileName()
  ui.title:setOn(currentSettings.enabled)
  vBotConfigSave("heal")
end

-- Profile buttons
for i = 1, 5 do
  local button = ui[i]
  button.onClick = function()
    HealBotConfig.currentHealBotProfile = i
    profileChange()
  end
end

-- Save function
function vBotConfigSave(configType)
  -- Save to storage
  storage.HealBotConfig = HealBotConfig
end

-- Load saved config
if storage.HealBotConfig then
  HealBotConfig = storage.HealBotConfig
  setActiveProfile()
  activeProfileColor()
  setProfileName()
  ui.title:setOn(currentSettings.enabled)
end

-- Healing spell macro
macro(100, function()
  if standBySpells then return end
  if not currentSettings.enabled then return end
  
  for _, entry in pairs(currentSettings.spellTable) do
    if entry.enabled and entry.cost <= mana() then
      if canCast(entry.spell, not currentSettings.Conditions, not currentSettings.Cooldown) then
        if entry.origin == "HP%" then
          local currentHp = hppercent()
          if currentHp >= entry.minValue and currentHp <= entry.maxValue then
            say(entry.spell)
            return
          end
        elseif entry.origin == "MP%" then
          local currentMp = manapercent()
          if currentMp >= entry.minValue and currentMp <= entry.maxValue then
            say(entry.spell)
            return
          end
        elseif entry.origin == "HP" then
          local currentHp = hp()
          if currentHp >= entry.minValue and currentHp <= entry.maxValue then
            say(entry.spell)
            return
          end
        elseif entry.origin == "MP" then
          local currentMp = mana()
          if currentMp >= entry.minValue and currentMp <= entry.maxValue then
            say(entry.spell)
            return
          end
        end
      end
    end
  end
end)

-- Healing item macro
macro(250, function()
  if standByItems then return end
  if not currentSettings.enabled then return end
  
  for _, entry in pairs(currentSettings.itemTable) do
    if entry.enabled then
      if entry.origin == "HP%" then
        local currentHp = hppercent()
        if currentHp >= entry.minValue and currentHp <= entry.maxValue then
          if currentSettings.Delay then
            -- Check item cooldown if needed
          end
          useWith(entry.itemId, player)
          return
        end
      elseif entry.origin == "MP%" then
        local currentMp = manapercent()
        if currentMp >= entry.minValue and currentMp <= entry.maxValue then
          useWith(entry.itemId, player)
          return
        end
      end
    end
  end
end)

-- Public API
HealBot = {
  isOn = function()
    return currentSettings.enabled
  end,
  
  isOff = function()
    return not currentSettings.enabled
  end,
  
  setOff = function()
    currentSettings.enabled = false
    ui.title:setOn(false)
    vBotConfigSave("heal")
  end,
  
  setOn = function()
    currentSettings.enabled = true
    ui.title:setOn(true)
    vBotConfigSave("heal")
  end,
  
  getActiveProfile = function()
    return HealBotConfig.currentHealBotProfile
  end,
  
  setActiveProfile = function(n)
    if not n or not tonumber(n) or n < 1 or n > 5 then
      return error("[HealBot] wrong profile parameter! should be 1 to 5 is " .. n)
    else
      HealBotConfig.currentHealBotProfile = n
      profileChange()
    end
  end,
  
  show = function()
    if healWindow then
      healWindow:show()
      healWindow:raise()
      healWindow:focus()
    end
  end,
  
  addSpell = function(spell, origin, minValue, maxValue, cost)
    table.insert(currentSettings.spellTable, {
      enabled = true,
      spell = spell,
      origin = origin or "HP%",
      minValue = minValue or 0,
      maxValue = maxValue or 60,
      cost = cost or 20
    })
    vBotConfigSave("heal")
  end,
  
  addItem = function(itemId, origin, minValue, maxValue)
    table.insert(currentSettings.itemTable, {
      enabled = true,
      itemId = itemId,
      origin = origin or "HP%",
      minValue = minValue or 0,
      maxValue = maxValue or 30
    })
    vBotConfigSave("heal")
  end,
  
  standbySpells = function(value)
    standBySpells = value
  end,
  
  standbyItems = function(value)
    standByItems = value
  end
}
