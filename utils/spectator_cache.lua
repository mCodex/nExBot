-- Lightweight cached wrapper around g_map.getSpectatorsInRange to reduce expensive map queries
local SpectatorCache = {}
local cache = {} -- key -> {ts = now, data = {...}}
local DEFAULT_TTL = 200 -- milliseconds

local function makeKey(rx, ry)
  return tostring(rx) .. "x" .. tostring(ry)
end

SpectatorCache.getNearby = function(rx, ry, ttl)
  ttl = ttl or DEFAULT_TTL
  local key = makeKey(rx or 10, ry or 10)
  local entry = cache[key]
  if entry and entry.ts and (now - entry.ts) < ttl then
    return entry.data
  end
  local ok, res = pcall(function()
    local player = g_game and g_game.getLocalPlayer() or nil
    if not player then return {} end
    local pos = player:getPosition()
    return g_map.getSpectatorsInRange(pos, false, rx, ry)
  end)
  local data = ok and res or {}
  cache[key] = { ts = now, data = data }
  return data
end

-- Utility to clear cache (for tests or forced refresh)
SpectatorCache.clear = function()
  cache = {}
end

return SpectatorCache
