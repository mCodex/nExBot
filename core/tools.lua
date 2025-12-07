-- tools tab
setDefaultTab("Tools")

if type(storage.moneyItems) ~= "table" then
  storage.moneyItems = {3031, 3035}
end
macro(1000, "Exchange money", function()
  if not storage.moneyItems[1] then return end
  local containers = g_game.getContainers()
  for index, container in pairs(containers) do
    if not container.lootContainer then -- ignore monster containers
      for i, item in ipairs(container:getItems()) do
        if item:getCount() == 100 then
          for m, moneyId in ipairs(storage.moneyItems) do
            if item:getId() == moneyId.id then
              return g_game.use(item)            
            end
          end
        end
      end
    end
  end
end)

local moneyContainer = UI.Container(function(widget, items)
  storage.moneyItems = items
end, true)
moneyContainer:setHeight(35)
moneyContainer:setItems(storage.moneyItems)

UI.Separator()

macro(60000, "Send message on trade", function()
  local trade = getChannelId("advertising")
  if not trade then
    trade = getChannelId("trade")
  end
  if trade and storage.autoTradeMessage:len() > 0 then    
    sayChannel(trade, storage.autoTradeMessage)
  end
end)
UI.TextEdit(storage.autoTradeMessage or "I'm using OTClientV8!", function(widget, text)    
  storage.autoTradeMessage = text
end)

UI.Separator()

-- Auto Haste Function
-- Detects vocation and uses appropriate haste spell
-- Knights/Paladins: utani hur  
-- Sorcerers/Druids: utani gran hur

-- Vocation IDs:
-- 0 = No vocation, 1 = Knight, 2 = Paladin, 3 = Sorcerer, 4 = Druid
-- 11 = Elite Knight, 12 = Royal Paladin, 13 = Master Sorcerer, 14 = Elder Druid

local HASTE_SPELLS = {
  [1] = { spell = "utani hur", mana = 60 },      -- Knight
  [2] = { spell = "utani hur", mana = 60 },      -- Paladin
  [3] = { spell = "utani gran hur", mana = 100 }, -- Sorcerer
  [4] = { spell = "utani gran hur", mana = 100 }, -- Druid
  [11] = { spell = "utani hur", mana = 60 },     -- Elite Knight
  [12] = { spell = "utani hur", mana = 60 },     -- Royal Paladin
  [13] = { spell = "utani gran hur", mana = 100 }, -- Master Sorcerer
  [14] = { spell = "utani gran hur", mana = 100 }, -- Elder Druid
}

macro(100, "Auto Haste", function()
  -- Get current vocation
  local voc = player:getVocation()
  local hasteData = HASTE_SPELLS[voc]
  
  -- No haste spell for this vocation
  if not hasteData then return end
  
  -- Check if in protection zone
  if isInPz() then return end
  
  -- Check mana requirement (use mana() helper function)
  if mana() < hasteData.mana then return end
  
  -- Check if already hasted (hasHaste is OTClientV8 built-in)
  if hasHaste() then return end
  
  -- Check spell cooldown
  if getSpellCoolDown(hasteData.spell) then return end
  
  -- Check if support spell group is on cooldown
  if modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive and 
     modules.game_cooldown.isGroupCooldownIconActive(2) then 
    return 
  end
  
  -- Cast haste spell
  say(hasteData.spell)
end)

UI.Separator()

-- Low Power Mode / FPS Reducer
-- Reduces FPS to save CPU/GPU power and reduce memory consumption
-- Useful when AFK botting or running multiple clients
-- Uses OTClientV8 APIs: g_app Pane FPS or Options module

-- FPS settings
local normalFps = 60
local lowPowerFps = 5  -- Low but still usable FPS

-- Helper function to set FPS using multiple approaches for compatibility
local function setClientFps(fps)
  local success = false
  
  -- Method 1: Direct g_app API (foreground + background panes)
  if g_app then
    if g_app.setForegroundPaneMaxFps then
      g_app.setForegroundPaneMaxFps(fps)
      success = true
    end
    if g_app.setBackgroundPaneMaxFps then
      g_app.setBackgroundPaneMaxFps(fps)
      success = true
    end
  end
  
  -- Method 2: Through modules.game_bot.g_app
  if modules and modules.game_bot and modules.game_bot.g_app then
    local app = modules.game_bot.g_app
    if app.setForegroundPaneMaxFps then
      app.setForegroundPaneMaxFps(fps)
      success = true
    end
    if app.setBackgroundPaneMaxFps then
      app.setBackgroundPaneMaxFps(fps)
      success = true
    end
  end
  
  -- Method 3: Through Options module (if available)
  if modules and modules.client_options then
    local options = modules.client_options
    if options.setOption then
      pcall(function() options.setOption('foregroundFrameRate', fps) end)
      pcall(function() options.setOption('backgroundFrameRate', fps) end)
      success = true
    end
  end
  
  -- Method 4: Through g_settings
  if g_settings then
    pcall(function() g_settings.set('foregroundFrameRate', fps) end)
    pcall(function() g_settings.set('backgroundFrameRate', fps) end)
  end
  
  return success
end

if not storage.lowPowerMode then
  storage.lowPowerMode = false
end

local lowPowerSwitch = UI.Button("Low Power Mode: OFF", function(widget)
  storage.lowPowerMode = not storage.lowPowerMode
  
  if storage.lowPowerMode then
    widget:setText("Low Power Mode: ON")
    widget:setColor("#00ff00")
    if setClientFps(lowPowerFps) then
      info("Low Power Mode enabled - FPS limited to " .. lowPowerFps)
    else
      warn("Low Power Mode: Could not change FPS settings")
    end
  else
    widget:setText("Low Power Mode: OFF")
    widget:setColor("#ffffff")
    if setClientFps(normalFps) then
      info("Low Power Mode disabled - FPS restored to " .. normalFps)
    else
      warn("Low Power Mode: Could not restore FPS settings")
    end
  end
end)

-- Initialize state on load
if storage.lowPowerMode then
  lowPowerSwitch:setText("Low Power Mode: ON")
  lowPowerSwitch:setColor("#00ff00")
  setClientFps(lowPowerFps)
end

UI.Separator()
