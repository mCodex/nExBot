--[[
  TargetBot Walking Module - Optimized Pathfinding intelligence.0.0
  
  Uses path caching and progressive pathfinding for better performance.
  Integrates with TargetBot's creature cache for efficient walking.
  
  intelligence.0.0: Integrated PathUtils for DRY, added anti-zigzag, native API optimization
]]

local getClient = nExBot.Shared.getClient

local getClientVersion = nExBot.Shared.getClientVersion

-- PathUtils is set as global by path_utils.lua (loaded in Phase 3 by _Loader)
local SharedHelpers = nExBot.SharedHelpers or {}
local function ensurePathUtils()
  if PathUtils then return PathUtils end
  SharedHelpers.ensurePathUtils()
  return PathUtils
end
ensurePathUtils()

local dest = nil
local maxDist = nil
local params = nil

-- Use PathUtils for direction offsets if available, else fallback
local DIR_TO_OFFSET = (PathUtils and PathUtils.DIR_TO_OFFSET) or {
  [North] = {x = 0, y = -1},
  [East] = {x = 1, y = 0},
  [South] = {x = 0, y = 1},
  [West] = {x = -1, y = 0},
  [NorthEast] = {x = 1, y = -1},
  [SouthEast] = {x = 1, y = 1},
  [SouthWest] = {x = -1, y = 1},
  [NorthWest] = {x = -1, y = -1}
}

-- Use PathUtils for floor-change detection (DRY, guaranteed loaded by ensurePathUtils)
local function isFloorChangeTile(pos)
  return PathUtils.isFloorChangeTile(pos)
end

-- Use TargetCore for path floor-change validation (DRY)
local function pathCrossesFloorChange(path, startPos)
  return TargetCore.PathSafety.pathCrossesFloorChange(path, startPos)
end

-- Use PathUtils for direction relationship checks (DRY)
local function areSimilarDirections(dir1, dir2)
  return PathUtils.areSimilarDirections(dir1, dir2)
end

local function areOppositeDirections(dir1, dir2)
  return PathUtils.areOppositeDirections(dir1, dir2)
end

-- Path cache for TargetBot walking
local WalkCache = {
  path = nil,
  destKey = nil,
  timestamp = 0,
  idx = 1,
  TTL = 200  -- Short TTL for combat responsiveness
}

-- Generate cache key
local function getCacheKey(destination)
  if not destination then return nil end
  return destination.x .. "," .. destination.y .. "," .. destination.z
end

TargetBot.walkTo = function(_dest, _maxDist, _params)
  dest = _dest
  maxDist = _maxDist
  params = _params or {}
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- NATIVE CHASE MODE CHECK
  -- When OTClient native chase mode is active (setChaseMode(1) + attacking),
  -- skip custom pathfinding - let the client handle walking automatically.
  -- This prevents interference with the native chase behavior.
  -- ═══════════════════════════════════════════════════════════════════════════
  if TargetBot.usingNativeChase then
    -- Check if we're actually attacking (native chase only works when attacking)
    local Client = getClient()
    local isAttacking = (Client and Client.isAttacking) and Client.isAttacking() or (g_game and g_game.isAttacking and g_game.isAttacking())
    if isAttacking then
      -- Verify chase mode is still set correctly
      local chaseMode = (Client and Client.getChaseMode) and Client.getChaseMode() or (g_game and g_game.getChaseMode and g_game.getChaseMode()) or 0
      if chaseMode == 1 then
        -- Native chase is active and working, skip custom walking
        dest = nil
        return true  -- Return true to indicate chase is handling movement
      end
    end
  end
  
  -- Check if following a player (for "Follow While Attacking" feature)
  -- We don't skip pathfinding for monsters anymore since we use custom pathfinding for chase
  local Client = getClient()
  local currentFollow = (Client and Client.getFollowingCreature) and Client.getFollowingCreature() or (g_game and g_game.getFollowingCreature and g_game.getFollowingCreature())
  if currentFollow then
    if currentFollow:isPlayer() and not currentFollow:isLocalPlayer() then
      -- Check if following a player with "Follow While Attacking" enabled
      local shouldKeepFollow = false
      if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        local followConfig = CharacterDB.get("tools.followPlayer")
        if followConfig and followConfig.enabled and followConfig.followWhileAttacking then
          local targetName = followConfig.playerName and followConfig.playerName:trim():lower() or ""
          local followName = currentFollow:getName():lower()
          if targetName ~= "" and (followName == targetName or followName:find(targetName, 1, true)) then
            shouldKeepFollow = true
          end
        end
      end
      
      if shouldKeepFollow then
        -- Following a player, skip custom pathfinding
        dest = nil
        return
      else
        -- Not a configured follow target, cancel and use custom pathfinding
        if Client and Client.cancelFollow then
          Client.cancelFollow()
        elseif g_game and g_game.cancelFollow then
          g_game.cancelFollow()
        end
      end
    end
  end
  
  -- Invalidate cache if destination changed
  local newKey = getCacheKey(_dest)
  if newKey ~= WalkCache.destKey then
    WalkCache.path = nil
    WalkCache.destKey = newKey
    WalkCache.timestamp = 0
    WalkCache.idx = 1
  end
  
  -- IMMEDIATE WALK: Execute first step right away instead of waiting for next tick
  -- This fixes the timing issue where TargetBot.walk() was called before walkTo()
  if dest and not player:isWalking() then
    return TargetBot.walk()
  end
  return true
end

-- Called every 100ms if targeting or looting is active
TargetBot.walk = function()
  if not dest then return end
  if player:isWalking() then return end
  
  local playerPos = player:getPosition()
  if not playerPos then return end
  if playerPos.z ~= dest.z then 
    dest = nil
    return 
  end

  -- Abort if player unexpectedly changed floor mid-chase (path likely invalid)
  if WalkCache.lastZ and WalkCache.lastZ ~= playerPos.z then
    dest = nil
    WalkCache.path = nil
    WalkCache.idx = 1
    WalkCache.timestamp = 0
    WalkCache.destKey = nil
    return
  end
  WalkCache.lastZ = playerPos.z
  
  -- Calculate distance
  local distX = math.abs(playerPos.x - dest.x)
  local distY = math.abs(playerPos.y - dest.y)
  local dist = math.max(distX, distY)
  
  -- Check precision
  if params.precision and params.precision >= dist then 
    dest = nil
    return 
  end
  
  -- Check margin range
  if params.marginMin and params.marginMax then
    if dist >= params.marginMin and dist <= params.marginMax then 
      dest = nil
      return
    end
  end
  
  -- Check cache
  if WalkCache.path and WalkCache.idx <= #WalkCache.path and (now - WalkCache.timestamp) < WalkCache.TTL then
    -- Safety: abort if next step leads to floor change
    local nextPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
    local nextDir = WalkCache.path[WalkCache.idx]
    local off = DIR_TO_OFFSET[nextDir]
    if off then
      nextPos.x = nextPos.x + off.x
      nextPos.y = nextPos.y + off.y
      if isFloorChangeTile(nextPos) then
        dest = nil
        WalkCache.path = nil
        WalkCache.idx = 1
        return
      end
    end
    
    -- Use cached path - take first step
    local moved = walk(nextDir) ~= false
    WalkCache.idx = WalkCache.idx + 1
    return moved
  end
  
  -- Calculate new path
  -- Safety: if destination itself is a floor-change tile, abort chase/avoid move
  if isFloorChangeTile(dest) then
    dest = nil
    WalkCache.path = nil
    WalkCache.idx = 1
    WalkCache.timestamp = 0
    WalkCache.destKey = nil
    return
  end

  local path = getPath(playerPos, dest, maxDist or 10, params)
  
  if path and #path > 0 then
    -- Abort if path crosses floor-change tiles (prevents unintended Z changes)
    if pathCrossesFloorChange(path, playerPos) then
      dest = nil
      WalkCache.path = nil
      WalkCache.idx = 1
      return
    end
    -- Cache the path
    WalkCache.path = path
    WalkCache.timestamp = now
    WalkCache.idx = 1
    
    -- Take first step
    local moved = walk(path[1]) ~= false
    WalkCache.idx = WalkCache.idx + 1
    dest = nil
    return moved
  end
  
  -- Clear destination after attempting walk
  dest = nil
  return false
end

-- Clear walking state
TargetBot.clearWalk = function()
  dest = nil
  WalkCache.path = nil
  WalkCache.timestamp = 0
end
