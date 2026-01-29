--[[
  Weak Reference Cache v1.0
  
  Provides weak-table based caching utilities for memory-efficient storage.
  Objects stored in weak caches can be garbage collected when no longer 
  referenced elsewhere, preventing memory leaks.
  
  USAGE:
    local WeakCache = require("utils.weak_cache")
    
    -- Create a cache with weak keys (creature -> data)
    local creatureData = WeakCache.createWeakKeys()
    creatureData[creature] = { lastSeen = now }
    
    -- Create a cache with weak values
    local pathCache = WeakCache.createWeakValues()
    pathCache["path_key"] = calculatedPath
    
    -- Create an LRU cache with automatic eviction
    local lruCache = WeakCache.createLRU(100)  -- max 100 entries
    lruCache:set("key", value)
    local v = lruCache:get("key")
]]

local WeakCache = {}
WeakCache.VERSION = "1.0"

-- ============================================================================
-- WEAK TABLE FACTORIES
-- ============================================================================

-- Create a table with weak keys
-- When the key object is garbage collected, the entry is automatically removed
-- Perfect for: creature -> data mappings, object -> metadata
-- @return table with weak keys metatable
function WeakCache.createWeakKeys()
  local t = {}
  setmetatable(t, { __mode = "k" })
  return t
end

-- Create a table with weak values
-- When the value object is garbage collected, the entry is automatically removed
-- Perfect for: caches where values can be regenerated
-- @return table with weak values metatable
function WeakCache.createWeakValues()
  local t = {}
  setmetatable(t, { __mode = "v" })
  return t
end

-- Create a table with both weak keys and values
-- Entry is removed when either key OR value is garbage collected
-- Perfect for: temporary associations, cross-references
-- @return table with weak keys+values metatable
function WeakCache.createWeakBoth()
  local t = {}
  setmetatable(t, { __mode = "kv" })
  return t
end

-- ============================================================================
-- LRU CACHE (Least Recently Used)
-- ============================================================================

-- Create an LRU cache with automatic eviction
-- @param maxSize: maximum number of entries (default 100)
-- @param ttl: optional time-to-live in milliseconds
-- @return LRU cache object
function WeakCache.createLRU(maxSize, ttl)
  maxSize = maxSize or 100
  
  local cache = {
    data = {},
    order = {},  -- Ordered list of keys (most recent last)
    maxSize = maxSize,
    ttl = ttl,
    hits = 0,
    misses = 0
  }
  
  local function nowMs()
    if now then return now end
    if g_clock and g_clock.millis then return g_clock.millis() end
    return os.time() * 1000
  end
  
  -- Remove oldest entry
  local function evict()
    if #cache.order > 0 then
      local oldestKey = table.remove(cache.order, 1)
      cache.data[oldestKey] = nil
    end
  end
  
  -- Move key to end (most recent)
  local function touch(key)
    for i = 1, #cache.order do
      if cache.order[i] == key then
        table.remove(cache.order, i)
        break
      end
    end
    cache.order[#cache.order + 1] = key
  end
  
  -- Get value from cache
  function cache:get(key)
    local entry = self.data[key]
    if not entry then
      self.misses = self.misses + 1
      return nil
    end
    
    -- Check TTL
    if self.ttl and (nowMs() - entry.ts) > self.ttl then
      self.data[key] = nil
      self.misses = self.misses + 1
      return nil
    end
    
    touch(key)
    self.hits = self.hits + 1
    return entry.value
  end
  
  -- Set value in cache
  function cache:set(key, value)
    -- Evict if at capacity
    while #self.order >= self.maxSize do
      evict()
    end
    
    self.data[key] = {
      value = value,
      ts = nowMs()
    }
    touch(key)
  end
  
  -- Remove entry
  function cache:remove(key)
    self.data[key] = nil
    for i = 1, #self.order do
      if self.order[i] == key then
        table.remove(self.order, i)
        break
      end
    end
  end
  
  -- Clear all entries
  function cache:clear()
    self.data = {}
    self.order = {}
  end
  
  -- Get stats
  function cache:getStats()
    local total = self.hits + self.misses
    return {
      hits = self.hits,
      misses = self.misses,
      size = #self.order,
      maxSize = self.maxSize,
      hitRate = total > 0 and (self.hits / total) or 0
    }
  end
  
  return cache
end

-- ============================================================================
-- TTL CACHE (Time-To-Live)
-- ============================================================================

-- Create a simple TTL cache
-- Entries expire after specified milliseconds
-- @param defaultTTL: default time-to-live in milliseconds
-- @return TTL cache object
function WeakCache.createTTL(defaultTTL)
  defaultTTL = defaultTTL or 5000
  
  local cache = {
    data = {},
    defaultTTL = defaultTTL,
    hits = 0,
    misses = 0
  }
  
  local function nowMs()
    if now then return now end
    if g_clock and g_clock.millis then return g_clock.millis() end
    return os.time() * 1000
  end
  
  -- Get value from cache
  function cache:get(key)
    local entry = self.data[key]
    if not entry then
      self.misses = self.misses + 1
      return nil
    end
    
    if (nowMs() - entry.ts) > entry.ttl then
      self.data[key] = nil
      self.misses = self.misses + 1
      return nil
    end
    
    self.hits = self.hits + 1
    return entry.value
  end
  
  -- Set value with optional custom TTL
  function cache:set(key, value, ttl)
    self.data[key] = {
      value = value,
      ts = nowMs(),
      ttl = ttl or self.defaultTTL
    }
  end
  
  -- Cleanup expired entries
  function cache:cleanup()
    local currentTime = nowMs()
    local toRemove = {}
    
    for key, entry in pairs(self.data) do
      if (currentTime - entry.ts) > entry.ttl then
        toRemove[#toRemove + 1] = key
      end
    end
    
    for i = 1, #toRemove do
      self.data[toRemove[i]] = nil
    end
    
    return #toRemove
  end
  
  -- Clear all entries
  function cache:clear()
    self.data = {}
  end
  
  -- Get stats
  function cache:getStats()
    local total = self.hits + self.misses
    local size = 0
    for _ in pairs(self.data) do size = size + 1 end
    
    return {
      hits = self.hits,
      misses = self.misses,
      size = size,
      hitRate = total > 0 and (self.hits / total) or 0
    }
  end
  
  return cache
end

-- ============================================================================
-- POOLED WEAK CACHE
-- Combines weak references with object pooling for table reuse
-- ============================================================================

-- Create a pooled weak cache
-- Automatically pools released objects for reuse
-- @param maxPoolSize: max objects to keep in pool (default 50)
-- @return Pooled weak cache object
function WeakCache.createPooled(maxPoolSize)
  maxPoolSize = maxPoolSize or 50
  
  local cache = {
    data = {},
    pool = {},
    maxPoolSize = maxPoolSize
  }
  
  -- Apply weak keys metatable
  setmetatable(cache.data, { __mode = "k" })
  
  -- Get or create a data table for a key
  function cache:getOrCreate(key)
    local entry = self.data[key]
    if entry then
      return entry
    end
    
    -- Try to reuse from pool
    if #self.pool > 0 then
      entry = table.remove(self.pool)
      -- Clear pooled table
      for k in pairs(entry) do
        entry[k] = nil
      end
    else
      entry = {}
    end
    
    self.data[key] = entry
    return entry
  end
  
  -- Release an entry back to pool
  function cache:release(key)
    local entry = self.data[key]
    if entry and #self.pool < self.maxPoolSize then
      self.pool[#self.pool + 1] = entry
    end
    self.data[key] = nil
  end
  
  -- Get entry (nil if not exists)
  function cache:get(key)
    return self.data[key]
  end
  
  -- Clear cache and pool
  function cache:clear()
    self.data = {}
    setmetatable(self.data, { __mode = "k" })
    self.pool = {}
  end
  
  return cache
end

-- ============================================================================
-- EXPORT
-- ============================================================================

-- Export to global (no _G in OTClient sandbox)
-- WeakCache is already global (declared without 'local')

return WeakCache
