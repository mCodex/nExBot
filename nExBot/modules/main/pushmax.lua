--[[
  PushMax Module
  
  Automated magic wall pushing for team defense.
  Based on vBot 4.8 pushmax patterns.
  
  Author: nExBot Team
  Version: 1.0.0
]]

setDefaultTab("Main")

local panelName = "pushmax"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('PUSHMAX')

  Button
    id: push
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

]])
ui:setId(panelName)

-- Initialize storage
if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    pushDelay = 1060,
    pushMaxRuneId = 3188, -- Magic Wall rune
    mwallBlockId = 2128,  -- Magic Wall item ID on ground
    pushMaxKey = "PageUp",
    autoMode = false,
    targetPlayer = "",
    minDistance = 1,
    maxDistance = 4
  }
end

local config = storage[panelName]

-- PushMax state
local pushState = {
  lastPush = 0,
  targetCreature = nil,
  pushSequence = {}
}

-- UI state
ui.title:setOn(config.enabled)

ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  storage[panelName] = config
end

-- Create settings window
local rootWidget = g_ui.getRootWidget()
local pushWindow = nil

if rootWidget then
  pushWindow = UI.createWindow('PushMaxWindow', rootWidget)
  if pushWindow then
    pushWindow:hide()
    
    pushWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        storage[panelName] = config
      end
    end
    
    -- Setup window controls
    schedule(100, function()
      if not pushWindow then return end
      
      if pushWindow.pushDelay then
        pushWindow.pushDelay:setValue(config.pushDelay)
        pushWindow.pushDelay.onValueChange = function(w, value)
          config.pushDelay = value
        end
      end
      
      if pushWindow.runeId then
        pushWindow.runeId:setItemId(config.pushMaxRuneId)
        pushWindow.runeId.onItemChange = function(w)
          config.pushMaxRuneId = w:getItemId()
        end
      end
      
      if pushWindow.autoMode then
        pushWindow.autoMode:setOn(config.autoMode)
        pushWindow.autoMode.onClick = function(w)
          config.autoMode = not config.autoMode
          w:setOn(config.autoMode)
        end
      end
      
      if pushWindow.targetPlayer then
        pushWindow.targetPlayer:setText(config.targetPlayer)
        pushWindow.targetPlayer.onTextChange = function(w, text)
          config.targetPlayer = text
        end
      end
      
      if pushWindow.closeButton then
        pushWindow.closeButton.onClick = function()
          pushWindow:hide()
        end
      end
    end)
  end
end

ui.push.onClick = function(widget)
  if pushWindow then
    pushWindow:show()
    pushWindow:raise()
    pushWindow:focus()
  end
end

-- Calculate push direction
local function calculatePushDirection(from, to)
  local dx = to.x - from.x
  local dy = to.y - from.y
  
  -- Normalize to single step
  if dx ~= 0 then dx = dx / math.abs(dx) end
  if dy ~= 0 then dy = dy / math.abs(dy) end
  
  return {x = dx, y = dy}
end

-- Find valid mwall position
local function findMwallPosition(targetPos, pushDir)
  -- The mwall should be placed behind the target (opposite of push direction)
  local mwallPos = {
    x = targetPos.x - pushDir.x,
    y = targetPos.y - pushDir.y,
    z = targetPos.z
  }
  
  local tile = g_map.getTile(mwallPos)
  if tile and tile:isWalkable() and not tile:hasCreature() then
    return mwallPos
  end
  
  return nil
end

-- Execute push sequence
local function executePush(targetCreature)
  if not targetCreature then return end
  if now - pushState.lastPush < config.pushDelay then return end
  
  local targetPos = targetCreature:getPosition()
  local myPos = player:getPosition()
  
  -- Calculate push direction (from player towards target)
  local pushDir = calculatePushDirection(myPos, targetPos)
  
  -- Find position for magic wall
  local mwallPos = findMwallPosition(targetPos, pushDir)
  
  if mwallPos then
    -- Use magic wall rune on the position
    useWith(config.pushMaxRuneId, g_map.getTile(mwallPos):getTopThing())
    pushState.lastPush = now
    
    if nExBot and nExBot.EventBus then
      nExBot.EventBus:emit("pushmax_executed", {
        target = targetCreature:getName(),
        position = mwallPos
      })
    end
  end
end

-- Hotkey trigger
onKeyDown(function(keys)
  if not config.enabled then return end
  if keys ~= config.pushMaxKey then return end
  
  -- Get target (attacking creature or target player)
  local targetCreature = g_game.getAttackingCreature()
  
  if not targetCreature and config.targetPlayer:len() > 0 then
    for _, creature in ipairs(getSpectators()) do
      if creature:isPlayer() and creature:getName():lower() == config.targetPlayer:lower() then
        targetCreature = creature
        break
      end
    end
  end
  
  if targetCreature then
    executePush(targetCreature)
  end
end)

-- Auto mode macro
macro(100, function()
  if not config.enabled then return end
  if not config.autoMode then return end
  
  -- Get target
  local targetCreature = nil
  
  if config.targetPlayer:len() > 0 then
    for _, creature in ipairs(getSpectators()) do
      if creature:isPlayer() and creature:getName():lower() == config.targetPlayer:lower() then
        targetCreature = creature
        break
      end
    end
  end
  
  if not targetCreature then
    targetCreature = g_game.getAttackingCreature()
  end
  
  if targetCreature then
    local distance = getDistanceBetween(player:getPosition(), targetCreature:getPosition())
    
    if distance >= config.minDistance and distance <= config.maxDistance then
      executePush(targetCreature)
    end
  end
end)

-- Public API
PushMax = {
  isOn = function()
    return config.enabled
  end,
  
  isOff = function()
    return not config.enabled
  end,
  
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
  
  push = function(creature)
    if creature then
      executePush(creature)
    end
  end,
  
  setTarget = function(name)
    config.targetPlayer = name
    storage[panelName] = config
  end,
  
  getTarget = function()
    return config.targetPlayer
  end
}
