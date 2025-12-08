--[[
  CaveBot Walking Module - Standard OTClient Walking
  
  Uses native OTClient autoWalk function for reliable pathfinding.
  
  FLOOR-CHANGE PREVENTION:
  - Detects stairs, ladders, holes, and teleports
  - Prevents accidental floor changes that would break cavebot
  - Auto-recovery when floor changes unexpectedly
]]

local isWalking = false
local walkDelay = 10
local expectedFloor = nil  -- Track expected floor level

-- Pre-computed direction lookup table for faster direction calculation
local DIR_LOOKUP = {
  [-1] = { [-1] = NorthWest, [0] = North, [1] = NorthEast },
  [0]  = { [-1] = West, [0] = 8, [1] = East },
  [1]  = { [-1] = SouthWest, [0] = South, [1] = SouthEast }
}

-- Minimap colors that indicate floor-change tiles
local FLOOR_CHANGE_COLORS = {
  [210] = true,  -- Stairs up
  [211] = true,  -- Stairs down
  [212] = true,  -- Ladder
  [213] = true,  -- Rope hole
}

-- Item IDs known to cause floor changes
local FLOOR_CHANGE_ITEMS = {
  -- Stairs
  [1948] = true, [1949] = true, [1950] = true, [1951] = true,
  [1952] = true, [1953] = true, [1954] = true, [1955] = true,
  [1956] = true, [1957] = true, [1958] = true, [1959] = true,
  -- Ladders
  [1386] = true, [3678] = true, [5543] = true,
  -- Holes/Pitfalls
  [294] = true, [369] = true, [370] = true, [383] = true,
  [392] = true, [408] = true, [409] = true, [410] = true,
  [427] = true, [428] = true, [429] = true, [430] = true,
  [462] = true, [469] = true, [470] = true, [482] = true,
  [484] = true, [485] = true, [489] = true,
  -- Rope spots
  [384] = true, [418] = true,
  -- Sewer grates
  [435] = true, [1369] = true, [1370] = true,
  -- Trapdoors
  [432] = true, [433] = true, [468] = true, [5765] = true,
}

-- Check if a tile has floor-change items
local function isFloorChangeTile(tilePos)
  if not tilePos then return false end
  
  -- Check minimap color first (fast check)
  local minimapColor = g_map.getMinimapColor(tilePos)
  if FLOOR_CHANGE_COLORS[minimapColor] then
    return true
  end
  
  -- Check tile items (slower but more accurate)
  local tile = g_map.getTile(tilePos)
  if tile then
    local items = tile:getItems()
    if items then
      for _, item in ipairs(items) do
        if FLOOR_CHANGE_ITEMS[item:getId()] then
          return true
        end
      end
    end
    
    -- Check ground item too
    local ground = tile:getGround()
    if ground and FLOOR_CHANGE_ITEMS[ground:getId()] then
      return true
    end
  end
  
  return false
end

-- Check if walking to a position would cause floor change
local function wouldCauseFloorChange(destPos)
  if not destPos then return false end
  
  local playerPos = pos()
  if not playerPos then return false end
  
  -- If destination is on different floor, that's intentional (waypoint system handles it)
  if destPos.z ~= playerPos.z then
    return false
  end
  
  -- Check if the destination tile has floor-change items
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
    -- Reset expected floor to prevent repeated warnings
    expectedFloor = nil
  end
end)

-- Main walking function - uses native OTClient autoWalk
-- Now with floor-change prevention
CaveBot.walkTo = function(dest, maxDist, params)
  local precision = params and params.precision or 1
  local allowFloorChange = params and params.allowFloorChange or false
  
  -- Set expected floor for tracking
  expectedFloor = dest.z
  
  -- FLOOR-CHANGE PREVENTION: Check if destination would cause accidental floor change
  if not allowFloorChange and wouldCauseFloorChange(dest) then
    -- Find alternative safe tile near destination
    local safeTiles = getSafeAdjacentTiles(dest)
    if #safeTiles > 0 then
      -- Use closest safe tile instead
      local playerPos = pos()
      local bestTile = safeTiles[1]
      local bestDist = math.max(math.abs(playerPos.x - bestTile.x), math.abs(playerPos.y - bestTile.y))
      
      for _, tile in ipairs(safeTiles) do
        local dist = math.max(math.abs(playerPos.x - tile.x), math.abs(playerPos.y - tile.y))
        if dist < bestDist then
          bestDist = dist
          bestTile = tile
        end
      end
      
      dest = bestTile
    end
  end
  
  -- Use native OTClient autoWalk for reliable pathfinding
  if autoWalk(dest, maxDist or 20, {
    ignoreNonPathable = params and params.ignoreNonPathable or true,
    precision = precision
  }) then
    -- Delay cavebot macro to allow walking to complete
    local stepDuration = player:getStepDuration(false, 0) or 100
    CaveBot.delay(walkDelay + stepDuration)
    return true
  end
  
  -- Try obstacle handler as last resort
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
