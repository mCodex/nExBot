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
UI.TextEdit(storage.autoTradeMessage or "nExBot has arrived!", function(widget, text)    
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
local normalFps = 0    -- 0 = unlimited/maximum FPS
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
      info("Low Power Mode disabled - FPS restored to maximum")
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

-- Mana Training Macro
-- Trains magic level by casting a spell when mana is sufficient
-- Configurable spell, minimum mana %, and interval

-- Available training spells
local TRAINING_SPELLS = {
  { name = "Light", spell = "utevo lux", mana = 20 },
  { name = "Magic Rope", spell = "exani tera", mana = 20 },
  { name = "Find Person", spell = "exiva", mana = 20 },
  { name = "Light Healing", spell = "exura", mana = 20 },
  { name = "Intense Healing", spell = "exura gran", mana = 70 },
  { name = "Food", spell = "exevo pan", mana = 120 },
  { name = "Invisible", spell = "utana vid", mana = 440 },
  { name = "Strong Haste", spell = "utani gran hur", mana = 100 },
  { name = "Haste", spell = "utani hur", mana = 60 },
  { name = "Magic Shield", spell = "utamo vita", mana = 50 },
  { name = "Cancel Magic Shield", spell = "exana vita", mana = 50 },
  { name = "Custom", spell = "", mana = 0 },
}

-- Initialize storage
if storage.manaTraining == nil then
  storage.manaTraining = {
    enabled = false,
    spellIndex = 1,
    minManaPercent = 80,
    customSpell = ""
  }
end

-- Ensure spellIndex is valid
if storage.manaTraining.spellIndex < 1 or storage.manaTraining.spellIndex > #TRAINING_SPELLS then
  storage.manaTraining.spellIndex = 1
end

-- Get current spell display text
local function getCurrentSpellText()
  local idx = storage.manaTraining.spellIndex or 1
  local spell = TRAINING_SPELLS[idx]
  if spell.name == "Custom" then
    local custom = storage.manaTraining.customSpell or ""
    if custom == "" then
      return "Spell: Custom (not set)"
    else
      return "Spell: " .. custom
    end
  else
    return "Spell: " .. spell.name .. " (" .. spell.mana .. "mp)"
  end
end

-- Mana training state
local manaTrainingEnabled = storage.manaTraining.enabled or false
local lastTrainCast = 0
local TRAIN_COOLDOWN = 1000  -- 1 second between casts

-- UI Label
UI.Label("Mana Training:")

-- Spell selector button (cycles through spells on click)
local spellButton = UI.Button(getCurrentSpellText(), function(widget)
  -- Cycle to next spell
  storage.manaTraining.spellIndex = storage.manaTraining.spellIndex + 1
  if storage.manaTraining.spellIndex > #TRAINING_SPELLS then
    storage.manaTraining.spellIndex = 1
  end
  widget:setText(getCurrentSpellText())
end)

-- Custom spell input
UI.Label("Custom spell:")
UI.TextEdit(storage.manaTraining.customSpell or "", function(widget, text)
  storage.manaTraining.customSpell = text
  -- Update spell button if custom is selected
  if TRAINING_SPELLS[storage.manaTraining.spellIndex].name == "Custom" then
    spellButton:setText(getCurrentSpellText())
  end
end)

-- Min mana % input (using TextEdit since UI.Scroll doesn't exist)
UI.Label("Min mana % to train (10-100):")
UI.TextEdit(tostring(storage.manaTraining.minManaPercent or 80), function(widget, text)
  local value = tonumber(text)
  if value then
    -- Clamp between 10 and 100
    if value < 10 then value = 10 end
    if value > 100 then value = 100 end
    storage.manaTraining.minManaPercent = value
  end
end)

-- Toggle button
local manaTrainSwitch = UI.Button("Mana Training: OFF", function(widget)
  manaTrainingEnabled = not manaTrainingEnabled
  storage.manaTraining.enabled = manaTrainingEnabled
  
  if manaTrainingEnabled then
    widget:setText("Mana Training: ON")
    widget:setColor("#00ff00")
    info("Mana Training enabled")
  else
    widget:setText("Mana Training: OFF")
    widget:setColor("#ffffff")
    info("Mana Training disabled")
  end
end)

-- Initialize state on load
if storage.manaTraining.enabled then
  manaTrainSwitch:setText("Mana Training: ON")
  manaTrainSwitch:setColor("#00ff00")
  manaTrainingEnabled = true
end

-- Mana training macro
macro(500, function()
  if not manaTrainingEnabled then return end
  if not player then return end
  if (now - lastTrainCast) < TRAIN_COOLDOWN then return end
  
  -- Check mana percentage
  local manaPercent = (mana() / maxMana()) * 100
  local minMana = storage.manaTraining.minManaPercent or 80
  
  if manaPercent < minMana then return end
  
  -- Get the spell to cast
  local spellIndex = storage.manaTraining.spellIndex or 1
  local spellData = TRAINING_SPELLS[spellIndex]
  local spellToCast = nil
  
  if spellData.name == "Custom" then
    spellToCast = storage.manaTraining.customSpell
  else
    spellToCast = spellData.spell
  end
  
  if not spellToCast or spellToCast == "" then return end
  
  -- Cast the spell
  say(spellToCast)
  lastTrainCast = now
end)

UI.Separator()
