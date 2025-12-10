--[[
  BotCore: Position Module
  
  High-performance position and tile utility functions.
  Consolidates position operations from lib.lua and CaveBot.
  
  Features:
    - Position creation and conversion
    - Near tile utilities
    - Path/distance calculations
    - Tile analysis
]]

local Position = {}
BotCore.Position = Position

-- ============================================================================
-- PRE-COMPUTED DATA
-- ============================================================================

-- Direction offsets for adjacent tiles (8 directions)
local NEAR_TILE_DIRS = {
  {-1, 1}, {0, 1}, {1, 1},   -- SW, S, SE
  {-1, 0}, {1, 0},            -- W, E
  {-1, -1}, {0, -1}, {1, -1}  -- NW, N, NE
}
local NEAR_TILE_COUNT = 8

-- Cardinal direction offsets (4 directions)
local CARDINAL_DIRS = {
  {0, -1},  -- N
  {1, 0},   -- E
  {0, 1},   -- S
  {-1, 0}   -- W
}

-- Reusable position table
local tempPos = {x = 0, y = 0, z = 0}

-- ============================================================================
-- POSITION CREATION
-- ============================================================================

-- Create a position table from coordinates
-- @param x: x coordinate
-- @param y: y coordinate
-- @param z: z coordinate
-- @return position table or nil
function Position.create(x, y, z)
  if not x or not y or not z then return nil end
  
  local p = pos()
  p.x = x
  p.y = y
  p.z = z
  return p
end

-- Get player position
-- @return position table
function Position.player()
  return player:getPosition()
end

-- Get player position coordinates
-- @return x, y, z
function Position.playerXYZ()
  local p = Position.player()
  return p.x, p.y, p.z
end

-- ============================================================================
-- DISTANCE CALCULATIONS
-- ============================================================================

-- Get distance between two positions (Chebyshev - max of dx, dy)
-- @param pos1: first position
-- @param pos2: second position
-- @return number
function Position.distance(pos1, pos2)
  return getDistanceBetween(pos1, pos2)
end

-- Get distance from player to position
-- @param targetPos: target position
-- @return number or false
function Position.distanceFromPlayer(targetPos)
  if not targetPos then return false end
  return getDistanceBetween(pos(), targetPos)
end

-- Get Manhattan distance (dx + dy)
-- @param pos1: first position
-- @param pos2: second position
-- @return number
function Position.manhattan(pos1, pos2)
  return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

-- Get Euclidean distance (sqrt(dx² + dy²))
-- @param pos1: first position
-- @param pos2: second position
-- @return number
function Position.euclidean(pos1, pos2)
  local dx = pos1.x - pos2.x
  local dy = pos1.y - pos2.y
  return math.sqrt(dx * dx + dy * dy)
end

-- ============================================================================
-- TILE UTILITIES
-- ============================================================================

-- Get tiles adjacent to a position (8 directions)
-- @param centerPos: center position or creature
-- @return array of tiles
function Position.getNearTiles(centerPos)
  if type(centerPos) ~= "table" then
    centerPos = centerPos:getPosition()
  end
  
  local tiles = {}
  local count = 0
  local baseX, baseY, baseZ = centerPos.x, centerPos.y, centerPos.z
  
  for i = 1, NEAR_TILE_COUNT do
    local dir = NEAR_TILE_DIRS[i]
    tempPos.x = baseX - dir[1]
    tempPos.y = baseY - dir[2]
    tempPos.z = baseZ
    
    local tile = g_map.getTile(tempPos)
    if tile then
      count = count + 1
      tiles[count] = tile
    end
  end
  
  return tiles
end

-- Get cardinal tiles (4 directions)
-- @param centerPos: center position
-- @return array of tiles
function Position.getCardinalTiles(centerPos)
  if type(centerPos) ~= "table" then
    centerPos = centerPos:getPosition()
  end
  
  local tiles = {}
  local count = 0
  local baseX, baseY, baseZ = centerPos.x, centerPos.y, centerPos.z
  
  for i = 1, 4 do
    local dir = CARDINAL_DIRS[i]
    tempPos.x = baseX + dir[1]
    tempPos.y = baseY + dir[2]
    tempPos.z = baseZ
    
    local tile = g_map.getTile(tempPos)
    if tile then
      count = count + 1
      tiles[count] = tile
    end
  end
  
  return tiles
end

-- Get tile at position
-- @param posOrXYZ: position table or x coordinate
-- @param y: y coordinate (if first arg is x)
-- @param z: z coordinate (if first arg is x)
-- @return tile or nil
function Position.getTile(posOrXYZ, y, z)
  if type(posOrXYZ) == "number" then
    tempPos.x = posOrXYZ
    tempPos.y = y
    tempPos.z = z
    return g_map.getTile(tempPos)
  end
  return g_map.getTile(posOrXYZ)
end

-- ============================================================================
-- TILE ANALYSIS
-- ============================================================================

-- Check if tile is walkable
-- @param tile: tile object
-- @return boolean
function Position.isWalkable(tile)
  if not tile then return false end
  return tile:isWalkable()
end

-- Check if tile can be shot through (line of sight)
-- @param tile: tile object
-- @return boolean
function Position.canShoot(tile)
  if not tile then return false end
  return tile:canShoot()
end

-- Check if position is stairs (based on minimap color)
-- @param tileOrPos: tile or position
-- @return boolean
function Position.isStairs(tileOrPos)
  local tilePos
  if type(tileOrPos) == "table" and tileOrPos.x then
    tilePos = tileOrPos
  elseif tileOrPos.getPosition then
    tilePos = tileOrPos:getPosition()
  else
    return false
  end
  
  local color = g_map.getMinimapColor(tilePos)
  return color >= 210 and color <= 213
end

-- ============================================================================
-- BEST TILE FINDING
-- ============================================================================

-- Find best tile for area spell/rune by creature count
-- @param pattern: pattern string
-- @param creatureType: 1=all, 2=monsters, 3=players
-- @param maxDist: maximum distance from player
-- @param safe: if true, avoid tiles with players
-- @return {pos, count} or false
function Position.getBestTileByPattern(pattern, creatureType, maxDist, safe)
  if not pattern or not creatureType then return false end
  maxDist = maxDist or 4
  
  local best = nil
  local getCreaturesInArea = BotCore.Creatures and BotCore.Creatures.getInArea or getCreaturesInArea
  
  for _, tile in pairs(g_map.getTiles(posz())) do
    local tilePos = tile:getPosition()
    
    if Position.distanceFromPlayer(tilePos) <= maxDist then
      if not Position.isStairs(tilePos) and tile:canShoot() and tile:isWalkable() then
        local count = getCreaturesInArea(tilePos, pattern, creatureType)
        
        if count > 0 then
          -- Check safety (no players in area)
          if not safe or getCreaturesInArea(tilePos, pattern, 3) == 0 then
            if not best or count > best.count then
              best = {pos = tile, count = count}
            end
          end
        end
      end
    end
  end
  
  return best or false
end

-- ============================================================================
-- PATH UTILITIES
-- ============================================================================

-- Check if path exists to target
-- @param targetPos: target position
-- @param maxNodes: max path nodes (default 20)
-- @param options: pathfinding options
-- @return boolean
function Position.canReach(targetPos, maxNodes, options)
  maxNodes = maxNodes or 20
  options = options or {ignoreNonPathable = true, precision = 1}
  
  local path = findPath(pos(), targetPos, maxNodes, options)
  return path ~= nil and #path > 0
end

-- Get path to target
-- @param targetPos: target position
-- @param maxNodes: max path nodes (default 20)
-- @param options: pathfinding options
-- @return path array or nil
function Position.getPath(targetPos, maxNodes, options)
  maxNodes = maxNodes or 20
  options = options or {ignoreNonPathable = true, precision = 1}
  
  return findPath(pos(), targetPos, maxNodes, options)
end

-- ============================================================================
-- POSITION COMPARISON
-- ============================================================================

-- Check if two positions are equal
-- @param pos1: first position
-- @param pos2: second position
-- @return boolean
function Position.equals(pos1, pos2)
  if not pos1 or not pos2 then return false end
  return pos1.x == pos2.x and pos1.y == pos2.y and pos1.z == pos2.z
end

-- Check if position is on same floor as player
-- @param targetPos: position to check
-- @return boolean
function Position.isSameFloor(targetPos)
  return targetPos and targetPos.z == posz()
end

-- Check if player is in protection zone
-- @return boolean
function Position.isInPz()
  return isInPz()
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

if logInfo then
  logInfo("[BotCore] Position module loaded")
end

return Position
