--[[
  PathStrategy v1.0.0 — Unified Pathfinding & Movement Strategy

  RESPONSIBILITIES:
  1) Single entry point for pathfinding across all ACL flavours (OTBR / OTCv8)
  2) Humanized step-timing with configurable jitter
  3) Direction anti-zigzag and smooth path compilation
  4) Floor-change-aware path validation and safe chunking
  5) PathCursor — lightweight iterator that avoids table.remove churn

  DESIGN:
  - SRP: each function does one thing
  - DRY: delegates to PathUtils for tile queries, ACL adapters for native calls
  - KISS: flat module table, no OOP / inheritance
  - SOLID Open/Closed: callers depend on PathStrategy interface;
    internals can swap ACL backends transparently

  USAGE:
    local PS = PathStrategy          -- global set by _Loader Phase 3
    local path = PS.findPath(from, to, opts)
    local dur  = PS.stepDuration(diagonal)
    local chunk = PS.chunkPath(path, startPos, opts)
]]

local PathStrategy = {}

-- ============================================================================
-- DEPENDENCIES (resolved lazily so load order is flexible)
-- ============================================================================

local PathUtils    = PathUtils           -- global from Phase 3
local getClient    = nExBot and nExBot.Shared and nExBot.Shared.getClient
local A            -- ACL adapter, resolved once at first call

local function acl()
  if A then return A end
  if nExBot and nExBot.ACL then A = nExBot.ACL end
  return A
end

-- safe `now` accessor — OTClient sandbox provides a global int `now`
local function tick()
  return now or (os.clock() * 1000)
end

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Pathfinding flags (OTClient C++ enum Otc::PathFindFlags)
local PF_ALLOW_NOT_SEEN      = 1
local PF_ALLOW_CREATURES      = 2
local PF_ALLOW_NON_PATHABLE   = 4
local PF_ALLOW_NON_WALKABLE   = 8
local PF_IGNORE_CREATURES     = 16

local MAX_NATIVE_STEPS  = 127    -- OTClient A* hard limit
local DEFAULT_MAX_STEPS = 50

-- Humanisation jitter bounds (ms)
local JITTER_MIN   = -25
local JITTER_MAX   =  40
local JITTER_DIAG  =  15         -- extra jitter for diagonal moves

-- Direction constants (must match OTClient globals)
local DIR_NORTH     = North     or 0
local DIR_EAST      = East      or 1
local DIR_SOUTH     = South     or 2
local DIR_WEST      = West      or 3
local DIR_NE        = NorthEast or 4
local DIR_SE        = SouthEast or 5
local DIR_SW        = SouthWest or 6
local DIR_NW        = NorthWest or 7

local DIR_TO_OFFSET = {
  [DIR_NORTH] = {x =  0, y = -1},
  [DIR_EAST]  = {x =  1, y =  0},
  [DIR_SOUTH] = {x =  0, y =  1},
  [DIR_WEST]  = {x = -1, y =  0},
  [DIR_NE]    = {x =  1, y = -1},
  [DIR_SE]    = {x =  1, y =  1},
  [DIR_SW]    = {x = -1, y =  1},
  [DIR_NW]    = {x = -1, y = -1},
}

-- Opposite direction LUT (for anti-zigzag)
local OPPOSITE = {
  [DIR_NORTH] = DIR_SOUTH, [DIR_SOUTH] = DIR_NORTH,
  [DIR_EAST]  = DIR_WEST,  [DIR_WEST]  = DIR_EAST,
  [DIR_NE]    = DIR_SW,    [DIR_SW]    = DIR_NE,
  [DIR_SE]    = DIR_NW,    [DIR_NW]    = DIR_SE,
}

-- Adjacent direction sets (for "similar" check)
local SIMILAR = {
  [DIR_NORTH] = {[DIR_NE]=true, [DIR_NW]=true},
  [DIR_EAST]  = {[DIR_NE]=true, [DIR_SE]=true},
  [DIR_SOUTH] = {[DIR_SE]=true, [DIR_SW]=true},
  [DIR_WEST]  = {[DIR_NW]=true, [DIR_SW]=true},
  [DIR_NE]    = {[DIR_NORTH]=true, [DIR_EAST]=true},
  [DIR_SE]    = {[DIR_EAST]=true, [DIR_SOUTH]=true},
  [DIR_SW]    = {[DIR_SOUTH]=true, [DIR_WEST]=true},
  [DIR_NW]    = {[DIR_WEST]=true, [DIR_NORTH]=true},
}

-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

local function posEq(a, b)
  return a.x == b.x and a.y == b.y and a.z == b.z
end

local function dirOffset(dir)
  return DIR_TO_OFFSET[dir]
end

local function applyOff(p, off)
  return {x = p.x + off.x, y = p.y + off.y, z = p.z}
end

local function chebyshev(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function isDiagonal(dir)
  return dir and dir >= 4
end

--- Pseudo-random jitter for human-like timing.
-- Uses math.random which is already seeded by OTClient.
local function jitter(diagonal)
  local base = JITTER_MIN + math.random() * (JITTER_MAX - JITTER_MIN)
  if diagonal then base = base + math.random() * JITTER_DIAG end
  return math.floor(base)
end

-- ============================================================================
-- PATHFINDING — ACL-UNIFIED ENTRY POINT
-- ============================================================================

--- Build native flags from human-readable option table.
local function optsToFlags(opts)
  local flags = 0
  if opts.allowUnseen       then flags = flags + PF_ALLOW_NOT_SEEN end
  if opts.allowCreatures    then flags = flags + PF_ALLOW_CREATURES end
  if opts.ignoreNonPathable then flags = flags + PF_ALLOW_NON_PATHABLE end
  if opts.ignoreNonWalkable then flags = flags + PF_ALLOW_NON_WALKABLE end
  if opts.ignoreCreatures   then flags = flags + PF_IGNORE_CREATURES end
  return flags
end

--- Find a path from `startPos` to `goalPos`.
-- Tries native API through ACL first, then falls back to bare global.
--
-- @param startPos table {x,y,z}
-- @param goalPos  table {x,y,z}
-- @param opts     table (optional) {
--   maxSteps:int, allowUnseen:bool, ignoreCreatures:bool,
--   ignoreNonPathable:bool, ignoreFields:bool, precision:int
-- }
-- @return {dir,...}|nil  array of direction ints, or nil
function PathStrategy.findPath(startPos, goalPos, opts)
  opts = opts or {}
  local maxSteps = math.min(opts.maxSteps or DEFAULT_MAX_STEPS, MAX_NATIVE_STEPS)
  local flags    = optsToFlags(opts)

  -- 1) Try ACL adapter (cross-client safe)
  local adapter = acl()
  if adapter and adapter.map and adapter.map.findPath then
    local ok, result = pcall(adapter.map.findPath, startPos, goalPos, {
      maxSteps = maxSteps,
      flags    = flags,
    })
    if ok and result and #result > 0 then return result end
  end

  -- 2) Bare sandbox global (always available in OTClient)
  if findPath then
    local ok, result = pcall(findPath, startPos, goalPos, maxSteps, opts)
    if ok and result and #result > 0 then return result end
  end

  -- 3) Raw g_map.findPath
  if g_map and g_map.findPath then
    local ok, result = pcall(g_map.findPath, startPos, goalPos, maxSteps, flags)
    if ok and result and #result > 0 then return result end
  end

  return nil
end

--- Multi-attempt pathfinding with progressive relaxation.
-- @return path, wasRelaxed
function PathStrategy.findPathRelaxed(startPos, goalPos, opts)
  opts = opts or {}
  local base = {
    maxSteps          = opts.maxSteps or DEFAULT_MAX_STEPS,
    ignoreNonPathable = true,
    ignoreCreatures   = opts.ignoreCreatures or false,
    ignoreFields      = opts.ignoreFields or false,
    precision         = opts.precision or 0,
  }

  -- Attempt 1: strict (visible tiles only)
  local path = PathStrategy.findPath(startPos, goalPos, base)
  if path then return path, false end

  -- Attempt 2: ignore creatures
  base.ignoreCreatures = true
  path = PathStrategy.findPath(startPos, goalPos, base)
  if path then return path, false end

  -- Attempt 3: allow unseen tiles
  base.allowUnseen = true
  path = PathStrategy.findPath(startPos, goalPos, base)
  if path then return path, false end

  -- Attempt 4: ignore fields (relaxed)
  if not opts.ignoreFields then
    base.ignoreFields = true
    path = PathStrategy.findPath(startPos, goalPos, base)
    if path then return path, true end
  end

  return nil, false
end

-- ============================================================================
-- HUMANISED STEP TIMING
-- ============================================================================

local _stepCache = { cardinal = 0, diagonal = 0, ts = 0 }
local STEP_CACHE_TTL = 1000   -- 1 s

--- Get humanised step duration (with jitter) for the local player.
function PathStrategy.stepDuration(diagonal)
  local t = tick()
  if (t - _stepCache.ts) > STEP_CACHE_TTL then
    local ok, p = pcall(function()
      if player and player.getStepDuration then
        return player
      end
    end)
    if ok and p then
      local cOk, c = pcall(p.getStepDuration, p, false)
      local dOk, d = pcall(p.getStepDuration, p, true)
      _stepCache.cardinal = cOk and c or 200
      _stepCache.diagonal = dOk and d or 280
    else
      _stepCache.cardinal = 200
      _stepCache.diagonal = 280
    end
    _stepCache.ts = t
  end
  local base = diagonal and _stepCache.diagonal or _stepCache.cardinal
  return math.max(50, base + jitter(diagonal))
end

--- Raw step duration (no jitter) for pure timing calculations.
function PathStrategy.rawStepDuration(diagonal)
  local t = tick()
  if (t - _stepCache.ts) > STEP_CACHE_TTL then
    PathStrategy.stepDuration(false) -- refresh cache
  end
  return diagonal and _stepCache.diagonal or _stepCache.cardinal
end

-- ============================================================================
-- DIRECTION ANALYSIS (anti-zigzag)
-- ============================================================================

local _dirState = {
  last      = nil,
  changes   = 0,
  lastTs    = 0,
  stability = 1.0,
}

function PathStrategy.isSimilar(d1, d2)
  if d1 == nil or d2 == nil then return true end
  if d1 == d2 then return true end
  local s = SIMILAR[d1]
  return s and s[d2] or false
end

function PathStrategy.isOpposite(d1, d2)
  return OPPOSITE[d1] == d2
end

--- Update anti-zigzag state and return smoothed direction.
-- @param dir       int  Direction constant
-- @param forceChange bool  When true, bypass dampening (used near FC tiles)
function PathStrategy.smoothDirection(dir, forceChange)
  if not dir then return dir end
  if forceChange then
    _dirState.last   = dir
    _dirState.lastTs = tick()
    _dirState.changes = 0
    return dir
  end
  local t = tick()

  if _dirState.last then
    if PathStrategy.isOpposite(_dirState.last, dir) then
      -- Dampen opposite direction changes
      if (t - _dirState.lastTs) < 200 then
        return _dirState.last  -- hold previous
      end
    end

    if not PathStrategy.isSimilar(_dirState.last, dir) then
      _dirState.changes = _dirState.changes + 1
      _dirState.stability = math.max(0, _dirState.stability - 0.15)
    else
      _dirState.changes = math.max(0, _dirState.changes - 1)
      _dirState.stability = math.min(1.0, _dirState.stability + 0.05)
    end

    -- If too many rapid changes, hold direction
    if _dirState.changes >= 3 and (t - _dirState.lastTs) < 200 then
      _dirState.changes = 0
      return _dirState.last
    end
  end

  _dirState.last   = dir
  _dirState.lastTs = t
  return dir
end

function PathStrategy.resetDirectionState()
  _dirState.last      = nil
  _dirState.changes   = 0
  _dirState.lastTs    = 0
  _dirState.stability = 1.0
end

-- ============================================================================
-- PATH SMOOTHING — zigzag-to-diagonal conversion
-- ============================================================================

local function directionTo(from, to)
  local dx = to.x - from.x
  local dy = to.y - from.y
  local nx = dx == 0 and 0 or (dx > 0 and 1 or -1)
  local ny = dy == 0 and 0 or (dy > 0 and 1 or -1)
  if nx ==  0 and ny == -1 then return DIR_NORTH end
  if nx ==  1 and ny ==  0 then return DIR_EAST end
  if nx ==  0 and ny ==  1 then return DIR_SOUTH end
  if nx == -1 and ny ==  0 then return DIR_WEST end
  if nx ==  1 and ny == -1 then return DIR_NE end
  if nx ==  1 and ny ==  1 then return DIR_SE end
  if nx == -1 and ny ==  1 then return DIR_SW end
  if nx == -1 and ny == -1 then return DIR_NW end
  return nil
end

--- Smooth a direction-array path by converting 2-step L-shapes into diagonals
-- when the diagonal tile is walkable. Returns a new array (does not mutate).
function PathStrategy.smoothPath(path, startPos)
  if not path or #path < 3 then return path end

  local smoothed = {}
  local p = {x = startPos.x, y = startPos.y, z = startPos.z}
  local i = 1
  local len = #path

  while i <= len do
    local d1 = path[i]
    local o1 = dirOffset(d1)
    if not o1 then
      smoothed[#smoothed + 1] = d1
      i = i + 1
    elseif i + 1 <= len then
      local d2 = path[i + 1]
      local o2 = dirOffset(d2)
      local merged = false
      -- Try to merge two cardinal moves into one diagonal
      if o2 and d1 ~= d2 and not isDiagonal(d1) and not isDiagonal(d2) then
        local diagPos = {x = p.x + o1.x + o2.x, y = p.y + o1.y + o2.y, z = p.z}
        local diagDir = directionTo(p, diagPos)
        if diagDir then
          -- Validate diagonal tile is safe
          local safe = true
          if PathUtils and PathUtils.isTileSafe then
            safe = PathUtils.isTileSafe(diagPos, false)
          else
            local tile = g_map and g_map.getTile(diagPos)
            safe = tile and tile:isWalkable() or false
          end
          if safe then
            -- Also verify the diagonal doesn't cross a floor change
            local fcSafe = true
            if PathUtils and PathUtils.isFloorChangeTile then
              fcSafe = not PathUtils.isFloorChangeTile(diagPos)
            end
            if fcSafe then
              smoothed[#smoothed + 1] = diagDir
              p = diagPos
              i = i + 2
              merged = true
            end
          end
        end
      end
      if not merged then
        -- no merge — emit d1 as-is
        smoothed[#smoothed + 1] = d1
        p = applyOff(p, o1)
        i = i + 1
      end
    else
      smoothed[#smoothed + 1] = d1
      p = applyOff(p, o1)
      i = i + 1
    end
  end

  return #smoothed > 0 and smoothed or path
end

-- ============================================================================
-- PATH CURSOR — lightweight iterator over a direction array
-- ============================================================================

local Cursor = {
  path      = nil,
  idx       = 1,
  ts        = 0,
  ttl       = 800,
  dest      = nil,
  chunkEnd  = nil,
  chunkDir  = nil,
  chunkTs   = 0,
  smoothed  = false,
}

function PathStrategy.setCursor(path, dest)
  Cursor.path     = path
  Cursor.idx      = 1
  Cursor.ts       = tick()
  Cursor.ttl      = 800
  Cursor.dest     = dest
  Cursor.chunkEnd = nil
  Cursor.chunkDir = nil
  Cursor.chunkTs  = 0
  Cursor.smoothed = false
end

function PathStrategy.resetCursor()
  Cursor.path     = nil
  Cursor.idx      = 1
  Cursor.ts       = 0
  Cursor.dest     = nil
  Cursor.chunkEnd = nil
  Cursor.chunkDir = nil
  Cursor.chunkTs  = 0
  Cursor.smoothed = false
end

function PathStrategy.getCursor()
  return Cursor
end

--- Check if the cursor cache is still valid for a given destination.
function PathStrategy.isCursorValid(dest)
  if not Cursor.path then return false end
  if Cursor.idx > #Cursor.path then return false end
  if (tick() - Cursor.ts) >= Cursor.ttl then return false end
  if not Cursor.dest then return false end
  return posEq(Cursor.dest, dest)
end

--- Advance cursor index by n steps and refresh TTL.
function PathStrategy.advanceCursor(steps, stepDur)
  Cursor.idx = math.min(Cursor.idx + steps, (Cursor.path and #Cursor.path or 0) + 1)
  Cursor.ts  = tick()
  Cursor.ttl = math.max(800, steps * (stepDur or 200) * 0.85)
end

-- ============================================================================
-- FLOOR-CHANGE SAFETY CHECK (native path verification)
-- ============================================================================

local _isFC = nil -- lazy-init

local function getIsFC()
  if not _isFC then
    _isFC = (PathUtils and PathUtils.isFloorChangeTile) or function() return false end
  end
  return _isFC
end

--- Compute the native A* path from start to goal and verify it doesn't cross
--- any floor-change tile.  Returns (isSafe, nativePath, unsafeIndex).
---
--- This catches the case where the *planned* direction-path is safe but the
--- actual native autowalk route would shortcut through a hole or stair.
---
--- @param startPos table {x,y,z}
--- @param goalPos  table {x,y,z}
--- @param opts     table|nil  same as findPath opts (optional)
--- @return boolean isSafe
--- @return table|nil nativePath (dir array, only when isSafe==true)
--- @return number|nil unsafeIdx  first unsafe step index (when isSafe==false)
function PathStrategy.nativePathIsSafe(startPos, goalPos, opts)
  local nativePath = PathStrategy.findPath(startPos, goalPos, opts or {
    ignoreNonPathable = true,
  })
  if not nativePath or #nativePath == 0 then
    return false, nil, nil   -- no path at all
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

--- Return the longest safe prefix of nativePath (stops before the first FC
--- tile).  Useful for reducing a chunk destination to a safe intermediate.
--- @return table safeDestPos, int safeSteps
function PathStrategy.safePrefixDest(startPos, nativePath, unsafeIdx)
  local dest = {x = startPos.x, y = startPos.y, z = startPos.z}
  local safeSteps = math.max(0, (unsafeIdx or 1) - 1)
  for i = 1, safeSteps do
    local off = dirOffset(nativePath[i])
    if off then dest = applyOff(dest, off) end
  end
  return dest, safeSteps
end

-- ============================================================================
-- FLOOR-CHANGE-AWARE CHUNKING
-- ============================================================================

--- Scan a direction-array path for the number of safe steps before a floor
-- change tile is reached.
-- @return safeSteps (int)
function PathStrategy.safeStepCount(path, startPos, fromIdx)
  fromIdx = fromIdx or 1
  local probe = {x = startPos.x, y = startPos.y, z = startPos.z}
  local safe  = 0
  local isFC  = PathUtils and PathUtils.isFloorChangeTile or function() return false end

  for i = fromIdx, #path do
    local off = dirOffset(path[i])
    if not off then break end
    probe = applyOff(probe, off)
    if isFC(probe) then break end
    safe = safe + 1
  end
  return safe
end

--- Compute optimal chunk size based on path characteristics.
-- Short path → small chunk; long/straight → large chunk; zigzag → smaller.
function PathStrategy.optimalChunk(path, safeSteps, maxChunk)
  maxChunk = maxChunk or 40
  local len = #path
  local chunk = math.min(safeSteps, maxChunk)

  if len <= 5 then
    chunk = math.min(chunk, len)
  elseif len <= 15 then
    chunk = math.min(chunk, 12)
  end

  -- Penalise zigzag
  local changes, last = 0, nil
  for i = 1, math.min(chunk, len) do
    if last and path[i] ~= last then changes = changes + 1 end
    last = path[i]
  end
  if chunk >= 6 and changes > chunk * 0.6 then
    chunk = math.max(4, math.floor(chunk * 0.65))
  end

  return chunk
end

--- Build the chunk destination position from cursor state.
function PathStrategy.chunkDestination(path, startPos, fromIdx, steps)
  local dest = {x = startPos.x, y = startPos.y, z = startPos.z}
  local endIdx = math.min(fromIdx + steps - 1, #path)
  for i = fromIdx, endIdx do
    local off = dirOffset(path[i])
    if off then dest = applyOff(dest, off) end
  end
  return dest
end

-- ============================================================================
-- MOVEMENT DISPATCH (ACL-aware)
-- ============================================================================

--- Walk a single step in the given direction.
function PathStrategy.walkStep(dir)
  local Client = getClient and getClient()
  if Client and Client.walk then
    return Client.walk(dir)
  end
  if g_game and g_game.walk then
    return g_game.walk(dir, true) -- prewalk=true
  end
  if walk then return walk(dir) end
end

--- AutoWalk to a destination via the native autowalk system.
function PathStrategy.autoWalk(dest, maxSteps, opts)
  maxSteps = maxSteps or DEFAULT_MAX_STEPS
  opts = opts or {}
  local adapter = acl()
  if adapter and adapter.game and adapter.game.autoWalk then
    return adapter.game.autoWalk(dest, maxSteps, opts)
  end
  if autoWalk then
    return autoWalk(dest, maxSteps, opts)
  end
  if g_game and g_game.autoWalk then
    return g_game.autoWalk(dest, maxSteps)
  end
end

--- Stop any ongoing autowalk.
function PathStrategy.stopAutoWalk()
  if PathUtils and PathUtils.stopAutoWalk then
    return PathUtils.stopAutoWalk()
  end
  if player and player.stopAutoWalk then
    pcall(player.stopAutoWalk, player)
  end
end

--- Check if player is currently autowalking.
function PathStrategy.isAutoWalking()
  if player and player.isAutoWalking then
    return player:isAutoWalking()
  end
  return false
end

--- Check if player is walking at all.
function PathStrategy.isWalking()
  if player and player.isWalking then
    return player:isWalking()
  end
  return false
end

-- ============================================================================
-- CONVENIENCE
-- ============================================================================

PathStrategy.posEquals           = posEq
PathStrategy.dirOffset           = dirOffset
PathStrategy.applyOffset         = applyOff
PathStrategy.chebyshevDistance    = chebyshev
PathStrategy.directionTo         = directionTo
PathStrategy.tick                = tick
PathStrategy.DIR_TO_OFFSET       = DIR_TO_OFFSET
PathStrategy.OPPOSITE            = OPPOSITE
PathStrategy.SIMILAR             = SIMILAR

-- ============================================================================
-- FULL RESET (call on CaveBot.resetWalking)
-- ============================================================================

function PathStrategy.fullReset()
  PathStrategy.resetCursor()
  PathStrategy.resetDirectionState()
  _stepCache.ts = 0
end

-- ============================================================================
-- GLOBAL EXPORT
-- ============================================================================

if _G then _G.PathStrategy = PathStrategy end
return PathStrategy
