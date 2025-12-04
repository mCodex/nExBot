--[[
  ============================================================================
  nExBot Simplified Target Tab UI
  ============================================================================
  
  Consolidated UI for the Target tab with the new Intelligent TargetBot.
  Uses the optimized targeting engine with spatial hashing.
  
  LAYOUT:
  ─────────────────────────────────────────────────────────────────────────────
  [TargetBot On/Off] [Editor]
  [Target: name] (current target display)
  [Looting On/Off] [Config]
  
  Author: nExBot Team
  Version: 2.0.0
  Last Updated: December 2025
  
  ============================================================================
]]

setDefaultTab("Target")

-- Load the intelligent targetbot engine
local IntelligentTargetBot = nExBot.modules.IntelligentTargetBot or 
                              dofile("/nExBot/modules/target/intelligent_targetbot.lua")

-- Create singleton instance
local targetBot = IntelligentTargetBot.new()

--[[
  ============================================================================
  MAIN TARGETBOT PANEL
  ============================================================================
]]

local targetPanelName = "targetbot"
local targetUI = setupUI([[
Panel
  height: 38

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('TargetBot')

  Button
    id: editor
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Editor

  Label
    id: targetLabel
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 15
    text-align: left
    font: verdana-11px-rounded
    color: #aaaaaa
    text: Target: none

]])
targetUI:setId(targetPanelName)

-- Load saved configuration
if not storage.targetbot then
  storage.targetbot = {
    enabled = false,
    creatures = {},
    settings = {
      range = 7,
      faceTarget = true,
      chaseMode = true,
      attackMode = "balanced",
      targetSwitchDelay = 1000,
      avoidWaves = false,
      antiAfk = false
    }
  }
end

local config = storage.targetbot

-- Apply saved config to engine
targetBot.config = config.settings
for name, creatureConfig in pairs(config.creatures) do
  targetBot:addCreature(name, creatureConfig)
end

-- UI state
targetUI.title:setOn(config.enabled)

targetUI.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  storage.targetbot = config
  
  if config.enabled then
    targetBot:start()
    logInfo("[TargetBot] Enabled")
  else
    targetBot:stop()
    logInfo("[TargetBot] Disabled")
  end
end

-- Start if previously enabled
if config.enabled then
  targetBot:start()
end

--[[
  ============================================================================
  TARGET DISPLAY UPDATE
  ============================================================================
]]

-- Update target display periodically
macro(200, function()
  if not config.enabled then
    targetUI.targetLabel:setText("Target: none")
    targetUI.targetLabel:setColor("#aaaaaa")
    return
  end
  
  local target = targetBot:getTarget()
  if target and not target:isDead() then
    targetUI.targetLabel:setText("Target: " .. target:getName())
    targetUI.targetLabel:setColor("#44ff44")
  else
    targetUI.targetLabel:setText("Target: none")
    targetUI.targetLabel:setColor("#aaaaaa")
  end
end)

--[[
  ============================================================================
  EDITOR WINDOW
  ============================================================================
]]

local rootWidget = g_ui.getRootWidget()
local editorWindow = nil

if rootWidget then
  local success, result = pcall(function()
    return UI.createWindow('CreatureEditorWindow', rootWidget)
  end)
  if success and result then
    editorWindow = result
    editorWindow:hide()
    
    editorWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        -- Save creature configs
        config.creatures = targetBot:getAllCreatures()
        storage.targetbot = config
      end
    end
  end
end

targetUI.editor.onClick = function(widget)
  if editorWindow then
    editorWindow:show()
    editorWindow:raise()
    editorWindow:focus()
  else
    warn("[Target Tab] CreatureEditor window not available")
  end
end

--[[
  ============================================================================
  LOOTING PANEL
  ============================================================================
]]

local lootPanelName = "looting"
local lootUI = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Auto Loot')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Config

]])
lootUI:setId(lootPanelName)

-- Looting storage init
if not storage[lootPanelName] then
  storage[lootPanelName] = {
    enabled = false,
    distance = 3,
    goldOnly = false,
    skinBodies = false,
    eatFood = true,
    openBodies = true,
    items = {}
  }
end

local lootConfig = storage[lootPanelName]

lootUI.title:setOn(lootConfig.enabled)

lootUI.title.onClick = function(widget)
  lootConfig.enabled = not lootConfig.enabled
  widget:setOn(lootConfig.enabled)
  storage[lootPanelName] = lootConfig
end

-- Looting Window
local lootWindow = nil

if rootWidget then
  local success, result = pcall(function()
    return UI.createWindow('LootingWindow', rootWidget)
  end)
  if success and result then
    lootWindow = result
    lootWindow:hide()
    
    lootWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        storage[lootPanelName] = lootConfig
      end
    end
  end
end

lootUI.settings.onClick = function(widget)
  if lootWindow then
    lootWindow:show()
    lootWindow:raise()
    lootWindow:focus()
  else
    warn("[Target Tab] Looting window not available")
  end
end

--[[
  ============================================================================
  PUBLIC API (BACKWARD COMPATIBLE)
  ============================================================================
]]

TargetBot = {
  -- State queries
  isOn = function() return config.enabled end,
  isOff = function() return not config.enabled end,
  isActive = function() return config.enabled and targetBot:isTargetValid() end,
  
  -- State control
  setOn = function()
    config.enabled = true
    targetUI.title:setOn(true)
    targetBot:start()
    storage.targetbot = config
  end,
  setOff = function()
    config.enabled = false
    targetUI.title:setOn(false)
    targetBot:stop()
    storage.targetbot = config
  end,
  
  -- Target management
  getTarget = function() return targetBot:getTarget() end,
  hasValidTarget = function() return targetBot:isTargetValid() end,
  
  -- Creature management
  addCreature = function(name, settings)
    local result = targetBot:addCreature(name, settings)
    config.creatures = targetBot:getAllCreatures()
    storage.targetbot = config
    return result
  end,
  removeCreature = function(name)
    local result = targetBot:removeCreature(name)
    config.creatures = targetBot:getAllCreatures()
    storage.targetbot = config
    return result
  end,
  getCreature = function(name)
    return targetBot:getCreature(name)
  end,
  getAllCreatures = function()
    return targetBot:getAllCreatures()
  end,
  clearCreatures = function()
    targetBot:clearCreatures()
    config.creatures = {}
    storage.targetbot = config
  end,
  
  -- Settings
  getSettings = function() return config.settings end,
  setSetting = function(key, value)
    config.settings[key] = value
    targetBot:setConfig(key, value)
    storage.targetbot = config
  end,
  
  -- Statistics
  getStats = function() return targetBot:getStats() end,
  
  -- Advanced - direct engine access
  getEngine = function() return targetBot end
}

-- Looting API
AutoLoot = {
  isOn = function() return lootConfig.enabled end,
  isOff = function() return not lootConfig.enabled end,
  setOn = function()
    lootConfig.enabled = true
    lootUI.title:setOn(true)
    storage[lootPanelName] = lootConfig
  end,
  setOff = function()
    lootConfig.enabled = false
    lootUI.title:setOn(false)
    storage[lootPanelName] = lootConfig
  end,
  addItem = function(itemId)
    if not table.find(lootConfig.items, itemId) then
      table.insert(lootConfig.items, itemId)
      storage[lootPanelName] = lootConfig
    end
  end,
  removeItem = function(itemId)
    local idx = table.find(lootConfig.items, itemId)
    if idx then
      table.remove(lootConfig.items, idx)
      storage[lootPanelName] = lootConfig
    end
  end
}

logInfo("[Target Tab] Intelligent TargetBot UI loaded")
