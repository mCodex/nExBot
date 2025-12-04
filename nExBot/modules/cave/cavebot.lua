--[[
  ============================================================================
  nExBot CaveBot Module
  ============================================================================
  
  Main CaveBot controller for automated hunting.
  Handles waypoint navigation, actions, and hunting loop management.
  
  WHAT IS CAVEBOT?
  CaveBot automates the hunting process by following a series of "waypoints"
  (positions on the map). Each waypoint can have an action like:
  - Walk to position
  - Use rope/shovel/ladder
  - Go to a named label
  - Execute custom functions
  - Wait for a duration
  
  WAYPOINT FLOW:
  1. Walk → Position 1
  2. Rope → Use rope at hole
  3. Walk → Position 2
  4. Label → "hunt_start"
  5. Stand → Stay at position (attack monsters)
  6. Walk → Position 3
  7. Goto → "hunt_start" (loops back)
  
  INTEGRATION:
  - TargetBot: CaveBot pauses when TargetBot is attacking
  - Depositor: Handles town/depot operations
  - Supply Check: Triggers refill when supplies are low
  
  PERFORMANCE FEATURES:
  - Local function caching
  - Early returns to minimize processing
  - Efficient position comparison
  
  Author: nExBot Team
  Version: 2.0.0 (Optimized)
  Last Updated: December 2025
  
  ============================================================================
]]

--[[
  ============================================================================
  LOCAL CACHING FOR PERFORMANCE
  ============================================================================
]]
local table_insert = table.insert
local table_remove = table.remove
local ipairs = ipairs
local math_abs = math.abs
local string_format = string.format
local pcall = pcall

--[[
  ============================================================================
  UI SETUP
  ============================================================================
]]
setDefaultTab("Cave")

-- CaveBot global namespace
CaveBot = {}
CaveBot.Extensions = {}

--[[
  ============================================================================
  INTERNAL STATE
  ============================================================================
  
  caveBotState tracks the current execution context:
  - enabled: Master on/off switch
  - paused: Temporarily paused (e.g., during combat)
  - currentWaypoint: Index of current waypoint
  - waitingFor: Current blocking operation (nil when ready)
  ============================================================================
]]
local caveBotState = {
  enabled = false,        -- Master enable flag
  paused = false,         -- Pause flag (doesn't persist)
  currentWaypoint = 1,    -- Current waypoint index
  waypoints = {},         -- Reference to waypoint list
  huntingArea = nil,      -- Current hunting area name
  lastAction = 0,         -- Timestamp of last action
  waitingFor = nil        -- Current wait reason: "timer", "delay", nil
}

--[[
  ============================================================================
  MAIN UI PANEL
  ============================================================================
]]
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

--[[
  ============================================================================
  STORAGE INITIALIZATION
  ============================================================================
]]

if not storage.cavebot then
  storage.cavebot = {
    enabled = false,
    waypoints = {},
    settings = {
      walkDelay = 100,        -- Delay between walk steps (ms)
      actionDelay = 200,      -- Delay between actions (ms)
      retryCount = 3,         -- Retries for failed actions
      useRope = true,         -- Auto-use rope at holes
      useShovel = true,       -- Auto-use shovel at loose stones
      useMachete = true,      -- Auto-use machete at jungle grass
      usePickaxe = false,     -- Auto-use pickaxe at rocks
      openDoors = true,       -- Auto-open doors
      ignoreCreatures = false,-- Walk through creatures
      walkMethod = "auto"     -- "auto", "arrow", "ctrl"
    }
  }
end

local config = storage.cavebot

--[[
  ============================================================================
  UI EVENT HANDLERS
  ============================================================================
]]

-- Initialize toggle state from config
ui.title:setOn(config.enabled)

-- Main on/off toggle
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  caveBotState.enabled = config.enabled
  widget:setOn(config.enabled)
  storage.cavebot = config
  
  if config.enabled then
    if logInfo then logInfo("[CaveBot] Enabled") end
  else
    if logInfo then logInfo("[CaveBot] Disabled") end
  end
end

-- Config window
local caveBotWindow = nil
local rootWidget = g_ui.getRootWidget()

if rootWidget then
  caveBotWindow = UI.createWindow('CaveBotWindow', rootWidget)
  if caveBotWindow then
    caveBotWindow:hide()
    
    -- Save config when window closes
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

--[[
  ============================================================================
  WAYPOINT TYPES
  ============================================================================
  
  Defines all available waypoint actions.
  Each type has specific handling in executeWaypoint().
  ============================================================================
]]
CaveBot.WaypointTypes = {
  WALK = "walk",        -- Walk to position
  STAND = "stand",      -- Walk and stay (for luring/attacking)
  ROPE = "rope",        -- Use rope at position
  SHOVEL = "shovel",    -- Use shovel at position
  LADDER = "ladder",    -- Click ladder at position
  STAIRS = "stairs",    -- Click stairs at position
  LABEL = "label",      -- Named marker (for goto)
  GOTO = "goto",        -- Jump to a label
  FUNCTION = "function",-- Execute custom Lua function
  WAIT = "wait",        -- Wait for duration (ms)
  LURE = "lure",        -- Enter lure mode
  ACTION = "action",    -- Custom action
  NPC = "npc",          -- NPC interaction
  SAY = "say"           -- Say text in-game
}

--[[
  ============================================================================
  WAYPOINT MANAGEMENT
  ============================================================================
]]

--- Adds a new waypoint to the route
-- @param waypointType (string) Type from CaveBot.WaypointTypes
-- @param data (table|nil) Waypoint data (pos, name, etc.)
-- @return (number) Index of the new waypoint
function CaveBot.addWaypoint(waypointType, data)
  data = data or {}
  data.type = waypointType
  data.pos = data.pos or player:getPosition()
  
  table_insert(config.waypoints, data)
  storage.cavebot = config
  
  if logInfo then
    logInfo(string_format("[CaveBot] Added waypoint: %s at %d, %d, %d", 
      waypointType, data.pos.x, data.pos.y, data.pos.z))
  end
  
  return #config.waypoints
end

--- Removes a waypoint by index
-- @param index (number) Waypoint index to remove
-- @return (boolean) Success
function CaveBot.removeWaypoint(index)
  if config.waypoints[index] then
    table_remove(config.waypoints, index)
    storage.cavebot = config
    return true
  end
  return false
end

--- Clears all waypoints
function CaveBot.clearWaypoints()
  config.waypoints = {}
  caveBotState.currentWaypoint = 1
  storage.cavebot = config
end

--- Gets the current waypoint data
-- @return (table|nil) Current waypoint or nil
function CaveBot.getCurrentWaypoint()
  return config.waypoints[caveBotState.currentWaypoint]
end

--- Gets total waypoint count
-- @return (number) Number of waypoints
function CaveBot.getWaypointCount()
  return #config.waypoints
end

--- Sets the current waypoint index
-- @param index (number) New waypoint index
-- @return (boolean) Success
function CaveBot.setCurrentWaypoint(index)
  if index >= 1 and index <= #config.waypoints then
    caveBotState.currentWaypoint = index
    return true
  end
  return false
end

--- Jumps to a named label
-- @param labelName (string) Name of the label waypoint
-- @return (boolean) Success
function CaveBot.gotoLabel(labelName)
  for i, wp in ipairs(config.waypoints) do
    if wp.type == CaveBot.WaypointTypes.LABEL and wp.name == labelName then
      caveBotState.currentWaypoint = i
      return true
    end
  end
  return false
end

--[[
  ============================================================================
  WAYPOINT EXECUTION
  ============================================================================
]]

--- Executes the action for a waypoint
-- Called when player reaches the waypoint position
-- 
-- @param waypoint (table) Waypoint data
-- @return (boolean) True if action completed successfully
local function executeWaypoint(waypoint)
  if not waypoint then return false end
  
  local wpType = waypoint.type
  local pos = waypoint.pos
  
  -- ========================================
  -- WALK / STAND
  -- ========================================
  if wpType == CaveBot.WaypointTypes.WALK or wpType == CaveBot.WaypointTypes.STAND then
    if not player:isWalking() then
      local result = autoWalk(pos, 10, {marginMin = 0, marginMax = 0})
      return result
    end
    return false
    
  -- ========================================
  -- ROPE - Use rope item at hole
  -- ========================================
  elseif wpType == CaveBot.WaypointTypes.ROPE then
    local tile = g_map.getTile(pos)
    if tile then
      local topThing = tile:getTopUseThing()
      if topThing then
        useWith(3003, topThing)  -- Rope item ID: 3003
        return true
      end
    end
    return false
    
  -- ========================================
  -- SHOVEL - Use shovel at loose stone
  -- ========================================
  elseif wpType == CaveBot.WaypointTypes.SHOVEL then
    local tile = g_map.getTile(pos)
    if tile then
      local topThing = tile:getTopUseThing()
      if topThing then
        useWith(3457, topThing)  -- Shovel item ID: 3457
        return true
      end
    end
    return false
    
  -- ========================================
  -- LADDER / STAIRS - Click to use
  -- ========================================
  elseif wpType == CaveBot.WaypointTypes.LADDER or wpType == CaveBot.WaypointTypes.STAIRS then
    local tile = g_map.getTile(pos)
    if tile then
      local topThing = tile:getTopUseThing()
      if topThing then
        g_game.use(topThing)
        return true
      end
    end
    return false
    
  -- ========================================
  -- LABEL - Just a marker, always succeeds
  -- ========================================
  elseif wpType == CaveBot.WaypointTypes.LABEL then
    return true
    
  -- ========================================
  -- GOTO - Jump to another label
  -- ========================================
  elseif wpType == CaveBot.WaypointTypes.GOTO then
    return CaveBot.gotoLabel(waypoint.label)
    
  -- ========================================
  -- FUNCTION - Execute custom Lua function
  -- ========================================
  elseif wpType == CaveBot.WaypointTypes.FUNCTION then
    if waypoint.func then
      local success, result = pcall(waypoint.func)
      return success and result
    end
    return true
    
  -- ========================================
  -- WAIT - Wait for specified duration
  -- ========================================
  elseif wpType == CaveBot.WaypointTypes.WAIT then
    local duration = waypoint.duration or 1000
    schedule(duration, function()
      caveBotState.waitingFor = nil
    end)
    caveBotState.waitingFor = "timer"
    return true
    
  -- ========================================
  -- LURE - Handled by lure manager
  -- ========================================
  elseif wpType == CaveBot.WaypointTypes.LURE then
    return true
    
  -- ========================================
  -- SAY - Speak text in-game
  -- ========================================
  elseif wpType == CaveBot.WaypointTypes.SAY then
    if waypoint.text then
      say(waypoint.text)
    end
    return true
    
  -- ========================================
  -- NPC - NPC interaction via NPC module
  -- ========================================
  elseif wpType == CaveBot.WaypointTypes.NPC then
    if waypoint.npcName and NPC and NPC.talk then
      NPC.talk(waypoint.npcName, waypoint.messages or {})
    end
    return true
  end
  
  return false
end

--- Checks if player is at a position within margin
-- @param pos (table) Target position
-- @param margin (number) Allowed distance (default: 0)
-- @return (boolean) True if within margin
local function isAtPosition(pos, margin)
  margin = margin or 0
  local myPos = player:getPosition()
  return math_abs(myPos.x - pos.x) <= margin 
     and math_abs(myPos.y - pos.y) <= margin 
     and myPos.z == pos.z
end

--[[
  ============================================================================
  MAIN CAVEBOT LOOP
  ============================================================================
  
  Runs every 100ms and handles:
  1. State checks (enabled, paused, waiting)
  2. TargetBot integration (pause during combat)
  3. Waypoint position check
  4. Waypoint action execution
  5. Walking to next waypoint
  ============================================================================
]]
macro(100, function()
  -- Early returns for efficiency
  if not config.enabled then return end
  if caveBotState.paused then return end
  if caveBotState.waitingFor then return end
  if player:isWalking() then return end
  
  -- Pause during TargetBot combat
  if TargetBot and TargetBot.isActive and TargetBot.isActive() then
    return
  end
  
  -- Get current waypoint
  local waypoint = CaveBot.getCurrentWaypoint()
  if not waypoint then
    -- No more waypoints, loop back to start
    caveBotState.currentWaypoint = 1
    return
  end
  
  -- Check if at waypoint position
  if isAtPosition(waypoint.pos, 0) then
    -- Execute waypoint action
    local success = executeWaypoint(waypoint)
    
    if success then
      -- Advance to next waypoint
      caveBotState.currentWaypoint = caveBotState.currentWaypoint + 1
      if caveBotState.currentWaypoint > #config.waypoints then
        caveBotState.currentWaypoint = 1  -- Loop
      end
    end
  else
    -- Walk to waypoint
    if not player:isWalking() then
      autoWalk(waypoint.pos, 10, {marginMin = 0, marginMax = 0})
    end
  end
end)

--[[
  ============================================================================
  PUBLIC API
  ============================================================================
]]

--- Checks if CaveBot is enabled
-- @return (boolean) True if enabled
CaveBot.isOn = function()
  return config.enabled
end

--- Checks if CaveBot is disabled
-- @return (boolean) True if disabled
CaveBot.isOff = function()
  return not config.enabled
end

--- Enables CaveBot
CaveBot.setOn = function()
  config.enabled = true
  caveBotState.enabled = true
  ui.title:setOn(true)
  storage.cavebot = config
end

--- Disables CaveBot
CaveBot.setOff = function()
  config.enabled = false
  caveBotState.enabled = false
  ui.title:setOn(false)
  storage.cavebot = config
end

--- Pauses CaveBot (temporary, doesn't persist)
CaveBot.pause = function()
  caveBotState.paused = true
end

--- Resumes CaveBot from pause
CaveBot.resume = function()
  caveBotState.paused = false
end

--- Checks if CaveBot is paused
-- @return (boolean) True if paused
CaveBot.isPaused = function()
  return caveBotState.paused
end

--- Adds a delay before next action
-- @param ms (number) Delay in milliseconds
CaveBot.delay = function(ms)
  caveBotState.waitingFor = "delay"
  schedule(ms, function()
    caveBotState.waitingFor = nil
  end)
end

--- Gets current waypoint index
-- @return (number) Current index
CaveBot.getCurrentIndex = function()
  return caveBotState.currentWaypoint
end

--- Gets all waypoints
-- @return (table) Array of waypoints
CaveBot.getWaypoints = function()
  return config.waypoints
end

--[[
  ============================================================================
  LOAD EXTENSIONS
  ============================================================================
]]
dofile("/nExBot/modules/cave/actions.lua")
dofile("/nExBot/modules/cave/editor.lua")
dofile("/nExBot/modules/cave/recorder.lua")
dofile("/nExBot/modules/cave/depositor.lua")
dofile("/nExBot/modules/cave/supply_check.lua")

if logInfo then
  logInfo("[CaveBot] Module loaded")
end
