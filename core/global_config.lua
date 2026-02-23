--[[
  nExBot Global Configuration
  
  Centralized configuration for global bot settings.
  Reads tool IDs from storage.extras (set in Extras panel).
  Auto doors and auto tools are always enabled by default.
  
  Features:
  - Default tool items from Extras panel (rope, shovel, machete, scythe)
  - Auto door opening (always enabled)
  - Auto use tools on terrain (always enabled)
]]

GlobalConfig = {}

-- Default item IDs (fallback if not set in extras)
local DEFAULT_ITEMS = {
  rope = 3003,      -- Rope
  shovel = 3457,    -- Shovel
  machete = 3308,   -- Machete
  scythe = 3453,    -- Scythe
  pick = 3456,      -- Pick (for rock/ore tiles)
}

-- Tile action types that require tools
local TILE_ACTIONS = {
  -- Rope spots (holes going up)
  ropeSpots = {
    384, 418, 8278, 8592, 13189, 14238, 17238, -- Common rope spots
  },
  -- Shovel spots (holes to dig)
  shovelSpots = {
    606, 593, 867, 608, 9027, -- Common shovel spots
  },
  -- Jungle grass / web (machete)
  macheteSpots = {
    2782, 3696, 3702, 2130, 2131, 2132, 2133, -- Spider webs
    3616, 3617, 3618, 3619, 3620, 3621, -- Jungle grass
  },
  -- Wheat/grain (scythe)
  scytheSpots = {
    3547, 3548, 3549, 3550, 3551, 3552, -- Wheat
  },
  -- Rock/ore (pick)
  pickSpots = {
    351, 352, 353, 354, 355, -- Loose stone pile
  },
}

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Get a tool item ID (reads from storage.extras)
function GlobalConfig.getTool(toolName)
  local extras = storage.extras or {}
  return extras[toolName] or DEFAULT_ITEMS[toolName]
end

-- Auto open doors and auto use tools are always enabled
function GlobalConfig.isEnabled(feature)
  if feature == "autoOpenDoors" then
    -- Check extras panel setting if available
    local extras = storage.extras or {}
    return extras.autoOpenDoors ~= false  -- Default true
  elseif feature == "autoUseTools" then
    return true  -- Always enabled
  end
  return false
end

-- Get the delay for tool usage
function GlobalConfig.getToolDelay()
  return 500
end

--------------------------------------------------------------------------------
-- Tile Detection Helpers
--------------------------------------------------------------------------------

-- Check if a tile requires a specific tool
-- @param tileId number: The tile/item ID to check
-- @return string|nil: Tool name or nil
function GlobalConfig.getRequiredTool(tileId)
  for _, id in ipairs(TILE_ACTIONS.ropeSpots) do
    if id == tileId then return "rope" end
  end
  for _, id in ipairs(TILE_ACTIONS.shovelSpots) do
    if id == tileId then return "shovel" end
  end
  for _, id in ipairs(TILE_ACTIONS.macheteSpots) do
    if id == tileId then return "machete" end
  end
  for _, id in ipairs(TILE_ACTIONS.scytheSpots) do
    if id == tileId then return "scythe" end
  end
  for _, id in ipairs(TILE_ACTIONS.pickSpots) do
    if id == tileId then return "pick" end
  end
  return nil
end

-- Check if an item ID is a closed door
-- @param itemId number: The item ID to check
-- @return boolean
function GlobalConfig.isClosedDoor(itemId)
  if DoorItems then
    return DoorItems.isClosedDoor(itemId)
  end
  return false
end

-- Check if an item ID is a locked door
-- @param itemId number: The item ID to check  
-- @return boolean
function GlobalConfig.isLockedDoor(itemId)
  if DoorItems then
    return DoorItems.isLockedDoor(itemId)
  end
  return false
end

-- Check if an item ID is any kind of door
-- @param itemId number: The item ID to check
-- @return boolean
function GlobalConfig.isDoor(itemId)
  if DoorItems then
    return DoorItems.isDoor(itemId)
  end
  return false
end

--------------------------------------------------------------------------------
-- Tool Usage Functions
--------------------------------------------------------------------------------

local lastToolUse = 0
local TOOL_DELAY = 500

-- Use a tool on a tile/thing
-- @param toolName string: Tool name (rope, shovel, machete, scythe, pick)
-- @param target: Target tile or thing
-- @return boolean: Success
function GlobalConfig.useTool(toolName, target)
  if (now - lastToolUse) < TOOL_DELAY then return false end
  
  local toolId = GlobalConfig.getTool(toolName)
  if not toolId then return false end
  
  -- Find the tool in inventory
  local tool = findItem(toolId)
  if not tool then
    return false
  end
  
  -- Use the tool on target
  if target then
    SafeCall.useWith(tool, target)
  else
    g_game.use(tool)
  end
  
  lastToolUse = now
  return true
end

-- Auto-handle a tile that requires a tool
-- @param tile: The tile to handle
-- @return boolean: True if handled
function GlobalConfig.handleTile(tile)
  if not tile then return false end
  
  local topThing = tile:getTopUseThing()
  if not topThing then return false end
  
  local itemId = topThing:getId()
  local toolName = GlobalConfig.getRequiredTool(itemId)
  
  if toolName then
    return GlobalConfig.useTool(toolName, topThing)
  end
  
  return false
end

-- Auto-open a door (always enabled)
-- @param tile: The tile with the door
-- @param keyId: Optional key item ID for locked doors
-- @return boolean: True if handled
function GlobalConfig.openDoor(tile, keyId)
  if not tile then return false end
  
  local topThing = tile:getTopUseThing()
  if not topThing then return false end
  
  local itemId = topThing:getId()
  
  if GlobalConfig.isLockedDoor(itemId) and keyId then
    local key = findItem(keyId)
    if key then
      SafeCall.useWith(key, topThing)
      return true
    end
  elseif GlobalConfig.isClosedDoor(itemId) then
    g_game.use(topThing)
    return true
  end
  
  return false
end