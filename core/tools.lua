-- Tools tab widgets and macros
setDefaultTab("Tools")

-- Money exchanger -----------------------------------------------------------
if type(storage.moneyItems) ~= "table" then
  storage.moneyItems = {
    { id = 3031 }, -- gold coin
    { id = 3035 }  -- platinum coin
  }
end

macro(1000, "Exchange money", function()
  if not storage.moneyItems[1] then return end
  for _, container in pairs(g_game.getContainers()) do
    if not container.lootContainer then
      for _, item in ipairs(container:getItems()) do
        if item:getCount() == 100 then
          for _, moneyId in ipairs(storage.moneyItems) do
            if item:getId() == moneyId.id then
              g_game.use(item)
              return
            end
          end
        end
      end
    end
  end
end)

UI.Container(function(widget, items)
  storage.moneyItems = items
end, true):setHeight(35)

UI.Separator()

-- Auto trade message --------------------------------------------------------
macro(60 * 1000, "Send message on trade", function()
  local trade = getChannelId("advertising") or getChannelId("trade")
  local message = storage.autoTradeMessage or "nExBot is online!"
  if trade and message:len() > 0 then
    sayChannel(trade, message)
  end
end)

UI.TextEdit(storage.autoTradeMessage or "nExBot is online!", function(widget, text)
  storage.autoTradeMessage = text
end)

UI.Separator()

-- Auto haste ---------------------------------------------------------------
local HASTE_SPELLS = {
  [1]  = { spell = "utani hur",      mana = 60  }, -- Knight
  [2]  = { spell = "utani hur",      mana = 60  }, -- Paladin
  [3]  = { spell = "utani gran hur", mana = 100 }, -- Sorcerer
  [4]  = { spell = "utani gran hur", mana = 100 }, -- Druid
  [11] = { spell = "utani hur",      mana = 60  },
  [12] = { spell = "utani hur",      mana = 60  },
  [13] = { spell = "utani gran hur", mana = 100 },
  [14] = { spell = "utani gran hur", mana = 100 },
}

macro(100, "Auto Haste", function()
  if not player then return end
  local vocation = player:getVocation()
  local haste = HASTE_SPELLS[vocation]
  if not haste then return end
  if hasHaste and hasHaste() then return end
  if mana() < haste.mana then return end
  if getSpellCoolDown and getSpellCoolDown(haste.spell) then return end
  say(haste.spell)
end)

UI.Separator()

-- Low power / FPS reducer ---------------------------------------------------
local normalFps = 0   -- 0 = unlimited
local lowPowerFps = 5

local function setClientFps(fps)
  local changed = false
  if g_app then
    if g_app.setForegroundPaneMaxFps then
      g_app.setForegroundPaneMaxFps(fps)
      changed = true
    end
    if g_app.setBackgroundPaneMaxFps then
      g_app.setBackgroundPaneMaxFps(fps)
      changed = true
    end
  end

  if modules and modules.game_bot and modules.game_bot.g_app then
    local app = modules.game_bot.g_app
    if app.setForegroundPaneMaxFps then
      app.setForegroundPaneMaxFps(fps)
      changed = true
    end
    if app.setBackgroundPaneMaxFps then
      app.setBackgroundPaneMaxFps(fps)
      changed = true
    end
  end

  if modules and modules.client_options and modules.client_options.setOption then
    pcall(function() modules.client_options.setOption('foregroundFrameRate', fps) end)
    pcall(function() modules.client_options.setOption('backgroundFrameRate', fps) end)
    changed = true
  end

  if g_settings then
    pcall(function() g_settings.set('foregroundFrameRate', fps) end)
    pcall(function() g_settings.set('backgroundFrameRate', fps) end)
    changed = true
  end

  return changed
end

if storage.lowPowerMode == nil then
  storage.lowPowerMode = false
end

local lowPowerSwitch = UI.Button("Low Power Mode: OFF", function(widget)
  storage.lowPowerMode = not storage.lowPowerMode
  local enabled = storage.lowPowerMode
  widget:setText(enabled and "Low Power Mode: ON" or "Low Power Mode: OFF")
  widget:setColor(enabled and "#00ff00" or "#ffffff")

  if enabled then
    if setClientFps(lowPowerFps) then
      info("Low Power Mode enabled - FPS limited to " .. lowPowerFps)
    else
      warn("Low Power Mode: could not change FPS settings")
    end
  else
    if setClientFps(normalFps) then
      info("Low Power Mode disabled - FPS restored to maximum")
    else
      warn("Low Power Mode: could not restore FPS settings")
    end
  end
end)

if storage.lowPowerMode then
  lowPowerSwitch:setText("Low Power Mode: ON")
  lowPowerSwitch:setColor("#00ff00")
  setClientFps(lowPowerFps)
end

UI.Separator()

-- Mana training -------------------------------------------------------------
if storage.manaTraining == nil then
  storage.manaTraining = {
    enabled = false,
    spell = "exura",
    minManaPercent = 80
  }
end

local function sanitizeSpell(text)
  text = text or ""
  text = text:match("^%s*(.-)%s*$")
  if text == "" then
    return "exura"
  end
  return text
end

local function getManaPercent()
  if not player then return 0 end
  local current = player.getMana and player:getMana() or 0
  local maximum = player.getMaxMana and player:getMaxMana() or 0
  if maximum <= 0 then return 0 end
  return (current / maximum) * 100
end

UI.Label("Mana Training:")

UI.Label("Spell to cast (default: exura):")
UI.TextEdit(storage.manaTraining.spell or "exura", function(widget, text)
  storage.manaTraining.spell = sanitizeSpell(text)
end)

UI.Label("Min mana % to train (10-100):")
UI.TextEdit(tostring(storage.manaTraining.minManaPercent or 80), function(widget, text)
  local value = tonumber(text)
  if not value then return end
  if value < 10 then value = 10 end
  if value > 100 then value = 100 end
  storage.manaTraining.minManaPercent = value
end)

local manaTrainSwitch = UI.Button("Mana Training: OFF", function()
  storage.manaTraining.enabled = not storage.manaTraining.enabled
  manaTrainSwitch:setText(storage.manaTraining.enabled and "Mana Training: ON" or "Mana Training: OFF")
  manaTrainSwitch:setColor(storage.manaTraining.enabled and "#00ff00" or "#ffffff")
  info(storage.manaTraining.enabled and "Mana Training enabled" or "Mana Training disabled")
end)

if storage.manaTraining.enabled then
  manaTrainSwitch:setText("Mana Training: ON")
  manaTrainSwitch:setColor("#00ff00")
end

local lastTrainCast = 0
local TRAIN_COOLDOWN = 1000

macro(500, function()
  if not storage.manaTraining.enabled then return end
  if not player then return end
  if (now - lastTrainCast) < TRAIN_COOLDOWN then return end

  local manaPercent = getManaPercent()
  if manaPercent < (storage.manaTraining.minManaPercent or 80) then return end

  local spell = sanitizeSpell(storage.manaTraining.spell)
  if not spell or spell == "" then return end

  say(spell)
  lastTrainCast = now
end)

UI.Separator()
