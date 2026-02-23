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

-- ============================================================================
-- LRU CACHE (Least Recently Used)
-- ============================================================================

-- Create an LRU cache with automatic eviction
-- Uses a doubly-linked list for true O(1) touch/evict/remove.
-- @param maxSize: maximum number of entries (default 100)
-- @param ttl: optional time-to-live in milliseconds
-- @return LRU cache object
function WeakCache.createLRU(maxSize, ttl)
  maxSize = maxSize or 100
  
  local cache = {
    data = {},
    nodeMap = {},  -- key -> DLL node
    head = nil,    -- oldest (eviction candidate)
    tail = nil,    -- newest
    size = 0,
    maxSize = maxSize,
    ttl = ttl,
    hits = 0,
    misses = 0
  }
  
  local nowMs = nExBot.Shared.nowMs
  
  -- Unlink a node from the doubly-linked list
  local function unlink(node)
    local p, n = node.prev, node.next
    if p then p.next = n else cache.head = n end
    if n then n.prev = p else cache.tail = p end
    node.prev = nil
    node.next = nil
  end
  
  -- Append a node to the tail (most recently used)
  local function appendToTail(node)
    node.prev = cache.tail
    node.next = nil
    if cache.tail then cache.tail.next = node end
    cache.tail = node
    if not cache.head then cache.head = node end
  end
  
  -- Move key to most-recently-used position — O(1)
  local function touch(key)
    local node = cache.nodeMap[key]
    if not node then
      node = { key = key }
      cache.nodeMap[key] = node
      cache.size = cache.size + 1
    else
      unlink(node)
    end
    appendToTail(node)
  end
  
  -- Evict the least-recently-used entry (head) — O(1)
  local function evict()
    local node = cache.head
    if not node then return end
    unlink(node)
    cache.nodeMap[node.key] = nil
    cache.data[node.key] = nil
    cache.size = cache.size - 1
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
      self:remove(key)
      self.misses = self.misses + 1
      return nil
    end
    
    touch(key)
    self.hits = self.hits + 1
    return entry.value
  end
  
  -- Set value in cache
  function cache:set(key, value)
    -- Evict if at capacity and this is a new key
    if not self.data[key] then
      while self.size >= self.maxSize do
        evict()
      end
    end
    
    self.data[key] = {
      value = value,
      ts = nowMs()
    }
    touch(key)
  end
  
  -- Remove entry — O(1)
  function cache:remove(key)
    self.data[key] = nil
    local node = self.nodeMap[key]
    if node then
      unlink(node)
      self.nodeMap[key] = nil
      self.size = self.size - 1
    end
  end
  
  -- Clear all entries
  function cache:clear()
    self.data = {}
    self.nodeMap = {}
    self.head = nil
    self.tail = nil
    self.size = 0
  end
  
  -- Get stats
  function cache:getStats()
    local total = self.hits + self.misses
    return {
      hits = self.hits,
      misses = self.misses,
      size = self.size,
      maxSize = self.maxSize,
      hitRate = total > 0 and (self.hits / total) or 0
    }
  end
  
  return cache
end

-- ============================================================================
-- EXPORT
-- ============================================================================

-- Export to global (no _G in OTClient sandbox)
-- WeakCache is already global (declared without 'local')

return WeakCache
