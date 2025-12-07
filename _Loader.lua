--[[
  nExBot - Tibia Bot for OTClientV8
  Main Loader Script
  
  This file loads all UI styles and scripts in the correct order.
  Core libraries must be loaded before dependent modules.
]]--

local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
local CORE_PATH = "/bot/" .. configName .. "/core"

-- Load all OTUI style files from the core directory
local function loadStyles()
  local configFiles = g_resources.listDirectoryFiles(CORE_PATH, true, false)
  for i = 1, #configFiles do
    local file = configFiles[i]
    local ext = file:split(".")
    local extension = ext[#ext]:lower()
    if extension == "ui" or extension == "otui" then
      g_ui.importStyle(file)
    end
  end
end

-- Load a script from the core directory
local function loadScript(name)
  return dofile("/core/" .. name .. ".lua")
end

-- Load styles first
loadStyles()

-- Script loading order - core libraries first, then dependent modules
-- DO NOT change the order of core entries
local scripts = {
  -- Core Libraries (load first, order matters)
  "main",           -- Main initialization
  "items",          -- Item definitions
  "item_classifier", -- Item metadata index
  "lib",            -- Utility library (renamed from vlib)
  "new_cavebot_lib", -- CaveBot library
  "configs",        -- Configuration system
  
  -- Event-Driven Architecture (load before feature modules)
  "event_bus",      -- Centralized event bus (Observer pattern)
  "door_items",     -- Door item database from items.xml
  "global_config",  -- Global tool/door configuration
  "dash_walk",      -- DASH speed walking module (arrow key simulation)
  
  -- Feature Modules
  "extras",         -- Extra settings
  "cavebot",        -- CaveBot integration
  "alarms",         -- Alarm system
  "Conditions",     -- Condition handlers
  "Equipper",       -- Equipment manager
  "pushmax",        -- Push maximizer
  "combo",          -- Combo system
  "HealBot",        -- Healing bot
  "new_healer",     -- Friend healer
  "AttackBot",      -- Attack bot
  
  -- Tools and Utilities
  "ingame_editor",  -- In-game script editor
  "Dropper",        -- Item dropper
  "Containers",     -- Container manager
  "quiver_manager", -- Quiver management
  "quiver_label",   -- Quiver labels
  "tools",          -- Miscellaneous tools
  "antiRs",         -- Anti-RS protection
  "depot_withdraw", -- Depot withdrawal
  "eat_food",       -- Auto eat food
  "equip",          -- Equipment utilities
  "exeta",          -- Exeta res handler
  "analyzer",       -- Session analyzer
  "spy_level",      -- Spy level display
  "supplies",       -- Supply management
  "depositer_config", -- Depositer settings
  "npc_talk",       -- NPC interaction
  "xeno_menu",      -- Xeno-style menu
  "hold_target",    -- Hold target feature
  "cavebot_control_panel" -- CaveBot control panel
}

-- Load all scripts
for i = 1, #scripts do
  loadScript(scripts[i])
end

-- Setup private scripts section
setDefaultTab("Main")
UI.Separator()
UI.Label("Private Scripts:")
UI.Separator()
