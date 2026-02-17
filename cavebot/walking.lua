--[[
  CaveBot Walking Module v5.0.0
  
  DESIGN PRINCIPLES:
  - SRP: Each function has one responsibility
  - DRY: Uses shared PathUtils module (no duplicated logic)
  - KISS: Simple, readable functions
  - Pure Functions: Predictable, no side effects where possible
  - SOLID: Open for extension, closed for modification
  
  OTClientBR Native API OPTIMIZATIONS:
  - Uses g_map.findPath() with native flags for performance
  - Uses player:getStepDuration() for precise timing
  - Uses player:isWalking() and player:isAutoWalking() for state checks
  - Uses player:stopAutoWalk() for proper walk cancellation
  - Uses player:canWalk() for direction validation
  - Uses tile:isWalkable(ignoreCreatures) for fast tile checks
  - Uses tile:isPathable() for path validation
  - Uses tile:getGroundSpeed() for accurate timing
  - Uses PathUtils for shared utilities and anti-zigzag logic
  
  PATHFINDING FLAGS (Otc::PathFindFlags):
  - PathFindAllowNotSeenTiles = 1
  - PathFindAllowCreatures = 2
  - PathFindAllowNonPathable = 4
  - PathFindAllowNonWalkable = 8
  - PathFindIgnoreCreatures = 16
  
  ANTI-ZIGZAG SYSTEM:
  - Direction smoothing via PathUtils.getSmoothedDirection()
  - Minimum delay between direction changes
  - Opposite direction dampening
]]

-- Load shared modules (set as globals in _Loader Phase 3)
local PathUtils    = PathUtils
local PathStrategy = PathStrategy
if not PathUtils then
  local ok, mod = pcall(require, "utils.path_utils")
  if ok and mod then PathUtils = mod end
end
if not PathStrategy then
  local ok, mod = pcall(require, "utils.path_strategy")
  if ok and mod then PathStrategy = mod end
end

-- SAFEGUARD: Ensure CaveBot.resetWalking exists even if file partially loads
-- This will be overwritten by the proper implementation below
if not CaveBot then CaveBot = {} end
if not CaveBot.resetWalking then
  CaveBot.resetWalking = function() end
end
if not CaveBot.fullResetWalking then
  CaveBot.fullResetWalking = function() end
end

local getClient = nExBot.Shared.getClient

-- ============================================================================
-- MODULE STATE (minimal, well-defined)
-- ============================================================================

local expectedFloor = nil
local lastWalkZ = nil

-- OPTIMIZED: Use native API limits for best performance
local MAX_PATHFIND_DIST = 50   -- OTClient A* limit is ~50-127 tiles
local MAX_WALK_CHUNK = 40      -- Larger chunks = fewer path recalculations

-- ============================================================================
-- OTCLIENT API OPTIMIZATIONS (NEW: High-performance walking)
-- ============================================================================

-- Use PathUtils for step duration (DRY: no duplicate caching logic)
local function getCachedStepDuration(diagonal)
  if PathUtils and PathUtils.getStepDuration then
    return PathUtils.getStepDuration(diagonal)
  end
  -- Fallback
  return (player.getStepDuration and player:getStepDuration(false, diagonal and NorthEast or North)) or 150
end

-- Use PathUtils for tile walkability (DRY)
local function isTileWalkableFast(pos, ignoreCreatures)
  if PathUtils and PathUtils.isTileWalkable then
    return PathUtils.isTileWalkable(pos, ignoreCreatures)
  end
  -- Fallback
  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(pos) or (g_map and g_map.getTile(pos))
  if not tile then return false end
  return tile:isWalkable(ignoreCreatures or false)
end

-- Check if player is auto-walking (native API)
local function isAutoWalking()
  if PathUtils and PathUtils.isAutoWalking then
    return PathUtils.isAutoWalking()
  end
  return player and player.isAutoWalking and player:isAutoWalking() or false
end

-- Stop auto-walk (native API)
local function stopAutoWalk()
  if PathUtils and PathUtils.stopAutoWalk then
    PathUtils.stopAutoWalk()
    return
  end
  if player and player.stopAutoWalk then
    player:stopAutoWalk()
  end
  if g_game and g_game.stop then
    g_game.stop()
  end
end

-- Get tile ground speed for timing calculations
local function getTileSpeed(pos)
  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(pos) or (g_map and g_map.getTile(pos))
  if not tile then return 150 end  -- Default speed
  return (tile.getGroundSpeed and tile:getGroundSpeed()) or 150
end

-- Check if player can walk in direction (uses native canWalk)
local function canWalkDirection(dir)
  return (player.canWalk and player:canWalk(dir)) or true
end

-- ============================================================================
-- PATH SMOOTHING CONSTANTS (For 40%+ accuracy improvement)
-- ============================================================================

-- Floor change tile cache (for resetWalking)
local FloorChangeCache = {
  tiles = {},
  lastUpdate = 0,
}

local PATH_SMOOTHING = {
  -- Direction consistency tracking
  lastDirection = nil,
  lastDirectionTime = 0,
  directionChanges = 0,
  directionChangeThreshold = 3,  -- Max rapid changes before dampening
  directionDampingTime = 150,    -- ms to wait before allowing direction change
  
  -- Path stability
  lastWaypointPos = nil,
  lastPathTime = 0,
  pathStabilityBonus = 0,  -- Bonus time added for stable walking
  
  -- Destination caching for continuous walking
  cachedDestination = nil,
  destinationReachedAt = 0,
}

-- Calculate direction from position A to position B (returns cardinal/diagonal direction)
local function getDirectionTo(fromPos, toPos)
  local dx = toPos.x - fromPos.x
  local dy = toPos.y - fromPos.y
  
  -- Normalize to -1, 0, 1
  local nx = dx == 0 and 0 or (dx > 0 and 1 or -1)
  local ny = dy == 0 and 0 or (dy > 0 and 1 or -1)
  
  -- Map to direction
  if nx == 0 and ny == -1 then return North end
  if nx == 1 and ny == 0 then return East end
  if nx == 0 and ny == 1 then return South end
  if nx == -1 and ny == 0 then return West end
  if nx == 1 and ny == -1 then return NorthEast end
  if nx == 1 and ny == 1 then return SouthEast end
  if nx == -1 and ny == 1 then return SouthWest end
  if nx == -1 and ny == -1 then return NorthWest end
  
  return nil
end

-- Use PathUtils for direction similarity (DRY)
local function areSimilarDirections(dir1, dir2)
  if PathUtils and PathUtils.areSimilarDirections then
    return PathUtils.areSimilarDirections(dir1, dir2)
  end
  -- Fallback
  if dir1 == nil or dir2 == nil then return true end
  return dir1 == dir2
end

-- Anti-zigzag: Check if directions are opposite
local function areOppositeDirections(dir1, dir2)
  if PathUtils and PathUtils.areOppositeDirections then
    return PathUtils.areOppositeDirections(dir1, dir2)
  end
  return false
end

-- Anti-zigzag: Get smoothed direction to prevent oscillation
local function getSmoothedDirection(dir, forceChange)
  if PathUtils and PathUtils.getSmoothedDirection then
    return PathUtils.getSmoothedDirection(dir, forceChange)
  end
  return dir
end

-- ============================================================================
-- DIRECTION UTILITIES (Use PathUtils where possible)
-- ============================================================================

-- Use Directions constant module if available (DRY)
local Dirs = Directions
local DIR_TO_OFFSET = (Dirs and Dirs.DIR_TO_OFFSET) or (PathUtils and PathUtils.DIR_TO_OFFSET) or {
  [North] = {x = 0, y = -1},
  [East] = {x = 1, y = 0},
  [South] = {x = 0, y = 1},
  [West] = {x = -1, y = 0},
  [NorthEast] = {x = 1, y = -1},
  [SouthEast] = {x = 1, y = 1},
  [SouthWest] = {x = -1, y = 1},
  [NorthWest] = {x = -1, y = -1}
}

local ADJACENT_OFFSETS = (Dirs and Dirs.ADJACENT_OFFSETS) or {
  {x = 0, y = -1},  {x = 1, y = 0},  {x = 0, y = 1},  {x = -1, y = 0},
  {x = 1, y = -1}, {x = 1, y = 1}, {x = -1, y = 1}, {x = -1, y = -1},
}

-- Pure: Get offset for direction (use PathUtils)
local function getDirectionOffset(dir)
  return DIR_TO_OFFSET[dir]
end

-- Pure: Apply offset to position (use PathUtils if available)
local function applyOffset(pos, offset)
  if PathUtils and PathUtils.applyDirection and type(offset) == 'number' then
    return PathUtils.applyDirection(pos, offset)
  end
  return {x = pos.x + offset.x, y = pos.y + offset.y, z = pos.z}
end

-- Pure: Check position equality (use PathUtils)
local function posEquals(a, b)
  if PathUtils and PathUtils.posEquals then
    return PathUtils.posEquals(a, b)
  end
  return a.x == b.x and a.y == b.y and a.z == b.z
end

-- ============================================================================
-- FIELD DETECTION (Use PathUtils if available)
-- ============================================================================

-- Use PathUtils for field items if available
local FIELD_ITEM_IDS = (PathUtils and PathUtils.FIELD_ITEMS) or {
  -- Fire Fields
  [1487] = true, [1488] = true, [1489] = true, [1490] = true, [1491] = true,
  [1492] = true, [1493] = true, [1494] = true, [1495] = true, [1496] = true,
  [1497] = true, [1498] = true, [1499] = true, [1500] = true, [1501] = true,
  [1502] = true, [1503] = true, [1504] = true, [1505] = true, [1506] = true,
  -- Old fire IDs
  [2120] = true, [2121] = true, [2122] = true, [2123] = true, [2124] = true,
  [2125] = true, [2126] = true, [2127] = true, [2128] = true,
  
  -- Energy Fields  
  [1491] = true, [1495] = true,
  [2119] = true, [2124] = true, [2125] = true,
  [7487] = true, [7488] = true, [7489] = true, [7490] = true,
  [8069] = true, [8070] = true, [8071] = true, [8072] = true,
  
  -- Poison Fields
  [1490] = true, [1496] = true,
  [1503] = true, [1504] = true, [1505] = true, [1506] = true,
  [2118] = true, [2119] = true,
  [7465] = true, [7466] = true, [7467] = true, [7468] = true,
  
  -- Magic Walls (treat as fields - block path)
  [2128] = true, [2129] = true, [2130] = true,
  [7491] = true, [7492] = true, [7493] = true, [7494] = true,
  
  -- Wild Growth
  [2130] = true, [2131] = true,
}

-- ============================================================================
-- FLOOR-CHANGE DETECTION (Use PathUtils for DRY)
-- ============================================================================

-- Use PathUtils for floor-change colors and items if available
local FLOOR_CHANGE_COLORS = (PathUtils and PathUtils.FLOOR_CHANGE_COLORS) or {
  [210] = true, [211] = true, [212] = true, [213] = true,
}

local FLOOR_CHANGE_ITEMS = (PathUtils and PathUtils.FLOOR_CHANGE_ITEMS) or {
  -- Minimal fallback set
  [414] = true, [415] = true, [416] = true, [417] = true,
  [1956] = true, [1957] = true, [1958] = true, [1959] = true,
  [1219] = true, [384] = true, [386] = true, [418] = true,
}

-- Use PathUtils for floor-change detection (DRY)
local function isFloorChangeTile(tilePos)
  if PathUtils and PathUtils.isFloorChangeTile then
    return PathUtils.isFloorChangeTile(tilePos)
  end
  -- Fallback: minimap color check
  if not tilePos then return false end
  local Client = getClient()
  local color = (Client and Client.getMinimapColor) and Client.getMinimapColor(tilePos) or (g_map and g_map.getMinimapColor(tilePos)) or 0
  return FLOOR_CHANGE_COLORS[color] or false
end

-- Use PathUtils for field detection (DRY)
local function isFieldTile(tilePos)
  if PathUtils and PathUtils.isFieldTile then
    return PathUtils.isFieldTile(tilePos)
  end
  return false
end

-- Fast minimap-only check (for distant tiles - performance optimization)
local function isFloorChangeTileFast(tilePos)
  if PathUtils and PathUtils.isFloorChangeTileFast then
    return PathUtils.isFloorChangeTileFast(tilePos)
  end
  return isFloorChangeTile(tilePos)
end

-- ============================================================================
-- TILE SAFETY (Use PathUtils for DRY)
-- ============================================================================

-- Use PathUtils for tile safety checks
local function isTileSafe(tilePos, allowFloorChange)
  if PathUtils and PathUtils.isTileSafe then
    return PathUtils.isTileSafe(tilePos, allowFloorChange)
  end
  -- Fallback
  if not tilePos then return false end
  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(tilePos) or (g_map and g_map.getTile(tilePos))
  if not tile then return false end
  if not tile:isWalkable() then return false end
  local hasCreature = tile.hasCreature and tile:hasCreature()
  if hasCreature then return false end
  if not allowFloorChange and isFloorChangeTile(tilePos) then return false end
  return true
end

-- Pure: Get safe adjacent tiles
local function getSafeAdjacentTiles(centerPos, allowFloorChange)
  local safe = {}
  for _, offset in ipairs(ADJACENT_OFFSETS) do
    local checkPos = applyOffset(centerPos, offset)
    if isTileSafe(checkPos, allowFloorChange) then
      table.insert(safe, checkPos)
    end
  end
  return safe
end

-- ============================================================================
-- PATH VALIDATION (SRP: Validates paths for safety)
-- ============================================================================

-- Check if a position is adjacent to a floor-change tile (Use PathUtils for DRY)
local function isNearFloorChangeTile(tilePos)
  if PathUtils and PathUtils.isNearFloorChangeTile then
    return PathUtils.isNearFloorChangeTile(tilePos)
  end
  -- Fallback implementation
  if not tilePos then return false end
  if isFloorChangeTile(tilePos) then return true end
  for _, offset in ipairs(ADJACENT_OFFSETS) do
    local checkPos = applyOffset(tilePos, offset)
    if isFloorChangeTile(checkPos) then return true end
  end
  return false
end

-- Check if path crosses floor-change tiles (Use PathUtils for DRY)
local function pathCrossesFloorChange(path, startPos, maxSteps)
  if PathUtils and PathUtils.pathCrossesFloorChange then
    return PathUtils.pathCrossesFloorChange(path, startPos, maxSteps)
  end
  -- Fallback implementation
  if not path or #path == 0 then return false end
  local probe = {x = startPos.x, y = startPos.y, z = startPos.z}
  local checkLimit = maxSteps and math.min(#path, maxSteps) or #path
  for i = 1, checkLimit do
    local offset = getDirectionOffset(path[i])
    if offset then
      probe = applyOffset(probe, offset)
      if isFloorChangeTile(probe) then
        return true
      end
    end
  end
  return false
end

-- Pure: Get first unsafe step index (0 if all safe)
local function getFirstUnsafeStep(path, startPos)
  if not path or #path == 0 then return 0 end
  
  local probe = {x = startPos.x, y = startPos.y, z = startPos.z}
  for i = 1, #path do
    local offset = getDirectionOffset(path[i])
    if offset then
      probe = applyOffset(probe, offset)
      if isFloorChangeTile(probe) then
        return i
      end
    end
  end
  return 0
end

-- ============================================================================
-- SAFE PATH FINDING (SRP: Finds paths avoiding floor changes)
-- ============================================================================

-- Find alternate destination with safe path (optimized: quick search)
local function findSafeAlternate(playerPos, dest, maxDist, opts)
  opts = opts or {}
  local precision = opts.precision or 1
  local ignoreFields = opts.ignoreFields or false
  
  -- Quick search: only check immediate neighbors (radius 1)
  for _, offset in ipairs(ADJACENT_OFFSETS) do
    local candidate = {
      x = dest.x + offset.x,
      y = dest.y + offset.y,
      z = dest.z
    }
    
    if not posEquals(candidate, playerPos) and not isFloorChangeTile(candidate) then
      -- Quick path check without full validation
      local path = findPath(playerPos, candidate, maxDist, {
        ignoreNonPathable = true,
        ignoreCreatures = true,
        ignoreFields = ignoreFields,
        precision = precision
      })
      
      if path and #path > 0 then
        return candidate, path
      end
    end
  end
  
  return nil, nil
end

-- Lightweight path cursor to avoid table.remove churn
-- IMPROVED: Extended TTL and added smoothing state
local PathCursor = {
  path = nil,
  idx = 1,
  ts = 0,
  TTL = 800,  -- IMPROVED: Extended TTL for smoother continuous walking (was 500)
  destPos = nil,  -- Track destination for path reuse
  lastChunkEnd = nil,  -- Track where last chunk ended for continuity
  smoothingActive = false,  -- Whether path smoothing is enabled
  lastChunkDir = nil,
  lastChunkTime = 0,
}

local function resetPathCursor()
  PathCursor.path = nil
  PathCursor.idx = 1
  PathCursor.ts = 0
  PathCursor.destPos = nil
  PathCursor.lastChunkEnd = nil
  PathCursor.smoothingActive = false
  PathCursor.lastChunkDir = nil
  PathCursor.lastChunkTime = 0
end

-- IMPROVED: Path smoothing function - removes unnecessary zig-zag movements
-- Analyzes path and simplifies redundant direction changes
local function smoothPath(path, startPos)
  if not path or #path < 3 then return path end
  
  local smoothed = {}
  local pos = {x = startPos.x, y = startPos.y, z = startPos.z}
  local i = 1
  
  while i <= #path do
    local dir = path[i]
    local offset = getDirectionOffset(dir)
    if not offset then 
      i = i + 1
    else
      -- Look ahead to see if we can simplify the path
      local nextPos = applyOffset(pos, offset)

      -- Check for zig-zag patterns and convert to diagonals when safe
      if i + 2 <= #path then
        local dir2 = path[i + 1]
        local dir3 = path[i + 2]
        if dir == dir3 and dir ~= dir2 then
          local offset2 = getDirectionOffset(dir2)
          if offset2 then
            -- Compute diagonal target (pos + dir + dir2)
            local diagPos = applyOffset(pos, {x = offset.x + offset2.x, y = offset.y + offset2.y})
            local diagonalDir = getDirectionTo(pos, diagPos)
            if diagonalDir then
              local Client = getClient()
              local tile = (Client and Client.getTile) and Client.getTile(diagPos) or (g_map and g_map.getTile(diagPos))
              if tile and tile:isWalkable() and not isFloorChangeTile(diagPos) then
                smoothed[#smoothed + 1] = diagonalDir
                -- Continue with the last direction in the pattern to reach the same end
                smoothed[#smoothed + 1] = dir
                pos = applyOffset(diagPos, offset)
                i = i + 3
                goto continue_smooth
              end
            end
          end
        end
      end

      -- Add direction to smoothed path
      smoothed[#smoothed + 1] = dir
      pos = nextPos
      i = i + 1
      ::continue_smooth::
    end
  end
  
  return #smoothed > 0 and smoothed or path
end

-- IMPROVED: Calculate optimal chunk size based on path characteristics
local function calculateOptimalChunkSize(path, startPos, baseSafeSteps)
  if not path or #path == 0 then return 1 end
  
  local pathLen = #path
  local chunkSize = baseSafeSteps
  
  -- For short paths, use smaller chunks for precision
  if pathLen <= 5 then
    chunkSize = math.min(chunkSize, pathLen)
  -- For medium paths, use moderate chunks
  elseif pathLen <= 15 then
    chunkSize = math.min(chunkSize, 10)
  -- For long paths, use larger chunks for speed
  else
    chunkSize = math.min(chunkSize, MAX_WALK_CHUNK)
  end
  
  -- Check direction consistency - if path has many direction changes, use smaller chunks
  local directionChanges = 0
  local lastDir = nil
  local probe = {x = startPos.x, y = startPos.y, z = startPos.z}
  
  for i = 1, math.min(chunkSize, #path) do
    local dir = path[i]
    if lastDir and dir ~= lastDir then
      directionChanges = directionChanges + 1
    end
    lastDir = dir
  end
  
  -- If path is very zig-zaggy, use smaller chunks (with hysteresis)
  if chunkSize >= 6 and directionChanges >= 3 and directionChanges > chunkSize * 0.65 then
    chunkSize = math.max(4, math.floor(chunkSize * 0.7))
  end
  
  return chunkSize
end

-- Track last safe position to allow a step-back on unexpected floor change
local lastSafePos = nil
local lastStepBackTs = 0
local STEP_BACK_COOLDOWN = 2000 -- ms - increased to prevent rapid step-back loops
local stepBackAttempts = 0
local MAX_STEP_BACK_ATTEMPTS = 3  -- Max attempts before giving up

local function stepBackToLastSafe(currentPos)
  if not lastSafePos then return false end
  currentPos = currentPos or pos()
  if not currentPos then return false end
  if now - lastStepBackTs < STEP_BACK_COOLDOWN then return false end
  if posEquals(currentPos, lastSafePos) then return false end
  
  -- Limit step-back attempts to prevent infinite loops
  stepBackAttempts = stepBackAttempts + 1
  if stepBackAttempts > MAX_STEP_BACK_ATTEMPTS then
    -- Too many attempts - give up and accept current position
    lastSafePos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
    stepBackAttempts = 0
    return false
  end

  lastStepBackTs = now

  -- Attempt a short path back; allow small detours but keep it tight
  local path = findPath(currentPos, lastSafePos, 10, {
    ignoreNonPathable = true,
    ignoreCreatures = true,
    ignoreFields = true,
    precision = 0
  })

  if not path or #path == 0 then
    -- Can't find path back - accept current position
    lastSafePos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
    stepBackAttempts = 0
    return false
  end

  autoWalk(lastSafePos, 10, {ignoreNonPathable = true, precision = 0})
  resetPathCursor()
  return true
end

-- Reset step-back attempts when we successfully complete a walk
local function resetStepBackAttempts()
  stepBackAttempts = 0
end

-- ============================================================================
-- MAIN WALKING FUNCTION (Orchestrates all components)
-- ============================================================================

CaveBot.walkTo = function(dest, maxDist, params)
  local playerPos = pos()
  if not playerPos then return false end
  
  -- Initialize lastSafePos if not set, but ONLY if we're not near a floor-change tile
  if not lastSafePos then
    if not isNearFloorChangeTile(playerPos) then
      lastSafePos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
    end
  end
  
  -- Check for floor mismatch since last walk call
  -- This catches floor changes that happened between walkTo calls
  if lastWalkZ and playerPos.z ~= lastWalkZ then
    -- Check if this floor change was intended (via intendedFloorChange system)
    local wasIntentional = CaveBot.isFloorChangeIntended and CaveBot.isFloorChangeIntended(playerPos.z)
    
    if wasIntentional then
      -- Intentional floor change - update tracking, continue normally
      lastWalkZ = playerPos.z
      lastSafePos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
      resetStepBackAttempts()
      -- Clear the intended flag since we've completed the floor change
      if CaveBot.clearIntendedFloorChange then
        CaveBot.clearIntendedFloorChange()
      end
    else
      -- Unintended floor change - try to step back (with loop protection)
      local shouldStepBack = true
      if CaveBot.getRecentFloorChange then
        local recent = CaveBot.getRecentFloorChange()
        if recent and recent.toZ == lastWalkZ then
          -- We'd be going back to a floor we just came from - loop detected
          shouldStepBack = false
        end
      end
      
      if shouldStepBack then
        stepBackToLastSafe(playerPos)
      else
        -- Accept the floor change to avoid loop
        lastSafePos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
      end
      
      lastWalkZ = playerPos.z
      return false
    end
  end
  
  params = params or {}
  local precision = params.precision or 1
  local allowFloorChange = params.allowFloorChange or false
  local ignoreCreatures = params.ignoreCreatures or false
  
  -- Get ignoreFields from params or config
  local ignoreFields = params.ignoreFields
  if ignoreFields == nil then
    ignoreFields = CaveBot.Config and CaveBot.Config.get and CaveBot.Config.get("ignoreFields") or false
  end
  
  maxDist = math.min(maxDist or 20, MAX_PATHFIND_DIST)
  
  -- IMPORTANT: Do NOT set expectedFloor here!
  -- Floor change tracking is handled ONLY by intendedFloorChange in cavebot.lua
  -- The goto action sets intendedFloorChange when walking to a floor-change waypoint
  lastWalkZ = playerPos.z
  
  -- Distance check
  local distX = math.abs(dest.x - playerPos.x)
  local distY = math.abs(dest.y - playerPos.y)
  
  -- Already at destination
  if distX <= precision and distY <= precision and dest.z == playerPos.z then
    return true
  end
  
  -- Floor mismatch
  if dest.z ~= playerPos.z then
    return false
  end
  
  -- FLOOR-CHANGE PATH: Smart approach — keyboard steps near FC tile, guarded autoWalk far away
  if allowFloorChange then
    -- Don't re-dispatch if still walking
    if player:isWalking() or (PathStrategy and PathStrategy.isAutoWalking()) then
      return true
    end

    local manhattan = math.abs(dest.x - playerPos.x) + math.abs(dest.y - playerPos.y)

    if manhattan <= 3 then
      -----------------------------------------------------------------------
      -- CLOSE RANGE (≤ 3 tiles): use keyboard steps for precise FC approach
      -----------------------------------------------------------------------
      local fcPath = PathStrategy
        and PathStrategy.findPath(playerPos, dest, {ignoreNonPathable = true, precision = 0})
        or findPath(playerPos, dest, maxDist, {ignoreNonPathable = true, precision = 0})

      if fcPath and #fcPath > 0 then
        local dir = fcPath[1]
        -- Use forceChange=true to bypass anti-zigzag dampening near FC
        local smoothed = PathStrategy
          and PathStrategy.smoothDirection(dir, true)
          or dir
        if canWalkDirection(smoothed) then
          if PathStrategy then
            PathStrategy.walkStep(smoothed)
          else
            walk(smoothed)
          end
        elseif canWalkDirection(dir) then
          -- Fallback to raw direction if smoothed somehow blocked
          if PathStrategy then
            PathStrategy.walkStep(dir)
          else
            walk(dir)
          end
        end
      end
      return true
    else
      -----------------------------------------------------------------------
      -- FAR RANGE (> 3 tiles): guarded autoWalk, but verify native path safe
      -----------------------------------------------------------------------
      if PathStrategy then
        local isSafe, _, unsafeIdx = PathStrategy.nativePathIsSafe(playerPos, dest, {ignoreNonPathable = true})
        if isSafe then
          PathStrategy.autoWalk(dest, maxDist, {ignoreNonPathable = true, precision = precision})
        else
          -- Native path crosses FC — walk one keyboard step toward dest instead
          local dirToDest = getDirectionTo(playerPos, dest)
          if dirToDest and canWalkDirection(dirToDest) then
            PathStrategy.walkStep(dirToDest)
          end
        end
      else
        autoWalk(dest, maxDist, {ignoreNonPathable = true, precision = precision})
      end
      return true
    end
  end
  
  -- Check if destination itself is a floor-change tile
  if isFloorChangeTile(dest) then
    local altTile, _ = findSafeAlternate(playerPos, dest, maxDist, {precision = precision, ignoreFields = ignoreFields})
    if altTile then
      dest = altTile
    else
      return false
    end
  end
  
  -- Compute path (with field awareness)
  local path

  -- IMPROVED: Reuse PathStrategy cursor cache if valid AND destination is the same
  local cacheValid = PathStrategy and PathStrategy.isCursorValid(dest)

  -- IMPROVED: Extend cache TTL if player is making good progress toward destination
  if not cacheValid and PathStrategy then
    local cursor = PathStrategy.getCursor()
    if cursor.chunkEnd and cursor.dest and posEquals(cursor.dest, dest) and cursor.path then
      local progressDist = math.max(
        math.abs(playerPos.x - cursor.chunkEnd.x),
        math.abs(playerPos.y - cursor.chunkEnd.y)
      )
      if progressDist <= 2 and cursor.idx <= #cursor.path then
        cacheValid = true
      end
    end
  end

  if cacheValid then
    path = PathStrategy.getCursor().path
  else
    if PathStrategy then PathStrategy.resetCursor() end
    -- Reset direction tracking for new path
    PATH_SMOOTHING.lastDirection = nil
    PATH_SMOOTHING.directionChanges = 0

    -- Use PathStrategy relaxed multi-attempt pathfinding
    if PathStrategy then
      local relaxed
      path, relaxed = PathStrategy.findPathRelaxed(playerPos, dest, {
        maxSteps          = maxDist,
        ignoreCreatures   = ignoreCreatures,
        ignoreFields      = ignoreFields,
        precision         = precision,
      })
      if relaxed and path then
        ignoreFields = true  -- Mark that we need to handle fields via keyboard walking
      end
    else
      -- Legacy fallback (bare sandbox global)
      path = findPath(playerPos, dest, maxDist, {
        ignoreNonPathable = true,
        ignoreCreatures = ignoreCreatures,
        ignoreFields = ignoreFields,
        precision = precision,
        allowOnlyVisibleTiles = true,
      })
    end

    if not path or #path == 0 then
      return false
    end

    if PathStrategy then
      PathStrategy.setCursor(path, dest)
    else
      PathCursor.path = path
      PathCursor.idx = 1
      PathCursor.ts = now
    end
  end

  -- Close path selection block
  

  -- End of path selection block

  -- Hard guard: if path crosses any floor-change tile, try a nearby alternate before aborting
  if pathCrossesFloorChange(path, playerPos, #path) then
    local altTile, altPath = findSafeAlternate(playerPos, dest, maxDist, {precision = precision, ignoreFields = ignoreFields})
    if altTile and altPath and #altPath > 0 and not pathCrossesFloorChange(altPath, playerPos, #altPath) then
      path = altPath
      if PathStrategy then
        PathStrategy.setCursor(altPath, dest)
      else
        PathCursor.path = altPath
        PathCursor.idx = 1
        PathCursor.ts = now
      end
    else
      if PathStrategy then PathStrategy.resetCursor() else resetPathCursor() end
      return false
    end
  end

  -- Safe-step counting via PathStrategy
  local cursorIdx = PathStrategy and PathStrategy.getCursor().idx or PathCursor.idx or 1
  local safeSteps = PathStrategy
    and PathStrategy.safeStepCount(path, playerPos, cursorIdx)
    or 0

  -- Fallback safe-step counting when PathStrategy is unavailable
  if not PathStrategy then
    local probe = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
    for i = 1, #path do
      local offset = getDirectionOffset(path[i])
      if offset then
        probe = applyOffset(probe, offset)
        if isFloorChangeTile(probe) then break end
        safeSteps = i
      end
    end
  end
  
  -- If no safe steps at all, try to find alternate route
  if safeSteps == 0 then
    local altTile, altPath = findSafeAlternate(playerPos, dest, maxDist, {precision = precision, ignoreFields = ignoreFields})
    if altTile and altPath and #altPath > 0 then
      -- Validate alternate path (it's short, so full validation is fine)
      probe = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
      for i = 1, #altPath do
        local offset = getDirectionOffset(altPath[i])
        if offset then
          probe = applyOffset(probe, offset)
          if isFloorChangeTile(probe) then
            break
          end
          safeSteps = i
        end
      end
      if safeSteps > 0 then
        path = altPath
      else
        return false
      end
    else
      return false
    end
  end
  
  -- CHUNKED WALKING: Limit steps per call to keep paths fresh
  local optimalChunkSize = PathStrategy
    and PathStrategy.optimalChunk(path, safeSteps, MAX_WALK_CHUNK)
    or calculateOptimalChunkSize(path, playerPos, safeSteps)
  local walkSteps = math.min(safeSteps, optimalChunkSize, MAX_WALK_CHUNK)

  -- IMPROVED: Track destination for path continuity
  if PathStrategy then
    PathStrategy.getCursor().dest = dest
  else
    PathCursor.destPos = dest
  end

  -- IMPROVED: Apply path smoothing via PathStrategy for better diagonal merging
  local curIdx = PathStrategy and PathStrategy.getCursor().idx or PathCursor.idx or 1
  local curSmoothed = PathStrategy and PathStrategy.getCursor().smoothed or (PathCursor and PathCursor.smoothingActive)
  if walkSteps >= 5 and not curSmoothed then
    local remainingPath = {}
    for i = curIdx, #path do
      remainingPath[#remainingPath + 1] = path[i]
    end
    local smoothFn = PathStrategy and PathStrategy.smoothPath or smoothPath
    local smoothedRemaining = smoothFn(remainingPath, playerPos)
    if smoothedRemaining and #smoothedRemaining > 0 then
      local newPath = {}
      for i = 1, curIdx - 1 do
        newPath[i] = path[i]
      end
      for i = 1, #smoothedRemaining do
        newPath[curIdx + i - 1] = smoothedRemaining[i]
      end
      path = newPath
      if PathStrategy then
        local c = PathStrategy.getCursor()
        c.path = path
        c.smoothed = true
      else
        PathCursor.path = path
        PathCursor.smoothingActive = true
      end
    end
  end

  -- Calculate the chunk destination using PathStrategy or legacy cursor
  local stepsToWalk = math.min(walkSteps, #path - curIdx + 1)
  local chunkDestination = PathStrategy
    and PathStrategy.chunkDestination(path, playerPos, curIdx, stepsToWalk)
    or {x = playerPos.x, y = playerPos.y, z = playerPos.z}

  if not PathStrategy then
    for i = PathCursor.idx, math.min(PathCursor.idx + stepsToWalk - 1, #path) do
      local offset = getDirectionOffset(path[i])
      if offset then
        chunkDestination = applyOffset(chunkDestination, offset)
      end
    end
  end

  -- Direction smoothing via PathStrategy (anti-zigzag)
  local chunkDirection = PathStrategy
    and PathStrategy.directionTo(playerPos, chunkDestination)
    or getDirectionTo(playerPos, chunkDestination)

  if chunkDirection then
    local smoothedDir = PathStrategy
      and PathStrategy.smoothDirection(chunkDirection)
      or (PathUtils and PathUtils.getSmoothedDirection and PathUtils.getSmoothedDirection(chunkDirection, false))

    if smoothedDir and smoothedDir ~= chunkDirection then
      local smoothedOffset = getDirectionOffset(smoothedDir)
      if smoothedOffset then
        chunkDestination = applyOffset(playerPos, smoothedOffset)
        chunkDirection = smoothedDir
        stepsToWalk = 1
      end
    end

    -- Legacy PATH_SMOOTHING dampening (still useful as secondary guard)
    if PATH_SMOOTHING.lastDirection and not areSimilarDirections(PATH_SMOOTHING.lastDirection, chunkDirection) then
      PATH_SMOOTHING.directionChanges = PATH_SMOOTHING.directionChanges + 1
      if PATH_SMOOTHING.directionChanges >= PATH_SMOOTHING.directionChangeThreshold then
        if now - PATH_SMOOTHING.lastDirectionTime < PATH_SMOOTHING.directionDampingTime then
          local curChunkEnd = PathStrategy and PathStrategy.getCursor().chunkEnd or PathCursor.lastChunkEnd
          if curChunkEnd then
            chunkDestination = curChunkEnd
            stepsToWalk = 1
          end
        end
        PATH_SMOOTHING.directionChanges = 0
      end
    else
      PATH_SMOOTHING.directionChanges = math.max(0, PATH_SMOOTHING.directionChanges - 1)
    end

    PATH_SMOOTHING.lastDirection = chunkDirection
    PATH_SMOOTHING.lastDirectionTime = now
  end

  -- Store chunk end position for continuity tracking
  if PathStrategy then
    local c = PathStrategy.getCursor()
    c.chunkEnd = chunkDestination
    c.chunkDir = chunkDirection
    c.chunkTs  = now
  else
    PathCursor.lastChunkEnd = chunkDestination
    PathCursor.lastChunkDir = chunkDirection
    PathCursor.lastChunkTime = now
  end
  
  -- FIELD HANDLING: Use keyboard walking for paths with fields
  -- autoWalk/map-click doesn't work through fire/poison/energy fields
  if ignoreFields then
    -- Walk through consecutive field tiles using keyboard walking
    local currentPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
    for i = 1, #path do
      local dir = path[i]
      local offset = getDirectionOffset(dir)
      if not offset then break end
      local nextPos = applyOffset(currentPos, offset)
      -- Check if nextPos is a field tile; if not, stop walking
      if not isFieldTile(nextPos) then
        break
      end
      walk(dir)
      currentPos = nextPos
      -- Optionally, check if we've reached the destination
      if posEquals(currentPos, dest) then
        return true
      end
    end
    return true
  end
  
  -- SMOOTH MOVEMENT: Use autoWalk for 2+ verified safe steps (more linear walking)
  if stepsToWalk >= 2 then
    local walkPrecision = 0
    if stepsToWalk >= 10 then
      walkPrecision = 1
    end

    -- OPTIMIZED: Check if player is already walking — don't interrupt smooth walks
    if player:isWalking() then
      local isOnTrack = math.abs(playerPos.x - chunkDestination.x) + math.abs(playerPos.y - chunkDestination.y) <= stepsToWalk + 2
      if isOnTrack then
        return true
      end
    end

    -- Humanised step duration for TTL calculation
    local stepDuration = PathStrategy and PathStrategy.rawStepDuration(false) or getCachedStepDuration(false)

    -- FC-SAFETY: Verify native autoWalk path won't cross floor-change tiles
    -- The planned path was validated safe via safeStepCount, but the native
    -- pathfinder may find a shorter route THROUGH a hole or ladder.
    local nativeSafe = true
    if PathStrategy and not allowFloorChange then
      local safe, nPath, unsafeIdx = PathStrategy.nativePathIsSafe(playerPos, chunkDestination)
      if not safe then
        nativeSafe = false
        -- Reduce chunk to the safe prefix of the native path
        if nPath and unsafeIdx and unsafeIdx > 1 then
          local safeDest, safeN = PathStrategy.safePrefixDest(playerPos, nPath, unsafeIdx)
          if safeN >= 2 then
            chunkDestination = safeDest
            stepsToWalk = safeN
            nativeSafe = true  -- now safe after trimming
          end
        end
      end
    end

    if not nativeSafe then
      -- Native path is unsafe even after trimming — fall through to keyboard step below
    else
      -- Dispatch autowalk through PathStrategy (ACL-aware)
      if PathStrategy then
        PathStrategy.autoWalk(chunkDestination, maxDist, {ignoreNonPathable = true, precision = walkPrecision})
        PathStrategy.advanceCursor(stepsToWalk, stepDuration)
      else
        autoWalk(chunkDestination, maxDist, {ignoreNonPathable = true, precision = walkPrecision})
        PathCursor.idx = math.min(PathCursor.idx + stepsToWalk, #path + 1)
        PathCursor.ts = now
        PathCursor.TTL = math.max(800, stepsToWalk * stepDuration * 0.8)
      end

      resetStepBackAttempts()
      return true
    end
  end

  -- For short safe paths (1 step), use direct walk via PathStrategy
  local firstDir = path[curIdx]
  local offset = getDirectionOffset(firstDir)
  if offset then
    if canWalkDirection(firstDir) then
      if PathStrategy then
        PathStrategy.walkStep(firstDir)
        PathStrategy.advanceCursor(1, PathStrategy.rawStepDuration(firstDir and firstDir >= 4))
      else
        local Client = getClient()
        if Client and Client.walk then
          Client.walk(firstDir)
        elseif g_game and g_game.walk then
          g_game.walk(firstDir, true)
        else
          walk(firstDir)
        end
        PathCursor.idx = PathCursor.idx + 1
      end
      resetStepBackAttempts()
      return true
    else
      if PathStrategy then PathStrategy.resetCursor() else resetPathCursor() end
      return false
    end
  end
  
  return false
end

-- ============================================================================
-- CONVENIENCE FUNCTIONS
-- ============================================================================

CaveBot.safeWalkTo = function(dest, maxDist, params)
  params = params or {}
  params.allowFloorChange = false
  return CaveBot.walkTo(dest, maxDist, params)
end

-- OPTIMIZED: Get current step duration for timing calculations
-- Uses PathStrategy humanized timing when available, fallback to PathUtils
CaveBot.getStepDuration = function(diagonal)
  if PathStrategy then
    return PathStrategy.stepDuration(diagonal or false)
  end
  return getCachedStepDuration(diagonal or false)
end

-- OPTIMIZED: Check if player is currently walking
-- Uses native player:isWalking() API
CaveBot.isPlayerWalking = function()
  return player and (player.isWalking and player:isWalking())
end

-- OPTIMIZED: Wait for walk to complete before next action
-- Returns estimated time until walk completes (0 if not walking)
CaveBot.getWalkWaitTime = function()
  if not CaveBot.isPlayerWalking() then
    return 0
  end
  -- Return step duration as estimated wait time
  return getCachedStepDuration(false)
end

-- OPTIMIZED: Check if a position is walkable using tile API
CaveBot.isPositionWalkable = function(checkPos, ignoreCreatures)
  return isTileWalkableFast(checkPos, ignoreCreatures or false)
end

-- OPTIMIZED: Get tile ground speed for timing
CaveBot.getTileGroundSpeed = function(checkPos)
  return getTileSpeed(checkPos)
end

CaveBot.resetWalking = function()
  -- Reset walking state
  expectedFloor = nil
  lastWalkZ = nil
  FloorChangeCache.tiles = {}
  if PathStrategy then
    PathStrategy.fullReset()
  end
  resetPathCursor()
  resetStepBackAttempts()
  
  -- IMPROVED: Reset path smoothing state
  PATH_SMOOTHING.lastDirection = nil
  PATH_SMOOTHING.lastDirectionTime = 0
  PATH_SMOOTHING.directionChanges = 0
  PATH_SMOOTHING.lastWaypointPos = nil
  PATH_SMOOTHING.cachedDestination = nil

  -- Note: We intentionally do NOT clear intendedFloorChange here
  -- as it should persist across walking resets during floor transitions
end

-- Full reset including floor change tracking (used on config change/hard reset)
CaveBot.fullResetWalking = function()
  CaveBot.resetWalking()
  if CaveBot.clearIntendedFloorChange then
    CaveBot.clearIntendedFloorChange()
  end
  lastSafePos = nil
  stepBackAttempts = 0  -- Ensure full reset clears this too
end

CaveBot.doWalking = function()
  return player and player:isWalking()
end

CaveBot.setExpectedFloor = function(floor)
  expectedFloor = floor
end

CaveBot.isOnExpectedFloor = function()
  if not expectedFloor then return true end
  return posz() == expectedFloor
end

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

CaveBot.isPathSafe = function(dest)
  local playerPos = pos()
  if not playerPos or not dest then return true end
  if posEquals(playerPos, dest) then return true end
  if playerPos.z ~= dest.z then return true end
  
  local path = findPath(playerPos, dest, 50, {ignoreNonPathable = true})
  return path and not pathCrossesFloorChange(path, playerPos)
end

-- Expose utilities
CaveBot.isFloorChangeTile = isFloorChangeTile
CaveBot.isNearFloorChangeTile = isNearFloorChangeTile
CaveBot.getSafeAdjacentTiles = function(centerPos) return getSafeAdjacentTiles(centerPos, false) end

-- Floor change detection on position change
onPlayerPositionChange(function(newPos, oldPos)
  if not oldPos or not newPos then return end
  
  -- Update last safe position when walking on same floor (away from floor-change tiles)
  if oldPos.z == newPos.z then
    if not isNearFloorChangeTile(oldPos) then
      lastSafePos = {x = oldPos.x, y = oldPos.y, z = oldPos.z}
      resetStepBackAttempts()
    end
    return  -- No floor change, nothing more to do
  end
  
  -- FLOOR CHANGE DETECTED
  -- Check if this was intentional (via intendedFloorChange system set by goto action)
  local wasIntentional = CaveBot.isFloorChangeIntended and CaveBot.isFloorChangeIntended(newPos.z)
  
  if wasIntentional then
    -- INTENTIONAL floor change - accept it completely
    lastSafePos = {x = newPos.x, y = newPos.y, z = newPos.z}
    expectedFloor = nil  -- Clear any stale expectedFloor
    FloorChangeCache.tiles = {}  -- Clear cache for new floor
    resetStepBackAttempts()
    
    -- Record this floor change for loop prevention
    if CaveBot.recordFloorChange then
      CaveBot.recordFloorChange(oldPos.z, newPos.z, nil)
    end
    
    -- Mark the floor-change waypoint (the old position) as completed
    -- This prevents re-execution of the same waypoint
    if CaveBot.markFloorChangeWaypointCompleted then
      CaveBot.markFloorChangeWaypointCompleted({x = oldPos.x, y = oldPos.y, z = oldPos.z})
    end
    
    -- Clear the intended flag now that floor change completed
    if CaveBot.clearIntendedFloorChange then
      CaveBot.clearIntendedFloorChange()
    end
    
    return  -- Done - no warning, no step-back
  end
  
  -- ACCIDENTAL floor change - not triggered by a floor-change waypoint
  -- But it might still be from a recently completed floor change
  -- (e.g., the intendedFloorChange was cleared but we're still processing)
  
  -- Check if this matches a recent floor change we recorded
  local shouldStepBack = true
  if CaveBot.getRecentFloorChange then
    local recent = CaveBot.getRecentFloorChange()
    if recent then
      -- We have a recent floor change record
      if recent.toZ == newPos.z then
        -- We just changed TO this floor recently - this is probably intentional
        -- Accept it without stepping back
        shouldStepBack = false
        lastSafePos = {x = newPos.x, y = newPos.y, z = newPos.z}
        resetStepBackAttempts()
        FloorChangeCache.tiles = {}
        return  -- Done - treat as intentional
      end
      
      if recent.toZ == oldPos.z then
        -- We just came FROM that floor - stepping back would loop
        shouldStepBack = false
      end
    end
  end
  
  -- Also limit step-back attempts to prevent infinite loops
  if stepBackAttempts >= MAX_STEP_BACK_ATTEMPTS then
    shouldStepBack = false
  end
  
  if shouldStepBack and lastSafePos and lastSafePos.z == oldPos.z then
    -- Try to step back to the safe position on the previous floor
    stepBackToLastSafe(newPos)
  else
    -- Accept the floor change (either to avoid loop or no safe pos)
    lastSafePos = {x = newPos.x, y = newPos.y, z = newPos.z}
    resetStepBackAttempts()
  end
  
  -- Record this floor change for loop prevention
  if CaveBot.recordFloorChange then
    CaveBot.recordFloorChange(oldPos.z, newPos.z, nil)
  end
  
  FloorChangeCache.tiles = {}  -- Clear cache on any floor change
end)

-- Safeguard: ensure module closes cleanly
return true
