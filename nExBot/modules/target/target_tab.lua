--[[
  ============================================================================
  nExBot Target Tab Module
  ============================================================================
  
  Consolidated target tab with TargetBot, Looting, and Creature Editor.
  Self-contained module without external dependencies.
  
  Author: nExBot Team
  Version: 2.0.0
  Last Updated: December 2025
  
  ============================================================================
]]

setDefaultTab("Target")

--[[
  ============================================================================
  TARGETBOT PANEL
  ============================================================================
]]

local targetPanelName = "nexbotTargetBot"
local targetUi = setupUI([[
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
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

  Button
    id: 1
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: 1
    margin-right: 2
    margin-top: 4
    size: 17 17

  Button
    id: 2
    anchors.top: prev.top
    anchors.left: prev.right
    text: 2
    margin-left: 2
    size: 17 17

  Button
    id: 3
    anchors.top: prev.top
    anchors.left: prev.right
    text: 3
    margin-left: 2
    size: 17 17

  Button
    id: 4
    anchors.top: prev.top
    anchors.left: prev.right
    text: 4
    margin-left: 2
    size: 17 17

  Button
    id: 5
    anchors.top: prev.top
    anchors.left: prev.right
    text: 5
    margin-left: 2
    size: 17 17

  Button
    id: name
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 4
    height: 17
    text: Target #1
    background: #292A2A
]])
targetUi:setId(targetPanelName)

-- Storage initialization
if not storage[targetPanelName] then
  storage[targetPanelName] = {
    enabled = false,
    currentProfile = 1,
    profiles = {}
  }
  for i = 1, 5 do
    storage[targetPanelName].profiles[i] = {
      name = "Target #" .. i,
      creatures = {},
      settings = {
        autoAttack = true,
        chaseMode = true,
        attackMode = "balanced"
      }
    }
  end
end
local targetConfig = storage[targetPanelName]

-- Get current profile
local function getCurrentTargetProfile()
  return targetConfig.profiles[targetConfig.currentProfile] or targetConfig.profiles[1]
end

-- Update profile name display
local function updateTargetProfileName()
  local profile = getCurrentTargetProfile()
  targetUi.name:setText(profile.name)
end

-- Update profile button colors
local function updateTargetProfileColors()
  for i = 1, 5 do
    if i == targetConfig.currentProfile then
      targetUi[i]:setColor("green")
    else
      targetUi[i]:setColor("white")
    end
  end
end

-- Initialize UI
targetUi.title:setOn(targetConfig.enabled)
targetUi.title.onClick = function(widget)
  targetConfig.enabled = not targetConfig.enabled
  widget:setOn(targetConfig.enabled)
  storage[targetPanelName] = targetConfig
end

-- Profile buttons
for i = 1, 5 do
  targetUi[i].onClick = function()
    targetConfig.currentProfile = i
    updateTargetProfileColors()
    updateTargetProfileName()
    storage[targetPanelName] = targetConfig
  end
end

updateTargetProfileColors()
updateTargetProfileName()

-- Settings button
targetUi.settings.onClick = function()
  warn("[TargetBot] Settings window - configure creatures to target")
end

--[[
  ============================================================================
  TARGETBOT LOGIC
  ============================================================================
]]

-- Simple targeting macro
macro(200, function()
  if not targetConfig.enabled then return end
  
  local profile = getCurrentTargetProfile()
  if not profile.settings.autoAttack then return end
  
  -- Check if already attacking
  local currentTarget = g_game.getAttackingCreature and g_game.getAttackingCreature()
  if currentTarget and not currentTarget:isDead() then return end
  
  -- Find nearest creature to attack
  local myPos = player:getPosition()
  local nearestDist = 999
  local nearestCreature = nil
  
  for _, spec in ipairs(getSpectators()) do
    if not spec:isPlayer() and not spec:isDead() and spec:isMonster() then
      local specPos = spec:getPosition()
      if myPos.z == specPos.z then
        local dist = math.max(math.abs(myPos.x - specPos.x), math.abs(myPos.y - specPos.y))
        if dist < nearestDist then
          nearestDist = dist
          nearestCreature = spec
        end
      end
    end
  end
  
  if nearestCreature then
    g_game.attack(nearestCreature)
  end
end)

--[[
  ============================================================================
  LOOTING PANEL
  ============================================================================
]]

local lootPanelName = "nexbotLooting"
local lootUi = setupUI([[
Panel
  height: 38

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Looting')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

  Button
    id: 1
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: 1
    margin-right: 2
    margin-top: 4
    size: 17 17

  Button
    id: 2
    anchors.top: prev.top
    anchors.left: prev.right
    text: 2
    margin-left: 2
    size: 17 17

  Button
    id: 3
    anchors.top: prev.top
    anchors.left: prev.right
    text: 3
    margin-left: 2
    size: 17 17

  Button
    id: 4
    anchors.top: prev.top
    anchors.left: prev.right
    text: 4
    margin-left: 2
    size: 17 17

  Button
    id: 5
    anchors.top: prev.top
    anchors.left: prev.right
    text: 5
    margin-left: 2
    size: 17 17

  Button
    id: name
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 4
    height: 17
    text: Loot #1
    background: #292A2A
]])
lootUi:setId(lootPanelName)

-- Storage initialization
if not storage[lootPanelName] then
  storage[lootPanelName] = {
    enabled = false,
    currentProfile = 1,
    profiles = {}
  }
  for i = 1, 5 do
    storage[lootPanelName].profiles[i] = {
      name = "Loot #" .. i,
      items = {},
      settings = {
        lootGold = true,
        lootAll = false,
        maxDistance = 3
      }
    }
  end
end
local lootConfig = storage[lootPanelName]

-- Get current profile
local function getCurrentLootProfile()
  return lootConfig.profiles[lootConfig.currentProfile] or lootConfig.profiles[1]
end

-- Update profile name display
local function updateLootProfileName()
  local profile = getCurrentLootProfile()
  lootUi.name:setText(profile.name)
end

-- Update profile button colors
local function updateLootProfileColors()
  for i = 1, 5 do
    if i == lootConfig.currentProfile then
      lootUi[i]:setColor("green")
    else
      lootUi[i]:setColor("white")
    end
  end
end

-- Initialize UI
lootUi.title:setOn(lootConfig.enabled)
lootUi.title.onClick = function(widget)
  lootConfig.enabled = not lootConfig.enabled
  widget:setOn(lootConfig.enabled)
  storage[lootPanelName] = lootConfig
end

-- Profile buttons
for i = 1, 5 do
  lootUi[i].onClick = function()
    lootConfig.currentProfile = i
    updateLootProfileColors()
    updateLootProfileName()
    storage[lootPanelName] = lootConfig
  end
end

updateLootProfileColors()
updateLootProfileName()

-- Settings button
lootUi.settings.onClick = function()
  warn("[Looting] Settings window - configure items to loot")
end

--[[
  ============================================================================
  LOOTING LOGIC
  ============================================================================
]]

-- Corpse IDs (common ones)
local corpseIds = {
  -- Add corpse item IDs as needed
}

-- Simple looting macro
macro(300, function()
  if not lootConfig.enabled then return end
  
  local profile = getCurrentLootProfile()
  local maxDist = profile.settings.maxDistance or 3
  local myPos = player:getPosition()
  
  -- Look for corpses nearby
  for dx = -maxDist, maxDist do
    for dy = -maxDist, maxDist do
      local pos = {x = myPos.x + dx, y = myPos.y + dy, z = myPos.z}
      local tile = g_map.getTile(pos)
      if tile then
        local topThing = tile:getTopUseThing()
        if topThing and topThing:isContainer() then
          -- This might be a corpse, try to open it
          -- In a real implementation, check if it's actually a corpse
        end
      end
    end
  end
end)

--[[
  ============================================================================
  CREATURE EDITOR PANEL
  ============================================================================
]]

local creaturePanelName = "nexbotCreatureEditor"
local creatureUi = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Creature Editor')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

]])
creatureUi:setId(creaturePanelName)

-- Storage initialization
if not storage[creaturePanelName] then
  storage[creaturePanelName] = {
    enabled = false,
    creatures = {}
  }
end
local creatureConfig = storage[creaturePanelName]

-- Initialize UI
creatureUi.title:setOn(creatureConfig.enabled)
creatureUi.title.onClick = function(widget)
  creatureConfig.enabled = not creatureConfig.enabled
  widget:setOn(creatureConfig.enabled)
  storage[creaturePanelName] = creatureConfig
end

-- Settings button
creatureUi.settings.onClick = function()
  warn("[Creature Editor] Settings window - configure creature behaviors")
end

--[[
  ============================================================================
  LURE SETTINGS PANEL
  ============================================================================
]]

local lurePanelName = "nexbotLure"
local lureUi = setupUI([[
Panel
  height: 50

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Lure Mode')

  Label
    id: countLabel
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 5
    text: Lure Count:
    font: verdana-11px-rounded

  SpinBox
    id: lureCount
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 5
    width: 50
    minimum: 1
    maximum: 20
    step: 1
]])
lureUi:setId(lurePanelName)

-- Storage initialization
if not storage[lurePanelName] then
  storage[lurePanelName] = {
    enabled = false,
    lureCount = 3
  }
end
local lureConfig = storage[lurePanelName]

-- Initialize UI
lureUi.title:setOn(lureConfig.enabled)
lureUi.title.onClick = function(widget)
  lureConfig.enabled = not lureConfig.enabled
  widget:setOn(lureConfig.enabled)
  storage[lurePanelName] = lureConfig
end

lureUi.lureCount:setValue(lureConfig.lureCount)
lureUi.lureCount.onValueChange = function(widget, value)
  lureConfig.lureCount = value
  storage[lurePanelName] = lureConfig
end

--[[
  ============================================================================
  PUBLIC API
  ============================================================================
]]

TargetBot = {
  isOn = function() return targetConfig.enabled end,
  isOff = function() return not targetConfig.enabled end,
  setOn = function()
    targetConfig.enabled = true
    targetUi.title:setOn(true)
    storage[targetPanelName] = targetConfig
  end,
  setOff = function()
    targetConfig.enabled = false
    targetUi.title:setOn(false)
    storage[targetPanelName] = targetConfig
  end,
  getActiveProfile = function() return targetConfig.currentProfile end,
  setActiveProfile = function(n)
    if n >= 1 and n <= 5 then
      targetConfig.currentProfile = n
      updateTargetProfileColors()
      updateTargetProfileName()
      storage[targetPanelName] = targetConfig
    end
  end
}

Looting = {
  isOn = function() return lootConfig.enabled end,
  isOff = function() return not lootConfig.enabled end,
  setOn = function()
    lootConfig.enabled = true
    lootUi.title:setOn(true)
    storage[lootPanelName] = lootConfig
  end,
  setOff = function()
    lootConfig.enabled = false
    lootUi.title:setOn(false)
    storage[lootPanelName] = lootConfig
  end,
  getActiveProfile = function() return lootConfig.currentProfile end,
  setActiveProfile = function(n)
    if n >= 1 and n <= 5 then
      lootConfig.currentProfile = n
      updateLootProfileColors()
      updateLootProfileName()
      storage[lootPanelName] = lootConfig
    end
  end
}

LureMode = {
  isOn = function() return lureConfig.enabled end,
  isOff = function() return not lureConfig.enabled end,
  setOn = function()
    lureConfig.enabled = true
    lureUi.title:setOn(true)
    storage[lurePanelName] = lureConfig
  end,
  setOff = function()
    lureConfig.enabled = false
    lureUi.title:setOn(false)
    storage[lurePanelName] = lureConfig
  end,
  getLureCount = function() return lureConfig.lureCount end,
  setLureCount = function(count)
    lureConfig.lureCount = count
    lureUi.lureCount:setValue(count)
    storage[lurePanelName] = lureConfig
  end
}

logInfo("[Target Tab] Module loaded")
