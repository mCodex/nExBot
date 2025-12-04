--[[
  NexBot Distance Calculator
  DRY implementation - centralized distance calculations
  Eliminates duplicate distance code across modules
  
  Author: NexBot Team
  Version: 1.0.0
]]

local DistanceCalculator = {}

-- Calculate Euclidean distance between two positions
-- @param pos1 table - First position {x, y, z}
-- @param pos2 table - Second position {x, y, z}
-- @return number - Euclidean distance
function DistanceCalculator:euclidean(pos1, pos2)
  if not pos1 or not pos2 then return math.huge end
  
  return math.sqrt(
    math.pow(pos1.x - pos2.x, 2) +
    math.pow(pos1.y - pos2.y, 2)
  )
end

-- Calculate Manhattan distance between two positions
-- @param pos1 table - First position
-- @param pos2 table - Second position
-- @return number - Manhattan distance
function DistanceCalculator:manhattan(pos1, pos2)
  if not pos1 or not pos2 then return math.huge end
  
  return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

-- Calculate Chebyshev distance (max of x/y difference)
-- Used for tile-based games where diagonal movement is allowed
-- @param pos1 table - First position
-- @param pos2 table - Second position
-- @return number - Chebyshev distance
function DistanceCalculator:chebyshev(pos1, pos2)
  if not pos1 or not pos2 then return math.huge end
  
  return math.max(
    math.abs(pos1.x - pos2.x),
    math.abs(pos1.y - pos2.y)
  )
end

-- Calculate distance from player to a target
-- @param target - Creature or position
-- @return number - Distance from player
function DistanceCalculator:fromPlayer(target)
  if not player then return math.huge end
  
  local playerPos = player:getPosition()
  local targetPos
  
  if type(target) == "table" and target.x then
    targetPos = target
  elseif target and target.getPosition then
    targetPos = target:getPosition()
  else
    return math.huge
  end
  
  return self:euclidean(playerPos, targetPos)
end

-- Check if a target is within range of player
-- @param target - Creature or position
-- @param range number - Maximum distance
-- @return boolean
function DistanceCalculator:isInRange(target, range)
  return self:fromPlayer(target) <= range
end

-- Check if a target is within a 3D range (including floor difference)
-- @param pos1 table - First position
-- @param pos2 table - Second position
-- @param horizontalRange number - Max horizontal distance
-- @param verticalRange number - Max floor difference
-- @return boolean
function DistanceCalculator:isInRange3D(pos1, pos2, horizontalRange, verticalRange)
  if not pos1 or not pos2 then return false end
  
  verticalRange = verticalRange or 0
  
  if math.abs(pos1.z - pos2.z) > verticalRange then
    return false
  end
  
  return self:euclidean(pos1, pos2) <= horizontalRange
end

-- Find the closest creature from a list
-- @param creatures table - List of creatures
-- @param fromPos table (optional) - Position to measure from (defaults to player)
-- @return creature, distance - Closest creature and its distance
function DistanceCalculator:findClosest(creatures, fromPos)
  if not creatures or #creatures == 0 then
    return nil, math.huge
  end
  
  fromPos = fromPos or (player and player:getPosition())
  if not fromPos then return nil, math.huge end
  
  local closest = nil
  local minDist = math.huge
  
  for _, creature in ipairs(creatures) do
    local creaturePos = creature:getPosition()
    local dist = self:euclidean(fromPos, creaturePos)
    
    if dist < minDist then
      minDist = dist
      closest = creature
    end
  end
  
  return closest, minDist
end

-- Find all creatures within a range
-- @param creatures table - List of creatures
-- @param range number - Maximum distance
-- @param fromPos table (optional) - Position to measure from
-- @return table - List of creatures within range
function DistanceCalculator:findInRange(creatures, range, fromPos)
  if not creatures then return {} end
  
  fromPos = fromPos or (player and player:getPosition())
  if not fromPos then return {} end
  
  local result = {}
  
  for _, creature in ipairs(creatures) do
    local creaturePos = creature:getPosition()
    if self:euclidean(fromPos, creaturePos) <= range then
      table.insert(result, creature)
    end
  end
  
  return result
end

-- Sort creatures by distance from a position
-- @param creatures table - List of creatures
-- @param fromPos table (optional) - Position to measure from
-- @return table - Sorted list (closest first)
function DistanceCalculator:sortByDistance(creatures, fromPos)
  if not creatures then return {} end
  
  fromPos = fromPos or (player and player:getPosition())
  if not fromPos then return creatures end
  
  local sorted = {}
  for _, creature in ipairs(creatures) do
    table.insert(sorted, creature)
  end
  
  local self_ref = self
  table.sort(sorted, function(a, b)
    return self_ref:euclidean(fromPos, a:getPosition()) < self_ref:euclidean(fromPos, b:getPosition())
  end)
  
  return sorted
end

-- Get direction from one position to another
-- @param from table - Source position
-- @param to table - Target position
-- @return number - Direction constant (North=0, East=1, South=2, West=3)
function DistanceCalculator:getDirection(from, to)
  if not from or not to then return nil end
  
  local dx = to.x - from.x
  local dy = to.y - from.y
  
  if math.abs(dx) > math.abs(dy) then
    return dx > 0 and 1 or 3  -- East or West
  else
    return dy > 0 and 2 or 0  -- South or North
  end
end

-- Get direction name
-- @param direction number - Direction constant
-- @return string - Direction name
function DistanceCalculator:getDirectionName(direction)
  local names = {"North", "East", "South", "West", "NorthEast", "SouthEast", "SouthWest", "NorthWest"}
  return names[direction + 1] or "Unknown"
end

-- Calculate path distance (number of steps needed)
-- @param from table - Source position
-- @param to table - Target position
-- @param allowDiagonal boolean - Whether diagonal movement is allowed
-- @return number - Number of steps
function DistanceCalculator:pathDistance(from, to, allowDiagonal)
  if not from or not to then return math.huge end
  
  if allowDiagonal then
    return self:chebyshev(from, to)
  else
    return self:manhattan(from, to)
  end
end

return DistanceCalculator
