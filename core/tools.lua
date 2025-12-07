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

macro(500, "Auto Haste", function()
  -- Get current vocation
  local voc = player:getVocation()
  local hasteData = HASTE_SPELLS[voc]
  
  -- No haste spell for this vocation
  if not hasteData then return end
  
  -- Check if in protection zone
  if isInPz() then return end
  
  -- Check mana requirement
  if player:getMana() < hasteData.mana then return end
  
  -- Check if already hasted using hasHaste() if available, otherwise use speed comparison
  if hasHaste and type(hasHaste) == "function" then
    if hasHaste() then return end
  else
    -- Fallback: compare current speed vs base speed
    -- Haste adds significant speed (~30% or more)
    local baseSpeed = player:getBaseSpeed()
    local currentSpeed = player:getSpeed()
    if baseSpeed and currentSpeed and currentSpeed > baseSpeed * 1.2 then
      return -- Already hasted
    end
  end
  
  -- Check spell cooldown
  if getSpellCoolDown and getSpellCoolDown(hasteData.spell) then return end
  
  -- Check if spell can be cast
  if canCast and not canCast(hasteData.spell) then return end
  
  -- Cast haste spell
  say(hasteData.spell)
end)

UI.Separator()

-- Low Power Mode / FPS Reducer
-- Reduces FPS to 1 to save CPU/GPU power and reduce memory consumption
-- Useful when AFK botting or running multiple clients

local normalFps = 60
local lowPowerFps = 1
local isLowPowerMode = false

macro(1000, "Low Power Mode", function()
  -- This macro just maintains the state
  -- The actual toggle happens in the checkbox callback
end, function(macro)
  -- On enable
  isLowPowerMode = true
  if g_app and g_app.setMaxFps then
    normalFps = g_app.getMaxFps and g_app.getMaxFps() or 60
    g_app.setMaxFps(lowPowerFps)
    logInfo("Low Power Mode enabled - FPS reduced to " .. lowPowerFps)
  end
end, function(macro)
  -- On disable
  isLowPowerMode = false
  if g_app and g_app.setMaxFps then
    g_app.setMaxFps(normalFps)
    logInfo("Low Power Mode disabled - FPS restored to " .. normalFps)
  end
end)

UI.Separator()
