--[[
  nExBot Weak Reference Tracker
  Memory-efficient creature and object tracking
  Uses weak references for automatic cleanup
  
  Author: nExBot Team
  Version: 1.0.0
]]

local WeakReferenceTracker = {}

-- Create new weak reference tracker
function WeakReferenceTracker:new()
  local instance = {
    -- Use weak values so GC can collect unreferenced objects
    references = setmetatable({}, {__mode = "v"}),
    metadata = {},  -- Strong references to metadata
    cleanupInterval = 30000,  -- 30 seconds
    lastCleanup = 0
  }
  
  setmetatable(instance, { __index = self })
  return instance
end

-- Get current time
local function getCurrentTime()
  return g_clock and g_clock.millis() or (now or 0)
end

-- Track an object with optional metadata
-- @param id - Unique identifier
-- @param object - Object to track (weak reference)
-- @param metadata - Optional metadata (strong reference)
function WeakReferenceTracker:track(id, object, metadata)
  self.references[id] = object
  
  if metadata then
    self.metadata[id] = metadata
  else
    self.metadata[id] = {
      trackedAt = getCurrentTime()
    }
  end
end

-- Get tracked object
function WeakReferenceTracker:get(id)
  return self.references[id]
end

-- Get metadata for tracked object
function WeakReferenceTracker:getMetadata(id)
  return self.metadata[id]
end

-- Check if object is still tracked (not GC'd)
function WeakReferenceTracker:exists(id)
  return self.references[id] ~= nil
end

-- Remove tracking for an object
function WeakReferenceTracker:remove(id)
  self.references[id] = nil
  self.metadata[id] = nil
end

-- Get all tracked IDs
function WeakReferenceTracker:getIds()
  local ids = {}
  for id, _ in pairs(self.references) do
    table.insert(ids, id)
  end
  return ids
end

-- Get count of tracked objects
function WeakReferenceTracker:count()
  local count = 0
  for _ in pairs(self.references) do
    count = count + 1
  end
  return count
end

-- Cleanup orphaned metadata (where object was GC'd)
function WeakReferenceTracker:cleanup()
  local currentTime = getCurrentTime()
  local cleaned = 0
  
  -- Find metadata without corresponding objects
  for id, _ in pairs(self.metadata) do
    if self.references[id] == nil then
      self.metadata[id] = nil
      cleaned = cleaned + 1
    end
  end
  
  self.lastCleanup = currentTime
  return cleaned
end

-- Periodic cleanup check
function WeakReferenceTracker:update()
  local currentTime = getCurrentTime()
  
  if (currentTime - self.lastCleanup) >= self.cleanupInterval then
    return self:cleanup()
  end
  
  return 0
end

-- Get statistics
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

-- Clear all tracking
function WeakReferenceTracker:clear()
  self.references = setmetatable({}, {__mode = "v"})
  self.metadata = {}
  self.lastCleanup = getCurrentTime()
end

-- Iterate over all tracked objects
-- @param callback function(id, object, metadata)
function WeakReferenceTracker:forEach(callback)
  for id, object in pairs(self.references) do
    if object then
      callback(id, object, self.metadata[id])
    end
  end
end

-- Find objects matching a predicate
-- @param predicate function(id, object, metadata) returns boolean
function WeakReferenceTracker:find(predicate)
  local results = {}
  
  for id, object in pairs(self.references) do
    if object and predicate(id, object, self.metadata[id]) then
      table.insert(results, {
        id = id,
        object = object,
        metadata = self.metadata[id]
      })
    end
  end
  
  return results
end

return WeakReferenceTracker
