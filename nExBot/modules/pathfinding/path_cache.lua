--[[
  ============================================================================
  nExBot Path Cache
  ============================================================================
  
  Caches calculated paths to avoid redundant A* calculations.
  Uses TTL (Time-To-Live) based eviction for freshness.
  
  WHY CACHE PATHS?
  A* pathfinding is CPU-intensive (O(b^d) worst case where b=branching
  factor, d=depth). By caching recent paths, we can return instantly for
  repeated route requests.
  
  CACHE STRATEGY:
  - LRU-like eviction when cache is full (oldest access time)
  - TTL-based expiration (paths become stale as creatures move)
  - Position-based invalidation (when map changes)
  
  USAGE:
    local cache = PathCache:new({
      maxSize = 100,  -- Maximum cached paths
      ttl = 30000     -- 30 second TTL
    })
    
    -- Check cache before pathfinding
    local path = cache:get(start, goal)
    if not path then
      path = astar:findPath(start, goal)
      cache:set(start, goal, path)
    end
  
  Author: nExBot Team
  Version: 2.0.0 (Optimized)
  Last Updated: December 2025
  
  ============================================================================
]]

--[[
  ============================================================================
  LOCAL CACHING FOR PERFORMANCE
  ============================================================================
]]
local table_insert = table.insert
local string_format = string.format
local string_gmatch = string.gmatch
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local math_huge = math.huge
local setmetatable = setmetatable

--[[
  ============================================================================
  HELPER FUNCTION
  ============================================================================
]]

--- Gets current time in milliseconds
-- @return (number) Current timestamp
local function getCurrentTime()
  if g_clock and g_clock.millis then
    return g_clock.millis()
  end
  return now or 0
end

--[[
  ============================================================================
  PATH CACHE CLASS
  ============================================================================
]]

local PathCache = {
  cache = {},          -- Key -> {path, timestamp, lastAccess}
  maxCacheSize = 100,  -- Maximum entries
  ttl = 30000,         -- Time-to-live in ms
  hits = 0,            -- Cache hit count
  misses = 0           -- Cache miss count
}

--- Creates a new PathCache instance
-- 
-- @param options (table|nil) Configuration:
--   - maxSize: Maximum cached paths (default: 100)
--   - ttl: Time-to-live in ms (default: 30000)
-- @return (PathCache) New cache instance
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

--[[
  ============================================================================
  KEY GENERATION
  ============================================================================
]]

--- Generates a unique cache key from start and end positions
-- Key format: "startX_startY_startZ_endX_endY_endZ"
-- 
-- @param startPos (table) Starting position
-- @param endPos (table) Ending position
-- @return (string) Cache key
function PathCache:getKey(startPos, endPos)
  return string_format("%d_%d_%d_%d_%d_%d",
    startPos.x, startPos.y, startPos.z,
    endPos.x, endPos.y, endPos.z)
end

--[[
  ============================================================================
  CACHE OPERATIONS
  ============================================================================
]]

--- Gets a cached path if available and not expired
-- Updates lastAccess time for LRU tracking
-- 
-- @param startPos (table) Starting position
-- @param endPos (table) Ending position
-- @return (table|nil) Cached path or nil if not found/expired
function PathCache:get(startPos, endPos)
  local key = self:getKey(startPos, endPos)
  local cached = self.cache[key]
  
  if cached then
    local currentTime = getCurrentTime()
    
    -- Check if not expired
    if (currentTime - cached.timestamp) < self.ttl then
      self.hits = self.hits + 1
      cached.lastAccess = currentTime  -- Update for LRU
      return cached.path
    else
      -- Expired - remove stale entry
      self.cache[key] = nil
    end
  end
  
  self.misses = self.misses + 1
  return nil
end

--- Stores a path in the cache
-- Evicts oldest entry if cache is full
-- 
-- @param startPos (table) Starting position
-- @param endPos (table) Ending position
-- @param path (table) Path to cache (array of positions)
function PathCache:set(startPos, endPos, path)
  -- Evict if at capacity
  if self:size() >= self.maxCacheSize then
    self:evictOldest()
  end
  
  local key = self:getKey(startPos, endPos)
  local currentTime = getCurrentTime()
  
  self.cache[key] = {
    path = path,
    timestamp = currentTime,  -- Creation time (for TTL)
    lastAccess = currentTime  -- Last access time (for LRU)
  }
end

--[[
  ============================================================================
  CACHE SIZE & EVICTION
  ============================================================================
]]

--- Gets current cache size
-- @return (number) Number of cached paths
function PathCache:size()
  local count = 0
  for _ in pairs(self.cache) do
    count = count + 1
  end
  return count
end

--- Evicts the least recently accessed entry
-- Called automatically when cache reaches maxSize
function PathCache:evictOldest()
  local oldest = nil
  local oldestTime = math_huge
  
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

--- Evicts all expired entries
-- Can be called periodically for cleanup
-- 
-- @return (number) Number of entries evicted
function PathCache:evictExpired()
  local currentTime = getCurrentTime()
  local evicted = 0
  
  for key, entry in pairs(self.cache) do
    if (currentTime - entry.timestamp) >= self.ttl then
      self.cache[key] = nil
      evicted = evicted + 1
    end
  end
  
  return evicted
end

--[[
  ============================================================================
  CACHE INVALIDATION
  ============================================================================
  
  Called when the game world changes and cached paths may no longer be valid.
  ============================================================================
]]

--- Invalidates all cached paths that pass through a specific position
-- Call when a tile becomes blocked/unblocked (creature, door, etc.)
-- 
-- @param pos (table) Position that changed
-- @return (number) Number of paths invalidated
function PathCache:invalidatePosition(pos)
  local invalidated = 0
  local posX, posY, posZ = pos.x, pos.y, pos.z
  
  for key, entry in pairs(self.cache) do
    if entry.path then
      -- Check if any step in the path matches the position
      for i = 1, #entry.path do
        local pathPos = entry.path[i]
        if pathPos.x == posX and pathPos.y == posY and pathPos.z == posZ then
          self.cache[key] = nil
          invalidated = invalidated + 1
          break  -- Don't need to check rest of path
        end
      end
    end
  end
  
  return invalidated
end

--- Invalidates all cached paths on a specific floor
-- Useful when major map changes occur (spawn events, etc.)
-- 
-- @param z (number) Floor level
-- @return (number) Number of paths invalidated
function PathCache:invalidateFloor(z)
  local invalidated = 0
  
  for key, entry in pairs(self.cache) do
    -- Parse z-levels from key format "x1_y1_z1_x2_y2_z2"
    local parts = {}
    for part in string_gmatch(key, "([^_]+)") do
      parts[#parts + 1] = tonumber(part)
    end
    
    -- parts[3] = start z, parts[6] = end z
    if #parts >= 6 and (parts[3] == z or parts[6] == z) then
      self.cache[key] = nil
      invalidated = invalidated + 1
    end
  end
  
  return invalidated
end

--- Clears all cached paths and resets statistics
function PathCache:clear()
  self.cache = {}
  self.hits = 0
  self.misses = 0
end

--[[
  ============================================================================
  STATISTICS
  ============================================================================
]]

--- Gets cache performance statistics
-- 
-- @return (table) Statistics object:
--   - size: Current cached paths
--   - maxSize: Maximum capacity
--   - hits: Cache hit count
--   - misses: Cache miss count
--   - hitRate: Percentage of hits (0-100)
--   - ttl: Time-to-live in ms
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

--- Gets a formatted summary string
-- @return (string) Human-readable cache status
function PathCache:getSummary()
  local stats = self:getStats()
  return string_format(
    "PathCache: %d/%d entries (%.1f%% hit rate)",
    stats.size, stats.maxSize, stats.hitRate
  )
end

--[[
  ============================================================================
  MODULE EXPORT
  ============================================================================
]]

return PathCache
