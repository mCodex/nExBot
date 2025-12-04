--[[
  ComboBot Module
  
  Team combo coordination for synchronized attacks.
  Based on classic OTClient bot combo patterns.
  
  Author: nExBot Team
  Version: 1.0.0
]]

setDefaultTab("Main")

local panelName = "combobot"
local ui = setupUI([[
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
    id: combos
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

]])
ui:setId(panelName)

-- Initialize storage
if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    onSayEnabled = false,
    onShootEnabled = false,
    onCastEnabled = false,
    followLeaderEnabled = false,
    attackLeaderTargetEnabled = false,
    attackSpellEnabled = false,
    attackItemToggle = false,
    sayLeader = "",
    shootLeader = "",
    castLeader = "",
    sayPhrase = "",
    spell = "",
    shootId = 0,
    castSpell = "",
    attackSpell = "",
    attackItem = 0,
    followName = "",
    minMana = 0,
    minHealth = 0,
    comboDelay = 100
  }
end

local config = storage[panelName]

-- Combo state
local comboState = {
  lastTrigger = 0,
  triggerCooldown = 500,
  pendingActions = {}
}

-- UI state
ui.title:setOn(config.enabled)

ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  storage[panelName] = config
end

-- Create settings window
local rootWidget = g_ui.getRootWidget()
local comboWindow = nil

if rootWidget then
  comboWindow = UI.createWindow('ComboBotWindow', rootWidget)
  if comboWindow then
    comboWindow:hide()
    
    comboWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        storage[panelName] = config
      end
    end
    
    -- Setup window controls
    schedule(100, function()
      if not comboWindow then return end
      
      -- On Say trigger
      if comboWindow.onSayEnabled then
        comboWindow.onSayEnabled:setOn(config.onSayEnabled)
        comboWindow.onSayEnabled.onClick = function(w)
          config.onSayEnabled = not config.onSayEnabled
          w:setOn(config.onSayEnabled)
        end
      end
      
      if comboWindow.sayLeader then
        comboWindow.sayLeader:setText(config.sayLeader)
        comboWindow.sayLeader.onTextChange = function(w, text)
          config.sayLeader = text
        end
      end
      
      if comboWindow.sayPhrase then
        comboWindow.sayPhrase:setText(config.sayPhrase)
        comboWindow.sayPhrase.onTextChange = function(w, text)
          config.sayPhrase = text
        end
      end
      
      -- Attack spell
      if comboWindow.attackSpell then
        comboWindow.attackSpell:setText(config.attackSpell)
        comboWindow.attackSpell.onTextChange = function(w, text)
          config.attackSpell = text
        end
      end
      
      -- Min mana
      if comboWindow.minMana then
        comboWindow.minMana:setValue(config.minMana)
        comboWindow.minMana.onValueChange = function(w, value)
          config.minMana = value
        end
      end
      
      -- Follow leader
      if comboWindow.followLeaderEnabled then
        comboWindow.followLeaderEnabled:setOn(config.followLeaderEnabled)
        comboWindow.followLeaderEnabled.onClick = function(w)
          config.followLeaderEnabled = not config.followLeaderEnabled
          w:setOn(config.followLeaderEnabled)
        end
      end
      
      if comboWindow.followName then
        comboWindow.followName:setText(config.followName)
        comboWindow.followName.onTextChange = function(w, text)
          config.followName = text
        end
      end
      
      -- Close button
      if comboWindow.closeButton then
        comboWindow.closeButton.onClick = function()
          comboWindow:hide()
        end
      end
    end)
  end
end

ui.combos.onClick = function(widget)
  if comboWindow then
    comboWindow:show()
    comboWindow:raise()
    comboWindow:focus()
  end
end

-- Execute combo action
local function executeCombo(triggerType, triggerData)
  if not config.enabled then return end
  if now - comboState.lastTrigger < comboState.triggerCooldown then return end
  
  -- Check mana requirement
  if mana() < config.minMana then return end
  
  -- Check health requirement
  if hp() < config.minHealth then return end
  
  comboState.lastTrigger = now
  
  -- Delay before executing
  schedule(config.comboDelay, function()
    -- Attack spell
    if config.attackSpellEnabled and config.attackSpell:len() > 0 then
      if canCast(config.attackSpell) then
        say(config.attackSpell)
      end
    end
    
    -- Attack item (rune)
    if config.attackItemToggle and config.attackItem > 0 then
      local target = g_game.getAttackingCreature()
      if target then
        useWith(config.attackItem, target)
      end
    end
  end)
end

-- Listen for say triggers
onTalk(function(name, level, mode, text, channelId, pos)
  if not config.enabled then return end
  if not config.onSayEnabled then return end
  
  -- Check if it's the leader
  if name:lower() == config.sayLeader:lower() then
    -- Check if phrase matches
    if config.sayPhrase:len() > 0 and text:lower():find(config.sayPhrase:lower()) then
      executeCombo("say", {speaker = name, text = text})
    end
  end
end)

-- Listen for missile/shoot triggers
onMissle(function(missile)
  if not config.enabled then return end
  if not config.onShootEnabled then return end
  
  -- Check source
  local source = missile:getSource()
  if source then
    -- Match leader position logic here
    executeCombo("shoot", {missile = missile})
  end
end)

-- Follow leader macro
macro(200, function()
  if not config.enabled then return end
  if not config.followLeaderEnabled then return end
  if config.followName:len() == 0 then return end
  
  -- Find leader
  for _, creature in ipairs(getSpectators()) do
    if creature:isPlayer() and creature:getName():lower() == config.followName:lower() then
      local leaderPos = creature:getPosition()
      local myPos = player:getPosition()
      
      -- Only follow if not too close
      if getDistanceBetween(myPos, leaderPos) > 1 then
        autoWalk(leaderPos, 100, {marginMin = 1, marginMax = 1})
      end
      break
    end
  end
end)

-- Attack leader's target macro
macro(100, function()
  if not config.enabled then return end
  if not config.attackLeaderTargetEnabled then return end
  if config.followName:len() == 0 then return end
  
  -- Find leader
  for _, creature in ipairs(getSpectators()) do
    if creature:isPlayer() and creature:getName():lower() == config.followName:lower() then
      -- Try to get leader's target (limited by API)
      -- This is a simplified approach
      break
    end
  end
end)

-- Public API
ComboBot = {
  isOn = function()
    return config.enabled
  end,
  
  isOff = function()
    return not config.enabled
  end,
  
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
  
  trigger = function(customData)
    executeCombo("manual", customData or {})
  end,
  
  getLeader = function()
    return config.followName
  end,
  
  setLeader = function(name)
    config.followName = name
    storage[panelName] = config
  end
}
