--[[
  ============================================================================
  nExBot Hold Target Module
  ============================================================================
  
  Hold target feature for persistent targeting.
  Keeps attacking the same target even when it moves or attacks fail.
  
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

local panelName = "nexbotHoldTarget"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Hold Target')

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

--[[
  ============================================================================
  STORAGE INITIALIZATION
  ============================================================================
]]

if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    mode = "Follow Target",  -- Follow Target, Keep Distance, Stand Still
    distance = 1,
    heldTarget = nil,
    heldTargetId = nil
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
  SETTINGS WINDOW
  ============================================================================
]]

local rootWidget = g_ui.getRootWidget()
local holdWindow = nil

if rootWidget then
  local success, result = pcall(function()
    return UI.createWindow('HoldTargetWindow', rootWidget)
  end)
  
  if success and result then
    holdWindow = result
    holdWindow:hide()
    
    -- Initialize enabled checkbox
    local enabledCb = holdWindow:recursiveGetChildById('Enabled')
    if enabledCb then
      enabledCb:setChecked(config.enabled)
      enabledCb.onClick = function(widget)
        config.enabled = widget:isChecked()
        ui.title:setOn(config.enabled)
        storage[panelName] = config
      end
    end
    
    -- Initialize mode combobox
    local modeCb = holdWindow:recursiveGetChildById('HoldMode')
    if modeCb then
      modeCb:setCurrentOption(config.mode)
      modeCb.onOptionChange = function(widget, text)
        config.mode = text
        storage[panelName] = config
      end
    end
    
    -- Initialize distance spinbox
    local distanceSb = holdWindow:recursiveGetChildById('HoldDistance')
    if distanceSb then
      distanceSb:setValue(config.distance)
      distanceSb.onValueChange = function(widget, value)
        config.distance = value
        storage[panelName] = config
      end
    end
    
    -- Close button
    local closeBtn = holdWindow:recursiveGetChildById('closeButton')
    if closeBtn then
      closeBtn.onClick = function()
        holdWindow:hide()
      end
    end
    
    holdWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        storage[panelName] = config
      end
    end
  end
end

ui.settings.onClick = function(widget)
  if holdWindow then
    holdWindow:show()
    holdWindow:raise()
    holdWindow:focus()
  else
    warn("[Hold Target] Settings window not available")
  end
end

--[[
  ============================================================================
  HOLD TARGET LOGIC
  ============================================================================
]]

-- Track when we get a new target
onAttackingCreatureChange(function(creature)
  if config.enabled and creature then
    config.heldTarget = creature
    config.heldTargetId = creature:getId()
  end
end)

-- Re-attack held target if lost
macro(200, function()
  if not config.enabled then return end
  if not config.heldTarget then return end
  
  local target = config.heldTarget
  
  -- Check if target is still valid
  if target:isDead() then
    config.heldTarget = nil
    config.heldTargetId = nil
    return
  end
  
  -- Check if we're still attacking
  local currentTarget = g_game.getAttackingCreature and g_game.getAttackingCreature()
  
  if not currentTarget or currentTarget ~= target then
    -- Check if target is in range
    local myPos = player:getPosition()
    local targetPos = target:getPosition()
    
    if myPos.z == targetPos.z then
      local dx = math.abs(myPos.x - targetPos.x)
      local dy = math.abs(myPos.y - targetPos.y)
      local distance = math.max(dx, dy)
      
      if distance <= 8 then
        -- Re-attack
        g_game.attack(target)
      else
        -- Target too far, clear
        config.heldTarget = nil
        config.heldTargetId = nil
      end
    else
      -- Different floor, clear
      config.heldTarget = nil
      config.heldTargetId = nil
    end
  end
  
  -- Handle movement mode
  if currentTarget and currentTarget == target then
    local myPos = player:getPosition()
    local targetPos = target:getPosition()
    local dx = math.abs(myPos.x - targetPos.x)
    local dy = math.abs(myPos.y - targetPos.y)
    local distance = math.max(dx, dy)
    
    if config.mode == "Follow Target" then
      -- Let game handle following
      if g_game.setChaseMode then
        g_game.setChaseMode(1)  -- Chase mode
      end
    elseif config.mode == "Keep Distance" then
      -- Maintain distance
      if distance < config.distance then
        -- Move away
        local moveX = 0
        local moveY = 0
        
        if myPos.x < targetPos.x then moveX = -1 end
        if myPos.x > targetPos.x then moveX = 1 end
        if myPos.y < targetPos.y then moveY = -1 end
        if myPos.y > targetPos.y then moveY = 1 end
        
        local newPos = {x = myPos.x + moveX, y = myPos.y + moveY, z = myPos.z}
        autoWalk(newPos, 3)
      elseif distance > config.distance + 1 then
        -- Move closer
        autoWalk(targetPos, 3, {marginMin = config.distance, marginMax = config.distance})
      end
    elseif config.mode == "Stand Still" then
      -- Don't move, just attack
      if g_game.setChaseMode then
        g_game.setChaseMode(0)  -- Stand mode
      end
    end
  end
end)

--[[
  ============================================================================
  PUBLIC API
  ============================================================================
]]

HoldTarget = {
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
  
  setMode = function(mode)
    config.mode = mode
    storage[panelName] = config
  end,
  
  setDistance = function(distance)
    config.distance = distance
    storage[panelName] = config
  end,
  
  getHeldTarget = function()
    return config.heldTarget
  end,
  
  clearHeldTarget = function()
    config.heldTarget = nil
    config.heldTargetId = nil
    storage[panelName] = config
  end,
  
  show = function()
    if holdWindow then
      holdWindow:show()
      holdWindow:raise()
      holdWindow:focus()
    end
  end
}

logInfo("[Hold Target] Module loaded")
