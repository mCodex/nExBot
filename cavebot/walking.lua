--[[
  CaveBot Walking Module v7.0.0
  Simplified: linear walkTo, no keyboard nudge, no findWalkablePath, no cursor cache.
]]

local PathUtils = PathUtils
if not PathUtils then
  local ok, mod = pcall(require, "utils.path_utils")
  if ok and mod then PathUtils = mod end
end

local NOOP_PS = setmetatable({}, {__index = function() return function() end end})
local _ps = nil
local function PS()
  if _ps and _ps ~= NOOP_PS then return _ps end
  _ps = (nExBot and nExBot.PathStrategy) or PathStrategy
  return _ps or NOOP_PS
end

if not CaveBot then CaveBot = {} end
if not CaveBot.resetWalking then CaveBot.resetWalking = function() end end
if not CaveBot.fullResetWalking then CaveBot.fullResetWalking = function() end end

local Dirs = Directions or {}
local DIR_TO_OFFSET = Dirs.DIR_TO_OFFSET or {}
local ADJACENT_OFFSETS = Dirs.ADJACENT_OFFSETS or {
  {x=0,y=-1},{x=1,y=0},{x=0,y=1},{x=-1,y=0},
  {x=1,y=-1},{x=1,y=1},{x=-1,y=1},{x=-1,y=-1}
}

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

local function canWalkDirection(dir)
  return (player.canWalk and player:canWalk(dir)) or true
end

local function applyOffset(p, off)
  return {x = p.x + off.x, y = p.y + off.y, z = p.z}
end

local function posEquals(a, b)
  return a.x == b.x and a.y == b.y and a.z == b.z
end

local function stopAutoWalk()
  if PathUtils and PathUtils.stopAutoWalk then PathUtils.stopAutoWalk(); return end
  if player and player.stopAutoWalk then player:stopAutoWalk() end
  if g_game and g_game.stop then g_game.stop() end
end

local lastWalkZ = nil
local MAX_PATHFIND_DIST = 50

CaveBot.walkTo = function(dest, maxDist, params)
  local playerPos = pos()
  if not playerPos then return false end

  params = params or {}
  local precision = params.precision or 1
  local allowFloorChange = params.allowFloorChange or false
  local ignoreCreatures = params.ignoreCreatures or false
  local ignoreFields = params.ignoreFields
  if ignoreFields == nil then
    ignoreFields = CaveBot.Config and CaveBot.Config.get and CaveBot.Config.get("ignoreFields") or false
  end
  maxDist = math.min(maxDist or 20, MAX_PATHFIND_DIST)

  if lastWalkZ and playerPos.z ~= lastWalkZ then
    lastWalkZ = playerPos.z
    return false
  end
  lastWalkZ = playerPos.z

  local distX = math.abs(dest.x - playerPos.x)
  local distY = math.abs(dest.y - playerPos.y)
  if distX <= precision and distY <= precision and dest.z == playerPos.z then
    return true
  end

  if dest.z ~= playerPos.z then return false end

  -- Floor-change handling: single direct step when adjacent, autoWalk when far
  if allowFloorChange then
    if player:isWalking() then return true end
    local manhattan = distX + distY
    if manhattan <= 2 then
      local dir = getDirectionTo(playerPos, dest)
      if dir and canWalkDirection(dir) then
        PS().walkStep(dir)
        return true
      end
      return false
    else
      PS().autoWalk(dest, maxDist, {ignoreNonPathable = true, precision = 0})
      return true
    end
  end

  -- Redirect if dest is a floor-change tile (walk to adjacent instead)
  local isFC = PathUtils and PathUtils.isFloorChangeTile
  if isFC and isFC(dest) then
    for _, off in ipairs(ADJACENT_OFFSETS) do
      local alt = applyOffset(dest, off)
      if not isFC(alt) then
        dest = alt
        break
      end
    end
  end

  -- Single findPath call with progressive escalation
  local opts = {
    maxSteps = maxDist,
    ignoreCreatures = ignoreCreatures,
    ignoreFields = ignoreFields,
    precision = precision,
  }
  local path = PS().findPath(playerPos, dest, opts)

  -- Escalation: if no path, try ignoring creatures
  if not path then
    opts.ignoreCreatures = true
    path = PS().findPath(playerPos, dest, opts)
  end

  -- Escalation: if still no path, allow non-pathable tiles
  if not path then
    opts.ignoreNonPathable = true
    path = PS().findPath(playerPos, dest, opts)
  end

  if not path then return false end

  -- Validate the native autoWalk route won't cross floor-change tiles
  local safeChunk = nil
  local isSafe, nPath, unsafeIdx = PS().nativePathIsSafe(playerPos, dest, {
    ignoreNonPathable = opts.ignoreNonPathable,
    ignoreCreatures = opts.ignoreCreatures,
  })
  if isSafe then
    safeChunk = dest
  elseif nPath and unsafeIdx and unsafeIdx > 1 then
    safeChunk, _ = PS().safePrefixDest(playerPos, nPath, unsafeIdx)
  else
    return false
  end

  -- Walk near (keyboard steps) or far (autoWalk)
  local remaining = math.max(distX, distY)
  if remaining <= 3 then
    local dir = path[1]
    if dir and canWalkDirection(dir) then
      PS().walkStep(dir)
      return true
    end
    return false
  else
    PS().autoWalk(safeChunk, maxDist, {
      ignoreNonPathable = opts.ignoreNonPathable,
      ignoreCreatures = opts.ignoreCreatures,
      precision = math.max(0, precision - 1),
    })
    return true
  end
end

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
  local Client = nExBot.Shared.getClient()
  local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile(checkPos))
  return tile and tile:isWalkable(ignoreCreatures or false) or false
end

CaveBot.doWalking = function()
  return player and player:isWalking()
end

CaveBot.resetWalking = function()
  lastWalkZ = nil
end

CaveBot.fullResetWalking = function()
  CaveBot.resetWalking()
end

CaveBot.stopAutoWalk = stopAutoWalk
CaveBot.isFloorChangeTile = PathUtils and PathUtils.isFloorChangeTile or function() return false end

return true
