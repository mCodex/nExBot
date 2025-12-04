--[[
  Wave Avoidance UI Module
  
  Tools panel integration for the Wave Avoidance AI System
  
  Author: nExBot Team
  Version: 1.0.0
]]

setDefaultTab("Tools")

local panelName = "waveAvoidance"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Wave Avoidance')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

]])
ui:setId(panelName)

-- Load wave avoidance core
local WaveAvoidance = dofile("/nExBot/modules/avoidance/wave_avoidance.lua")
local waveAvoidanceInstance = nil

-- Initialize storage
if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    checkInterval = 100,
    safeDistance = 3,
    predictionWindow = 500,
    maxThreatLevel = 10,
    avoidPlayers = false,
    prioritizePath = true,
    debugMode = false,
    -- Custom patterns added by user
    customPatterns = {}
  }
end

local config = storage[panelName]

-- Create settings window
local rootWidget = g_ui.getRootWidget()
local settingsWindow = nil

if rootWidget then
  local success, result = pcall(function()
    return UI.createWindow('WaveAvoidanceWindow', rootWidget)
  end)
  if success and result then
    settingsWindow = result
    settingsWindow:hide()
    
    -- Close handler
    settingsWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        -- Save config
        storage[panelName] = config
      end
    end
  end
end

-- Initialize UI state
ui.title:setOn(config.enabled)

-- Toggle handler
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  
  if config.enabled then
    if not waveAvoidanceInstance then
      waveAvoidanceInstance = WaveAvoidance.new(config)
    end
    waveAvoidanceInstance:start()
  else
    if waveAvoidanceInstance then
      waveAvoidanceInstance:stop()
    end
  end
  
  storage[panelName] = config
end

-- Settings button handler
ui.settings.onClick = function(widget)
  if settingsWindow then
    settingsWindow:show()
    settingsWindow:raise()
    settingsWindow:focus()
  end
end

-- Setup window controls if available
if settingsWindow then
  local function setupControls()
    -- Check interval
    if settingsWindow.checkInterval then
      settingsWindow.checkInterval:setValue(config.checkInterval)
      settingsWindow.checkInterval.onValueChange = function(widget, value)
        config.checkInterval = value
        if waveAvoidanceInstance then
          waveAvoidanceInstance:setConfig("checkInterval", value)
        end
      end
    end
    
    -- Safe distance
    if settingsWindow.safeDistance then
      settingsWindow.safeDistance:setValue(config.safeDistance)
      settingsWindow.safeDistance.onValueChange = function(widget, value)
        config.safeDistance = value
        if waveAvoidanceInstance then
          waveAvoidanceInstance:setConfig("safeDistance", value)
        end
      end
    end
    
    -- Max threat level
    if settingsWindow.maxThreatLevel then
      settingsWindow.maxThreatLevel:setValue(config.maxThreatLevel)
      settingsWindow.maxThreatLevel.onValueChange = function(widget, value)
        config.maxThreatLevel = value
        if waveAvoidanceInstance then
          waveAvoidanceInstance:setConfig("maxThreatLevel", value)
        end
      end
    end
    
    -- Avoid players toggle
    if settingsWindow.avoidPlayers then
      settingsWindow.avoidPlayers:setOn(config.avoidPlayers)
      settingsWindow.avoidPlayers.onClick = function(widget)
        config.avoidPlayers = not config.avoidPlayers
        widget:setOn(config.avoidPlayers)
        if waveAvoidanceInstance then
          waveAvoidanceInstance:setConfig("avoidPlayers", config.avoidPlayers)
        end
      end
    end
    
    -- Prioritize path toggle
    if settingsWindow.prioritizePath then
      settingsWindow.prioritizePath:setOn(config.prioritizePath)
      settingsWindow.prioritizePath.onClick = function(widget)
        config.prioritizePath = not config.prioritizePath
        widget:setOn(config.prioritizePath)
        if waveAvoidanceInstance then
          waveAvoidanceInstance:setConfig("prioritizePath", config.prioritizePath)
        end
      end
    end
    
    -- Debug mode toggle
    if settingsWindow.debugMode then
      settingsWindow.debugMode:setOn(config.debugMode)
      settingsWindow.debugMode.onClick = function(widget)
        config.debugMode = not config.debugMode
        widget:setOn(config.debugMode)
        if waveAvoidanceInstance then
          waveAvoidanceInstance:setConfig("debugMode", config.debugMode)
        end
      end
    end
    
    -- Close button
    if settingsWindow.closeButton then
      settingsWindow.closeButton.onClick = function()
        settingsWindow:hide()
      end
    end
  end
  
  schedule(100, setupControls)
end

-- Auto-start if enabled
if config.enabled then
  schedule(500, function()
    waveAvoidanceInstance = WaveAvoidance.new(config)
    waveAvoidanceInstance:start()
  end)
end

-- Public API
WaveAvoidanceUI = {
  isEnabled = function()
    return config.enabled
  end,
  
  setEnabled = function(enabled)
    config.enabled = enabled
    ui.title:setOn(enabled)
    
    if enabled then
      if not waveAvoidanceInstance then
        waveAvoidanceInstance = WaveAvoidance.new(config)
      end
      waveAvoidanceInstance:start()
    else
      if waveAvoidanceInstance then
        waveAvoidanceInstance:stop()
      end
    end
  end,
  
  getDangerLevel = function()
    if waveAvoidanceInstance then
      return waveAvoidanceInstance:getDangerLevel()
    end
    return 0
  end,
  
  isInDanger = function()
    if waveAvoidanceInstance then
      return waveAvoidanceInstance:isInDanger()
    end
    return false
  end,
  
  addPattern = function(creatureName, pattern)
    if waveAvoidanceInstance then
      waveAvoidanceInstance:addPattern(creatureName, pattern)
    end
    -- Also save to storage
    if not config.customPatterns[creatureName] then
      config.customPatterns[creatureName] = {}
    end
    table.insert(config.customPatterns[creatureName], pattern)
    storage[panelName] = config
  end,
  
  getConfig = function()
    return config
  end
}
