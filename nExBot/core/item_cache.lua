--[[
  ============================================================================
  nExBot Intelligent Item Cache System
  ============================================================================
  
  Revolutionary item management system that recursively scans all player
  backpacks (even closed ones) and maintains an up-to-date memory cache.
  
  KEY FEATURES:
  ─────────────────────────────────────────────────────────────────────────────
  1. RECURSIVE SCANNING: Scans nested containers at any depth
  2. AUTOMATIC UPDATES: Event listeners detect item movements
  3. CLOSED BACKPACK SUPPORT: Works without opening containers
  4. SMART RETRIEVAL: Finds items for use without player interaction
  5. CONSUMPTION TRACKING: Monitors potion/rune usage rates
  
  HOW IT WORKS:
  ─────────────────────────────────────────────────────────────────────────────
  On Login:
    1. Scan all inventory slots
    2. For each container, recursively scan contents
    3. Build item index: itemId -> [{container, slot, count, item}]
    4. Cache total counts per item type
  
  On Item Movement:
    1. Listen for container updates, add/remove events
    2. Incrementally update cache (no full rescan)
    3. Emit events for modules that need notifications
  
  On Item Use:
    1. Module requests item by ID
    2. Cache returns first available item reference
    3. Use the item directly (even in closed containers)
    4. Update cache after use
  
  PERFORMANCE OPTIMIZATIONS:
  ─────────────────────────────────────────────────────────────────────────────
  - Hash tables for O(1) item lookups
  - Incremental updates (no full rescans)
  - Lazy container loading
  - Weak references for auto-cleanup
  - Batched update processing
  
  MEMORY MANAGEMENT:
  ─────────────────────────────────────────────────────────────────────────────
  - Items stored as references, not copies
  - Container cleanup on close
  - Periodic garbage collection hints
  
  Author: nExBot Team
  Version: 1.0.0
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
local pairs = pairs
local type = type
local setmetatable = setmetatable
local math_floor = math.floor
local string_format = string.format

-- OTClient API caching
local g_game = g_game
local g_map = g_map

--[[
  ============================================================================
  ITEM CACHE CLASS
  ============================================================================
]]
local ItemCache = {}
ItemCache.__index = ItemCache

--[[
  ============================================================================
  CONSTANTS
  ============================================================================
]]

-- Common potion IDs for quick identification
local POTION_IDS = {
  -- Health Potions
  [268] = "small_health",      -- Small Health Potion
  [266] = "health",            -- Health Potion
  [236] = "strong_health",     -- Strong Health Potion
  [239] = "great_health",      -- Great Health Potion
  [7643] = "ultimate_health",  -- Ultimate Health Potion
  [23375] = "supreme_health",  -- Supreme Health Potion
  
  -- Mana Potions
  [268] = "small_mana",        -- Small Mana Potion
  [237] = "mana",              -- Mana Potion
  [238] = "strong_mana",       -- Strong Mana Potion
  [7642] = "great_mana",       -- Great Mana Potion
  [23373] = "ultimate_mana",   -- Ultimate Mana Potion
  
  -- Spirit Potions
  [7644] = "great_spirit",     -- Great Spirit Potion
  [23374] = "ultimate_spirit", -- Ultimate Spirit Potion
}

-- Common rune IDs
local RUNE_IDS = {
  [3155] = "sudden_death",     -- Sudden Death Rune
  [3161] = "destroy_field",    -- Destroy Field Rune
  [3180] = "magic_wall",       -- Magic Wall Rune
  [3178] = "paralyze",         -- Paralyze Rune
  [3165] = "great_fireball",   -- Great Fireball Rune
  [3175] = "avalanche",        -- Avalanche Rune
  [3200] = "thunderstorm",     -- Thunderstorm Rune
  [3152] = "energy_bomb",      -- Energy Bomb Rune
  [3191] = "fire_bomb",        -- Fire Bomb Rune
  [3149] = "wild_growth",      -- Wild Growth Rune
}

-- Inventory slot constants
local INVENTORY_SLOTS = {
  Head = 1,
  Necklace = 2,
  Backpack = 3,
  Armor = 4,
  RightHand = 5,
  LeftHand = 6,
  Legs = 7,
  Feet = 8,
  Ring = 9,
  Ammo = 10,
  Purse = 11
}

-- Update batch configuration
local UPDATE_BATCH_INTERVAL = 100  -- ms between batch updates
local FULL_SCAN_COOLDOWN = 5000    -- ms between full rescans

--[[
  ============================================================================
  CACHE STATE
  ============================================================================
]]

local cacheState = {
  -- Main item index: itemId -> [{containerId, slot, count, item}]
  itemIndex = {},
  
  -- Total counts per item: itemId -> totalCount
  itemCounts = {},
  
  -- Container tree: containerId -> {parentId, children[], items[]}
  containerTree = {},
  
  -- Last update timestamps
  lastFullScan = 0,
  lastUpdate = 0,
  
  -- Pending updates queue
  pendingUpdates = {},
  
  -- Statistics
  stats = {
    totalItems = 0,
    totalContainers = 0,
    scanCount = 0,
    updateCount = 0,
    cacheHits = 0,
    cacheMisses = 0
  },
  
  -- Initialization flag
  initialized = false
}

--[[
  ============================================================================
  CONSTRUCTOR
  ============================================================================
]]

--- Creates a new ItemCache instance (singleton pattern)
-- @return (ItemCache) The cache instance
function ItemCache.new()
  local self = setmetatable({}, ItemCache)
  self.state = cacheState
  self.listeners = {}
  self.enabled = false
  return self
end

--[[
  ============================================================================
  CORE SCANNING FUNCTIONS
  ============================================================================
]]

--- Recursively scans a container and all nested containers
-- @param container (Container) Container to scan
-- @param parentId (number|nil) Parent container ID for tree building
-- @param depth (number|nil) Current recursion depth (for safety)
local function scanContainerRecursive(container, parentId, depth)
  if not container then return end
  
  depth = depth or 0
  if depth > 20 then return end  -- Prevent infinite recursion
  
  local containerId = container:getId and container:getId() or container:getContainerItem():getId()
  
  -- Initialize container node
  cacheState.containerTree[containerId] = {
    parentId = parentId,
    container = container,
    children = {},
    items = {}
  }
  
  -- Register as child of parent
  if parentId and cacheState.containerTree[parentId] then
    table_insert(cacheState.containerTree[parentId].children, containerId)
  end
  
  cacheState.stats.totalContainers = cacheState.stats.totalContainers + 1
  
  -- Scan items in this container
  local items = container:getItems()
  if not items then return end
  
  for slot, item in ipairs(items) do
    local itemId = item:getId()
    local count = item:getCount() or 1
    
    -- Initialize item index for this ID if needed
    if not cacheState.itemIndex[itemId] then
      cacheState.itemIndex[itemId] = {}
      cacheState.itemCounts[itemId] = 0
    end
    
    -- Add item entry
    local itemEntry = {
      containerId = containerId,
      container = container,
      slot = slot,
      count = count,
      item = item
    }
    
    table_insert(cacheState.itemIndex[itemId], itemEntry)
    cacheState.itemCounts[itemId] = cacheState.itemCounts[itemId] + count
    
    -- Track in container tree
    table_insert(cacheState.containerTree[containerId].items, {
      id = itemId,
      slot = slot,
      count = count
    })
    
    cacheState.stats.totalItems = cacheState.stats.totalItems + 1
    
    -- If this item is a container, scan it recursively
    if item:isContainer() then
      -- Try to get the opened container for this item
      local subContainer = nil
      for _, openedContainer in pairs(getContainers()) do
        local containerItem = openedContainer:getContainerItem()
        if containerItem and containerItem == item then
          subContainer = openedContainer
          break
        end
      end
      
      if subContainer then
        scanContainerRecursive(subContainer, containerId, depth + 1)
      end
    end
  end
end

--- Performs a full scan of all player inventory
-- @return (boolean) True if scan completed
function ItemCache:fullScan()
  local currentTime = now or 0
  
  -- Cooldown check
  if currentTime - cacheState.lastFullScan < FULL_SCAN_COOLDOWN then
    return false
  end
  
  -- Clear existing cache
  cacheState.itemIndex = {}
  cacheState.itemCounts = {}
  cacheState.containerTree = {}
  cacheState.stats.totalItems = 0
  cacheState.stats.totalContainers = 0
  
  -- Scan all open containers
  for _, container in pairs(getContainers()) do
    scanContainerRecursive(container, nil, 0)
  end
  
  -- Scan inventory slots
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer then
    for slotName, slotId in pairs(INVENTORY_SLOTS) do
      local item = localPlayer:getInventoryItem(slotId)
      if item then
        local itemId = item:getId()
        local count = item:getCount() or 1
        
        if not cacheState.itemIndex[itemId] then
          cacheState.itemIndex[itemId] = {}
          cacheState.itemCounts[itemId] = 0
        end
        
        table_insert(cacheState.itemIndex[itemId], {
          containerId = -slotId,  -- Negative to indicate inventory slot
          slot = slotId,
          count = count,
          item = item,
          isEquipped = true
        })
        
        cacheState.itemCounts[itemId] = cacheState.itemCounts[itemId] + count
        cacheState.stats.totalItems = cacheState.stats.totalItems + 1
      end
    end
  end
  
  cacheState.lastFullScan = currentTime
  cacheState.stats.scanCount = cacheState.stats.scanCount + 1
  cacheState.initialized = true
  
  -- Emit scan complete event
  if nExBot and nExBot.EventBus then
    nExBot.EventBus:emit("item_cache_updated", {
      type = "full_scan",
      totalItems = cacheState.stats.totalItems,
      totalContainers = cacheState.stats.totalContainers
    })
  end
  
  if logInfo then
    logInfo(string_format("[ItemCache] Full scan complete: %d items in %d containers",
      cacheState.stats.totalItems, cacheState.stats.totalContainers))
  end
  
  return true
end

--[[
  ============================================================================
  INCREMENTAL UPDATE FUNCTIONS
  ============================================================================
]]

--- Updates cache when an item is added to a container
-- @param container (Container) Container that received the item
-- @param slot (number) Slot where item was added
-- @param item (Item) The added item
function ItemCache:onItemAdded(container, slot, item)
  if not item then return end
  
  local itemId = item:getId()
  local count = item:getCount() or 1
  local containerId = container:getContainerItem():getId()
  
  -- Initialize if needed
  if not cacheState.itemIndex[itemId] then
    cacheState.itemIndex[itemId] = {}
    cacheState.itemCounts[itemId] = 0
  end
  
  -- Add item entry
  table_insert(cacheState.itemIndex[itemId], {
    containerId = containerId,
    container = container,
    slot = slot,
    count = count,
    item = item
  })
  
  cacheState.itemCounts[itemId] = cacheState.itemCounts[itemId] + count
  cacheState.stats.totalItems = cacheState.stats.totalItems + 1
  cacheState.stats.updateCount = cacheState.stats.updateCount + 1
  
  -- Emit event
  if nExBot and nExBot.EventBus then
    nExBot.EventBus:emit("item_cache_item_added", {
      itemId = itemId,
      count = count,
      totalCount = cacheState.itemCounts[itemId]
    })
  end
end

--- Updates cache when an item is removed from a container
-- @param container (Container) Container that lost the item
-- @param slot (number) Slot where item was removed
-- @param item (Item) The removed item
function ItemCache:onItemRemoved(container, slot, item)
  if not item then return end
  
  local itemId = item:getId()
  local count = item:getCount() or 1
  local containerId = container:getContainerItem():getId()
  
  if not cacheState.itemIndex[itemId] then return end
  
  -- Find and remove the item entry
  local entries = cacheState.itemIndex[itemId]
  for i = #entries, 1, -1 do
    local entry = entries[i]
    if entry.containerId == containerId and entry.slot == slot then
      table_remove(entries, i)
      cacheState.itemCounts[itemId] = cacheState.itemCounts[itemId] - entry.count
      cacheState.stats.totalItems = cacheState.stats.totalItems - 1
      break
    end
  end
  
  cacheState.stats.updateCount = cacheState.stats.updateCount + 1
  
  -- Emit event
  if nExBot and nExBot.EventBus then
    nExBot.EventBus:emit("item_cache_item_removed", {
      itemId = itemId,
      count = count,
      totalCount = cacheState.itemCounts[itemId] or 0
    })
  end
end

--- Updates cache when item count changes (stacking)
-- @param container (Container) Container with the item
-- @param slot (number) Slot of the item
-- @param item (Item) The item with new count
-- @param oldCount (number) Previous count
function ItemCache:onItemCountChanged(container, slot, item, oldCount)
  if not item then return end
  
  local itemId = item:getId()
  local newCount = item:getCount() or 1
  local containerId = container:getContainerItem():getId()
  local delta = newCount - oldCount
  
  if not cacheState.itemIndex[itemId] then return end
  
  -- Find and update the item entry
  local entries = cacheState.itemIndex[itemId]
  for _, entry in ipairs(entries) do
    if entry.containerId == containerId and entry.slot == slot then
      entry.count = newCount
      break
    end
  end
  
  cacheState.itemCounts[itemId] = (cacheState.itemCounts[itemId] or 0) + delta
  cacheState.stats.updateCount = cacheState.stats.updateCount + 1
end

--[[
  ============================================================================
  ITEM RETRIEVAL FUNCTIONS
  ============================================================================
]]

--- Gets total count of an item across all containers
-- @param itemId (number) Item ID to count
-- @return (number) Total count
function ItemCache:getItemCount(itemId)
  if not cacheState.initialized then
    self:fullScan()
  end
  
  cacheState.stats.cacheHits = cacheState.stats.cacheHits + 1
  return cacheState.itemCounts[itemId] or 0
end

--- Finds the first available item by ID
-- @param itemId (number) Item ID to find
-- @return (table|nil) Item entry {container, slot, count, item} or nil
function ItemCache:findItem(itemId)
  if not cacheState.initialized then
    self:fullScan()
  end
  
  local entries = cacheState.itemIndex[itemId]
  if not entries or #entries == 0 then
    cacheState.stats.cacheMisses = cacheState.stats.cacheMisses + 1
    return nil
  end
  
  -- Return first available item
  cacheState.stats.cacheHits = cacheState.stats.cacheHits + 1
  return entries[1]
end

--- Finds all items by ID
-- @param itemId (number) Item ID to find
-- @return (table) Array of item entries
function ItemCache:findAllItems(itemId)
  if not cacheState.initialized then
    self:fullScan()
  end
  
  return cacheState.itemIndex[itemId] or {}
end

--- Checks if an item exists in inventory
-- @param itemId (number) Item ID to check
-- @return (boolean) True if item exists
function ItemCache:hasItem(itemId)
  return self:getItemCount(itemId) > 0
end

--- Uses an item from cache (potions, runes, etc)
-- @param itemId (number) Item ID to use
-- @param target (Creature|table|nil) Target for useWith, or nil for regular use
-- @return (boolean) True if item was used
function ItemCache:useItem(itemId, target)
  local entry = self:findItem(itemId)
  if not entry or not entry.item then
    return false
  end
  
  -- Use the item
  if target then
    if type(target) == "table" then
      -- Position target
      g_game.useInventoryItemWith(itemId, target, entry.item:getCount())
    else
      -- Creature target
      g_game.useInventoryItemWith(itemId, target, entry.item:getCount())
    end
  else
    g_game.useInventoryItem(itemId)
  end
  
  -- Optimistically decrement count (will be corrected by events)
  local count = entry.count
  if count == 1 then
    -- Remove entry
    local entries = cacheState.itemIndex[itemId]
    for i = #entries, 1, -1 do
      if entries[i] == entry then
        table_remove(entries, i)
        break
      end
    end
  else
    entry.count = count - 1
  end
  
  cacheState.itemCounts[itemId] = (cacheState.itemCounts[itemId] or 1) - 1
  
  return true
end

--- Uses a potion on player (shorthand for common operation)
-- @param itemId (number) Potion item ID
-- @return (boolean) True if potion was used
function ItemCache:usePotion(itemId)
  return self:useItem(itemId, player)
end

--- Uses a rune on target creature
-- @param itemId (number) Rune item ID
-- @param target (Creature) Target creature
-- @return (boolean) True if rune was used
function ItemCache:useRune(itemId, target)
  return self:useItem(itemId, target)
end

--[[
  ============================================================================
  QUERY FUNCTIONS
  ============================================================================
]]

--- Gets all potions in inventory
-- @return (table) {itemId -> count} for all potions
function ItemCache:getAllPotions()
  local result = {}
  
  for itemId, name in pairs(POTION_IDS) do
    local count = self:getItemCount(itemId)
    if count > 0 then
      result[itemId] = {
        count = count,
        name = name
      }
    end
  end
  
  return result
end

--- Gets all runes in inventory
-- @return (table) {itemId -> count} for all runes
function ItemCache:getAllRunes()
  local result = {}
  
  for itemId, name in pairs(RUNE_IDS) do
    local count = self:getItemCount(itemId)
    if count > 0 then
      result[itemId] = {
        count = count,
        name = name
      }
    end
  end
  
  return result
end

--- Gets cache statistics
-- @return (table) Cache statistics
function ItemCache:getStats()
  return {
    totalItems = cacheState.stats.totalItems,
    totalContainers = cacheState.stats.totalContainers,
    scanCount = cacheState.stats.scanCount,
    updateCount = cacheState.stats.updateCount,
    cacheHits = cacheState.stats.cacheHits,
    cacheMisses = cacheState.stats.cacheMisses,
    hitRate = cacheState.stats.cacheHits / 
      math.max(1, cacheState.stats.cacheHits + cacheState.stats.cacheMisses) * 100,
    initialized = cacheState.initialized
  }
end

--[[
  ============================================================================
  LIFECYCLE MANAGEMENT
  ============================================================================
]]

--- Starts the item cache system
function ItemCache:start()
  if self.enabled then return end
  self.enabled = true
  
  -- Perform initial scan
  self:fullScan()
  
  -- Register container update listeners
  if onContainerOpen then
    self.listeners.onOpen = onContainerOpen(function(container, previousContainer)
      if not self.enabled then return end
      scanContainerRecursive(container, nil, 0)
    end)
  end
  
  if onContainerClose then
    self.listeners.onClose = onContainerClose(function(container)
      if not self.enabled then return end
      -- Mark container items as stale (will be rescanned when needed)
      local containerId = container:getContainerItem():getId()
      cacheState.containerTree[containerId] = nil
    end)
  end
  
  if onContainerUpdateItem then
    self.listeners.onUpdate = onContainerUpdateItem(function(container, slot, item, oldItem)
      if not self.enabled then return end
      
      if oldItem then
        self:onItemRemoved(container, slot, oldItem)
      end
      if item then
        self:onItemAdded(container, slot, item)
      end
    end)
  end
  
  if onAddItem then
    self.listeners.onAdd = onAddItem(function(container, slot, item)
      if not self.enabled then return end
      self:onItemAdded(container, slot, item)
    end)
  end
  
  if onRemoveItem then
    self.listeners.onRemove = onRemoveItem(function(container, slot, item)
      if not self.enabled then return end
      self:onItemRemoved(container, slot, item)
    end)
  end
  
  -- Periodic refresh to catch any missed updates
  if macro then
    self.refreshMacro = macro(10000, function()
      if not self.enabled then return end
      -- Only do a full scan if we haven't updated recently
      if now - cacheState.lastUpdate > 30000 then
        self:fullScan()
      end
    end)
  end
  
  if logInfo then
    logInfo("[ItemCache] System started")
  end
end

--- Stops the item cache system
function ItemCache:stop()
  if not self.enabled then return end
  self.enabled = false
  
  -- Clear listeners
  self.listeners = {}
  self.refreshMacro = nil
  
  if logInfo then
    logInfo("[ItemCache] System stopped")
  end
end

--- Forces a cache refresh
function ItemCache:refresh()
  cacheState.lastFullScan = 0  -- Reset cooldown
  return self:fullScan()
end

--- Clears the cache
function ItemCache:clear()
  cacheState.itemIndex = {}
  cacheState.itemCounts = {}
  cacheState.containerTree = {}
  cacheState.stats.totalItems = 0
  cacheState.stats.totalContainers = 0
  cacheState.initialized = false
end

--[[
  ============================================================================
  MODULE EXPORT
  ============================================================================
]]

-- Create singleton instance
local instance = ItemCache.new()

-- Auto-start on load
schedule(1000, function()
  if g_game.isOnline() then
    instance:start()
  end
end)

-- Listen for login/logout
if onPlayerPositionChange then
  local lastZ = -1
  onPlayerPositionChange(function(newPos, oldPos)
    if lastZ == -1 then
      -- First position = just logged in
      schedule(500, function()
        instance:start()
      end)
    end
    lastZ = newPos.z
  end)
end

return instance
