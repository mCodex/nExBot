--[[
  Friend Healer Module
  
  Automated healing for party members and friends.
  Based on vBot 4.8 new_healer patterns.
  
  Author: nExBot Team
  Version: 1.0.0
]]

setDefaultTab("Main")

local panelName = "friendHealer"
local ui = setupUI([[
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
    id: edit
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
      
]])
ui:setId(panelName)

-- Initialize storage
if not storage[panelName] or not storage[panelName].priorities then
  storage[panelName] = {
    enabled = false,
    customPlayers = {},
    vocations = {},
    groups = {},
    priorities = {
      {name = "Custom Spell", enabled = false, custom = true},
      {name = "exura sio", enabled = true, minHp = 60, minMana = 70, range = 9},
      {name = "exura gran sio", enabled = false, minHp = 40, minMana = 170, range = 9},
      {name = "exura max sio", enabled = false, minHp = 25, minMana = 300, range = 9}
    },
    settings = {
      {type = "HealScroll", text = "Heal Range: ", value = 9},
      {type = "HealScroll", text = "Heal Item ID: ", value = 3160},
      {type = "HealScroll", text = "Item Heal Range: ", value = 5},
      {type = "HealScroll", text = "Mas Res Amount: ", value = 3},
      {type = "HealScroll", text = "Min Player HP%: ", value = 80},
      {type = "HealScroll", text = "Min Player MP%: ", value = 50}
    },
    conditions = {
      knights = true,
      paladins = true,
      druids = false,
      sorcerers = false,
      party = true,
      guild = false,
      botserver = false,
      friends = false
    }
  }
end

local config = storage[panelName]

-- Healer state
local healerState = {
  lastHeal = 0,
  healCooldown = 1000,
  priorityTarget = nil
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
local healerWindow = nil

if rootWidget then
  healerWindow = UI.createWindow('FriendHealerWindow', rootWidget)
  if healerWindow then
    healerWindow:hide()
    healerWindow:setId(panelName)
    
    healerWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        storage[panelName] = config
      end
    end
  end
end

ui.edit.onClick = function()
  if healerWindow then
    healerWindow:show()
    healerWindow:raise()
    healerWindow:focus()
  end
end

-- Check if creature should be healed
local function shouldHeal(creature)
  if not creature:isPlayer() then return false end
  if creature == player then return false end
  
  local name = creature:getName()
  local pos = creature:getPosition()
  local distance = getDistanceBetween(player:getPosition(), pos)
  
  -- Check range
  local maxRange = config.settings[1] and config.settings[1].value or 9
  if distance > maxRange then return false end
  
  -- Check custom player list
  for _, customPlayer in ipairs(config.customPlayers) do
    if customPlayer:lower() == name:lower() then
      return true
    end
  end
  
  -- Check conditions
  if config.conditions.party then
    if creature:getShield() >= 2 then -- Party member
      return true
    end
  end
  
  if config.conditions.guild then
    if creature:getGuild() == player:getGuild() then
      return true
    end
  end
  
  -- Check vocations (would need API support)
  -- For now, assume all valid players should be considered
  
  return false
end

-- Get best healing spell for target
local function getBestHealSpell(target)
  local hp = target:getHealthPercent()
  local currentMana = mana()
  
  for _, priority in ipairs(config.priorities) do
    if priority.enabled then
      local minHp = priority.minHp or 60
      local minMana = priority.minMana or 50
      local range = priority.range or 9
      
      local distance = getDistanceBetween(player:getPosition(), target:getPosition())
      
      if hp <= minHp and currentMana >= minMana and distance <= range then
        if canCast(priority.name) then
          return priority.name, target:getName()
        end
      end
    end
  end
  
  return nil
end

-- Execute healing action
local function executeHeal(target, spell)
  if not target or not spell then return false end
  
  local name = target:getName()
  local fullSpell = spell .. ' "' .. name .. '"'
  
  if canCast(fullSpell) then
    say(fullSpell)
    healerState.lastHeal = now
    
    if nExBot and nExBot.EventBus then
      nExBot.EventBus:emit("friend_healed", {
        target = name,
        spell = spell,
        hp = target:getHealthPercent()
      })
    end
    
    return true
  end
  
  return false
end

-- Main healer macro
macro(100, function()
  if not config.enabled then return end
  
  -- Cooldown check
  if now - healerState.lastHeal < healerState.healCooldown then return end
  
  -- Find targets needing heal
  local healTarget = nil
  local lowestHp = 100
  
  for _, creature in ipairs(getSpectators()) do
    if shouldHeal(creature) then
      local hp = creature:getHealthPercent()
      
      -- Find lowest HP target
      if hp < lowestHp then
        local spell = getBestHealSpell(creature)
        if spell then
          lowestHp = hp
          healTarget = creature
        end
      end
    end
  end
  
  -- Execute heal
  if healTarget then
    local spell = getBestHealSpell(healTarget)
    if spell then
      executeHeal(healTarget, spell)
    end
  end
end)

-- Item heal macro
macro(500, function()
  if not config.enabled then return end
  
  local itemId = config.settings[2] and config.settings[2].value or 3160
  local itemRange = config.settings[3] and config.settings[3].value or 5
  local minPlayerHp = config.settings[5] and config.settings[5].value or 80
  
  if itemId <= 0 then return end
  
  -- Find target for item heal
  for _, creature in ipairs(getSpectators()) do
    if shouldHeal(creature) then
      local hp = creature:getHealthPercent()
      local distance = getDistanceBetween(player:getPosition(), creature:getPosition())
      
      if hp <= minPlayerHp and distance <= itemRange then
        useWith(itemId, creature)
        return
      end
    end
  end
end)

-- Mass heal check
macro(200, function()
  if not config.enabled then return end
  
  local masResAmount = config.settings[4] and config.settings[4].value or 3
  local minHp = config.settings[5] and config.settings[5].value or 80
  
  local count = 0
  
  for _, creature in ipairs(getSpectators()) do
    if shouldHeal(creature) and creature:getHealthPercent() <= minHp then
      count = count + 1
    end
  end
  
  if count >= masResAmount then
    if canCast("exura gran mas res") then
      say("exura gran mas res")
    end
  end
end)

-- Public API
FriendHealer = {
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
  
  addPlayer = function(name)
    table.insert(config.customPlayers, name)
    storage[panelName] = config
  end,
  
  removePlayer = function(name)
    for i, p in ipairs(config.customPlayers) do
      if p:lower() == name:lower() then
        table.remove(config.customPlayers, i)
        storage[panelName] = config
        return true
      end
    end
    return false
  end,
  
  getPlayers = function()
    return config.customPlayers
  end
}
