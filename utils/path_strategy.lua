--[[
  PathStrategy v2.0.0 — Unified Pathfinding & Movement Strategy
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
  return _pathBackend(startPos, goalPos, maxSteps, flags, opts)
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

function PathStrategy.safePrefixDest(startPos, nativePath, unsafeIdx)
  local dest = {x = startPos.x, y = startPos.y, z = startPos.z}
  local safeSteps = math.max(0, (unsafeIdx or 1) - 1)
  for i = 1, safeSteps do
    local off = dirOffset(nativePath[i])
    if off then dest = applyOff(dest, off) end
  end
  return dest, safeSteps
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

if _G then _G.PathStrategy = PathStrategy end
if nExBot then nExBot.PathStrategy = PathStrategy end
return PathStrategy
