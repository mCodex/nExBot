--[[
  ============================================================================
  nExBot Object Pool
  ============================================================================
  
  Memory optimization through object reuse pattern.
  Reduces garbage collection pressure by recycling objects instead of
  creating new ones and letting them be collected.
  
  HOW IT WORKS:
  1. Pool pre-creates objects using a factory function
  2. acquire() returns a recycled object or creates new if pool is empty
  3. release() returns the object to the pool for reuse
  4. Optional reset function clears object state between uses
  
  USE CASES:
  - Pathfinding nodes (created/destroyed frequently)
  - Temporary position objects
  - Spell effect data structures
  - Any frequently allocated/deallocated objects
  
  PERFORMANCE BENEFITS:
  - Reduces GC pause times
  - Avoids allocation overhead
  - Better cache locality (reused objects)
  
  USAGE:
    -- Create pool with factory function
    local nodePool = ObjectPool:new(
      function() return {x = 0, y = 0, z = 0, g = 0, h = 0, parent = nil} end,
      100,  -- Pre-create 100 nodes
      function(node)  -- Reset function
        node.x, node.y, node.z = 0, 0, 0
        node.g, node.h = 0, 0
        node.parent = nil
      end
    )
    
    -- Use in pathfinding
    local node = nodePool:acquire()
    node.x, node.y, node.z = 100, 200, 7
    -- ... use node ...
    nodePool:release(node)  -- Returns to pool
  
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
local table_remove = table.remove
local ipairs = ipairs
local setmetatable = setmetatable

--[[
  ============================================================================
  OBJECT POOL CLASS
  ============================================================================
]]

local ObjectPool = {}

--- Creates a new object pool
-- 
-- @param factory (function) Function that creates new objects
-- @param initialSize (number|nil) Number of objects to pre-create
-- @param reset (function|nil) Function to reset object state before reuse
-- @return (ObjectPool) New pool instance
-- 
-- Example:
--   local pool = ObjectPool:new(
--     function() return {} end,  -- Factory
--     50,                         -- Pre-create 50
--     function(t) for k in pairs(t) do t[k] = nil end end  -- Clear table
--   )
function ObjectPool:new(factory, initialSize, reset)
  local instance = {
    -- ========================================
    -- CONFIGURATION
    -- ========================================
    factory = factory,      -- Function to create new objects
    resetFunc = reset,      -- Function to reset object state
    maxSize = 500,          -- Maximum pool size (prevents unbounded growth)
    
    -- ========================================
    -- OBJECT STORAGE
    -- available: Objects ready for reuse (stack behavior)
    -- inUse: Objects currently in use (for forced recycle)
    -- ========================================
    available = {},
    inUse = {},
    
    -- ========================================
    -- STATISTICS
    -- ========================================
    totalCreated = 0,       -- Total objects ever created
    hits = 0,               -- Successful reuses from pool
    misses = 0              -- Times a new object had to be created
  }
  
  setmetatable(instance, { __index = self })
  
  -- ========================================
  -- PRE-POPULATE POOL
  -- Creates initial objects to avoid cold-start misses
  -- ========================================
  if initialSize and initialSize > 0 then
    for i = 1, initialSize do
      local obj = factory()
      table_insert(instance.available, obj)
      instance.totalCreated = instance.totalCreated + 1
    end
  end
  
  return instance
end

--[[
  ============================================================================
  ACQUIRE & RELEASE
  ============================================================================
]]

--- Acquires an object from the pool
-- Returns a recycled object if available, otherwise creates a new one
-- 
-- @return (any) Object from pool (either recycled or newly created)
-- 
-- Performance Note:
--   Recycled objects are O(1) via table.remove from end
--   New object creation depends on factory function complexity
function ObjectPool:acquire()
  local obj
  
  -- ========================================
  -- TRY TO RECYCLE FROM POOL
  -- Remove from end of available array (stack pop - O(1))
  -- ========================================
  if #self.available > 0 then
    obj = table_remove(self.available)
    self.hits = self.hits + 1
  else
    -- ========================================
    -- CREATE NEW OBJECT IF UNDER LIMIT
    -- ========================================
    if self.totalCreated < self.maxSize then
      obj = self.factory()
      self.totalCreated = self.totalCreated + 1
      self.misses = self.misses + 1
    else
      -- ========================================
      -- POOL EXHAUSTED - FORCE RECYCLE
      -- Recycle the oldest in-use object (FIFO)
      -- This is a last resort and indicates pool is too small
      -- ========================================
      if warn then
        warn("[ObjectPool] Pool exhausted (" .. self.maxSize .. 
             "), forcing recycle - consider increasing maxSize")
      end
      
      if #self.inUse > 0 then
        obj = table_remove(self.inUse, 1)  -- Remove oldest (FIFO)
        if self.resetFunc then
          self.resetFunc(obj)
        end
      else
        -- Absolute last resort: exceed limit
        obj = self.factory()
        self.totalCreated = self.totalCreated + 1
      end
    end
  end
  
  -- Track as in-use for forced recycle scenario
  table_insert(self.inUse, obj)
  return obj
end

--- Releases an object back to the pool for reuse
-- Resets the object state if a reset function was provided
-- 
-- @param obj (any) Object previously acquired from this pool
-- @return (boolean) True if successfully released
-- 
-- Warning:
--   Only release objects that were acquired from this pool!
--   Releasing foreign objects will cause undefined behavior
function ObjectPool:release(obj)
  if not obj then return false end
  
  -- ========================================
  -- FIND AND REMOVE FROM IN-USE LIST
  -- Iterate backwards for safe removal
  -- ========================================
  for i = #self.inUse, 1, -1 do
    if self.inUse[i] == obj then
      table_remove(self.inUse, i)
      
      -- Reset object state for clean reuse
      if self.resetFunc then
        self.resetFunc(obj)
      end
      
      -- Return to available pool
      table_insert(self.available, obj)
      return true
    end
  end
  
  -- Object not found in in-use list
  return false
end

--- Releases all in-use objects back to the pool
-- Useful when resetting state or at end of a logical operation
function ObjectPool:releaseAll()
  for _, obj in ipairs(self.inUse) do
    if self.resetFunc then
      self.resetFunc(obj)
    end
    table_insert(self.available, obj)
  end
  self.inUse = {}
end

--[[
  ============================================================================
  POOL MANAGEMENT
  ============================================================================
]]

--- Sets the maximum pool size
-- @param size (number) New maximum size
function ObjectPool:setMaxSize(size)
  self.maxSize = size
end

--- Pre-warms the pool by creating additional objects
-- Call during initialization or low-activity periods
-- 
-- @param count (number) Number of objects to create
-- @return (number) Actual number created (may be less if maxSize reached)
function ObjectPool:prewarm(count)
  local created = 0
  
  while created < count and self.totalCreated < self.maxSize do
    local obj = self.factory()
    table_insert(self.available, obj)
    self.totalCreated = self.totalCreated + 1
    created = created + 1
  end
  
  return created
end

--- Shrinks the pool to a target size
-- Removes excess available objects to free memory
-- 
-- @param targetSize (number|nil) Target available count (default: 10)
-- @return (number) Number of objects removed
function ObjectPool:shrink(targetSize)
  targetSize = targetSize or 10
  local removed = 0
  
  while #self.available > targetSize do
    table_remove(self.available)
    self.totalCreated = self.totalCreated - 1
    removed = removed + 1
  end
  
  return removed
end

--- Clears the entire pool
-- Use when pool is no longer needed or for complete reset
function ObjectPool:clear()
  self.available = {}
  self.inUse = {}
  self.totalCreated = 0
  self.hits = 0
  self.misses = 0
end

--[[
  ============================================================================
  STATISTICS & DIAGNOSTICS
  ============================================================================
]]

--- Gets pool statistics for monitoring
-- 
-- @return (table) Statistics object:
--   - available: Objects ready for reuse
--   - inUse: Objects currently acquired
--   - total: Total objects in pool
--   - totalCreated: Lifetime objects created
--   - maxSize: Pool size limit
--   - hits: Successful reuses
--   - misses: New creations required
--   - hitRate: Percentage of acquisitions that were reuses
function ObjectPool:getStats()
  local total = self.hits + self.misses
  local hitRate = total > 0 and (self.hits / total * 100) or 0
  
  return {
    available = #self.available,
    inUse = #self.inUse,
    total = #self.available + #self.inUse,
    totalCreated = self.totalCreated,
    maxSize = self.maxSize,
    hits = self.hits,
    misses = self.misses,
    hitRate = hitRate
  }
end

--- Gets a formatted summary string
-- @return (string) Human-readable pool status
function ObjectPool:getSummary()
  local stats = self:getStats()
  return string.format(
    "Pool: %d available, %d in-use (hit rate: %.1f%%)",
    stats.available, stats.inUse, stats.hitRate
  )
end

--[[
  ============================================================================
  MODULE EXPORT
  ============================================================================
]]

return ObjectPool
