local targetbotMacro = nil
local config = nil
local lastAction = 0
local cavebotAllowance = 0
local lureEnabled = true
local dangerValue = 0
local looterStatus = ""

-- Creature type constants for clarity
local CREATURE_TYPE = {
  PLAYER = 0,
  MONSTER = 1,      -- Targetable monster
  NPC = 2,
  SUMMON = 3        -- Non-targetable (other player's summons)
}

-- Pre-allocated constants for pathfinding (PERFORMANCE: avoid table creation in loop)
local PATH_PARAMS = {
  ignoreLastCreature = true,
  ignoreNonPathable = true,
  ignoreCost = true,
  ignoreCreatures = true
}

-- Pre-allocated status strings (PERFORMANCE: avoid string concatenation)
local STATUS_ATTACKING = "Attacking"
local STATUS_ATTACKING_LURE_OFF = "Attacking (luring off)"
local STATUS_PULLING = "Pulling (using CaveBot)"
local STATUS_WAITING = "Waiting"
local STATUS_ATTACK_PREFIX = "Attack & "

-- PERFORMANCE: Path cache to avoid recalculating paths every tick
local PathCache = {
  paths = {},           -- {creatureId -> {path, timestamp}}
  TTL = 500,            -- Cache paths for 500ms
  lastCleanup = 0,
  cleanupInterval = 2000
}

local function getCachedPath(creatureId, fromPos, toPos)
  local cached = PathCache.paths[creatureId]
  if cached and (now - cached.timestamp) < PathCache.TTL then
    return cached.path
  end
  return nil
end

local function setCachedPath(creatureId, path)
  PathCache.paths[creatureId] = {
    path = path,
    timestamp = now
  }
end

local function cleanupPathCache()
  if now - PathCache.lastCleanup < PathCache.cleanupInterval then
    return
  end
  
  local cutoff = now - PathCache.TTL
  for id, data in pairs(PathCache.paths) do
    if data.timestamp < cutoff then
      PathCache.paths[id] = nil
    end
  end
  PathCache.lastCleanup = now
end

-- Helper function to check if creature is targetable
local function isTargetableCreature(creature, oldTibia)
  if not creature:isMonster() then
    return false
  end
  
  -- Old Tibia clients don't have creature types
  if oldTibia then
    return true
  end
  
  local creatureType = creature:getType()
  
  -- Target monsters and some summons (type < 3)
  return creatureType < 3
end

-- ui
local configWidget = UI.Config()
local ui = UI.createWidget("TargetBotPanel")

ui.list = ui.listPanel.list -- shortcut
TargetBot.targetList = ui.list
TargetBot.Looting.setup()

-- Setup eat food feature if available
if TargetBot.EatFood and TargetBot.EatFood.setup then
  TargetBot.EatFood.setup()
end

ui.status.left:setText("Status:")
ui.status.right:setText("Off")
ui.target.left:setText("Target:")
ui.target.right:setText("-")
ui.config.left:setText("Config:")
ui.config.right:setText("-")
ui.danger.left:setText("Danger:")
ui.danger.right:setText("0")

ui.editor.debug.onClick = function()
  local on = ui.editor.debug:isOn()
  ui.editor.debug:setOn(not on)
  if on then
    local specs = getSpectators()
    for i = 1, #specs do
      specs[i]:clearText()
    end
  end
end

local oldTibia = g_game.getClientVersion() < 960

-- NOTE: TargetBot main loop is currently disabled pending performance optimization.
-- The targeting system uses path caching and reduced API calls for better performance.
-- TODO: Re-enable after completing macro performance tuning.
-- See PathCache implementation above for the optimized approach.

-- config, its callback is called immediately, data can be nil
config = Config.setup("targetbot_configs", configWidget, "json", function(name, enabled, data)
  if not data then
    ui.status.right:setText("Off")
    return targetbotMacro.setOff() 
  end
  TargetBot.Creature.resetConfigs()
  for _, value in ipairs(data["targeting"] or {}) do
    TargetBot.Creature.addConfig(value)
  end
  TargetBot.Looting.update(data["looting"] or {})

  -- add configs
  if enabled then
    ui.status.right:setText("On")
  else
    ui.status.right:setText("Off")
  end

  if targetbotMacro and targetbotMacro.setOn then
    targetbotMacro.setOn(enabled)
    targetbotMacro.delay = nil
  end
  lureEnabled = true
end)

-- Setup UI tooltips
ui.editor.buttons.add:setTooltip("Add a new creature targeting configuration.\nDefine which creatures to attack and how.")
ui.editor.buttons.edit:setTooltip("Edit the selected creature targeting configuration.\nModify priority, distance, and behavior settings.")
ui.editor.buttons.remove:setTooltip("Remove the selected creature targeting configuration.\nThis action cannot be undone.")
ui.editor.debug:setTooltip("Show priority values on creatures in-game.\nUseful for debugging targeting decisions.")
ui.configButton:setTooltip("Show/hide the target editor panel.\nUse to add, edit, or remove creature configurations.")

-- setup ui
ui.editor.buttons.add.onClick = function()
  TargetBot.Creature.edit(nil, function(newConfig)
    TargetBot.Creature.addConfig(newConfig, true)
    TargetBot.save()
  end)
end

ui.editor.buttons.edit.onClick = function()
  local entry = ui.list:getFocusedChild()
  if not entry then return end
  TargetBot.Creature.edit(entry.value, function(newConfig)
    entry:setText(newConfig.name)
    entry.value = newConfig
    TargetBot.Creature.resetConfigsCache()
    TargetBot.save()
  end)
end

ui.editor.buttons.remove.onClick = function()
  local entry = ui.list:getFocusedChild()
  if not entry then return end
  entry:destroy()
  TargetBot.Creature.resetConfigsCache()
  TargetBot.save()
end

-- public function, you can use them in your scripts
TargetBot.isActive = function() -- return true if attacking or looting takes place
  return lastAction + 300 > now
end

TargetBot.isCaveBotActionAllowed = function()
  return cavebotAllowance > now
end

TargetBot.setStatus = function(text)
  return ui.status.right:setText(text)
end

TargetBot.getStatus = function()
  return ui.status.right:getText()
end

TargetBot.isOn = function()
  if not config or not config.isOn then return false end
  return config.isOn()
end

TargetBot.isOff = function()
  if not config or not config.isOff then return true end
  return config.isOff()
end

TargetBot.setOn = function(val)
  if val == false then  
    return TargetBot.setOff(true)
  end
  config.setOn()
end

TargetBot.setOff = function(val)
  if val == false then  
    return TargetBot.setOn(true)
  end
  config.setOff()
end

TargetBot.getCurrentProfile = function()
  return storage._configs.targetbot_configs.selected
end

local botConfigName = modules.game_bot.contentsPanel.config:getCurrentOption().text
TargetBot.setCurrentProfile = function(name)
  if not g_resources.fileExists("/bot/"..botConfigName.."/targetbot_configs/"..name..".json") then
    return warn("there is no targetbot profile with that name!")
  end
  TargetBot.setOff()
  storage._configs.targetbot_configs.selected = name
  TargetBot.setOn()
end

TargetBot.delay = function(value)
  targetbotMacro.delay = now + value
end

TargetBot.save = function()
  local data = {targeting={}, looting={}}
  for _, entry in ipairs(ui.list:getChildren()) do
    table.insert(data.targeting, entry.value)
  end
  TargetBot.Looting.save(data.looting)
  config.save(data)
end

TargetBot.allowCaveBot = function(time)
  cavebotAllowance = now + time
end

TargetBot.disableLuring = function()
  lureEnabled = false
end

TargetBot.enableLuring = function()
  lureEnabled = true
end

TargetBot.Danger = function()
  return dangerValue
end

TargetBot.lootStatus = function()
  return looterStatus
end


-- attacks
local lastSpell = 0
local lastAttackSpell = 0

TargetBot.saySpell = function(text, delay)
  if type(text) ~= 'string' or text:len() < 1 then return end
  if not delay then delay = 500 end
  if g_game.getProtocolVersion() < 1090 then
    lastAttackSpell = now -- pause attack spells, healing spells are more important
  end
  if lastSpell + delay < now then
    say(text)
    lastSpell = now
    return true
  end
  return false
end

TargetBot.sayAttackSpell = function(text, delay)
  if type(text) ~= 'string' or text:len() < 1 then return end
  if not delay then delay = 2000 end
  if lastAttackSpell + delay < now then
    say(text)
    lastAttackSpell = now
    return true
  end
  return false
end

local lastItemUse = 0
local lastRuneAttack = 0

-- Use item on target like hotkey (doesn't require open backpack)
-- Tries multiple methods for maximum compatibility and speed
local function useItemOnTargetLikeHotkey(item, target, subType)
  -- Determine subType based on client version
  local thing = g_things.getThingType(item)
  if not thing or not thing:isFluidContainer() then
    subType = g_game.getClientVersion() >= 860 and 0 or 1
  end
  
  -- Method 1: Modern clients (780+) - use inventory item directly (like hotkey)
  if g_game.getClientVersion() >= 780 then
    if g_game.useInventoryItemWith then
      g_game.useInventoryItemWith(item, target, subType)
      return true
    end
  end
  
  -- Method 2: Legacy clients - find item and use with target
  local tmpItem = g_game.findPlayerItem(item, subType)
  if tmpItem then
    g_game.useWith(tmpItem, target, subType)
    return true
  end
  
  return false
end

TargetBot.useItem = function(item, subType, target, delay)
  if not delay then delay = 200 end
  if lastItemUse + delay < now then
    if useItemOnTargetLikeHotkey(item, target, subType) then
      lastItemUse = now
      return true
    end
  end
  return false
end

TargetBot.useAttackItem = function(item, subType, target, delay)
  if not delay then delay = 2000 end
  if lastRuneAttack + delay < now then
    if useItemOnTargetLikeHotkey(item, target, subType) then
      lastRuneAttack = now
      return true
    end
  end
  return false
end

TargetBot.canLure = function()
  return lureEnabled
end