-- Safe function calls to prevent "attempt to call global function (a nil value)" errors
local SafeCall = SafeCall or require("core.safe_call")

--------------------------------------------------------------------------------
-- CLIENTSERVICE HELPERS (using global ClientHelper for consistency)
--------------------------------------------------------------------------------
local function getClient()
  return ClientHelper and ClientHelper.getClient() or ClientService
end

local function getClientVersion()
  return ClientHelper and ClientHelper.getClientVersion() or ((g_game and g_game.getClientVersion and g_game.getClientVersion()) or 1200)
end

TargetBot.Looting = {}
TargetBot.Looting.list = {} -- list of containers to loot

local ui
local items = {}
local containers = {}
local itemsById = {}
local containersById = {}
local dontSave = false

TargetBot.Looting.setup = function()
  ui = UI.createWidget("TargetBotLootingPanel")
  UI.Container(TargetBot.Looting.onItemsUpdate, true, nil, ui.items)
  UI.Container(TargetBot.Looting.onContainersUpdate, true, nil, ui.containers)

  ui.everyItem.onClick = function()
    if ui.everyItem and ui.everyItem.isOn then ui.everyItem:setOn(not ui.everyItem:isOn()) end
    TargetBot.save()
  end

  -- Eat food from corpses toggle
  ui.eatFromCorpses.onClick = function()
    ui.eatFromCorpses:setOn(not ui.eatFromCorpses:isOn())
    if TargetBot.EatFood and TargetBot.EatFood.setEnabled then
      TargetBot.EatFood.setEnabled(ui.eatFromCorpses:isOn())
    end
    TargetBot.save()
  end

  ui.maxDangerPanel.value.onTextChange = function()
    local value = tonumber(ui.maxDangerPanel.value:getText())
    if not value then
      ui.maxDangerPanel.value:setText(0)
    end
    if dontSave then return end
    TargetBot.save()
  end
  ui.minCapacityPanel.value.onTextChange = function()
    local value = tonumber(ui.minCapacityPanel.value:getText())
    if not value then
      ui.minCapacityPanel.value:setText(0)
    end
    if dontSave then return end
    TargetBot.save()
  end

  -- Event-driven triggers: mark loot state dirty when containers change
  if EventBus and nExBot and nExBot.EventUtil and nExBot.EventUtil.debounce then
    local markDirtyDebounced = nExBot.EventUtil.debounce(120, function()
      TargetBot.Looting.markDirty()
    end)

    EventBus.on("container:open", function(container, prev)
      markDirtyDebounced()
    end, 20)

    EventBus.on("container:close", function(container)
      markDirtyDebounced()
    end, 20)

    EventBus.on("container:update", function(container, slot, item, oldItem)
      markDirtyDebounced()
    end, 20)

    -- Map tile changes can affect loot availability (containers added/removed)
    EventBus.on("tile:add", function(tile, thing)
      markDirtyDebounced()
    end, 10)

    EventBus.on("tile:remove", function(tile, thing)
      markDirtyDebounced()
    end, 10)
  end
end

TargetBot.Looting.onItemsUpdate = function()
  if dontSave then return end
  TargetBot.save()
  TargetBot.Looting.updateItemsAndContainers()
end

TargetBot.Looting.onContainersUpdate = function()
  if dontSave then return end
  TargetBot.save()
  TargetBot.Looting.updateItemsAndContainers()
end

TargetBot.Looting.update = function(data)
  dontSave = true
  TargetBot.Looting.list = {}
  ui.items:setItems(data['items'] or {})
  ui.containers:setItems(data['containers'] or {})
  ui.everyItem:setOn(data['everyItem'])
  ui.maxDangerPanel.value:setText(data['maxDanger'] or 10)
  ui.minCapacityPanel.value:setText(data['minCapacity'] or 100)
  
  -- Eat food from corpses setting
  local eatFromCorpses = data['eatFromCorpses'] or false
  ui.eatFromCorpses:setOn(eatFromCorpses)
  if TargetBot.EatFood and TargetBot.EatFood.setEnabled then
    TargetBot.EatFood.setEnabled(eatFromCorpses)
  end
  
  TargetBot.Looting.updateItemsAndContainers()
  dontSave = false
  
  -- nExBot loot tracking
  nExBot.lootContainers = {}
  nExBot.lootItems = {}
  for i, item in ipairs(ui.containers:getItems()) do
    table.insert(nExBot.lootContainers, item['id'])
  end
  for i, item in ipairs(ui.items:getItems()) do
    table.insert(nExBot.lootItems, item['id'])
  end
end

TargetBot.Looting.save = function(data)
  data['items'] = ui.items:getItems()
  data['containers'] = ui.containers:getItems()
  data['maxDanger'] = tonumber(ui.maxDangerPanel.value:getText())
  data['minCapacity'] = tonumber(ui.minCapacityPanel.value:getText())
  data['everyItem'] = (ui.everyItem and ui.everyItem.isOn) and ui.everyItem:isOn() or false
  data['eatFromCorpses'] = ui.eatFromCorpses:isOn()
end

TargetBot.Looting.updateItemsAndContainers = function()
  items = ui.items:getItems()
  containers = ui.containers:getItems()
  itemsById = {}
  containersById = {}
  for i, item in ipairs(items) do
    itemsById[item.id] = 1
  end
  for i, container in ipairs(containers) do
    containersById[container.id] = 1
  end
end

local waitTill = 0
local waitingForContainer = nil
local status = ""
local lastFoodConsumption = 0
local lootDirty = false

TargetBot.Looting.getStatus = function()
  return status
end

-- Mark looting state as needing re-evaluation
TargetBot.Looting.markDirty = function()
  lootDirty = true
end

-- Helper to reset dirty flag (called by TargetBot main loop)
TargetBot.Looting.clearDirty = function()
  lootDirty = false
end

TargetBot.Looting.isDirty = function()
  return lootDirty
end

TargetBot.Looting.process = function(targets, dangerLevel)
  if (not items[1] and not ((ui.everyItem and ui.everyItem.isOn) and ui.everyItem:isOn())) or not containers[1] then
    status = ""
    return false
  end
  local maxDanger = tonumber((ui and ui.maxDangerPanel and ui.maxDangerPanel.value and ui.maxDangerPanel.value.getText) and ui.maxDangerPanel.value:getText() or nil) or 0
  if dangerLevel > maxDanger then
    status = "High danger"
    return false
  end
  local minCap = tonumber((ui and ui.minCapacityPanel and ui.minCapacityPanel.value and ui.minCapacityPanel.value.getText) and ui.minCapacityPanel.value:getText() or nil) or 0
  local freeCap = player and player.getFreeCapacity and player:getFreeCapacity() or 0
  if freeCap < minCap then
    status = "No cap"
    TargetBot.Looting.list = {}
    return false
  end
  -- Get extras from UnifiedStorage or fallback to storage.extras
  local extras = (UnifiedStorage and UnifiedStorage.get("extras")) or storage.extras or {}
  local loot = extras.lootLast and TargetBot.Looting.list[#TargetBot.Looting.list] or TargetBot.Looting.list[1]
  if loot == nil then
    status = ""
    return false
  end

  if waitTill > now then
    return true
  end
  local Client = getClient()
  local containers = (Client and Client.getContainers) and Client.getContainers() or (g_game and g_game.getContainers and g_game.getContainers())
  local lootContainers = TargetBot.Looting.getLootContainers(containers)

  -- check if there's container for loot and has empty space for it
  if not lootContainers[1] then
    -- there's no space, don't loot
    status = "No space"
    return false
  end

  status = "Looting"

  for index, container in pairs(containers) do
    if container.lootContainer then
      TargetBot.Looting.lootContainer(lootContainers, container)
      return true
    end
  end

  local pos = player:getPosition()
  local dist = math.max(math.abs(pos.x-loot.pos.x), math.abs(pos.y-loot.pos.y))
  local maxRange = extras.looting or 40
  if loot.tries > 30 or loot.pos.z ~= pos.z or dist > maxRange then
    table.remove(TargetBot.Looting.list, extras.lootLast and #TargetBot.Looting.list or 1)
    return true
  end

  local tile = (Client and Client.getTile) and Client.getTile(loot.pos) or (g_map and g_map.getTile and g_map.getTile(loot.pos))
  if dist >= 3 or not tile then
    loot.tries = loot.tries + 1
    if nExBot and nExBot.MovementCoordinator and nExBot.MovementCoordinator.canMove then
      if nExBot.MovementCoordinator.canMove() then
        TargetBot.walkTo(loot.pos, 20, { ignoreNonPathable = true, precision = 2 })
      end
    else
      TargetBot.walkTo(loot.pos, 20, { ignoreNonPathable = true, precision = 2 })
    end
    return true
  end

  local container = tile:getTopUseThing()
  if not container or not container:isContainer() then
    table.remove(TargetBot.Looting.list, extras.lootLast and #TargetBot.Looting.list or 1)
    return true
  end

  if Client and Client.open then
    Client.open(container)
  elseif g_game and g_game.open then
    g_game.open(container)
  end
  waitTill = now + (extras.lootDelay or 200)
  waitingForContainer = container:getId()

  return true
end

--[[
  ═══════════════════════════════════════════════════════════════════════════
  LOOT CONTAINER FINDER v7.0
  
  Improved algorithm using BFS (Breadth-First Search) graph traversal.
  Properly handles nested and sibling backpacks by using a queue-based approach.
  
  Graph Traversal Logic:
  1. Scan all open containers (roots of the graph)
  2. For each container, check if it has space
  3. If full, add all nested containers to the queue
  4. Process queue: open containers one at a time
  5. Continue until we find a container with space or queue is empty
  
  Integration with ContainerOpener module for advanced opening logic.
  ═══════════════════════════════════════════════════════════════════════════
]]

-- BFS Queue for container opening
local containerOpenQueue = {}
local containerOpenIndex = 1
local openedThisCycle = {} -- Track containers opened this cycle by itemId
local lastQueueProcess = 0
local QUEUE_COOLDOWN = 200 -- ms between queue processes

-- Helper: Check if container has free space
local function hasContainerSpace(container)
  if not container then return false end
  local ok1, capacity = pcall(function() return container:getCapacity() end)
  local ok2, count = pcall(function() return container:getItemsCount() end)
  local ok3, hasPages = pcall(function() return container:hasPages() end)
  
  if hasPages then return true end -- Paged containers are always "available"
  if ok1 and ok2 then
    return count < capacity
  end
  return false
end

-- Helper: Get container item ID safely
local function getContainerId(container)
  if not container then return nil end
  local ok, containerItem = pcall(function() return container:getContainerItem() end)
  if not ok or not containerItem then return nil end
  local okId, id = pcall(function() return containerItem:getId() end)
  if okId then return id end
  return nil
end

-- Helper: Get all container items from a container
local function getNestedContainerItems(container, filterIds)
  local items = {}
  if not container then return items end
  
  local ok, containerItems = pcall(function() return container:getItems() end)
  if not ok or not containerItems then return items end
  
  for slot, item in ipairs(containerItems) do
    local okC, isContainer = pcall(function() return item:isContainer() end)
    if okC and isContainer then
      local okId, itemId = pcall(function() return item:getId() end)
      if okId and itemId then
        -- Filter by allowed container IDs if provided
        if not filterIds or filterIds[itemId] then
          table.insert(items, { item = item, id = itemId, slot = slot })
        end
      end
    end
  end
  
  return items
end

-- Enqueue container items for opening (BFS enqueue)
local function enqueueNestedContainers(container, filterIds, depth)
  local nestedItems = getNestedContainerItems(container, filterIds)
  for _, entry in ipairs(nestedItems) do
    -- Create unique key to prevent duplicates
    local key = string.format("%d_%d", entry.id, depth or 0)
    if not openedThisCycle[key] then
      table.insert(containerOpenQueue, {
        item = entry.item,
        parent = container,
        itemId = entry.id,
        depth = (depth or 0) + 1,
        key = key,
      })
    end
  end
end

-- Process the container open queue (BFS step)
local function processContainerQueue()
  if #containerOpenQueue == 0 then
    return false
  end
  
  -- Rate limit queue processing
  if now - lastQueueProcess < QUEUE_COOLDOWN then
    return true -- Queue not empty, but cooling down
  end
  
  -- Dequeue first item (BFS order)
  local entry = table.remove(containerOpenQueue, 1)
  if not entry or not entry.item then
    return #containerOpenQueue > 0
  end
  
  -- Check if already opened this cycle
  if openedThisCycle[entry.key] then
    return #containerOpenQueue > 0
  end
  
  -- Validate item still exists
  local ok, itemId = pcall(function() return entry.item:getId() end)
  if not ok or not itemId then
    return #containerOpenQueue > 0
  end
  
  -- Open the container
  lastQueueProcess = now
  openedThisCycle[entry.key] = true
  
  -- ALWAYS OPEN IN NEW WINDOW for better container management
  -- g_game.open(item) without second parameter opens in new window
  local Client = getClient()
  if Client and Client.open then
    Client.open(entry.item)
  elseif g_game and g_game.open then
    g_game.open(entry.item)
  end
  
  waitTill = now + 300
  waitingForContainer = itemId
  
  return true
end

-- Reset queue state (call at start of new loot cycle)
local function resetContainerQueue()
  containerOpenQueue = {}
  containerOpenIndex = 1
  openedThisCycle = {}
end

TargetBot.Looting.getLootContainers = function(containers)
  local lootContainers = {}
  local openedContainersById = {}
  local fullContainers = {} -- Containers that are full and need nested opening
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- PHASE 1: Scan all open containers for ones with space
  -- ═══════════════════════════════════════════════════════════════════════
  for index, container in pairs(containers) do
    local containerId = getContainerId(container)
    if containerId then
      openedContainersById[containerId] = true
      
      -- Check if this is a loot container
      if containersById[containerId] and not container.lootContainer then
        if hasContainerSpace(container) then
          table.insert(lootContainers, container)
        else
          -- Container is full, track for nested opening
          table.insert(fullContainers, container)
        end
      end
    end
  end
  
  -- If we found containers with space, return them
  if #lootContainers > 0 then
    resetContainerQueue() -- Clear queue since we have space
    return lootContainers
  end
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- PHASE 2: No space found - BFS traverse nested containers
  -- ═══════════════════════════════════════════════════════════════════════
  
  -- First, check if queue is still processing
  if #containerOpenQueue > 0 then
    processContainerQueue()
    return lootContainers
  end
  
  -- Queue is empty, build new queue from full containers
  resetContainerQueue()
  
  -- Add all nested containers from full loot containers to queue
  for _, container in ipairs(fullContainers) do
    enqueueNestedContainers(container, containersById, 0)
  end
  
  -- If we found nested containers to open, start processing
  if #containerOpenQueue > 0 then
    processContainerQueue()
    return lootContainers
  end
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- PHASE 3: Check ALL open containers for nested loot containers (aggressive scan)
  -- Also check intermediate containers that may contain loot containers
  -- ═══════════════════════════════════════════════════════════════════════
  for index, container in pairs(containers) do
    local containerId = getContainerId(container)
    if containerId and not container.lootContainer then
      -- First, look for loot containers inside
      enqueueNestedContainers(container, containersById, 0)
      
      -- Also check if any container inside might have loot containers (go deeper)
      local nestedItems = getNestedContainerItems(container, nil) -- nil = no filter, get ALL containers
      for _, entry in ipairs(nestedItems) do
        -- If this nested container is NOT a loot container, it might contain one
        if not containersById[entry.id] then
          local key = string.format("any_%d_%d", entry.id, 0)
          if not openedThisCycle[key] then
            table.insert(containerOpenQueue, {
              item = entry.item,
              parent = container,
              itemId = entry.id,
              depth = 1,
              key = key,
            })
          end
        end
      end
    end
  end
  
  if #containerOpenQueue > 0 then
    processContainerQueue()
    return lootContainers
  end
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- PHASE 4: Check ALL inventory slots for closed loot containers
  -- Includes: back, left hand, right hand (quiver!), ammo slot
  -- ═══════════════════════════════════════════════════════════════════════
  local inventorySlots = {
    InventorySlotBack,   -- Backpack
    InventorySlotLeft,   -- Left hand
    InventorySlotRight,  -- Right hand (QUIVER is usually here!)
    InventorySlotAmmo,   -- Ammo slot
  }
  
  -- First try specific slots, then fallback to all slots
  for _, slot in ipairs(inventorySlots) do
    local item = getInventoryItem(slot)
    if item then
      local okC, isContainer = pcall(function() return item:isContainer() end)
      if okC and isContainer then
        local okId, itemId = pcall(function() return item:getId() end)
        if okId and itemId and containersById[itemId] and not openedContainersById[itemId] then
          -- Found a closed loot container in inventory
          local Client = getClient()
          if Client and Client.open then
            Client.open(item)
          elseif g_game and g_game.open then
            g_game.open(item)
          end
          waitTill = now + 400
          waitingForContainer = itemId
          openedContainersById[itemId] = true
          return lootContainers
        end
      end
    end
  end
  
  -- Fallback: scan ALL slots
  for slot = InventorySlotFirst, InventorySlotLast do
    local item = getInventoryItem(slot)
    if item then
      local okC, isContainer = pcall(function() return item:isContainer() end)
      if okC and isContainer then
        local okId, itemId = pcall(function() return item:getId() end)
        if okId and itemId and containersById[itemId] and not openedContainersById[itemId] then
          -- Found a closed loot container in inventory
          local Client2 = getClient()
          if Client2 and Client2.open then
            Client2.open(item)
          elseif g_game and g_game.open then
            g_game.open(item)
          end
          waitTill = now + 400
          waitingForContainer = itemId
          openedContainersById[itemId] = true
          return lootContainers
        end
      end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- PHASE 5: Use ContainerOpener module if available (advanced opening)
  -- ═══════════════════════════════════════════════════════════════════════
  if ContainerOpener and ContainerOpener.ensureLootContainerSpace then
    local containerIdList = {}
    for id, _ in pairs(containersById) do
      table.insert(containerIdList, id)
    end
    
    if ContainerOpener.ensureLootContainerSpace(containerIdList) then
      waitTill = now + 300
      return lootContainers
    end
  end
  
  return lootContainers
end

TargetBot.Looting.lootContainer = function(lootContainers, container)
  -- loot items
  local nestedContainers = {} -- Track all nested containers for BFS
  for i, item in ipairs(container:getItems()) do
    if item:isContainer() and not itemsById[item:getId()] then
      -- Add to nested containers list instead of just tracking one
      table.insert(nestedContainers, item)
    elseif itemsById[item:getId()] or ((ui.everyItem and ui.everyItem.isOn) and ui.everyItem:isOn() and not item:isContainer()) then
      item.lootTries = (item.lootTries or 0) + 1
      if item.lootTries < 5 then -- if can't be looted within 0.5s then skip it
        return TargetBot.Looting.lootItem(lootContainers, item)
      end
    elseif storage.foodItems and storage.foodItems[1] and lastFoodConsumption + 5000 < now then
      for _, food in ipairs(storage.foodItems) do
        if item:getId() == food.id then
          local Client = getClient()
          if Client and Client.use then
            Client.use(item)
          elseif g_game and g_game.use then
            g_game.use(item)
          end
          lastFoodConsumption = now
          return
        end
      end
    end
    
    -- nExBot: Eat food from corpses feature
    if TargetBot.EatFood and TargetBot.EatFood.isEnabled and TargetBot.EatFood.isEnabled() then
      local itemId = item:getId()
      local foodIds = TargetBot.EatFood.getFoodIds and TargetBot.EatFood.getFoodIds() or {}
      if foodIds[itemId] and lastFoodConsumption + 3000 < now then
        local Client2 = getClient()
        if Client2 and Client2.use then
          Client2.use(item)
        elseif g_game and g_game.use then
          g_game.use(item)
        end
        lastFoodConsumption = now
        return
      end
    end
  end

  -- no more items to loot, open next nested container (BFS: first in queue)
  if #nestedContainers > 0 then
    local nextContainer = nestedContainers[1]
    nextContainer.lootTries = (nextContainer.lootTries or 0) + 1
    if nextContainer.lootTries < 3 then -- Increased from 2 for more reliability
      local Client3 = getClient()
      if Client3 and Client3.open then
        Client3.open(nextContainer, container)
      elseif g_game and g_game.open then
        g_game.open(nextContainer, container)
      end
      waitTill = now + 250 -- Reduced from 300ms for faster opening
      waitingForContainer = nextContainer:getId()
      return
    end
    
    -- First container failed, try next ones
    for i = 2, #nestedContainers do
      local altContainer = nestedContainers[i]
      altContainer.lootTries = (altContainer.lootTries or 0) + 1
      if altContainer.lootTries < 3 then
        local Client4 = getClient()
        if Client4 and Client4.open then
          Client4.open(altContainer, container)
        elseif g_game and g_game.open then
          g_game.open(altContainer, container)
        end
        waitTill = now + 250
        waitingForContainer = altContainer:getId()
        return
      end
    end
  end
  
  -- looting finished, remove container from list
  container.lootContainer = false
  local Client5 = getClient()
  if Client5 and Client5.close then
    Client5.close(container)
  elseif g_game and g_game.close then
    g_game.close(container)
  end
  -- Get extras from UnifiedStorage or fallback to storage.extras
  local extras = (UnifiedStorage and UnifiedStorage.get("extras")) or storage.extras or {}
  table.remove(TargetBot.Looting.list, extras.lootLast and #TargetBot.Looting.list or 1) 
end

onTextMessage(function(mode, text)
  if not TargetBot or not TargetBot.isOff or TargetBot.isOff() then return end
  local listCount = #TargetBot.Looting.list
  if listCount == 0 then return end
  -- Use pattern matching for faster check
  if text:lower():find("you are not the owner", 1, true) then
    local removeIndex = storage.extras.lootLast and listCount or 1
    table.remove(TargetBot.Looting.list, removeIndex)
  end
end)

-- Pre-cache for lootItem optimization
local stackableItemCache = {}

TargetBot.Looting.lootItem = function(lootContainers, item)
  local itemId = item:getId()
  local isStackable = item:isStackable()
  local Client = getClient()
  
  if isStackable then
    local count = item:getCount()
    -- Search for existing stacks to combine with
    for i = 1, #lootContainers do
      local container = lootContainers[i]
      local containerItems = container:getItems()
      for slot = 1, #containerItems do
        local citem = containerItems[slot]
        if citem:getId() == itemId and citem:getCount() < 100 then
          if Client and Client.move then
            Client.move(item, container:getSlotPosition(slot - 1), count)
          elseif g_game and g_game.move then
            g_game.move(item, container:getSlotPosition(slot - 1), count)
          end
          waitTill = now + 250 -- Reduced from 300ms
          return
        end
      end
    end
  end

  local container = lootContainers[1]
  local moveCount = isStackable and item:getCount() or 1
  if Client and Client.move then
    Client.move(item, container:getSlotPosition(container:getItemsCount()), moveCount)
  elseif g_game and g_game.move then
    g_game.move(item, container:getSlotPosition(container:getItemsCount()), moveCount)
  end
  waitTill = now + 250 -- Reduced from 300ms
end

onContainerOpen(function(container, previousContainer)
  local containerId = container:getContainerItem():getId()
  if containerId == waitingForContainer then
    container.lootContainer = true
    waitingForContainer = nil
  end
end)

-- Cache for faster distance calculation during sort
local playerPosCache = nil
local playerPosCacheTime = 0

local function getCachedPlayerPos()
  if now - playerPosCacheTime > 100 then
    playerPosCache = player:getPosition()
    playerPosCacheTime = now
  end
  return playerPosCache
end

onCreatureDisappear(function(creature)
  if SafeCall.isInPz() then return end
  -- Defensive: TargetBot or its isOn may not be ready during early load; guard safely
  if not TargetBot or not TargetBot.isOn or type(TargetBot.isOn) ~= 'function' or not TargetBot.isOn() then return end
  if not creature or type(creature.isMonster) ~= 'function' or not creature:isMonster() then return end
  
  local config = TargetBot.Creature.calculateParams(creature, {})
  if not config.config or config.config.dontLoot then
    return
  end
  
  local playerPos = getCachedPlayerPos()
  local mpos = creature:getPosition()
  local name = creature:getName()
  
  -- Early distance check with inlined calculation
  if playerPos.z ~= mpos.z then return end
  local dx = math.abs(playerPos.x - mpos.x)
  local dy = math.abs(playerPos.y - mpos.y)
  if math.max(dx, dy) > 6 then return end
  
  schedule(20, function()
    if not containers[1] then return end
    local listCount = #TargetBot.Looting.list
    if listCount >= 20 then return end -- too many items to loot
    
    local Client = getClient()
    local tile = (Client and Client.getTile) and Client.getTile(mpos) or (g_map and g_map.getTile and g_map.getTile(mpos))
    if not tile then return end
    
    local container = tile:getTopUseThing()
    if not container or not container:isContainer() then return end
    
    local currentPos = player:getPosition()
    if not findPath(currentPos, mpos, 6, {ignoreNonPathable=true, ignoreCreatures=true, ignoreCost=true}) then return end
    
    -- Direct index insertion is faster
    local newEntry = {
      pos = mpos,
      creature = name,
      container = container:getId(),
      added = now,
      tries = 0,
      dist = 0  -- Will be calculated during sort
    }
    TargetBot.Looting.list[listCount + 1] = newEntry

    -- Optimized sort with cached player position
    local sortPos = player:getPosition()
    table.sort(TargetBot.Looting.list, function(a, b)
      -- Calculate distances only once per sort call
      if not a._sortDist then
        a._sortDist = math.max(math.abs(a.pos.x - sortPos.x), math.abs(a.pos.y - sortPos.y))
      end
      if not b._sortDist then
        b._sortDist = math.max(math.abs(b.pos.x - sortPos.x), math.abs(b.pos.y - sortPos.y))
      end
      return a._sortDist > b._sortDist
    end)
    
    -- Clear cached sort distances
    for _, entry in ipairs(TargetBot.Looting.list) do
      entry._sortDist = nil
    end
    
    container:setMarked('#000088')
  end)
end)
