--[[
  nExBot Containers Module
  Tools panel module for container management
  
  Features:
  - Rename containers
  - Auto-open containers
  - Container stacking
  - Container organization
  
  Author: nExBot Team
  Version: 1.0.0
]]

setDefaultTab("Tools")

-- Panel setup
local panelName = "containers"
local ui = setupUI([[
Panel
  height: 38

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Containers')

  Button
    id: config
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Config

  BotLabel
    id: countLabel
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 14
    text-align: left
    font: verdana-11px-rounded
    color: #aaaaaa
    text: Open: 0

]])
ui:setId(panelName)

-- Storage initialization
if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    autoOpen = true,
    renameList = {},
    stackGold = true,
    sortItems = false,
    closeFull = false
  }
end
local config = storage[panelName]

-- Container names mapping
local containerNames = {
  [2853] = "Backpack",
  [2854] = "Bag",
  [2855] = "Basket",
  [2856] = "Beach Backpack",
  [2857] = "Blue Bag",
  [2858] = "Blue Backpack",
  [2859] = "Buggy Backpack",
  [2860] = "Camouflage Backpack",
  [2861] = "Crown Backpack",
  [2862] = "Demon Backpack",
  [2863] = "Dragon Backpack",
  [2864] = "Expedition Backpack",
  [2865] = "Fur Backpack",
  [2866] = "Golden Backpack",
  [2867] = "Green Backpack",
  [2868] = "Grey Backpack",
  [2869] = "Heart Backpack",
  [2870] = "Jungle Backpack",
  [2871] = "Minotaur Backpack",
  [2872] = "Orange Backpack",
  [2873] = "Pannier Backpack",
  [2874] = "Pirate Backpack",
  [2875] = "Purple Backpack",
  [2876] = "Red Backpack",
  [2877] = "Santa Backpack",
  [3960] = "Brocade Backpack",
  [5949] = "Jewelled Backpack",
  [9774] = "Stamped Parcel",
  [21411] = "Loot Backpack"
}

-- Custom rename list
local renameList = config.renameList or {}

-- UI state
ui.title:setOn(config.enabled)

ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  storage[panelName] = config
end

-- Config window
local containersWindow = nil
local rootWidget = g_ui.getRootWidget()

if rootWidget then
  containersWindow = UI.createWindow('ContainersWindow', rootWidget)
  if containersWindow then
    containersWindow:hide()
  end
end

ui.config.onClick = function(widget)
  if containersWindow then
    containersWindow:show()
    containersWindow:raise()
    containersWindow:focus()
    refreshContainerList()
  end
end

-- Update open container count
local function updateContainerCount()
  local containers = getContainers()
  local count = 0
  if containers then
    for _ in pairs(containers) do
      count = count + 1
    end
  end
  ui.countLabel:setText(string.format("Open: %d", count))
end

-- Get custom name for container
local function getCustomName(containerId, index)
  local key = tostring(containerId) .. "_" .. tostring(index)
  return renameList[key]
end

-- Set custom name for container
local function setCustomName(containerId, index, name)
  local key = tostring(containerId) .. "_" .. tostring(index)
  renameList[key] = name
  config.renameList = renameList
  storage[panelName] = config
end

-- Rename container
function renameContainer(container, newName)
  if not container then return false end
  
  local containerId = container:getContainerItem():getId()
  local index = container:getContainerItem():getContainerIndex()
  
  setCustomName(containerId, index or 0, newName)
  
  return true
end

-- Get container list for UI
function refreshContainerList()
  if not containersWindow then return end
  
  local containerList = containersWindow:recursiveGetChildById('containerList')
  if not containerList then return end
  
  containerList:destroyChildren()
  
  local containers = getContainers()
  if not containers then return end
  
  for _, container in pairs(containers) do
    local item = container:getContainerItem()
    local itemId = item:getId()
    local name = containerNames[itemId] or "Container"
    
    -- Check for custom name
    local customName = getCustomName(itemId, item:getContainerIndex())
    if customName then
      name = customName
    end
    
    local row = g_ui.createWidget('ContainerListItem', containerList)
    if row then
      row:setText(name .. " (" .. container:getItemsCount() .. "/" .. container:getCapacity() .. ")")
      row.container = container
    end
  end
end

-- Auto-open containers
local function autoOpenContainers()
  if not config.enabled or not config.autoOpen then return end
  
  local containers = getContainers()
  if not containers then return end
  
  for _, container in pairs(containers) do
    local items = container:getItems()
    
    for _, item in ipairs(items) do
      if item:isContainer() then
        -- Check if already open
        local alreadyOpen = false
        for _, openContainer in pairs(containers) do
          if openContainer:getContainerItem() == item then
            alreadyOpen = true
            break
          end
        end
        
        if not alreadyOpen then
          g_game.open(item)
          return -- Open one at a time
        end
      end
    end
  end
end

-- Stack gold coins
local function stackGold()
  if not config.enabled or not config.stackGold then return end
  
  local containers = getContainers()
  if not containers then return end
  
  local goldCoins = {}
  local platCoins = {}
  local crystalCoins = {}
  
  for _, container in pairs(containers) do
    local items = container:getItems()
    
    for _, item in ipairs(items) do
      local itemId = item:getId()
      local count = item:getCount()
      
      if itemId == 3031 and count < 100 then
        table.insert(goldCoins, {item = item, container = container, count = count})
      elseif itemId == 3035 and count < 100 then
        table.insert(platCoins, {item = item, container = container, count = count})
      elseif itemId == 3043 and count < 100 then
        table.insert(crystalCoins, {item = item, container = container, count = count})
      end
    end
  end
  
  -- Stack coins
  local function stackCoins(coins)
    if #coins < 2 then return false end
    
    for i = 2, #coins do
      local source = coins[i]
      local target = coins[1]
      
      if source.count + target.count <= 100 then
        g_game.move(source.item, target.container:getSlotPosition(0), source.count)
        return true
      end
    end
    return false
  end
  
  if stackCoins(goldCoins) then return end
  if stackCoins(platCoins) then return end
  stackCoins(crystalCoins)
end

-- Close full containers
local function closeFullContainers()
  if not config.enabled or not config.closeFull then return end
  
  local containers = getContainers()
  if not containers then return end
  
  for _, container in pairs(containers) do
    if container:getItemsCount() >= container:getCapacity() then
      g_game.close(container)
      return
    end
  end
end

-- Main container macro
macro(1000, function()
  if not config.enabled then return end
  
  updateContainerCount()
  autoOpenContainers()
  stackGold()
  closeFullContainers()
end)

-- Public API
Containers = {
  isOn = function() return config.enabled end,
  setOn = function()
    config.enabled = true
    ui.title:setOn(true)
    storage[panelName] = config
  end,
  setOff = function()
    config.enabled = false
    ui.title:setOn(false)
    storage[panelName] = config
  end,
  rename = renameContainer,
  refresh = refreshContainerList,
  setAutoOpen = function(enabled)
    config.autoOpen = enabled
    storage[panelName] = config
  end,
  setStackGold = function(enabled)
    config.stackGold = enabled
    storage[panelName] = config
  end,
  getOpen = function()
    local containers = getContainers()
    local count = 0
    if containers then
      for _ in pairs(containers) do
        count = count + 1
      end
    end
    return count
  end
}

updateContainerCount()

logInfo("[Containers] Module loaded")
