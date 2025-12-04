--[[
  nExBot Object Pool
  Memory optimization through object reuse
  Reduces garbage collection pressure
  
  Author: nExBot Team
  Version: 1.0.0
]]

local ObjectPool = {}

-- Create a new object pool
-- @param factory function - Function that creates new objects
-- @param initialSize number - Initial pool size
-- @param reset function - Optional function to reset object state
-- @return ObjectPool instance
function ObjectPool:new(factory, initialSize, reset)
  local instance = {
    factory = factory,
    resetFunc = reset,
    available = {},
    inUse = {},
    totalCreated = 0,
    maxSize = 500,  -- Prevent unbounded growth
    hits = 0,
    misses = 0
  }
  
  setmetatable(instance, { __index = self })
  
  -- Pre-populate pool
  if initialSize and initialSize > 0 then
    for i = 1, initialSize do
      local obj = factory()
      table.insert(instance.available, obj)
      instance.totalCreated = instance.totalCreated + 1
    end
  end
  
  return instance
end

-- Acquire an object from the pool
function ObjectPool:acquire()
  local obj
  
  if #self.available > 0 then
    obj = table.remove(self.available)
    self.hits = self.hits + 1
  else
    if self.totalCreated < self.maxSize then
      obj = self.factory()
      self.totalCreated = self.totalCreated + 1
      self.misses = self.misses + 1
    else
      -- Pool exhausted, force recycle oldest in-use object
      warn("[ObjectPool] Pool exhausted, forcing recycle")
      if #self.inUse > 0 then
        obj = table.remove(self.inUse, 1)
        if self.resetFunc then
          self.resetFunc(obj)
        end
      else
        -- Last resort: create new object
        obj = self.factory()
      end
    end
  end
  
  table.insert(self.inUse, obj)
  return obj
end

-- Release an object back to the pool
function ObjectPool:release(obj)
  if not obj then return false end
  
  -- Find and remove from in-use list
  for i, inUseObj in ipairs(self.inUse) do
    if inUseObj == obj then
      table.remove(self.inUse, i)
      
      -- Reset object if reset function provided
      if self.resetFunc then
        self.resetFunc(obj)
      end
      
      table.insert(self.available, obj)
      return true
    end
  end
  
  return false
end

-- Release all objects back to pool
function ObjectPool:releaseAll()
  for _, obj in ipairs(self.inUse) do
    if self.resetFunc then
      self.resetFunc(obj)
    end
    table.insert(self.available, obj)
  end
  self.inUse = {}
end

-- Get pool statistics
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

-- Set maximum pool size
function ObjectPool:setMaxSize(size)
  self.maxSize = size
end

-- Clear the entire pool
function ObjectPool:clear()
  self.available = {}
  self.inUse = {}
  self.totalCreated = 0
  self.hits = 0
  self.misses = 0
end

-- Pre-warm the pool with additional objects
function ObjectPool:prewarm(count)
  local created = 0
  while created < count and self.totalCreated < self.maxSize do
    local obj = self.factory()
    table.insert(self.available, obj)
    self.totalCreated = self.totalCreated + 1
    created = created + 1
  end
  return created
end

-- Shrink pool to target size
function ObjectPool:shrink(targetSize)
  targetSize = targetSize or 10
  local removed = 0
  
  while #self.available > targetSize do
    table.remove(self.available)
    self.totalCreated = self.totalCreated - 1
    removed = removed + 1
  end
  
  return removed
end

return ObjectPool
