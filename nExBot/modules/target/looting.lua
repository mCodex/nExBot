--[[
  TargetBot Looting Module
  
  Automatic looting and skinning system.
  Based on vBot 4.8 looting patterns.
  
  Author: nExBot Team
  Version: 1.0.0
]]

-- Looting Panel
local panelName = "looting"
local ui = setupUI([[
Panel
  height: 57

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Auto Loot')

  Button
    id: config
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Config

  BotLabel
    id: statsLabel
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 14
    text-align: left
    font: verdana-11px-rounded
    color: #aaaaaa
    text: Bodies: 0 | Gold: 0

  OptionCheckBox
    id: goldOnly
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 2
    width: 80
    !text: tr('Gold Only')

  OptionCheckBox
    id: skinBodies
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 5
    width: 80
    !text: tr('Skin')

]])
ui:setId(panelName)

-- Storage initialization
if not storage.looting then
  storage.looting = {
    enabled = false,
    lootList = {},
    goldOnly = false,
    skinBodies = false,
    skinningKnife = 5908,
    obsidianKnife = 5908,
    lootDistance = 3,
    stats = {
      bodiesLooted = 0,
      goldCollected = 0,
      itemsCollected = 0
    },
    settings = {
      openBodies = true,
      eatFood = true,
      stackableOnly = false
    }
  }
end

local config = storage.looting

-- Default loot items (gold, platinum, crystal coins, valuable items)
local DEFAULT_LOOT = {
  3031, -- gold coin
  3035, -- platinum coin
  3043, -- crystal coin
  -- Food
  3577, -- meat
  3582, -- ham
  3583, -- dragon ham
  3607, -- mana potion
  -- Commonly looted
  3386, -- dragon scale mail
  3386, -- golden legs
}

-- Rope spots for corpse detection
local ROPE_SPOT_IDS = {384, 418, 8278, 8592}
local SHOVEL_SPOT_IDS = {386, 593, 867, 8276}

-- UI state
ui.title:setOn(config.enabled)
ui.goldOnly:setChecked(config.goldOnly or false)
ui.skinBodies:setChecked(config.skinBodies or false)

ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  storage.looting = config
end

ui.goldOnly.onClick = function(widget)
  config.goldOnly = widget:isChecked()
  storage.looting = config
end

ui.skinBodies.onClick = function(widget)
  config.skinBodies = widget:isChecked()
  storage.looting = config
end

-- Config button
local lootingWindow = nil
local rootWidget = g_ui.getRootWidget()

if rootWidget then
  lootingWindow = UI.createWindow('LootingWindow', rootWidget)
  if lootingWindow then
    lootingWindow:hide()
  end
end

ui.config.onClick = function(widget)
  if lootingWindow then
    lootingWindow:show()
    lootingWindow:raise()
    lootingWindow:focus()
  end
end

-- Loot list management
function addLootItem(itemId)
  config.lootList[itemId] = true
  storage.looting = config
end

function removeLootItem(itemId)
  config.lootList[itemId] = nil
  storage.looting = config
end

function isLootItem(itemId)
  if config.goldOnly then
    -- Only gold coins
    return itemId == 3031 or itemId == 3035 or itemId == 3043
  end
  
  -- Check custom list
  if config.lootList[itemId] then
    return true
  end
  
  -- Check default list
  for _, id in ipairs(DEFAULT_LOOT) do
    if id == itemId then
      return true
    end
  end
  
  return false
end

function clearLootList()
  config.lootList = {}
  storage.looting = config
end

-- Body detection
local function findBodiesInRange()
  local bodies = {}
  local myPos = player:getPosition()
  local range = config.lootDistance or 3
  
  for dx = -range, range do
    for dy = -range, range do
      local pos = {x = myPos.x + dx, y = myPos.y + dy, z = myPos.z}
      local tile = g_map.getTile(pos)
      
      if tile then
        local items = tile:getItems()
        for _, item in ipairs(items) do
          if item:isContainer() then
            -- Check if it's a body (has items inside or is a known corpse)
            local distance = math.sqrt(dx * dx + dy * dy)
            table.insert(bodies, {
              item = item,
              pos = pos,
              distance = distance
            })
          end
        end
      end
    end
  end
  
  -- Sort by distance
  table.sort(bodies, function(a, b)
    return a.distance < b.distance
  end)
  
  return bodies
end

-- Loot from body
local function lootBody(bodyInfo)
  if not bodyInfo or not bodyInfo.item then return 0 end
  
  local itemsLooted = 0
  
  -- Open container
  g_game.open(bodyInfo.item)
  
  -- Wait for container
  schedule(300, function()
    local containers = getContainers()
    
    for _, container in pairs(containers) do
      local items = container:getItems()
      
      for _, item in ipairs(items) do
        local itemId = item:getId()
        
        if isLootItem(itemId) then
          -- Find target container
          local targetContainer = getFirstAvailableContainer()
          
          if targetContainer then
            local count = item:getCount()
            g_game.move(item, targetContainer:getSlotPosition(targetContainer:getItemsCount()), count)
            itemsLooted = itemsLooted + 1
            
            -- Update stats
            if itemId == 3031 then
              config.stats.goldCollected = config.stats.goldCollected + count
            elseif itemId == 3035 then
              config.stats.goldCollected = config.stats.goldCollected + (count * 100)
            elseif itemId == 3043 then
              config.stats.goldCollected = config.stats.goldCollected + (count * 10000)
            else
              config.stats.itemsCollected = config.stats.itemsCollected + 1
            end
            
            storage.looting = config
          end
        end
        
        -- Eat food option
        if config.settings.eatFood and isFood(itemId) then
          g_game.use(item)
        end
      end
    end
    
    if itemsLooted > 0 then
      config.stats.bodiesLooted = config.stats.bodiesLooted + 1
      storage.looting = config
      updateStatsLabel()
    end
  end)
  
  return itemsLooted
end

-- Skin body
local function skinBody(bodyInfo)
  if not bodyInfo or not bodyInfo.item then return false end
  
  local knife = findItem(config.skinningKnife) or findItem(config.obsidianKnife)
  if not knife then return false end
  
  useWith(knife:getId(), bodyInfo.item)
  
  return true
end

-- Get first available container for loot
function getFirstAvailableContainer()
  local containers = getContainers()
  
  for _, container in pairs(containers) do
    if container:getItemsCount() < container:getCapacity() then
      return container
    end
  end
  
  return nil
end

-- Food items
local FOOD_ITEMS = {
  3577, 3578, 3579, 3580, 3581, 3582, 3583, 3584, 3585, 3586, 
  3587, 3588, 3589, 3590, 3591, 3592, 3593, 3594, 3595, 3596,
  3597, 3598, 3599, 3600, 3601, 3602, 3603, 3604, 3605, 3606,
  3607, 3723, 3725, 3726, 3727, 3728, 3729, 3730, 3731
}

function isFood(itemId)
  for _, id in ipairs(FOOD_ITEMS) do
    if id == itemId then
      return true
    end
  end
  return false
end

-- Update stats label
function updateStatsLabel()
  local goldK = config.stats.goldCollected / 1000
  ui.statsLabel:setText(string.format("Bodies: %d | Gold: %.1fk", 
    config.stats.bodiesLooted, goldK))
end

updateStatsLabel()

-- Main looting macro
local lastLootTime = 0
local lootCooldown = 500

macro(200, function()
  if not config.enabled then return end
  if player:isWalking() then return end
  
  -- Check cooldown
  if now - lastLootTime < lootCooldown then return end
  
  -- Find bodies in range
  local bodies = findBodiesInRange()
  
  if #bodies > 0 then
    local body = bodies[1]
    
    -- Loot body
    lootBody(body)
    lastLootTime = now
    
    -- Skin if enabled
    if config.skinBodies then
      schedule(500, function()
        skinBody(body)
      end)
    end
  end
end)

-- Reset stats
function resetLootStats()
  config.stats = {
    bodiesLooted = 0,
    goldCollected = 0,
    itemsCollected = 0
  }
  storage.looting = config
  updateStatsLabel()
end

-- Get stats
function getLootStats()
  return config.stats
end

-- Set loot distance
function setLootDistance(tiles)
  config.lootDistance = math.max(1, math.min(6, tiles))
  storage.looting = config
end

-- Public API
Looting = {
  isOn = function() return config.enabled end,
  setOn = function()
    config.enabled = true
    ui.title:setOn(true)
    storage.looting = config
  end,
  setOff = function()
    config.enabled = false
    ui.title:setOn(false)
    storage.looting = config
  end,
  addItem = addLootItem,
  removeItem = removeLootItem,
  isLootItem = isLootItem,
  clearList = clearLootList,
  setDistance = setLootDistance,
  getStats = getLootStats,
  resetStats = resetLootStats,
  setGoldOnly = function(enabled)
    config.goldOnly = enabled
    ui.goldOnly:setChecked(enabled)
    storage.looting = config
  end,
  setSkin = function(enabled)
    config.skinBodies = enabled
    ui.skinBodies:setChecked(enabled)
    storage.looting = config
  end
}

-- Event listener for creature death
onCreatureDeath(function(creature)
  if config.enabled then
    local pos = creature:getPosition()
    local myPos = player:getPosition()
    
    local distance = math.sqrt(
      math.pow(myPos.x - pos.x, 2) +
      math.pow(myPos.y - pos.y, 2)
    )
    
    if distance <= config.lootDistance then
      -- Schedule loot attempt
      schedule(1000, function()
        if config.enabled then
          local bodies = findBodiesInRange()
          if #bodies > 0 then
            lootBody(bodies[1])
          end
        end
      end)
    end
  end
end)

logInfo("[TargetBot] Looting module loaded")
