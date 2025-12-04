--[[
  nExBot Smart Fishing Module
  Tools panel module with event-driven architecture
  
  Features:
  - Random tile selection to avoid filling same spot
  - Tile capacity checking
  - Automatic trash fish disposal
  - Smart walking to different tiles
  
  Author: nExBot Team
  Version: 1.0.0
]]

setDefaultTab("Tools")

-- Panel setup
local panelName = "smartFishing"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Smart Fishing')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])
ui:setId(panelName)

-- Settings window
local settingsWindow = UI.createWindow('SmartFishingWindow', rootWidget)
if not settingsWindow then
  g_ui.loadUIFromString([[
SmartFishingWindow < MainWindow
  size: 280 260
  padding: 20
  !text: tr('Smart Fishing Settings')
  @onEscape: self:hide()

  Label
    id: infoLabel
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Configure fishing settings
    margin-bottom: 10

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 10
    text: Fishing Rod ID:
    width: 100

  BotItem
    id: rodItem
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 5

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 10
    text: Max Tile Items:
    width: 100

  SpinBox
    id: maxTileItems
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 5
    width: 60
    minimum: 1
    maximum: 10

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 10
    text: Search Radius:
    width: 100

  SpinBox
    id: searchRadius
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 5
    width: 60
    minimum: 1
    maximum: 10

  CheckBox
    id: randomTile
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 15
    text: Random Tile Selection

  CheckBox
    id: autoWalk
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 5
    text: Auto Walk to Water

  CheckBox
    id: dropTrash
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 5
    text: Auto Drop Trash Fish

  Button
    id: closeButton
    !text: tr('Close')
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    width: 60
    height: 20
  ]])
  settingsWindow = UI.createWindow('SmartFishingWindow', rootWidget)
end
settingsWindow:hide()

-- Default config
if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    rodId = 3483,
    maxTileItems = 8,
    searchRadius = 7,
    randomTile = true,
    autoWalk = true,
    dropTrash = true
  }
end
local config = storage[panelName]

-- Water IDs
local waterIds = {
  4597, 4598, 4599, 4600, 4601, 4602,
  4609, 4610, 4611, 4612, 4613, 4614, 4615, 4616,
  4617, 4618, 4619, 4620, 4621, 4622, 4623, 4624, 4625, 4626,
  7236, 618, 619, 620, 664, 665, 666
}

-- Trash fish IDs
local trashFish = {3578, 3579}

-- State
local recentTiles = {}
local lastFishTime = 0
local subscriptions = {}

-- Helper functions
local function posKey(p)
  return string.format("%d_%d_%d", p.x, p.y, p.z)
end

local function tileHasCapacity(tile)
  return tile and #tile:getItems() < config.maxTileItems
end

local function wasRecentlyUsed(p)
  local key = posKey(p)
  for _, k in ipairs(recentTiles) do
    if k == key then return true end
  end
  return false
end

local function markTileUsed(p)
  table.insert(recentTiles, posKey(p))
  while #recentTiles > 5 do
    table.remove(recentTiles, 1)
  end
end

local function findWaterTiles()
  local tiles = {}
  local playerPos = pos()
  
  for _, tile in ipairs(g_map.getTiles(posz())) do
    local tilePos = tile:getPosition()
    local dist = getDistanceBetween(playerPos, tilePos)
    
    if dist <= config.searchRadius then
      for _, item in ipairs(tile:getItems()) do
        if table.contains(waterIds, item:getId()) then
          table.insert(tiles, {
            pos = tilePos,
            item = item,
            dist = dist,
            capacity = tileHasCapacity(tile),
            recent = wasRecentlyUsed(tilePos)
          })
          break
        end
      end
    end
  end
  
  return tiles
end

local function selectBestTile(tiles)
  if #tiles == 0 then return nil end
  
  -- Prefer tiles with capacity that weren't recently used
  local best = {}
  for _, t in ipairs(tiles) do
    if t.capacity and not t.recent then
      table.insert(best, t)
    end
  end
  
  if #best == 0 then
    for _, t in ipairs(tiles) do
      if t.capacity then table.insert(best, t) end
    end
  end
  
  if #best == 0 then best = tiles end
  
  -- Random or closest selection
  if config.randomTile and #best > 1 then
    return best[math.random(1, #best)]
  else
    table.sort(best, function(a, b) return a.dist < b.dist end)
    return best[1]
  end
end

local function dropTrashFish()
  if not config.dropTrash then return false end
  
  for _, id in ipairs(trashFish) do
    local item = findItem(id)
    if item then
      local nearTiles = getNearTiles(pos())
      for _, tile in ipairs(nearTiles) do
        if tile:isWalkable() and tileHasCapacity(tile) then
          g_game.move(item, tile:getPosition(), item:getCount())
          return true
        end
      end
    end
  end
  return false
end

local function doFishing()
  if not config.enabled then return end
  if now - lastFishTime < 1000 then return end
  
  local rod = findItem(config.rodId)
  if not rod then return end
  
  dropTrashFish()
  
  local tiles = findWaterTiles()
  local selected = selectBestTile(tiles)
  
  if not selected then
    if config.autoWalk then
      -- Try to find a position near water
      for _, t in ipairs(tiles) do
        local nearTiles = getNearTiles(t.pos)
        for _, tile in ipairs(nearTiles) do
          if tile:isWalkable() and not tile:hasCreature() then
            if findPath(pos(), tile:getPosition(), 5, {ignoreNonPathable = true}) then
              autoWalk(tile:getPosition(), 5, {ignoreNonPathable = true})
              return
            end
          end
        end
      end
    end
    return
  end
  
  if selected.dist > 1 then
    if config.autoWalk then
      local nearTiles = getNearTiles(selected.pos)
      for _, tile in ipairs(nearTiles) do
        if tile:isWalkable() and not tile:hasCreature() then
          if findPath(pos(), tile:getPosition(), 5, {ignoreNonPathable = true}) then
            autoWalk(tile:getPosition(), 5, {ignoreNonPathable = true})
            return
          end
        end
      end
    end
    return
  end
  
  usewith(config.rodId, selected.item)
  markTileUsed(selected.pos)
  lastFishTime = now
  
  -- Emit event
  if nExBot and nExBot.EventBus then
    nExBot.EventBus:emit("fishing:cast", selected.pos)
  end
end

-- Main macro with event-driven pattern
local fishingMacro = macro(500, function()
  doFishing()
end)
fishingMacro.setOn(config.enabled)

-- UI Setup
ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  fishingMacro.setOn(config.enabled)
  
  if nExBot and nExBot.EventBus then
    if config.enabled then
      nExBot.EventBus:emit("module:enabled", panelName)
    else
      nExBot.EventBus:emit("module:disabled", panelName)
    end
  end
end

ui.settings.onClick = function()
  settingsWindow:show()
  settingsWindow:raise()
  settingsWindow:focus()
end

-- Settings window setup
if settingsWindow.rodItem then
  settingsWindow.rodItem:setItemId(config.rodId)
  settingsWindow.rodItem.onItemChange = function(widget)
    config.rodId = widget:getItemId()
  end
end

if settingsWindow.maxTileItems then
  settingsWindow.maxTileItems:setValue(config.maxTileItems)
  settingsWindow.maxTileItems.onValueChange = function(widget, value)
    config.maxTileItems = value
  end
end

if settingsWindow.searchRadius then
  settingsWindow.searchRadius:setValue(config.searchRadius)
  settingsWindow.searchRadius.onValueChange = function(widget, value)
    config.searchRadius = value
  end
end

if settingsWindow.randomTile then
  settingsWindow.randomTile:setChecked(config.randomTile)
  settingsWindow.randomTile.onCheckChange = function(widget, checked)
    config.randomTile = checked
  end
end

if settingsWindow.autoWalk then
  settingsWindow.autoWalk:setChecked(config.autoWalk)
  settingsWindow.autoWalk.onCheckChange = function(widget, checked)
    config.autoWalk = checked
  end
end

if settingsWindow.dropTrash then
  settingsWindow.dropTrash:setChecked(config.dropTrash)
  settingsWindow.dropTrash.onCheckChange = function(widget, checked)
    config.dropTrash = checked
  end
end

if settingsWindow.closeButton then
  settingsWindow.closeButton.onClick = function()
    settingsWindow:hide()
  end
end

-- Event subscriptions for reactive behavior
if nExBot and nExBot.EventBus then
  -- Subscribe to position changes for smarter fishing
  subscriptions.position = nExBot.EventBus:subscribe(
    "player:position_changed",
    function(newPos, oldPos)
      -- Reset recent tiles when moving to new area
      if newPos.z ~= oldPos.z then
        recentTiles = {}
      end
    end,
    5
  )
end

-- Public API
SmartFishing = {
  toggle = function()
    config.enabled = not config.enabled
    ui.title:setOn(config.enabled)
    fishingMacro.setOn(config.enabled)
  end,
  
  setOn = function()
    config.enabled = true
    ui.title:setOn(true)
    fishingMacro.setOn(true)
  end,
  
  setOff = function()
    config.enabled = false
    ui.title:setOn(false)
    fishingMacro.setOn(false)
  end,
  
  isOn = function()
    return config.enabled
  end,
  
  show = function()
    settingsWindow:show()
    settingsWindow:raise()
    settingsWindow:focus()
  end
}

return SmartFishing
