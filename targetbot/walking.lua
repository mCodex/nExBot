--[[
  TargetBot Walking Module - Optimized Pathfinding
  
  Uses path caching and progressive pathfinding for better performance.
  Integrates with TargetBot's creature cache for efficient walking.
]]

local dest = nil
local maxDist = nil
local params = nil

-- Path cache for TargetBot walking
local WalkCache = {
  path = nil,
  destKey = nil,
  timestamp = 0,
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
  
  -- Invalidate cache if destination changed
  local newKey = getCacheKey(_dest)
  if newKey ~= WalkCache.destKey then
    WalkCache.path = nil
    WalkCache.destKey = newKey
    WalkCache.timestamp = 0
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
  if WalkCache.path and #WalkCache.path > 0 and (now - WalkCache.timestamp) < WalkCache.TTL then
    -- Use cached path - take first step
    walk(WalkCache.path[1])
    -- Remove used step from cache
    table.remove(WalkCache.path, 1)
    return
  end
  
  -- Calculate new path
  local path = getPath(playerPos, dest, maxDist or 10, params)
  
  if path and #path > 0 then
    -- Cache the path
    WalkCache.path = path
    WalkCache.timestamp = now
    
    -- Take first step
    walk(path[1])
    table.remove(WalkCache.path, 1)
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
