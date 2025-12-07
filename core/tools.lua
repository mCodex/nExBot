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
if storage.autoTradeMessage == nil then
  storage.autoTradeMessage = "nExBot is online!"
end

macro(60 * 1000, "Send message on trade", function()
  local trade = getChannelId("advertising") or getChannelId("trade")
  local message = storage.autoTradeMessage or ""
  if trade and message:len() > 0 then
    sayChannel(trade, message)
  end
end)

local tradeMessageEdit = UI.TextEdit(storage.autoTradeMessage, function(widget, text)
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

-- Auto Mount ----------------------------------------------------------------
-- Automatically mounts player when outside of PZ
-- Uses the player's default mount from client settings
-- Does NOT attempt to mount in PZ (saves CPU/memory)

local lastMountAttempt = 0
local MOUNT_COOLDOWN = 2000 -- Don't spam mount attempts

macro(500, "Auto Mount", function()
  if not player then return end
  
  -- Skip if in protection zone - saves CPU/memory
  if isInPz() then return end
  
  -- Cooldown to prevent spamming
  if (now - lastMountAttempt) < MOUNT_COOLDOWN then return end
  
  -- Check if already mounted
  local outfit = player:getOutfit()
  if outfit and outfit.mount and outfit.mount > 0 then
    return -- Already mounted
  end
  
  -- Mount using default mount from client
  if g_game.mount then
    g_game.mount(true)
    lastMountAttempt = now
  end
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

-- Low Power Mode macro with built-in toggle (like Hold Target)
local lowPowerMacro = macro(1000, "Low Power Mode", function()
  -- This runs when enabled - apply low FPS
  setClientFps(lowPowerFps)
end)

-- Handle state changes
lowPowerMacro.onSwitch = function(macro, enabled)
  if enabled then
    if setClientFps(lowPowerFps) then
      info("Low Power Mode enabled - FPS limited to " .. lowPowerFps)
    end
  else
    if setClientFps(normalFps) then
      info("Low Power Mode disabled - FPS restored to maximum")
    end
  end
end

UI.Separator()

-- Mana training -------------------------------------------------------------
if storage.manaTraining == nil then
  storage.manaTraining = {
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

-- Mana Training macro with built-in toggle (like Hold Target)
local lastTrainCast = 0
local TRAIN_COOLDOWN = 1000

macro(500, "Mana Training", function()
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

-- Global Configuration Settings ---------------------------------------------
UI.Label("== Global Settings ==")
UI.Separator()

-- Auto Open Doors toggle
if storage.globalConfig == nil then
  storage.globalConfig = {
    autoOpenDoors = true,
    autoUseTools = true,
    targetOnlyTargetable = false
  }
end

local doorToggle = UI.Button("Auto Open Doors: " .. (storage.globalConfig.autoOpenDoors and "ON" or "OFF"), function(widget)
  storage.globalConfig.autoOpenDoors = not storage.globalConfig.autoOpenDoors
  local enabled = storage.globalConfig.autoOpenDoors
  widget:setText("Auto Open Doors: " .. (enabled and "ON" or "OFF"))
  widget:setColor(enabled and "#00ff00" or "#ffffff")
  if GlobalConfig then
    GlobalConfig.setEnabled("autoOpenDoors", enabled)
  end
  info("Auto Open Doors: " .. (enabled and "enabled" or "disabled"))
end)

if storage.globalConfig.autoOpenDoors then
  doorToggle:setColor("#00ff00")
end

-- Auto Use Tools toggle (rope, shovel, machete)
local toolsToggle = UI.Button("Auto Use Tools: " .. (storage.globalConfig.autoUseTools and "ON" or "OFF"), function(widget)
  storage.globalConfig.autoUseTools = not storage.globalConfig.autoUseTools
  local enabled = storage.globalConfig.autoUseTools
  widget:setText("Auto Use Tools: " .. (enabled and "ON" or "OFF"))
  widget:setColor(enabled and "#00ff00" or "#ffffff")
  if GlobalConfig then
    GlobalConfig.setEnabled("autoUseTools", enabled)
  end
  info("Auto Use Tools: " .. (enabled and "enabled" or "disabled"))
end)

if storage.globalConfig.autoUseTools then
  toolsToggle:setColor("#00ff00")
end

-- Target Only Targetable Monsters toggle
local targetableToggle = UI.Button("Target Only Targetable: " .. (storage.globalConfig.targetOnlyTargetable and "ON" or "OFF"), function(widget)
  storage.globalConfig.targetOnlyTargetable = not storage.globalConfig.targetOnlyTargetable
  local enabled = storage.globalConfig.targetOnlyTargetable
  widget:setText("Target Only Targetable: " .. (enabled and "ON" or "OFF"))
  widget:setColor(enabled and "#00ff00" or "#ffffff")
  if GlobalConfig then
    GlobalConfig.setEnabled("targetOnlyTargetable", enabled)
  end
  info("Target Only Targetable Monsters: " .. (enabled and "enabled" or "disabled"))
end)

if storage.globalConfig.targetOnlyTargetable then
  targetableToggle:setColor("#00ff00")
end

UI.Label("Tip: Target Only Targetable ignores")
UI.Label("other players' summons")

UI.Separator()

-- Tool Item IDs Configuration
UI.Label("Tool Item IDs (from items.xml):")

UI.Label("Rope ID (default: 3003):")
UI.TextEdit(tostring(storage.globalConfig.ropeId or 3003), function(widget, text)
  local id = tonumber(text)
  if id and id > 0 then
    storage.globalConfig.ropeId = id
    if GlobalConfig then GlobalConfig.setTool("rope", id) end
  end
end)

UI.Label("Shovel ID (default: 3457):")
UI.TextEdit(tostring(storage.globalConfig.shovelId or 3457), function(widget, text)
  local id = tonumber(text)
  if id and id > 0 then
    storage.globalConfig.shovelId = id
    if GlobalConfig then GlobalConfig.setTool("shovel", id) end
  end
end)

UI.Label("Machete ID (default: 3308):")
UI.TextEdit(tostring(storage.globalConfig.macheteId or 3308), function(widget, text)
  local id = tonumber(text)
  if id and id > 0 then
    storage.globalConfig.macheteId = id
    if GlobalConfig then GlobalConfig.setTool("machete", id) end
  end
end)
