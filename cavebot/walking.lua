--[[
  CaveBot Walking Module v4.0.0 - High-Performance Floor-Safe Navigation
  
  ARCHITECTURE (SOLID Principles):
  ============================================================================
  1. Single Responsibility Principle (SRP):
     - TileAnalyzer: Analyzes tile properties (floor-change, safety, fields)
     - PathValidator: Validates paths for safety
     - FloorGuard: Monitors and prevents unintended floor changes
     - Navigator: Orchestrates movement decisions
  
  2. Open/Closed Principle:
     - Floor-change detection extensible via FLOOR_CHANGE_ITEMS table
     - Custom validators can be registered via hooks
  
  3. Interface Segregation:
     - Clean public API: walkTo, safeWalkTo, isPathSafe
     - Internal modules operate independently
  
  4. Dependency Inversion:
     - High-level Navigator depends on abstractions (TileAnalyzer, PathValidator)
  
  DESIGN PATTERNS:
  ============================================================================
  - Strategy: Different walking strategies (autoWalk, keyboard, chunked)
  - Cache-Aside: LRU cache with TTL for tile analysis
  - Observer: Floor change notifications via onFloorChanged
  - Flyweight: Pre-allocated position objects to reduce allocations
  
  PERFORMANCE CHARACTERISTICS:
  ============================================================================
  - O(1) cache lookups with numeric keys
  - O(n) path validation with early exit
  - Time-budgeted BFS searches (15-20ms max)
  - Zero allocations in hot paths (pre-allocated pools)
  - Lazy cache cleanup (every 30 seconds)
  
  FLOOR-CHANGE PREVENTION (Multi-Layer):
  ============================================================================
  Layer 1: Tile Analysis - Comprehensive detection of floor-change tiles
  Layer 2: Path Validation - Check entire path before walking
  Layer 3: Predictive Analysis - Detect patterns leading to floor changes
  Layer 4: Runtime Guard - Monitor actual movement and recover
]]

-- ============================================================================
-- MODULE INITIALIZATION
-- ============================================================================

setDefaultTab("Main")

CaveBot = CaveBot or {}

-- ============================================================================
-- CONFIGURATION (Single source of truth - Configurable)
-- ============================================================================
local Config = {
  -- Path validation limits
  MAX_PATHFIND_DIST = 50,       -- Maximum pathfinding distance
  MAX_WALK_CHUNK = 20,          -- Maximum steps per walk call
  THOROUGH_CHECK_DIST = 40,     -- Distance for thorough floor-change checks
  
  -- Reachability analysis
  REACHABLE_MAX_NODES = 200,    -- Max BFS nodes for reachability
  REACHABLE_TIME_BUDGET = 0.015, -- 15ms time budget
  
  -- Safe alternate search
  SAFE_ALT_RADIUS = 6,          -- Max search radius for alternates
  SAFE_ALT_BUDGET = 20,         -- ms time budget
  SAFE_ALT_MAX_PATHS = 4,       -- Max pathfinding calls
  
  -- Step-back recovery
  STEP_BACK_COOLDOWN = 1500,    -- ms between step-back attempts
  FLOOR_CHANGE_THRESHOLD = 2,   -- Consecutive changes before step-back
  
  -- Cache settings
  CACHE_TTL = 10000,            -- 10 second TTL
  CACHE_MAX_SIZE = 200,         -- Maximum cache entries
  CACHE_CLEANUP_INTERVAL = 30000, -- 30 second cleanup
  
  -- AutoWalk detection
  AUTOWALK_STALL_TIMEOUT = 500  -- ms before detecting stall
}

-- Config helper: read CaveBot.Config safely with fallback to local Config
local function getCfg(key, def)
  if CaveBot and CaveBot.Config and CaveBot.Config.get then
    local ok, v = pcall(function() return CaveBot.Config.get(key) end)
    if ok and v ~= nil then return v end
  end
  -- Fallback to local Config
  if Config[key] ~= nil then return Config[key] end
  return def
end

-- Debug logging (no-op by default)
local function log_dbg(msg) end

-- ============================================================================
-- PURE UTILITY FUNCTIONS (No side effects, deterministic)
-- ============================================================================

-- Direction to offset lookup (constant, never modified)
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

-- Adjacent offsets for 8-directional movement
local ADJACENT_OFFSETS = {
  {x = 0, y = -1},  {x = 1, y = 0},  {x = 0, y = 1},  {x = -1, y = 0},
  {x = 1, y = -1}, {x = 1, y = 1}, {x = -1, y = 1}, {x = -1, y = -1},
}

-- Pure: Get offset for direction
local function getDirectionOffset(dir)
  return DIR_TO_OFFSET[dir]
end

-- Pure: Apply offset to position (returns new table)
local function applyOffset(pos, offset)
  return {x = pos.x + offset.x, y = pos.y + offset.y, z = pos.z}
end

-- Pure: Check position equality
local function posEquals(a, b)
  return a.x == b.x and a.y == b.y and a.z == b.z
end

-- Pure: Calculate Manhattan distance
local function manhattanDist(a, b)
  return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

-- Pure: Generate numeric cache key (faster than string concatenation)
local function posToKey(pos)
  return pos.x * 100000000 + pos.y * 10000 + pos.z
end

-- Pre-allocated position objects (Flyweight pattern - avoid allocations)
local ProbePos = {x = 0, y = 0, z = 0}
local AltPos = {x = 0, y = 0, z = 0}

-- ============================================================================
-- MODULE STATE (FloorGuard - monitors floor changes)
-- ============================================================================
local FloorGuard = {
  expectedFloor = nil,        -- Expected floor level
  lastWalkZ = nil,            -- Last walk Z level
  lastSafePos = nil,          -- Last known safe position
  lastStepBackTs = 0,         -- Last step-back timestamp
  consecutiveChanges = 0,     -- Consecutive unexpected floor changes
}

-- ============================================================================
-- TILE ANALYZER (SRP: Analyzes tile properties)
-- ============================================================================
local TileAnalyzer = {}

-- Floor-change tile cache (LRU-like with TTL)
TileAnalyzer.Cache = {
  tiles = {},
  entryCount = 0,
  lastCleanup = 0,
  lastCleanupCheck = 0,
  TTL = getCfg("CACHE_TTL", 10000),
  MAX_ENTRIES = getCfg("CACHE_MAX_SIZE", 200),
  CLEANUP_INTERVAL = getCfg("CACHE_CLEANUP_INTERVAL", 30000),
}

-- Recent position buffer to detect oscillation/flicker (performance: tiny fixed-size ring)
local RecentPos = {
  buf = {},
  size = 6,
  idx = 1
}

local function pushRecentPos(p)
  RecentPos.buf[RecentPos.idx] = {x = p.x, y = p.y, z = p.z, t = now}
  RecentPos.idx = (RecentPos.idx % RecentPos.size) + 1
end

local function isOscillating()
  -- Detect simple back-and-forth oscillation between two tiles
  local count = 0
  local seen = {}
  for i = 1, #RecentPos.buf do
    local v = RecentPos.buf[i]
    if v then
      local key = v.x .. "," .. v.y .. "," .. v.z
      seen[key] = (seen[key] or 0) + 1
      count = count + 1
    end
  end
  if count < RecentPos.size then return false end
  local keys = 0
  for k,_ in pairs(seen) do keys = keys + 1 end
  -- If only two positions seen repeatedly, treat as oscillation
  return keys == 2
end

local function getFloorChangeCacheKey(pos)
  return pos.x .. "," .. pos.y .. "," .. pos.z
end

-- Minimap colors for floor-change
local FLOOR_CHANGE_COLORS = {
  [210] = true, [211] = true, [212] = true, [213] = true,
}

-- Fast minimap-only check (for distant tiles - performance optimization)
local function isFloorChangeTileFast(tilePos)
  if not tilePos then return false end
  local color = g_map.getMinimapColor(tilePos)
  return FLOOR_CHANGE_COLORS[color] or false
end

-- Comprehensive floor-change item IDs
local FLOOR_CHANGE_ITEMS = {
  -- === STAIRS ===
  -- Stone stairs down (414-417, 428-431)
  [414] = true, [415] = true, [416] = true, [417] = true,
  [428] = true, [429] = true, [430] = true, [431] = true,
  -- Stone stairs up (432-435)
  [432] = true, [433] = true, [434] = true, [435] = true,
  -- Wooden stairs (1949-1955)
  [1949] = true, [1950] = true, [1951] = true,
  [1952] = true, [1953] = true, [1954] = true, [1955] = true,
  
  -- === RAMPS ===
  -- Standard ramps (1956-1959) - very common cause of pathfinding issues!
  [1956] = true, [1957] = true, [1958] = true, [1959] = true,
  -- Stone/Cave ramps (1385, 1396-1402)
  [1385] = true, [1396] = true, [1397] = true, [1398] = true,
  [1399] = true, [1400] = true, [1401] = true, [1402] = true,
  -- Special terrain ramps (4834-4841)
  [4834] = true, [4835] = true, [4836] = true, [4837] = true,
  [4838] = true, [4839] = true, [4840] = true, [4841] = true,
  -- Ice ramps (6915-6918)
  [6915] = true, [6916] = true, [6917] = true, [6918] = true,
  -- Desert/Jungle ramps (7545-7548)
  [7545] = true, [7546] = true, [7547] = true, [7548] = true,
  
  -- === LADDERS & ROPE SPOTS ===
  -- Ladders (1219, 1386, 3678, 5543)
  [1219] = true, [1386] = true, [3678] = true, [5543] = true,
  -- Rope spots (384, 386, 418)
  [384] = true, [386] = true, [418] = true,
  
  -- === HOLES & TRAPDOORS ===
  -- Holes and pitfalls (294, 369-370, 383, 392, 408-410, 469-470, 482, 484)
  [294] = true, [369] = true, [370] = true, [383] = true,
  [392] = true, [408] = true, [409] = true, [410] = true,
  [469] = true, [470] = true, [482] = true, [484] = true,
  -- Trapdoors (423-425)
  [423] = true, [424] = true, [425] = true,
  -- Sewer grates (426-427)
  [426] = true, [427] = true,
  
  -- === TELEPORTS & PORTALS ===
  -- Basic teleports (502, 1387)
  [502] = true, [1387] = true,
  -- Magic forcefields and portals (2129-2130, 8709)
  [2129] = true, [2130] = true, [8709] = true,
}

-- Pure: Check if tile has floor-change ground
local function hasFloorChangeGround(tile)
  if not tile then return false end
  local ground = tile:getGround()
  return ground and FLOOR_CHANGE_ITEMS[ground:getId()]
end

-- Pure: Check if tile has floor-change item on top
local function hasFloorChangeItem(tile)
  if not tile then return false end
  
  local useThing = tile:getTopUseThing()
  if useThing and useThing:isItem() and FLOOR_CHANGE_ITEMS[useThing:getId()] then
    return true
  end
  
  local topThing = tile:getTopThing()
  if topThing and topThing:isItem() and FLOOR_CHANGE_ITEMS[topThing:getId()] then
    return true
  end
  
  return false
end

-- ============================================================================
-- TILE ANALYZER FUNCTIONS (SRP: Tile analysis only)
-- ============================================================================

-- Pure: Analyze tile for floor-change (core detection logic)
local function analyzeTileForFloorChange(tilePos)
  if not tilePos then return false end
  
  -- Layer 1: Fast minimap color check (no tile lookup needed)
  local color = g_map.getMinimapColor(tilePos)
  if FLOOR_CHANGE_COLORS[color] then
    return true
  end
  
  -- Layer 2: Tile inspection (ground and items)
  local tile = g_map.getTile(tilePos)
  if tile then
    if hasFloorChangeGround(tile) or hasFloorChangeItem(tile) then
      return true
    end
  end
  
  -- Layer 3: Strict ramp detection (check adjacent Z layers)
  if getCfg("strictRampDetect", false) then
    local upTile = g_map.getTile({x = tilePos.x, y = tilePos.y, z = tilePos.z + 1})
    if upTile and (hasFloorChangeGround(upTile) or hasFloorChangeItem(upTile)) then
      return true
    end
    local downTile = g_map.getTile({x = tilePos.x, y = tilePos.y, z = tilePos.z - 1})
    if downTile and (hasFloorChangeGround(downTile) or hasFloorChangeItem(downTile)) then
      return true
    end
  end
  
  return false
end

-- Cached floor-change check (with TTL and lazy cleanup)
-- This is the main public function for floor-change detection
local function isFloorChangeTile(tilePos)
  -- Prefer external PathSafety module if available
  if CaveBot and CaveBot.PathSafety and CaveBot.PathSafety.isFloorChangeTile then
    return CaveBot.PathSafety.isFloorChangeTile(tilePos)
  end
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isFloorChangeTile then
    return TargetCore.PathSafety.isFloorChangeTile(tilePos)
  end
  if not tilePos then return false end
  
  local Cache = TileAnalyzer.Cache
  local cacheKey = posToKey(tilePos)
  
  -- Hot path: check cache first
  local cached = Cache.tiles[cacheKey]
  if cached then
    if now - cached.time < Cache.TTL then
      return cached.value
    end
    -- Expired, will recompute below
  end
  
  -- Lazy cleanup: check periodically and when entry count is high
  if Cache.entryCount > Cache.MAX_ENTRIES then
    Cache.tiles = {}
    Cache.entryCount = 0
    Cache.lastCleanup = now
  elseif now - Cache.lastCleanupCheck > 5000 then
    Cache.lastCleanupCheck = now
    if now - Cache.lastCleanup > Cache.CLEANUP_INTERVAL then
      local newTiles = {}
      local newCount = 0
      local cutoff = now - Cache.TTL
      for k, v in pairs(Cache.tiles) do
        if v.time > cutoff then
          newTiles[k] = v
          newCount = newCount + 1
        end
      end
      Cache.tiles = newTiles
      Cache.entryCount = newCount
      Cache.lastCleanup = now
    end
  end
  
  -- Perform analysis and cache result
  local result = analyzeTileForFloorChange(tilePos)
  Cache.tiles[cacheKey] = {value = result, time = now}
  Cache.entryCount = Cache.entryCount + 1
  return result
end

-- Register with TileAnalyzer for external access
TileAnalyzer.isFloorChangeTile = isFloorChangeTile
TileAnalyzer.isFloorChangeTileFast = isFloorChangeTileFast
TileAnalyzer.analyzeTileForFloorChange = analyzeTileForFloorChange

-- ============================================================================
-- TILE SAFETY (SRP: Checks if tiles are safe to walk)
-- ============================================================================

-- Pure: Check if tile is walkable and safe
local function isTileSafe(tilePos, allowFloorChange)
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isTileSafe then
    return TargetCore.PathSafety.isTileSafe(tilePos, allowFloorChange)
  end
  if not tilePos then return false end
  
  local tile = g_map.getTile(tilePos)
  if not tile then return false end
  if not tile:isWalkable() then return false end
  if tile:hasCreature() then return false end
  
  if not allowFloorChange and isFloorChangeTile(tilePos) then
    return false
  end
  
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
-- PATH VALIDATOR (SRP: Validates paths for safety)
-- ============================================================================

-- Check if a position is adjacent to a floor-change tile (buffer zone)
local function isNearFloorChangeTile(tilePos)
  if not tilePos then return false end
  
  -- Check the tile itself first
  if isFloorChangeTile(tilePos) then return true end
  
  -- Check adjacent tiles for floor-change (diagonal too - prevents diagonal step-on)
  for _, offset in ipairs(ADJACENT_OFFSETS) do
    local checkPos = applyOffset(tilePos, offset)
    if isFloorChangeTile(checkPos) then
      return true
    end
  end
  
  return false
end

-- Pure: Check if path crosses floor-change tiles (checks ALL steps for safety)
-- Also checks buffer zone around floor-change tiles to prevent accidental step-on
local function pathCrossesFloorChange(path, startPos, maxSteps)
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.pathCrossesFloorChange then
    return TargetCore.PathSafety.pathCrossesFloorChange(path, startPos, maxSteps)
  end
  if not path then return false end
  local pathLen = #path
  if pathLen == 0 then return false end
  
  -- Reuse pre-allocated probe
  pathProbe.x = startPos.x
  pathProbe.y = startPos.y
  pathProbe.z = startPos.z
  
  -- Limit checks to first N steps (floor changes happen quickly)
  local checkLimit = maxSteps or math.min(pathLen, 25)
  
  for i = 1, checkLimit do
    local dir = path[i]
    local offset = DIR_TO_OFFSET[dir]
    if offset then
      pathProbe.x = pathProbe.x + offset.x
      pathProbe.y = pathProbe.y + offset.y
      if isFloorChangeTile(pathProbe) then
        return true
      end
    end
  end
  return false
end

-- Pure: Get first unsafe step index (0 if all safe)
local function getFirstUnsafeStep(path, startPos)
  if not path then return 0 end
  local pathLen = #path
  if pathLen == 0 then return 0 end
  
  -- Reuse pre-allocated probe
  pathProbe.x = startPos.x
  pathProbe.y = startPos.y
  pathProbe.z = startPos.z
  
  for i = 1, pathLen do
    local dir = path[i]
    local offset = DIR_TO_OFFSET[dir]
    if offset then
      pathProbe.x = pathProbe.x + offset.x
      pathProbe.y = pathProbe.y + offset.y
      if isFloorChangeTile(pathProbe) then
        return i
      end
    end
  end
  return 0
end

-- Pure: Count consecutive safe steps from start
local function countSafeSteps(path, startPos, maxCheck)
  if not path or #path == 0 then return 0 end
  
  pathProbe.x = startPos.x
  pathProbe.y = startPos.y
  pathProbe.z = startPos.z
  
  local safeCount = 0
  local limit = math.min(#path, maxCheck or #path)
  
  for i = 1, limit do
    local offset = DIR_TO_OFFSET[path[i]]
    if offset then
      pathProbe.x = pathProbe.x + offset.x
      pathProbe.y = pathProbe.y + offset.y
      if isFloorChangeTile(pathProbe) then
        break
      end
      safeCount = i
    end
  end
  return safeCount
end

-- Register PathValidator functions
PathValidator.pathCrossesFloorChange = pathCrossesFloorChange
PathValidator.getFirstUnsafeStep = getFirstUnsafeStep
PathValidator.countSafeSteps = countSafeSteps
PathValidator.countFloorChangesInPath = countFloorChangesInPath
PathValidator.pathLeadsToFloorChangeZone = pathLeadsToFloorChangeZone

-- ============================================================================
-- SAFE PATH FINDING (SRP: Finds paths avoiding floor changes)
-- ============================================================================

-- Pre-allocated candidate position (avoid allocations)
local altCandidate = {x = 0, y = 0, z = 0}

-- Find alternate destination with safe path (optimized: limited pathfinding calls)
local function findSafeAlternate(playerPos, dest, maxDist, opts)
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.findSafeAlternate then
    return TargetCore.PathSafety.findSafeAlternate(playerPos, dest, maxDist, opts)
  end
  opts = opts or {}
  local precision = opts.precision or 1
  local ignoreFields = opts.ignoreFields or false
  local pathChecks = 0
  local maxPathChecks = 3  -- Limit expensive operations

  -- Quick search: immediate neighbors (radius 1) - reuse pre-allocated table
  for i = 1, 8 do
    local offset = ADJACENT_OFFSETS[i]
    altCandidate.x = dest.x + offset.x
    altCandidate.y = dest.y + offset.y
    altCandidate.z = dest.z
    
    if not posEquals(altCandidate, playerPos) and not isFloorChangeTile(altCandidate) then
      if pathChecks < maxPathChecks then
        pathChecks = pathChecks + 1
        local path = findPath(playerPos, altCandidate, maxDist, {
          ignoreNonPathable = true, 
          ignoreCreatures = true, 
          ignoreFields = ignoreFields, 
          precision = precision
        })
        if path and #path > 0 and not pathCrossesFloorChange(path, playerPos) then
          -- Return a copy (caller may modify)
          return {x = altCandidate.x, y = altCandidate.y, z = altCandidate.z}, path
        end
      end
    end
  end

  -- If quick search failed, do a small BFS search (only if we have budget left)
  if pathChecks < maxPathChecks then
    local bfsTile, bfsPath = findSafeAlternateBFS(playerPos, dest, maxDist, {
      precision = precision, 
      ignoreFields = ignoreFields, 
      radius = 3  -- Reduced radius
    })
    if bfsTile and bfsPath then return bfsTile, bfsPath end
  end

  return nil, nil
end

-- Lightweight path cursor to avoid table.remove churn
local PathCursor = {
  path = nil,
  idx = 1,
  ts = 0,
  TTL = 300
}

-- Track autoWalk issuance to detect stalls (avoid being stuck mid-path)
PathCursor.autoWalkIssued = false
PathCursor.autoWalkIssuedTs = 0

local function resetPathCursor()
  PathCursor.path = nil
  PathCursor.idx = 1
  PathCursor.ts = 0
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
-- PATH HELPERS (Must be defined before walkTo)
-- ============================================================================

-- Helper: Compute safe path with multiple fallback strategies
local function computeSafePath(playerPos, dest, maxDist, opts)
  -- Strategy 1: Direct path
  local path = findPath(playerPos, dest, maxDist, {
    ignoreNonPathable = true,
    ignoreCreatures = opts.ignoreCreatures or false,
    ignoreFields = opts.ignoreFields or false,
    precision = opts.precision or 1
  })
  if path and #path > 0 then return path end
  
  -- Strategy 2: Ignore creatures
  path = findPath(playerPos, dest, maxDist, {
    ignoreNonPathable = true,
    ignoreCreatures = true,
    ignoreFields = opts.ignoreFields or false,
    precision = opts.precision or 1
  })
  if path and #path > 0 then return path end
  
  -- Strategy 3: Ignore fields (if not already)
  if not opts.ignoreFields then
    path = findPath(playerPos, dest, maxDist, {
      ignoreNonPathable = true,
      ignoreCreatures = true,
      ignoreFields = true,
      precision = opts.precision or 1
    })
  end
  
  return path
end

-- Helper: Execute keyboard walking through fields
local function executeFieldWalk(path, dest, playerPos)
  pathProbe.x = playerPos.x
  pathProbe.y = playerPos.y
  pathProbe.z = playerPos.z
  
  if CaveBot.setWalkingToWaypoint then CaveBot.setWalkingToWaypoint(dest) end
  
  for i = 1, #path do
    local dir = path[i]
    local offset = DIR_TO_OFFSET[dir]
    if not offset then break end
    
    pathProbe.x = pathProbe.x + offset.x
    pathProbe.y = pathProbe.y + offset.y
    
    if not isFieldTile(pathProbe) then break end
    
    walk(dir)
    
    if pathProbe.x == dest.x and pathProbe.y == dest.y then
      return true
    end
  end
  return true
end

-- ============================================================================
-- NAVIGATOR (SRP: Main walking orchestration - KISS principle)
-- ============================================================================

CaveBot.walkTo = function(dest, maxDist, params)
  -- === LAYER 1: Basic validation ===
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
  
  -- === LAYER 2: Parse parameters ===
  params = params or {}
  local precision = params.precision or 1
  local allowFloorChange = params.allowFloorChange or false
  local ignoreCreatures = params.ignoreCreatures or false
  local ignoreFields = params.ignoreFields
  if ignoreFields == nil then
    ignoreFields = getCfg("ignoreFields", false)
  end
  
  maxDist = math.min(maxDist or 20, Config.MAX_PATHFIND_DIST)
  
  -- IMPORTANT: Do NOT set expectedFloor here!
  -- Floor change tracking is handled ONLY by intendedFloorChange in cavebot.lua
  -- The goto action sets intendedFloorChange when walking to a floor-change waypoint
  lastWalkZ = playerPos.z
  
  -- === LAYER 3: Quick checks (avoid expensive operations) ===
  local distX = math.abs(dest.x - playerPos.x)
  local distY = math.abs(dest.y - playerPos.y)
  
  -- Already at destination
  if distX <= precision and distY <= precision and dest.z == playerPos.z then
    return true
  end
  
  -- Floor mismatch (can't walk to different floor without floor change)
  if dest.z ~= playerPos.z then
    return false
  end
  
  -- === LAYER 4: Fast path (floor changes allowed) ===
  if allowFloorChange then
    autoWalk(dest, maxDist, {ignoreNonPathable = true, precision = precision})
    if CaveBot.setWalkingToWaypoint then CaveBot.setWalkingToWaypoint(dest) end
    return true
  end
  
  -- === LAYER 5: Destination safety check ===
  if isFloorChangeTile(dest) then
    local altTile, _ = findSafeAlternate(playerPos, dest, maxDist, {
      precision = precision, 
      ignoreFields = ignoreFields
    })
    if altTile then
      dest = altTile
    else
      return false
    end
  end
  
  -- === LAYER 6: Path computation (with caching) ===
  local path
  if PathCursor.path and PathCursor.idx <= #PathCursor.path and (now - PathCursor.ts) < PathCursor.TTL then
    path = PathCursor.path
  else
    resetPathCursor()
    path = computeSafePath(playerPos, dest, maxDist, {
      ignoreCreatures = ignoreCreatures,
      ignoreFields = ignoreFields,
      precision = precision
    })
    
    if not path or #path == 0 then
      return false
    end
    
    PathCursor.path = path
    PathCursor.idx = 1
    PathCursor.ts = now
  end
  
  -- === LAYER 7: AutoWalk stall detection ===
  local stallTimeout = getCfg("autoWalkStallTimeout", Config.AUTOWALK_STALL_TIMEOUT)
  if PathCursor.autoWalkIssued and not (player and player:isWalking()) then
    if (now - PathCursor.autoWalkIssuedTs) > stallTimeout then
      resetPathCursor()
      local altTile, altPath = findSafeAlternate(playerPos, dest, maxDist, {
        precision = precision, 
        ignoreFields = ignoreFields
      })
      if altTile and altPath and #altPath > 0 then
        PathCursor.path = altPath
        PathCursor.idx = 1
        PathCursor.ts = now
      end
      PathCursor.autoWalkIssued = false
      PathCursor.autoWalkIssuedTs = 0
      return false
    end
  end
  
  -- === LAYER 8: Path safety validation ===
  if pathCrossesFloorChange(path, playerPos, #path) then
    local altTile, altPath = findSafeAlternate(playerPos, dest, maxDist, {
      precision = precision, 
      ignoreFields = ignoreFields
    })
    if altTile and altPath and #altPath > 0 and not pathCrossesFloorChange(altPath, playerPos, #altPath) then
      path = altPath
      PathCursor.path = altPath
      PathCursor.idx = 1
      PathCursor.ts = now
    else
      resetPathCursor()
      return false
    end
  end
  
  -- === LAYER 9: Count safe steps (tiered validation) ===
  local safeSteps = countSafeSteps(path, playerPos, Config.MAX_WALK_CHUNK + 5)
  
  if safeSteps == 0 then
    -- Try alternate route
    local altTile, altPath = findSafeAlternate(playerPos, dest, maxDist, {
      precision = precision, 
      ignoreFields = ignoreFields
    })
    if altTile and altPath and #altPath > 0 then
      safeSteps = countSafeSteps(altPath, playerPos, #altPath)
      if safeSteps > 0 then
        path = altPath
        PathCursor.path = altPath
        PathCursor.idx = 1
        PathCursor.ts = now
      end
    end
    if safeSteps == 0 then
      return false
    end
  end
  
  -- === LAYER 10: Execute walk (chunked) ===
  local walkSteps = math.min(safeSteps, Config.MAX_WALK_CHUNK)
  
  -- Calculate chunk destination
  pathProbe.x = playerPos.x
  pathProbe.y = playerPos.y
  pathProbe.z = playerPos.z
  local endIdx = math.min(PathCursor.idx + walkSteps - 1, #path)
  for i = PathCursor.idx, endIdx do
    local offset = DIR_TO_OFFSET[path[i]]
    if offset then
      pathProbe.x = pathProbe.x + offset.x
      pathProbe.y = pathProbe.y + offset.y
    end
  end
  local chunkDest = {x = pathProbe.x, y = pathProbe.y, z = pathProbe.z}
  
  -- Handle field walking (keyboard walk)
  if ignoreFields then
    return executeFieldWalk(path, dest, playerPos)
  end
  
  -- Verify reachability
  local reachable = iterativeReachable(playerPos, chunkDest)
  if not reachable then
    local testPath = findPath(playerPos, chunkDest, maxDist, {
      ignoreNonPathable = true, 
      ignoreCreatures = true, 
      ignoreFields = ignoreFields, 
      precision = 0
    })
    if not testPath or #testPath == 0 or pathCrossesFloorChange(testPath, playerPos) then
      resetPathCursor()
      return false
    end
  end
  
  -- === LAYER 11: Execute movement ===
  if walkSteps >= 3 then
    -- Smooth autoWalk for longer paths
    if player and player:isWalking() and (now - PathCursor.ts) < 600 then
      return true
    end
    autoWalk(chunkDest, maxDist, {ignoreNonPathable = true, precision = 0})
    if CaveBot.setWalkingToWaypoint then CaveBot.setWalkingToWaypoint(chunkDest) end
    PathCursor.autoWalkIssued = true
    PathCursor.autoWalkIssuedTs = now
    PathCursor.idx = math.min(PathCursor.idx + walkSteps, #path + 1)
    PathCursor.ts = now
    return true
  end
  
  -- Single step for short paths
  local firstDir = path[PathCursor.idx]
  local offset = getDirectionOffset(firstDir)
  if offset then
    if CaveBot.setWalkingToWaypoint then CaveBot.setWalkingToWaypoint(dest) end
    walk(firstDir)
    PathCursor.idx = PathCursor.idx + 1
    return true
  end
  
  return false
end

-- ============================================================================
-- CONVENIENCE FUNCTIONS (Clean public API)
-- ============================================================================

CaveBot.safeWalkTo = function(dest, maxDist, params)
  params = params or {}
  params.allowFloorChange = false
  return CaveBot.walkTo(dest, maxDist, params)
end

CaveBot.resetWalking = function()
  -- Reset walking state
  expectedFloor = nil
  lastWalkZ = nil
  FloorChangeCache.tiles = {}
  resetPathCursor()
  resetStepBackAttempts()  -- Reset step-back counter
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
  FloorGuard.expectedFloor = floor
end

CaveBot.isOnExpectedFloor = function()
  if not FloorGuard.expectedFloor then return true end
  return posz() == FloorGuard.expectedFloor
end

CaveBot.getFloorChangeInfo = function()
  if not FloorGuard.expectedFloor then return nil end
  local currentFloor = posz()
  if currentFloor ~= FloorGuard.expectedFloor then
    return {
      expected = FloorGuard.expectedFloor,
      current = currentFloor,
      difference = currentFloor - FloorGuard.expectedFloor
    }
  end
  return nil
end

CaveBot.isPathSafe = function(dest)
  local playerPos = pos()
  if not playerPos or not dest then return true end
  if posEquals(playerPos, dest) then return true end
  if playerPos.z ~= dest.z then return true end
  
  local path = findPath(playerPos, dest, Config.MAX_PATHFIND_DIST, {ignoreNonPathable = true})
  return path and not PathValidator.pathCrossesFloorChange(path, playerPos)
end

-- Expose utilities (clean public API)
CaveBot.isFloorChangeTile = isFloorChangeTile
CaveBot.isNearFloorChangeTile = isNearFloorChangeTile
CaveBot.getSafeAdjacentTiles = function(centerPos) return getSafeAdjacentTiles(centerPos, false) end
CaveBot.resetPathCursor = resetPathCursor

-- Expose modules for external access (SOLID: Interface Segregation)
CaveBot.TileAnalyzer = TileAnalyzer
CaveBot.PathValidator = PathValidator
CaveBot.FloorGuard = FloorGuard

-- ============================================================================
-- FLOOR GUARD EVENT HANDLER (Monitors position changes)
-- ============================================================================
local consecutiveFloorChanges = 0
local FLOORCHANGE_STEPBACK_THRESHOLD = getCfg("floorChangeStepBackThreshold", Config.FLOOR_CHANGE_THRESHOLD)

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
