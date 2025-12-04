--[[
  nExBot Path Cache
  Caches calculated paths to reduce CPU usage
  Implements TTL-based cache eviction
  
  Author: nExBot Team
  Version: 1.0.0
]]

local PathCache = {
  cache = {},
  maxCacheSize = 100,
  ttl = 30000,  -- 30 seconds in milliseconds
  hits = 0,
  misses = 0
}

-- Create a new PathCache instance
function PathCache:new(options)
  options = options or {}
  
  local instance = {
    cache = {},
    maxCacheSize = options.maxSize or 100,
    ttl = options.ttl or 30000,
    hits = 0,
    misses = 0
  }
  
  setmetatable(instance, { __index = self })
  return instance
end

-- Generate cache key from positions
function PathCache:getKey(startPos, endPos)
  return string.format("%d_%d_%d_%d_%d_%d",
    startPos.x, startPos.y, startPos.z,
    endPos.x, endPos.y, endPos.z)
end

-- Get cached path
function PathCache:get(startPos, endPos)
  local key = self:getKey(startPos, endPos)
  local cached = self.cache[key]
  
  if cached then
    local currentTime = g_clock and g_clock.millis() or (now or 0)
    
    if (currentTime - cached.timestamp) < self.ttl then
      self.hits = self.hits + 1
      cached.lastAccess = currentTime
      return cached.path
    else
      -- Expired, remove it
      self.cache[key] = nil
    end
  end
  
  self.misses = self.misses + 1
  return nil
end

-- Store path in cache
function PathCache:set(startPos, endPos, path)
  -- Check cache size
  if self:size() >= self.maxCacheSize then
    self:evictOldest()
  end
  
  local key = self:getKey(startPos, endPos)
  local currentTime = g_clock and g_clock.millis() or (now or 0)
  
  self.cache[key] = {
    path = path,
    timestamp = currentTime,
    lastAccess = currentTime
  }
end

-- Get cache size
function PathCache:size()
  local count = 0
  for _ in pairs(self.cache) do
    count = count + 1
  end
  return count
end

-- Evict oldest entry
function PathCache:evictOldest()
  local oldest = nil
  local oldestTime = math.huge
  
  for key, entry in pairs(self.cache) do
    if entry.lastAccess < oldestTime then
      oldestTime = entry.lastAccess
      oldest = key
    end
  end
  
  if oldest then
    self.cache[oldest] = nil
  end
end

-- Evict expired entries
function PathCache:evictExpired()
  local currentTime = g_clock and g_clock.millis() or (now or 0)
  local evicted = 0
  
  for key, entry in pairs(self.cache) do
    if (currentTime - entry.timestamp) >= self.ttl then
      self.cache[key] = nil
      evicted = evicted + 1
    end
  end
  
  return evicted
end

-- Clear all cache
function PathCache:clear()
  self.cache = {}
  self.hits = 0
  self.misses = 0
end

-- Get cache statistics
function PathCache:getStats()
  local totalRequests = self.hits + self.misses
  local hitRate = totalRequests > 0 and (self.hits / totalRequests * 100) or 0
  
  return {
    size = self:size(),
    maxSize = self.maxCacheSize,
    hits = self.hits,
    misses = self.misses,
    hitRate = hitRate,
    ttl = self.ttl
  }
end

-- Invalidate paths that pass through a position
function PathCache:invalidatePosition(pos)
  local invalidated = 0
  
  for key, entry in pairs(self.cache) do
    if entry.path then
      for _, pathPos in ipairs(entry.path) do
        if pathPos.x == pos.x and pathPos.y == pos.y and pathPos.z == pos.z then
          self.cache[key] = nil
          invalidated = invalidated + 1
          break
        end
      end
    end
  end
  
  return invalidated
end

-- Invalidate all paths on a floor
function PathCache:invalidateFloor(z)
  local invalidated = 0
  
  for key, entry in pairs(self.cache) do
    -- Check start/end position z-level from key
    local parts = {}
    for part in string.gmatch(key, "([^_]+)") do
      table.insert(parts, tonumber(part))
    end
    
    if #parts >= 6 and (parts[3] == z or parts[6] == z) then
      self.cache[key] = nil
      invalidated = invalidated + 1
    end
  end
  
  return invalidated
end

return PathCache
