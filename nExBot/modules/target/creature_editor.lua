--[[
  TargetBot Creature Editor
  
  Visual editor for creature targeting settings.
  Based on classic OTClient bot creature editor patterns.
  
  Author: nExBot Team
  Version: 1.0.0
]]

-- Creature Editor Panel
local panelName = "creatureEditor"
local ui = setupUI([[
Panel
  height: 38

  BotLabel
    id: creatureLabel
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Creatures (0)

  Button
    id: addBtn
    anchors.top: prev.bottom
    anchors.left: parent.left
    width: 60
    margin-top: 2
    height: 17
    text: Add

  Button
    id: editBtn
    anchors.top: prev.top
    anchors.left: prev.right
    width: 60
    margin-left: 2
    height: 17
    text: Edit

  Button
    id: removeBtn
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 2
    height: 17
    text: Remove

]])
ui:setId(panelName)

local config = storage.targetbot

-- Creature editor window
local creatureEditorWindow = nil
local rootWidget = g_ui.getRootWidget()

if rootWidget then
  creatureEditorWindow = UI.createWindow('CreatureEditorWindow', rootWidget)
  if creatureEditorWindow then
    creatureEditorWindow:hide()
  end
end

-- Update creature count
local function updateCreatureCount()
  local count = 0
  for _ in pairs(config.creatures) do
    count = count + 1
  end
  ui.creatureLabel:setText(string.format("Creatures (%d)", count))
end

updateCreatureCount()

-- Add creature button
ui.addBtn.onClick = function(widget)
  local function addCreatureCallback(name)
    if name and name ~= "" then
      TargetBot.addCreature(name, {
        attack = true,
        priority = 1,
        danger = 5,
        loot = true,
        keepDistance = false,
        avoidWaves = true
      })
      updateCreatureCount()
    end
  end
  
  -- Show input dialog
  modules.client_textedit.singlelineEditor(
    "Add Creature",
    "Enter creature name:",
    addCreatureCallback
  )
end

-- Edit creature button
ui.editBtn.onClick = function(widget)
  if creatureEditorWindow then
    creatureEditorWindow:show()
    creatureEditorWindow:raise()
    creatureEditorWindow:focus()
    
    -- Populate creature list
    refreshCreatureList()
  end
end

-- Remove creature button
ui.removeBtn.onClick = function(widget)
  local function removeCreatureCallback(name)
    if name and name ~= "" then
      if TargetBot.removeCreature(name) then
        logInfo("[TargetBot] Removed creature: " .. name)
        updateCreatureCount()
      else
        warn("[TargetBot] Creature not found: " .. name)
      end
    end
  end
  
  -- Show input dialog
  modules.client_textedit.singlelineEditor(
    "Remove Creature",
    "Enter creature name to remove:",
    removeCreatureCallback
  )
end

-- Creature list management
local currentSelectedCreature = nil

function refreshCreatureList()
  if not creatureEditorWindow then return end
  
  local creatureList = creatureEditorWindow:recursiveGetChildById('creatureList')
  if not creatureList then return end
  
  creatureList:destroyChildren()
  
  for name, creatureConfig in pairs(config.creatures) do
    local item = g_ui.createWidget('CreatureListItem', creatureList)
    if item then
      item:setText(name)
      item.creatureName = name
      item.creatureConfig = creatureConfig
      
      item.onClick = function(self)
        selectCreature(name)
      end
    end
  end
end

function selectCreature(name)
  currentSelectedCreature = name
  local creatureConfig = config.creatures[name]
  
  if not creatureConfig or not creatureEditorWindow then return end
  
  -- Update fields
  local priorityField = creatureEditorWindow:recursiveGetChildById('priorityField')
  if priorityField then
    priorityField:setText(tostring(creatureConfig.priority or 1))
  end
  
  local dangerField = creatureEditorWindow:recursiveGetChildById('dangerField')
  if dangerField then
    dangerField:setText(tostring(creatureConfig.danger or 5))
  end
  
  local attackCheck = creatureEditorWindow:recursiveGetChildById('attackCheck')
  if attackCheck then
    attackCheck:setChecked(creatureConfig.attack ~= false)
  end
  
  local lootCheck = creatureEditorWindow:recursiveGetChildById('lootCheck')
  if lootCheck then
    lootCheck:setChecked(creatureConfig.loot ~= false)
  end
  
  local avoidCheck = creatureEditorWindow:recursiveGetChildById('avoidCheck')
  if avoidCheck then
    avoidCheck:setChecked(creatureConfig.avoidWaves == true)
  end
  
  local distanceCheck = creatureEditorWindow:recursiveGetChildById('distanceCheck')
  if distanceCheck then
    distanceCheck:setChecked(creatureConfig.keepDistance == true)
  end
end

-- Save creature settings
function saveCreatureSettings()
  if not currentSelectedCreature then return end
  
  local creatureConfig = config.creatures[currentSelectedCreature]
  if not creatureConfig then return end
  
  if not creatureEditorWindow then return end
  
  local priorityField = creatureEditorWindow:recursiveGetChildById('priorityField')
  if priorityField then
    creatureConfig.priority = tonumber(priorityField:getText()) or 1
  end
  
  local dangerField = creatureEditorWindow:recursiveGetChildById('dangerField')
  if dangerField then
    creatureConfig.danger = tonumber(dangerField:getText()) or 5
  end
  
  local attackCheck = creatureEditorWindow:recursiveGetChildById('attackCheck')
  if attackCheck then
    creatureConfig.attack = attackCheck:isChecked()
  end
  
  local lootCheck = creatureEditorWindow:recursiveGetChildById('lootCheck')
  if lootCheck then
    creatureConfig.loot = lootCheck:isChecked()
  end
  
  local avoidCheck = creatureEditorWindow:recursiveGetChildById('avoidCheck')
  if avoidCheck then
    creatureConfig.avoidWaves = avoidCheck:isChecked()
  end
  
  local distanceCheck = creatureEditorWindow:recursiveGetChildById('distanceCheck')
  if distanceCheck then
    creatureConfig.keepDistance = distanceCheck:isChecked()
  end
  
  config.creatures[currentSelectedCreature] = creatureConfig
  storage.targetbot = config
  
  logInfo("[TargetBot] Saved settings for: " .. currentSelectedCreature)
end

-- Creature spell management
local creatureSpells = {}

function addCreatureSpell(creatureName, spellWords, options)
  options = options or {}
  
  local creatureConfig = config.creatures[creatureName:lower()]
  if not creatureConfig then return false end
  
  if not creatureConfig.spells then
    creatureConfig.spells = {}
  end
  
  table.insert(creatureConfig.spells, {
    words = spellWords,
    enabled = true,
    minMana = options.minMana or 0,
    minHp = options.minHp or 0,
    cooldown = options.cooldown or 1000
  })
  
  config.creatures[creatureName:lower()] = creatureConfig
  storage.targetbot = config
  
  return true
end

function removeCreatureSpell(creatureName, index)
  local creatureConfig = config.creatures[creatureName:lower()]
  if not creatureConfig or not creatureConfig.spells then return false end
  
  if creatureConfig.spells[index] then
    table.remove(creatureConfig.spells, index)
    config.creatures[creatureName:lower()] = creatureConfig
    storage.targetbot = config
    return true
  end
  
  return false
end

-- Creature item management
function addCreatureItem(creatureName, itemId, options)
  options = options or {}
  
  local creatureConfig = config.creatures[creatureName:lower()]
  if not creatureConfig then return false end
  
  if not creatureConfig.items then
    creatureConfig.items = {}
  end
  
  table.insert(creatureConfig.items, {
    id = itemId,
    enabled = true
  })
  
  config.creatures[creatureName:lower()] = creatureConfig
  storage.targetbot = config
  
  return true
end

-- Import creatures from target area
function importCreaturesFromArea()
  local specs = getSpectators() or {}
  local imported = 0
  
  for _, creature in ipairs(specs) do
    if creature:isMonster() then
      local name = creature:getName():lower()
      
      if not config.creatures[name] then
        TargetBot.addCreature(name)
        imported = imported + 1
      end
    end
  end
  
  updateCreatureCount()
  logInfo(string.format("[TargetBot] Imported %d creatures", imported))
  
  return imported
end

-- Export creatures to text
function exportCreatures()
  local lines = {}
  
  for name, creatureConfig in pairs(config.creatures) do
    local line = string.format("%s|p:%d|d:%d|a:%s|l:%s",
      name,
      creatureConfig.priority or 1,
      creatureConfig.danger or 5,
      creatureConfig.attack and "1" or "0",
      creatureConfig.loot and "1" or "0"
    )
    table.insert(lines, line)
  end
  
  return table.concat(lines, "\n")
end

-- Import creatures from text
function importCreatures(text)
  local count = 0
  
  for line in text:gmatch("[^\r\n]+") do
    local parts = {}
    for part in line:gmatch("[^|]+") do
      table.insert(parts, part)
    end
    
    if #parts >= 1 then
      local name = parts[1]:lower()
      local settings = {
        priority = 1,
        danger = 5,
        attack = true,
        loot = true
      }
      
      for i = 2, #parts do
        local key, value = parts[i]:match("(%w+):(.+)")
        if key and value then
          if key == "p" then settings.priority = tonumber(value) or 1
          elseif key == "d" then settings.danger = tonumber(value) or 5
          elseif key == "a" then settings.attack = value == "1"
          elseif key == "l" then settings.loot = value == "1"
          end
        end
      end
      
      TargetBot.addCreature(name, settings)
      count = count + 1
    end
  end
  
  updateCreatureCount()
  return count
end

-- Presets
local creaturePresets = {
  ["Rotworms"] = {
    {"rotworm", {priority = 1, danger = 2}},
    {"carrion worm", {priority = 2, danger = 3}}
  },
  ["Dragons"] = {
    {"dragon", {priority = 3, danger = 8}},
    {"dragon lord", {priority = 5, danger = 10}},
    {"dragon hatchling", {priority = 1, danger = 3}}
  },
  ["Demons"] = {
    {"demon", {priority = 5, danger = 10}},
    {"hellhound", {priority = 3, danger = 7}},
    {"diabolic imp", {priority = 2, danger = 5}}
  },
  ["Undead"] = {
    {"ghoul", {priority = 1, danger = 3}},
    {"skeleton", {priority = 1, danger = 2}},
    {"ghost", {priority = 2, danger = 4}},
    {"mummy", {priority = 2, danger = 4}},
    {"vampire", {priority = 3, danger = 6}},
    {"necromancer", {priority = 4, danger = 7}}
  }
}

function loadPreset(presetName)
  local preset = creaturePresets[presetName]
  if not preset then return false end
  
  for _, creatureData in ipairs(preset) do
    TargetBot.addCreature(creatureData[1], creatureData[2])
  end
  
  updateCreatureCount()
  return true
end

function getPresetList()
  local names = {}
  for name, _ in pairs(creaturePresets) do
    table.insert(names, name)
  end
  return names
end

-- Public API for creature editor
TargetBot.CreatureEditor = {
  addSpell = addCreatureSpell,
  removeSpell = removeCreatureSpell,
  addItem = addCreatureItem,
  importFromArea = importCreaturesFromArea,
  exportCreatures = exportCreatures,
  importCreatures = importCreatures,
  loadPreset = loadPreset,
  getPresets = getPresetList,
  refresh = refreshCreatureList,
  save = saveCreatureSettings
}

logInfo("[TargetBot] Creature Editor loaded")
