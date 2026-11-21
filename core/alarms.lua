local panelName = "alarms"
if not storage[panelName] then
  storage[panelName] = {}
end

local config = storage[panelName]

local catalog = {
  { id = "ignoreFriends", title = "Ignore Friends", parent = "settings" },
  { id = "flashClient", title = "Flash Client", parent = "settings" },
  { id = "damageTaken", title = "Damage Taken", parent = "alarms" },
  { id = "lowHealth", title = "Low Health", value = 20, parent = "alarms" },
  { id = "lowMana", title = "Low Mana", value = 20, parent = "alarms" },
  { id = "playerAttack", title = "Player Attack", parent = "alarms" },
  { id = "privateMsg", title = "Private Message", parent = "alarms" },
  { id = "defaultMsg", title = "Default Message", parent = "alarms" },
  { id = "customMessage", title = "Custom Message", value = "", parent = "alarms" },
  { id = "creatureDetected", title = "Creature Detected", parent = "alarms" },
  { id = "playerDetected", title = "Player Detected", parent = "alarms" },
  { id = "creatureName", title = "Creature Name", value = "", parent = "alarms" },
}

for _, spec in ipairs(catalog) do
  if type(config[spec.id]) ~= "table" then config[spec.id] = {} end
  config[spec.id].enabled = config[spec.id].enabled == true
  if spec.value ~= nil then config[spec.id].value = spec.value end
end

Alarms = {
  config = config,
  isOn = function() return config.enabled == true end,
  setOn = function() config.enabled = true end,
  setOff = function() config.enabled = false end,
  toggle = function() config.enabled = not config.enabled return config.enabled end,
  show = function() end,
  getAlarms = function()
    local rows = {}
    for _, spec in ipairs(catalog) do
      local entry = config[spec.id]
      rows[#rows + 1] = {
        id = spec.id, title = spec.title, parent = spec.parent,
        enabled = entry and entry.enabled == true or false,
        value = entry and entry.value,
      }
    end
    return rows
  end,
  setAlarm = function(id, key, value)
    config[id] = config[id] or {}
    config[id][key] = value
  end
}

local lastCall = now
local function alarm(file, windowText)
  if now - lastCall < 2000 then return end -- 2s delay
  lastCall = now

  if not g_resources.fileExists(file) then
    file = "/sounds/alarm.ogg"
    lastCall = now + 4000 -- alarm.ogg length is 6s
  end

  
  if modules.game_bot.g_app.getOs() == "windows" and config.flashClient.enabled then
    if g_window.flash then g_window.flash() end
  end
  g_window.setTitle(player:getName() .. " - " .. windowText)
  playSound(file)
end

-- damage taken & custom message
onTextMessage(function(mode, text)
  if not config.enabled then return end
  if mode == 22 and config.damageTaken.enabled then
    return alarm('/sounds/magnum.ogg', "Damage Received!")
  end

  if config.customMessage.enabled then
    local alertText = config.customMessage.value
    if alertText:len() > 0 then
      text = text:lower()
      local parts = string.split(alertText, ",")

      for i=1,#parts do
        local part = parts[i]
        part = part:trim()
        part = part:lower()

        if text:find(part) then
          return alarm('/sounds/magnum.ogg', "Special Message!")
        end
      end
    end
  end
end)

-- default & private message
onTalk(function(name, level, mode, text, channelId, pos)
  if not config.enabled then return end
  if name == player:getName() then return end -- ignore self messages
  if config.ignoreFriends.enabled and isFriend(name) then return end -- ignore friends if enabled

  if mode == 1 and config.defaultMsg.enabled then
    return alarm("/sounds/magnum.ogg", "Default Message!")
  end

  if mode == 4 and config.privateMsg.enabled then
    return alarm("/sounds/Private_Message.ogg", "Private Message!")
  end
end)

-- health & mana alarm handler
local function healthManaAlarmHandler()
  if not config.enabled then return end
  if config.lowHealth.enabled then
    if hppercent() < config.lowHealth.value then
      return alarm("/sounds/Low_Health.ogg", "Low Health!")
    end
  end

  if config.lowMana.enabled then
    if manapercent() < config.lowMana.value then
      return alarm("/sounds/Low_Mana.ogg", "Low Mana!")
    end
  end

  for i, spec in ipairs(SafeCall.global("getSpectators") or {}) do
    if not spec:isLocalPlayer() and not (config.ignoreFriends.enabled and isFriend(spec)) then

      if config.creatureDetected.enabled then
        return alarm("/sounds/magnum.ogg", "Creature Detected!")
      end

      if spec:isPlayer() then 
        if spec:isTimedSquareVisible() and config.playerAttack.enabled then
          return alarm("/sounds/Player_Attack.ogg", "Player Attack!")
        end
        if config.playerDetected.enabled then
          return alarm("/sounds/Player_Detected.ogg", "Player Detected!")
        end
      end

      if config.creatureName.enabled then
        local name = spec:getName():lower()
        local fragments = string.split(config.creatureName.value, ",")
        
        for i=1,#fragments do
          local frag = fragments[i]:trim():lower()

          if name:lower():find(frag) then
            return alarm("/sounds/alarm.ogg", "Special Creature Detected!")
          end
        end
      end
    end
  end
end

-- Use UnifiedTick if available (reduces macro overhead)
if UnifiedTick and UnifiedTick.register then
  UnifiedTick.register("alarms_health_mana", {
    interval = 250,
    priority = UnifiedTick.Priority and UnifiedTick.Priority.HIGH or 75,
    handler = healthManaAlarmHandler,
    group = "alarms"
  })
else
  -- Fallback to traditional macro
  macro(250, healthManaAlarmHandler)
end
