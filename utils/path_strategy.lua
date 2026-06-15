--[[
  PathStrategy v2.1.0 — Unified Pathfinding & Movement Strategy
  Added: findPath result caching with TTL for performance
  Simplified: no cursor cache, no anti-zigzag, no path smoothing, no findPathRelaxed.
]]

local PathStrategy = {}

local _PU
local getClient = nExBot and nExBot.Shared and nExBot.Shared.getClient

local function PU()
  if _PU then return _PU end
  _PU = PathUtils
  return _PU
end

local function tick()
  return now or (os.clock() * 1000)
end

local PF_ALLOW_NOT_SEEN      = 1
local PF_ALLOW_CREATURES      = 2
local PF_ALLOW_NON_PATHABLE   = 4
local PF_ALLOW_NON_WALKABLE   = 8
local PF_IGNORE_CREATURES     = 16

local MAX_NATIVE_STEPS = 127
local DEFAULT_MAX_STEPS = 50

-- Path cache configuration
local PATH_CACHE_TTL = 500          -- Cache TTL in milliseconds
local PATH_CACHE_MAX_ENTRIES = 100  -- Maximum cache entries

local DIR_TO_OFFSET, OPPOSITE
local function _ensureDirTables()
  if DIR_TO_OFFSET then return end
  local D = Directions
  if D then
    DIR_TO_OFFSET = D.DIR_TO_OFFSET
    OPPOSITE      = D.OPPOSITE
  end
end

local function dirOffset(dir)
  _ensureDirTables()
  return DIR_TO_OFFSET and DIR_TO_OFFSET[dir]
end

local function applyOff(p, off)
  return {x = p.x + off.x, y = p.y + off.y, z = p.z}
end

local _flagsCacheRef = nil
local _flagsCacheVal = 0

local function optsToFlags(opts)
  if opts == _flagsCacheRef then return _flagsCacheVal end
  local flags = 0
  if opts.allowUnseen       then flags = flags + PF_ALLOW_NOT_SEEN end
  if opts.allowCreatures    then flags = flags + PF_ALLOW_CREATURES end
  if opts.ignoreNonPathable then flags = flags + PF_ALLOW_NON_PATHABLE end
  if opts.ignoreNonWalkable then flags = flags + PF_ALLOW_NON_WALKABLE end
  if opts.ignoreCreatures   then flags = flags + PF_IGNORE_CREATURES end
  _flagsCacheRef = opts
  _flagsCacheVal = flags
  return flags
end

-- Path result cache
local _pathCache = {}
local _pathCacheOrder = {}  -- LRU order

local function makeCacheKey(startPos, goalPos, maxSteps, flags)
  return string.format("%d,%d,%d|%d,%d,%d|%d|%d", 
    startPos.x, startPos.y, startPos.z,
    goalPos.x, goalPos.y, goalPos.z,
    maxSteps, flags)
end

local function cacheGet(key)
  local entry = _pathCache[key]
  if not entry then return nil end
  local nowMs = tick()
  if nowMs - entry.time > PATH_CACHE_TTL then
    _pathCache[key] = nil
    return nil
  end
  -- Update LRU
  for i, k in ipairs(_pathCacheOrder) do
    if k == key then
      table.remove(_pathCacheOrder, i)
      break
    end
  end
  _pathCacheOrder[#_pathCacheOrder + 1] = key
  return entry.path
end

local function cacheSet(key, path)
  -- Evict oldest if at capacity
  if #_pathCacheOrder >= PATH_CACHE_MAX_ENTRIES then
    local oldest = table.remove(_pathCacheOrder, 1)
    _pathCache[oldest] = nil
  end
  _pathCache[key] = { path = path, time = tick() }
  _pathCacheOrder[#_pathCacheOrder + 1] = key
end

local _pathBackend = nil

local function resolveBackend()
  local adapter = nExBot and nExBot.ACL
  if adapter and adapter.map and adapter.map.findPath then
    return function(startPos, goalPos, maxSteps, flags, _opts)
      local ok, result = pcall(adapter.map.findPath, startPos, goalPos, {
        maxSteps = maxSteps, flags = flags,
      })
      if ok and result and #result > 0 then return result end
      return nil
    end
  end
  if findPath then
    return function(startPos, goalPos, maxSteps, _flags, opts)
      local ok, result = pcall(findPath, startPos, goalPos, maxSteps, opts)
      if ok and result and #result > 0 then return result end
      return nil
    end
  end
  if g_map and g_map.findPath then
    return function(startPos, goalPos, maxSteps, flags, _opts)
      local ok, result = pcall(g_map.findPath, startPos, goalPos, maxSteps, flags)
      if ok and result and #result > 0 then return result end
      return nil
    end
  end
  return function() return nil end
end

function PathStrategy.findPath(startPos, goalPos, opts)
  opts = opts or {}
  local maxSteps = math.min(opts.maxSteps or DEFAULT_MAX_STEPS, MAX_NATIVE_STEPS)
  local flags    = optsToFlags(opts)
  if not _pathBackend then _pathBackend = resolveBackend() end

  -- Generate cache key
  local key = makeCacheKey(startPos, goalPos, maxSteps, flags)
  
  -- Try cache first
  local cached = cacheGet(key)
  if cached then
    return cached
  end

  -- Not in cache, compute
  local path = _pathBackend(startPos, goalPos, maxSteps, flags, opts)
  
  -- Cache result (even nil to avoid repeated failed lookups)
  cacheSet(key, path)
  
  return path
end

-- Clear path cache (useful when map changes significantly)
function PathStrategy.clearPathCache()
  _pathCache = {}
  _pathCacheOrder = {}
end

function PathStrategy.stepDuration(diagonal)
  local pu = PU()
  local base = pu and pu.getStepDuration(diagonal) or (diagonal and 280 or 200)
  return math.max(50, base + (diagonal and math.random(-25, 55) or math.random(-25, 40)))
end

function PathStrategy.rawStepDuration(diagonal)
  local pu = PU()
  return pu and pu.getStepDuration(diagonal) or (diagonal and 280 or 200)
end

local _isFC = nil

local function getIsFC()
  if not _isFC then
    _isFC = (PU() and PU().isFloorChangeTile) or function() return false end
  end
  return _isFC
end

function PathStrategy.nativePathIsSafe(startPos, goalPos, opts)
  local nativePath = PathStrategy.findPath(startPos, goalPos, opts or {
    ignoreNonPathable = true,
  })
  if not nativePath or #nativePath == 0 then
    return false, nil, nil
  end
  local isFC = getIsFC()
  local probe = {x = startPos.x, y = startPos.y, z = startPos.z}
  for i = 1, #nativePath do
    local off = dirOffset(nativePath[i])
    if not off then break end
    probe = applyOff(probe, off)
    if isFC(probe) then
      return false, nativePath, i
    end
  end
  return true, nativePath, nil
end

--[[
  Check if an existing path contains a floor-change tile.
  Returns true if path is safe, false + index of first FC step otherwise.
  O(pathLength) — no redundant pathfinding.
]]
function PathStrategy.pathContainsFC(path, startPos)
  if not path or #path == 0 then return false end
  local isFC = getIsFC()
  local probe = {x = startPos.x, y = startPos.y, z = startPos.z}
  for i = 1, #path do
    local off = dirOffset(path[i])
    if not off then break end
    probe = applyOff(probe, off)
    if isFC(probe) then
      return true, i
    end
  end
  return false
end

function PathStrategy.safePrefixDest(startPos, nativePath, unsafeIdx)
  local dest = {x = startPos.x, y = startPos.y, z = startPos.z}
  local safeSteps = math.max(0, (unsafeIdx or 1) - 1)
  for i = 1, safeSteps do
    local off = dirOffset(nativePath[i])
    if off then dest = applyOff(dest, off) end
  end
  return dest, safeSteps
end

--[[
  Search for the nearest floor-change tile on the current floor
  that transitions to targetZ. Uses minimap color (already cached
  by the client) for O(1) lookups. Spiral search guarantees
  finding the nearest tile by Manhattan distance.
  @param fromPos Position on current floor
  @param targetZ number Target Z coordinate
  @param maxRadius number Search radius (default 30)
  @return Position, expectedZ or nil, nil
]]
function PathStrategy.findNearestFC(fromPos, targetZ, maxRadius)
  maxRadius = maxRadius or 30
  if not fromPos or targetZ == nil then return nil end
  local map = g_map
  if not (map and map.getMinimapColor) then return nil end
  local FloorItems = (function()
    local ok, fi = pcall(dofile, "/constants/floor_items.lua")
    if ok and fi then return fi end
    ok, fi = pcall(dofile, "/core/constants/floor_items.lua")
    return ok and fi or nil
  end)()
  local FI = FloorItems
  if not (FI and FI.isFloorChangeColor and FI.getExpectedFloor) then return nil end

  for r = 1, maxRadius do
    local cx, cy = fromPos.x, fromPos.y
    -- Top edge: (cx-r, cy-r) → (cx+r, cy-r)
    local y = cy - r
    for x = cx - r, cx + r do
      local color = map.getMinimapColor({x = x, y = y, z = fromPos.z})
      if color > 0 and FI.isFloorChangeColor(color) and FI.getExpectedFloor(color, fromPos.z) == targetZ then
        return {x = x, y = y, z = fromPos.z}
      end
    end
    -- Bottom edge: (cx-r, cy+r) → (cx+r, cy+r)
    y = cy + r
    for x = cx - r, cx + r do
      local color = map.getMinimapColor({x = x, y = y, z = fromPos.z})
      if color > 0 and FI.isFloorChangeColor(color) and FI.getExpectedFloor(color, fromPos.z) == targetZ then
        return {x = x, y = y, z = fromPos.z}
      end
    end
    -- Left edge (excluding corners): (cx-r, cy-r+1) → (cx-r, cy+r-1)
    local x = cx - r
    for y = cy - r + 1, cy + r - 1 do
      local color = map.getMinimapColor({x = x, y = y, z = fromPos.z})
      if color > 0 and FI.isFloorChangeColor(color) and FI.getExpectedFloor(color, fromPos.z) == targetZ then
        return {x = x, y = y, z = fromPos.z}
      end
    end
    -- Right edge (excluding corners): (cx+r, cy-r+1) → (cx+r, cy+r-1)
    x = cx + r
    for y = cy - r + 1, cy + r - 1 do
      local color = map.getMinimapColor({x = x, y = y, z = fromPos.z})
      if color > 0 and FI.isFloorChangeColor(color) and FI.getExpectedFloor(color, fromPos.z) == targetZ then
        return {x = x, y = y, z = fromPos.z}
      end
    end
  end
  return nil
end

function PathStrategy.walkStep(dir)
  local Client = getClient and getClient()
  if Client and Client.walk then return Client.walk(dir) end
  if g_game and g_game.walk then return g_game.walk(dir, true) end
  if walk then return walk(dir) end
end

function PathStrategy.autoWalk(dest, maxSteps, opts)
  maxSteps = maxSteps or DEFAULT_MAX_STEPS
  opts = opts or {}
  local adapter = nExBot and nExBot.ACL
  if adapter and adapter.game and adapter.game.autoWalk then
    return adapter.game.autoWalk(dest, maxSteps, opts)
  end
  if autoWalk then return autoWalk(dest, maxSteps, opts) end
  if g_game and g_game.autoWalk then return g_game.autoWalk(dest, maxSteps) end
end

function PathStrategy.stopAutoWalk()
  local pu = PU()
  if pu and pu.stopAutoWalk then return pu.stopAutoWalk() end
  if player and player.stopAutoWalk then pcall(player.stopAutoWalk, player) end
end

function PathStrategy.isAutoWalking()
  if player and player.isAutoWalking then return player:isAutoWalking() end
  return false
end

function PathStrategy.isWalking()
  if player and player.isWalking then return player:isWalking() end
  return false
end

PathStrategy.dirOffset  = dirOffset
PathStrategy.applyOffset = applyOff
PathStrategy.tick       = tick

if nExBot then nExBot.PathStrategy = PathStrategy end
return PathStrategy