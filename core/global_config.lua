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

-- Door IDs that can be opened
local DOOR_IDS = {
  closed = {},
  open = {},
  locked = {},
  quest = {},
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
  -- Use DoorItems module if available, otherwise fall back to local
  if DoorItems then
    return DoorItems.isClosedDoor(itemId)
  end
  return DOOR_IDS.closed[itemId] == true
end

-- Check if an item ID is a locked door
-- @param itemId number: The item ID to check  
-- @return boolean
function GlobalConfig.isLockedDoor(itemId)
  -- Use DoorItems module if available, otherwise fall back to local
  if DoorItems then
    return DoorItems.isLockedDoor(itemId)
  end
  return DOOR_IDS.locked[itemId] == true
end

-- Check if an item ID is any kind of door
-- @param itemId number: The item ID to check
-- @return boolean
function GlobalConfig.isDoor(itemId)
  if DoorItems then
    return DoorItems.isDoor(itemId)
  end
  return DOOR_IDS.closed[itemId] == true or DOOR_IDS.locked[itemId] == true or DOOR_IDS.open[itemId] == true
end

-- Add a door ID to the closed doors list
function GlobalConfig.addClosedDoor(itemId)
  DOOR_IDS.closed[itemId] = true
end

-- Add a door ID to the locked doors list
function GlobalConfig.addLockedDoor(itemId)
  DOOR_IDS.locked[itemId] = true
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

--------------------------------------------------------------------------------
-- Door ID Population
-- This runs once on load to build the door database
--------------------------------------------------------------------------------

local function populateDoorIds()
  -- Common closed door IDs (from standard Tibia)
  local closedDoors = {
    -- Wooden doors
    1209, 1210, 1211, 1212, 1213, 1214, 1215, 1216,
    1217, 1218, 1219, 1220, 1221, 1222, 1223, 1224,
    1225, 1226, 1227, 1228, 1229, 1230, 1231, 1232,
    -- Stone doors
    1233, 1234, 1235, 1236, 1237, 1238, 1239, 1240,
    1241, 1242, 1243, 1244, 1245, 1246, 1247, 1248,
    -- Gate of expertise
    1249, 1250, 1251, 1252,
    -- Vertical/Horizontal wooden
    5082, 5083, 5084, 5085, 5098, 5099, 5100, 5101,
    -- Additional common doors
    5102, 5103, 5104, 5105, 5106, 5107, 5108, 5109,
    5116, 5117, 5118, 5119, 5120, 5121, 5122, 5123,
    5124, 5125, 5126, 5127, 5128, 5129, 5130, 5131,
    5132, 5133, 5134, 5135, 5136, 5137, 5138, 5139,
    5140, 5141, 5142, 5143, 5144, 5145, 5146, 5147,
    -- Newer doors
    6192, 6193, 6194, 6195, 6196, 6197, 6198, 6199,
    6249, 6250, 6251, 6252, 6253, 6254, 6255, 6256,
    6891, 6892, 6893, 6894, 6895, 6896, 6897, 6898,
    6899, 6900, 6901, 6902, 6903, 6904, 6905, 6906,
    7033, 7034, 7035, 7036, 7037, 7038, 7039, 7040,
    7041, 7042, 7043, 7044, 7045, 7046, 7047, 7048,
    8541, 8542, 8543, 8544, 8545, 8546, 8547, 8548,
    9165, 9166, 9167, 9168, 9169, 9170, 9171, 9172,
    9267, 9268, 9269, 9270, 9271, 9272, 9273, 9274,
  }
  
  for _, id in ipairs(closedDoors) do
    DOOR_IDS.closed[id] = true
  end
  
  -- Locked doors (require key)
  local lockedDoors = {
    1209, 1210, 1217, 1218, 1225, 1226, 1233, 1234,
    1241, 1242, 1249, 1250, 5082, 5083, 5098, 5099,
    5116, 5117, 5124, 5125, 5132, 5133, 5140, 5141,
  }
  
  for _, id in ipairs(lockedDoors) do
    DOOR_IDS.locked[id] = true
  end
end

-- Initialize door IDs
populateDoorIds()