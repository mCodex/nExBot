--[[
  nExBot Smart Mount Module
  Tools panel module with event-driven architecture
  
  Features:
  - PZ (Protection Zone) awareness
  - PZ Lock detection - waits until lock drops
  - Combat detection
  - Auto-dismount in PZ option
  
  Author: nExBot Team
  Version: 1.0.0
]]

setDefaultTab("Tools")

-- Panel setup
local panelName = "smartMount"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Smart Mount')

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

-- Settings window
local rootWidget = g_ui.getRootWidget()
local settingsWindow = rootWidget and UI.createWindow('SmartMountWindow', rootWidget) or nil
if not settingsWindow then
  g_ui.loadUIFromString([[
SmartMountWindow < MainWindow
  size: 280 280
  padding: 20
  !text: tr('Smart Mount Settings')
  @onEscape: self:hide()

  Label
    id: infoLabel
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Configure mount settings
    margin-bottom: 10

  CheckBox
    id: pzAware
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 15
    text: Only mount outside Protection Zone

  CheckBox
    id: waitPzLock
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    text: Wait for PZ Lock to drop

  CheckBox
    id: autoDismount
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    text: Auto dismount when entering PZ

  CheckBox
    id: safeMode
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    text: Don't mount during combat

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 15
    text: Combat Cooldown (ms):
    width: 130

  SpinBox
    id: combatCooldown
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 5
    width: 80
    minimum: 0
    maximum: 10000
    step: 500

  Label
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 10
    text: Min HP% to mount:
    width: 130

  SpinBox
    id: minHp
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 5
    width: 80
    minimum: 0
    maximum: 100
    step: 5

  Button
    id: closeButton
    !text: tr('Close')
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    width: 60
    height: 20
  ]])
  settingsWindow = UI.createWindow('SmartMountWindow', rootWidget)
end
settingsWindow:hide()

-- Default config
if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    pzAware = true,
    waitPzLock = true,
    autoDismount = false,
    safeMode = true,
    combatCooldown = 3000,
    minHp = 50
  }
end
local config = storage[panelName]

-- State
local lastDamageTime = 0
local lastMountAttempt = 0
local lastPosition = nil
local standingStartTime = 0
local subscriptions = {}

-- Track damage for combat detection
onTextMessage(function(mode, text)
  if not config.enabled then return end
  if text:lower():find("you lose") and text:lower():find("due to") then
    lastDamageTime = now
  end
end)

-- Track position changes
onPlayerPositionChange(function(newPos, oldPos)
  lastPosition = newPos
  standingStartTime = now
end)

-- Helper: Check if standing still
local function isStandingStill()
  local currentPos = pos()
  if lastPosition then
    if currentPos.x == lastPosition.x and 
       currentPos.y == lastPosition.y and 
       currentPos.z == lastPosition.z then
      return now - standingStartTime >= 500
    else
      lastPosition = currentPos
      standingStartTime = now
      return false
    end
  else
    lastPosition = currentPos
    standingStartTime = now
    return false
  end
end

-- Helper: Check if in combat recently
local function isInCombat()
  return now - lastDamageTime < config.combatCooldown
end

-- Helper: Check if player is mounted
local function isPlayerMounted()
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return false end
  return localPlayer:isMounted()
end

-- Main mount logic
local function checkMount()
  if not config.enabled then return end
  
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end
  
  local mounted = isPlayerMounted()
  local inPz = isInPz()
  local pzLock = hasPzLock()
  
  -- Auto-dismount in PZ
  if config.autoDismount and inPz and mounted then
    localPlayer:dismount()
    
    if nExBot and nExBot.EventBus then
      nExBot.EventBus:emit("mount:dismounted", "entered_pz")
    end
    return
  end
  
  -- Already mounted
  if mounted then return end
  
  -- HP check
  if hppercent() < config.minHp then return end
  
  -- PZ checks
  if config.pzAware and inPz then return end
  if config.waitPzLock and pzLock then return end
  
  -- Combat check
  if config.safeMode and isInCombat() then return end
  
  -- Standing check
  if not isStandingStill() then return end
  
  -- Rate limiting
  if now - lastMountAttempt < 1000 then return end
  
  -- Mount!
  localPlayer:mount()
  lastMountAttempt = now
  
  if nExBot and nExBot.EventBus then
    nExBot.EventBus:emit("mount:mounted")
  end
end

-- Main macro
local mountMacro = macro(500, function()
  checkMount()
end)
mountMacro.setOn(config.enabled)

-- UI Setup
ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  mountMacro.setOn(config.enabled)
  
  if nExBot and nExBot.EventBus then
    if config.enabled then
      nExBot.EventBus:emit("module:enabled", panelName)
    else
      nExBot.EventBus:emit("module:disabled", panelName)
    end
  end
end

ui.settings.onClick = function()
  settingsWindow:show()
  settingsWindow:raise()
  settingsWindow:focus()
end

-- Settings window setup
if settingsWindow.pzAware then
  settingsWindow.pzAware:setChecked(config.pzAware)
  settingsWindow.pzAware.onCheckChange = function(widget, checked)
    config.pzAware = checked
  end
end

if settingsWindow.waitPzLock then
  settingsWindow.waitPzLock:setChecked(config.waitPzLock)
  settingsWindow.waitPzLock.onCheckChange = function(widget, checked)
    config.waitPzLock = checked
  end
end

if settingsWindow.autoDismount then
  settingsWindow.autoDismount:setChecked(config.autoDismount)
  settingsWindow.autoDismount.onCheckChange = function(widget, checked)
    config.autoDismount = checked
  end
end

if settingsWindow.safeMode then
  settingsWindow.safeMode:setChecked(config.safeMode)
  settingsWindow.safeMode.onCheckChange = function(widget, checked)
    config.safeMode = checked
  end
end

if settingsWindow.combatCooldown then
  settingsWindow.combatCooldown:setValue(config.combatCooldown)
  settingsWindow.combatCooldown.onValueChange = function(widget, value)
    config.combatCooldown = value
  end
end

if settingsWindow.minHp then
  settingsWindow.minHp:setValue(config.minHp)
  settingsWindow.minHp.onValueChange = function(widget, value)
    config.minHp = value
  end
end

if settingsWindow.closeButton then
  settingsWindow.closeButton.onClick = function()
    settingsWindow:hide()
  end
end

-- Event subscriptions for reactive behavior
if nExBot and nExBot.EventBus then
  -- React to health changes
  subscriptions.health = nExBot.EventBus:subscribe(
    "player:health_changed",
    function(newHp, oldHp)
      if config.enabled and newHp < oldHp then
        lastDamageTime = now
      end
    end,
    5
  )
  
  -- React to PZ state changes
  subscriptions.pz = nExBot.EventBus:subscribe(
    "player:pz_changed",
    function(inPz)
      if config.enabled and config.autoDismount and inPz then
        local localPlayer = g_game.getLocalPlayer()
        if localPlayer and localPlayer:isMounted() then
          localPlayer:dismount()
        end
      end
    end,
    10
  )
end

-- Public API
SmartMount = {
  toggle = function()
    config.enabled = not config.enabled
    ui.title:setOn(config.enabled)
    mountMacro.setOn(config.enabled)
  end,
  
  setOn = function()
    config.enabled = true
    ui.title:setOn(true)
    mountMacro.setOn(true)
  end,
  
  setOff = function()
    config.enabled = false
    ui.title:setOn(false)
    mountMacro.setOn(false)
  end,
  
  isOn = function()
    return config.enabled
  end,
  
  show = function()
    settingsWindow:show()
    settingsWindow:raise()
    settingsWindow:focus()
  end,
  
  -- Force mount/dismount commands
  forceMount = function()
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer and not localPlayer:isMounted() then
      localPlayer:mount()
    end
  end,
  
  forceDismount = function()
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer and localPlayer:isMounted() then
      localPlayer:dismount()
    end
  end,
  
  -- Status check
  getStatus = function()
    return {
      enabled = config.enabled,
      mounted = isPlayerMounted(),
      inPz = isInPz(),
      hasPzLock = hasPzLock(),
      inCombat = isInCombat(),
      standingStill = isStandingStill()
    }
  end
}

return SmartMount
