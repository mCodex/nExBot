--[[
  ============================================================================
  nExBot HealBot Module
  ============================================================================
  
  Advanced self-healing with spell and item management.
  Provides automatic health and mana restoration based on configurable
  thresholds and priorities.
  
  NEW IN V2.0: Uses ItemCache for intelligent potion consumption
  - Works even with closed backpacks
  - Recursive scanning of all nested containers
  - Event-driven cache updates
  
  FEATURES:
  - 5 switchable profiles for different hunting situations
  - Spell-based healing with mana/cooldown checks
  - Potion/item-based healing (using ItemCache)
  - HP% / MP% / flat HP / flat MP threshold triggers
  - Priority ordering (first matching rule executes)
  - Standby modes for coordination with other modules
  
  HOW IT WORKS:
  1. Spells are checked every 100ms (10 times/second)
  2. Items are checked every 250ms (4 times/second) - slower due to exhaustion
  3. Rules are evaluated in order - first matching rule triggers
  4. Standby flags allow other modules to temporarily pause healing
  5. ItemCache provides O(1) potion lookups even in closed backpacks
  
  PERFORMANCE NOTES:
  - Local caching of frequently accessed functions
  - Early returns prevent unnecessary iterations
  - Profile switching is O(1)
  - ItemCache reduces container scanning overhead
  
  USAGE:
    -- Programmatic control
    HealBot.setOn()
    HealBot.setActiveProfile(2)  -- Switch to profile 2
    HealBot.addSpell("exura", "HP%", 0, 70, 20)  -- Heal below 70% HP
    HealBot.standbySpells(true)  -- Pause spell healing
  
  Author: nExBot Team
  Version: 2.0.0 (Optimized)
  Last Updated: December 2025
  
  ============================================================================
]]

--[[
  ============================================================================
  LOCAL CACHING FOR PERFORMANCE
  ============================================================================
]]
local table_insert = table.insert
local pairs = pairs
local tonumber = tonumber
local tostring = tostring

-- Reference to ItemCache (loaded after nExBot init)
local itemCache = nil

-- Lazy load ItemCache
local function getItemCache()
  if itemCache then return itemCache end
  if nExBot and nExBot.ItemCache then
    itemCache = nExBot.ItemCache
    return itemCache
  end
  return nil
end

--[[
  ============================================================================
  MODULE STATE
  ============================================================================
]]

-- Standby flags - allow other modules to pause healing temporarily
local standBySpells = false  -- When true, skip spell healing
local standByItems = false   -- When true, skip item/potion healing

-- UI colors for visual feedback
local red = "#ff0800"
local blue = "#7ef9ff"

--[[
  ============================================================================
  UI SETUP
  ============================================================================
  Creates the HealBot panel in the Regen tab with:
  - On/Off toggle switch
  - Settings button to open configuration window
  - 5 profile buttons for quick switching
  - Profile name display
  ============================================================================
]]
setDefaultTab("Regen")

local healPanelName = "healbot"
local ui = setupUI([[
Panel
  height: 38

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('HealBot')

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
    text: Profile #1
    background: #292A2A
]])
ui:setId(healPanelName)

--[[
  ============================================================================
  CONFIGURATION INITIALIZATION
  ============================================================================
  
  HealBotConfig structure:
  {
    currentHealBotProfile = 1,  -- Active profile (1-5)
    healbot = {
      [1] = {
        enabled = false,
        spellTable = {},
        itemTable = {},
        name = "Profile #1",
        Visible = true,
        Cooldown = true,      -- Check game cooldowns
        Interval = true,
        Conditions = true,    -- Check spell conditions (mana, level, etc.)
        Delay = true,
        MessageDelay = false
      },
      [2] = { ... },
      ...
    }
  }
  ============================================================================
]]

if not HealBotConfig then
  HealBotConfig = {}
end

-- Initialize 5 empty profiles if not present
if not HealBotConfig[healPanelName] or not HealBotConfig[healPanelName][1] or #HealBotConfig[healPanelName] ~= 5 then
  HealBotConfig[healPanelName] = {}
  for i = 1, 5 do
    HealBotConfig[healPanelName][i] = {
      enabled = false,
      spellTable = {},       -- Array of spell rules
      itemTable = {},        -- Array of item/potion rules
      name = "Profile #" .. i,
      Visible = true,
      Cooldown = true,       -- Respect game spell cooldowns
      Interval = true,
      Conditions = true,     -- Respect spell requirements (mana, level)
      Delay = true,
      MessageDelay = false
    }
  end
end

-- Validate current profile index
if not HealBotConfig.currentHealBotProfile or HealBotConfig.currentHealBotProfile == 0 or HealBotConfig.currentHealBotProfile > 5 then
  HealBotConfig.currentHealBotProfile = 1
end

--[[
  ============================================================================
  PROFILE MANAGEMENT
  ============================================================================
]]

-- Reference to current profile's settings (avoids repeated indexing)
local currentSettings

--- Updates currentSettings to point to the active profile
local function setActiveProfile()
  local n = HealBotConfig.currentHealBotProfile
  currentSettings = HealBotConfig[healPanelName][n]
end
setActiveProfile()

--- Updates profile button colors to show active selection
local function activeProfileColor()
  for i = 1, 5 do
    if i == HealBotConfig.currentHealBotProfile then
      ui[i]:setColor("green")
    else
      ui[i]:setColor("white")
    end
  end
end
activeProfileColor()

--- Updates the profile name display
local function setProfileName()
  ui.name:setText(currentSettings.name)
end
setProfileName()

--- Called when switching profiles - updates all UI elements
local function profileChange()
  setActiveProfile()
  activeProfileColor()
  setProfileName()
  ui.title:setOn(currentSettings.enabled)
  nexbotConfigSave("heal")
end

--[[
  ============================================================================
  UI EVENT HANDLERS
  ============================================================================
]]

-- Main on/off toggle
ui.title:setOn(currentSettings.enabled)
ui.title.onClick = function(widget)
  currentSettings.enabled = not currentSettings.enabled
  widget:setOn(currentSettings.enabled)
  nexbotConfigSave("heal")
end

-- Profile selection buttons (1-5)
for i = 1, 5 do
  local button = ui[i]
  button.onClick = function()
    HealBotConfig.currentHealBotProfile = i
    profileChange()
  end
end

--[[
  ============================================================================
  SETTINGS WINDOW
  ============================================================================
]]
local rootWidget = g_ui.getRootWidget()
local healWindow = nil

if rootWidget then
  healWindow = UI.createWindow('HealBotWindow', rootWidget)
  if healWindow then
    healWindow:hide()
    
    -- Save config when window closes
    healWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        nexbotConfigSave("heal")
        if healWindow.healer then healWindow.healer:show() end
        if healWindow.settings then healWindow.settings:hide() end
        if healWindow.settingsButton then healWindow.settingsButton:setText("Settings") end
      end
    end
    
    -- Toggle between healer and settings views
    if healWindow.settingsButton then
      healWindow.settingsButton.onClick = function(widget)
        if healWindow.healer:isVisible() then
          healWindow.healer:hide()
          healWindow.settings:show()
          widget:setText("Back")
        else
          healWindow.healer:show()
          healWindow.settings:hide()
          widget:setText("Settings")
        end
      end
    end
  end
end

-- Open settings window button
ui.settings.onClick = function(widget)
  if healWindow then
    healWindow:show()
    healWindow:raise()
    healWindow:focus()
  end
end

--[[
  ============================================================================
  PERSISTENCE
  ============================================================================
]]

--- Saves HealBot configuration to storage
-- @param configType (string) Type identifier (used for logging)
function nexbotConfigSave(configType)
  storage.HealBotConfig = HealBotConfig
end

-- Load saved configuration if available
if storage.HealBotConfig then
  HealBotConfig = storage.HealBotConfig
  setActiveProfile()
  activeProfileColor()
  setProfileName()
  ui.title:setOn(currentSettings.enabled)
end

--[[
  ============================================================================
  HEALING MACROS
  ============================================================================
  
  Two separate macros for spells and items:
  - Spells: 100ms interval (fast, for emergency heals)
  - Items: 250ms interval (slower, matches potion exhaustion)
  ============================================================================
]]

--- Spell healing macro
-- Iterates through spellTable and casts first matching spell
-- 
-- Rule structure:
-- {
--   enabled = true,
--   spell = "exura vita",
--   origin = "HP%",        -- HP%, MP%, HP, MP
--   minValue = 0,
--   maxValue = 60,
--   cost = 160             -- Mana cost
-- }
macro(100, function()
  -- Early returns for performance
  if standBySpells then return end
  if not currentSettings.enabled then return end
  
  -- Cache player stats (called once per tick, not per rule)
  local currentHp = hppercent()
  local currentMp = manapercent()
  local currentHpFlat = hp()
  local currentMpFlat = mana()
  
  for _, entry in pairs(currentSettings.spellTable) do
    if entry.enabled and entry.cost <= currentMpFlat then
      -- Check spell cooldown and conditions
      if canCast(entry.spell, not currentSettings.Conditions, not currentSettings.Cooldown) then
        local shouldCast = false
        
        -- Check origin-specific condition
        if entry.origin == "HP%" then
          shouldCast = currentHp >= entry.minValue and currentHp <= entry.maxValue
        elseif entry.origin == "MP%" then
          shouldCast = currentMp >= entry.minValue and currentMp <= entry.maxValue
        elseif entry.origin == "HP" then
          shouldCast = currentHpFlat >= entry.minValue and currentHpFlat <= entry.maxValue
        elseif entry.origin == "MP" then
          shouldCast = currentMpFlat >= entry.minValue and currentMpFlat <= entry.maxValue
        end
        
        if shouldCast then
          say(entry.spell)
          return  -- Only one spell per tick
        end
      end
    end
  end
end)

--- Item/Potion healing macro
-- Iterates through itemTable and uses first matching item
-- Uses ItemCache for intelligent potion lookup in closed backpacks
-- 
-- Rule structure:
-- {
--   enabled = true,
--   itemId = 266,          -- Great Health Potion
--   origin = "HP%",        -- HP%, MP%
--   minValue = 0,
--   maxValue = 30
-- }
macro(250, function()
  -- Early returns for performance
  if standByItems then return end
  if not currentSettings.enabled then return end
  
  -- Cache player stats
  local currentHp = hppercent()
  local currentMp = manapercent()
  
  -- Try to get ItemCache for intelligent potion use
  local cache = getItemCache()
  
  for _, entry in pairs(currentSettings.itemTable) do
    if entry.enabled then
      local shouldUse = false
      
      -- Check origin-specific condition
      if entry.origin == "HP%" then
        shouldUse = currentHp >= entry.minValue and currentHp <= entry.maxValue
      elseif entry.origin == "MP%" then
        shouldUse = currentMp >= entry.minValue and currentMp <= entry.maxValue
      end
      
      if shouldUse then
        -- Use ItemCache if available (works with closed backpacks)
        if cache and cache:hasItem(entry.itemId) then
          cache:usePotion(entry.itemId)
        else
          -- Fallback to standard method
          useWith(entry.itemId, player)
        end
        return  -- Only one item per tick
      end
    end
  end
end)

--[[
  ============================================================================
  PUBLIC API
  ============================================================================
  
  Provides programmatic control over HealBot from other modules.
  ============================================================================
]]

HealBot = {
  --- Checks if HealBot is currently enabled
  -- @return (boolean) True if enabled
  isOn = function()
    return currentSettings.enabled
  end,
  
  --- Checks if HealBot is currently disabled
  -- @return (boolean) True if disabled
  isOff = function()
    return not currentSettings.enabled
  end,
  
  --- Disables HealBot
  setOff = function()
    currentSettings.enabled = false
    ui.title:setOn(false)
    nexbotConfigSave("heal")
  end,
  
  --- Enables HealBot
  setOn = function()
    currentSettings.enabled = true
    ui.title:setOn(true)
    nexbotConfigSave("heal")
  end,
  
  --- Gets the current active profile number
  -- @return (number) Profile index (1-5)
  getActiveProfile = function()
    return HealBotConfig.currentHealBotProfile
  end,
  
  --- Switches to a specific profile
  -- @param n (number) Profile number (1-5)
  setActiveProfile = function(n)
    if not n or not tonumber(n) or n < 1 or n > 5 then
      return error("[HealBot] wrong profile parameter! should be 1 to 5, is " .. tostring(n))
    else
      HealBotConfig.currentHealBotProfile = n
      profileChange()
    end
  end,
  
  --- Shows the HealBot settings window
  show = function()
    if healWindow then
      healWindow:show()
      healWindow:raise()
      healWindow:focus()
    end
  end,
  
  --- Programmatically adds a spell rule to current profile
  -- @param spell (string) Spell words to cast
  -- @param origin (string) Trigger type: "HP%", "MP%", "HP", "MP"
  -- @param minValue (number) Minimum threshold
  -- @param maxValue (number) Maximum threshold
  -- @param cost (number) Mana cost of the spell
  addSpell = function(spell, origin, minValue, maxValue, cost)
    table_insert(currentSettings.spellTable, {
      enabled = true,
      spell = spell,
      origin = origin or "HP%",
      minValue = minValue or 0,
      maxValue = maxValue or 60,
      cost = cost or 20
    })
    nexbotConfigSave("heal")
  end,
  
  --- Programmatically adds an item/potion rule to current profile
  -- @param itemId (number) Item ID (e.g., 266 for Great Health Potion)
  -- @param origin (string) Trigger type: "HP%", "MP%"
  -- @param minValue (number) Minimum threshold
  -- @param maxValue (number) Maximum threshold
  addItem = function(itemId, origin, minValue, maxValue)
    table_insert(currentSettings.itemTable, {
      enabled = true,
      itemId = itemId,
      origin = origin or "HP%",
      minValue = minValue or 0,
      maxValue = maxValue or 30
    })
    nexbotConfigSave("heal")
  end,
  
  --- Sets standby mode for spell healing
  -- When true, spell healing is paused (useful during special actions)
  -- @param value (boolean) Standby state
  standbySpells = function(value)
    standBySpells = value
  end,
  
  --- Sets standby mode for item/potion healing
  -- When true, item healing is paused
  -- @param value (boolean) Standby state
  standbyItems = function(value)
    standByItems = value
  end,
  
  --- Gets current profile's settings
  -- @return (table) Current profile configuration
  getSettings = function()
    return currentSettings
  end,
  
  --- Checks if ItemCache is available for intelligent potion use
  -- @return (boolean) True if ItemCache is available
  hasItemCache = function()
    return getItemCache() ~= nil
  end,
  
  --- Gets potion count from ItemCache (works with closed backpacks)
  -- @param itemId (number) Potion item ID
  -- @return (number) Count of potions available
  getPotionCount = function(itemId)
    local cache = getItemCache()
    if cache then
      return cache:getItemCount(itemId)
    end
    return itemAmount(itemId)  -- Fallback
  end
}
