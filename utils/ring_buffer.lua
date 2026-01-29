--[[
  RingBuffer - O(1) Fixed-Size Circular Buffer
  
  Replaces inefficient table.remove(arr, 1) pattern which is O(n).
  Used for history tracking in monster_ai, event_targeting, looting, etc.
  
  PERFORMANCE:
  - push: O(1) - overwrites oldest element
  - get: O(1) - direct index access
  - iterate: O(n) - ordered traversal from oldest to newest
  
  MEMORY:
  - Pre-allocated fixed size
  - Integrates with nExBot.acquireTable()/releaseTable() for pooling
  
  USAGE:
    local RingBuffer = dofile("utils/ring_buffer.lua")
    local buffer = RingBuffer.new(50)  -- 50 element capacity
    buffer:push({time = now, value = 100})
    for item in buffer:iterate() do
      print(item.time, item.value)
    end
]]

local RingBuffer = {}
RingBuffer.__index = RingBuffer

-- Stats for monitoring
local stats = {
  created = 0,
  pushes = 0,
  clears = 0
}

--[[
  Create a new ring buffer with fixed capacity
  @param maxSize (number) Maximum number of elements
  @param poolName (string, optional) Object pool name for internal tables
  @return RingBuffer instance
]]
function RingBuffer.new(maxSize, poolName)
  if not maxSize or maxSize < 1 then
    maxSize = 50  -- Default capacity
  end
  
  local self = setmetatable({}, RingBuffer)
  self.data = {}          -- Array storage
  self.maxSize = maxSize  -- Fixed capacity
  self.head = 1           -- Next write position (1-indexed)
  self.size = 0           -- Current element count
  self.poolName = poolName  -- Optional: for object pooling integration
  
  stats.created = stats.created + 1
  return self
end

--[[
  Push an item to the buffer (overwrites oldest if full)
  @param item Any value to store
]]
function RingBuffer:push(item)
  -- Optionally release old item to pool before overwriting
  if self.size == self.maxSize and self.poolName and nExBot and nExBot.releaseTable then
    local oldItem = self.data[self.head]
    if oldItem and type(oldItem) == "table" then
      nExBot.releaseTable(self.poolName, oldItem)
    end
  end
  
  -- Store at head position
  self.data[self.head] = item
  
  -- Advance head (wrap around)
  self.head = (self.head % self.maxSize) + 1
  
  -- Increment size up to max
  if self.size < self.maxSize then
    self.size = self.size + 1
  end
  
  stats.pushes = stats.pushes + 1
end

--[[
  Get item at index (0 = oldest, size-1 = newest)
  @param index (number) 0-based index from oldest
  @return item or nil if out of bounds
]]
function RingBuffer:get(index)
  if index < 0 or index >= self.size then
    return nil
  end
  
  -- Calculate actual position in data array
  local start = self.head - self.size
  if start < 1 then
    start = start + self.maxSize
  end
  local actualIndex = ((start + index - 1) % self.maxSize) + 1
  return self.data[actualIndex]
end

--[[
  Get the newest item (most recently pushed)
  @return item or nil if empty
]]
function RingBuffer:newest()
  if self.size == 0 then return nil end
  local newestIdx = self.head - 1
  if newestIdx < 1 then newestIdx = self.maxSize end
  return self.data[newestIdx]
end

--[[
  Get the oldest item (will be overwritten next if full)
  @return item or nil if empty
]]
function RingBuffer:oldest()
  if self.size == 0 then return nil end
  return self:get(0)
end

--[[
  Get current number of elements
  @return number
]]
function RingBuffer:count()
  return self.size
end

--[[
  Check if buffer is empty
  @return boolean
]]
function RingBuffer:isEmpty()
  return self.size == 0
end

--[[
  Check if buffer is at capacity
  @return boolean
]]
function RingBuffer:isFull()
  return self.size == self.maxSize
end

--[[
  Clear all elements (releases to pool if configured)
]]
function RingBuffer:clear()
  -- Release all items to pool if configured
  if self.poolName and nExBot and nExBot.releaseTable then
    for i = 1, self.maxSize do
      local item = self.data[i]
      if item and type(item) == "table" then
        nExBot.releaseTable(self.poolName, item)
      end
    end
  end
  
  self.data = {}
  self.head = 1
  self.size = 0
  stats.clears = stats.clears + 1
end

--[[
  Iterate from oldest to newest
  @return iterator function
]]
function RingBuffer:iterate()
  local index = 0
  local count = self.size
  return function()
    if index >= count then return nil end
    local item = self:get(index)
    index = index + 1
    return item
  end
end

--[[
  Iterate from newest to oldest
  @return iterator function
]]
function RingBuffer:iterateReverse()
  local index = self.size - 1
  return function()
    if index < 0 then return nil end
    local item = self:get(index)
    index = index - 1
    return item
  end
end

--[[
  Convert to array (oldest to newest)
  @return array table
]]
function RingBuffer:toArray()
  local arr = {}
  for item in self:iterate() do
    arr[#arr + 1] = item
  end
  return arr
end

--[[
  Apply function to all items (filter/map)
  @param fn function(item) -> newItem or nil to remove
  @return new RingBuffer with results
]]
function RingBuffer:map(fn)
  local result = RingBuffer.new(self.maxSize, self.poolName)
  for item in self:iterate() do
    local newItem = fn(item)
    if newItem ~= nil then
      result:push(newItem)
    end
  end
  return result
end

--[[
  Find first matching item (from oldest)
  @param predicate function(item) -> boolean
  @return item or nil
]]
function RingBuffer:find(predicate)
  for item in self:iterate() do
    if predicate(item) then
      return item
    end
  end
  return nil
end

--[[
  Find last matching item (from newest)
  @param predicate function(item) -> boolean
  @return item or nil
]]
function RingBuffer:findLast(predicate)
  for item in self:iterateReverse() do
    if predicate(item) then
      return item
    end
  end
  return nil
end

--[[
  Count items matching predicate
  @param predicate function(item) -> boolean
  @return number
]]
function RingBuffer:countWhere(predicate)
  local count = 0
  for item in self:iterate() do
    if predicate(item) then
      count = count + 1
    end
  end
  return count
end

--[[
  Get average of numeric values extracted from items
  @param extractor function(item) -> number
  @return number or nil if empty
]]
function RingBuffer:average(extractor)
  if self.size == 0 then return nil end
  
  local sum = 0
  for item in self:iterate() do
    sum = sum + (extractor(item) or 0)
  end
  return sum / self.size
end

--[[
  Remove items older than cutoff time
  @param cutoffTime (number) Timestamp threshold
  @param timeExtractor function(item) -> timestamp
  @return number of items removed
]]
function RingBuffer:trimOlderThan(cutoffTime, timeExtractor)
  -- For ring buffer, we can't truly remove middle elements
  -- Instead, we create a new buffer with only valid items
  local removed = 0
  local newData = {}
  local newSize = 0
  
  for item in self:iterate() do
    local itemTime = timeExtractor(item)
    if itemTime >= cutoffTime then
      newSize = newSize + 1
      newData[newSize] = item
    else
      removed = removed + 1
      -- Release to pool if configured
      if self.poolName and nExBot and nExBot.releaseTable and type(item) == "table" then
        nExBot.releaseTable(self.poolName, item)
      end
    end
  end
  
  -- Reset buffer with remaining items
  self.data = {}
  self.head = 1
  self.size = 0
  for i = 1, newSize do
    self:push(newData[i])
  end
  
  return removed
end

--[[
  Get module stats for debugging
  @return stats table
]]
function RingBuffer.getStats()
  return {
    created = stats.created,
    pushes = stats.pushes,
    clears = stats.clears
  }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STATIC HELPER FUNCTIONS FOR BOUNDED ARRAYS
-- These provide O(1) bounded array operations without converting to RingBuffer
-- ═══════════════════════════════════════════════════════════════════════════

--[[
  Push to a bounded array with O(1) amortized complexity
  Instead of: table.insert(arr, item); while #arr > max do table.remove(arr, 1) end
  Use: RingBuffer.boundedPush(arr, item, max)
  
  This shifts oldest elements in batches to avoid O(n) per push.
  
  @param arr (table) The array to push to
  @param item (any) The item to push
  @param maxSize (number) Maximum array size
  @return (table) The same array (for chaining)
]]
function RingBuffer.boundedPush(arr, item, maxSize)
  arr[#arr + 1] = item
  
  -- Only compact when significantly over limit (batch removal)
  if #arr > maxSize * 1.5 then
    local removeCount = #arr - maxSize
    -- Shift all elements left
    for i = 1, #arr - removeCount do
      arr[i] = arr[i + removeCount]
    end
    -- Clear trailing elements
    for i = #arr - removeCount + 1, #arr do
      arr[i] = nil
    end
  end
  
  return arr
end

--[[
  Trim array to max size (call periodically for cleanup)
  More efficient than per-push trimming for high-frequency updates
  
  @param arr (table) The array to trim
  @param maxSize (number) Maximum array size
  @return (number) Number of elements removed
]]
function RingBuffer.trimArray(arr, maxSize)
  local excess = #arr - maxSize
  if excess <= 0 then return 0 end
  
  -- Shift elements left
  for i = 1, maxSize do
    arr[i] = arr[i + excess]
  end
  -- Clear trailing
  for i = maxSize + 1, #arr do
    arr[i] = nil
  end
  
  return excess
end

--[[
  Create a bounded array wrapper with automatic management
  Returns a table with push/get/iterate methods but backed by simple array
  
  @param maxSize (number) Maximum capacity
  @return bounded array wrapper
]]
function RingBuffer.createBoundedArray(maxSize)
  local arr = {}
  local wrapper = {}
  
  function wrapper:push(item)
    RingBuffer.boundedPush(arr, item, maxSize)
  end
  
  function wrapper:get(index)
    return arr[index]
  end
  
  function wrapper:size()
    return #arr
  end
  
  function wrapper:newest()
    return arr[#arr]
  end
  
  function wrapper:oldest()
    return arr[1]
  end
  
  function wrapper:iterate()
    local i = 0
    return function()
      i = i + 1
      return arr[i]
    end
  end
  
  function wrapper:clear()
    for i = 1, #arr do arr[i] = nil end
  end
  
  function wrapper:toArray()
    return arr
  end
  
  return wrapper
end

-- Export globally for easy access across codebase (no _G in OTClient sandbox)
if not BoundedPush then BoundedPush = RingBuffer.boundedPush end
if not TrimArray then TrimArray = RingBuffer.trimArray end

return RingBuffer
