--[[
  TargetBot Walking Module - Optimized Pathfinding
  
  Uses path caching and progressive pathfinding for better performance.
  Integrates with TargetBot's creature cache for efficient walking.
]]

local dest = nil
local maxDist = nil
local params = nil

-- Floor-change detection (to prevent unintended Z changes during chase/avoid)
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

local FLOOR_CHANGE_COLORS = {
  [210] = true, [211] = true, [212] = true, [213] = true,
}

-- Subset of floor-change items sufficient to detect stairs/ramps/holes common in hunts
local FLOOR_CHANGE_ITEMS = {
  -- Stairs up/down
  [414]=true,[415]=true,[416]=true,[417]=true,[428]=true,[429]=true,[430]=true,[431]=true,
  [432]=true,[433]=true,[434]=true,[435]=true,[1949]=true,[1950]=true,[1951]=true,[1952]=true,[1953]=true,[1954]=true,[1955]=true,
  -- Ramps
  [1956]=true,[1957]=true,[1958]=true,[1959]=true,[1385]=true,[1396]=true,[1397]=true,[1398]=true,[1399]=true,[1400]=true,[1401]=true,[1402]=true,
  -- Ladders/Rope spots
  [1219]=true,[1386]=true,[3678]=true,[5543]=true,[384]=true,[386]=true,[418]=true,
  -- Holes/Trapdoors
  [294]=true,[369]=true,[370]=true,[383]=true,[392]=true,[408]=true,[409]=true,[410]=true,[469]=true,[470]=true,[482]=true,[484]=true,[423]=true,[424]=true,[425]=true,
  -- Teleports/Portals
  [502]=true,[1387]=true,[2129]=true,[2130]=true,[8709]=true,
}

local function isFloorChangeTile(pos)
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isFloorChangeTile then
    return TargetCore.PathSafety.isFloorChangeTile(pos)
  end
  if not pos then return false end
  local color = g_map.getMinimapColor(pos)
  if FLOOR_CHANGE_COLORS[color] then return true end
  local tile = g_map.getTile(pos)
  if not tile then return false end
  local ground = tile:getGround()
  if ground and FLOOR_CHANGE_ITEMS[ground:getId()] then return true end
  local topUse = tile:getTopUseThing()
  if topUse and topUse:isItem() and FLOOR_CHANGE_ITEMS[topUse:getId()] then return true end
  local top = tile:getTopThing()
  if top and top:isItem() and FLOOR_CHANGE_ITEMS[top:getId()] then return true end
  return false
end

local function pathCrossesFloorChange(path, startPos)
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.pathCrossesFloorChange then
    return TargetCore.PathSafety.pathCrossesFloorChange(path, startPos)
  end
  if not path or #path == 0 or not startPos then return false end
  local probe = {x = startPos.x, y = startPos.y, z = startPos.z}
  for i = 1, #path do
    local off = DIR_TO_OFFSET[path[i]]
    if off then
      probe.x = probe.x + off.x
      probe.y = probe.y + off.y
      if isFloorChangeTile(probe) then
        return true
      end
    end
  end
  return false
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
  
  -- Check if following a player (for "Follow While Attacking" feature)
  -- We don't skip pathfinding for monsters anymore since we use custom pathfinding for chase
  if g_game.getFollowingCreature then
    local currentFollow = g_game.getFollowingCreature()
    if currentFollow and currentFollow:isPlayer() and not currentFollow:isLocalPlayer() then
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
        g_game.cancelFollow()
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
    TargetBot.walk()
  end
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
    local off = DIR_TO_OFFSET[WalkCache.path[WalkCache.idx]]
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
    walk(WalkCache.path[WalkCache.idx])
    WalkCache.idx = WalkCache.idx + 1
    return
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
    walk(path[WalkCache.idx])
    WalkCache.idx = WalkCache.idx + 1
  end
  
  -- Clear destination after attempting walk
  dest = nil
end

-- Clear walking state
TargetBot.clearWalk = function()
  dest = nil
  WalkCache.path = nil
  WalkCache.timestamp = 0
end
