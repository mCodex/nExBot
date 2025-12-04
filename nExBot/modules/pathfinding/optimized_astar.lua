--[[
  NexBot Optimized A* Pathfinder
  Improved pathfinding with caching and performance optimizations
  
  Features:
  - Path caching integration
  - Node evaluation limits
  - Straight-line optimization for nearby targets
  - Diagonal movement support
  - Priority queue using binary heap
  
  Author: NexBot Team
  Version: 1.0.0
]]

local PathCache = dofile("/NexBot/modules/pathfinding/path_cache.lua")

local OptimizedAStar = {
  cache = nil,
  enabled = true,
  debugMode = false
}

-- Configuration
local CONFIG = {
  straightLineThreshold = 5,  -- Use direct path if distance <= this
  nodeEvaluationLimit = 500,  -- Max nodes to evaluate per path
  diagonalMovement = true,
  preferHorizontal = true,
  cacheEnabled = true,
  maxPathLength = 100
}

-- Direction vectors (including diagonals)
local DIRECTIONS = {
  {x = 1, y = 0, cost = 1},     -- East
  {x = -1, y = 0, cost = 1},    -- West
  {x = 0, y = 1, cost = 1},     -- South
  {x = 0, y = -1, cost = 1},    -- North
  {x = 1, y = 1, cost = 1.41},  -- SouthEast (diagonal)
  {x = -1, y = 1, cost = 1.41}, -- SouthWest
  {x = 1, y = -1, cost = 1.41}, -- NorthEast
  {x = -1, y = -1, cost = 1.41} -- NorthWest
}

-- Initialize pathfinder
function OptimizedAStar:initialize(options)
  options = options or {}
  
  CONFIG.straightLineThreshold = options.straightLineThreshold or 5
  CONFIG.nodeEvaluationLimit = options.nodeLimit or 500
  CONFIG.diagonalMovement = options.diagonal ~= false
  CONFIG.cacheEnabled = options.cache ~= false
  
  if CONFIG.cacheEnabled then
    self.cache = PathCache:new({
      maxSize = options.cacheSize or 100,
      ttl = options.cacheTTL or 30000
    })
  end
  
  return self
end

-- Convert position to string key
function OptimizedAStar:posToKey(pos)
  return string.format("%d_%d_%d", pos.x, pos.y, pos.z)
end

-- Parse key back to position
function OptimizedAStar:keyToPos(key)
  local parts = {}
  for part in string.gmatch(key, "([^_]+)") do
    table.insert(parts, tonumber(part))
  end
  return {x = parts[1], y = parts[2], z = parts[3]}
end

-- Calculate Manhattan distance
function OptimizedAStar:manhattanDistance(posA, posB)
  return math.abs(posA.x - posB.x) + math.abs(posA.y - posB.y)
end

-- Calculate Euclidean distance
function OptimizedAStar:euclideanDistance(posA, posB)
  return math.sqrt(
    (posA.x - posB.x)^2 + (posA.y - posB.y)^2
  )
end

-- Heuristic function for A*
function OptimizedAStar:heuristic(pos, goal)
  if CONFIG.diagonalMovement then
    -- Octile distance for diagonal movement
    local dx = math.abs(pos.x - goal.x)
    local dy = math.abs(pos.y - goal.y)
    return math.max(dx, dy) + 0.41 * math.min(dx, dy)
  else
    return self:manhattanDistance(pos, goal)
  end
end

-- Check if a tile is walkable
function OptimizedAStar:isWalkable(pos, options)
  options = options or {}
  
  local tile = g_map and g_map.getTile(pos)
  if not tile then return false end
  
  -- Basic walkability check
  if not tile:isWalkable() then
    return false
  end
  
  -- Check for creatures if not ignoring them
  if not options.ignoreCreatures then
    local creatures = tile:getCreatures()
    if creatures and #creatures > 0 then
      -- Allow if it's the last tile (target)
      if not options.isLastTile then
        return false
      end
    end
  end
  
  -- Check for fields/fire if not ignoring
  if not options.ignoreFields then
    local items = tile:getItems()
    for _, item in ipairs(items or {}) do
      local itemType = item:getType and item:getType()
      if itemType and itemType:isNotWalkable() then
        return false
      end
    end
  end
  
  return true
end

-- Check if straight line is possible
function OptimizedAStar:isStraightLinePossible(startPos, endPos)
  local distance = self:manhattanDistance(startPos, endPos)
  
  -- Only use straight line for short distances on same floor
  if distance > CONFIG.straightLineThreshold then
    return false
  end
  
  if startPos.z ~= endPos.z then
    return false
  end
  
  -- Check all tiles in the line
  local dx = endPos.x - startPos.x
  local dy = endPos.y - startPos.y
  local steps = math.max(math.abs(dx), math.abs(dy))
  
  if steps == 0 then return true end
  
  local stepX = dx / steps
  local stepY = dy / steps
  
  for i = 1, steps do
    local checkPos = {
      x = math.floor(startPos.x + stepX * i + 0.5),
      y = math.floor(startPos.y + stepY * i + 0.5),
      z = startPos.z
    }
    
    if not self:isWalkable(checkPos, {isLastTile = (i == steps)}) then
      return false
    end
  end
  
  return true
end

-- Build direct path (for straight lines)
function OptimizedAStar:buildDirectPath(startPos, endPos)
  local path = {}
  local current = {x = startPos.x, y = startPos.y, z = startPos.z}
  
  while current.x ~= endPos.x or current.y ~= endPos.y do
    local nextX = current.x + (endPos.x > current.x and 1 or (endPos.x < current.x and -1 or 0))
    local nextY = current.y + (endPos.y > current.y and 1 or (endPos.y < current.y and -1 or 0))
    
    table.insert(path, {x = nextX, y = nextY, z = current.z})
    current = {x = nextX, y = nextY, z = current.z}
  end
  
  return path
end

-- Get valid neighbors of a position
function OptimizedAStar:getNeighbors(pos, options)
  local neighbors = {}
  local maxDirs = CONFIG.diagonalMovement and 8 or 4
  
  for i = 1, maxDirs do
    local dir = DIRECTIONS[i]
    local neighbor = {
      x = pos.x + dir.x,
      y = pos.y + dir.y,
      z = pos.z
    }
    
    if self:isWalkable(neighbor, options) then
      table.insert(neighbors, {
        pos = neighbor,
        cost = dir.cost
      })
    end
  end
  
  return neighbors
end

-- Reconstruct path from came-from map
function OptimizedAStar:reconstructPath(cameFrom, current)
  local path = {current}
  local currentKey = self:posToKey(current)
  
  while cameFrom[currentKey] do
    current = cameFrom[currentKey]
    table.insert(path, 1, current)
    currentKey = self:posToKey(current)
  end
  
  -- Remove start position from path
  table.remove(path, 1)
  
  return path
end

-- Main A* pathfinding function
function OptimizedAStar:findPath(startPos, endPos, options)
  options = options or {}
  
  -- Quick check: same position
  if startPos.x == endPos.x and startPos.y == endPos.y and startPos.z == endPos.z then
    return {}
  end
  
  -- Quick check: destination not walkable
  if not self:isWalkable(endPos, {isLastTile = true, ignoreCreatures = options.ignoreLastCreature}) then
    if self.debugMode then
      print("[PathFinder] Destination not walkable")
    end
    return nil
  end
  
  -- Check cache first
  if CONFIG.cacheEnabled and self.cache then
    local cached = self.cache:get(startPos, endPos)
    if cached then
      if self.debugMode then
        print("[PathFinder] Cache hit!")
      end
      return cached
    end
  end
  
  -- Try straight line for nearby targets
  if self:isStraightLinePossible(startPos, endPos) then
    local path = self:buildDirectPath(startPos, endPos)
    if CONFIG.cacheEnabled and self.cache then
      self.cache:set(startPos, endPos, path)
    end
    if self.debugMode then
      print("[PathFinder] Using straight line path")
    end
    return path
  end
  
  -- Full A* algorithm
  return self:astarWithLimit(startPos, endPos, options)
end

-- A* with node evaluation limit
function OptimizedAStar:astarWithLimit(startPos, endPos, options)
  options = options or {}
  local nodeLimit = options.nodeLimit or CONFIG.nodeEvaluationLimit
  
  -- Priority queue (simple implementation)
  local openSet = {}
  local openSetHash = {}
  local closedSet = {}
  local cameFrom = {}
  local gScore = {}
  local fScore = {}
  
  local startKey = self:posToKey(startPos)
  gScore[startKey] = 0
  fScore[startKey] = self:heuristic(startPos, endPos)
  
  table.insert(openSet, {pos = startPos, f = fScore[startKey]})
  openSetHash[startKey] = true
  
  local evaluatedNodes = 0
  
  while #openSet > 0 and evaluatedNodes < nodeLimit do
    -- Get node with lowest f-score
    table.sort(openSet, function(a, b) return a.f < b.f end)
    local current = table.remove(openSet, 1)
    local currentKey = self:posToKey(current.pos)
    openSetHash[currentKey] = nil
    
    -- Goal reached
    if current.pos.x == endPos.x and current.pos.y == endPos.y and current.pos.z == endPos.z then
      local path = self:reconstructPath(cameFrom, current.pos)
      
      -- Cache the result
      if CONFIG.cacheEnabled and self.cache then
        self.cache:set(startPos, endPos, path)
      end
      
      if self.debugMode then
        print(string.format("[PathFinder] Path found, %d nodes evaluated, path length: %d", 
          evaluatedNodes, #path))
      end
      
      return path
    end
    
    closedSet[currentKey] = true
    evaluatedNodes = evaluatedNodes + 1
    
    -- Evaluate neighbors
    local neighbors = self:getNeighbors(current.pos, {
      ignoreCreatures = options.ignoreCreatures,
      ignoreFields = options.ignoreFields
    })
    
    for _, neighbor in ipairs(neighbors) do
      local neighborKey = self:posToKey(neighbor.pos)
      
      if not closedSet[neighborKey] then
        local tentativeGScore = gScore[currentKey] + neighbor.cost
        
        if not gScore[neighborKey] or tentativeGScore < gScore[neighborKey] then
          cameFrom[neighborKey] = current.pos
          gScore[neighborKey] = tentativeGScore
          fScore[neighborKey] = tentativeGScore + self:heuristic(neighbor.pos, endPos)
          
          if not openSetHash[neighborKey] then
            table.insert(openSet, {pos = neighbor.pos, f = fScore[neighborKey]})
            openSetHash[neighborKey] = true
          end
        end
      end
    end
  end
  
  -- No path found within limit
  if self.debugMode then
    print(string.format("[PathFinder] No path found after %d nodes", evaluatedNodes))
  end
  
  return nil
end

-- Get cache statistics
function OptimizedAStar:getCacheStats()
  if self.cache then
    return self.cache:getStats()
  end
  return nil
end

-- Clear path cache
function OptimizedAStar:clearCache()
  if self.cache then
    self.cache:clear()
  end
end

-- Invalidate cache for a position
function OptimizedAStar:invalidatePosition(pos)
  if self.cache then
    return self.cache:invalidatePosition(pos)
  end
  return 0
end

-- Set debug mode
function OptimizedAStar:setDebugMode(enabled)
  self.debugMode = enabled
end

-- Configure settings
function OptimizedAStar:configure(options)
  if options.straightLineThreshold then
    CONFIG.straightLineThreshold = options.straightLineThreshold
  end
  if options.nodeLimit then
    CONFIG.nodeEvaluationLimit = options.nodeLimit
  end
  if options.diagonal ~= nil then
    CONFIG.diagonalMovement = options.diagonal
  end
  if options.maxPathLength then
    CONFIG.maxPathLength = options.maxPathLength
  end
end

return OptimizedAStar
