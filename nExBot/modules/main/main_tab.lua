--[[
  ============================================================================
  nExBot Simplified Main Tab UI
  ============================================================================
  
  Consolidated UI for the Main tab with reduced button count.
  Groups related features together for improved UX.
  
  LAYOUT:
  ─────────────────────────────────────────────────────────────────────────────
  [ComboBot On/Off] [Config]
  [Friend Healer On/Off] [Config]  
  [Team Settings] (grouped config for party features)
  
  Author: nExBot Team
  Version: 2.0.0
  Last Updated: December 2025
  
  ============================================================================
]]

setDefaultTab("Main")

--[[
  ============================================================================
  COMBO BOT PANEL (SIMPLIFIED)
  ============================================================================
]]

local comboPanelName = "combobot"
local comboUI = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('ComboBot')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Config

]])
comboUI:setId(comboPanelName)

-- ComboBot storage init
if not storage[comboPanelName] then
  storage[comboPanelName] = {
    enabled = false,
    onSayEnabled = false,
    followLeaderEnabled = false,
    sayLeader = "",
    sayPhrase = "",
    attackSpell = "",
    followName = "",
    minMana = 0,
    comboDelay = 100
  }
end

local comboConfig = storage[comboPanelName]

comboUI.title:setOn(comboConfig.enabled)

comboUI.title.onClick = function(widget)
  comboConfig.enabled = not comboConfig.enabled
  widget:setOn(comboConfig.enabled)
  storage[comboPanelName] = comboConfig
end

-- ComboBot Settings Window
local rootWidget = g_ui.getRootWidget()
local comboWindow = nil

if rootWidget then
  local success, result = pcall(function()
    return UI.createWindow('ComboBotWindow', rootWidget)
  end)
  if success and result then
    comboWindow = result
    comboWindow:hide()
    
    comboWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        storage[comboPanelName] = comboConfig
      end
    end
    
    if comboWindow.closeButton then
      comboWindow.closeButton.onClick = function()
        comboWindow:hide()
      end
    end
  end
end

comboUI.settings.onClick = function(widget)
  if comboWindow then
    comboWindow:show()
    comboWindow:raise()
    comboWindow:focus()
  else
    warn("[Main Tab] ComboBot window not available")
  end
end

--[[
  ============================================================================
  FRIEND HEALER PANEL (SIMPLIFIED)
  ============================================================================
]]

local friendHealerPanelName = "friendhealer"
local friendUI = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Friend Healer')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Config

]])
friendUI:setId(friendHealerPanelName)

-- Friend Healer storage init
if not storage[friendHealerPanelName] then
  storage[friendHealerPanelName] = {
    enabled = false,
    partyMembers = true,
    guildMembers = false,
    knights = true,
    paladins = true,
    druids = true,
    sorcerers = true,
    healRange = 7,
    minHpToHeal = 60,
    masResCount = 3,
    customPlayers = ""
  }
end

local friendConfig = storage[friendHealerPanelName]

friendUI.title:setOn(friendConfig.enabled)

friendUI.title.onClick = function(widget)
  friendConfig.enabled = not friendConfig.enabled
  widget:setOn(friendConfig.enabled)
  storage[friendHealerPanelName] = friendConfig
end

-- Friend Healer Settings Window
local friendWindow = nil

if rootWidget then
  local success, result = pcall(function()
    return UI.createWindow('FriendHealerWindow', rootWidget)
  end)
  if success and result then
    friendWindow = result
    friendWindow:hide()
    
    friendWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        storage[friendHealerPanelName] = friendConfig
      end
    end
    
    if friendWindow.closeButton then
      friendWindow.closeButton.onClick = function()
        friendWindow:hide()
      end
    end
  end
end

friendUI.settings.onClick = function(widget)
  if friendWindow then
    friendWindow:show()
    friendWindow:raise()
    friendWindow:focus()
  else
    warn("[Main Tab] FriendHealer window not available")
  end
end

--[[
  ============================================================================
  PUSHMAX PANEL (PVP FEATURE - SIMPLIFIED)
  ============================================================================
]]

local pushPanelName = "pushmax"
local pushUI = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('PushMax')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Config

]])
pushUI:setId(pushPanelName)

-- PushMax storage init
if not storage[pushPanelName] then
  storage[pushPanelName] = {
    enabled = false,
    autoMode = false,
    pushDelay = 1000,
    runeId = 3180,
    targetPlayer = "",
    minDistance = 2,
    maxDistance = 4,
    hotkey = ""
  }
end

local pushConfig = storage[pushPanelName]

pushUI.title:setOn(pushConfig.enabled)

pushUI.title.onClick = function(widget)
  pushConfig.enabled = not pushConfig.enabled
  widget:setOn(pushConfig.enabled)
  storage[pushPanelName] = pushConfig
end

-- PushMax Settings Window
local pushWindow = nil

if rootWidget then
  local success, result = pcall(function()
    return UI.createWindow('PushMaxWindow', rootWidget)
  end)
  if success and result then
    pushWindow = result
    pushWindow:hide()
    
    pushWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        storage[pushPanelName] = pushConfig
      end
    end
    
    if pushWindow.closeButton then
      pushWindow.closeButton.onClick = function()
        pushWindow:hide()
      end
    end
  end
end

pushUI.settings.onClick = function(widget)
  if pushWindow then
    pushWindow:show()
    pushWindow:raise()
    pushWindow:focus()
  else
    warn("[Main Tab] PushMax window not available")
  end
end

--[[
  ============================================================================
  SEPARATOR AND INFO
  ============================================================================
]]

UI.Separator()
UI.Label("nExBot v2.0.0 - Main Tab")

--[[
  ============================================================================
  PUBLIC APIs
  ============================================================================
]]

-- ComboBot API
ComboBot = {
  isOn = function() return comboConfig.enabled end,
  isOff = function() return not comboConfig.enabled end,
  setOn = function()
    comboConfig.enabled = true
    comboUI.title:setOn(true)
    storage[comboPanelName] = comboConfig
  end,
  setOff = function()
    comboConfig.enabled = false
    comboUI.title:setOn(false)
    storage[comboPanelName] = comboConfig
  end,
  getLeader = function() return comboConfig.followName end,
  setLeader = function(name)
    comboConfig.followName = name
    storage[comboPanelName] = comboConfig
  end
}

-- FriendHealer API
FriendHealer = {
  isOn = function() return friendConfig.enabled end,
  isOff = function() return not friendConfig.enabled end,
  setOn = function()
    friendConfig.enabled = true
    friendUI.title:setOn(true)
    storage[friendHealerPanelName] = friendConfig
  end,
  setOff = function()
    friendConfig.enabled = false
    friendUI.title:setOn(false)
    storage[friendHealerPanelName] = friendConfig
  end
}

-- PushMax API
PushMax = {
  isOn = function() return pushConfig.enabled end,
  isOff = function() return not pushConfig.enabled end,
  setOn = function()
    pushConfig.enabled = true
    pushUI.title:setOn(true)
    storage[pushPanelName] = pushConfig
  end,
  setOff = function()
    pushConfig.enabled = false
    pushUI.title:setOn(false)
    storage[pushPanelName] = pushConfig
  end
}

logInfo("[Main Tab] Simplified UI loaded")
