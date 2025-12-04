--[[
  ============================================================================
  nExBot Alarms Module
  ============================================================================
  
  Comprehensive alarm system with audio and visual alerts.
  
  FEATURES:
  - Health Below alarm
  - Mana Below alarm
  - Damage Taken alarm
  - Player On Screen alarm
  - Player Attacks alarm
  - Private Message alarm
  - Default Message alarm
  - Creature Detection alarm
  - Item On Floor alarm
  
  Author: nExBot Team
  Version: 2.0.0
  Last Updated: December 2025
  
  ============================================================================
]]

setDefaultTab("Main")

--[[
  ============================================================================
  PANEL SETUP
  ============================================================================
]]

local panelName = "nexbotAlarms"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Alarms')

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

--[[
  ============================================================================
  STORAGE INITIALIZATION
  ============================================================================
]]

if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    -- Health/Mana
    HealthAlarm = { enabled = false, value = 30 },
    ManaAlarm = { enabled = false, value = 20 },
    DamageAlarm = { enabled = false, value = 500 },
    -- Player detection
    PlayerOnScreen = false,
    PlayerAttacks = false,
    -- Messages
    PrivateMessage = false,
    DefaultMessage = false,
    -- Creature/Item detection
    CreatureAlarm = { enabled = false, value = "" },
    ItemAlarm = { enabled = false, value = "" },
    -- Internal state
    lastDamage = 0,
    lastDamageTime = 0,
    alarmCooldown = 5000  -- 5 seconds between alarms
  }
end
local config = storage[panelName]

-- Track last alarm times
local lastAlarmTimes = {}

local function canPlayAlarm(alarmType)
  local lastTime = lastAlarmTimes[alarmType] or 0
  if now - lastTime >= config.alarmCooldown then
    lastAlarmTimes[alarmType] = now
    return true
  end
  return false
end

local function playAlarmSound(alarmType)
  if not canPlayAlarm(alarmType) then return end
  
  local soundFile = "/sounds/alarm.ogg"
  
  if alarmType == "health" then
    soundFile = "/sounds/health_alarm.ogg"
  elseif alarmType == "mana" then
    soundFile = "/sounds/mana_alarm.ogg"
  elseif alarmType == "player" then
    soundFile = "/sounds/player_alarm.ogg"
  elseif alarmType == "damage" then
    soundFile = "/sounds/damage_alarm.ogg"
  elseif alarmType == "creature" then
    soundFile = "/sounds/creature_alarm.ogg"
  elseif alarmType == "item" then
    soundFile = "/sounds/item_alarm.ogg"
  elseif alarmType == "message" then
    soundFile = "/sounds/message_alarm.ogg"
  end
  
  -- Try to play sound, fallback to default
  if playSound then
    local success = pcall(function() playSound(soundFile) end)
    if not success then
      pcall(function() playSound("/sounds/alarm.ogg") end)
    end
  end
end

--[[
  ============================================================================
  UI TOGGLE
  ============================================================================
]]

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  storage[panelName] = config
end

--[[
  ============================================================================
  ALARMS WINDOW
  ============================================================================
]]

local rootWidget = g_ui.getRootWidget()
local alarmsWindow = nil

if rootWidget then
  local success, result = pcall(function()
    return UI.createWindow('AlarmsWindow', rootWidget)
  end)
  
  if success and result then
    alarmsWindow = result
    alarmsWindow:hide()
    
    -- Initialize Health Alarm
    local healthPanel = alarmsWindow:recursiveGetChildById('HealthAlarm')
    if healthPanel then
      local healthEnabled = healthPanel:recursiveGetChildById('enabled')
      local healthValue = healthPanel:recursiveGetChildById('value')
      
      if healthEnabled then
        healthEnabled:setChecked(config.HealthAlarm.enabled)
        healthEnabled.onClick = function(widget)
          config.HealthAlarm.enabled = widget:isChecked()
          storage[panelName] = config
        end
      end
      
      if healthValue then
        healthValue:setValue(config.HealthAlarm.value)
        healthValue.onValueChange = function(widget, value)
          config.HealthAlarm.value = value
          storage[panelName] = config
        end
      end
    end
    
    -- Initialize Mana Alarm
    local manaPanel = alarmsWindow:recursiveGetChildById('ManaAlarm')
    if manaPanel then
      local manaEnabled = manaPanel:recursiveGetChildById('enabled')
      local manaValue = manaPanel:recursiveGetChildById('value')
      
      if manaEnabled then
        manaEnabled:setChecked(config.ManaAlarm.enabled)
        manaEnabled.onClick = function(widget)
          config.ManaAlarm.enabled = widget:isChecked()
          storage[panelName] = config
        end
      end
      
      if manaValue then
        manaValue:setValue(config.ManaAlarm.value)
        manaValue.onValueChange = function(widget, value)
          config.ManaAlarm.value = value
          storage[panelName] = config
        end
      end
    end
    
    -- Initialize Damage Alarm
    local damagePanel = alarmsWindow:recursiveGetChildById('DamageAlarm')
    if damagePanel then
      local damageEnabled = damagePanel:recursiveGetChildById('enabled')
      local damageValue = damagePanel:recursiveGetChildById('value')
      
      if damageEnabled then
        damageEnabled:setChecked(config.DamageAlarm.enabled)
        damageEnabled.onClick = function(widget)
          config.DamageAlarm.enabled = widget:isChecked()
          storage[panelName] = config
        end
      end
      
      if damageValue then
        damageValue:setValue(config.DamageAlarm.value)
        damageValue.onValueChange = function(widget, value)
          config.DamageAlarm.value = value
          storage[panelName] = config
        end
      end
    end
    
    -- Initialize simple checkboxes
    local function initSimpleCheckbox(id, configKey)
      local checkbox = alarmsWindow:recursiveGetChildById(id)
      if checkbox then
        checkbox:setChecked(config[configKey] or false)
        checkbox.onClick = function(widget)
          config[configKey] = widget:isChecked()
          storage[panelName] = config
        end
      end
    end
    
    initSimpleCheckbox('PlayerOnScreen', 'PlayerOnScreen')
    initSimpleCheckbox('PlayerAttacks', 'PlayerAttacks')
    initSimpleCheckbox('PrivateMessage', 'PrivateMessage')
    initSimpleCheckbox('DefaultMessage', 'DefaultMessage')
    
    -- Initialize Creature Alarm
    local creaturePanel = alarmsWindow:recursiveGetChildById('CreatureAlarm')
    if creaturePanel then
      local creatureEnabled = creaturePanel:recursiveGetChildById('enabled')
      local creatureValue = creaturePanel:recursiveGetChildById('value')
      
      if creatureEnabled then
        creatureEnabled:setChecked(config.CreatureAlarm.enabled)
        creatureEnabled.onClick = function(widget)
          config.CreatureAlarm.enabled = widget:isChecked()
          storage[panelName] = config
        end
      end
      
      if creatureValue then
        creatureValue:setText(config.CreatureAlarm.value)
        creatureValue.onTextChange = function(widget, text)
          config.CreatureAlarm.value = text
          storage[panelName] = config
        end
      end
    end
    
    -- Initialize Item Alarm
    local itemPanel = alarmsWindow:recursiveGetChildById('ItemAlarm')
    if itemPanel then
      local itemEnabled = itemPanel:recursiveGetChildById('enabled')
      local itemValue = itemPanel:recursiveGetChildById('value')
      
      if itemEnabled then
        itemEnabled:setChecked(config.ItemAlarm.enabled)
        itemEnabled.onClick = function(widget)
          config.ItemAlarm.enabled = widget:isChecked()
          storage[panelName] = config
        end
      end
      
      if itemValue then
        itemValue:setText(config.ItemAlarm.value)
        itemValue.onTextChange = function(widget, text)
          config.ItemAlarm.value = text
          storage[panelName] = config
        end
      end
    end
    
    -- Test button
    local testBtn = alarmsWindow:recursiveGetChildById('testButton')
    if testBtn then
      testBtn.onClick = function()
        playAlarmSound("test")
        warn("[Alarms] Test alarm played!")
      end
    end
    
    -- Close button
    local closeBtn = alarmsWindow:recursiveGetChildById('closeButton')
    if closeBtn then
      closeBtn.onClick = function()
        alarmsWindow:hide()
      end
    end
    
    alarmsWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        storage[panelName] = config
      end
    end
  end
end

ui.settings.onClick = function(widget)
  if alarmsWindow then
    alarmsWindow:show()
    alarmsWindow:raise()
    alarmsWindow:focus()
  else
    warn("[Alarms] Alarms window not available")
  end
end

--[[
  ============================================================================
  HEALTH/MANA ALARMS
  ============================================================================
]]

macro(500, function()
  if not config.enabled then return end
  
  -- Health alarm
  if config.HealthAlarm.enabled then
    if hppercent() <= config.HealthAlarm.value then
      playAlarmSound("health")
      warn("[Alarms] Low health! " .. hppercent() .. "%")
    end
  end
  
  -- Mana alarm
  if config.ManaAlarm.enabled then
    if manapercent() <= config.ManaAlarm.value then
      playAlarmSound("mana")
      warn("[Alarms] Low mana! " .. manapercent() .. "%")
    end
  end
end)

--[[
  ============================================================================
  DAMAGE ALARM
  ============================================================================
]]

local lastHp = 0

onGameStart(function()
  lastHp = hp()
end)

macro(100, function()
  if not config.enabled then return end
  if not config.DamageAlarm.enabled then return end
  
  local currentHp = hp()
  
  if lastHp > 0 and currentHp < lastHp then
    local damage = lastHp - currentHp
    
    if damage >= config.DamageAlarm.value then
      playAlarmSound("damage")
      warn("[Alarms] Heavy damage taken! " .. damage .. " HP")
      
      if nExBot and nExBot.EventBus then
        nExBot.EventBus:emit("alarms:heavyDamage", damage)
      end
    end
  end
  
  lastHp = currentHp
end)

--[[
  ============================================================================
  PLAYER DETECTION ALARMS
  ============================================================================
]]

local detectedPlayers = {}

macro(500, function()
  if not config.enabled then return end
  if not config.PlayerOnScreen and not config.PlayerAttacks then return end
  
  for _, spec in ipairs(getSpectators()) do
    if spec:isPlayer() and spec ~= player then
      local name = spec:getName()
      
      if config.PlayerOnScreen and not detectedPlayers[name] then
        detectedPlayers[name] = true
        playAlarmSound("player")
        warn("[Alarms] Player on screen: " .. name)
      end
      
      -- Check if player is attacking us
      if config.PlayerAttacks then
        local target = spec:getTarget and spec:getTarget()
        if target and target == player then
          playAlarmSound("player")
          warn("[Alarms] Player attacking you: " .. name)
        end
      end
    end
  end
end)

-- Reset detected players when changing floors
onPlayerPositionChange(function(newPos, oldPos)
  if newPos.z ~= oldPos.z then
    detectedPlayers = {}
  end
end)

--[[
  ============================================================================
  MESSAGE ALARMS
  ============================================================================
]]

onTextMessage(function(mode, text)
  if not config.enabled then return end
  
  if config.PrivateMessage and (mode == MessageModes.PrivateFrom or mode == 6) then
    playAlarmSound("message")
    warn("[Alarms] Private message received!")
  end
  
  if config.DefaultMessage and (mode == MessageModes.Say or mode == 1) then
    playAlarmSound("message")
  end
end)

--[[
  ============================================================================
  CREATURE DETECTION ALARM
  ============================================================================
]]

local detectedCreatures = {}

macro(500, function()
  if not config.enabled then return end
  if not config.CreatureAlarm.enabled then return end
  if config.CreatureAlarm.value == "" then return end
  
  local searchName = config.CreatureAlarm.value:lower()
  
  for _, spec in ipairs(getSpectators()) do
    if not spec:isPlayer() then
      local name = spec:getName():lower()
      
      if name:find(searchName) then
        local key = name .. "_" .. spec:getId()
        
        if not detectedCreatures[key] then
          detectedCreatures[key] = true
          playAlarmSound("creature")
          warn("[Alarms] Creature detected: " .. spec:getName())
        end
      end
    end
  end
end)

--[[
  ============================================================================
  ITEM ON FLOOR ALARM
  ============================================================================
]]

onAddThing(function(tile, thing)
  if not config.enabled then return end
  if not config.ItemAlarm.enabled then return end
  if config.ItemAlarm.value == "" then return end
  if not thing:isItem() then return end
  
  local searchName = config.ItemAlarm.value:lower()
  local itemName = thing:getName and thing:getName():lower() or ""
  
  if itemName:find(searchName) then
    playAlarmSound("item")
    warn("[Alarms] Item detected on floor: " .. (thing:getName and thing:getName() or "Unknown"))
  end
end)

--[[
  ============================================================================
  PUBLIC API
  ============================================================================
]]

Alarms = {
  isOn = function() return config.enabled end,
  isOff = function() return not config.enabled end,
  
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
  
  -- Health alarm
  setHealthAlarm = function(enabled, value)
    config.HealthAlarm.enabled = enabled
    if value then config.HealthAlarm.value = value end
    storage[panelName] = config
  end,
  
  -- Mana alarm
  setManaAlarm = function(enabled, value)
    config.ManaAlarm.enabled = enabled
    if value then config.ManaAlarm.value = value end
    storage[panelName] = config
  end,
  
  -- Damage alarm
  setDamageAlarm = function(enabled, value)
    config.DamageAlarm.enabled = enabled
    if value then config.DamageAlarm.value = value end
    storage[panelName] = config
  end,
  
  -- Player detection
  setPlayerOnScreen = function(enabled)
    config.PlayerOnScreen = enabled
    storage[panelName] = config
  end,
  
  setPlayerAttacks = function(enabled)
    config.PlayerAttacks = enabled
    storage[panelName] = config
  end,
  
  -- Message alarms
  setPrivateMessage = function(enabled)
    config.PrivateMessage = enabled
    storage[panelName] = config
  end,
  
  setDefaultMessage = function(enabled)
    config.DefaultMessage = enabled
    storage[panelName] = config
  end,
  
  -- Creature detection
  setCreatureAlarm = function(enabled, name)
    config.CreatureAlarm.enabled = enabled
    if name then config.CreatureAlarm.value = name end
    storage[panelName] = config
  end,
  
  -- Item detection
  setItemAlarm = function(enabled, name)
    config.ItemAlarm.enabled = enabled
    if name then config.ItemAlarm.value = name end
    storage[panelName] = config
  end,
  
  -- Show window
  show = function()
    if alarmsWindow then
      alarmsWindow:show()
      alarmsWindow:raise()
      alarmsWindow:focus()
    end
  end,
  
  -- Play custom alarm
  playAlarm = function(alarmType)
    playAlarmSound(alarmType or "test")
  end
}

logInfo("[Alarms] Module loaded")
