--[[
  ============================================================================
  nExBot AttackBot Module
  ============================================================================
  
  Advanced attack configuration with 5 profiles.
  
  FEATURES:
  - 5 switchable profiles
  - Targeted Spells (exori, exori gran, etc.)
  - Area Runes (SD, GFB, Avalanche, etc.)
  - Targeted Runes (SD on target, etc.)
  - Minimum monster count for AoE
  - Mana management
  
  Author: nExBot Team
  Version: 2.0.0
  Last Updated: December 2025
  
  ============================================================================
]]

setDefaultTab("Main")

--[[
  ============================================================================
  LOCAL CACHING FOR PERFORMANCE
  ============================================================================
]]
local table_insert = table.insert
local pairs = pairs
local tonumber = tonumber
local tostring = tostring

--[[
  ============================================================================
  UI SETUP
  ============================================================================
]]

local attackPanelName = "attackbot"
local ui = setupUI([[
Panel
  height: 38

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('AttackBot')

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
    text: Attack #1
    background: #292A2A
]])
ui:setId(attackPanelName)

--[[
  ============================================================================
  CONFIGURATION INITIALIZATION
  ============================================================================
]]

if not AttackBotConfig then
  AttackBotConfig = {}
end

-- Initialize 5 empty profiles if not present
if not AttackBotConfig[attackPanelName] or not AttackBotConfig[attackPanelName][1] or #AttackBotConfig[attackPanelName] ~= 5 then
  AttackBotConfig[attackPanelName] = {}
  for i = 1, 5 do
    AttackBotConfig[attackPanelName][i] = {
      enabled = false,
      targetedSpells = {},      -- Array of targeted spell rules
      areaRunes = {},           -- Array of area rune rules
      targetedRunes = {},       -- Array of targeted rune rules
      name = "Attack #" .. i,
      CheckMana = true,
      CheckCooldown = true,
      WaitForTarget = false,
      SafeMode = false
    }
  end
end

-- Validate current profile index
if not AttackBotConfig.currentAttackBotProfile or AttackBotConfig.currentAttackBotProfile == 0 or AttackBotConfig.currentAttackBotProfile > 5 then
  AttackBotConfig.currentAttackBotProfile = 1
end

--[[
  ============================================================================
  PROFILE MANAGEMENT
  ============================================================================
]]

local currentSettings

local function setActiveProfile()
  local n = AttackBotConfig.currentAttackBotProfile
  currentSettings = AttackBotConfig[attackPanelName][n]
end
setActiveProfile()

local function activeProfileColor()
  for i = 1, 5 do
    if i == AttackBotConfig.currentAttackBotProfile then
      ui[i]:setColor("green")
    else
      ui[i]:setColor("white")
    end
  end
end
activeProfileColor()

local function setProfileName()
  ui.name:setText(currentSettings.name)
end
setProfileName()

local function profileChange()
  setActiveProfile()
  activeProfileColor()
  setProfileName()
  ui.title:setOn(currentSettings.enabled)
  nexbotConfigSave("attack")
end

--[[
  ============================================================================
  UI EVENT HANDLERS
  ============================================================================
]]

ui.title:setOn(currentSettings.enabled)
ui.title.onClick = function(widget)
  currentSettings.enabled = not currentSettings.enabled
  widget:setOn(currentSettings.enabled)
  nexbotConfigSave("attack")
end

-- Profile selection buttons (1-5)
for i = 1, 5 do
  local button = ui[i]
  button.onClick = function()
    AttackBotConfig.currentAttackBotProfile = i
    profileChange()
  end
end

--[[
  ============================================================================
  SETTINGS WINDOW
  ============================================================================
]]
local rootWidget = g_ui.getRootWidget()
local attackWindow = nil

if rootWidget then
  local success, result = pcall(function()
    return UI.createWindow('AttackBotWindow', rootWidget)
  end)
  
  if success and result then
    attackWindow = result
    attackWindow:hide()
    
    attackWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        nexbotConfigSave("attack")
        if attackWindow.attacker then attackWindow.attacker:show() end
        if attackWindow.settings then attackWindow.settings:hide() end
        if attackWindow.settingsButton then attackWindow.settingsButton:setText("Settings") end
      end
    end
    
    -- Toggle between attacker and settings views
    local settingsBtn = attackWindow:recursiveGetChildById('settingsButton')
    if settingsBtn then
      settingsBtn.onClick = function(widget)
        local attacker = attackWindow:recursiveGetChildById('attacker')
        local settings = attackWindow:recursiveGetChildById('settings')
        
        if attacker and settings then
          if attacker:isVisible() then
            attacker:hide()
            settings:show()
            widget:setText("Back")
          else
            attacker:show()
            settings:hide()
            widget:setText("Settings")
          end
        end
      end
    end
    
    -- Close button
    local closeBtn = attackWindow:recursiveGetChildById('closeButton')
    if closeBtn then
      closeBtn.onClick = function()
        attackWindow:hide()
      end
    end
  end
end

ui.settings.onClick = function(widget)
  if attackWindow then
    attackWindow:show()
    attackWindow:raise()
    attackWindow:focus()
  else
    warn("[AttackBot] Settings window not available")
  end
end

--[[
  ============================================================================
  PERSISTENCE
  ============================================================================
]]

function nexbotConfigSave(configType)
  if configType == "attack" then
    storage.AttackBotConfig = AttackBotConfig
  end
  storage.AttackBotConfig = AttackBotConfig
end

if storage.AttackBotConfig then
  AttackBotConfig = storage.AttackBotConfig
  setActiveProfile()
  activeProfileColor()
  setProfileName()
  ui.title:setOn(currentSettings.enabled)
end

--[[
  ============================================================================
  ATTACK MACROS
  ============================================================================
]]

-- Helper: Count monsters in range
local function countMonstersInRange(range)
  local count = 0
  local myPos = player:getPosition()
  
  for _, spec in ipairs(getSpectators()) do
    if not spec:isPlayer() and not spec:isDead() then
      local specPos = spec:getPosition()
      if myPos.z == specPos.z then
        local distance = math.max(math.abs(myPos.x - specPos.x), math.abs(myPos.y - specPos.y))
        if distance <= range then
          count = count + 1
        end
      end
    end
  end
  
  return count
end

-- Targeted Spells Macro
macro(100, function()
  if not currentSettings.enabled then return end
  
  local target = g_game.getAttackingCreature and g_game.getAttackingCreature()
  
  if currentSettings.WaitForTarget and not target then return end
  
  local currentMp = mana()
  local monstersAround = countMonstersInRange(3)
  
  for _, entry in pairs(currentSettings.targetedSpells or {}) do
    if entry.enabled then
      local minMana = tonumber(entry.mana) or 0
      local minMonsters = tonumber(entry.minMonsters) or 1
      
      if currentMp >= minMana and monstersAround >= minMonsters then
        if canCast(entry.spell, not currentSettings.CheckCooldown) then
          say(entry.spell)
          return
        end
      end
    end
  end
end)

-- Area Runes Macro
macro(200, function()
  if not currentSettings.enabled then return end
  
  local target = g_game.getAttackingCreature and g_game.getAttackingCreature()
  if not target then return end
  
  for _, entry in pairs(currentSettings.areaRunes or {}) do
    if entry.enabled then
      local minMonsters = tonumber(entry.minMonsters) or 2
      local monstersAround = countMonstersInRange(3)
      
      if monstersAround >= minMonsters then
        local runeId = tonumber(entry.runeId)
        if runeId and itemAmount(runeId) > 0 then
          -- Use on target position for area effect
          local targetPos = target:getPosition()
          useWith(runeId, g_map.getTile(targetPos):getTopUseThing())
          return
        end
      end
    end
  end
end)

-- Targeted Runes Macro
macro(200, function()
  if not currentSettings.enabled then return end
  
  local target = g_game.getAttackingCreature and g_game.getAttackingCreature()
  if not target then return end
  
  for _, entry in pairs(currentSettings.targetedRunes or {}) do
    if entry.enabled then
      local minMonsters = tonumber(entry.minMonsters) or 1
      local monstersAround = countMonstersInRange(3)
      
      if monstersAround >= minMonsters then
        local runeId = tonumber(entry.runeId)
        if runeId and itemAmount(runeId) > 0 then
          local useTarget = target
          
          -- Check source type (On Target vs On Self)
          if entry.source == "On Self" then
            useTarget = player
          end
          
          useWith(runeId, useTarget)
          return
        end
      end
    end
  end
end)

--[[
  ============================================================================
  PUBLIC API
  ============================================================================
]]

AttackBot = {
  isOn = function()
    return currentSettings.enabled
  end,
  
  isOff = function()
    return not currentSettings.enabled
  end,
  
  setOff = function()
    currentSettings.enabled = false
    ui.title:setOn(false)
    nexbotConfigSave("attack")
  end,
  
  setOn = function()
    currentSettings.enabled = true
    ui.title:setOn(true)
    nexbotConfigSave("attack")
  end,
  
  getActiveProfile = function()
    return AttackBotConfig.currentAttackBotProfile
  end,
  
  setActiveProfile = function(n)
    if not n or not tonumber(n) or n < 1 or n > 5 then
      return error("[AttackBot] wrong profile parameter! should be 1 to 5, is " .. tostring(n))
    else
      AttackBotConfig.currentAttackBotProfile = n
      profileChange()
    end
  end,
  
  show = function()
    if attackWindow then
      attackWindow:show()
      attackWindow:raise()
      attackWindow:focus()
    end
  end,
  
  addTargetedSpell = function(spell, mana, minMonsters)
    table_insert(currentSettings.targetedSpells, {
      enabled = true,
      spell = spell,
      mana = mana or 0,
      minMonsters = minMonsters or 1
    })
    nexbotConfigSave("attack")
  end,
  
  addAreaRune = function(runeId, minMonsters)
    table_insert(currentSettings.areaRunes, {
      enabled = true,
      runeId = runeId,
      minMonsters = minMonsters or 2
    })
    nexbotConfigSave("attack")
  end,
  
  addTargetedRune = function(runeId, source, minMonsters)
    table_insert(currentSettings.targetedRunes, {
      enabled = true,
      runeId = runeId,
      source = source or "On Target",
      minMonsters = minMonsters or 1
    })
    nexbotConfigSave("attack")
  end,
  
  getSettings = function()
    return currentSettings
  end
}

logInfo("[AttackBot] Module loaded")
