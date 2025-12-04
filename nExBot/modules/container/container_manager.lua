--[[
  nExBot Container Manager
  Recursive backpack management and item searching
  
  Author: nExBot Team
  Version: 1.0.0
]]

local ContainerManager = {
  openContainers = {},
  containerCache = {},
  cacheTimeout = 5000,
  lastCacheUpdate = 0
}

-- Common container IDs
local CONTAINER_IDS = {
  1987, 1988, 1989, 1990, 1991, 1992, 1993, 1994, 1995, 1996,
  1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005, 2006,
  2853, 2854, 2855, 2856, 2857, 2858, 2859, 2860, 2861, 2862,
  2863, 2864, 2865, 2866, 2867, 2868, 2869, 2870, 2871, 2872,
  3939, 3940, 5926, 5927, 5928, 5929, 7342, 7343, 7344, 7345,
  7346, 7347, 7348, 7349, 7350, 7351, 7352, 7353, 9601, 9602,
  9603, 9604, 9605, 10518, 10519, 10520, 10521, 10522, 10523,
  11119, 11243, 11244, 11263, 11264, 12101, 12102, 12103, 12104
}

function ContainerManager:new()
  local instance = {
    openContainers = {},
    containerCache = {},
    cacheTimeout = 5000,
    lastCacheUpdate = 0
  }
  setmetatable(instance, { __index = self })
  return instance
end

function ContainerManager:isContainer(itemId)
  for _, id in ipairs(CONTAINER_IDS) do
    if itemId == id then
      return true
    end
  end
  return false
end

function ContainerManager:getOpenContainers()
  if not getContainers then return {} end
  return getContainers()
end

function ContainerManager:getContainerCount()
  local containers = self:getOpenContainers()
  local count = 0
  for _ in pairs(containers) do
    count = count + 1
  end
  return count
end

function ContainerManager:openAllBackpacks()
  local opened = {}
  local containers = self:getOpenContainers()
  
  for _, container in pairs(containers) do
    local items = container:getItems()
    
    for _, item in ipairs(items) do
      if self:isContainer(item:getId()) then
        g_game.open(item, container)
        table.insert(opened, {
          itemId = item:getId(),
          name = item:getName()
        })
      end
    end
  end
  
  return opened
end

function ContainerManager:closeAllContainers()
  local containers = self:getOpenContainers()
  local closed = 0
  
  for _, container in pairs(containers) do
    g_game.close(container)
    closed = closed + 1
  end
  
  return closed
end

function ContainerManager:searchInAllContainers(itemId)
  local results = {}
  local containers = self:getOpenContainers()
  
  for _, container in pairs(containers) do
    local items = container:getItems()
    
    for slot, item in ipairs(items) do
      if item:getId() == itemId then
        table.insert(results, {
          container = container,
          slot = slot,
          item = item,
          count = item:getCount()
        })
      end
    end
  end
  
  return results
end

function ContainerManager:searchByName(itemName)
  local results = {}
  local containers = self:getOpenContainers()
  itemName = itemName:lower()
  
  for _, container in pairs(containers) do
    local items = container:getItems()
    
    for slot, item in ipairs(items) do
      if item:getName():lower():find(itemName) then
        table.insert(results, {
          container = container,
          slot = slot,
          item = item,
          count = item:getCount(),
          name = item:getName()
        })
      end
    end
  end
  
  return results
end

function ContainerManager:getTotalItemCount(itemId)
  local total = 0
  local results = self:searchInAllContainers(itemId)
  
  for _, entry in ipairs(results) do
    total = total + entry.count
  end
  
  return total
end

function ContainerManager:moveItemToContainer(item, targetContainer, amount)
  if not item or not targetContainer then return false end
  
  amount = amount or item:getCount()
  
  g_game.move(item, targetContainer:getSlotPosition(targetContainer:getItemsCount()), amount)
  
  return true
end

function ContainerManager:getContainerByName(name)
  local containers = self:getOpenContainers()
  name = name:lower()
  
  for _, container in pairs(containers) do
    if container:getName():lower():find(name) then
      return container
    end
  end
  
  return nil
end

function ContainerManager:getContainerByItem(itemId)
  local containers = self:getOpenContainers()
  
  for _, container in pairs(containers) do
    if container:getContainerItem():getId() == itemId then
      return container
    end
  end
  
  return nil
end

function ContainerManager:containerIsFull(container)
  if not container then return true end
  return container:getItemsCount() >= container:getCapacity()
end

function ContainerManager:getFirstAvailableContainer()
  local containers = self:getOpenContainers()
  
  for _, container in pairs(containers) do
    if not self:containerIsFull(container) then
      return container
    end
  end
  
  return nil
end

function ContainerManager:sortContainer(container, sortFunc)
  if not container then return false end
  
  -- Default sort by item ID
  sortFunc = sortFunc or function(a, b)
    return a:getId() < b:getId()
  end
  
  local items = container:getItems()
  table.sort(items, sortFunc)
  
  -- Rearrange items (simplified - actual implementation would need proper move logic)
  return true
end

function ContainerManager:getContainerFreeSlots(container)
  if not container then return 0 end
  return container:getCapacity() - container:getItemsCount()
end

function ContainerManager:getTotalFreeSlots()
  local total = 0
  local containers = self:getOpenContainers()
  
  for _, container in pairs(containers) do
    total = total + self:getContainerFreeSlots(container)
  end
  
  return total
end

return ContainerManager
