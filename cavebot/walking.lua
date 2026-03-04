--[[
  CaveBot Walking Module v6.0.0

  Simplified rewrite. Delegates to PathStrategy for pathfinding, cursor,
  smoothing, and timing.  This file is pure orchestration.

  PUBLIC API:
    CaveBot.walkTo(dest, maxDist, params) -> true | false | "nudge"
    CaveBot.safeWalkTo(dest, maxDist, params)
    CaveBot.resetWalking()
    CaveBot.fullResetWalking()
    CaveBot.stopAutoWalk
    CaveBot.isFloorChangeTile
    CaveBot.isNearFloorChangeTile
    CaveBot.getStepDuration(diagonal)
    CaveBot.isPlayerWalking()
    CaveBot.doWalking()
]]

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================

local PathUtils    = PathUtils
if not PathUtils then
  local ok, mod = pcall(require, "utils.path_utils")
  if ok and mod then PathUtils = mod end
end

-- Lazy resolver: PathStrategy may not be a direct global in the sandbox.
-- Primary: nExBot.PathStrategy (set by path_strategy.lua). Fallback: bare global.
-- Null-object NOOP_PS ensures PS() NEVER returns nil (defense-in-depth).
local NOOP_PS = setmetatable({}, {__index = function() return function() end end})
local _ps = nil
local function PS()
  if _ps and _ps ~= NOOP_PS then return _ps end
  _ps = (nExBot and nExBot.PathStrategy) or PathStrategy
  return _ps or NOOP_PS
end

-- Safeguard stubs (overwritten below)
if not CaveBot then CaveBot = {} end
if not CaveBot.resetWalking then CaveBot.resetWalking = function() end end
if not CaveBot.fullResetWalking then CaveBot.fullResetWalking = function() end end

local getClient = nExBot.Shared.getClient

-- ============================================================================
-- DIRECTION & TILE UTILITIES (thin delegates)
-- ============================================================================

local Dirs          = Directions or {}
local DIR_TO_OFFSET = Dirs.DIR_TO_OFFSET or {}

local function canWalkDirection(dir)
  return (player.canWalk and player:canWalk(dir)) or true
end

local function getDirectionTo(fromPos, toPos)
  local dx = toPos.x - fromPos.x
  local dy = toPos.y - fromPos.y
  local nx = dx == 0 and 0 or (dx > 0 and 1 or -1)
  local ny = dy == 0 and 0 or (dy > 0 and 1 or -1)
  if nx == 0 and ny == -1 then return North end
  if nx == 1 and ny == 0  then return East end
  if nx == 0 and ny == 1  then return South end
  if nx == -1 and ny == 0 then return West end
  if nx == 1 and ny == -1 then return NorthEast end
  if nx == 1 and ny == 1  then return SouthEast end
  if nx == -1 and ny == 1 then return SouthWest end
  if nx == -1 and ny == -1 then return NorthWest end
  return nil
end

local function applyOffset(p, off)
  return {x = p.x + off.x, y = p.y + off.y, z = p.z}
end

local function posEquals(a, b)
  return a.x == b.x and a.y == b.y and a.z == b.z
end

local function isFloorChangeTile(tilePos)
  return PathUtils and PathUtils.isFloorChangeTile(tilePos) or false
end

local function isFieldTile(tilePos)
  return PathUtils and PathUtils.isFieldTile(tilePos) or false
end

local function isNearFloorChangeTile(tilePos)
  if PathUtils and PathUtils.isNearFloorChangeTile then
    return PathUtils.isNearFloorChangeTile(tilePos)
  end
  if isFloorChangeTile(tilePos) then return true end
  local adjOffs = Dirs.ADJACENT_OFFSETS or {}
  for _, off in ipairs(adjOffs) do
    if isFloorChangeTile(applyOffset(tilePos, off)) then return true end
  end
  return false
end

local function stopAutoWalk()
  if PathUtils and PathUtils.stopAutoWalk then PathUtils.stopAutoWalk(); return end
  if player and player.stopAutoWalk then player:stopAutoWalk() end
  if g_game and g_game.stop then g_game.stop() end
end

-- ============================================================================
-- KEYBOARD NUDGE (fallback when pathfinding fails)
-- ============================================================================

local ADJACENT_DIRS = {}
if Directions and Directions.ADJACENT then
  for dir, neighbours in pairs(Directions.ADJACENT) do
    local arr = {}
    for nd, _ in pairs(neighbours) do arr[#arr + 1] = nd end
    ADJACENT_DIRS[dir] = arr
  end
end

local lastNudgeDir  = nil
local lastNudgeTime = 0

--- Try a single keyboard step toward dest. Returns "nudge" or false.
local function tryKeyboardNudge(playerPos, dest)
  if not playerPos or not dest then return false end
  if player:isWalking() then return false end

  local dir = getDirectionTo(playerPos, dest)
  if dir == nil then return false end

  local candidates = { dir }
  local adj = ADJACENT_DIRS[dir]
  if adj then candidates[2] = adj[1]; candidates[3] = adj[2] end

  -- Anti-oscillation
  if dir == lastNudgeDir and now - lastNudgeTime < 500 and adj then
    candidates = { adj[1], adj[2], dir }
  end

  for _, d in ipairs(candidates) do
    if canWalkDirection(d) then
      local off = DIR_TO_OFFSET[d]
      if off then
        local target = {x = playerPos.x + off.x, y = playerPos.y + off.y, z = playerPos.z}
        if not isFloorChangeTile(target) then
          PS().walkStep(d)
          lastNudgeDir  = d
          lastNudgeTime = now
          return "nudge"
        end
      end
    end
  end
  return false
end

-- ============================================================================
-- MODULE STATE (minimal)
-- ============================================================================

local lastWalkZ   = nil
local lastSafePos = nil
local MAX_PATHFIND_DIST = 50

-- ============================================================================
-- CORE: FIND A WALKABLE PATH
-- Tries cached cursor first, then strict, then relaxed.
-- Always validates first step against canWalkDirection before accepting.
-- ============================================================================

--- Check if a direction (or its smoothed variant) is physically walkable.
--- Returns the walkable direction, or nil.
local function resolveWalkableDir(dir)
  if PS() == NOOP_PS then return canWalkDirection(dir) and dir or nil end
  local smoothed = PS().smoothDirection(dir) or dir
  if canWalkDirection(smoothed) then return smoothed end
  if smoothed ~= dir and canWalkDirection(dir) then return dir end
  return nil
end

--- Find a path whose first step is physically walkable.
--- Returns path (dir array) or nil, wasRelaxed (bool)
local function findWalkablePath(playerPos, dest, opts)
  if PS() == NOOP_PS then return nil end
  -- 1) Try PathStrategy cursor cache
  if PS().isCursorValid and PS().isCursorValid(dest) then
    local cursor = PS().getCursor()
    if cursor then
      local path = cursor.path
      local idx  = cursor.idx
      if path and idx and idx <= #path then
        if resolveWalkableDir(path[idx]) then
          return path, false
        end
        -- First step blocked -> cache is stale
        PS().resetCursor()
      end
    end
  end

  local maxSteps = opts.maxSteps or MAX_PATHFIND_DIST

  -- 2) STRICT pathfinding (no ignoreNonPathable -> won't path through walls)
  local strictOpts = {
    maxSteps        = maxSteps,
    ignoreCreatures = opts.ignoreCreatures or false,
    ignoreFields    = opts.ignoreFields or false,
    precision       = opts.precision or 0,
  }
  local path = PS().findPath(playerPos, dest, strictOpts)

  -- 2b) Strict + ignoreCreatures
  if not path then
    strictOpts.ignoreCreatures = true
    path = PS().findPath(playerPos, dest, strictOpts)
  end

  if path and #path > 0 and resolveWalkableDir(path[1]) then
    PS().setCursor(path, dest)
    local sm = PS().smoothPath(path, playerPos)
    if sm and #sm > 0 and #sm <= #path then
      path = sm
      local cur = PS().getCursor()
      if cur then cur.path = path end
    end
    return path, false
  end

  -- 3) RELAXED pathfinding (last resort, includes ignoreNonPathable)
  local relaxedPath, wasRelaxed = PS().findPathRelaxed(playerPos, dest, {
    maxSteps        = maxSteps,
    ignoreCreatures = opts.ignoreCreatures or false,
    ignoreFields    = opts.ignoreFields or false,
    precision       = opts.precision or 0,
  })

  if relaxedPath and #relaxedPath > 0 and resolveWalkableDir(relaxedPath[1]) then
    PS().setCursor(relaxedPath, dest)
    local sm = PS().smoothPath(relaxedPath, playerPos)
    if sm and #sm > 0 and #sm <= #relaxedPath then
      relaxedPath = sm
      local cur = PS().getCursor()
      if cur then cur.path = relaxedPath end
    end
    return relaxedPath, wasRelaxed
  end

  -- No walkable path found
  return nil, false
end

-- ============================================================================
-- DISPATCH: KEYBOARD STEP vs AUTOWALK
-- ============================================================================

local KEYBOARD_THRESHOLD = 12

--- Walk a single keyboard step along the path. Returns true on success.
local function keyboardStep(path, playerPos, curIdx)
  local dir = path[curIdx]
  if not dir then return false end

  local walkDir = resolveWalkableDir(dir)
  if not walkDir then return false end

  PS().walkStep(walkDir)
  PS().advanceCursor(1, PS().rawStepDuration(walkDir >= 4))
  return true
end

--- Walk via autoWalk for longer distances. Returns true on success.
local function autoWalkDispatch(path, playerPos, curIdx, safeSteps, maxDist)
  local chunkSteps = math.min(safeSteps, 40)
  local chunkDest  = PS().chunkDestination(path, playerPos, curIdx, chunkSteps)

  -- Don't interrupt ongoing walk toward same destination
  if player:isWalking() then
    local d = math.abs(playerPos.x - chunkDest.x) + math.abs(playerPos.y - chunkDest.y)
    if d <= chunkSteps + 2 then return true end
  end

  -- Verify native autoWalk path won't cross floor-change tiles
  local isSafe, nPath, unsafeIdx = PS().nativePathIsSafe(playerPos, chunkDest)
  if not isSafe then
    if nPath and unsafeIdx and unsafeIdx > 1 then
      local safeDest, safeN = PS().safePrefixDest(playerPos, nPath, unsafeIdx)
      if safeN >= 2 then
        chunkDest  = safeDest
        chunkSteps = safeN
        isSafe = true
      end
    end
    if not isSafe then
      return keyboardStep(path, playerPos, curIdx)
    end
  end

  local precision = chunkSteps >= 10 and 1 or 0
  PS().autoWalk(chunkDest, maxDist, {ignoreNonPathable = true, precision = precision})
  PS().advanceCursor(chunkSteps, PS().rawStepDuration(false))
  return true
end

-- ============================================================================
-- MAIN: CaveBot.walkTo
-- ============================================================================

CaveBot.walkTo = function(dest, maxDist, params)
  local playerPos = pos()
  if not playerPos then return false end

  params = params or {}
  local precision        = params.precision or 1
  local allowFloorChange = params.allowFloorChange or false
  local ignoreCreatures  = params.ignoreCreatures or false
  local ignoreFields     = params.ignoreFields
  if ignoreFields == nil then
    ignoreFields = CaveBot.Config and CaveBot.Config.get and CaveBot.Config.get("ignoreFields") or false
  end
  maxDist = math.min(maxDist or 20, MAX_PATHFIND_DIST)

  -- Track last safe position (away from FC tiles)
  if not lastSafePos and not isNearFloorChangeTile(playerPos) then
    lastSafePos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  end

  -- Z-change detection -> let main loop Z-handler take over
  if lastWalkZ and playerPos.z ~= lastWalkZ then
    lastWalkZ = playerPos.z
    lastSafePos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
    return false
  end
  lastWalkZ = playerPos.z

  -- Already at destination?
  local distX = math.abs(dest.x - playerPos.x)
  local distY = math.abs(dest.y - playerPos.y)
  if distX <= precision and distY <= precision and dest.z == playerPos.z then
    return true
  end

  -- Floor mismatch
  if dest.z ~= playerPos.z then return false end

  -- Reset anti-zigzag for short walks
  if PS() ~= NOOP_PS and math.max(distX, distY) <= 5 then PS().resetDirectionState() end

  -- ========== FLOOR-CHANGE PATH (special handling) ==========
  if allowFloorChange then
    if player:isWalking() then return true end
    local manhattan = distX + distY

    if manhattan <= 3 then
      -- Close: precise keyboard steps
      local fcPath = PS().findPath(playerPos, dest, {ignoreNonPathable = true, precision = 0})
      if fcPath and #fcPath > 0 then
        local dir = fcPath[1]
        local smoothed = PS().smoothDirection(dir, true) or dir
        if canWalkDirection(smoothed) then
          PS().walkStep(smoothed)
        elseif canWalkDirection(dir) then
          PS().walkStep(dir)
        end
      end
      return true
    else
      -- Far: guarded autoWalk
      local isSafe = PS().nativePathIsSafe(playerPos, dest, {ignoreNonPathable = true})
      if isSafe then
        PS().autoWalk(dest, maxDist, {ignoreNonPathable = true, precision = precision})
      else
        local dirToDest = getDirectionTo(playerPos, dest)
        if dirToDest and canWalkDirection(dirToDest) then
          PS().walkStep(dirToDest)
        end
      end
      return true
    end
  end

  -- ========== NORMAL PATH ==========

  -- Redirect if dest itself is a FC tile
  if isFloorChangeTile(dest) then
    for _, off in ipairs(Dirs.ADJACENT_OFFSETS or {}) do
      local alt = applyOffset(dest, off)
      if not isFloorChangeTile(alt) then
        local altPath = PS().findPath(playerPos, alt, {
          ignoreNonPathable = true, ignoreCreatures = true, precision = 0,
        })
        if altPath and #altPath > 0 then dest = alt; break end
      end
    end
  end

  -- Find a path with first-step validation
  local path, wasRelaxed = findWalkablePath(playerPos, dest, {
    maxSteps        = maxDist,
    ignoreCreatures = ignoreCreatures,
    ignoreFields    = ignoreFields,
    precision       = precision,
  })

  if not path then
    return tryKeyboardNudge(playerPos, dest)
  end

  -- Count safe steps before first FC tile
  local cursor  = PS().getCursor()
  local curIdx  = (cursor and cursor.idx) or 1
  local safeSteps = PS().safeStepCount(path, playerPos, curIdx)

  if safeSteps == 0 then
    PS().resetCursor()
    return tryKeyboardNudge(playerPos, dest)
  end

  local remaining   = #path - curIdx + 1
  local stepsToWalk = math.min(safeSteps, remaining)
  if stepsToWalk <= 0 then
    PS().resetCursor()
    return tryKeyboardNudge(playerPos, dest)
  end

  local curObj = PS().getCursor()
  if curObj then curObj.dest = dest end

  -- Field handling: keyboard-walk through field tiles
  if ignoreFields or wasRelaxed then
    local peekDir = path[curIdx]
    local peekOff = peekDir and DIR_TO_OFFSET[peekDir]
    if peekOff then
      local peekPos = applyOffset(playerPos, peekOff)
      if isFieldTile(peekPos) then
        local currentPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
        local lastWalked = curIdx - 1
        for i = curIdx, #path do
          local d   = path[i]
          local off = DIR_TO_OFFSET[d]
          if not off then break end
          local nextPos = applyOffset(currentPos, off)
          if not isFieldTile(nextPos) then break end
          if isFloorChangeTile(nextPos) then break end
          walk(d)
          currentPos = nextPos
          lastWalked = i
          if posEquals(currentPos, dest) then
            PS().resetCursor()
            return true
          end
        end
        local fc = PS().getCursor()
        if fc then fc.idx = lastWalked + 1 end
        return true
      end
    end
  end

  -- Dispatch: keyboard for short paths, autoWalk for long
  if stepsToWalk <= KEYBOARD_THRESHOLD then
    if keyboardStep(path, playerPos, curIdx) then return true end
    PS().resetCursor()
    return tryKeyboardNudge(playerPos, dest)
  else
    if autoWalkDispatch(path, playerPos, curIdx, safeSteps, maxDist) then return true end
    PS().resetCursor()
    return tryKeyboardNudge(playerPos, dest)
  end
end

-- ============================================================================
-- CONVENIENCE & PUBLIC API
-- ============================================================================

CaveBot.safeWalkTo = function(dest, maxDist, params)
  params = params or {}
  params.allowFloorChange = false
  return CaveBot.walkTo(dest, maxDist, params)
end

CaveBot.getStepDuration = function(diagonal)
  if PS() == NOOP_PS then return 200 end
  return PS().stepDuration(diagonal or false)
end

CaveBot.isPlayerWalking = function()
  return player and player.isWalking and player:isWalking()
end

CaveBot.getWalkWaitTime = function()
  if not CaveBot.isPlayerWalking() then return 0 end
  if PS() == NOOP_PS then return 200 end
  return PS().rawStepDuration(false)
end

CaveBot.isPositionWalkable = function(checkPos, ignoreCreatures)
  if PathUtils and PathUtils.isTileWalkable then
    return PathUtils.isTileWalkable(checkPos, ignoreCreatures or false)
  end
  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile(checkPos))
  return tile and tile:isWalkable(ignoreCreatures or false) or false
end

CaveBot.doWalking = function()
  return player and player:isWalking()
end

CaveBot.resetWalking = function()
  lastWalkZ = nil
  if PS() then PS().fullReset() end
end

CaveBot.fullResetWalking = function()
  CaveBot.resetWalking()
  lastSafePos = nil
end

CaveBot.stopAutoWalk          = stopAutoWalk
CaveBot.isFloorChangeTile     = isFloorChangeTile
CaveBot.isNearFloorChangeTile = isNearFloorChangeTile

-- ============================================================================
-- EVENT: Position change (update safe pos, handle floor change)
-- ============================================================================

onPlayerPositionChange(function(newPos, oldPos)
  if zChanging() then return end
  if not oldPos or not newPos then return end

  if oldPos.z == newPos.z then
    if not isNearFloorChangeTile(oldPos) then
      lastSafePos = {x = oldPos.x, y = oldPos.y, z = oldPos.z}
    end
    return
  end

  -- Floor change: accept new position, let main loop Z-handler deal with it
  lastSafePos = {x = newPos.x, y = newPos.y, z = newPos.z}
end)

return true
