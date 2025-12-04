--[[
  ============================================================================
  nExBot Weak Reference Tracker
  ============================================================================
  
  Memory-efficient tracking of objects using Lua's weak reference tables.
  Objects are automatically removed when garbage collected elsewhere.
  
  HOW WEAK REFERENCES WORK:
  When a table has a metatable with __mode = "v" (weak values), the values
  in that table don't count as references for garbage collection purposes.
  If the only reference to an object is in a weak table, the GC will
  collect it and remove the entry from the table.
  
  USE CASES:
  - Tracking creatures without preventing their cleanup
  - Caching computed data about entities
  - Monitoring objects that may be destroyed by the game
  - Event listeners that should auto-cleanup
  
  DESIGN PATTERN:
  - Weak references for tracked objects (auto-cleanup)
  - Strong references for metadata (explicit cleanup via cleanup())
  
  USAGE:
    local tracker = WeakReferenceTracker:new()
    
    -- Track a creature
    tracker:track(creature:getId(), creature, {
      dangerLevel = 5,
      lastSeen = now
    })
    
    -- Later, check if still exists
    if tracker:exists(creatureId) then
      local creature = tracker:get(creatureId)
      local meta = tracker:getMetadata(creatureId)
    end
    
    -- Cleanup orphaned metadata periodically
    tracker:update()  -- Call each tick
  
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
local pairs = pairs
local setmetatable = setmetatable

--[[
  ============================================================================
  HELPER FUNCTION
  ============================================================================
]]

--- Gets current time in milliseconds
-- Prefers g_clock.millis() for precision, falls back to now global
-- @return (number) Current time in milliseconds
local function getCurrentTime()
  if g_clock and g_clock.millis then
    return g_clock.millis()
  end
  return now or 0
end

--[[
  ============================================================================
  WEAK REFERENCE TRACKER CLASS
  ============================================================================
]]

local WeakReferenceTracker = {}

--- Creates a new weak reference tracker
-- @return (WeakReferenceTracker) New tracker instance
function WeakReferenceTracker:new()
  local instance = {
    -- ========================================
    -- WEAK REFERENCE TABLE
    -- Objects here don't count as references for GC
    -- When an object is collected, its entry is automatically removed
    -- ========================================
    references = setmetatable({}, {__mode = "v"}),
    
    -- ========================================
    -- METADATA TABLE (STRONG REFERENCES)
    -- Metadata persists until explicitly cleaned up
    -- This allows storing computed data about objects
    -- ========================================
    metadata = {},
    
    -- ========================================
    -- CLEANUP CONFIGURATION
    -- ========================================
    cleanupInterval = 30000,  -- 30 seconds between cleanups
    lastCleanup = 0           -- Timestamp of last cleanup
  }
  
  setmetatable(instance, { __index = self })
  return instance
end

--[[
  ============================================================================
  TRACKING OPERATIONS
  ============================================================================
]]

--- Tracks an object with optional metadata
-- The object is held weakly, metadata is held strongly
-- 
-- @param id (any) Unique identifier for lookup (usually creature ID)
-- @param object (any) Object to track (held weakly)
-- @param metadata (table|nil) Optional data about the object (held strongly)
-- 
-- Example:
--   tracker:track(creature:getId(), creature, {
--     firstSeen = now,
--     threatLevel = calculateThreat(creature)
--   })
function WeakReferenceTracker:track(id, object, metadata)
  -- Store weak reference to object
  self.references[id] = object
  
  -- Store metadata (or default)
  if metadata then
    self.metadata[id] = metadata
  else
    self.metadata[id] = {
      trackedAt = getCurrentTime()
    }
  end
end

--- Gets a tracked object by ID
-- Returns nil if object was garbage collected
-- 
-- @param id (any) ID used when tracking
-- @return (any|nil) The tracked object or nil
function WeakReferenceTracker:get(id)
  return self.references[id]
end

--- Gets metadata for a tracked object
-- Metadata persists even after object is collected (until cleanup)
-- 
-- @param id (any) ID used when tracking
-- @return (table|nil) Metadata or nil
function WeakReferenceTracker:getMetadata(id)
  return self.metadata[id]
end

--- Checks if an object is still tracked and not collected
-- 
-- @param id (any) ID to check
-- @return (boolean) True if object still exists
function WeakReferenceTracker:exists(id)
  return self.references[id] ~= nil
end

--- Removes tracking for an object
-- Clears both the weak reference and metadata
-- 
-- @param id (any) ID to remove
function WeakReferenceTracker:remove(id)
  self.references[id] = nil
  self.metadata[id] = nil
end

--[[
  ============================================================================
  QUERY OPERATIONS
  ============================================================================
]]

--- Gets all tracked IDs
-- Only returns IDs where the object still exists
-- 
-- @return (table) Array of IDs
function WeakReferenceTracker:getIds()
  local ids = {}
  for id, _ in pairs(self.references) do
    table_insert(ids, id)
  end
  return ids
end

--- Gets count of currently tracked objects
-- O(n) operation - caches result if called frequently
-- 
-- @return (number) Number of tracked objects
function WeakReferenceTracker:count()
  local count = 0
  for _ in pairs(self.references) do
    count = count + 1
  end
  return count
end

--- Iterates over all tracked objects
-- Callback is called for each object that still exists
-- 
-- @param callback (function) Function(id, object, metadata)
-- 
-- Example:
--   tracker:forEach(function(id, creature, meta)
--     print(creature:getName(), meta.threatLevel)
--   end)
function WeakReferenceTracker:forEach(callback)
  for id, object in pairs(self.references) do
    if object then
      callback(id, object, self.metadata[id])
    end
  end
end

--- Finds objects matching a predicate function
-- 
-- @param predicate (function) Function(id, object, metadata) -> boolean
-- @return (table) Array of {id, object, metadata}
-- 
-- Example:
--   local dangerous = tracker:find(function(id, creature, meta)
--     return meta.threatLevel > 5
--   end)
function WeakReferenceTracker:find(predicate)
  local results = {}
  
  for id, object in pairs(self.references) do
    if object then
      local meta = self.metadata[id]
      if predicate(id, object, meta) then
        table_insert(results, {
          id = id,
          object = object,
          metadata = meta
        })
      end
    end
  end
  
  return results
end

--[[
  ============================================================================
  CLEANUP OPERATIONS
  ============================================================================
]]

--- Cleans up orphaned metadata
-- Removes metadata entries where the object has been garbage collected
-- Should be called periodically or via update()
-- 
-- @return (number) Number of orphaned entries cleaned
function WeakReferenceTracker:cleanup()
  local currentTime = getCurrentTime()
  local cleaned = 0
  
  -- ========================================
  -- FIND ORPHANED METADATA
  -- Metadata exists but object was collected
  -- ========================================
  for id, _ in pairs(self.metadata) do
    if self.references[id] == nil then
      self.metadata[id] = nil
      cleaned = cleaned + 1
    end
  end
  
  self.lastCleanup = currentTime
  return cleaned
end

--- Performs periodic cleanup check
-- Call this every tick - it only runs cleanup() at the configured interval
-- 
-- @return (number) Number cleaned (0 if interval not reached)
function WeakReferenceTracker:update()
  local currentTime = getCurrentTime()
  
  if (currentTime - self.lastCleanup) >= self.cleanupInterval then
    return self:cleanup()
  end
  
  return 0
end

--- Sets the cleanup interval
-- @param intervalMs (number) Interval in milliseconds
function WeakReferenceTracker:setCleanupInterval(intervalMs)
  self.cleanupInterval = intervalMs
end

--- Clears all tracking data
function WeakReferenceTracker:clear()
  self.references = setmetatable({}, {__mode = "v"})
  self.metadata = {}
  self.lastCleanup = getCurrentTime()
end

--[[
  ============================================================================
  STATISTICS
  ============================================================================
]]

--- Gets statistics about the tracker
-- Useful for debugging and monitoring
-- 
-- @return (table) Statistics object:
--   - trackedObjects: Objects still alive
--   - metadataEntries: Metadata records
--   - orphanedMetadata: Metadata without objects (needs cleanup)
--   - lastCleanup: Timestamp of last cleanup
function WeakReferenceTracker:getStats()
  local refCount = self:count()
  local metaCount = 0
  
  for _ in pairs(self.metadata) do
    metaCount = metaCount + 1
  end
  
  return {
    trackedObjects = refCount,
    metadataEntries = metaCount,
    orphanedMetadata = metaCount - refCount,
    lastCleanup = self.lastCleanup
  }
end

--[[
  ============================================================================
  MODULE EXPORT
  ============================================================================
]]

return WeakReferenceTracker
