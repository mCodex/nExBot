--[[
  nExBot Door Items Database
  ===========================
  
  Comprehensive door item IDs - hardcoded for reliability.
  No external items.xml dependency required.
  
  Architecture: Single Responsibility - Door identification only
  Pattern: Data-driven configuration
  
  To add new doors: Add the ID to the appropriate list below
]]

-- Door type constants
DOOR_TYPE = {
  CLOSED = "closed",
  OPEN = "open",
  LOCKED = "locked",
  LEVEL = "level",
  QUEST = "quest"
}

-- Closed door IDs (can be opened by clicking)
-- These are doors that block movement until used
ClosedDoorIds = {
  -- Classic wooden doors
  1629, 1632, 1638, 1640, 1642, 1644,
  -- Stone/brick doors
  1651, 1654, 1656, 1658, 1660, 1662,
  -- Dark/black doors
  1669, 1672, 1674, 1676,
  -- Metal doors
  1683, 1685, 1689, 1692, 1694, 1698,
  -- Quest/special doors
  5006, 5007,
  -- Wood variant doors
  5082, 5084, 5098, 5100, 5104, 5107, 5109, 5113, 5116, 5118, 5122, 5125, 5127, 5131, 5134, 5137, 5140, 5143,
  -- Sand/desert doors  
  5278, 5281, 5283, 5285, 5287, 5289,
  -- Ice doors
  5514, 5516,
  -- Runic doors
  5733, 5736, 5745, 5749,
  -- Elvish doors
  6192, 6195, 6197, 6199, 6201, 6203,
  -- Dwarven doors
  6249, 6252, 6254, 6256, 6258, 6260,
  -- Crystal doors
  6892, 6894, 6898, 6901, 6903, 6907,
  -- Metal variant doors
  7034, 7036, 7040, 7043, 7045, 7049, 7054, 7056,
  -- New style doors (7xxx series)
  7712, 7715, 7717, 7719, 7721,
  -- 8xxx series doors
  8252, 8254, 8256, 8258, 8260, 8262,
  -- 9xxx series doors  
  9165, 9167, 9169, 9171, 9173, 9175,
  9267, 9269, 9271, 9273,
  -- 10xxx series doors (modern updates)
  10268, 10270, 10272, 10274, 10276, 10278,
  10474, 10476, 10478, 10480,
  10786, 10788, 10790, 10792,
  -- 11xxx series doors
  11119, 11121, 11123, 11125, 11127, 11129,
  11234, 11236, 11238, 11240,
  -- 12xxx series doors
  12093, 12095, 12097, 12099,
  12188, 12190, 12192, 12194,
  -- 13xxx series doors
  13020, 13022, 13024, 13026,
  -- 17xxx series doors
  17095, 17097, 17099, 17101, 17103, 17105,
  17236, 17238, 17240, 17242,
  -- 19xxx series doors (newer content)
  19213, 19215, 19217, 19219, 19221, 19223,
  19840, 19842, 19844, 19846,
  -- 20xxx series doors (newest content)
  20273, 20275, 20277, 20279,
  20444, 20446, 20448, 20450, 20452, 20454,  -- Including 20444!
  20543, 20545, 20547, 20549,
  20720, 20722, 20724, 20726,
  -- 21xxx series doors
  21463, 21465, 21467, 21469,
  21536, 21538, 21540, 21542,
  -- 22xxx series doors
  22475, 22477, 22479, 22481,
  22810, 22812, 22814, 22816,
  -- 23xxx series doors
  23477, 23479, 23481, 23483,
  23731, 23733, 23735, 23737,
  -- 24xxx+ modern doors
  24430, 24432, 24434, 24436,
  25280, 25282, 25284, 25286,
  26172, 26174, 26176, 26178,
  27031, 27033, 27035, 27037,
  -- Common quest/special area doors
  8554, 8556, 8558, 8560,
  9573, 9575, 9577, 9579,
  10269, 10271, 10273, 10275,
  -- Thais, Carlin, Venore common doors
  1634, 1636, 1646, 1648,
  -- Kazordoon, Ab'Dendriel doors
  5734, 5738, 6193, 6196,
}

-- Locked door IDs (require a key to open)
-- These cannot be opened without the correct key item
LockedDoorIds = {
  1628, 1631, 1650, 1653, 1668, 1671, 1682, 1691,
  4912, 4913,
  5097, 5106, 5115, 5124, 5133, 5136, 5139, 5142,
  5277, 5280,
  5732, 5735,
  6191, 6194,
  6248, 6251,
  6891, 6900,
  7033, 7042,
  7711, 7714
}

-- Open door IDs (already open, walkable)
OpenDoorIds = {
  -- Classic doors open
  1630, 1633, 1639, 1641, 1643, 1645,
  1652, 1655, 1657, 1659, 1661, 1663,
  1670, 1673, 1675, 1677,
  1684, 1686, 1690, 1693, 1695, 1699,
  -- Quest doors open
  4911, 4914,
  -- Wood variants open
  5083, 5085, 5099, 5101, 5105, 5108, 5110, 5114, 5117, 5119, 5123, 5126, 5128, 5132, 5135, 5138, 5141, 5144,
  -- Sand/desert open
  5279, 5282, 5284, 5286, 5288, 5290,
  -- Ice open
  5515, 5517,
  -- Runic open
  5734, 5737, 5746, 5748,
  -- Elvish open
  6193, 6196, 6198, 6200, 6202, 6204,
  -- Dwarven open
  6250, 6253, 6255, 6257, 6259, 6261,
  -- Crystal open
  6893, 6895, 6899, 6902, 6904, 6908,
  -- Metal variants open
  7035, 7037, 7041, 7044, 7046, 7050, 7055, 7057,
  7713, 7716, 7718, 7720,
  -- 8xxx+ series open doors
  8253, 8255, 8257, 8259, 8261, 8263,
  9166, 9168, 9170, 9172, 9174, 9176,
  10269, 10271, 10273, 10275, 10277, 10279,
  -- 20xxx series open (including 20445 - open version of 20444)
  20274, 20276, 20278, 20280,
  20445, 20447, 20449, 20451, 20453, 20455,
  20544, 20546, 20548, 20550,
  20721, 20723, 20725, 20727,
}

-- Quest doors (special doors that may require quest completion)
QuestDoorIds = {
  -- Level doors and quest-specific doors
  1646, 1647, 1648, 1649,
  1664, 1665, 1666, 1667,
  1678, 1679, 1680, 1681,
  1696, 1697
}

-- Trapdoors (floor doors for going up/down)
TrapdoorIds = {
  369, 370, 411, 412, 432, 434, 475, 476, 484, 1156
}

-- Gate IDs (horizontal bars, fences, etc.)
GateIds = {
  -- Fence gates
  1237, 1238, 1239, 1240,
  -- Metal gates
  1241, 1242, 1243, 1244,
  -- Stone gates
  1259, 1260, 1261, 1262
}

-- Lookup tables for O(1) checks
local closedDoorLookup = {}
local lockedDoorLookup = {}
local openDoorLookup = {}
local questDoorLookup = {}
local trapdoorLookup = {}
local gateLookup = {}
local allDoorLookup = {}

-- Build lookup tables
local function buildLookups()
  for _, id in ipairs(ClosedDoorIds) do
    closedDoorLookup[id] = true
    allDoorLookup[id] = DOOR_TYPE.CLOSED
  end
  for _, id in ipairs(LockedDoorIds) do
    lockedDoorLookup[id] = true
    allDoorLookup[id] = DOOR_TYPE.LOCKED
  end
  for _, id in ipairs(OpenDoorIds) do
    openDoorLookup[id] = true
    allDoorLookup[id] = DOOR_TYPE.OPEN
  end
  for _, id in ipairs(QuestDoorIds) do
    questDoorLookup[id] = true
    allDoorLookup[id] = DOOR_TYPE.QUEST
  end
  for _, id in ipairs(TrapdoorIds) do
    trapdoorLookup[id] = true
  end
  for _, id in ipairs(GateIds) do
    gateLookup[id] = true
  end
end

buildLookups()

-- Door identification API
DoorItems = {
  -- Check if item ID is a door (any type)
  isDoor = function(itemId)
    return allDoorLookup[itemId] ~= nil
  end,
  
  -- Check if item ID is a closed door (can be opened)
  isClosedDoor = function(itemId)
    return closedDoorLookup[itemId] == true
  end,
  
  -- Check if item ID is a locked door (needs key)
  isLockedDoor = function(itemId)
    return lockedDoorLookup[itemId] == true
  end,
  
  -- Check if item ID is an open door
  isOpenDoor = function(itemId)
    return openDoorLookup[itemId] == true
  end,
  
  -- Check if item ID is a quest door
  isQuestDoor = function(itemId)
    return questDoorLookup[itemId] == true
  end,
  
  -- Check if item ID is a trapdoor
  isTrapdoor = function(itemId)
    return trapdoorLookup[itemId] == true
  end,
  
  -- Check if item ID is a gate
  isGate = function(itemId)
    return gateLookup[itemId] == true
  end,
  
  -- Get door type
  getDoorType = function(itemId)
    return allDoorLookup[itemId]
  end,
  
  -- Check if door can be opened without a key
  canOpenWithoutKey = function(itemId)
    return closedDoorLookup[itemId] == true
  end,
  
  -- Find door on a tile
  findDoorOnTile = function(tile)
    if not tile then return nil end
    
    local topThing = tile:getTopUseThing()
    if topThing then
      local itemId = topThing:getId()
      if allDoorLookup[itemId] then
        return topThing, allDoorLookup[itemId]
      end
    end
    
    -- Check all items on tile
    local items = tile:getItems()
    if items then
      for _, item in ipairs(items) do
        local itemId = item:getId()
        if allDoorLookup[itemId] then
          return item, allDoorLookup[itemId]
        end
      end
    end
    
    return nil
  end,
  
  -- Check if tile has a closed door that can be opened
  tileHasClosedDoor = function(tile)
    if not tile then return false end
    
    local door, doorType = DoorItems.findDoorOnTile(tile)
    return door ~= nil and doorType == DOOR_TYPE.CLOSED
  end,
  
  -- Get all closed door IDs (for configuration)
  getClosedDoorIds = function()
    return ClosedDoorIds
  end,
  
  -- Get all locked door IDs (for configuration)
  getLockedDoorIds = function()
    return LockedDoorIds
  end
}

-- Register with event bus if available
if nExBot and nExBot.EventBus then
  nExBot.EventBus:emit("door_items:loaded", {
    closedCount = #ClosedDoorIds,
    lockedCount = #LockedDoorIds,
    openCount = #OpenDoorIds
  })
end

-- Export to global namespace
nExBot = nExBot or {}
nExBot.DoorItems = DoorItems
