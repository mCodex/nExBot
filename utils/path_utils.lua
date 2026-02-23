--[[
  PathUtils v1.0.0 - Shared Pathfinding Utilities
  
  DESIGN PRINCIPLES:
  - SRP: Single responsibility per function
  - DRY: Shared across CaveBot and TargetBot
  - KISS: Simple, efficient implementations
  - Native API First: Use OTClientBR APIs when available
  
  OTClientBR Native API Reference:
  - g_map.findPath(start, goal, maxComplexity, flags) - returns {directions}, result
  - g_map.findEveryPath(start, maxDistance, params) - returns all reachable tiles
  - g_map.getSpectatorsInRangeEx(pos, multiFloor, minX, maxX, minY, maxY)
  - player:isAutoWalking() - check if auto-walking
  - player:stopAutoWalk() - cancel auto-walk
  - player:getStepDuration(ignoreDiagonal, dir) - get step timing
  - player:canWalk(dir) - check if direction is walkable
  - tile:isWalkable(ignoreCreatures) - native walkability with creature ignore
  - tile:isPathable() - check pathability
  - tile:getGroundSpeed() - get ground speed
  
  PathFind Flags (Otc::PathFindFlags):
  - PathFindAllowNotSeenTiles = 1
  - PathFindAllowCreatures = 2
  - PathFindAllowNonPathable = 4
  - PathFindAllowNonWalkable = 8
  - PathFindIgnoreCreatures = 16
]]

PathUtils = PathUtils or {}
local PathUtils = PathUtils  -- local alias for speed

-- ============================================================================
-- CLIENT SERVICE ABSTRACTION (ACL Pattern)
-- Resolved lazily so Phase 3 load order doesn't require nExBot.Shared yet
-- ============================================================================

local _getClient  -- resolved once on first call

local function getClient()
  if _getClient then return _getClient() end
  if nExBot and nExBot.Shared and nExBot.Shared.getClient then
    _getClient = nExBot.Shared.getClient
    return _getClient()
  end
  return nil
end

local function getGame()
  local Client = getClient()
  return (Client and Client.g_game) or g_game
end

local function getMap()
  local Client = getClient()
  return (Client and Client.g_map) or g_map
end

local function getPlayer()
  local Client = getClient()
  return (Client and Client.getLocalPlayer and Client.getLocalPlayer()) 
      or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
end

-- ============================================================================
-- DIRECTION CONSTANTS (Shared, no duplication)
-- ============================================================================

-- Delegate to Directions module (DRY: SSoT is constants/directions.lua)
PathUtils.DIR_TO_OFFSET = Directions.DIR_TO_OFFSET

PathUtils.OFFSET_TO_DIR = Directions.OFFSET_TO_DIR

PathUtils.CARDINAL_DIRS = Directions.CARDINAL
PathUtils.DIAGONAL_DIRS = Directions.DIAGONAL
PathUtils.ALL_DIRS = Directions.ALL

-- ============================================================================
-- PATHFIND FLAGS (Native OTClientBR constants)
-- ============================================================================

PathUtils.Flags = {
  ALLOW_NOT_SEEN = 1,
  ALLOW_CREATURES = 2,
  ALLOW_NON_PATHABLE = 4,
  ALLOW_NON_WALKABLE = 8,
  IGNORE_CREATURES = 16
}

-- Convert params table to native flags integer (PERFORMANCE: single integer vs table)
function PathUtils.paramsToFlags(params)
  if not params then return 0 end
  local flags = 0
  
  if params.allowUnseen or params.allowNotSeenTiles then
    flags = flags + PathUtils.Flags.ALLOW_NOT_SEEN
  end
  if params.allowCreatures then
    flags = flags + PathUtils.Flags.ALLOW_CREATURES
  end
  if params.ignoreNonPathable or params.allowNonPathable then
    flags = flags + PathUtils.Flags.ALLOW_NON_PATHABLE
  end
  if params.ignoreNonWalkable or params.allowNonWalkable then
    flags = flags + PathUtils.Flags.ALLOW_NON_WALKABLE
  end
  if params.ignoreCreatures then
    flags = flags + PathUtils.Flags.IGNORE_CREATURES
  end
  
  return flags
end

-- ============================================================================
-- FLOOR-CHANGE DETECTION (Using constants/floor_items.lua as single source)
-- ============================================================================

-- Load FloorItems constants if available
local FloorItems = (function()
  local ok, fi = pcall(dofile, "/constants/floor_items.lua")
  if ok and fi then return fi end
  ok, fi = pcall(dofile, "/core/constants/floor_items.lua")
  if ok and fi then return fi end
  return nil
end)()

-- Minimap colors for floor-change (using constants or fallback)
PathUtils.FLOOR_CHANGE_COLORS = (FloorItems and FloorItems.FLOOR_CHANGE_COLORS) or {
  [210] = true, [211] = true, [212] = true, [213] = true
}

-- Comprehensive floor-change item IDs (using constants or fallback)
PathUtils.FLOOR_CHANGE_ITEMS = (FloorItems and FloorItems.FLOOR_CHANGE) or {
  -- Stairs (stone)
  [414] = true, [415] = true, [416] = true, [417] = true,
  [428] = true, [429] = true, [430] = true, [431] = true,
  [432] = true, [433] = true, [434] = true, [435] = true,
  -- Stairs (wooden)
  [1949] = true, [1950] = true, [1951] = true,
  [1952] = true, [1953] = true, [1954] = true, [1955] = true,
  -- Ramps (standard)
  [1956] = true, [1957] = true, [1958] = true, [1959] = true,
  -- Ramps (stone/cave)
  [1385] = true, [1396] = true, [1397] = true, [1398] = true,
  [1399] = true, [1400] = true, [1401] = true, [1402] = true,
  -- Ramps (terrain)
  [4834] = true, [4835] = true, [4836] = true, [4837] = true,
  [4838] = true, [4839] = true, [4840] = true, [4841] = true,
  -- Ramps (ice)
  [6915] = true, [6916] = true, [6917] = true, [6918] = true,
  -- Ramps (desert/jungle)
  [7545] = true, [7546] = true, [7547] = true, [7548] = true,
  -- Ladders
  [1219] = true, [1386] = true, [3678] = true, [5543] = true,
  -- Rope spots
  [384] = true, [386] = true, [418] = true,
  -- Holes and pitfalls
  [294] = true, [369] = true, [370] = true, [383] = true,
  [392] = true, [408] = true, [409] = true, [410] = true,
  [469] = true, [470] = true, [482] = true, [484] = true,
  -- Trapdoors
  [423] = true, [424] = true, [425] = true,
  -- Sewer grates
  [426] = true, [427] = true,
  -- Teleports
  [502] = true, [1387] = true,
  [2129] = true, [2130] = true, [8709] = true,
}

-- Field item IDs (using constants or fallback)
PathUtils.FIELD_ITEMS = (FloorItems and FloorItems.FIELDS) or {
  -- Fire Fields
  [1487] = true, [1488] = true, [1489] = true, [1490] = true, [1491] = true,
  [1492] = true, [1493] = true, [1494] = true, [1495] = true, [1496] = true,
  [1497] = true, [1498] = true, [1499] = true, [1500] = true, [1501] = true,
  [1502] = true, [1503] = true, [1504] = true, [1505] = true, [1506] = true,
  [2120] = true, [2121] = true, [2122] = true, [2123] = true, [2124] = true,
  [2125] = true, [2126] = true, [2127] = true, [2128] = true,
  -- Energy Fields  
  [7487] = true, [7488] = true, [7489] = true, [7490] = true,
  [8069] = true, [8070] = true, [8071] = true, [8072] = true,
  -- Poison Fields
  [7465] = true, [7466] = true, [7467] = true, [7468] = true,
  -- Magic Walls
  [2128] = true, [2129] = true, [2130] = true,
  [7491] = true, [7492] = true, [7493] = true, [7494] = true,
  -- Wild Growth
  [2130] = true, [2131] = true,
}

-- Floor-change tile cache (per-entry TTL to avoid cold-cache burst)
local floorChangeCache = {}
local CACHE_TTL = 2000
local CACHE_CLEANUP_INTERVAL = 5000
local lastCacheCleanup = 0

-- Pure: Check if position is floor-change tile (cached with per-entry TTL)
-- Uses integer key: x*100000+y*100+z — zero allocation vs string concat
function PathUtils.isFloorChangeTile(pos)
  if not pos then return false end
  
  -- Periodic cleanup of expired entries (avoids unbounded growth)
  if now - lastCacheCleanup > CACHE_CLEANUP_INTERVAL then
    local cutoff = now - CACHE_TTL
    for k, v in pairs(floorChangeCache) do
      if v.time < cutoff then
        floorChangeCache[k] = nil
      end
    end
    lastCacheCleanup = now
  end
  
  local key = pos.x * 100000 + pos.y * 100 + pos.z
  local cached = floorChangeCache[key]
  if cached and now - cached.time < CACHE_TTL then
    return cached.value
  end
  
  -- Fast path: minimap color
  local map = getMap()
  local color = map and map.getMinimapColor and map.getMinimapColor(pos) or 0
  if PathUtils.FLOOR_CHANGE_COLORS[color] then
    floorChangeCache[key] = {value = true, time = now}
    return true
  end
  
  -- Slow path: tile inspection
  local result = false
  local tile = map and map.getTile and map.getTile(pos)
  if tile then
    local ground = tile:getGround()
    if ground and PathUtils.FLOOR_CHANGE_ITEMS[ground:getId()] then
      result = true
    else
      local topThing = tile:getTopThing()
      if topThing and topThing:isItem() and PathUtils.FLOOR_CHANGE_ITEMS[topThing:getId()] then
        result = true
      end
    end
  end
  
  floorChangeCache[key] = {value = result, time = now}
  return result
end

-- Pure: Check if position has a field
function PathUtils.isFieldTile(pos)
  if not pos then return false end
  local map = getMap()
  local tile = map and map.getTile and map.getTile(pos)
  if not tile then return false end
  
  local ground = tile:getGround()
  if ground and PathUtils.FIELD_ITEMS[ground:getId()] then
    return true
  end
  
  local items = tile:getItems()
  if items then
    for _, item in ipairs(items) do
      if PathUtils.FIELD_ITEMS[item:getId()] then
        return true
      end
    end
  end
  
  return false
end

-- ============================================================================
-- TILE UTILITIES (Native API wrappers)
-- ============================================================================

-- Get tile with fallback
function PathUtils.getTile(pos)
  if not pos then return nil end
  local map = getMap()
  return map and map.getTile and map.getTile(pos)
end

-- Check if tile is walkable (uses native ignoreCreatures flag)
function PathUtils.isTileWalkable(pos, ignoreCreatures)
  local tile = PathUtils.getTile(pos)
  if not tile then return false end
  return tile:isWalkable(ignoreCreatures or false)
end

-- Check if tile is pathable (native API)
function PathUtils.isTilePathable(pos)
  local tile = PathUtils.getTile(pos)
  if not tile then return false end
  return tile.isPathable and tile:isPathable() or tile:isWalkable()
end

-- Get tile ground speed (native API)
function PathUtils.getTileSpeed(pos)
  local tile = PathUtils.getTile(pos)
  if not tile then return 150 end
  return tile.getGroundSpeed and tile:getGroundSpeed() or 150
end

-- Check if tile has creatures
function PathUtils.tileHasCreature(pos)
  local tile = PathUtils.getTile(pos)
  if not tile then return false end
  return tile.hasCreature and tile:hasCreature() or tile:getCreatureCount() > 0
end

-- Check if tile is safe (walkable, no floor change, no field)
function PathUtils.isTileSafe(pos, allowFloorChange)
  if not PathUtils.isTileWalkable(pos, false) then return false end
  if PathUtils.tileHasCreature(pos) then return false end
  if not allowFloorChange and PathUtils.isFloorChangeTile(pos) then return false end
  return true
end

-- ============================================================================
-- PATHFINDING (Native API with fallback)
-- ============================================================================

-- 1-entry LRU cache for findPath (avoids redundant A* on rapid retries)
-- 4-entry LRU cache for findPath: walking loop typically alternates 2-3 queries
-- (recovery probe + goto path + FC safety check). 4 entries avoid redundant A*.
local FINDPATH_LRU_SIZE = 4
local FINDPATH_CACHE_TTL = 200
local _fpLRU = {}       -- array of {key, time, result}, newest at [1]
local _fpLRUCount = 0

-- Negative result cache: remembers unreachable destinations to avoid repeated A* waste.
-- Key: "startX,startY,startZ>goalX,goalY,goalZ:flags", value: expiry timestamp.
local _fpNegCache = {}
local FINDPATH_NEG_TTL = 500   -- 500ms before retrying an unreachable destination
local FINDPATH_NEG_MAX = 32    -- max entries to prevent unbounded growth
local _fpNegCount = 0

-- Find path using native g_map.findPath with flags
function PathUtils.findPath(startPos, goalPos, maxDist, params)
  if not startPos or not goalPos then return nil end
  if startPos.z ~= goalPos.z then return nil end
  
  maxDist = maxDist or 50
  local flags = PathUtils.paramsToFlags(params)
  
  -- 4-entry LRU: same start+goal+flags within TTL → reuse
  local key = startPos.x .. "," .. startPos.y .. "," .. startPos.z .. ">"
            .. goalPos.x .. "," .. goalPos.y .. "," .. goalPos.z .. ":" .. flags
  for i = 1, _fpLRUCount do
    local entry = _fpLRU[i]
    if entry.key == key and now - entry.time < FINDPATH_CACHE_TTL then
      -- Move to front (promote on hit)
      if i > 1 then
        for j = i, 2, -1 do _fpLRU[j] = _fpLRU[j - 1] end
        _fpLRU[1] = entry
      end
      return entry.result
    end
  end

  -- Negative cache: skip A* if we recently proved this dest unreachable
  local negExpiry = _fpNegCache[key]
  if negExpiry and now < negExpiry then
    return nil
  end
  
  local map = getMap()
  if not map or not map.findPath then return nil end
  
  -- Native API call (returns {directions}, result)
  local directions, result = map.findPath(startPos, goalPos, maxDist, flags)
  
  -- Result codes: 0=OK, 1=SamePosition, 2=Impossible, 3=TooFar, 4=NoWay
  local ret = nil
  if result == 0 and directions and #directions > 0 then
    ret = directions
    -- Clear negative cache on success
    if _fpNegCache[key] then
      _fpNegCache[key] = nil
      _fpNegCount = _fpNegCount - 1
    end
  else
    -- Cache negative result
    if not _fpNegCache[key] then
      _fpNegCount = _fpNegCount + 1
      -- Evict oldest entries if over limit
      if _fpNegCount > FINDPATH_NEG_MAX then
        local oldest_key, oldest_time = nil, math.huge
        for k, v in pairs(_fpNegCache) do
          if v < oldest_time then
            oldest_key, oldest_time = k, v
          end
        end
        if oldest_key then
          _fpNegCache[oldest_key] = nil
          _fpNegCount = _fpNegCount - 1
        end
      end
    end
    _fpNegCache[key] = now + FINDPATH_NEG_TTL
  end
  
  -- Insert at front of LRU
  local newEntry = {key = key, time = now, result = ret}
  if _fpLRUCount < FINDPATH_LRU_SIZE then
    _fpLRUCount = _fpLRUCount + 1
    for j = _fpLRUCount, 2, -1 do _fpLRU[j] = _fpLRU[j - 1] end
  else
    for j = FINDPATH_LRU_SIZE, 2, -1 do _fpLRU[j] = _fpLRU[j - 1] end
  end
  _fpLRU[1] = newEntry
  return ret
end

-- Find all reachable tiles within distance (native findEveryPath)
function PathUtils.findEveryPath(startPos, maxDist, params)
  if not startPos then return nil end
  
  local map = getMap()
  if not map or not map.findEveryPath then return nil end
  
  -- Convert params for native API
  local nativeParams = {}
  if params then
    if params.ignoreCreatures then nativeParams.ignoreCreatures = "1" end
    if params.ignoreLastCreature then nativeParams.ignoreLastCreature = "1" end
    if params.ignoreNonPathable then nativeParams.ignoreNonPathable = "1" end
    if params.ignoreNonWalkable then nativeParams.ignoreNonWalkable = "1" end
    if params.ignoreStairs then nativeParams.ignoreStairs = "1" end
    if params.ignoreCost then nativeParams.ignoreCost = "1" end
    if params.allowUnseen then nativeParams.allowUnseen = "1" end
    if params.allowOnlyVisibleTiles then nativeParams.allowOnlyVisibleTiles = "1" end
  end
  
  return map.findEveryPath(startPos, maxDist or 10, nativeParams)
end

-- Translate findEveryPath result to a path of directions
function PathUtils.translatePathToDirections(paths, destPosStr)
  if not paths or not destPosStr then return nil end
  
  local predirections = {}
  local currentPos = destPosStr
  
  while currentPos and currentPos:len() > 0 do
    local node = paths[currentPos]
    if not node then break end
    if node[3] < 0 then break end
    table.insert(predirections, node[3])
    currentPos = node[4]
  end
  
  -- Reverse the path
  local directions = {}
  for i = #predirections, 1, -1 do
    table.insert(directions, predirections[i])
  end
  
  return directions
end

-- ============================================================================
-- AUTO-WALK STATE MANAGEMENT (Native API)
-- ============================================================================

-- Check if player is currently auto-walking (native API)
function PathUtils.isAutoWalking()
  local player = getPlayer()
  if not player then return false end
  return player.isAutoWalking and player:isAutoWalking() or false
end

-- Stop current auto-walk (native API)
function PathUtils.stopAutoWalk()
  local player = getPlayer()
  if not player then return end
  if player.stopAutoWalk then
    player:stopAutoWalk()
  end
  -- Also stop via game if available
  local game = getGame()
  if game and game.stop then
    game.stop()
  end
end

-- Check if player is walking (single step or auto)
function PathUtils.isWalking()
  local player = getPlayer()
  if not player then return false end
  local isStep = player.isWalking and player:isWalking() or false
  local isAuto = player.isAutoWalking and player:isAutoWalking() or false
  return isStep or isAuto
end

-- Get step duration (native API with caching)
local stepDurationCache = {speed = 0, cardinal = 0, diagonal = 0, time = 0}

function PathUtils.getStepDuration(diagonal)
  local player = getPlayer()
  if not player then return 150 end
  
  local speed = player.getSpeed and player:getSpeed() or 220
  
  -- Cache hit
  if speed == stepDurationCache.speed and now - stepDurationCache.time < 1000 then
    return diagonal and stepDurationCache.diagonal or stepDurationCache.cardinal
  end
  
  -- Calculate using native API
  local dir = diagonal and NorthEast or North
  local duration = player.getStepDuration and player:getStepDuration(false, dir) or 150
  
  -- Update cache
  stepDurationCache.speed = speed
  stepDurationCache.time = now
  if diagonal then
    stepDurationCache.diagonal = duration
  else
    stepDurationCache.cardinal = duration
  end
  
  return duration
end

-- Check if player can walk in direction (native API)
function PathUtils.canWalk(dir)
  local player = getPlayer()
  if not player then return false end
  return player.canWalk and player:canWalk(dir) or true
end

-- ============================================================================
-- DIRECTION UTILITIES
-- ============================================================================

-- Pre-built lookup tables for direction checks (DRY: SSoT is constants/directions.lua)
local ADJACENT_DIRS = Directions.ADJACENT
local OPPOSITE_DIRS = Directions.OPPOSITE

-- Check if two directions are similar (same or adjacent)
function PathUtils.areSimilarDirections(dir1, dir2)
  if dir1 == nil or dir2 == nil then return true end
  if dir1 == dir2 then return true end
  return ADJACENT_DIRS[dir1] and ADJACENT_DIRS[dir1][dir2] or false
end

-- Check if direction is opposite (causes zigzag)
function PathUtils.areOppositeDirections(dir1, dir2)
  if dir1 == nil or dir2 == nil then return false end
  return OPPOSITE_DIRS[dir1] == dir2
end

-- ============================================================================
-- POSITION UTILITIES
-- ============================================================================

-- Get direction from one position to another
function PathUtils.getDirectionTo(fromPos, toPos)
  if not fromPos or not toPos then return nil end
  
  local dx = toPos.x - fromPos.x
  local dy = toPos.y - fromPos.y
  
  local nx = dx == 0 and 0 or (dx > 0 and 1 or -1)
  local ny = dy == 0 and 0 or (dy > 0 and 1 or -1)
  
  local key = nx .. "," .. ny
  return PathUtils.OFFSET_TO_DIR[key]
end

-- Apply direction offset to position
function PathUtils.applyDirection(pos, dir)
  if not pos or not dir then return nil end
  local offset = PathUtils.DIR_TO_OFFSET[dir]
  if not offset then return nil end
  return {x = pos.x + offset.x, y = pos.y + offset.y, z = pos.z}
end

-- Calculate Chebyshev distance (diagonal allowed)
function PathUtils.chebyshevDistance(pos1, pos2)
  if not pos1 or not pos2 then return 999 end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

-- Calculate Manhattan distance (no diagonal)
function PathUtils.manhattanDistance(pos1, pos2)
  if not pos1 or not pos2 then return 999 end
  return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

-- Check if positions are equal
function PathUtils.posEquals(pos1, pos2)
  if not pos1 or not pos2 then return false end
  return pos1.x == pos2.x and pos1.y == pos2.y and pos1.z == pos2.z
end

-- Check if positions are on same floor
function PathUtils.sameFloor(pos1, pos2)
  if not pos1 or not pos2 then return false end
  return pos1.z == pos2.z
end

-- ============================================================================
-- CREATURE UTILITIES (Optimized with single validation)
-- ============================================================================

-- Validate creature in one call (reduces pcall overhead)
function PathUtils.validateCreature(creature)
  if not creature then
    return false, nil, nil, nil
  end
  
  local ok, result = pcall(function()
    local isDead = creature:isDead()
    local id = creature:getId()
    local pos = creature:getPosition()
    local hp = creature:getHealthPercent()
    return {dead = isDead, id = id, pos = pos, hp = hp}
  end)
  
  if not ok or not result then
    return false, nil, nil, nil
  end
  
  if result.dead then
    return false, result.id, result.pos, result.hp
  end
  
  return true, result.id, result.pos, result.hp
end

-- Check if creature is a valid monster target
function PathUtils.isValidMonsterTarget(creature)
  if not creature then return false end
  
  local ok, valid = pcall(function()
    if creature:isDead() then return false end
    if not creature:isMonster() then return false end
    -- Type 3+ = summons (not targetable)
    local ctype = creature.getType and creature:getType() or 0
    if ctype >= 3 then return false end
    return true
  end)
  
  return ok and valid
end

-- ============================================================================
-- SPECTATOR UTILITIES (Native API)
-- ============================================================================

-- Get spectators with asymmetric range (native API)
function PathUtils.getSpectatorsEx(centerPos, multiFloor, minX, maxX, minY, maxY)
  local map = getMap()
  if not map then return {} end
  
  if map.getSpectatorsInRangeEx then
    return map.getSpectatorsInRangeEx(centerPos, multiFloor, minX, maxX, minY, maxY)
  elseif map.getSpectatorsInRange then
    local range = math.max(math.abs(minX), math.abs(maxX), math.abs(minY), math.abs(maxY))
    return map.getSpectatorsInRange(centerPos, multiFloor, range, range)
  end
  
  return {}
end

-- Get spectators in symmetric range
function PathUtils.getSpectators(centerPos, range, multiFloor)
  local map = getMap()
  if not map then return {} end
  
  range = range or 7
  multiFloor = multiFloor or false
  
  if map.getSpectatorsInRange then
    return map.getSpectatorsInRange(centerPos, multiFloor, range, range)
  elseif map.getSpectators then
    return map.getSpectators(centerPos, multiFloor)
  end
  
  return {}
end

-- ============================================================================
-- MODULE EXPORT
-- ============================================================================

-- PathUtils is already global (declared at top of file)
return PathUtils
