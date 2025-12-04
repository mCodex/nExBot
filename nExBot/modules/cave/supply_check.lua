--[[
  CaveBot Supply Check
  
  Automatic supply verification and refill triggers.
  
  Author: nExBot Team
  Version: 1.0.0
]]

-- Supply check storage
if not storage.supplyCheck then
  storage.supplyCheck = {
    enabled = true,
    supplies = {},
    checkLabel = "refill",
    goLabel = "hunt"
  }
end

local supplyConfig = storage.supplyCheck

-- Supply check UI
local supplyUI = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Supply Check')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

]])
supplyUI:setId("supplyCheck")

-- UI state
supplyUI.title:setOn(supplyConfig.enabled)

supplyUI.title.onClick = function(widget)
  supplyConfig.enabled = not supplyConfig.enabled
  widget:setOn(supplyConfig.enabled)
  storage.supplyCheck = supplyConfig
end

-- Default supplies to track
local defaultSupplies = {
  {id = 3155, name = "Ultimate Healing Rune", min = 50},
  {id = 3180, name = "Magic Wall Rune", min = 20},
  {id = 3161, name = "Sudden Death Rune", min = 100},
  {id = 3031, name = "Gold Coin", min = 1000},
  {id = 238, name = "Great Mana Potion", min = 100},
  {id = 239, name = "Great Health Potion", min = 50}
}

-- Count item in all containers
local function countItem(itemId)
  local count = 0
  local containers = g_game.getContainers()
  
  for _, container in pairs(containers) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId then
        count = count + item:getCount()
      end
    end
  end
  
  return count
end

-- Check if supplies are low
local function checkSupplies()
  if not supplyConfig.enabled then return true end
  
  for _, supply in ipairs(supplyConfig.supplies) do
    local count = countItem(supply.id)
    if count < supply.min then
      return false, supply
    end
  end
  
  return true
end

-- Supply check for CaveBot integration
macro(5000, function()
  if not supplyConfig.enabled then return end
  if not CaveBot or not CaveBot.isOn() then return end
  
  local ok, lowSupply = checkSupplies()
  
  if not ok then
    logInfo(string.format("[Supply Check] Low on %s (%d < %d)", 
      lowSupply.name or "Item " .. lowSupply.id, 
      countItem(lowSupply.id), 
      lowSupply.min))
    
    -- Go to refill label
    if supplyConfig.checkLabel and supplyConfig.checkLabel:len() > 0 then
      CaveBot.gotoLabel(supplyConfig.checkLabel)
    end
  end
end)

-- Supply check public API
CaveBot.SupplyCheck = {
  isEnabled = function()
    return supplyConfig.enabled
  end,
  
  setEnabled = function(enabled)
    supplyConfig.enabled = enabled
    supplyUI.title:setOn(enabled)
    storage.supplyCheck = supplyConfig
  end,
  
  check = function()
    return checkSupplies()
  end,
  
  addSupply = function(itemId, minAmount, name)
    table.insert(supplyConfig.supplies, {
      id = itemId,
      min = minAmount,
      name = name or "Item " .. itemId
    })
    storage.supplyCheck = supplyConfig
  end,
  
  removeSupply = function(itemId)
    for i, supply in ipairs(supplyConfig.supplies) do
      if supply.id == itemId then
        table.remove(supplyConfig.supplies, i)
        storage.supplyCheck = supplyConfig
        return true
      end
    end
    return false
  end,
  
  setLabels = function(checkLabel, goLabel)
    supplyConfig.checkLabel = checkLabel
    supplyConfig.goLabel = goLabel
    storage.supplyCheck = supplyConfig
  end,
  
  getSupplies = function()
    return supplyConfig.supplies
  end,
  
  countItem = countItem
}

-- Initialize with default supplies if empty
if #supplyConfig.supplies == 0 then
  supplyConfig.supplies = defaultSupplies
  storage.supplyCheck = supplyConfig
end
