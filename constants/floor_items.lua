--[[
  Floor Items Constants - Single Source of Truth
  
  Consolidates floor-change item IDs, field items, and minimap colors
  that were duplicated across 5+ files.
  
  USAGE:
    dofile("constants/floor_items.lua")  -- Loads FloorItems globally
    if FloorItems.FLOOR_CHANGE[itemId] then ... end
    if FloorItems.isFloorChange(itemId) then ... end
]]

-- Declare as global (not local) so it's accessible after dofile
FloorItems = FloorItems or {}

-- Singleton guard: skip the (large) body on subsequent dofile() calls
if FloorItems._loaded then return FloorItems end

-- ============================================================================
-- MINIMAP COLORS FOR FLOOR CHANGE
-- ============================================================================

FloorItems.FLOOR_CHANGE_COLORS = {
  [210] = true, [211] = true,  -- Stairs up/down
  [212] = true, [213] = true,  -- Rope spot / Ladder
  [214] = true, [215] = true,  -- Additional floor-change colors
  [216] = true, [217] = true,
}

-- LRU cache for isFloorChangeTile results (500 entries, no TTL — tiles don't change)
local _fcTileCache = nil
local function getFcCache()
  if _fcTileCache then return _fcTileCache end
  local ok, wc = pcall(require, "utils.weak_cache")
  if ok and wc and wc.createLRU then
    _fcTileCache = wc.createLRU(500)
  end
  return _fcTileCache
end

local function makeFcKey(pos)
  return pos.x * 100000 + pos.y * 100 + pos.z
end

-- ============================================================================
-- FLOOR CHANGE ITEMS (Stairs, Ramps, Ladders, Holes, Teleports)
-- ============================================================================

FloorItems.FLOOR_CHANGE = {
  -- ═══════════════════════════════════════════════════════════════════════
  -- STAIRS (Stone)
  -- ═══════════════════════════════════════════════════════════════════════
  [414] = true, [415] = true, [416] = true, [417] = true,
  [428] = true, [429] = true, [430] = true, [431] = true,
  [432] = true, [433] = true, [434] = true, [435] = true,
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- STAIRS (Wooden)
  -- ═══════════════════════════════════════════════════════════════════════
  [1948] = true, [1949] = true, [1950] = true, [1951] = true,
  [1952] = true, [1953] = true, [1954] = true, [1955] = true,
  [1977] = true, [1978] = true, [1979] = true, [1980] = true,
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- RAMPS (Standard)
  -- ═══════════════════════════════════════════════════════════════════════
  [1956] = true, [1957] = true, [1958] = true, [1959] = true,
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- RAMPS (Stone/Cave)
  -- ═══════════════════════════════════════════════════════════════════════
  [1385] = true, [1396] = true, [1397] = true, [1398] = true,
  [1399] = true, [1400] = true, [1401] = true, [1402] = true,
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- RAMPS (Terrain - Grass/Dirt)
  -- ═══════════════════════════════════════════════════════════════════════
  [4834] = true, [4835] = true, [4836] = true, [4837] = true,
  [4838] = true, [4839] = true, [4840] = true, [4841] = true,
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- RAMPS (Ice)
  -- ═══════════════════════════════════════════════════════════════════════
  [6915] = true, [6916] = true, [6917] = true, [6918] = true,
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- RAMPS (Desert/Jungle)
  -- ═══════════════════════════════════════════════════════════════════════
  [7545] = true, [7546] = true, [7547] = true, [7548] = true,
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- LADDERS
  -- ═══════════════════════════════════════════════════════════════════════
  [1219] = true,  -- Standard ladder
  [1386] = true,  -- Cave ladder
  [3678] = true,  -- Ship ladder
  [5543] = true,  -- Broken ladder
  [8599] = true,  -- Modern ladder
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- ROPE SPOTS
  -- ═══════════════════════════════════════════════════════════════════════
  [384] = true,   -- Standard rope spot
  [386] = true,   -- Cave rope spot
  [418] = true,   -- Alternate rope spot
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- HOLES AND PITFALLS
  -- ═══════════════════════════════════════════════════════════════════════
  [294] = true,   -- Pitfall
  [369] = true,   -- Hole
  [370] = true,   -- Hole variant
  [383] = true,   -- Cave hole
  [392] = true,   -- Dungeon hole
  [408] = true,   -- Dark hole
  [409] = true,   -- Hole variant
  [410] = true,   -- Hole variant
  [469] = true,   -- Stone hole
  [470] = true,   -- Stone hole variant
  [482] = true,   -- Large hole
  [484] = true,   -- Large hole variant
  [595] = true,   -- Sewer hole
  [596] = true,   -- Sewer hole variant
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- TRAPDOORS
  -- ═══════════════════════════════════════════════════════════════════════
  [423] = true,   -- Trapdoor closed
  [424] = true,   -- Trapdoor open
  [425] = true,   -- Trapdoor variant
  [426] = true,   -- Stone trapdoor
  [427] = true,   -- Stone trapdoor variant
  [428] = true,   -- Wooden trapdoor
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- SEWER GRATES
  -- ═══════════════════════════════════════════════════════════════════════
  [426] = true,
  [427] = true,
  [435] = true,
  [594] = true,
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- TELEPORTS
  -- ═══════════════════════════════════════════════════════════════════════
  [502] = true,   -- Magic teleport
  [1387] = true,  -- Portal
  [2129] = true,  -- Teleport pad
  [2130] = true,  -- Teleport pad variant
  [8709] = true,  -- Modern teleport
  [1949] = true,  -- Temple teleport
  [1958] = true,  -- City teleport
}

-- ============================================================================
-- FIELD ITEMS (Fire, Energy, Poison, Magic Walls)
-- ============================================================================

FloorItems.FIELDS = {
  -- ═══════════════════════════════════════════════════════════════════════
  -- FIRE FIELDS (multiple visual states)
  -- ═══════════════════════════════════════════════════════════════════════
  [1487] = "fire", [1488] = "fire", [1489] = "fire", [1490] = "fire",
  [1491] = "fire", [1492] = "fire", [1493] = "fire", [1494] = "fire",
  [1495] = "fire", [1496] = "fire", [1497] = "fire", [1498] = "fire",
  [1499] = "fire", [1500] = "fire", [1501] = "fire", [1502] = "fire",
  [1503] = "fire", [1504] = "fire", [1505] = "fire", [1506] = "fire",
  [2120] = "fire", [2121] = "fire", [2122] = "fire", [2123] = "fire",
  [2124] = "fire", [2125] = "fire", [2126] = "fire", [2127] = "fire",
  [2128] = "fire",
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- ENERGY FIELDS
  -- ═══════════════════════════════════════════════════════════════════════
  [7487] = "energy", [7488] = "energy", [7489] = "energy", [7490] = "energy",
  [8069] = "energy", [8070] = "energy", [8071] = "energy", [8072] = "energy",
  [1510] = "energy", [1511] = "energy", [1512] = "energy", [1513] = "energy",
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- POISON FIELDS
  -- ═══════════════════════════════════════════════════════════════════════
  [7465] = "poison", [7466] = "poison", [7467] = "poison", [7468] = "poison",
  [1490] = "poison", [1496] = "poison", [1503] = "poison",
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- MAGIC WALLS / WILD GROWTH
  -- ═══════════════════════════════════════════════════════════════════════
  [2129] = "wall", [2130] = "wall",
  [7491] = "wall", [7492] = "wall", [7493] = "wall", [7494] = "wall",
  [2131] = "wildgrowth", [2132] = "wildgrowth",
}

-- Simple boolean lookup for fields (backwards compatibility)
FloorItems.FIELD_ITEMS = {}
for id, _ in pairs(FloorItems.FIELDS) do
  FloorItems.FIELD_ITEMS[id] = true
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
  Check if item ID is a floor-change item
  @param itemId number
  @return boolean
]]
function FloorItems.isFloorChange(itemId)
  return FloorItems.FLOOR_CHANGE[itemId] == true
end

-- Floor-change item subtypes for auto-use actions
FloorItems.LADDER_IDS = {
  [1219] = true, [1386] = true, [3678] = true, [5543] = true, [8599] = true,
}
FloorItems.ROPE_SPOT_IDS = {
  [384] = true, [386] = true, [418] = true,
}
FloorItems.HOLE_IDS = {
  [294] = true, [369] = true, [370] = true, [383] = true,
  [392] = true, [408] = true, [409] = true, [410] = true,
  [469] = true, [470] = true, [482] = true, [484] = true,
  [595] = true, [596] = true,
}

function FloorItems.isLadder(itemId)
  return FloorItems.LADDER_IDS[itemId] == true
end

function FloorItems.isRopeSpot(itemId)
  return FloorItems.ROPE_SPOT_IDS[itemId] == true
end

function FloorItems.isHole(itemId)
  return FloorItems.HOLE_IDS[itemId] == true
end

--[[
  Check if minimap color indicates floor change
  @param color number
  @return boolean
]]
function FloorItems.isFloorChangeColor(color)
  return FloorItems.FLOOR_CHANGE_COLORS[color] == true
end

--[[
  Get expected floor after stepping on a floor-change tile.
  @param color number minimap color of the tile
  @param baseZ number the Z coordinate of the tile
  @return number expected Z after floor change, or baseZ if unknown
]]
function FloorItems.getExpectedFloor(color, baseZ)
  if color == 210 or color == 211 or color == 214 or color == 215 then return baseZ - 1 end
  if color == 212 or color == 213 or color == 216 or color == 217 then return baseZ + 1 end
  return baseZ
end

--[[
  Check if item ID is a field
  @param itemId number
  @return boolean
]]
function FloorItems.isField(itemId)
  return FloorItems.FIELD_ITEMS[itemId] == true
end

--[[
  Get field type for item ID
  @param itemId number
  @return string ("fire", "energy", "poison", "wall", "wildgrowth") or nil
]]
function FloorItems.getFieldType(itemId)
  return FloorItems.FIELDS[itemId]
end

--[[
  Check if position has floor-change tile.
  Minimap color is authoritative for explored tiles (color > 0).
  Item inspection is only used for unexplored tiles (color == 0).
  @param pos Position
  @return boolean
]]
function FloorItems.isFloorChangeTile(pos)
  if not pos then return false end

  local cache = getFcCache()
  if cache then
    local key = makeFcKey(pos)
    local cached = cache:get(key)
    if cached ~= nil then return cached end
  end

  local map = g_map
  if not (map and map.getMinimapColor) then return false end
  local color = map.getMinimapColor(pos)

  -- Explored tile: minimap color is authoritative
  if color > 0 then
    local result = FloorItems.FLOOR_CHANGE_COLORS[color] == true
    if cache then cache:set(makeFcKey(pos), result) end
    return result
  end

  -- Unexplored tile (color 0): fall back to item inspection
  local tile = map.getTile and map.getTile(pos)
  if tile then
    local ground = tile:getGround()
    if ground and FloorItems.FLOOR_CHANGE[ground:getId()] then
      if cache then cache:set(makeFcKey(pos), true) end
      return true
    end
    local topThing = tile:getTopThing()
    if topThing and topThing.isItem and topThing:isItem() and FloorItems.FLOOR_CHANGE[topThing:getId()] then
      if cache then cache:set(makeFcKey(pos), true) end
      return true
    end
  end

  if cache then cache:set(makeFcKey(pos), false) end
  return false
end

--[[
  Check if position has a field tile
  @param pos Position
  @return boolean, string (hasField, fieldType)
]]
function FloorItems.hasField(pos)
  if not pos then return false, nil end
  
  local map = g_map
  local tile = map and map.getTile and map.getTile(pos)
  if not tile then return false, nil end
  
  local ground = tile:getGround()
  if ground then
    local fieldType = FloorItems.FIELDS[ground:getId()]
    if fieldType then
      return true, fieldType
    end
  end
  
  local items = tile:getItems()
  if items then
    for _, item in ipairs(items) do
      local fieldType = FloorItems.FIELDS[item:getId()]
      if fieldType then
        return true, fieldType
      end
    end
  end
  
  return false, nil
end

FloorItems._loaded = true
return FloorItems
