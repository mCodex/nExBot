--[[
  ═══════════════════════════════════════════════════════════════════════════
  CONTAINER OPENER v11.0 - Passive Helper Module
  
  This is a PASSIVE helper that does NOT automatically open containers.
  It only provides utility functions for the looting system to use ON-DEMAND.
  
  The Container Panel (Containers.lua) handles all automatic container opening.
  This module ONLY provides helper functions - NO macros, NO event handlers.
  
  Functions:
  - ContainerOpener.getAllOpenContainers() - Get all open containers
  - ContainerOpener.getOpenContainersByItemId(itemId) - Get containers by type
  - ContainerOpener.findNestedContainer(itemId) - Find closed nested container
  - ContainerOpener.openItemAsNewWindow(item) - Open item in new window
  - ContainerOpener.countOpenContainers() - Count open container windows
  ═══════════════════════════════════════════════════════════════════════════
]]

-- ═══════════════════════════════════════════════════════════════════════════
-- SAFE UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

local function safeCall(fn)
  local ok, result = pcall(fn)
  return ok and result or nil
end

local function getItemId(item)
  return item and safeCall(function() return item:getId() end)
end

local function isContainerItem(item)
  return item and safeCall(function() return item:isContainer() end) == true
end

local function getContainerWindowId(container)
  return container and safeCall(function() return container:getId() end)
end

local function getContainerItemId(container)
  if not container then return nil end
  local cItem = safeCall(function() return container:getContainerItem() end)
  return cItem and getItemId(cItem)
end

local function getContainerItems(container)
  return container and safeCall(function() return container:getItems() end) or {}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

local ContainerOpener = {}

-- Get count of open containers
function ContainerOpener.countOpenContainers()
  local containers = safeCall(function() return g_game.getContainers() end) or {}
  local count = 0
  for _ in pairs(containers) do count = count + 1 end
  return count
end

-- Get all open containers as array
function ContainerOpener.getAllOpenContainers()
  local containers = safeCall(function() return g_game.getContainers() end) or {}
  local result = {}
  for _, container in pairs(containers) do
    table.insert(result, container)
  end
  return result
end

-- Get open containers matching specific item ID(s)
function ContainerOpener.getOpenContainersByItemId(itemIds)
  if type(itemIds) ~= "table" then
    itemIds = { itemIds }
  end
  
  local lookup = {}
  for _, id in ipairs(itemIds) do lookup[id] = true end
  
  local containers = safeCall(function() return g_game.getContainers() end) or {}
  local result = {}
  
  for _, container in pairs(containers) do
    local itemId = getContainerItemId(container)
    if itemId and lookup[itemId] then
      table.insert(result, container)
    end
  end
  
  return result
end

-- Find a nested container of specified type that is NOT yet open
-- Returns: item, parentContainer, slot (or nil if not found)
function ContainerOpener.findNestedContainer(itemId)
  local containers = safeCall(function() return g_game.getContainers() end) or {}
  
  -- Build set of itemIds that are currently open as windows
  local openItemIds = {}
  for _, container in pairs(containers) do
    local id = getContainerItemId(container)
    if id then
      openItemIds[id] = (openItemIds[id] or 0) + 1
    end
  end
  
  -- Search for nested container
  for _, container in pairs(containers) do
    local items = getContainerItems(container)
    for slot, item in ipairs(items) do
      if isContainerItem(item) then
        local id = getItemId(item)
        if id == itemId or (not itemId and id) then
          -- Found a container, return it
          return item, container, slot
        end
      end
    end
  end
  
  return nil
end

-- Open an item in a NEW container window
-- IMPORTANT: This will toggle if already open! Only call if you're sure it's closed
function ContainerOpener.openItemAsNewWindow(item)
  if not item then return false end
  if not isContainerItem(item) then return false end
  
  return safeCall(function()
    g_game.open(item, nil)
    return true
  end) == true
end

-- Get all containers that have space for looting
function ContainerOpener.getContainersWithSpace(itemIds)
  local containers = ContainerOpener.getOpenContainersByItemId(itemIds)
  local result = {}
  
  for _, container in ipairs(containers) do
    local capacity = safeCall(function() return container:getCapacity() end) or 0
    local count = safeCall(function() return container:getItemsCount() end) or 0
    local hasPages = safeCall(function() return container:hasPages() end)
    
    if hasPages or count < capacity then
      table.insert(result, container)
    end
  end
  
  return result
end

-- Check if there's at least one open container with space
function ContainerOpener.hasLootSpace(itemIds)
  local containers = ContainerOpener.getContainersWithSpace(itemIds)
  return #containers > 0
end

-- Get inventory container that isn't open yet
function ContainerOpener.getClosedInventoryContainer(slot)
  slot = slot or InventorySlotBack
  local item = safeCall(function() return getInventoryItem(slot) end)
  if not item or not isContainerItem(item) then return nil end
  
  local itemId = getItemId(item)
  if not itemId then return nil end
  
  -- Check if already open
  local containers = safeCall(function() return g_game.getContainers() end) or {}
  for _, container in pairs(containers) do
    local openItemId = getContainerItemId(container)
    if openItemId == itemId then
      return nil -- Already open
    end
  end
  
  return item
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EXPORT
-- ═══════════════════════════════════════════════════════════════════════════

nExBot = nExBot or {}
nExBot.ContainerOpener = ContainerOpener
ContainerOpener = ContainerOpener
