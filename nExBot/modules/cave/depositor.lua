--[[
  CaveBot Depositor
  
  Automatic depot/stash depositing.
  
  Author: nExBot Team
  Version: 1.0.0
]]

-- Depositor storage
if not storage.depositor then
  storage.depositor = {
    enabled = false,
    depositItems = {},
    depositGold = true,
    ignoreItems = {},
    openStash = true,
    minCap = 50
  }
end

local depositorConfig = storage.depositor

-- Depositor UI
local depositorUI = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Depositor')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

]])
depositorUI:setId("depositor")

-- UI state
depositorUI.title:setOn(depositorConfig.enabled)

depositorUI.title.onClick = function(widget)
  depositorConfig.enabled = not depositorConfig.enabled
  widget:setOn(depositorConfig.enabled)
  storage.depositor = depositorConfig
end

-- Depot container IDs
local depotContainers = {
  depot = {3499, 3500, 3501, 3502, 3503}, -- Depot chests
  stash = {24435, 24436} -- Stash
}

-- Check if item should be deposited
local function shouldDeposit(item)
  local itemId = item:getId()
  
  -- Check ignore list
  for _, id in ipairs(depositorConfig.ignoreItems) do
    if itemId == id then
      return false
    end
  end
  
  -- Check deposit list (empty = deposit all)
  if #depositorConfig.depositItems == 0 then
    return true
  end
  
  for _, id in ipairs(depositorConfig.depositItems) do
    if itemId == id then
      return true
    end
  end
  
  return false
end

-- Find depot container
local function findDepotContainer()
  local containers = g_game.getContainers()
  
  for _, container in pairs(containers) do
    local name = container:getName():lower()
    if name:find("depot") or name:find("locker") then
      return container
    end
  end
  
  return nil
end

-- Find stash container
local function findStashContainer()
  local containers = g_game.getContainers()
  
  for _, container in pairs(containers) do
    local name = container:getName():lower()
    if name:find("stash") then
      return container
    end
  end
  
  return nil
end

-- Deposit items to depot
local function depositToDepot()
  local depot = findDepotContainer()
  if not depot then return false end
  
  local containers = g_game.getContainers()
  local deposited = false
  
  for _, container in pairs(containers) do
    if container ~= depot then
      for _, item in ipairs(container:getItems()) do
        if shouldDeposit(item) then
          local pos = depot:getSlotPosition(depot:getItemsCount())
          g_game.move(item, pos, item:getCount())
          deposited = true
          return true -- One item at a time
        end
      end
    end
  end
  
  return deposited
end

-- Deposit gold
local function depositGold()
  if not depositorConfig.depositGold then return false end
  
  local depot = findDepotContainer()
  if not depot then return false end
  
  local goldIds = {3031, 3035, 3043} -- Gold, platinum, crystal coins
  local containers = g_game.getContainers()
  
  for _, container in pairs(containers) do
    if container ~= depot then
      for _, item in ipairs(container:getItems()) do
        for _, goldId in ipairs(goldIds) do
          if item:getId() == goldId then
            local pos = depot:getSlotPosition(depot:getItemsCount())
            g_game.move(item, pos, item:getCount())
            return true
          end
        end
      end
    end
  end
  
  return false
end

-- Depositor public API
CaveBot.Depositor = {
  isEnabled = function()
    return depositorConfig.enabled
  end,
  
  setEnabled = function(enabled)
    depositorConfig.enabled = enabled
    depositorUI.title:setOn(enabled)
    storage.depositor = depositorConfig
  end,
  
  deposit = function()
    -- First deposit gold if enabled
    if depositGold() then
      return true
    end
    
    -- Then deposit items
    return depositToDepot()
  end,
  
  isFinished = function()
    -- Check if there's anything left to deposit
    local containers = g_game.getContainers()
    
    for _, container in pairs(containers) do
      local name = container:getName():lower()
      if not name:find("depot") and not name:find("locker") and not name:find("stash") then
        for _, item in ipairs(container:getItems()) do
          if shouldDeposit(item) then
            return false
          end
        end
      end
    end
    
    return true
  end,
  
  addDepositItem = function(itemId)
    table.insert(depositorConfig.depositItems, itemId)
    storage.depositor = depositorConfig
  end,
  
  addIgnoreItem = function(itemId)
    table.insert(depositorConfig.ignoreItems, itemId)
    storage.depositor = depositorConfig
  end,
  
  clearDepositItems = function()
    depositorConfig.depositItems = {}
    storage.depositor = depositorConfig
  end,
  
  clearIgnoreItems = function()
    depositorConfig.ignoreItems = {}
    storage.depositor = depositorConfig
  end
}
