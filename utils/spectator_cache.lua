-- Lightweight cached wrapper around g_map.getSpectatorsInRange to reduce expensive map queries
-- Performance optimized with EventBus integration for auto-invalidation
-- v1.1: Integrated WeakCache for automatic memory cleanup

local SpectatorCache = {}

-- Use WeakCache if available for memory-efficient storage
local WC = WeakCache
local cache = (WC and WC.createTTL) and WC.createTTL(200) or {}
local useTTLCache = (WC and WC.createTTL) ~= nil

local DEFAULT_TTL = 200 -- milliseconds

-- Performance counters
local stats = {
  hits = 0,
  misses = 0,
  invalidations = 0
}

-- Use global ClientHelper (loaded by _Loader.lua)
local function getClient()
    return ClientHelper and ClientHelper.getClient() or ClientService
end

local function makeKey(rx, ry)
  return tostring(rx) .. "x" .. tostring(ry)
end

SpectatorCache.getNearby = function(rx, ry, ttl)
  ttl = ttl or DEFAULT_TTL
  local key = makeKey(rx or 10, ry or 10)
  
  -- Use TTL cache API if available
  if useTTLCache then
    local cached = cache:get(key)
    if cached then
      stats.hits = stats.hits + 1
      return cached
    end
    stats.misses = stats.misses + 1
    
    local ok, res = pcall(function()
      local Client = getClient()
      local player = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer()) or nil
      if not player then return {} end
      local pos = player:getPosition()
      return (Client and Client.getSpectatorsInRange) and Client.getSpectatorsInRange(pos, false, rx, ry) or (g_map and g_map.getSpectatorsInRange(pos, false, rx, ry)) or {}
    end)
    local data = ok and res or {}
    cache:set(key, data, ttl)
    return data
  end
  
  -- Fallback: simple cache
  local entry = cache[key]
  if entry and entry.ts and (now - entry.ts) < ttl then
    stats.hits = stats.hits + 1
    return entry.data
  end
  stats.misses = stats.misses + 1
  local ok, res = pcall(function()
    local Client = getClient()
    local player = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer()) or nil
    if not player then return {} end
    local pos = player:getPosition()
    return (Client and Client.getSpectatorsInRange) and Client.getSpectatorsInRange(pos, false, rx, ry) or (g_map and g_map.getSpectatorsInRange(pos, false, rx, ry)) or {}
  end)
  local data = ok and res or {}
  cache[key] = { ts = now, data = data }
  return data
end

-- Utility to clear cache (for tests or forced refresh)
SpectatorCache.clear = function()
  if useTTLCache then
    cache:clear()
  else
    cache = {}
  end
  stats.invalidations = stats.invalidations + 1
end

-- Get performance stats
SpectatorCache.getStats = function()
  local total = stats.hits + stats.misses
  return {
    hits = stats.hits,
    misses = stats.misses,
    invalidations = stats.invalidations,
    hitRate = total > 0 and (stats.hits / total) or 0
  }
end

-- Auto-invalidate on player position change (EventBus integration)
if EventBus and EventBus.on then
  EventBus.on("player:move", function(newPos, oldPos)
    -- Only invalidate if player actually changed tiles
    if newPos and oldPos and (newPos.x ~= oldPos.x or newPos.y ~= oldPos.y or newPos.z ~= oldPos.z) then
      SpectatorCache.clear()
    end
  end, 5) -- Lower priority to run after more critical handlers
end

return SpectatorCache
