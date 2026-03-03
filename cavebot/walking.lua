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
  - Sole direction smoothing via PathStrategy.smoothDirection() (DirectionGuard)
  - 3-entry ring buffer with 150ms opposite rejection
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

-- Floor change tile cache (for resetWalking)
local FloorChangeCache = {
  tiles = {},
  lastUpdate = 0,
}

-- Floor-change handling throttle (reduce repeated work on rapid z-changes)
local FLOOR_CHANGE_HANDLE_DEFAULT = 200  -- ms, internal safe default
local floorChangeThrottle = {
  lastUnintended = 0,
  lastCacheReset = 0
}

local function getFloorChangeHandleDelay()
  local delay = FLOOR_CHANGE_HANDLE_DEFAULT
  if storage and storage.cavebot and storage.cavebot.walking then
    local v = tonumber(storage.cavebot.walking.floorChangeDelay)
    if v and v >= 0 then
      delay = v
    end
  end
  return delay
end

local function resetFloorChangeCacheThrottled()
  local delay = getFloorChangeHandleDelay()
  if now - floorChangeThrottle.lastCacheReset >= delay then
    if FloorChangeCache then
      FloorChangeCache.tiles = {}
    end
    floorChangeThrottle.lastCacheReset = now
  end
end

-- Nudge anti-oscillation: avoid repeating same direction
local lastNudgeDir = nil
local lastNudgeTime = 0

-- OPTIMIZED: Use native API limits for best performance
local MAX_PATHFIND_DIST = 50   -- OTClient A* limit is ~50-127 tiles

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
-- DIRECTION UTILITIES
-- ============================================================================

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

-- ============================================================================
-- DIRECTION UTILITIES (Use PathUtils where possible)
-- ============================================================================

-- Use Directions constant module (DRY: SSoT is constants/directions.lua)
local Dirs = Directions
local DIR_TO_OFFSET = Directions.DIR_TO_OFFSET

local ADJACENT_OFFSETS = Directions.ADJACENT_OFFSETS

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
-- FLOOR-CHANGE & FIELD DETECTION (delegates to PathUtils — loaded in Phase 3)
-- ============================================================================

local function isFloorChangeTile(tilePos)
  if not PathUtils then return false end
  return PathUtils.isFloorChangeTile(tilePos)
end

local function isFieldTile(tilePos)
  if not PathUtils then return false end
  return PathUtils.isFieldTile(tilePos)
end

local function isFloorChangeTileFast(tilePos)
  if not PathUtils then return false end
  if PathUtils.isFloorChangeTileFast then
    return PathUtils.isFloorChangeTileFast(tilePos)
  end
  return isFloorChangeTile(tilePos)
end

-- ============================================================================
-- KEYBOARD NUDGE (fallback when pathfinding fails)
-- ============================================================================

-- Adjacent directions lookup derived from Directions.ADJACENT (DRY).
-- Flattened to ordered arrays so tryKeyboardNudge can iterate left/right.
local ADJACENT_DIRS = {}
if Directions and Directions.ADJACENT then
  for dir, neighbours in pairs(Directions.ADJACENT) do
    local arr = {}
    for nd, _ in pairs(neighbours) do arr[#arr + 1] = nd end
    ADJACENT_DIRS[dir] = arr
  end
end

-- Keyboard-step nudge: when pathfinding fails, walk one step toward the
-- destination using arrow-key movement.  Tries the direct direction first,
-- then two adjacent directions.  Returns true if a step was taken.
-- @param playerPos table {x,y,z}
-- @param dest      table {x,y,z}
-- @return "nudge" if a step was dispatched, false otherwise
local function tryKeyboardNudge(playerPos, dest)
  if not playerPos or not dest then return false end
  if player:isWalking() then return false end

  local dir = getDirectionTo(playerPos, dest)
  if dir == nil then return false end

  -- Build candidate list: direct → adjacent-left → adjacent-right
  local candidates = { dir }
  local adj = ADJACENT_DIRS[dir]
  if adj then
    candidates[2] = adj[1]
    candidates[3] = adj[2]
  end

  -- Anti-oscillation: if same direction was nudged recently, try adjacent first
  if dir == lastNudgeDir and now - lastNudgeTime < 500 and adj then
    candidates = { adj[1], adj[2], dir }
  end

  for _, d in ipairs(candidates) do
    if canWalkDirection(d) then
      local off = DIR_TO_OFFSET and DIR_TO_OFFSET[d]
      -- Extra guard: don't step onto a floor-change tile
      if off then
        local target = {x = playerPos.x + off.x, y = playerPos.y + off.y, z = playerPos.z}
        if not isFloorChangeTile(target) then
          if PathStrategy then
            PathStrategy.walkStep(d)
          else
            walk(d)
          end
          lastNudgeDir = d
          lastNudgeTime = now
          return "nudge"
        end
      end
    end
  end
  return false
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

-- Find alternate destination with safe path
-- Searches radius 1 + radius 2 (24 tiles), sorted by distance, capped at 4 pathfind calls
local function findSafeAlternate(playerPos, dest, maxDist, opts)
  opts = opts or {}
  local precision = opts.precision or 1
  local ignoreFields = opts.ignoreFields or false

  -- Generate candidates at radius 1 and radius 2 (perimeter tiles only)
  local candidates = {}
  for r = 1, 2 do
    for dx = -r, r do
      for dy = -r, r do
        if math.abs(dx) == r or math.abs(dy) == r then
          local candidate = {x = dest.x + dx, y = dest.y + dy, z = dest.z}
          if not posEquals(candidate, playerPos) and not isFloorChangeTile(candidate) then
            local dist = math.abs(dx) + math.abs(dy)
            candidates[#candidates + 1] = {pos = candidate, dist = dist}
          end
        end
      end
    end
  end

  -- Sort by Manhattan distance to original destination (prefer closer)
  table.sort(candidates, function(a, b) return a.dist < b.dist end)

  -- Check pathfinding for top 4 candidates (performance bound)
  local checked = 0
  for _, entry in ipairs(candidates) do
    if checked >= 4 then break end
    checked = checked + 1
    local path = findPath(playerPos, entry.pos, maxDist, {
      ignoreNonPathable = true,
      ignoreCreatures = true,
      ignoreFields = ignoreFields,
      precision = precision
    })
    if path and #path > 0 then
      return entry.pos, path
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
  TTL = 800,
  destPos = nil,
  smoothingActive = false,
}

local function resetPathCursor()
  PathCursor.path = nil
  PathCursor.idx = 1
  PathCursor.ts = 0
  PathCursor.destPos = nil
  PathCursor.smoothingActive = false
end

-- L-shape → diagonal lookup for path smoothing (two cardinals → one diagonal)
-- Uses OTClient direction constants. Both orderings map to the same diagonal.
local CARDINAL_PAIR_TO_DIAGONAL = {}
do
  local N, E, S, W = North or 0, East or 1, South or 2, West or 3
  local NE, SE, SW, NW = NorthEast or 4, SouthEast or 5, SouthWest or 6, NorthWest or 7
  CARDINAL_PAIR_TO_DIAGONAL[N * 8 + E] = NE
  CARDINAL_PAIR_TO_DIAGONAL[E * 8 + N] = NE
  CARDINAL_PAIR_TO_DIAGONAL[E * 8 + S] = SE
  CARDINAL_PAIR_TO_DIAGONAL[S * 8 + E] = SE
  CARDINAL_PAIR_TO_DIAGONAL[S * 8 + W] = SW
  CARDINAL_PAIR_TO_DIAGONAL[W * 8 + S] = SW
  CARDINAL_PAIR_TO_DIAGONAL[W * 8 + N] = NW
  CARDINAL_PAIR_TO_DIAGONAL[N * 8 + W] = NW
end

-- IMPROVED: Path smoothing function - removes unnecessary zig-zag movements
-- Two-pass: (1) L-shape to diagonal, (2) A→B→A zig-zag to diagonal
local function smoothPath(path, startPos)
  if not path or #path < 2 then return path end
  
  local smoothed = {}
  local curPos = {x = startPos.x, y = startPos.y, z = startPos.z}
  local i = 1
  local isCardinal = Directions and Directions.isCardinal or function(d) return d ~= nil and d <= 3 end
  
  while i <= #path do
    local dir = path[i]
    local offset = getDirectionOffset(dir)
    if not offset then 
      i = i + 1
    else
      local nextPos = applyOffset(curPos, offset)

      -- Pass 1: L-shape — two consecutive cardinals → one diagonal
      -- e.g., North + East → NorthEast (if diagonal tile is walkable)
      if i + 1 <= #path then
        local dir2 = path[i + 1]
        if isCardinal(dir) and isCardinal(dir2) and dir ~= dir2 then
          local diag = CARDINAL_PAIR_TO_DIAGONAL[dir * 8 + dir2]
          if diag then
            local diagOff = DIR_TO_OFFSET and DIR_TO_OFFSET[diag]
            if diagOff then
              local diagPos = applyOffset(curPos, diagOff)
              if not isFloorChangeTile(diagPos) then
                local Client = getClient()
                local tile = (Client and Client.getTile) and Client.getTile(diagPos) or (g_map and g_map.getTile(diagPos))
                if tile and tile:isWalkable() then
                  -- Validate cardinal legs (diagonal requires both to be walkable)
                  local off2 = getDirectionOffset(dir2)
                  local leg1 = nextPos  -- curPos + dir
                  local leg2 = off2 and applyOffset(curPos, off2)
                  local lt1 = leg1 and ((Client and Client.getTile) and Client.getTile(leg1) or (g_map and g_map.getTile(leg1)))
                  local lt2 = leg2 and ((Client and Client.getTile) and Client.getTile(leg2) or (g_map and g_map.getTile(leg2)))
                  if (lt1 and lt1:isWalkable()) and (lt2 and lt2:isWalkable()) then
                    smoothed[#smoothed + 1] = diag
                    curPos = diagPos
                    i = i + 2
                    goto continue_smooth
                  end
                end
              end
            end
          end
        end
      end

      -- Pass 2: A→B→A zig-zag → diagonal + A (3 steps → 2 steps)
      if i + 2 <= #path then
        local dir2 = path[i + 1]
        local dir3 = path[i + 2]
        if dir == dir3 and dir ~= dir2 then
          local offset2 = getDirectionOffset(dir2)
          if offset2 then
            local diagPos = applyOffset(curPos, {x = offset.x + offset2.x, y = offset.y + offset2.y})
            local diagonalDir = getDirectionTo(curPos, diagPos)
            if diagonalDir then
              local Client = getClient()
              local tile = (Client and Client.getTile) and Client.getTile(diagPos) or (g_map and g_map.getTile(diagPos))
              if tile and tile:isWalkable() and not isFloorChangeTile(diagPos) then
                -- Validate cardinal legs (diagonal requires both to be walkable)
                local legA = nextPos  -- curPos + dir (A direction)
                local legB = applyOffset(curPos, offset2)  -- curPos + dir2 (B direction)
                local ltA = (Client and Client.getTile) and Client.getTile(legA) or (g_map and g_map.getTile(legA))
                local ltB = (Client and Client.getTile) and Client.getTile(legB) or (g_map and g_map.getTile(legB))
                if (ltA and ltA:isWalkable()) and (ltB and ltB:isWalkable()) then
                  smoothed[#smoothed + 1] = diagonalDir
                  smoothed[#smoothed + 1] = dir
                  curPos = applyOffset(diagPos, offset)
                  i = i + 3
                  goto continue_smooth
                end
              end
            end
          end
        end
      end

      -- No pattern matched — keep original direction
      smoothed[#smoothed + 1] = dir
      curPos = nextPos
      i = i + 1
      ::continue_smooth::
    end
  end
  
  return #smoothed > 0 and smoothed or path
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
      -- Unintended floor change — accept it and let WaypointEngine find rescue WPs.
      lastSafePos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
      
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
  local totalDist = math.max(distX, distY)
  
  -- Already at destination
  if distX <= precision and distY <= precision and dest.z == playerPos.z then
    return true
  end
  
  -- Reset anti-zigzag dampening for short walks (quick direction changes needed)
  if totalDist <= 5 and PathStrategy and PathStrategy.resetDirectionState then
    PathStrategy.resetDirectionState()
  end
  
  -- Floor mismatch
  if dest.z ~= playerPos.z then
    return false
  end
  
  -- FLOOR-CHANGE PATH: Smart approach — keyboard steps near FC tile, guarded autoWalk far away
  if allowFloorChange then
    -- Don't re-dispatch if still walking
    if player:isWalking() or isAutoWalking() then
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

  if cacheValid then
    path = PathStrategy.getCursor().path
  else
    if PathStrategy then PathStrategy.resetCursor() end

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
      -- Pathfinding failed — try a single keyboard step toward the destination.
      -- This nudges the player into a new position where A* may succeed next tick.
      return tryKeyboardNudge(playerPos, dest)
    end

    if PathStrategy then
      PathStrategy.setCursor(path, dest)
      -- Smooth-once: convert L-shapes to diagonals at cursor creation time
      local smoothed = PathStrategy.smoothPath(path, playerPos)
      if smoothed and #smoothed > 0 and #smoothed <= #path then
        path = smoothed
        PathStrategy.getCursor().path = path
      end
    else
      PathCursor.path = path
      PathCursor.idx = 1
      PathCursor.ts = now
      -- Smooth-once for legacy cursor
      local legacySmoothed = smoothPath(path, playerPos)
      if legacySmoothed and #legacySmoothed > 0 and #legacySmoothed <= #path then
        path = legacySmoothed
        PathCursor.path = path
        PathCursor.smoothingActive = true
      end
    end
  end

  -- FC-aware walking: safeSteps counts walkable steps before the first
  -- floor-change tile. walkTo walks only that prefix, so the player makes
  -- partial progress instead of aborting the entire walk.
  -- (The old hard guard returned false here, preventing any progress.)

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
        return tryKeyboardNudge(playerPos, dest)
      end
    else
      return tryKeyboardNudge(playerPos, dest)
    end
  end
  
  -- PATH-FAITHFUL WALKING DISPATCH
  -- Short/complex paths (≤15 tiles): keyboard step (follows computed path exactly)
  -- Long straight paths (>15 tiles, low complexity): autoWalk with FC-safety verification

  local curIdx = PathStrategy and PathStrategy.getCursor().idx or PathCursor.idx or 1
  local remainingSteps = #path - curIdx + 1
  local stepsToWalk = math.min(safeSteps, remainingSteps)

  if stepsToWalk <= 0 then
    if PathStrategy then PathStrategy.resetCursor() else resetPathCursor() end
    return tryKeyboardNudge(playerPos, dest)
  end

  -- Track destination for path continuity
  if PathStrategy then
    PathStrategy.getCursor().dest = dest
  else
    PathCursor.destPos = dest
  end

  -- FIELD HANDLING: Use keyboard walking for paths with fields
  -- FIELD HANDLING: keyboard-walk through field tiles (autoWalk avoids them)
  -- Only intercept when the immediate next step IS a field tile; otherwise
  -- fall through to normal walking so non-field paths aren't blocked.
  if ignoreFields then
    local peekDir = path[curIdx]
    local peekOff = peekDir and getDirectionOffset(peekDir)
    if peekOff then
      local peekPos = applyOffset({x = playerPos.x, y = playerPos.y, z = playerPos.z}, peekOff)
      if isFieldTile(peekPos) then
        local currentPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
        local lastWalked = curIdx - 1
        for i = curIdx, #path do
          local dir = path[i]
          local offset = getDirectionOffset(dir)
          if not offset then break end
          local nextPos = applyOffset(currentPos, offset)
          if not isFieldTile(nextPos) then break end
          if isFloorChangeTile(nextPos) then break end
          walk(dir)
          currentPos = nextPos
          lastWalked = i
          if posEquals(currentPos, dest) then
            if PathStrategy then PathStrategy.resetCursor() else resetPathCursor() end
            return true
          end
        end
        -- Advance cursor past the walked field tiles only
        if PathStrategy then
          PathStrategy.getCursor().idx = lastWalked + 1
        else
          PathCursor.idx = lastWalked + 1
        end
        return true
      end
    end
    -- Next step is NOT a field tile — fall through to normal walking
  end

  -- Determine path complexity (direction changes in remaining path)
  local dirChanges = 0
  local prevDir = nil
  for i = curIdx, math.min(curIdx + stepsToWalk - 1, #path) do
    if prevDir and path[i] ~= prevDir then dirChanges = dirChanges + 1 end
    prevDir = path[i]
  end
  local complexity = stepsToWalk > 0 and (dirChanges / stepsToWalk) or 0

  -- ADAPTIVE CHUNK SIZING: scale by path complexity
  local adaptiveChunk = complexity < 0.15 and 40    -- straight corridor
                     or complexity < 0.35 and 25    -- moderate turns
                     or complexity < 0.55 and 15    -- complex
                     or 8                           -- very complex
  adaptiveChunk = math.min(adaptiveChunk, safeSteps, stepsToWalk)

  -- DISTANCE-AWARE DISPATCH: prefer autoWalk for smoother movement
  local useAutoWalk = false
  if stepsToWalk > 15 then
    useAutoWalk = complexity <= 0.60   -- long: allow more complex paths via autoWalk
  elseif stepsToWalk > 8 then
    useAutoWalk = complexity <= 0.45   -- medium: tighter threshold
  elseif stepsToWalk > 5 then
    useAutoWalk = complexity <= 0.30   -- short: prefer keyboard for accuracy
  end
  -- stepsToWalk ≤ 5: always keyboard

  if not useAutoWalk then
    -- KEYBOARD STEPPING with PIPELINING: dispatch up to 2 steps ahead for smoother movement.
    -- Pipelining is disabled near FC tiles or on sharp turns (>90° direction change).
    local dir = path[curIdx]
    if not dir then
      if PathStrategy then PathStrategy.resetCursor() else resetPathCursor() end
      return false
    end

    -- Apply direction smoothing (sole anti-zigzag via PathStrategy)
    local smoothedDir = PathStrategy and PathStrategy.smoothDirection(dir) or dir
    local walkDir = nil

    if canWalkDirection(smoothedDir) then
      walkDir = smoothedDir
    elseif smoothedDir ~= dir and canWalkDirection(dir) then
      walkDir = dir
    end

    if not walkDir then
      if PathStrategy then PathStrategy.resetCursor() else resetPathCursor() end
      return false
    end

    -- Dispatch first step
    if PathStrategy then
      PathStrategy.walkStep(walkDir)
      PathStrategy.advanceCursor(1, PathStrategy.rawStepDuration(walkDir and walkDir >= 4))
    else
      walk(walkDir)
      PathCursor.idx = PathCursor.idx + 1
    end
    resetStepBackAttempts()

    -- Pipeline second step: dispatch ahead if path has another step and it's safe
    local nextIdx = curIdx + 1
    if nextIdx <= #path and nextIdx <= curIdx + stepsToWalk - 1 then
      local nextDir = path[nextIdx]
      if nextDir then
        local nextOff = DIR_TO_OFFSET and DIR_TO_OFFSET[nextDir]
        local curOff = DIR_TO_OFFSET and DIR_TO_OFFSET[walkDir]
        -- Only pipeline if direction change is ≤ 90° (similar or same)
        local isSimilar = (nextDir == walkDir) or
          (PathStrategy and PathStrategy.isSimilar(nextDir, walkDir))
        -- Don't pipeline near floor-change tiles
        local nextSafe = true
        if nextOff and curOff then
          local stepPos = applyOffset(playerPos, curOff)
          local nextPos = applyOffset(stepPos, nextOff)
          if isFloorChangeTile(nextPos) or isFloorChangeTile(stepPos) then
            nextSafe = false
          end
        end
        if isSimilar and nextSafe and canWalkDirection(nextDir) then
          if PathStrategy then
            PathStrategy.walkStep(nextDir)
            PathStrategy.advanceCursor(1, PathStrategy.rawStepDuration(nextDir and nextDir >= 4))
          else
            walk(nextDir)
            PathCursor.idx = PathCursor.idx + 1
          end
        end
      end
    end

    return true
  end

  -- AUTOWALK: Long straight path — delegate to native pathfinder with FC verification
  local chunkSteps = math.min(stepsToWalk, adaptiveChunk)
  local chunkDest = PathStrategy
    and PathStrategy.chunkDestination(path, playerPos, curIdx, chunkSteps)
    or playerPos

  if not PathStrategy then
    local probe = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
    for i = PathCursor.idx, math.min(PathCursor.idx + chunkSteps - 1, #path) do
      local offset = getDirectionOffset(path[i])
      if offset then probe = applyOffset(probe, offset) end
    end
    chunkDest = probe
  end

  -- Don't interrupt if player is already walking toward chunk destination
  if player:isWalking() then
    local distToChunk = math.abs(playerPos.x - chunkDest.x) + math.abs(playerPos.y - chunkDest.y)
    if distToChunk <= chunkSteps + 2 then
      return true
    end
  end

  -- FC-SAFETY: Verify native autoWalk path won't cross floor-change tiles
  local nativeSafe = true
  if PathStrategy and not allowFloorChange then
    local safe, nPath, unsafeIdx = PathStrategy.nativePathIsSafe(playerPos, chunkDest)
    if not safe then
      nativeSafe = false
      if nPath and unsafeIdx and unsafeIdx > 1 then
        local safeDest, safeN = PathStrategy.safePrefixDest(playerPos, nPath, unsafeIdx)
        if safeN >= 2 then
          chunkDest = safeDest
          chunkSteps = safeN
          nativeSafe = true
        end
      end
    end
  end

  if not nativeSafe then
    -- Native path unsafe — fall back to keyboard step
    local dir = path[curIdx]
    if dir and canWalkDirection(dir) then
      if PathStrategy then
        PathStrategy.walkStep(dir)
        PathStrategy.advanceCursor(1, PathStrategy.rawStepDuration(dir and dir >= 4))
      else
        walk(dir)
        PathCursor.idx = PathCursor.idx + 1
      end
      resetStepBackAttempts()
      return true
    end
    if PathStrategy then PathStrategy.resetCursor() else resetPathCursor() end
    return false
  end

  -- Dispatch autoWalk
  local walkPrecision = chunkSteps >= 10 and 1 or 0
  local stepDuration = PathStrategy and PathStrategy.rawStepDuration(false) or getCachedStepDuration(false)
  if PathStrategy then
    PathStrategy.autoWalk(chunkDest, maxDist, {ignoreNonPathable = true, precision = walkPrecision})
    PathStrategy.advanceCursor(chunkSteps, stepDuration)
  else
    autoWalk(chunkDest, maxDist, {ignoreNonPathable = true, precision = walkPrecision})
    PathCursor.idx = math.min(PathCursor.idx + chunkSteps, #path + 1)
    PathCursor.ts = now
  end
  resetStepBackAttempts()
  return true
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
CaveBot.stopAutoWalk = stopAutoWalk
CaveBot.getSafeAdjacentTiles = function(centerPos) return getSafeAdjacentTiles(centerPos, false) end

-- Floor change detection on position change
onPlayerPositionChange(function(newPos, oldPos)
  if zChanging() then return end
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
    resetFloorChangeCacheThrottled()  -- Clear cache for new floor
    resetStepBackAttempts()
    
    -- Record this floor change for loop prevention
    if CaveBot.recordFloorChange then
      CaveBot.recordFloorChange(oldPos.z, newPos.z, nil)
    end
    
    -- Clear the intended flag now that floor change completed
    if CaveBot.clearIntendedFloorChange then
      CaveBot.clearIntendedFloorChange()
    end
    
    return  -- Done - no warning, no step-back
  end

  -- ACCIDENTAL floor change — accept it and let WaypointEngine handle recovery.
  -- Step-back was removed: it fought rescue floor-change waypoints that users place
  -- to handle accidental falls. The recovery system finds rescue WPs on the new floor.
  lastSafePos = {x = newPos.x, y = newPos.y, z = newPos.z}
  resetStepBackAttempts()
  
  -- Record this floor change for loop prevention
  if CaveBot.recordFloorChange then
    CaveBot.recordFloorChange(oldPos.z, newPos.z, nil)
  end
  
  resetFloorChangeCacheThrottled()  -- Clear cache on any floor change
end)

-- Safeguard: ensure module closes cleanly
return true
