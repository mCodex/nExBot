-- Safe function calls to prevent "attempt to call global function (a nil value)" errors
local SafeCall = SafeCall or require("core.safe_call")

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
    ui.everyItem:setOn(not ui.everyItem:isOn())
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
  data['everyItem'] = ui.everyItem:isOn()
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
  if (not items[1] and not ui.everyItem:isOn()) or not containers[1] then
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
  local loot = storage.extras.lootLast and TargetBot.Looting.list[#TargetBot.Looting.list] or TargetBot.Looting.list[1]
  if loot == nil then
    status = ""
    return false
  end

  if waitTill > now then
    return true
  end
  local containers = g_game.getContainers()
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
  local maxRange = storage.extras.looting or 40
  if loot.tries > 30 or loot.pos.z ~= pos.z or dist > maxRange then
    table.remove(TargetBot.Looting.list, storage.extras.lootLast and #TargetBot.Looting.list or 1)
    return true
  end

  local tile = g_map.getTile(loot.pos)
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
    table.remove(TargetBot.Looting.list, storage.extras.lootLast and #TargetBot.Looting.list or 1)
    return true
  end

  g_game.open(container)
  waitTill = now + (storage.extras.lootDelay or 200)
  waitingForContainer = container:getId()

  return true
end

TargetBot.Looting.getLootContainers = function(containers)
  local lootContainers = {}
  local openedContainersById = {}
  local toOpen = nil
  for index, container in pairs(containers) do
    openedContainersById[container:getContainerItem():getId()] = 1
    if containersById[container:getContainerItem():getId()] and not container.lootContainer then
      if container:getItemsCount() < container:getCapacity() or container:hasPages() then
        table.insert(lootContainers, container)
      else -- it's full, open next container if possible
        for slot, item in ipairs(container:getItems()) do
          if item:isContainer() and containersById[item:getId()] then
            toOpen = {item, container}
            break
          end
        end
      end
    end
  end
  if not lootContainers[1] then
    if toOpen then
      g_game.open(toOpen[1], toOpen[2])
      waitTill = now + 500 -- wait 0.5s
      return lootContainers
    end
    -- check containers one more time, maybe there's any loot container
    for index, container in pairs(containers) do
      if not containersById[container:getContainerItem():getId()] and not container.lootContainer then
        for slot, item in ipairs(container:getItems()) do
          if item:isContainer() and containersById[item:getId()] then
            g_game.open(item)
            waitTill = now + 500 -- wait 0.5s
            return lootContainers
          end
        end
      end
    end
    -- can't find any lootContainer, let's check slots, maybe there's one
    for slot = InventorySlotFirst, InventorySlotLast do
      local item = getInventoryItem(slot)
      if item and item:isContainer() and not openedContainersById[item:getId()] then
        -- container which is not opened yet, let's open it
        g_game.open(item)
        waitTill = now + 500 -- wait 0.5s
        return lootContainers
      end
    end
  end
  return lootContainers
end

TargetBot.Looting.lootContainer = function(lootContainers, container)
  -- loot items
  local nextContainer = nil
  for i, item in ipairs(container:getItems()) do
    if item:isContainer() and not itemsById[item:getId()] then
      nextContainer = item
    elseif itemsById[item:getId()] or (ui.everyItem:isOn() and not item:isContainer()) then
      item.lootTries = (item.lootTries or 0) + 1
      if item.lootTries < 5 then -- if can't be looted within 0.5s then skip it
        return TargetBot.Looting.lootItem(lootContainers, item)
      end
    elseif storage.foodItems and storage.foodItems[1] and lastFoodConsumption + 5000 < now then
      for _, food in ipairs(storage.foodItems) do
        if item:getId() == food.id then
          g_game.use(item)
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
        g_game.use(item)
        lastFoodConsumption = now
        return
      end
    end
  end

  -- no more items to loot, open next container
  if nextContainer then
    nextContainer.lootTries = (nextContainer.lootTries or 0) + 1
    if nextContainer.lootTries < 2 then -- max 0.6s to open it
      g_game.open(nextContainer, container)
      waitTill = now + 300 -- give it 0.3s to open
      waitingForContainer = nextContainer:getId()
      return
    end
  end
  
  -- looting finished, remove container from list
  container.lootContainer = false
  g_game.close(container)
  table.remove(TargetBot.Looting.list, storage.extras.lootLast and #TargetBot.Looting.list or 1) 
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
  
  if isStackable then
    local count = item:getCount()
    -- Search for existing stacks to combine with
    for i = 1, #lootContainers do
      local container = lootContainers[i]
      local containerItems = container:getItems()
      for slot = 1, #containerItems do
        local citem = containerItems[slot]
        if citem:getId() == itemId and citem:getCount() < 100 then
          g_game.move(item, container:getSlotPosition(slot - 1), count)
          waitTill = now + 250 -- Reduced from 300ms
          return
        end
      end
    end
  end

  local container = lootContainers[1]
  local moveCount = isStackable and item:getCount() or 1
  g_game.move(item, container:getSlotPosition(container:getItemsCount()), moveCount)
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
  if not TargetBot.isOn() then return end
  if not creature:isMonster() then return end
  
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
    
    local tile = g_map.getTile(mpos)
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
