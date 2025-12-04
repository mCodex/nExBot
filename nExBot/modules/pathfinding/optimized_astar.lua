--[[
  ============================================================================
  nExBot Optimized A* Pathfinder
  ============================================================================
  
  High-performance pathfinding using the A* algorithm with several
  optimizations for game bot use cases.
  
  ALGORITHM OVERVIEW (A*):
  A* finds the shortest path by combining:
  - g(n): Actual cost from start to current node
  - h(n): Estimated cost from current to goal (heuristic)
  - f(n) = g(n) + h(n): Total estimated cost
  
  It always expands the node with lowest f(n), guaranteeing optimal paths
  when using an admissible heuristic.
  
  OPTIMIZATIONS IMPLEMENTED:
  1. Path Caching: Reuses recent paths (huge performance win for repeated routes)
  2. Straight-Line Detection: Skips A* for obvious direct paths
  3. Node Evaluation Limit: Prevents infinite loops in complex maps
  4. Octile Heuristic: Better estimate for 8-directional movement
  5. Hash Table Lookups: O(1) closed set checks
  6. Local Function Caching: Faster global lookups
  
  USAGE:
    local AStar = dofile("path/to/optimized_astar.lua")
    AStar:initialize({
      diagonal = true,
      nodeLimit = 500,
      cache = true
    })
    
    local path = AStar:findPath(startPos, endPos)
    if path then
      for _, step in ipairs(path) do
        -- walk to step
      end
    end
  
  Author: nExBot Team
  Version: 2.0.0 (Optimized)
  Last Updated: December 2025
  
  ============================================================================
]]

--[[
  ============================================================================
  LOCAL CACHING FOR PERFORMANCE
  ============================================================================
  Cache frequently used functions to avoid global lookups in hot paths.
  The pathfinding algorithm calls these functions thousands of times per path.
  ============================================================================
]]
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort
local math_abs = math.abs
local math_sqrt = math.sqrt
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local string_format = string.format
local string_gmatch = string.gmatch
local ipairs = ipairs
local tonumber = tonumber

--[[
  ============================================================================
  PATH CACHE INTEGRATION
  ============================================================================
]]
local PathCache = dofile("/nExBot/modules/pathfinding/path_cache.lua")

--[[
  ============================================================================
  PATHFINDER CLASS DEFINITION
  ============================================================================
]]

local OptimizedAStar = {
  cache = nil,       -- PathCache instance
  enabled = true,    -- Master enable switch
  debugMode = false  -- Verbose logging
}

--[[
  ============================================================================
  CONFIGURATION
  ============================================================================
  These values balance performance vs. path quality.
  Adjust based on your server's map complexity.
  ============================================================================
]]
local CONFIG = {
  -- Distance threshold for straight-line optimization
  -- If target is within this range, try direct path first
  straightLineThreshold = 5,
  
  -- Maximum nodes to evaluate before giving up
  -- Prevents infinite loops in complex or blocked areas
  nodeEvaluationLimit = 500,
  
  -- Enable 8-directional movement (diagonal)
  -- Set false for 4-directional (cardinal only) servers
  diagonalMovement = true,
  
  -- Prefer horizontal/vertical over diagonal when costs are equal
  preferHorizontal = true,
  
  -- Enable path caching for repeated routes
  cacheEnabled = true,
  
  -- Maximum path length to return
  maxPathLength = 100
}

--[[
  ============================================================================
  DIRECTION VECTORS
  ============================================================================
  Defines possible movement directions with their associated costs.
  Diagonal movement uses ~1.41 (sqrt(2)) to reflect actual distance.
  
  Order matters: Cardinal directions first for preferHorizontal behavior.
  ============================================================================
]]
local DIRECTIONS = {
  -- Cardinal directions (cost = 1)
  {x = 1, y = 0, cost = 1},      -- East
  {x = -1, y = 0, cost = 1},     -- West
  {x = 0, y = 1, cost = 1},      -- South
  {x = 0, y = -1, cost = 1},     -- North
  -- Diagonal directions (cost = sqrt(2) ≈ 1.41)
  {x = 1, y = 1, cost = 1.41},   -- SouthEast
  {x = -1, y = 1, cost = 1.41},  -- SouthWest
  {x = 1, y = -1, cost = 1.41},  -- NorthEast
  {x = -1, y = -1, cost = 1.41}  -- NorthWest
}

-- Cached direction count for loops
local CARDINAL_COUNT = 4
local DIAGONAL_COUNT = 8

--[[
  ============================================================================
  INITIALIZATION
  ============================================================================
]]

--- Initializes the pathfinder with configuration options
-- 
-- @param options (table|nil) Configuration options:
--   - straightLineThreshold: Distance for direct path optimization
--   - nodeLimit: Max nodes to evaluate
--   - diagonal: Enable diagonal movement (default: true)
--   - cache: Enable path caching (default: true)
--   - cacheSize: Maximum cached paths
--   - cacheTTL: Cache time-to-live in ms
-- @return self for chaining
function OptimizedAStar:initialize(options)
  options = options or {}
  
  CONFIG.straightLineThreshold = options.straightLineThreshold or 5
  CONFIG.nodeEvaluationLimit = options.nodeLimit or 500
  CONFIG.diagonalMovement = options.diagonal ~= false
  CONFIG.cacheEnabled = options.cache ~= false
  
  -- Initialize path cache if enabled
  if CONFIG.cacheEnabled then
    self.cache = PathCache:new({
      maxSize = options.cacheSize or 100,
      ttl = options.cacheTTL or 30000
    })
  end
  
  return self
end

--[[
  ============================================================================
  POSITION UTILITIES
  ============================================================================
]]

--- Converts a position table to a unique string key
-- Used for hash table lookups (O(1) instead of table scan)
-- 
-- @param pos (table) Position with x, y, z
-- @return (string) Unique key like "100_200_7"
function OptimizedAStar:posToKey(pos)
  return string_format("%d_%d_%d", pos.x, pos.y, pos.z)
end

--- Parses a key string back to a position table
-- @param key (string) Key from posToKey()
-- @return (table) Position with x, y, z
function OptimizedAStar:keyToPos(key)
  local parts = {}
  for part in string_gmatch(key, "([^_]+)") do
    parts[#parts + 1] = tonumber(part)
  end
  return {x = parts[1], y = parts[2], z = parts[3]}
end

--[[
  ============================================================================
  DISTANCE & HEURISTIC FUNCTIONS
  ============================================================================
]]

--- Calculates Manhattan distance (grid distance without diagonals)
-- Used for 4-directional heuristic
-- 
-- @param posA (table) First position
-- @param posB (table) Second position
-- @return (number) Manhattan distance
function OptimizedAStar:manhattanDistance(posA, posB)
  return math_abs(posA.x - posB.x) + math_abs(posA.y - posB.y)
end

--- Calculates Euclidean distance (straight-line)
-- @param posA (table) First position
-- @param posB (table) Second position
-- @return (number) Euclidean distance
function OptimizedAStar:euclideanDistance(posA, posB)
  local dx = posA.x - posB.x
  local dy = posA.y - posB.y
  return math_sqrt(dx * dx + dy * dy)
end

--- A* heuristic function
-- Estimates cost from current position to goal.
-- Uses Octile distance for diagonal movement (more accurate than Manhattan).
-- 
-- OCTILE FORMULA:
-- max(dx, dy) + 0.41 * min(dx, dy)
-- The 0.41 comes from (sqrt(2) - 1) ≈ 0.414
-- 
-- @param pos (table) Current position
-- @param goal (table) Goal position
-- @return (number) Estimated cost
function OptimizedAStar:heuristic(pos, goal)
  local dx = math_abs(pos.x - goal.x)
  local dy = math_abs(pos.y - goal.y)
  
  if CONFIG.diagonalMovement then
    -- Octile distance: better for 8-directional
    return math_max(dx, dy) + 0.41 * math_min(dx, dy)
  else
    -- Manhattan distance: correct for 4-directional
    return dx + dy
  end
end

--[[
  ============================================================================
  WALKABILITY CHECKS
  ============================================================================
]]

--- Checks if a tile is walkable
-- Considers tile properties, creatures, and field effects
-- 
-- @param pos (table) Position to check
-- @param options (table|nil) Check options:
--   - ignoreCreatures: Don't consider creatures blocking
--   - ignoreFields: Don't consider fire/energy fields
--   - isLastTile: Allow creatures on destination tile
-- @return (boolean) True if walkable
function OptimizedAStar:isWalkable(pos, options)
  options = options or {}
  
  -- Get tile from game map
  local tile = g_map and g_map.getTile(pos)
  if not tile then return false end
  
  -- Basic walkability from tile flags
  if not tile:isWalkable() then
    return false
  end
  
  -- ========================================
  -- CREATURE CHECK
  -- ========================================
  if not options.ignoreCreatures then
    local creatures = tile:getCreatures()
    if creatures and #creatures > 0 then
      -- Allow creatures on destination (we want to reach it)
      if not options.isLastTile then
        return false
      end
    end
  end
  
  -- ========================================
  -- FIELD EFFECT CHECK
  -- ========================================
  if not options.ignoreFields then
    local items = tile:getItems()
    if items then
      for i = 1, #items do
        local item = items[i]
        local itemType = item.getType and item:getType()
        if itemType and itemType:isNotWalkable() then
          return false
        end
      end
    end
  end
  
  return true
end

--[[
  ============================================================================
  STRAIGHT-LINE OPTIMIZATION
  ============================================================================
  For nearby targets on the same floor, check if direct path is possible.
  Much faster than full A* when there are no obstacles.
  ============================================================================
]]

--- Checks if a straight line path is possible
-- @param startPos (table) Starting position
-- @param endPos (table) Ending position
-- @return (boolean) True if direct path is clear
function OptimizedAStar:isStraightLinePossible(startPos, endPos)
  -- Must be on same floor
  if startPos.z ~= endPos.z then
    return false
  end
  
  local distance = self:manhattanDistance(startPos, endPos)
  
  -- Only for short distances
  if distance > CONFIG.straightLineThreshold then
    return false
  end
  
  -- Check all tiles along the line
  local dx = endPos.x - startPos.x
  local dy = endPos.y - startPos.y
  local steps = math_max(math_abs(dx), math_abs(dy))
  
  if steps == 0 then return true end
  
  local stepX = dx / steps
  local stepY = dy / steps
  
  for i = 1, steps do
    local checkPos = {
      x = math_floor(startPos.x + stepX * i + 0.5),
      y = math_floor(startPos.y + stepY * i + 0.5),
      z = startPos.z
    }
    
    if not self:isWalkable(checkPos, {isLastTile = (i == steps)}) then
      return false
    end
  end
  
  return true
end

--- Builds a direct path without A*
-- @param startPos (table) Starting position
-- @param endPos (table) Ending position
-- @return (table) Array of positions
function OptimizedAStar:buildDirectPath(startPos, endPos)
  local path = {}
  local current = {x = startPos.x, y = startPos.y, z = startPos.z}
  
  while current.x ~= endPos.x or current.y ~= endPos.y do
    -- Calculate next step (move towards goal)
    local nextX = current.x
    local nextY = current.y
    
    if endPos.x > current.x then
      nextX = nextX + 1
    elseif endPos.x < current.x then
      nextX = nextX - 1
    end
    
    if endPos.y > current.y then
      nextY = nextY + 1
    elseif endPos.y < current.y then
      nextY = nextY - 1
    end
    
    table_insert(path, {x = nextX, y = nextY, z = current.z})
    current = {x = nextX, y = nextY, z = current.z}
  end
  
  return path
end

--[[
  ============================================================================
  NEIGHBOR GENERATION
  ============================================================================
]]

--- Gets valid walkable neighbors of a position
-- @param pos (table) Current position
-- @param options (table|nil) Walkability options
-- @return (table) Array of {pos, cost} for each valid neighbor
function OptimizedAStar:getNeighbors(pos, options)
  local neighbors = {}
  local maxDirs = CONFIG.diagonalMovement and DIAGONAL_COUNT or CARDINAL_COUNT
  
  for i = 1, maxDirs do
    local dir = DIRECTIONS[i]
    local neighbor = {
      x = pos.x + dir.x,
      y = pos.y + dir.y,
      z = pos.z
    }
    
    if self:isWalkable(neighbor, options) then
      neighbors[#neighbors + 1] = {
        pos = neighbor,
        cost = dir.cost
      }
    end
  end
  
  return neighbors
end

--[[
  ============================================================================
  PATH RECONSTRUCTION
  ============================================================================
]]

--- Reconstructs the path from the cameFrom map
-- Works backwards from goal to start
-- 
-- @param cameFrom (table) Map of position key -> previous position
-- @param current (table) Goal position
-- @return (table) Array of positions from start to goal (excludes start)
function OptimizedAStar:reconstructPath(cameFrom, current)
  local path = {current}
  local currentKey = self:posToKey(current)
  
  -- Walk backwards through cameFrom
  while cameFrom[currentKey] do
    current = cameFrom[currentKey]
    table_insert(path, 1, current)  -- Prepend to reverse order
    currentKey = self:posToKey(current)
  end
  
  -- Remove start position (we're already there)
  table_remove(path, 1)
  
  return path
end

--[[
  ============================================================================
  MAIN PATHFINDING FUNCTION
  ============================================================================
]]

--- Finds a path from start to end position
-- 
-- @param startPos (table) Starting position {x, y, z}
-- @param endPos (table) Goal position {x, y, z}
-- @param options (table|nil) Pathfinding options:
--   - ignoreCreatures: Walk through creatures
--   - ignoreFields: Walk through fire/energy
--   - ignoreLastCreature: Allow creature on destination
--   - nodeLimit: Override evaluation limit
-- @return (table|nil) Array of positions, or nil if no path found
function OptimizedAStar:findPath(startPos, endPos, options)
  options = options or {}
  
  -- ========================================
  -- QUICK CHECK: SAME POSITION
  -- ========================================
  if startPos.x == endPos.x and startPos.y == endPos.y and startPos.z == endPos.z then
    return {}  -- Already at destination
  end
  
  -- ========================================
  -- QUICK CHECK: DESTINATION WALKABLE
  -- ========================================
  if not self:isWalkable(endPos, {isLastTile = true, ignoreCreatures = options.ignoreLastCreature}) then
    if self.debugMode then
      print("[PathFinder] Destination not walkable")
    end
    return nil
  end
  
  -- ========================================
  -- CHECK CACHE FIRST
  -- ========================================
  if CONFIG.cacheEnabled and self.cache then
    local cached = self.cache:get(startPos, endPos)
    if cached then
      if self.debugMode then
        print("[PathFinder] Cache hit!")
      end
      return cached
    end
  end
  
  -- ========================================
  -- TRY STRAIGHT-LINE OPTIMIZATION
  -- ========================================
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
  
  -- ========================================
  -- FULL A* ALGORITHM
  -- ========================================
  return self:astarWithLimit(startPos, endPos, options)
end

--- Internal A* implementation with node evaluation limit
-- @param startPos (table) Starting position
-- @param endPos (table) Goal position
-- @param options (table) Pathfinding options
-- @return (table|nil) Path or nil
function OptimizedAStar:astarWithLimit(startPos, endPos, options)
  options = options or {}
  local nodeLimit = options.nodeLimit or CONFIG.nodeEvaluationLimit
  
  -- ========================================
  -- DATA STRUCTURES
  -- ========================================
  -- openSet: Nodes to evaluate (priority queue by f-score)
  -- openSetHash: O(1) membership check
  -- closedSet: Already evaluated nodes
  -- cameFrom: Path reconstruction map
  -- gScore: Cost from start to each node
  -- fScore: Estimated total cost through each node
  local openSet = {}
  local openSetHash = {}
  local closedSet = {}
  local cameFrom = {}
  local gScore = {}
  local fScore = {}
  
  -- Initialize with start position
  local startKey = self:posToKey(startPos)
  gScore[startKey] = 0
  fScore[startKey] = self:heuristic(startPos, endPos)
  
  openSet[1] = {pos = startPos, f = fScore[startKey]}
  openSetHash[startKey] = true
  
  local evaluatedNodes = 0
  
  -- ========================================
  -- MAIN A* LOOP
  -- ========================================
  while #openSet > 0 and evaluatedNodes < nodeLimit do
    -- Get node with lowest f-score
    -- TODO: Binary heap would be O(log n) vs O(n log n) for sort
    table_sort(openSet, function(a, b) return a.f < b.f end)
    local current = table_remove(openSet, 1)
    local currentKey = self:posToKey(current.pos)
    openSetHash[currentKey] = nil
    
    -- ========================================
    -- GOAL CHECK
    -- ========================================
    if current.pos.x == endPos.x and current.pos.y == endPos.y and current.pos.z == endPos.z then
      local path = self:reconstructPath(cameFrom, current.pos)
      
      -- Cache successful path
      if CONFIG.cacheEnabled and self.cache then
        self.cache:set(startPos, endPos, path)
      end
      
      if self.debugMode then
        print(string_format("[PathFinder] Path found, %d nodes evaluated, path length: %d", 
          evaluatedNodes, #path))
      end
      
      return path
    end
    
    closedSet[currentKey] = true
    evaluatedNodes = evaluatedNodes + 1
    
    -- ========================================
    -- EVALUATE NEIGHBORS
    -- ========================================
    local neighbors = self:getNeighbors(current.pos, {
      ignoreCreatures = options.ignoreCreatures,
      ignoreFields = options.ignoreFields
    })
    
    for i = 1, #neighbors do
      local neighbor = neighbors[i]
      local neighborKey = self:posToKey(neighbor.pos)
      
      -- Skip if already evaluated
      if not closedSet[neighborKey] then
        local tentativeGScore = gScore[currentKey] + neighbor.cost
        
        -- Is this a better path to neighbor?
        if not gScore[neighborKey] or tentativeGScore < gScore[neighborKey] then
          -- Update path and scores
          cameFrom[neighborKey] = current.pos
          gScore[neighborKey] = tentativeGScore
          fScore[neighborKey] = tentativeGScore + self:heuristic(neighbor.pos, endPos)
          
          -- Add to open set if not already there
          if not openSetHash[neighborKey] then
            openSet[#openSet + 1] = {pos = neighbor.pos, f = fScore[neighborKey]}
            openSetHash[neighborKey] = true
          end
        end
      end
    end
  end
  
  -- ========================================
  -- NO PATH FOUND
  -- ========================================
  if self.debugMode then
    print(string_format("[PathFinder] No path found after %d nodes", evaluatedNodes))
  end
  
  return nil
end

--[[
  ============================================================================
  CACHE MANAGEMENT
  ============================================================================
]]

--- Gets cache statistics
-- @return (table|nil) Cache stats or nil if caching disabled
function OptimizedAStar:getCacheStats()
  if self.cache then
    return self.cache:getStats()
  end
  return nil
end

--- Clears the entire path cache
function OptimizedAStar:clearCache()
  if self.cache then
    self.cache:clear()
  end
end

--- Invalidates cached paths involving a position
-- Call when map changes (door opens, creature moves, etc.)
-- 
-- @param pos (table) Position that changed
-- @return (number) Number of paths invalidated
function OptimizedAStar:invalidatePosition(pos)
  if self.cache then
    return self.cache:invalidatePosition(pos)
  end
  return 0
end

--[[
  ============================================================================
  CONFIGURATION
  ============================================================================
]]

--- Enables or disables debug logging
-- @param enabled (boolean) Enable debug output
function OptimizedAStar:setDebugMode(enabled)
  self.debugMode = enabled
end

--- Updates configuration at runtime
-- @param options (table) Configuration options (same as initialize)
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

--[[
  ============================================================================
  MODULE EXPORT
  ============================================================================
]]

return OptimizedAStar
