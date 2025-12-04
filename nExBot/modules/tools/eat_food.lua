--[[
  ============================================================================
  nExBot Eat Food Module
  ============================================================================
  
  Simple eat food feature.
  Separate from automation for granular control.
  
  Author: nExBot Team
  Version: 2.0.0
  Last Updated: December 2025
  
  ============================================================================
]]

setDefaultTab("Tools")

--[[
  ============================================================================
  PANEL SETUP
  ============================================================================
]]

local panelName = "nexbotEatFood"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    !text: tr('Eat Food')

]])
ui:setId(panelName)

--[[
  ============================================================================
  STORAGE INITIALIZATION
  ============================================================================
]]

if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    interval = 30000,
    lastEat = 0
  }
end
local config = storage[panelName]

--[[
  ============================================================================
  UI TOGGLE
  ============================================================================
]]

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  storage[panelName] = config
end

--[[
  ============================================================================
  FOOD IDS
  ============================================================================
]]

local foodIds = {
  -- Common foods
  3607, -- Meat
  3585, -- Salmon
  3593, -- Roast Meat
  3582, -- Ham
  3600, -- Cheese
  3601, -- Brown Bread
  3599, -- Cake
  3596, -- Cookies
  3586, -- Crunchy Rolls
  3592, -- Cake Piece
  3597, -- Dragon Ham
  3583, -- Carrot
  3587, -- Lemon
  3588, -- Raspberry
  3589, -- Cherries
  3590, -- Blueberry
  3591, -- Pear
  3723, -- Bread
  8112, -- Mango
  9992, -- Rice Ball
  3595, -- Fish
  3606, -- Meat
  3578, -- Cake
  3584  -- Sausage
}

--[[
  ============================================================================
  EAT FOOD MACRO
  ============================================================================
]]

macro(1000, function()
  if not config.enabled then return end
  if now - config.lastEat < config.interval then return end
  
  for _, foodId in ipairs(foodIds) do
    if itemAmount(foodId) > 0 then
      useWith(foodId, player)
      config.lastEat = now
      storage[panelName] = config
      return
    end
  end
end)

--[[
  ============================================================================
  PUBLIC API
  ============================================================================
]]

EatFood = {
  isOn = function() return config.enabled end,
  isOff = function() return not config.enabled end,
  
  setOn = function()
    config.enabled = true
    ui.title:setOn(true)
    storage[panelName] = config
  end,
  
  setOff = function()
    config.enabled = false
    ui.title:setOn(false)
    storage[panelName] = config
  end,
  
  setInterval = function(ms)
    config.interval = ms
    storage[panelName] = config
  end,
  
  forceEat = function()
    for _, foodId in ipairs(foodIds) do
      if itemAmount(foodId) > 0 then
        useWith(foodId, player)
        config.lastEat = now
        return true
      end
    end
    return false
  end
}

logInfo("[EatFood] Module loaded")
