--[[
  nExBot Extras Module
  Tools panel module for miscellaneous utilities
  
  Features:
  - Anti-idle (prevent logout)
  - Auto screenshots
  - Auto trainer (offline training)
  - Light hack
  - Title changer
  - Hold target
  - Anti-push
  
  Author: nExBot Team
  Version: 1.0.0
]]

setDefaultTab("Tools")

-- Panel setup
local panelName = "extras"
local ui = setupUI([[
Panel
  height: 95

  BotLabel
    id: extrasLabel
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Extra Tools
    color: #ffffff

  OptionCheckBox
    id: antiIdle
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 5
    width: 90
    !text: tr('Anti Idle')

  OptionCheckBox
    id: holdTarget
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 5
    width: 90
    !text: tr('Hold Target')

  OptionCheckBox
    id: antiPush
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    width: 90
    !text: tr('Anti Push')

  OptionCheckBox
    id: lightHack
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 5
    width: 90
    !text: tr('Light Hack')

  OptionCheckBox
    id: expTracker
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    width: 90
    !text: tr('Exp Tracker')

  OptionCheckBox
    id: autoScreenshot
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 5
    width: 90
    !text: tr('Screenshots')

]])
ui:setId(panelName)

-- Storage initialization
if not storage[panelName] then
  storage[panelName] = {
    antiIdle = false,
    holdTarget = false,
    antiPush = false,
    lightHack = false,
    expTracker = false,
    autoScreenshot = false,
    lastActivity = 0,
    heldTarget = nil
  }
end
local config = storage[panelName]

-- UI state initialization
ui.antiIdle:setChecked(config.antiIdle)
ui.holdTarget:setChecked(config.holdTarget)
ui.antiPush:setChecked(config.antiPush)
ui.lightHack:setChecked(config.lightHack)
ui.expTracker:setChecked(config.expTracker)
ui.autoScreenshot:setChecked(config.autoScreenshot)

-- Anti-Idle: Turn character to prevent logout
ui.antiIdle.onClick = function(widget)
  config.antiIdle = widget:isChecked()
  storage[panelName] = config
end

local lastAntiIdle = 0
macro(60000, function()
  if not config.antiIdle then return end
  if now - lastAntiIdle < 60000 then return end
  
  -- Random turn direction
  local directions = {"north", "south", "east", "west"}
  local dir = directions[math.random(1, 4)]
  
  turn(dir)
  lastAntiIdle = now
  
  if nExBot and nExBot.EventBus then
    nExBot.EventBus:emit("extras:antiIdle", dir)
  end
end)

-- Hold Target: Re-attack lost targets
ui.holdTarget.onClick = function(widget)
  config.holdTarget = widget:isChecked()
  storage[panelName] = config
  
  if not config.holdTarget then
    config.heldTarget = nil
  end
end

-- Track current target
onAttackingCreatureChange(function(creature)
  if config.holdTarget and creature then
    config.heldTarget = creature
  end
end)

macro(200, function()
  if not config.holdTarget then return end
  if not config.heldTarget then return end
  
  -- Check if target is valid and not dead
  local target = config.heldTarget
  if target and not target:isDead() then
    local currentTarget = g_game.getAttackingCreature and g_game.getAttackingCreature()
    
    if not currentTarget or currentTarget ~= target then
      -- Check if target is in range
      local myPos = player:getPosition()
      local targetPos = target:getPosition()
      
      if myPos.z == targetPos.z then
        local distance = math.sqrt(
          math.pow(myPos.x - targetPos.x, 2) +
          math.pow(myPos.y - targetPos.y, 2)
        )
        
        if distance <= 8 then
          g_game.attack(target)
        end
      end
    end
  else
    config.heldTarget = nil
  end
end)

-- Anti-Push: Walk back when pushed
ui.antiPush.onClick = function(widget)
  config.antiPush = widget:isChecked()
  storage[panelName] = config
end

local antiPushPosition = nil
local antiPushActive = false

onPlayerPositionChange(function(newPos, oldPos)
  if not config.antiPush then return end
  if player:isWalking() then return end
  
  -- Detect push (position changed without walking)
  if not antiPushActive and antiPushPosition then
    if newPos.x ~= antiPushPosition.x or newPos.y ~= antiPushPosition.y then
      -- Was pushed, try to walk back
      schedule(100, function()
        if not player:isWalking() then
          autoWalk(antiPushPosition, 5, {marginMin = 0, marginMax = 0})
        end
      end)
    end
  end
  
  antiPushPosition = newPos
end)

-- Light Hack: Full light
ui.lightHack.onClick = function(widget)
  config.lightHack = widget:isChecked()
  storage[panelName] = config
  
  if config.lightHack then
    if g_game.setMaxLight then
      g_game.setMaxLight()
    elseif setAmbientLight then
      setAmbientLight(100)
    end
  else
    if g_game.resetLight then
      g_game.resetLight()
    elseif setAmbientLight then
      setAmbientLight(0)
    end
  end
end

-- Apply light hack on login
onGameStart(function()
  if config.lightHack then
    schedule(1000, function()
      if g_game.setMaxLight then
        g_game.setMaxLight()
      elseif setAmbientLight then
        setAmbientLight(100)
      end
    end)
  end
end)

-- Exp Tracker
ui.expTracker.onClick = function(widget)
  config.expTracker = widget:isChecked()
  storage[panelName] = config
end

local expTracking = {
  startExp = 0,
  startTime = 0,
  lastExp = 0
}

onGameStart(function()
  if config.expTracker then
    expTracking.startExp = player:getExperience and player:getExperience() or 0
    expTracking.startTime = now
    expTracking.lastExp = expTracking.startExp
  end
end)

macro(5000, function()
  if not config.expTracker then return end
  
  local currentExp = player:getExperience and player:getExperience() or 0
  
  if currentExp ~= expTracking.lastExp then
    local gained = currentExp - expTracking.startExp
    local elapsed = (now - expTracking.startTime) / 1000 / 3600 -- hours
    local expPerHour = elapsed > 0 and (gained / elapsed) or 0
    
    if nExBot and nExBot.EventBus then
      nExBot.EventBus:emit("extras:expUpdate", {
        gained = gained,
        perHour = expPerHour,
        elapsed = elapsed
      })
    end
    
    expTracking.lastExp = currentExp
  end
end)

-- Auto Screenshots on level up / rare loot
ui.autoScreenshot.onClick = function(widget)
  config.autoScreenshot = widget:isChecked()
  storage[panelName] = config
end

local lastLevel = 0
onGameStart(function()
  if config.autoScreenshot then
    lastLevel = player:getLevel and player:getLevel() or 0
  end
end)

onTextMessage(function(mode, text)
  if not config.autoScreenshot then return end
  
  -- Level up detection
  if text:find("You advanced") then
    schedule(500, function()
      if g_game.takeScreenshot then
        g_game.takeScreenshot()
      end
    end)
  end
  
  -- Rare loot detection
  local rarePatterns = {"rare", "legendary", "boss"}
  for _, pattern in ipairs(rarePatterns) do
    if text:lower():find(pattern) then
      schedule(500, function()
        if g_game.takeScreenshot then
          g_game.takeScreenshot()
        end
      end)
      break
    end
  end
end)

-- Public API
Extras = {
  setAntiIdle = function(enabled)
    config.antiIdle = enabled
    ui.antiIdle:setChecked(enabled)
    storage[panelName] = config
  end,
  
  setHoldTarget = function(enabled)
    config.holdTarget = enabled
    ui.holdTarget:setChecked(enabled)
    storage[panelName] = config
  end,
  
  setAntiPush = function(enabled)
    config.antiPush = enabled
    ui.antiPush:setChecked(enabled)
    storage[panelName] = config
  end,
  
  setLightHack = function(enabled)
    config.lightHack = enabled
    ui.lightHack:setChecked(enabled)
    storage[panelName] = config
    
    if enabled then
      if g_game.setMaxLight then g_game.setMaxLight() end
    else
      if g_game.resetLight then g_game.resetLight() end
    end
  end,
  
  setExpTracker = function(enabled)
    config.expTracker = enabled
    ui.expTracker:setChecked(enabled)
    storage[panelName] = config
    
    if enabled then
      expTracking.startExp = player:getExperience and player:getExperience() or 0
      expTracking.startTime = now
    end
  end,
  
  getExpStats = function()
    if not config.expTracker then return nil end
    
    local currentExp = player:getExperience and player:getExperience() or 0
    local gained = currentExp - expTracking.startExp
    local elapsed = (now - expTracking.startTime) / 1000 / 3600
    
    return {
      gained = gained,
      perHour = elapsed > 0 and (gained / elapsed) or 0,
      elapsed = elapsed
    }
  end,
  
  resetExpTracker = function()
    expTracking.startExp = player:getExperience and player:getExperience() or 0
    expTracking.startTime = now
    expTracking.lastExp = expTracking.startExp
  end,
  
  isAntiIdle = function() return config.antiIdle end,
  isHoldTarget = function() return config.holdTarget end,
  isAntiPush = function() return config.antiPush end,
  isLightHack = function() return config.lightHack end,
  isExpTracker = function() return config.expTracker end
}

logInfo("[Extras] Module loaded")
