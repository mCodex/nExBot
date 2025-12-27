--[[
  CaveBot Walking Module v3.2.0
  
  DESIGN PRINCIPLES:
  - SRP: Each function has one responsibility
  - DRY: No duplicated logic, shared helpers
  - KISS: Simple, readable functions
  - Pure Functions: Predictable, no side effects where possible
  
  FLOOR-CHANGE PREVENTION:
  - Validates path before autoWalk (never walk on floor-change tiles)
  - Comprehensive ramp/ladder/hole/teleport detection
  - Safe path computation with floor-change avoidance
  - Immediate stop if floor change detected in path
  
  FIELD HANDLING:
  - Respects ignoreFields config option
  - Falls back to keyboard walking when autoWalk fails on fields
  - Supports fire, poison, energy fields
  
  PATHFINDING DESIGN:
  - Uses realistic pathfinding limit (50 tiles) matching game engine
  - For longer distances, use waypoint-to-waypoint navigation
  - Chunked walking (15 tiles/call) keeps paths fresh
  - Tiered validation: thorough near, fast minimap far
]]

-- ============================================================================
-- MODULE STATE (minimal, well-defined)
-- ============================================================================

local expectedFloor = nil
local lastWalkZ = nil

-- IMPORTANT: Game client's A* pathfinding has practical limits (~50-70 tiles)
-- For longer distances, rely on waypoint-to-waypoint navigation
local MAX_PATHFIND_DIST = 50   -- Realistic pathfinding limit
local MAX_WALK_CHUNK = 25      -- Increased from 15 for faster walking
local THOROUGH_CHECK_DIST = 40 -- Increased thorough window to improve floor-change accuracy

-- Config helper: read CaveBot.Config safely
local function getCfg(key, def)
  if CaveBot and CaveBot.Config and CaveBot.Config.get then
    local ok, v = pcall(function() return CaveBot.Config.get(key) end)
    if ok and v ~= nil then return v end
  end
  return def
end

local function log_dbg(msg) end

-- ============================================================================
-- DIRECTION UTILITIES (Pure functions)
-- ============================================================================

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

local ADJACENT_OFFSETS = {
  {x = 0, y = -1},  {x = 1, y = 0},  {x = 0, y = 1},  {x = -1, y = 0},
  {x = 1, y = -1}, {x = 1, y = 1}, {x = -1, y = 1}, {x = -1, y = -1},
}

-- Pure: Get offset for direction
local function getDirectionOffset(dir)
  return DIR_TO_OFFSET[dir]
end

-- Pure: Apply offset to position
local function applyOffset(pos, offset)
  return {x = pos.x + offset.x, y = pos.y + offset.y, z = pos.z}
end

-- Pure: Check position equality
local function posEquals(a, b)
  return a.x == b.x and a.y == b.y and a.z == b.z
end

-- ============================================================================
-- FLOOR-CHANGE DETECTION (SRP: Only detects floor-change tiles)
-- ============================================================================

-- Floor-change tile cache (PERFORMANCE: avoid repeated tile lookups)
local FloorChangeCache = {
  tiles = {},
  lastCleanup = 0,
  TTL = 2000,  -- Cache valid for 2 seconds
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

-- Pure: Check if position is a floor-change tile (with caching)
local function isFloorChangeTile(tilePos)
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isFloorChangeTile then
    return TargetCore.PathSafety.isFloorChangeTile(tilePos)
  end
  if not tilePos then return false end
  
  -- Periodic cache cleanup (guarded to run at most once per second)
  FloorChangeCache.lastCleanupCheck = FloorChangeCache.lastCleanupCheck or 0
  if now - FloorChangeCache.lastCleanupCheck > 1000 then
    FloorChangeCache.lastCleanupCheck = now
    if now - FloorChangeCache.lastCleanup > 5000 then
      FloorChangeCache.tiles = {}
      FloorChangeCache.lastCleanup = now
    end
  end
  
  -- Check cache first
  local cacheKey = getFloorChangeCacheKey(tilePos)
  local cached = FloorChangeCache.tiles[cacheKey]
  if cached ~= nil and now - cached.time < FloorChangeCache.TTL then
    return cached.value
  end
  
  -- Fast path: minimap color (no tile lookup needed)
  local color = g_map.getMinimapColor(tilePos)
  if FLOOR_CHANGE_COLORS[color] then
    FloorChangeCache.tiles[cacheKey] = {value = true, time = now}
    return true
  end
  
  -- Slow path: tile inspection (only if minimap didn't detect)
  local result = false
  local tile = g_map.getTile(tilePos)
  if tile then
    result = hasFloorChangeGround(tile) or hasFloorChangeItem(tile)
  end
   
  FloorChangeCache.tiles[cacheKey] = {value = result, time = now}
  return result
end

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
-- PATH VALIDATION (SRP: Validates paths for safety)
-- ============================================================================

-- Pure: Check if path crosses floor-change tiles (checks ALL steps for safety)
local function pathCrossesFloorChange(path, startPos, maxSteps)
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.pathCrossesFloorChange then
    return TargetCore.PathSafety.pathCrossesFloorChange(path, startPos, maxSteps)
  end
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
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.findSafeAlternate then
    return TargetCore.PathSafety.findSafeAlternate(playerPos, dest, maxDist, opts)
  end
  opts = opts or {}
  local precision = opts.precision or 1
  local ignoreFields = opts.ignoreFields or false

  -- Quick search: immediate neighbors (radius 1)
  for _, offset in ipairs(ADJACENT_OFFSETS) do
    local candidate = {x = dest.x + offset.x, y = dest.y + offset.y, z = dest.z}
    if not posEquals(candidate, playerPos) and not isFloorChangeTile(candidate) then
      local path = findPath(playerPos, candidate, maxDist, {ignoreNonPathable = true, ignoreCreatures = true, ignoreFields = ignoreFields, precision = precision})
      if path and #path > 0 and not pathCrossesFloorChange(path, playerPos) then
        return candidate, path
      end
    end
  end

  -- If quick search failed, do a small BFS search around destination for a safe reachable tile
  local bfsTile, bfsPath = findSafeAlternateBFS(playerPos, dest, maxDist, {precision = precision, ignoreFields = ignoreFields, radius = 3})
  if bfsTile and bfsPath then return bfsTile, bfsPath end

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
local STEP_BACK_COOLDOWN = getCfg("stepBackCooldown", 1500) -- ms
local RecentBufferSize = getCfg("recentPosBufferSize", 6)
RecentPos.size = RecentBufferSize
local consecutiveFloorChanges = 0
local FLOORCHANGE_STEPBACK_THRESHOLD = getCfg("floorChangeStepBackThreshold", 2) -- require consecutive floor changes to attempt step-back

local function stepBackToLastSafe(currentPos)
  if not lastSafePos then return false end
  currentPos = currentPos or pos()
  if not currentPos then return false end
  if now - lastStepBackTs < STEP_BACK_COOLDOWN then return false end
  if posEquals(currentPos, lastSafePos) then return false end

  lastStepBackTs = now

  -- Attempt a short path back; allow small detours but keep it tight
  local path = findPath(currentPos, lastSafePos, 10, {
    ignoreNonPathable = true,
    ignoreCreatures = true,
    ignoreFields = true,
    precision = 0
  })

  if not path or #path == 0 then
    return false
  end

  autoWalk(lastSafePos, 10, {ignoreNonPathable = true, precision = 0})
  resetPathCursor()
  return true
end


-- BFS-based safe alternate finder (search small radius for reachable safe tile)
local function findSafeAlternateBFS(playerPos, dest, maxDist, opts)
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.findSafeAlternate then
    return TargetCore.PathSafety.findSafeAlternate(playerPos, dest, maxDist, opts)
  end
  opts = opts or {}
  local maxSearchRadius = opts.radius or getCfg("safeAlternateMaxRadius", 8)
  local timeBudget = opts.timeBudget or getCfg("safeAlternateTimeBudget", 30) -- ms

  local startTs = now
  -- Adaptive expansion: try increasing radii until we find a candidate or reach maxSearchRadius
  for radius = 1, maxSearchRadius do
    local visited = {}
    local queue = {{x = dest.x, y = dest.y, z = dest.z}}
    local head = 1
    while head <= #queue do
      -- time budget check
      if now - startTs > timeBudget then
        return nil, nil
      end

      local cur = queue[head]
      head = head + 1
      local key = cur.x .. "," .. cur.y .. "," .. cur.z
      if not visited[key] then
        visited[key] = true

        local dx = math.abs(cur.x - dest.x)
        local dy = math.abs(cur.y - dest.y)
        if dx + dy <= radius then
          -- Skip player's current tile
          if not posEquals(cur, playerPos) and not isFloorChangeTile(cur) then
            local path = findPath(playerPos, cur, maxDist, {ignoreNonPathable = true, ignoreCreatures = true, ignoreFields = opts.ignoreFields or false, precision = opts.precision or 1})
            if path and #path > 0 and not pathCrossesFloorChange(path, playerPos) then
              return cur, path
            end
          end

          -- expand neighbors for next layer
          for _, off in ipairs(ADJACENT_OFFSETS) do
            local nxt = {x = cur.x + off.x, y = cur.y + off.y, z = cur.z}
            local k2 = nxt.x .. "," .. nxt.y .. "," .. nxt.z
            if not visited[k2] then table.insert(queue, nxt) end
          end
        end
      end
    end
    -- no candidate found at this radius, continue to next radius
  end
  return nil, nil
end

-- Recursive reachability check (pure-style recursion with limits)
local RECURSIVE_MAX_DEPTH = getCfg("recursiveReachDepth", 20)
local RECURSIVE_MAX_NODES = getCfg("recursiveReachNodes", 300)

local function recursiveReachable(startPos, targetPos, depth, visited, nodes)
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.recursiveReachable then
    return TargetCore.PathSafety.recursiveReachable(startPos, targetPos, getCfg("recursiveReachDepth", 20), getCfg("recursiveReachNodes", 300))
  end
  depth = depth or 0
  visited = visited or {}
  nodes = nodes or {count = 0}

  if depth > RECURSIVE_MAX_DEPTH or nodes.count > RECURSIVE_MAX_NODES then
    return false
  end

  if posEquals(startPos, targetPos) then return true end

  nodes.count = nodes.count + 1
  local key = getFloorChangeCacheKey(startPos)
  visited[key] = true

  local neighbors = getSafeAdjacentTiles(startPos, false)
  for _, n in ipairs(neighbors) do
    local k = getFloorChangeCacheKey(n)
    if not visited[k] then
      if recursiveReachable(n, targetPos, depth + 1, visited, nodes) then
        return true
      end
    end
  end

  return false
end

-- ============================================================================
-- MAIN WALKING FUNCTION (Orchestrates all components)
-- ============================================================================

CaveBot.walkTo = function(dest, maxDist, params)
  local playerPos = pos()
  if not playerPos then return false end
  if not lastSafePos then
    lastSafePos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  end
  if lastWalkZ and playerPos.z ~= lastWalkZ then
    stepBackToLastSafe(playerPos)
    expectedFloor = nil
    lastWalkZ = playerPos.z
    return false
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
  
  -- Track expected floor
  expectedFloor = dest.z
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
  
  -- FAST PATH: If floor changes allowed, just use autoWalk directly
  if allowFloorChange then
    autoWalk(dest, maxDist, {ignoreNonPathable = true, precision = precision})
    if CaveBot.setWalkingToWaypoint then CaveBot.setWalkingToWaypoint(dest) end
    return true
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

  -- Reuse cursor cache if valid
  if PathCursor.path and PathCursor.idx <= #PathCursor.path and (now - PathCursor.ts) < PathCursor.TTL then
    path = PathCursor.path
  else
    resetPathCursor()
    path = findPath(playerPos, dest, maxDist, {
      ignoreNonPathable = true,
      ignoreCreatures = ignoreCreatures,
      ignoreFields = ignoreFields,
      precision = precision
    })

    -- Try with creature ignoring if first attempt failed
    if not path then
      path = findPath(playerPos, dest, maxDist, {
        ignoreNonPathable = true,
        ignoreCreatures = true,
        ignoreFields = ignoreFields,
        precision = precision
      })
    end

    -- FALLBACK: If still no path and ignoreFields is off, try with ignoreFields on
    if not path and not ignoreFields then
      path = findPath(playerPos, dest, maxDist, {
        ignoreNonPathable = true,
        ignoreCreatures = true,
        ignoreFields = true,
        precision = precision
      })
      -- If we found a path with fields ignored, we'll use keyboard walking
      if path then
        ignoreFields = true  -- Mark that we need to handle fields
      end
    end

    if not path or #path == 0 then
      return false
    end

    PathCursor.path = path
    PathCursor.idx = 1
    PathCursor.ts = now
  end

  -- Detect autoWalk stall: if we issued autoWalk previously and the player isn't walking
  -- after a short timeout, reset cursor to force recompute. Configurable timeout.
  local autoWalkStallTimeout = getCfg("autoWalkStallTimeout", 500)
  if PathCursor.autoWalkIssued and not (player and player:isWalking()) and (now - PathCursor.autoWalkIssuedTs) > autoWalkStallTimeout then
    resetPathCursor()
    -- try to find a nearby safe alternate immediately
    local altTile, altPath = findSafeAlternate(playerPos, dest, maxDist, {precision = precision, ignoreFields = ignoreFields})
    if altTile and altPath and #altPath > 0 then
      PathCursor.path = altPath
      PathCursor.idx = 1
      PathCursor.ts = now
    end
    PathCursor.autoWalkIssued = false
    PathCursor.autoWalkIssuedTs = 0
    return false
  end

  -- Close path selection block
  

  -- End of path selection block

  -- Hard guard: if path crosses any floor-change tile, try a nearby alternate before aborting
  if pathCrossesFloorChange(path, playerPos, #path) then
    local altTile, altPath = findSafeAlternate(playerPos, dest, maxDist, {precision = precision, ignoreFields = ignoreFields})
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

  -- TIERED VALIDATION: Check for floor-change tiles (kept for near/far mixed accuracy)
  local safeSteps = 0
  local probe = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  local pathLen = #path
  
  for i = 1, pathLen do
    local offset = getDirectionOffset(path[i])
    if offset then
      probe = applyOffset(probe, offset)
      
      -- Use appropriate check based on distance
      local isUnsafe
      if i <= THOROUGH_CHECK_DIST then
        -- Thorough check for near tiles (cached)
        isUnsafe = isFloorChangeTile(probe)
      else
        -- Fast minimap check for distant tiles
        isUnsafe = isFloorChangeTileFast(probe)
      end
      
      if isUnsafe then
        break
      end
      safeSteps = i
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
  -- This is critical for long paths - prevents walking on stale data
  local walkSteps = math.min(safeSteps, MAX_WALK_CHUNK)

  -- Calculate the chunk destination using the cursor (no table removes)
  local chunkDestination = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  for i = PathCursor.idx, math.min(PathCursor.idx + walkSteps - 1, #path) do
    local offset = getDirectionOffset(path[i])
    if offset then
      chunkDestination = applyOffset(chunkDestination, offset)
    end
  end
  
  -- FIELD HANDLING: Use keyboard walking for paths with fields
  -- autoWalk/map-click doesn't work through fire/poison/energy fields
  if ignoreFields then
    -- Walk through consecutive field tiles using keyboard walking
    local currentPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
      if CaveBot.setWalkingToWaypoint then CaveBot.setWalkingToWaypoint(dest) end
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
  
  -- Recursively validate reachability to the chunk destination to avoid hidden floor-changes
  local rrDepth = getCfg("recursiveReachDepth", 20)
  local rrNodes = getCfg("recursiveReachNodes", 300)
  local reachable = recursiveReachable(playerPos, chunkDestination, rrDepth, nil, {count = 0})
  if not reachable then
    -- Fallback: if pathfinding still finds a direct path without floor changes, accept it
    local testPath = findPath(playerPos, chunkDestination, maxDist, {ignoreNonPathable = true, ignoreCreatures = true, ignoreFields = ignoreFields, precision = 0})
    if testPath and #testPath > 0 and not pathCrossesFloorChange(testPath, playerPos) then
      -- accept path as fallback
    else
      resetPathCursor()
      return false
    end
  end

  -- SMOOTH MOVEMENT: Use autoWalk for 3+ verified safe steps
  if walkSteps >= 3 then
    -- Avoid re-sending autoWalk too frequently while the player is already walking
    if player and player:isWalking() and (now - PathCursor.ts) < 600 then
      return true
    end
    autoWalk(chunkDestination, maxDist, {ignoreNonPathable = true, precision = 0})
    if CaveBot.setWalkingToWaypoint then CaveBot.setWalkingToWaypoint(chunkDestination) end
    -- mark autoWalk issued so we can detect stalls
    PathCursor.autoWalkIssued = true
    PathCursor.autoWalkIssuedTs = now
    PathCursor.idx = math.min(PathCursor.idx + walkSteps, #path + 1)
    PathCursor.ts = now
    return true
  end

  -- For short safe paths (1-2 steps), use direct walk via cursor
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
-- CONVENIENCE FUNCTIONS
-- ============================================================================

CaveBot.safeWalkTo = function(dest, maxDist, params)
  params = params or {}
  params.allowFloorChange = false
  return CaveBot.walkTo(dest, maxDist, params)
end

CaveBot.resetWalking = function()
  -- Reset walking state
  expectedFloor = nil
  FloorChangeCache.tiles = {}
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
CaveBot.getSafeAdjacentTiles = function(centerPos) return getSafeAdjacentTiles(centerPos, false) end
-- Expose internal reset for external modules (safe API)
CaveBot.resetPathCursor = resetPathCursor

-- Floor change detection on position change
onPlayerPositionChange(function(newPos, oldPos)
  if not oldPos or not newPos then return end
  lastSafePos = {x = oldPos.x, y = oldPos.y, z = oldPos.z}
  -- track recent positions for oscillation detection
  pushRecentPos(newPos)

  if expectedFloor and newPos.z ~= expectedFloor then
    warn("[CaveBot] Unexpected floor change! Expected: " .. expectedFloor .. ", Current: " .. newPos.z)
    consecutiveFloorChanges = consecutiveFloorChanges + 1

    -- Notify CaveBot controller to allow oscillation handling
    if CaveBot and CaveBot.onFloorChanged then
      local fromFloor = expectedFloor or lastWalkZ or (oldPos and oldPos.z) or 0
      pcall(function() CaveBot.onFloorChanged(fromFloor, newPos.z) end)
    end

    -- only attempt step-back after a couple of consecutive unexpected floor changes
    if consecutiveFloorChanges >= FLOORCHANGE_STEPBACK_THRESHOLD then
      stepBackToLastSafe(newPos)
      consecutiveFloorChanges = 0
    end
    expectedFloor = nil
    FloorChangeCache.tiles = {}  -- Clear cache on floor change
  else
    consecutiveFloorChanges = 0
  end

  -- if we detect oscillation between two tiles, reset path cursor to recompute
  if isOscillating() then
    resetPathCursor()
  end
end)

-- Safeguard: ensure module closes cleanly
return true
