--[[
  TargetBot Module
  
  Main TargetBot controller for automated targeting and attacking.
  Based on classic OTClient bot TargetBot patterns.
  
  Author: nExBot Team
  Version: 1.0.0
]]

setDefaultTab("Target")

-- TargetBot global namespace
TargetBot = {}
TargetBot.Creatures = {}

-- TargetBot state
local targetBotState = {
  enabled = false,
  currentTarget = nil,
  lastAttack = 0,
  lastSwitch = 0,
  attacking = false
}

-- Main TargetBot UI
local panelName = "targetbot"
local ui = setupUI([[
Panel
  height: 38

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('TargetBot')

  Button
    id: config
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Editor

  Label
    id: targetLabel
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 15
    text-align: left
    font: verdana-11px-rounded
    color: #aaaaaa
    text: Target: none

]])
ui:setId(panelName)

-- Storage initialization
if not storage.targetbot then
  storage.targetbot = {
    enabled = false,
    creatures = {},
    settings = {
      range = 7,
      faceTarget = true,
      chaseMode = true,
      attackMode = "balanced",
      targetSwitchDelay = 1000,
      avoidWaves = false,
      lootBodies = true,
      lootDistance = 3,
      antiAfk = false
    }
  }
end

local config = storage.targetbot

-- UI state
ui.title:setOn(config.enabled)

ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  targetBotState.enabled = config.enabled
  widget:setOn(config.enabled)
  storage.targetbot = config
  
  if config.enabled then
    logInfo("[TargetBot] Enabled")
  else
    logInfo("[TargetBot] Disabled")
  end
end

-- Config button opens editor
local targetBotWindow = nil
local rootWidget = g_ui.getRootWidget()

if rootWidget then
  targetBotWindow = UI.createWindow('TargetBotWindow', rootWidget)
  if targetBotWindow then
    targetBotWindow:hide()
    
    targetBotWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        storage.targetbot = config
      end
    end
  end
end

ui.config.onClick = function(widget)
  if targetBotWindow then
    targetBotWindow:show()
    targetBotWindow:raise()
    targetBotWindow:focus()
  end
end

-- Attack modes
TargetBot.AttackModes = {
  OFFENSIVE = "offensive",
  BALANCED = "balanced", 
  DEFENSIVE = "defensive"
}

-- Chase modes
TargetBot.ChaseModes = {
  STAND = "stand",
  CHASE = "chase"
}

-- Priority types
TargetBot.Priority = {
  HEALTH = "health",
  DISTANCE = "distance",
  DANGER = "danger",
  CUSTOM = "custom"
}

-- Creature settings structure
TargetBot.CreatureConfig = {
  -- Default creature settings
  default = {
    attack = true,
    priority = 1,
    danger = 5,
    keepDistance = false,
    avoidWaves = true,
    loot = true,
    skin = false,
    spells = {},
    items = {},
    chase = true
  }
}

-- Add creature configuration
function TargetBot.addCreature(name, settings)
  settings = settings or {}
  
  -- Merge with defaults
  local creatureConfig = {}
  for k, v in pairs(TargetBot.CreatureConfig.default) do
    creatureConfig[k] = v
  end
  for k, v in pairs(settings) do
    creatureConfig[k] = v
  end
  
  creatureConfig.name = name:lower()
  config.creatures[name:lower()] = creatureConfig
  storage.targetbot = config
  
  logInfo(string.format("[TargetBot] Added creature: %s", name))
  
  return creatureConfig
end

-- Remove creature configuration
function TargetBot.removeCreature(name)
  if config.creatures[name:lower()] then
    config.creatures[name:lower()] = nil
    storage.targetbot = config
    return true
  end
  return false
end

-- Get creature configuration
function TargetBot.getCreature(name)
  return config.creatures[name:lower()]
end

-- Get all creature configurations
function TargetBot.getAllCreatures()
  return config.creatures
end

-- Clear all creatures
function TargetBot.clearCreatures()
  config.creatures = {}
  storage.targetbot = config
end

-- Calculate danger score for a creature
local function calculateDangerScore(creature)
  if not creature then return 0 end
  
  local name = creature:getName():lower()
  local creatureConfig = config.creatures[name]
  
  if creatureConfig then
    return creatureConfig.danger or 5
  end
  
  -- Default danger based on health
  local health = creature:getHealth and creature:getHealth() or 100
  local maxHealth = creature:getMaxHealth and creature:getMaxHealth() or 100
  
  return (maxHealth / 100) -- Higher health = more dangerous
end

-- Calculate priority score for a creature
local function calculatePriorityScore(creature)
  if not creature then return 0 end
  
  local score = 0
  local name = creature:getName():lower()
  local creatureConfig = config.creatures[name]
  
  -- Base priority from config
  if creatureConfig then
    score = score + (creatureConfig.priority or 1) * 100
  end
  
  -- Health factor (lower health = higher priority for killing)
  local health = creature:getHealth and creature:getHealth() or 100
  local maxHealth = creature:getMaxHealth and creature:getMaxHealth() or 100
  local healthPercent = (maxHealth > 0) and (health / maxHealth) or 1
  score = score + (1 - healthPercent) * 50
  
  -- Distance factor (closer = higher priority)
  local myPos = player:getPosition()
  local creaturePos = creature:getPosition()
  local distance = math.sqrt(
    math.pow(myPos.x - creaturePos.x, 2) +
    math.pow(myPos.y - creaturePos.y, 2)
  )
  score = score + math.max(0, (10 - distance) * 10)
  
  -- Danger factor
  local danger = calculateDangerScore(creature)
  score = score + danger * 10
  
  return score
end

-- Check if creature should be attacked
function TargetBot.shouldAttack(creature)
  if not creature then return false end
  
  -- Check if dead
  if creature:isDead() then return false end
  
  -- Check if monster
  if not creature:isMonster() then return false end
  
  local name = creature:getName():lower()
  local creatureConfig = config.creatures[name]
  
  -- If no config, check if in target list
  if creatureConfig then
    return creatureConfig.attack ~= false
  end
  
  -- Default: attack all monsters if no config exists
  return true
end

-- Get creatures in range
function TargetBot.getCreaturesInRange(range)
  range = range or config.settings.range
  
  local creatures = {}
  local specs = getSpectators() or {}
  
  for _, creature in ipairs(specs) do
    if creature:isMonster() and not creature:isDead() then
      local myPos = player:getPosition()
      local creaturePos = creature:getPosition()
      
      -- Check same floor
      if myPos.z == creaturePos.z then
        local distance = math.sqrt(
          math.pow(myPos.x - creaturePos.x, 2) +
          math.pow(myPos.y - creaturePos.y, 2)
        )
        
        if distance <= range then
          table.insert(creatures, {
            creature = creature,
            distance = distance,
            priority = calculatePriorityScore(creature)
          })
        end
      end
    end
  end
  
  -- Sort by priority
  table.sort(creatures, function(a, b)
    return a.priority > b.priority
  end)
  
  return creatures
end

-- Select best target
function TargetBot.selectBestTarget()
  local creatures = TargetBot.getCreaturesInRange()
  
  if #creatures == 0 then
    return nil
  end
  
  -- Get highest priority target
  for _, data in ipairs(creatures) do
    if TargetBot.shouldAttack(data.creature) then
      return data.creature
    end
  end
  
  return nil
end

-- Attack target
function TargetBot.attackTarget(creature)
  if not creature then return false end
  
  local currentTarget = g_game.getAttackingCreature and g_game.getAttackingCreature()
  
  if currentTarget ~= creature then
    g_game.attack(creature)
    targetBotState.currentTarget = creature
    targetBotState.lastSwitch = now
    
    -- Update UI
    ui.targetLabel:setText("Target: " .. creature:getName())
    
    -- Emit event
    if nExBot and nExBot.EventBus then
      nExBot.EventBus:emit(nExBot.EventBus.Events.TARGET_CHANGED, creature)
    end
    
    return true
  end
  
  return false
end

-- Get current target
function TargetBot.getTarget()
  return targetBotState.currentTarget
end

-- Clear target
function TargetBot.clearTarget()
  targetBotState.currentTarget = nil
  ui.targetLabel:setText("Target: none")
end

-- Check if target is valid
function TargetBot.hasValidTarget()
  local target = targetBotState.currentTarget
  
  if not target then return false end
  if target:isDead() then return false end
  
  -- Check if in range
  local myPos = player:getPosition()
  local targetPos = target:getPosition()
  
  if myPos.z ~= targetPos.z then return false end
  
  local distance = math.sqrt(
    math.pow(myPos.x - targetPos.x, 2) +
    math.pow(myPos.y - targetPos.y, 2)
  )
  
  return distance <= config.settings.range
end

-- Execute attack spells for creature
local function executeCreatureSpells(creature)
  if not creature then return end
  
  local name = creature:getName():lower()
  local creatureConfig = config.creatures[name]
  
  if not creatureConfig or not creatureConfig.spells then return end
  
  for _, spell in ipairs(creatureConfig.spells) do
    if spell.enabled then
      local mana = player:getMana()
      local hp = player:getHealthPercent()
      
      -- Check conditions
      local canCast = true
      
      if spell.minMana and mana < spell.minMana then
        canCast = false
      end
      
      if spell.minHp and hp < spell.minHp then
        canCast = false
      end
      
      if canCast then
        say(spell.words)
        break -- Only one spell per cycle
      end
    end
  end
end

-- Use items on creature
local function useCreatureItems(creature)
  if not creature then return end
  
  local name = creature:getName():lower()
  local creatureConfig = config.creatures[name]
  
  if not creatureConfig or not creatureConfig.items then return end
  
  for _, item in ipairs(creatureConfig.items) do
    if item.enabled then
      local hasItem = findItem(item.id)
      if hasItem then
        useWith(item.id, creature)
        break
      end
    end
  end
end

-- Main TargetBot loop
macro(100, function()
  if not config.enabled then return end
  
  -- Check if we have a valid target
  if TargetBot.hasValidTarget() then
    -- Execute spells and items
    executeCreatureSpells(targetBotState.currentTarget)
    useCreatureItems(targetBotState.currentTarget)
  else
    -- Find new target
    local newTarget = TargetBot.selectBestTarget()
    
    if newTarget then
      TargetBot.attackTarget(newTarget)
    else
      TargetBot.clearTarget()
    end
  end
  
  -- Update attack indicator
  local attacking = g_game.getAttackingCreature and g_game.getAttackingCreature()
  if attacking then
    ui.targetLabel:setColor("#44ff44")
  else
    ui.targetLabel:setColor("#aaaaaa")
  end
end)

-- Listen for creature death
onCreatureDeath(function(creature)
  if targetBotState.currentTarget == creature then
    TargetBot.clearTarget()
    
    -- Emit event
    if nExBot and nExBot.EventBus then
      nExBot.EventBus:emit(nExBot.EventBus.Events.CREATURE_DIED, creature, creature:getPosition())
    end
  end
end)

-- Public API
TargetBot.isOn = function()
  return config.enabled
end

TargetBot.isOff = function()
  return not config.enabled
end

TargetBot.setOn = function()
  config.enabled = true
  targetBotState.enabled = true
  ui.title:setOn(true)
  storage.targetbot = config
end

TargetBot.setOff = function()
  config.enabled = false
  targetBotState.enabled = false
  ui.title:setOn(false)
  storage.targetbot = config
end

TargetBot.isActive = function()
  return config.enabled and TargetBot.hasValidTarget()
end

TargetBot.getSettings = function()
  return config.settings
end

TargetBot.setSetting = function(key, value)
  config.settings[key] = value
  storage.targetbot = config
end

-- Load TargetBot extensions
dofile("/nExBot/modules/target/creature_editor.lua")
dofile("/nExBot/modules/target/looting.lua")

logInfo("[TargetBot] Module loaded")
