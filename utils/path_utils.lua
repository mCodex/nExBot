--[[
  PathUtils v2.0.0 - Shared Pathfinding Utilities
  Simplified: no LRU cache, no negative cache, no findEveryPath, no creature utils.
]]

PathUtils = PathUtils or {}
local PathUtils = PathUtils

local _getClient

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

PathUtils.DIR_TO_OFFSET = Directions.DIR_TO_OFFSET
PathUtils.OFFSET_TO_DIR = Directions.OFFSET_TO_DIR
PathUtils.CARDINAL_DIRS = Directions.CARDINAL
PathUtils.DIAGONAL_DIRS = Directions.DIAGONAL
PathUtils.ALL_DIRS = Directions.ALL

PathUtils.Flags = {
  ALLOW_NOT_SEEN = 1,
  ALLOW_CREATURES = 2,
  ALLOW_NON_PATHABLE = 4,
  ALLOW_NON_WALKABLE = 8,
  IGNORE_CREATURES = 16
}

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

local FloorItems = (function()
  local ok, fi = pcall(dofile, "/constants/floor_items.lua")
  if ok and fi then return fi end
  ok, fi = pcall(dofile, "/core/constants/floor_items.lua")
  if ok and fi then return fi end
  return nil
end)()

PathUtils.FLOOR_CHANGE_COLORS = (FloorItems and FloorItems.FLOOR_CHANGE_COLORS) or {
  [210] = true, [211] = true, [212] = true, [213] = true
}

PathUtils.FLOOR_CHANGE_ITEMS = (FloorItems and FloorItems.FLOOR_CHANGE) or {}

PathUtils.FIELD_ITEMS = (FloorItems and FloorItems.FIELD_ITEMS) or {}

function PathUtils.isFloorChangeTile(pos)
  if not pos then return false end
  local map = getMap()
  if not (map and map.getMinimapColor) then return false end
  local color = map.getMinimapColor(pos)

  -- Explored tile: minimap color is authoritative
  if color > 0 then
    return PathUtils.FLOOR_CHANGE_COLORS[color] == true
  end

  -- Unexplored tile (color 0): fall back to item inspection
  local tile = map.getTile and map.getTile(pos)
  if tile then
    local ground = tile:getGround()
    if ground and PathUtils.FLOOR_CHANGE_ITEMS[ground:getId()] then return true end
    local topThing = tile:getTopThing()
    if topThing and topThing:isItem() and PathUtils.FLOOR_CHANGE_ITEMS[topThing:getId()] then return true end
  end
  return false
end

function PathUtils.isFieldTile(pos)
  if not pos then return false end
  local map = getMap()
  local tile = map and map.getTile and map.getTile(pos)
  if not tile then return false end
  local ground = tile:getGround()
  if ground and PathUtils.FIELD_ITEMS[ground:getId()] then return true end
  local items = tile:getItems()
  if items then
    for _, item in ipairs(items) do
      if PathUtils.FIELD_ITEMS[item:getId()] then return true end
    end
  end
  return false
end

function PathUtils.getTile(pos)
  if not pos then return nil end
  local map = getMap()
  return map and map.getTile and map.getTile(pos)
end

function PathUtils.isTileWalkable(pos, ignoreCreatures)
  local tile = PathUtils.getTile(pos)
  if not tile then return false end
  return tile:isWalkable(ignoreCreatures or false)
end

function PathUtils.isTilePathable(pos)
  local tile = PathUtils.getTile(pos)
  if not tile then return false end
  return tile.isPathable and tile:isPathable() or tile:isWalkable()
end

function PathUtils.getTileSpeed(pos)
  local tile = PathUtils.getTile(pos)
  if not tile then return 150 end
  return tile.getGroundSpeed and tile:getGroundSpeed() or 150
end

function PathUtils.tileHasCreature(pos)
  local tile = PathUtils.getTile(pos)
  if not tile then return false end
  if tile.hasCreature then return tile:hasCreature() end
  if tile.getCreatureCount then return tile:getCreatureCount() > 0 end
  return false
end

function PathUtils.isTileSafe(pos, allowFloorChange)
  if not PathUtils.isTileWalkable(pos, false) then return false end
  if PathUtils.tileHasCreature(pos) then return false end
  if not allowFloorChange and PathUtils.isFloorChangeTile(pos) then return false end
  return true
end

function PathUtils.findPath(startPos, goalPos, maxDist, params)
  if not startPos or not goalPos then return nil end
  if startPos.z ~= goalPos.z then return nil end
  maxDist = maxDist or 50
  local flags = PathUtils.paramsToFlags(params)
  local map = getMap()
  if not map or not map.findPath then return nil end
  local directions, result = map.findPath(startPos, goalPos, maxDist, flags)
  if result == 0 and directions and #directions > 0 then
    return directions
  end
  return nil
end

function PathUtils.isAutoWalking()
  local player = getPlayer()
  if not player then return false end
  return player.isAutoWalking and player:isAutoWalking() or false
end

function PathUtils.stopAutoWalk()
  local player = getPlayer()
  if not player then return end
  if player.stopAutoWalk then player:stopAutoWalk() end
  local game = getGame()
  if game and game.stop then game.stop() end
end

function PathUtils.isWalking()
  local player = getPlayer()
  if not player then return false end
  local isStep = player.isWalking and player:isWalking() or false
  local isAuto = player.isAutoWalking and player:isAutoWalking() or false
  return isStep or isAuto
end

function PathUtils.getStepDuration(diagonal)
  local player = getPlayer()
  if not player then return 150 end
  local dir = diagonal and (NorthEast or 4) or (North or 0)
  return player.getStepDuration and player:getStepDuration(false, dir) or 150
end

function PathUtils.canWalk(dir)
  local player = getPlayer()
  if not player then return false end
  return player.canWalk and player:canWalk(dir) or true
end

local ADJACENT_DIRS = Directions.ADJACENT
local OPPOSITE_DIRS = Directions.OPPOSITE

function PathUtils.areSimilarDirections(dir1, dir2)
  if dir1 == nil or dir2 == nil then return true end
  if dir1 == dir2 then return true end
  return ADJACENT_DIRS[dir1] and ADJACENT_DIRS[dir1][dir2] or false
end

function PathUtils.areOppositeDirections(dir1, dir2)
  if dir1 == nil or dir2 == nil then return false end
  return OPPOSITE_DIRS[dir1] == dir2
end

PathUtils.getDirectionTo = Directions.getDirectionTo
PathUtils.chebyshevDistance = Directions.chebyshevDistance
PathUtils.manhattanDistance = Directions.manhattanDistance

function PathUtils.applyDirection(pos, dir)
  if not pos or not dir then return nil end
  local offset = PathUtils.DIR_TO_OFFSET[dir]
  if not offset then return nil end
  return {x = pos.x + offset.x, y = pos.y + offset.y, z = pos.z}
end

function PathUtils.posEquals(pos1, pos2)
  if not pos1 or not pos2 then return false end
  return pos1.x == pos2.x and pos1.y == pos2.y and pos1.z == pos2.z
end

function PathUtils.sameFloor(pos1, pos2)
  if not pos1 or not pos2 then return false end
  return pos1.z == pos2.z
end

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

return PathUtils
