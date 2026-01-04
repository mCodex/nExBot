-- PathSafety module: pure functions and caching for floor-change detection and safe alternate finding
-- Follows SRP: exposes pure-path-safety operations and lightweight caching.

local PathSafety = {}
PathSafety.VERSION = "1.0"

local FLOOR_CHANGE_COLORS = { [210]=true,[211]=true,[212]=true,[213]=true }
local FloorChangeCache = { tiles = {}, lastCleanup = 0, TTL = 2000 }

local function nowMs() if now then return now end if g_clock and g_clock.millis then return g_clock.millis() end return os.time()*1000 end
local function getKey(p) return p.x..","..p.y..","..p.z end

-- Pure: check ground tiles
local function hasFloorChangeGround(tile)
  if not tile then return false end
  local ground = tile:getGround()
  if not ground or not ground:getId then return false end
  local idx = ground:getId()
  -- Use minimap color mapping fallback is done in callers
  return floorChangeIds and floorChangeIds[idx] or false
end

local function hasFloorChangeItem(tile)
  if not tile then return false end
  for i,item in ipairs(tile:getItems() or {}) do
    local tid = item:getId()
    -- Common stair IDs are handled by minimap color; this is a conservative extra check
    if tid == 414 or tid == 415 or tid == 416 or tid == 417 or tid == 428 or tid == 429 or tid == 430 or tid == 431 or tid == 432 or tid == 433 or tid == 434 or tid == 435 then
      return true
    end
  end
  return false
end

-- Public: is floor-change tile (cached)
function PathSafety.isFloorChangeTile(pos)
  if not pos then return false end
  -- Prefer external PathSafety (already here) - check map minimap color first (fast)
  local color = g_map.getMinimapColor(pos)
  if FLOOR_CHANGE_COLORS[color] then return true end

  -- TTL cache cleanup
  if nowMs() - FloorChangeCache.lastCleanup > 1000 then FloorChangeCache.tiles = {}; FloorChangeCache.lastCleanup = nowMs() end
  local key = getKey(pos)
  local cached = FloorChangeCache.tiles[key]
  if cached and nowMs() - cached.time < FloorChangeCache.TTL then return cached.value end

  local tile = g_map.getTile(pos)
  local res = hasFloorChangeGround(tile) or hasFloorChangeItem(tile)
  FloorChangeCache.tiles[key] = {value = res, time = nowMs()}
  return res
end

-- Fast minimap-only check
function PathSafety.isFloorChangeTileFast(pos)
  if not pos then return false end
  local color = g_map.getMinimapColor(pos)
  return FLOOR_CHANGE_COLORS[color] or false
end

-- Path crosses floor-change check (pure): given path steps (directions) and startPos
function PathSafety.pathCrossesFloorChange(path, startPos, maxSteps)
  if not path or #path == 0 or not startPos then return false end
  local probe = {x=startPos.x, y=startPos.y, z=startPos.z}
  local steps = maxSteps or #path
  for i=1, math.min(#path, steps) do
    local off = getDirectionOffset(path[i])
    if not off then break end
    probe = applyOffset(probe, off)
    if PathSafety.isFloorChangeTile(probe) then return true end
  end
  return false
end

-- Find safe nearby alternate (neighbors first, then BFS)
function PathSafety.findSafeAlternate(playerPos, dest, maxDist, opts)
  opts = opts or {}
  local precision = opts.precision or 1
  local ignoreFields = opts.ignoreFields or false
  local ADJ = {{x=0,y=1},{x=1,y=0},{x=0,y=-1},{x=-1,y=0},{x=1,y=1},{x=-1,y=-1},{x=1,y=-1},{x=-1,y,1}}

  -- Quick neighbors
  for _, off in ipairs(ADJ) do
    local candidate = {x = dest.x + off.x, y = dest.y + off.y, z = dest.z}
    if not posEquals(candidate, playerPos) and not PathSafety.isFloorChangeTile(candidate) then
      local path = findPath(playerPos, candidate, maxDist, {ignoreNonPathable=true, ignoreCreatures=true, ignoreFields = ignoreFields, precision = precision})
      if path and #path > 0 and not PathSafety.pathCrossesFloorChange(path, playerPos) then return candidate, path end
    end
  end

  -- BFS fallback
  local radius = opts.radius or 3
  return PathSafety.findSafeAlternateBFS(playerPos, dest, maxDist, opts)
end

function PathSafety.findSafeAlternateBFS(playerPos, dest, maxDist, opts)
  opts = opts or {}
  local maxSearchRadius = opts.radius or 8
  local timeBudget = opts.timeBudget or 30
  local startTs = nowMs()
  for radius=1, maxSearchRadius do
    local visited = {}
    local queue = {{x=dest.x, y=dest.y, z=dest.z}}
    local head = 1
    while head <= #queue do
      if nowMs() - startTs > timeBudget then return nil, nil end
      local cur = queue[head]; head = head+1
      local key = getKey(cur)
      if not visited[key] then
        visited[key] = true
        local dx = math.abs(cur.x - dest.x)
        local dy = math.abs(cur.y - dest.y)
        if dx + dy <= radius then
          if not posEquals(cur, playerPos) and not PathSafety.isFloorChangeTile(cur) then
            local path = findPath(playerPos, cur, maxDist, {ignoreNonPathable=true, ignoreCreatures=true, ignoreFields=opts.ignoreFields or false, precision = opts.precision or 1})
            if path and #path > 0 and not PathSafety.pathCrossesFloorChange(path, playerPos) then return cur, path end
          end
          for _, off in ipairs(ADJACENT_OFFSETS) do table.insert(queue, {x=cur.x+off.x, y=cur.y+off.y, z=cur.z}) end
        end
      end
    end
  end
  return nil, nil
end

-- Recursive reachability (bounded)
function PathSafety.recursiveReachable(startPos, targetPos, depth, visited, nodes)
  local RECURSIVE_MAX_DEPTH = getCfg("recursiveReachDepth", 20)
  local RECURSIVE_MAX_NODES = getCfg("recursiveReachNodes", 300)
  depth = depth or 0; visited = visited or {}; nodes = nodes or {count = 0}
  if depth > RECURSIVE_MAX_DEPTH or nodes.count > RECURSIVE_MAX_NODES then return false end
  if posEquals(startPos, targetPos) then return true end
  nodes.count = nodes.count + 1
  visited[getKey(startPos)] = true
  local neighbors = PathSafety.getSafeAdjacentTiles(startPos) or {}
  for _, n in ipairs(neighbors) do
    if not visited[getKey(n)] then
      if PathSafety.recursiveReachable(n, targetPos, depth+1, visited, nodes) then return true end
    end
  end
  return false
end

-- helper: get safe adjacent tiles using existing function
function PathSafety.getSafeAdjacentTiles(centerPos)
  local res = {}
  for _, off in ipairs(ADJACENT_OFFSETS) do
    local checkPos = {x = centerPos.x + off.x, y = centerPos.y + off.y, z = centerPos.z}
    if not PathSafety.isFloorChangeTile(checkPos) and isTileSafe(checkPos, false) then
      table.insert(res, checkPos)
    end
  end
  return res
end

-- expose
CaveBot.PathSafety = PathSafety
return PathSafety
