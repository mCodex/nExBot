--[[
  CaveBot Walking Module - Optimized Pathfinding
  
  Uses a hybrid approach:
  1. Path caching with smart invalidation
  2. Progressive pathfinding (try simple first, then complex)
  3. EventBus integration for path invalidation on world changes
  4. Memory-efficient path storage
  
  FLOOR-CHANGE PREVENTION:
  - Detects stairs, ladders, holes, and teleports
  - Prevents accidental floor changes that would break cavebot
  - Auto-recovery when floor changes unexpectedly
]]

local isWalking = false
local walkDelay = 10
local expectedFloor = nil  -- Track expected floor level

--------------------------------------------------------------------------------
-- OPTIMIZED PATH CACHE
-- Stores computed paths with smart invalidation to avoid recalculation
--------------------------------------------------------------------------------
local PathCache = {
  cache = {},           -- {destKey -> {path, timestamp, playerPos}}
  maxSize = 50,         -- Maximum cached paths
  TTL = 2000,           -- Path valid for 2 seconds
  lastCleanup = 0,
  cleanupInterval = 5000
}

-- Generate cache key from destination
local function getCacheKey(dest)
  return dest.x .. "," .. dest.y .. "," .. dest.z
end

-- Get cached path if still valid
local function getCachedPath(playerPos, dest)
  local key = getCacheKey(dest)
  local cached = PathCache.cache[key]
  
  if not cached then return nil end
  if now - cached.timestamp > PathCache.TTL then
    PathCache.cache[key] = nil
    return nil
  end
  
  -- Invalidate if player moved significantly
  local dx = math.abs(playerPos.x - cached.playerPos.x)
  local dy = math.abs(playerPos.y - cached.playerPos.y)
  if dx > 2 or dy > 2 or playerPos.z ~= cached.playerPos.z then
    PathCache.cache[key] = nil
    return nil
  end
  
  return cached.path
end

-- Store path in cache
local function setCachedPath(playerPos, dest, path)
  -- Cleanup if cache is full
  local count = 0
  for _ in pairs(PathCache.cache) do count = count + 1 end
  
  if count >= PathCache.maxSize then
    -- Remove oldest entries
    local oldest = nil
    local oldestTime = now
    for key, data in pairs(PathCache.cache) do
      if data.timestamp < oldestTime then
        oldestTime = data.timestamp
        oldest = key
      end
    end
    if oldest then
      PathCache.cache[oldest] = nil
    end
  end
  
  PathCache.cache[getCacheKey(dest)] = {
    path = path,
    timestamp = now,
    playerPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  }
end

-- Invalidate all cached paths (called on world changes)
local function invalidatePathCache()
  PathCache.cache = {}
end

-- EventBus integration for path invalidation
if EventBus then
  EventBus.on("player:move", function(newPos, oldPos)
    -- Only invalidate on floor change
    if oldPos and newPos and oldPos.z ~= newPos.z then
      invalidatePathCache()
    end
  end, 30)
  
  EventBus.on("tile:add", function(tile, thing)
    -- Invalidate on significant tile changes
    if thing and thing:isNotMoveable() then
      invalidatePathCache()
    end
  end, 20)
end

-- Pre-computed direction lookup table for faster direction calculation
local DIR_LOOKUP = {
  [-1] = { [-1] = NorthWest, [0] = North, [1] = NorthEast },
  [0]  = { [-1] = West, [0] = 8, [1] = East },
  [1]  = { [-1] = SouthWest, [0] = South, [1] = SouthEast }
}

-- Direction to offset mapping for path validation
local DIR_TO_OFFSET = {
  [North] = {x = 0, y = -1},
  [East] = {x = 1, y = 0},
  [South] = {x = 0, y = 1},
  [West] = {x = -1, y = 0},
  [NorthEast] = {x = 1, y = -1},
  [SouthEast] = {x = 1, y = 1},
  [SouthWest] = {x = -1, y = 1},
  [NorthWest] = {x = -1, y = -1}
}

-- Minimap colors that indicate floor-change tiles
local FLOOR_CHANGE_COLORS = {
  [210] = true,  -- Stairs up
  [211] = true,  -- Stairs down
  [212] = true,  -- Ladder
  [213] = true,  -- Rope hole
}

-- Item IDs known to cause floor changes (minimal set for performance)
local FLOOR_CHANGE_ITEMS = {
  -- Stairs (most common)
  [1948] = true, [1949] = true, [1950] = true, [1951] = true,
  [1952] = true, [1953] = true, [1954] = true, [1955] = true,
  -- Ladders
  [1386] = true, [3678] = true, [5543] = true,
  -- Holes
  [294] = true, [369] = true, [370] = true, [383] = true,
  [392] = true, [408] = true, [409] = true, [410] = true,
  -- Rope spots
  [384] = true, [418] = true,
}

-- Check if a tile has floor-change items (optimized - minimap check first)
local function isFloorChangeTile(tilePos)
  if not tilePos then return false end
  
  -- Fast check via minimap color (O(1))
  local minimapColor = g_map.getMinimapColor(tilePos)
  if FLOOR_CHANGE_COLORS[minimapColor] then
    return true
  end
  
  return false
end

-- Check if walking to a position would cause floor change
local function wouldCauseFloorChange(destPos)
  if not destPos then return false end
  
  local playerPos = pos()
  if not playerPos then return false end
  
  -- Different floor is intentional
  if destPos.z ~= playerPos.z then
    return false
  end
  
  return isFloorChangeTile(destPos)
end

-- Get safe adjacent tiles (no floor change)
local function getSafeAdjacentTiles(centerPos)
  local safeTiles = {}
  local directions = {
    {x = 0, y = -1},  -- North
    {x = 1, y = 0},   -- East
    {x = 0, y = 1},   -- South
    {x = -1, y = 0},  -- West
    {x = 1, y = -1},  -- NorthEast
    {x = 1, y = 1},   -- SouthEast
    {x = -1, y = 1},  -- SouthWest
    {x = -1, y = -1}, -- NorthWest
  }
  
  for _, dir in ipairs(directions) do
    local checkPos = {
      x = centerPos.x + dir.x,
      y = centerPos.y + dir.y,
      z = centerPos.z
    }
    
    local tile = g_map.getTile(checkPos)
    if tile and tile:isWalkable() and not isFloorChangeTile(checkPos) then
      table.insert(safeTiles, checkPos)
    end
  end
  
  return safeTiles
end

CaveBot.resetWalking = function()
  isWalking = false
end

-- Check if cavebot is currently in walking state
-- Uses native player:isWalking() for accurate detection
CaveBot.doWalking = function()
  return player and player:isWalking()
end

-- Set expected floor (call when starting to walk to a waypoint)
CaveBot.setExpectedFloor = function(floor)
  expectedFloor = floor
end

-- Check if player is on expected floor
CaveBot.isOnExpectedFloor = function()
  if not expectedFloor then return true end
  return posz() == expectedFloor
end

-- Get unexpected floor change info
CaveBot.getFloorChangeInfo = function()
  if not expectedFloor then return nil end
  local currentFloor = posz()
  if currentFloor ~= expectedFloor then
    return {
      expected = expectedFloor,
      current = currentFloor,
      difference = currentFloor - expectedFloor
    }
  end
  return nil
end

-- Called when player position changes (step confirmed by server)
onPlayerPositionChange(function(newPos, oldPos)
  if not oldPos or not newPos then return end
  
  -- Detect unexpected floor change
  if expectedFloor and newPos.z ~= expectedFloor then
    warn("[CaveBot] Unexpected floor change! Expected: " .. expectedFloor .. ", Current: " .. newPos.z)
    expectedFloor = nil
    invalidatePathCache()
  end
end)

--------------------------------------------------------------------------------
-- OPTIMIZED WALKING FUNCTION
-- Uses progressive pathfinding: simple -> complex -> fallback
-- PERFORMANCE: Limits pathfinding distance to prevent client freeze
--------------------------------------------------------------------------------

-- Maximum pathfinding calculation distance (prevents freeze on long paths)
local MAX_PATHFIND_DIST = 50  -- Limit pathfinding to 50 tiles

CaveBot.walkTo = function(dest, maxDist, params)
  local playerPos = pos()
  if not playerPos then return false end
  
  local precision = params and params.precision or 1
  local allowFloorChange = params and params.allowFloorChange or false
  maxDist = maxDist or 20
  
  -- PERFORMANCE: Clamp maxDist to prevent expensive pathfinding
  local clampedMaxDist = math.min(maxDist, MAX_PATHFIND_DIST)
  
  -- Set expected floor for tracking
  expectedFloor = dest.z
  
  -- Quick distance check
  local distX = math.abs(dest.x - playerPos.x)
  local distY = math.abs(dest.y - playerPos.y)
  local totalDist = distX + distY
  
  -- Already at destination
  if distX <= precision and distY <= precision and dest.z == playerPos.z then
    return true
  end
  
  -- Floor mismatch - can't walk
  if dest.z ~= playerPos.z then
    return false
  end
  
  -- FLOOR-CHANGE PREVENTION
  if not allowFloorChange and wouldCauseFloorChange(dest) then
    local safeTiles = getSafeAdjacentTiles(dest)
    if #safeTiles > 0 then
      local bestTile = safeTiles[1]
      local bestDist = distX + distY
      
      for _, tile in ipairs(safeTiles) do
        local d = math.abs(playerPos.x - tile.x) + math.abs(playerPos.y - tile.y)
        if d < bestDist then
          bestDist = d
          bestTile = tile
        end
      end
      dest = bestTile
    end
  end
  
  -- Check path cache first (avoid redundant pathfinding)
  local cachedPath = getCachedPath(playerPos, dest)
  if cachedPath and #cachedPath > 0 then
    -- Validate first step of cached path is still walkable
    local firstDir = cachedPath[1]
    local offset = DIR_TO_OFFSET[firstDir]
    if offset then
      local nextPos = {
        x = playerPos.x + offset.x,
        y = playerPos.y + offset.y,
        z = playerPos.z
      }
      local tile = g_map.getTile(nextPos)
      if tile and tile:isWalkable() and not tile:hasCreature() then
        -- Path still valid, take first step
        walk(firstDir)
        local stepDuration = player:getStepDuration(false, 0) or 100
        CaveBot.delay(walkDelay + stepDuration)
        return true
      end
    end
    -- Path invalid, clear it
    PathCache.cache[getCacheKey(dest)] = nil
  end
  
  -- PERFORMANCE: For very long distances, use autoWalk directly (let client handle it)
  -- This avoids expensive progressive pathfinding
  if totalDist > MAX_PATHFIND_DIST then
    if autoWalk(dest, maxDist, {
      ignoreNonPathable = params and params.ignoreNonPathable or true,
      ignoreCreatures = params and params.ignoreCreatures or false,
      precision = precision
    }) then
      local stepDuration = player:getStepDuration(false, 0) or 100
      CaveBot.delay(walkDelay + stepDuration)
      return true
    end
    -- autoWalk failed, skip progressive pathfinding (would freeze client)
    return false
  end
  
  -- Progressive pathfinding: try simple first (faster), then complex
  -- Only used for short/medium distances
  -- OPTIMIZED: Use autoWalk first (fastest), only fall back to manual pathfinding if needed
  local path = nil
  
  -- Try autoWalk first (most efficient - uses client's pathfinding)
  if autoWalk(dest, clampedMaxDist, {
    ignoreNonPathable = params and params.ignoreNonPathable or true,
    ignoreCreatures = params and params.ignoreCreatures or false,
    precision = precision
  }) then
    local stepDuration = player:getStepDuration(false, 0) or 100
    CaveBot.delay(walkDelay + stepDuration)
    return true
  end
  
  -- autoWalk failed - try manual pathfinding (Stage 1: Simple)
  path = findPath(playerPos, dest, clampedMaxDist, {
    ignoreNonPathable = true,
    precision = precision
  })
  
  -- Only try more complex pathfinding if simple failed AND we're close enough
  if not path and totalDist <= 30 then
    -- Stage 2: Try with creature ignoring
    path = findPath(playerPos, dest, clampedMaxDist, {
      ignoreNonPathable = true,
      ignoreCreatures = true,
      precision = precision
    })
  end
  
  -- Stage 3 is expensive - only try if really close and previous stages failed
  if not path and totalDist <= 15 then
    path = findPath(playerPos, dest, clampedMaxDist, {
      ignoreNonPathable = true,
      ignoreCreatures = true,
      allowUnseen = true,
      allowOnlyVisibleTiles = false,
      precision = precision
    })
  end
  
  if path and #path > 0 then
    -- Cache the path for future use
    setCachedPath(playerPos, dest, path)
    
    -- Use native autoWalk for smooth walking
    if autoWalk(dest, maxDist, {
      ignoreNonPathable = params and params.ignoreNonPathable or true,
      ignoreCreatures = params and params.ignoreCreatures or false,
      precision = precision
    }) then
      local stepDuration = player:getStepDuration(false, 0) or 100
      CaveBot.delay(walkDelay + stepDuration)
      return true
    end
    
    -- Fallback: manual first step if autoWalk fails
    walk(path[1])
    local stepDuration = player:getStepDuration(false, 0) or 100
    CaveBot.delay(walkDelay + stepDuration)
    return true
  end
  
  -- Last resort: obstacle handler
  if CaveBot.Tools and CaveBot.Tools.handleObstacle then
    if CaveBot.Tools.handleObstacle(dest) then
      return true
    end
  end
  
  return false
end

-- Safe walk function that explicitly prevents floor changes
CaveBot.safeWalkTo = function(dest, maxDist, params)
  params = params or {}
  params.allowFloorChange = false
  return CaveBot.walkTo(dest, maxDist, params)
end

-- Check if a path to destination would cross floor-change tiles
CaveBot.isPathSafe = function(dest)
  local playerPos = pos()
  if not playerPos or not dest then return true end
  
  -- Same position
  if playerPos.x == dest.x and playerPos.y == dest.y and playerPos.z == dest.z then
    return true
  end
  
  -- Different floor is intentional
  if playerPos.z ~= dest.z then
    return true
  end
  
  -- For short distances, check each tile in the path
  local path = findPath(playerPos, dest, {ignoreNonPathable = true})
  if path then
    for _, pathPos in ipairs(path) do
      if isFloorChangeTile(pathPos) then
        return false
      end
    end
  end
  
  return true
end

-- Expose utility functions
CaveBot.isFloorChangeTile = isFloorChangeTile
CaveBot.getSafeAdjacentTiles = getSafeAdjacentTiles
CaveBot.invalidatePathCache = invalidatePathCache
