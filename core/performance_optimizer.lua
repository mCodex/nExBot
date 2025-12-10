--[[
  Performance Optimization Module for nExBot
  
  Provides performance optimizations:
  - Predictive Pathfinding
  - Lazy Evaluation System
  - Batch Item Operations
  - Container Caching
  
  Author: nExBot Team
  Version: 1.1
]]

PerformanceOptimizer = {}

-- Helper function to safely get item count
local function safeGetCount(item)
  if item and item.getCount then
    return item:getCount()
  end
  return 1
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local Config = {
  -- Predictive Pathfinding
  pathfinding = {
    enabled = true,
    cacheSize = 100,          -- Max cached paths
    cacheTTL = 5000,          -- Path cache lifetime (ms)
    predictiveDepth = 3,      -- Number of future waypoints to pre-cache
    maxPathLength = 50,       -- Max path length to cache
    cleanupInterval = 10000,  -- Cache cleanup interval (ms)
  },
  
  -- Lazy Evaluation
  lazy = {
    enabled = true,
    monsterCheckInterval = 100,   -- Monster data refresh (ms)
    containerCheckInterval = 500, -- Container refresh (ms)
    tileCheckInterval = 200,      -- Tile data refresh (ms)
    equipmentCheckInterval = 1000, -- Equipment refresh (ms)
  },
  
  -- Batch Operations
  batch = {
    enabled = true,
    maxBatchSize = 10,        -- Max items per batch
    batchDelay = 50,          -- Delay between batch items (ms)
    operationTimeout = 5000,  -- Max time for batch operation (ms)
  },
  
  -- Container Caching
  container = {
    enabled = true,
    cacheSize = 50,           -- Max cached container states
    dirtyCacheTTL = 2000,     -- Time before revalidating cache (ms)
    trackChanges = true,      -- Track item changes
  }
}

-- ============================================================================
-- PREDICTIVE PATHFINDING
-- ============================================================================
PerformanceOptimizer.Pathfinding = {}

local PathCache = {
  paths = {},       -- {hash -> {path, timestamp, hitCount}}
  order = {},       -- LRU order tracking
  size = 0,
  lastCleanup = 0   -- Last cleanup timestamp
}

-- Generate hash for path lookup
local function pathHash(fromPos, toPos)
  return string.format("%d_%d_%d_%d_%d_%d", 
    fromPos.x, fromPos.y, fromPos.z,
    toPos.x, toPos.y, toPos.z)
end

-- Clean expired paths
local function cleanPathCache()
  local cutoff = now - Config.pathfinding.cacheTTL
  local toRemove = {}
  
  for hash, data in pairs(PathCache.paths) do
    if data.timestamp < cutoff then
      table.insert(toRemove, hash)
    end
  end
  
  for _, hash in ipairs(toRemove) do
    PathCache.paths[hash] = nil
    PathCache.size = PathCache.size - 1
  end
  
  -- Also trim if over size
  while PathCache.size > Config.pathfinding.cacheSize and #PathCache.order > 0 do
    local oldestHash = table.remove(PathCache.order, 1)
    if PathCache.paths[oldestHash] then
      PathCache.paths[oldestHash] = nil
      PathCache.size = PathCache.size - 1
    end
  end
end

-- Get cached path or calculate new one
function PerformanceOptimizer.Pathfinding.getPath(fromPos, toPos, options)
  if not Config.pathfinding.enabled then
    return findPath and findPath(fromPos, toPos, options or {}) or nil
  end
  
  local hash = pathHash(fromPos, toPos)
  local cached = PathCache.paths[hash]
  
  -- Return cached if valid
  if cached and (now - cached.timestamp) < Config.pathfinding.cacheTTL then
    cached.hitCount = cached.hitCount + 1
    return cached.path
  end
  
  -- Calculate new path
  local path = findPath and findPath(fromPos, toPos, options or {}) or nil
  
  -- Cache if valid and not too long
  if path and #path <= Config.pathfinding.maxPathLength then
    PathCache.paths[hash] = {
      path = path,
      timestamp = now,
      hitCount = 1
    }
    table.insert(PathCache.order, hash)
    PathCache.size = PathCache.size + 1
    
    -- Cleanup if needed
    if PathCache.size > Config.pathfinding.cacheSize then
      cleanPathCache()
    end
  end
  
  return path
end

-- Pre-cache paths to upcoming waypoints
function PerformanceOptimizer.Pathfinding.prefetchWaypoints(waypoints, currentIndex)
  if not Config.pathfinding.enabled or not waypoints then return end
  
  local playerPos = pos()
  
  for i = 0, Config.pathfinding.predictiveDepth - 1 do
    local waypointIndex = currentIndex + i
    if waypointIndex <= #waypoints then
      local waypoint = waypoints[waypointIndex]
      if waypoint and waypoint.pos then
        local fromPos = (i == 0) and playerPos or waypoints[waypointIndex - 1].pos
        
        -- Pre-calculate path in background (non-blocking)
        schedule(i * 50, function()
          PerformanceOptimizer.Pathfinding.getPath(fromPos, waypoint.pos)
        end)
      end
    end
  end
end

-- Get cache statistics
function PerformanceOptimizer.Pathfinding.getStats()
  local totalHits = 0
  for _, data in pairs(PathCache.paths) do
    totalHits = totalHits + data.hitCount
  end
  
  return {
    size = PathCache.size,
    maxSize = Config.pathfinding.cacheSize,
    totalHits = totalHits,
    utilization = PathCache.size / Config.pathfinding.cacheSize
  }
end

-- Clear path cache
function PerformanceOptimizer.Pathfinding.clearCache()
  PathCache.paths = {}
  PathCache.order = {}
  PathCache.size = 0
end

-- ============================================================================
-- LAZY EVALUATION SYSTEM
-- ============================================================================
PerformanceOptimizer.Lazy = {}

local LazyCache = {
  monsters = { data = nil, lastUpdate = 0 },
  containers = { data = nil, lastUpdate = 0 },
  tiles = { data = {}, lastUpdate = {} },
  equipment = { data = nil, lastUpdate = 0 },
  spectators = { data = nil, lastUpdate = 0 }
}

-- Lazy monster data
function PerformanceOptimizer.Lazy.getMonsters()
  if not Config.lazy.enabled then
    return getSpectators and getSpectators() or {}
  end
  
  local cache = LazyCache.monsters
  if cache.data and (now - cache.lastUpdate) < Config.lazy.monsterCheckInterval then
    return cache.data
  end
  
  -- Refresh cache
  local monsters = {}
  for _, creature in ipairs(getSpectators and getSpectators() or {}) do
    if creature:isMonster() and creature:getHealthPercent() > 0 then
      table.insert(monsters, {
        creature = creature,
        id = creature:getId(),
        name = creature:getName(),
        hp = creature:getHealthPercent(),
        pos = creature:getPosition()
      })
    end
  end
  
  cache.data = monsters
  cache.lastUpdate = now
  
  return monsters
end

-- Lazy spectators (all creatures)
function PerformanceOptimizer.Lazy.getSpectators()
  if not Config.lazy.enabled then
    return getSpectators and getSpectators() or {}
  end
  
  local cache = LazyCache.spectators
  if cache.data and (now - cache.lastUpdate) < Config.lazy.monsterCheckInterval then
    return cache.data
  end
  
  cache.data = getSpectators and getSpectators() or {}
  cache.lastUpdate = now
  
  return cache.data
end

-- Lazy container data
function PerformanceOptimizer.Lazy.getContainers()
  if not Config.lazy.enabled then
    return getContainers and getContainers() or {}
  end
  
  local cache = LazyCache.containers
  if cache.data and (now - cache.lastUpdate) < Config.lazy.containerCheckInterval then
    return cache.data
  end
  
  cache.data = getContainers and getContainers() or {}
  cache.lastUpdate = now
  
  return cache.data
end

-- Lazy tile data with position-based caching
function PerformanceOptimizer.Lazy.getTile(position)
  if not Config.lazy.enabled then
    return g_map.getTile(position)
  end
  
  local hash = string.format("%d_%d_%d", position.x, position.y, position.z)
  local cache = LazyCache.tiles
  
  if cache.data[hash] and cache.lastUpdate[hash] and 
     (now - cache.lastUpdate[hash]) < Config.lazy.tileCheckInterval then
    return cache.data[hash]
  end
  
  local tile = g_map.getTile(position)
  cache.data[hash] = tile
  cache.lastUpdate[hash] = now
  
  return tile
end

-- Lazy equipment data
function PerformanceOptimizer.Lazy.getEquipment()
  if not Config.lazy.enabled then
    return getEquipment and getEquipment() or {}
  end
  
  local cache = LazyCache.equipment
  if cache.data and (now - cache.lastUpdate) < Config.lazy.equipmentCheckInterval then
    return cache.data
  end
  
  local equipment = {}
  local slots = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}  -- All equipment slots
  
  for _, slot in ipairs(slots) do
    local item = getSlot and getSlot(slot)
    if item then
      local count = 1
      if item.getCount then
        count = item:getCount()
      end
      equipment[slot] = {
        id = item:getId(),
        count = count,
        item = item
      }
    end
  end
  
  cache.data = equipment
  cache.lastUpdate = now
  
  return equipment
end

-- Invalidate specific cache
function PerformanceOptimizer.Lazy.invalidate(cacheType)
  if LazyCache[cacheType] then
    LazyCache[cacheType].data = nil
    LazyCache[cacheType].lastUpdate = 0
  end
end

-- Invalidate all caches
function PerformanceOptimizer.Lazy.invalidateAll()
  for key, _ in pairs(LazyCache) do
    if type(LazyCache[key]) == "table" then
      LazyCache[key].data = nil
      LazyCache[key].lastUpdate = 0
    end
  end
end

-- ============================================================================
-- BATCH ITEM OPERATIONS
-- ============================================================================
PerformanceOptimizer.Batch = {}

local BatchQueue = {
  operations = {},
  isProcessing = false,
  currentIndex = 0,
  startTime = 0
}

-- Add operation to batch queue
function PerformanceOptimizer.Batch.addOperation(operation)
  if not Config.batch.enabled then
    -- Execute immediately if batching disabled
    if operation.execute then
      operation.execute()
    end
    return true
  end
  
  if #BatchQueue.operations >= Config.batch.maxBatchSize then
    return false, "Batch queue full"
  end
  
  table.insert(BatchQueue.operations, {
    execute = operation.execute,
    callback = operation.callback,
    priority = operation.priority or 0,
    timestamp = now
  })
  
  -- Sort by priority (higher first)
  table.sort(BatchQueue.operations, function(a, b)
    return a.priority > b.priority
  end)
  
  return true
end

-- Process batch queue
function PerformanceOptimizer.Batch.process()
  if not Config.batch.enabled then return end
  if BatchQueue.isProcessing then return end
  if #BatchQueue.operations == 0 then return end
  
  BatchQueue.isProcessing = true
  BatchQueue.currentIndex = 1
  BatchQueue.startTime = now
  
  local function processNext()
    -- Timeout check
    if (now - BatchQueue.startTime) > Config.batch.operationTimeout then
      BatchQueue.isProcessing = false
      BatchQueue.operations = {}
      warn("[Batch] Operation timeout - queue cleared")
      return
    end
    
    if BatchQueue.currentIndex > #BatchQueue.operations then
      BatchQueue.isProcessing = false
      BatchQueue.operations = {}
      return
    end
    
    local op = BatchQueue.operations[BatchQueue.currentIndex]
    if op and op.execute then
      local success, result = pcall(op.execute)
      if op.callback then
        op.callback(success, result)
      end
    end
    
    BatchQueue.currentIndex = BatchQueue.currentIndex + 1
    schedule(Config.batch.batchDelay, processNext)
  end
  
  processNext()
end

-- Batch move items
function PerformanceOptimizer.Batch.moveItems(items, destination)
  local results = {}
  
  for i, item in ipairs(items) do
    PerformanceOptimizer.Batch.addOperation({
      execute = function()
        if g_game.move then
          g_game.move(item, destination, safeGetCount(item))
        end
      end,
      callback = function(success, result)
        results[i] = {success = success, result = result}
      end,
      priority = #items - i  -- Process in order
    })
  end
  
  PerformanceOptimizer.Batch.process()
  return results
end

-- Batch use items
function PerformanceOptimizer.Batch.useItems(items, target)
  for i, item in ipairs(items) do
    PerformanceOptimizer.Batch.addOperation({
      execute = function()
        if target then
          g_game.useWith(item, target)
        else
          g_game.use(item)
        end
      end,
      priority = #items - i
    })
  end
  
  PerformanceOptimizer.Batch.process()
end

-- Get batch queue status
function PerformanceOptimizer.Batch.getStatus()
  return {
    pending = #BatchQueue.operations,
    isProcessing = BatchQueue.isProcessing,
    currentIndex = BatchQueue.currentIndex,
    maxSize = Config.batch.maxBatchSize
  }
end

-- Clear batch queue
function PerformanceOptimizer.Batch.clear()
  BatchQueue.operations = {}
  BatchQueue.isProcessing = false
  BatchQueue.currentIndex = 0
end

-- ============================================================================
-- CONTAINER CACHING
-- ============================================================================
PerformanceOptimizer.Containers = {}

local ContainerCache = {
  states = {},      -- {containerId -> {items, hash, timestamp, dirty}}
  itemIndex = {},   -- {itemId -> [{containerId, slot}]}
  lastCleanup = 0
}

-- Generate hash for container contents
local function containerHash(container)
  if not container then return nil end
  
  local parts = {}
  for slot = 0, container:getItemsCount() - 1 do
    local item = container:getItem(slot)
    if item then
      table.insert(parts, string.format("%d:%d", item:getId(), safeGetCount(item)))
    end
  end
  
  return table.concat(parts, ",")
end

-- Update container cache
function PerformanceOptimizer.Containers.update(container)
  if not Config.container.enabled then return end
  if not container then return end
  
  local id
  if container.getId then
    id = container:getId()
  else
    id = container:getContainerItem():getId()
  end
  local hash = containerHash(container)
  local cached = ContainerCache.states[id]
  
  -- Check if changed
  local changed = not cached or cached.hash ~= hash
  
  if changed then
    -- Build item list
    local items = {}
    for slot = 0, container:getItemsCount() - 1 do
      local item = container:getItem(slot)
      if item then
        table.insert(items, {
          id = item:getId(),
          count = safeGetCount(item),
          slot = slot,
          item = item
        })
      end
    end
    
    ContainerCache.states[id] = {
      items = items,
      hash = hash,
      timestamp = now,
      dirty = false,
      container = container
    }
    
    -- Update item index
    if Config.container.trackChanges then
      PerformanceOptimizer.Containers.rebuildIndex()
    end
  else
    cached.timestamp = now
  end
  
  return changed
end

-- Rebuild item index
function PerformanceOptimizer.Containers.rebuildIndex()
  ContainerCache.itemIndex = {}
  
  for containerId, state in pairs(ContainerCache.states) do
    for _, itemData in ipairs(state.items) do
      if not ContainerCache.itemIndex[itemData.id] then
        ContainerCache.itemIndex[itemData.id] = {}
      end
      table.insert(ContainerCache.itemIndex[itemData.id], {
        containerId = containerId,
        slot = itemData.slot,
        count = itemData.count
      })
    end
  end
end

-- Find item across all cached containers
function PerformanceOptimizer.Containers.findItem(itemId)
  if not Config.container.enabled then
    return findItem and findItem(itemId)
  end
  
  local locations = ContainerCache.itemIndex[itemId]
  if locations and #locations > 0 then
    -- Verify first result is still valid
    local loc = locations[1]
    local state = ContainerCache.states[loc.containerId]
    
    if state and (now - state.timestamp) < Config.container.dirtyCacheTTL then
      -- Return cached item
      for _, item in ipairs(state.items) do
        if item.id == itemId then
          return item.item
        end
      end
    end
  end
  
  -- Fallback to actual search
  return findItem and findItem(itemId)
end

-- Find all items of type
function PerformanceOptimizer.Containers.findAllItems(itemId)
  if not Config.container.enabled then
    -- Fallback to manual search
    local items = {}
    for _, container in pairs(getContainers and getContainers() or {}) do
      for slot = 0, container:getItemsCount() - 1 do
        local item = container:getItem(slot)
        if item and item:getId() == itemId then
          table.insert(items, item)
        end
      end
    end
    return items
  end
  
  local results = {}
  local locations = ContainerCache.itemIndex[itemId]
  
  if locations then
    for _, loc in ipairs(locations) do
      local state = ContainerCache.states[loc.containerId]
      if state then
        for _, item in ipairs(state.items) do
          if item.id == itemId then
            table.insert(results, item.item)
          end
        end
      end
    end
  end
  
  return results
end

-- Count item across all containers
function PerformanceOptimizer.Containers.countItem(itemId)
  if not Config.container.enabled then
    return itemAmount and itemAmount(itemId) or 0
  end
  
  local count = 0
  local locations = ContainerCache.itemIndex[itemId]
  
  if locations then
    for _, loc in ipairs(locations) do
      count = count + loc.count
    end
  end
  
  return count
end

-- Get container by item (find which container has item)
function PerformanceOptimizer.Containers.getContainerByItem(itemId)
  local locations = ContainerCache.itemIndex[itemId]
  if locations and #locations > 0 then
    local state = ContainerCache.states[locations[1].containerId]
    return state and state.container or nil
  end
  return nil
end

-- Mark container as dirty (needs refresh)
function PerformanceOptimizer.Containers.markDirty(containerId)
  if ContainerCache.states[containerId] then
    ContainerCache.states[containerId].dirty = true
  end
end

-- Clear container cache
function PerformanceOptimizer.Containers.clear()
  ContainerCache.states = {}
  ContainerCache.itemIndex = {}
end

-- Get cache statistics
function PerformanceOptimizer.Containers.getStats()
  local itemCount = 0
  for _, locations in pairs(ContainerCache.itemIndex) do
    itemCount = itemCount + #locations
  end
  
  local containerCount = 0
  for _ in pairs(ContainerCache.states) do
    containerCount = containerCount + 1
  end
  
  return {
    containers = containerCount,
    items = itemCount,
    maxContainers = Config.container.cacheSize
  }
end

-- ============================================================================
-- AUTO-UPDATE HOOKS
-- ============================================================================

-- Periodic cache maintenance
if macro then
  macro(1000, function()
    -- Clean path cache
    local lastCleanup = PathCache.lastCleanup or 0
    if now - lastCleanup > Config.pathfinding.cleanupInterval then
      cleanPathCache()
      PathCache.lastCleanup = now
    end
    
    -- Update open containers
    if Config.container.enabled then
      for _, container in pairs(getContainers and getContainers() or {}) do
        PerformanceOptimizer.Containers.update(container)
      end
    end
  end)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Get overall performance summary
function PerformanceOptimizer.getSummary()
  local pathStats = PerformanceOptimizer.Pathfinding.getStats()
  local containerStats = PerformanceOptimizer.Containers.getStats()
  local batchStatus = PerformanceOptimizer.Batch.getStatus()
  
  local summary = "=== Performance Optimizer ===\n"
  
  summary = summary .. "\n[Pathfinding Cache]"
  summary = summary .. "\n  Cached: " .. pathStats.size .. "/" .. pathStats.maxSize
  summary = summary .. "\n  Total Hits: " .. pathStats.totalHits
  
  summary = summary .. "\n\n[Container Cache]"
  summary = summary .. "\n  Containers: " .. containerStats.containers
  summary = summary .. "\n  Items Indexed: " .. containerStats.items
  
  summary = summary .. "\n\n[Batch Operations]"
  summary = summary .. "\n  Pending: " .. batchStatus.pending
  summary = summary .. "\n  Processing: " .. (batchStatus.isProcessing and "Yes" or "No")
  
  summary = summary .. "\n\n[Lazy Evaluation]"
  summary = summary .. "\n  Status: " .. (Config.lazy.enabled and "Active" or "Disabled")
  
  return summary
end

-- Configure module
function PerformanceOptimizer.setConfig(module, key, value)
  if Config[module] and Config[module][key] ~= nil then
    Config[module][key] = value
    return true
  end
  return false
end

function PerformanceOptimizer.getConfig(module, key)
  if Config[module] then
    return key and Config[module][key] or Config[module]
  end
  return nil
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
-- Initialization messages removed for clean output
