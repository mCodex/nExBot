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

-- ============================================================================
-- MINIMAP COLORS FOR FLOOR CHANGE
-- ============================================================================

FloorItems.FLOOR_CHANGE_COLORS = {
  [210] = true,  -- Stairs up
  [211] = true,  -- Stairs down  
  [212] = true,  -- Rope spot
  [213] = true,  -- Ladder
}

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

--[[
  Check if minimap color indicates floor change
  @param color number
  @return boolean
]]
function FloorItems.isFloorChangeColor(color)
  return FloorItems.FLOOR_CHANGE_COLORS[color] == true
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
  Check if position has floor-change tile
  Uses minimap color first (fast), then tile inspection (slow)
  @param pos Position
  @return boolean
]]
function FloorItems.isFloorChangeTile(pos)
  if not pos then return false end
  
  -- Fast path: minimap color
  local map = g_map
  if map and map.getMinimapColor then
    local color = map.getMinimapColor(pos)
    if FloorItems.FLOOR_CHANGE_COLORS[color] then
      return true
    end
  end
  
  -- Slow path: tile inspection
  local tile = map and map.getTile and map.getTile(pos)
  if tile then
    local ground = tile:getGround()
    if ground and FloorItems.FLOOR_CHANGE[ground:getId()] then
      return true
    end
    local topThing = tile:getTopThing()
    if topThing and topThing.isItem and topThing:isItem() and FloorItems.FLOOR_CHANGE[topThing:getId()] then
      return true
    end
  end
  
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

return FloorItems
