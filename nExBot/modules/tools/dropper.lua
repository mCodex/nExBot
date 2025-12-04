--[[
  nExBot Dropper Module
  Tools panel module for automatic item dropping
  
  Features:
  - Drop items by ID
  - Drop items by name
  - Drop on death/loot
  - Configurable drop list
  
  Author: nExBot Team
  Version: 1.0.0
]]

setDefaultTab("Tools")

-- Panel setup
local panelName = "dropper"
local ui = setupUI([[
Panel
  height: 38

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Dropper')

  Button
    id: config
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Config

  BotLabel
    id: statusLabel
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 14
    text-align: left
    font: verdana-11px-rounded
    color: #aaaaaa
    text: Items: 0

]])
ui:setId(panelName)

-- Storage initialization
if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    dropList = {},
    dropAfterKill = false,
    dropOnFull = false,
    dropDistance = 1,
    dropDelay = 500
  }
end
local config = storage[panelName]

-- Common trash items
local DEFAULT_DROP_ITEMS = {
  -- Trash items
  3578, -- fish
  3579, -- fish
  2920, -- torch
  2914, -- lamp
  
  -- Empty flasks
  283, -- empty potion flask (small)
  284, -- empty potion flask (medium)
  285, -- empty potion flask (large)
  
  -- Bones
  3115, -- bone
  3116, -- skull
  
  -- Misc trash
  3125, -- remains
  3114, -- skull
}

-- UI state
ui.title:setOn(config.enabled)

ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  storage[panelName] = config
end

-- Config window
local dropperWindow = nil
local rootWidget = g_ui.getRootWidget()

if rootWidget then
  dropperWindow = UI.createWindow('DropperWindow', rootWidget)
  if dropperWindow then
    dropperWindow:hide()
  end
end

ui.config.onClick = function(widget)
  if dropperWindow then
    dropperWindow:show()
    dropperWindow:raise()
    dropperWindow:focus()
    refreshDropList()
  end
end

-- Update item count
local function updateItemCount()
  local count = 0
  for _ in pairs(config.dropList) do
    count = count + 1
  end
  ui.statusLabel:setText(string.format("Items: %d", count))
end

updateItemCount()

-- Add item to drop list
function addDropItem(itemId)
  if type(itemId) ~= "number" then
    itemId = tonumber(itemId)
  end
  if itemId then
    config.dropList[itemId] = true
    storage[panelName] = config
    updateItemCount()
    return true
  end
  return false
end

-- Remove item from drop list
function removeDropItem(itemId)
  if type(itemId) ~= "number" then
    itemId = tonumber(itemId)
  end
  if itemId then
    config.dropList[itemId] = nil
    storage[panelName] = config
    updateItemCount()
    return true
  end
  return false
end

-- Check if item should be dropped
function shouldDrop(itemId)
  return config.dropList[itemId] == true
end

-- Clear drop list
function clearDropList()
  config.dropList = {}
  storage[panelName] = config
  updateItemCount()
end

-- Load default drop items
function loadDefaultItems()
  for _, itemId in ipairs(DEFAULT_DROP_ITEMS) do
    config.dropList[itemId] = true
  end
  storage[panelName] = config
  updateItemCount()
end

-- Find walkable tile for dropping
local function findDropTile()
  local myPos = player:getPosition()
  local range = config.dropDistance or 1
  
  for dx = -range, range do
    for dy = -range, range do
      if dx ~= 0 or dy ~= 0 then
        local pos = {x = myPos.x + dx, y = myPos.y + dy, z = myPos.z}
        local tile = g_map.getTile(pos)
        
        if tile and tile:isWalkable() then
          local itemCount = #tile:getItems()
          if itemCount < 10 then
            return tile, pos
          end
        end
      end
    end
  end
  
  return nil
end

-- Drop single item
local function dropItem(item)
  if not item then return false end
  
  local tile, pos = findDropTile()
  if not tile then return false end
  
  g_game.move(item, pos, item:getCount())
  return true
end

-- Drop all configured items
local function dropAllItems()
  if not config.enabled then return 0 end
  
  local dropped = 0
  local containers = getContainers()
  
  if not containers then return 0 end
  
  for _, container in pairs(containers) do
    local items = container:getItems()
    
    for _, item in ipairs(items) do
      local itemId = item:getId()
      
      if shouldDrop(itemId) then
        if dropItem(item) then
          dropped = dropped + 1
          return dropped -- Drop one item per cycle
        end
      end
    end
  end
  
  return dropped
end

-- Refresh drop list in UI
function refreshDropList()
  if not dropperWindow then return end
  
  local dropList = dropperWindow:recursiveGetChildById('dropList')
  if not dropList then return end
  
  dropList:destroyChildren()
  
  for itemId, _ in pairs(config.dropList) do
    local row = g_ui.createWidget('DropListItem', dropList)
    if row then
      row:setText("Item ID: " .. tostring(itemId))
      row.itemId = itemId
    end
  end
end

-- Main dropper macro
local lastDrop = 0
macro(500, function()
  if not config.enabled then return end
  
  -- Check drop delay
  if now - lastDrop < config.dropDelay then return end
  
  local dropped = dropAllItems()
  
  if dropped > 0 then
    lastDrop = now
    
    -- Emit event
    if nExBot and nExBot.EventBus then
      nExBot.EventBus:emit("dropper:dropped", dropped)
    end
  end
end)

-- Public API
Dropper = {
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
  add = addDropItem,
  remove = removeDropItem,
  clear = clearDropList,
  loadDefaults = loadDefaultItems,
  shouldDrop = shouldDrop,
  dropNow = function()
    local dropped = dropAllItems()
    return dropped
  end,
  setDelay = function(ms)
    config.dropDelay = math.max(100, math.min(5000, ms))
    storage[panelName] = config
  end,
  setDistance = function(tiles)
    config.dropDistance = math.max(1, math.min(3, tiles))
    storage[panelName] = config
  end
}

logInfo("[Dropper] Module loaded")
