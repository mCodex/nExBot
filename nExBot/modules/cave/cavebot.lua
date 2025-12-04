--[[
  CaveBot Module
  
  Main CaveBot controller for automated hunting.
  Based on vBot 4.8 CaveBot patterns.
  
  Author: nExBot Team
  Version: 1.0.0
]]

setDefaultTab("Cave")

-- CaveBot global namespace
CaveBot = {}
CaveBot.Extensions = {}

-- CaveBot state
local caveBotState = {
  enabled = false,
  paused = false,
  currentWaypoint = 1,
  waypoints = {},
  huntingArea = nil,
  lastAction = 0,
  waitingFor = nil
}

-- Main CaveBot UI
local panelName = "cavebot"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('CaveBot')

  Button
    id: config
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Config

]])
ui:setId(panelName)

-- Storage initialization
if not storage.cavebot then
  storage.cavebot = {
    enabled = false,
    waypoints = {},
    settings = {
      walkDelay = 100,
      actionDelay = 200,
      retryCount = 3,
      useRope = true,
      useShovel = true,
      useMachete = true,
      usePickaxe = false,
      openDoors = true,
      ignoreCreatures = false,
      walkMethod = "auto"
    }
  }
end

local config = storage.cavebot

-- UI state
ui.title:setOn(config.enabled)

ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  caveBotState.enabled = config.enabled
  widget:setOn(config.enabled)
  storage.cavebot = config
  
  if config.enabled then
    logInfo("[CaveBot] Enabled")
  else
    logInfo("[CaveBot] Disabled")
  end
end

-- Config button
local caveBotWindow = nil
local rootWidget = g_ui.getRootWidget()

if rootWidget then
  caveBotWindow = UI.createWindow('CaveBotWindow', rootWidget)
  if caveBotWindow then
    caveBotWindow:hide()
    
    caveBotWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        storage.cavebot = config
      end
    end
  end
end

ui.config.onClick = function(widget)
  if caveBotWindow then
    caveBotWindow:show()
    caveBotWindow:raise()
    caveBotWindow:focus()
  end
end

-- Waypoint types
CaveBot.WaypointTypes = {
  WALK = "walk",
  STAND = "stand",
  ROPE = "rope",
  SHOVEL = "shovel",
  LADDER = "ladder",
  STAIRS = "stairs",
  LABEL = "label",
  GOTO = "goto",
  FUNCTION = "function",
  WAIT = "wait",
  LURE = "lure",
  ACTION = "action",
  NPC = "npc",
  SAY = "say"
}

-- Add waypoint
function CaveBot.addWaypoint(waypointType, data)
  data = data or {}
  data.type = waypointType
  data.pos = data.pos or player:getPosition()
  
  table.insert(config.waypoints, data)
  storage.cavebot = config
  
  logInfo(string.format("[CaveBot] Added waypoint: %s at %d, %d, %d", 
    waypointType, data.pos.x, data.pos.y, data.pos.z))
  
  return #config.waypoints
end

-- Remove waypoint
function CaveBot.removeWaypoint(index)
  if config.waypoints[index] then
    table.remove(config.waypoints, index)
    storage.cavebot = config
    return true
  end
  return false
end

-- Clear all waypoints
function CaveBot.clearWaypoints()
  config.waypoints = {}
  caveBotState.currentWaypoint = 1
  storage.cavebot = config
end

-- Get current waypoint
function CaveBot.getCurrentWaypoint()
  return config.waypoints[caveBotState.currentWaypoint]
end

-- Get waypoint count
function CaveBot.getWaypointCount()
  return #config.waypoints
end

-- Set current waypoint
function CaveBot.setCurrentWaypoint(index)
  if index >= 1 and index <= #config.waypoints then
    caveBotState.currentWaypoint = index
    return true
  end
  return false
end

-- Go to label
function CaveBot.gotoLabel(labelName)
  for i, wp in ipairs(config.waypoints) do
    if wp.type == CaveBot.WaypointTypes.LABEL and wp.name == labelName then
      caveBotState.currentWaypoint = i
      return true
    end
  end
  return false
end

-- Execute waypoint action
local function executeWaypoint(waypoint)
  if not waypoint then return false end
  
  local wpType = waypoint.type
  local pos = waypoint.pos
  
  if wpType == CaveBot.WaypointTypes.WALK or wpType == CaveBot.WaypointTypes.STAND then
    -- Walk to position
    if not player:isWalking() then
      local result = autoWalk(pos, 10, {marginMin = 0, marginMax = 0})
      return result
    end
    return false
    
  elseif wpType == CaveBot.WaypointTypes.ROPE then
    -- Use rope
    local tile = g_map.getTile(pos)
    if tile then
      local topThing = tile:getTopUseThing()
      if topThing then
        useWith(3003, topThing) -- Rope item ID
        return true
      end
    end
    return false
    
  elseif wpType == CaveBot.WaypointTypes.SHOVEL then
    -- Use shovel
    local tile = g_map.getTile(pos)
    if tile then
      local topThing = tile:getTopUseThing()
      if topThing then
        useWith(3457, topThing) -- Shovel item ID
        return true
      end
    end
    return false
    
  elseif wpType == CaveBot.WaypointTypes.LADDER or wpType == CaveBot.WaypointTypes.STAIRS then
    -- Use ladder/stairs
    local tile = g_map.getTile(pos)
    if tile then
      local topThing = tile:getTopUseThing()
      if topThing then
        g_game.use(topThing)
        return true
      end
    end
    return false
    
  elseif wpType == CaveBot.WaypointTypes.LABEL then
    -- Labels are just markers, skip
    return true
    
  elseif wpType == CaveBot.WaypointTypes.GOTO then
    -- Go to label
    return CaveBot.gotoLabel(waypoint.label)
    
  elseif wpType == CaveBot.WaypointTypes.FUNCTION then
    -- Execute custom function
    if waypoint.func then
      local success, result = pcall(waypoint.func)
      return success and result
    end
    return true
    
  elseif wpType == CaveBot.WaypointTypes.WAIT then
    -- Wait for specified time
    local duration = waypoint.duration or 1000
    schedule(duration, function()
      caveBotState.waitingFor = nil
    end)
    caveBotState.waitingFor = "timer"
    return true
    
  elseif wpType == CaveBot.WaypointTypes.LURE then
    -- Lure mode
    -- Will be handled by lure manager
    return true
    
  elseif wpType == CaveBot.WaypointTypes.SAY then
    -- Say text
    if waypoint.text then
      say(waypoint.text)
    end
    return true
    
  elseif wpType == CaveBot.WaypointTypes.NPC then
    -- NPC interaction
    if waypoint.npcName then
      NPC.talk(waypoint.npcName, waypoint.messages or {})
    end
    return true
  end
  
  return false
end

-- Check if at waypoint position
local function isAtPosition(pos, margin)
  margin = margin or 0
  local myPos = player:getPosition()
  return math.abs(myPos.x - pos.x) <= margin 
     and math.abs(myPos.y - pos.y) <= margin 
     and myPos.z == pos.z
end

-- Main CaveBot loop
macro(100, function()
  if not config.enabled then return end
  if caveBotState.paused then return end
  if caveBotState.waitingFor then return end
  if player:isWalking() then return end
  
  -- Check if TargetBot is active
  if TargetBot and TargetBot.isActive and TargetBot.isActive() then
    return
  end
  
  -- Get current waypoint
  local waypoint = CaveBot.getCurrentWaypoint()
  if not waypoint then
    -- No more waypoints, loop back
    caveBotState.currentWaypoint = 1
    return
  end
  
  -- Check if at waypoint
  if isAtPosition(waypoint.pos, 0) then
    -- Execute waypoint action
    local success = executeWaypoint(waypoint)
    
    if success then
      -- Move to next waypoint
      caveBotState.currentWaypoint = caveBotState.currentWaypoint + 1
      if caveBotState.currentWaypoint > #config.waypoints then
        caveBotState.currentWaypoint = 1
      end
    end
  else
    -- Walk to waypoint
    if not player:isWalking() then
      autoWalk(waypoint.pos, 10, {marginMin = 0, marginMax = 0})
    end
  end
end)

-- Public API
CaveBot.isOn = function()
  return config.enabled
end

CaveBot.isOff = function()
  return not config.enabled
end

CaveBot.setOn = function()
  config.enabled = true
  caveBotState.enabled = true
  ui.title:setOn(true)
  storage.cavebot = config
end

CaveBot.setOff = function()
  config.enabled = false
  caveBotState.enabled = false
  ui.title:setOn(false)
  storage.cavebot = config
end

CaveBot.pause = function()
  caveBotState.paused = true
end

CaveBot.resume = function()
  caveBotState.paused = false
end

CaveBot.isPaused = function()
  return caveBotState.paused
end

CaveBot.delay = function(ms)
  caveBotState.waitingFor = "delay"
  schedule(ms, function()
    caveBotState.waitingFor = nil
  end)
end

-- Load CaveBot extensions/actions
dofile("/nExBot/modules/cave/actions.lua")
dofile("/nExBot/modules/cave/editor.lua")
dofile("/nExBot/modules/cave/recorder.lua")
dofile("/nExBot/modules/cave/depositor.lua")
dofile("/nExBot/modules/cave/supply_check.lua")

logInfo("[CaveBot] Module loaded")
