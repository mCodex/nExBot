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

local _PU           -- PathUtils, resolved once on first call
local getClient    = nExBot and nExBot.Shared and nExBot.Shared.getClient
local A            -- ACL adapter, resolved once at first call

local function PU()
  if _PU then return _PU end
  _PU = PathUtils  -- global set by path_utils.lua
  return _PU
end

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

-- Direction constants
local DIR_NORTH     = North     or 0
local DIR_EAST      = East      or 1
local DIR_SOUTH     = South     or 2
local DIR_WEST      = West      or 3
local DIR_NE        = NorthEast or 4
local DIR_SE        = SouthEast or 5
local DIR_SW        = SouthWest or 6
local DIR_NW        = NorthWest or 7

-- Direction tables: resolved lazily from Directions / PathUtils globals
-- (may not be set yet during Phase 3 file load)
local DIR_TO_OFFSET, OPPOSITE, SIMILAR
local function _ensureDirTables()
  if DIR_TO_OFFSET then return end
  local D = Directions
  if D then
    DIR_TO_OFFSET = D.DIR_TO_OFFSET
    OPPOSITE      = D.OPPOSITE
    SIMILAR       = D.ADJACENT
  end
end

-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

-- Lazy-resolved PathUtils helpers
local _posEq, _chebyshev, _directionTo
local function _ensureHelpers()
  if _posEq then return end
  local pu = PU()
  if not pu then return end
  _posEq      = pu.posEquals
  _chebyshev  = pu.chebyshevDistance
  _directionTo = pu.getDirectionTo
end

local function dirOffset(dir)
  _ensureDirTables()
  return DIR_TO_OFFSET and DIR_TO_OFFSET[dir]
end

local function applyOff(p, off)
  return {x = p.x + off.x, y = p.y + off.y, z = p.z}
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
-- PATHFINDING — ACL-UNIFIED ENTRY POINT (one-time backend detection)
-- ============================================================================

--- Build native flags from human-readable option table.
-- Caches result on the opts table to avoid recomputation on same-reference calls.
local function optsToFlags(opts)
  if opts._cachedFlags then return opts._cachedFlags end
  local flags = 0
  if opts.allowUnseen       then flags = flags + PF_ALLOW_NOT_SEEN end
  if opts.allowCreatures    then flags = flags + PF_ALLOW_CREATURES end
  if opts.ignoreNonPathable then flags = flags + PF_ALLOW_NON_PATHABLE end
  if opts.ignoreNonWalkable then flags = flags + PF_ALLOW_NON_WALKABLE end
  if opts.ignoreCreatures   then flags = flags + PF_IGNORE_CREATURES end
  opts._cachedFlags = flags
  return flags
end

-- Resolved once on first findPath call, then reused
local _pathBackend = nil  -- function(startPos, goalPos, maxSteps, flags, opts) -> path|nil

local function resolveBackend()
  -- 1) ACL adapter (cross-client safe)
  local adapter = acl()
  if adapter and adapter.map and adapter.map.findPath then
    return function(startPos, goalPos, maxSteps, flags, _opts)
      local ok, result = pcall(adapter.map.findPath, startPos, goalPos, {
        maxSteps = maxSteps, flags = flags,
      })
      if ok and result and #result > 0 then return result end
      return nil
    end
  end
  -- 2) Bare sandbox global (always available in OTClient)
  if findPath then
    return function(startPos, goalPos, maxSteps, _flags, opts)
      local ok, result = pcall(findPath, startPos, goalPos, maxSteps, opts)
      if ok and result and #result > 0 then return result end
      return nil
    end
  end
  -- 3) Raw g_map.findPath
  if g_map and g_map.findPath then
    return function(startPos, goalPos, maxSteps, flags, _opts)
      local ok, result = pcall(g_map.findPath, startPos, goalPos, maxSteps, flags)
      if ok and result and #result > 0 then return result end
      return nil
    end
  end
  -- No backend available (should never happen in OTClient)
  return function() return nil end
end

--- Find a path from `startPos` to `goalPos`.
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

  if not _pathBackend then _pathBackend = resolveBackend() end
  return _pathBackend(startPos, goalPos, maxSteps, flags, opts)
end

--- Multi-attempt pathfinding with progressive relaxation.
-- @return path, wasRelaxed
function PathStrategy.findPathRelaxed(startPos, goalPos, opts)
  opts = opts or {}
  local base = {
    maxSteps          = opts.maxSteps or DEFAULT_MAX_STEPS,
    ignoreCreatures   = opts.ignoreCreatures or false,
    ignoreFields      = opts.ignoreFields or false,
    precision         = opts.precision or 0,
  }

  -- Attempt 1: truly strict (no ignoreNonPathable — respects PZ, invisible walls)
  local path = PathStrategy.findPath(startPos, goalPos, base)
  if path then return path, false end

  -- Attempt 2: allow non-pathable tiles (relaxes PZ borders, etc.)
  base._cachedFlags = nil
  base.ignoreNonPathable = true
  path = PathStrategy.findPath(startPos, goalPos, base)
  if path then return path, false end

  -- Attempt 3: ignore creatures
  base._cachedFlags = nil
  base.ignoreCreatures = true
  path = PathStrategy.findPath(startPos, goalPos, base)
  if path then return path, false end

  -- Early exit: for far destinations (>30 tiles), attempts 4+5 are unlikely to help
  -- and just waste CPU. They only matter for close-range blocked tiles.
  local dx = math.abs(goalPos.x - startPos.x)
  local dy = math.abs(goalPos.y - startPos.y)
  if (dx + dy) > 30 then
    return nil, false
  end

  -- Attempt 4: allow unseen tiles
  base._cachedFlags = nil
  base.allowUnseen = true
  path = PathStrategy.findPath(startPos, goalPos, base)
  if path then return path, false end

  -- Attempt 5: ignore fields (relaxed)
  if not opts.ignoreFields then
    base._cachedFlags = nil
    base.ignoreFields = true
    path = PathStrategy.findPath(startPos, goalPos, base)
    if path then return path, true end
  end

  return nil, false
end

-- ============================================================================
-- HUMANISED STEP TIMING (DRY: raw duration from PathUtils, jitter added here)
-- ============================================================================

--- Get humanised step duration (with jitter) for the local player.
function PathStrategy.stepDuration(diagonal)
  local pu = PU()
  local base = pu and pu.getStepDuration(diagonal) or (diagonal and 280 or 200)
  return math.max(50, base + jitter(diagonal))
end

--- Raw step duration (no jitter) for pure timing calculations.
function PathStrategy.rawStepDuration(diagonal)
  local pu = PU()
  return pu and pu.getStepDuration(diagonal) or (diagonal and 280 or 200)
end

-- ============================================================================
-- DIRECTION GUARD (sole anti-zigzag system — replaces all others)
-- 3-entry ring buffer, 150ms opposite rejection, dampening after 3 rapid changes
-- ============================================================================

local _dirRing = {nil, nil, nil}  -- 3 most recent directions
local _dirRingHead = 1
local _dirRingSize = 0
local _dirLastTs = 0
local _dirRapidChanges = 0
local _dirDampenUntil = 0         -- timestamp: hold direction until this time

-- DRY: delegate to PathUtils (SSoT for direction relationship checks)
-- Lazy wrappers since PathUtils may not be loaded yet at file scope
function PathStrategy.isSimilar(a, b)
  _ensureHelpers()
  _ensureDirTables()
  -- Fast inline check using SIMILAR table as fallback
  if SIMILAR and SIMILAR[a] then return SIMILAR[a][b] == true end
  local pu = PU()
  return pu and pu.areSimilarDirections and pu.areSimilarDirections(a, b) or false
end
function PathStrategy.isOpposite(a, b)
  _ensureDirTables()
  if OPPOSITE then return OPPOSITE[a] == b end
  local pu = PU()
  return pu and pu.areOppositeDirections and pu.areOppositeDirections(a, b) or false
end

--- Update anti-zigzag state and return smoothed direction.
-- @param dir       int  Direction constant
-- @param forceChange bool  When true, bypass dampening (used near FC tiles)
function PathStrategy.smoothDirection(dir, forceChange)
  if not dir then return dir end
  local t = tick()

  if forceChange then
    -- Force: accept direction, reset state
    _dirRing[_dirRingHead] = dir
    _dirRingHead = (_dirRingHead % 3) + 1
    _dirRingSize = math.min(_dirRingSize + 1, 3)
    _dirLastTs = t
    _dirRapidChanges = 0
    _dirDampenUntil = 0
    return dir
  end

  -- If dampening is active, hold the last accepted direction
  if t < _dirDampenUntil then
    local lastAccepted = _dirRing[((_dirRingHead - 2) % 3) + 1]
    return lastAccepted or dir
  end

  local lastDir = _dirRingSize > 0 and _dirRing[((_dirRingHead - 2) % 3) + 1] or nil

  -- Same direction — no change needed
  if lastDir and dir == lastDir then
    _dirRapidChanges = math.max(0, _dirRapidChanges - 1)
    return dir
  end

  -- Opposite direction rejection: if last direction was set <150ms ago, reject
  if lastDir and PathStrategy.isOpposite(lastDir, dir) then
    if (t - _dirLastTs) < 150 then
      return lastDir
    end
  end

  -- Track rapid direction changes
  if lastDir and not PathStrategy.isSimilar(lastDir, dir) then
    _dirRapidChanges = _dirRapidChanges + 1
  else
    _dirRapidChanges = math.max(0, _dirRapidChanges - 1)
  end

  -- If 3+ rapid changes, dampen for one step duration (~200ms)
  if _dirRapidChanges >= 3 then
    _dirRapidChanges = 0
    _dirDampenUntil = t + 200
    return lastDir or dir
  end

  -- Accept the new direction
  _dirRing[_dirRingHead] = dir
  _dirRingHead = (_dirRingHead % 3) + 1
  _dirRingSize = math.min(_dirRingSize + 1, 3)
  _dirLastTs = t
  return dir
end

function PathStrategy.resetDirectionState()
  _dirRing = {nil, nil, nil}
  _dirRingHead = 1
  _dirRingSize = 0
  _dirLastTs = 0
  _dirRapidChanges = 0
  _dirDampenUntil = 0
end

-- ============================================================================
-- PATH SMOOTHING — zigzag-to-diagonal conversion
-- ============================================================================

-- Lazy wrapper for directionTo
local function directionTo(from, to)
  _ensureHelpers()
  if _directionTo then return _directionTo(from, to) end
  -- Inline fallback: compute direction from offset
  local dx = to.x - from.x
  local dy = to.y - from.y
  if dx ~= 0 then dx = dx > 0 and 1 or -1 end
  if dy ~= 0 then dy = dy > 0 and 1 or -1 end
  _ensureDirTables()
  local key = dx .. "," .. dy
  local D = Directions
  return D and D.OFFSET_TO_DIR and D.OFFSET_TO_DIR[key]
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
          local pu = PU()
          if pu and pu.isTileSafe then
            safe = pu.isTileSafe(diagPos, false)
          else
            local tile = g_map and g_map.getTile(diagPos)
            safe = tile and tile:isWalkable() or false
          end
          if safe then
            -- Also verify the diagonal doesn't cross a floor change
            local fcSafe = true
            if pu and pu.isFloorChangeTile then
              fcSafe = not pu.isFloorChangeTile(diagPos)
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
}

function PathStrategy.setCursor(path, dest)
  Cursor.path     = path
  Cursor.idx      = 1
  Cursor.ts       = tick()
  Cursor.ttl      = 800
  Cursor.dest     = dest
end

function PathStrategy.resetCursor()
  Cursor.path     = nil
  Cursor.idx      = 1
  Cursor.ts       = 0
  Cursor.dest     = nil
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
  _ensureHelpers()
  return _posEq and _posEq(Cursor.dest, dest) or
    (Cursor.dest.x == dest.x and Cursor.dest.y == dest.y and Cursor.dest.z == dest.z)
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
    _isFC = (PU() and PU().isFloorChangeTile) or function() return false end
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
  local pu = PU()
  local isFC  = (pu and pu.isFloorChangeTile) or function() return false end

  for i = 1, math.max(0, fromIdx - 1) do
    local off = dirOffset(path[i])
    if not off then break end
    probe = applyOff(probe, off)
    if isFC(probe) then break end
  end

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
  local pu = PU()
  if pu and pu.stopAutoWalk then
    return pu.stopAutoWalk()
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
-- CONVENIENCE (DRY: lazy aliases to PathUtils / Directions SSoT)
-- These are resolved on first access via __index so load order doesn't matter.
-- ============================================================================

PathStrategy.dirOffset           = dirOffset
PathStrategy.applyOffset         = applyOff
PathStrategy.tick                = tick

-- Set lazy-resolved aliases after first real call
local _convenienceResolved = false
local function _resolveConvenience()
  if _convenienceResolved then return end
  _convenienceResolved = true
  _ensureHelpers()
  _ensureDirTables()
  local pu = PU()
  if pu then
    PathStrategy.posEquals        = pu.posEquals
    PathStrategy.chebyshevDistance = pu.chebyshevDistance
    PathStrategy.directionTo      = pu.getDirectionTo
    PathStrategy.DIR_TO_OFFSET    = pu.DIR_TO_OFFSET
  end
  local D = Directions
  if D then
    PathStrategy.OPPOSITE         = D.OPPOSITE
    PathStrategy.SIMILAR          = D.ADJACENT
  end
end

-- Resolve on first external access via module metatable
setmetatable(PathStrategy, {
  __index = function(t, k)
    _resolveConvenience()
    return rawget(t, k)
  end
})

-- ============================================================================
-- FULL RESET (call on CaveBot.resetWalking)
-- ============================================================================

function PathStrategy.fullReset()
  PathStrategy.resetCursor()
  PathStrategy.resetDirectionState()
end

-- ============================================================================
-- GLOBAL EXPORT
-- ============================================================================

if _G then _G.PathStrategy = PathStrategy end
return PathStrategy
