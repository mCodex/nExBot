--[[
  nExBot - Tibia Bot for OTClientV8
  Main Loader Script
  
  This file loads all UI styles and scripts in the correct order.
  Core libraries must be loaded before dependent modules.
  
  HOT-RELOAD SYSTEM:
  - nExBot.reloadModule("module_name") - Reload a specific module
  - nExBot.reloadAll() - Reload all non-core modules
  - nExBot.listModules() - List all loaded modules
]]--

local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
local CORE_PATH = "/bot/" .. configName .. "/core"

-- Initialize global nExBot namespace if not exists
nExBot = nExBot or {}

-- ============================================
-- MODULE HOT-RELOAD SYSTEM (Feature 33)
-- ============================================

-- Track loaded modules for hot-reload
local loadedModules = {}
local moduleLoadOrder = {}
local coreModules = {
  ["main"] = true,
  ["items"] = true,
  ["item_classifier"] = true,
  ["lib"] = true,
  ["new_cavebot_lib"] = true,
  ["configs"] = true,
  ["event_bus"] = true,
  ["door_items"] = true,
  ["global_config"] = true,
  ["state_machine"] = true,
}

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

-- Safe timing function (works before main.lua loads)
local function getTime()
  return (now and now) or (os.clock() * 1000)
end

-- Load a script from the core directory with tracking
local function loadScript(name, isReload)
  local startTime = getTime()
  local status, result = pcall(function()
    return dofile("/core/" .. name .. ".lua")
  end)
  
  local loadTime = getTime() - startTime
  
  if status then
    loadedModules[name] = {
      loaded = true,
      loadTime = loadTime,
      lastReload = getTime(),
      isCore = coreModules[name] or false,
      result = result
    }
    
    if not isReload then
      table.insert(moduleLoadOrder, name)
    end
    
    if isReload then
      info("[HotReload] Module '" .. name .. "' reloaded successfully (" .. loadTime .. "ms)")
    end
    
    return result
  else
    warn("[HotReload] Failed to load module '" .. name .. "': " .. tostring(result))
    loadedModules[name] = {
      loaded = false,
      error = result,
      lastAttempt = getTime()
    }
    return nil
  end
end

-- Reload a specific module by name
nExBot.reloadModule = function(moduleName)
  if not moduleName or type(moduleName) ~= "string" then
    warn("[HotReload] Invalid module name")
    return false
  end
  
  moduleName = moduleName:lower()
  
  -- Check if module exists
  if not loadedModules[moduleName] then
    warn("[HotReload] Module '" .. moduleName .. "' not found. Use nExBot.listModules() to see available modules.")
    return false
  end
  
  -- Warn about core modules
  if coreModules[moduleName] then
    warn("[HotReload] Warning: Reloading core module '" .. moduleName .. "' may cause instability. Proceeding anyway...")
  end
  
  -- Attempt reload
  info("[HotReload] Reloading module: " .. moduleName)
  local result = loadScript(moduleName, true)
  
  -- Fire event for listeners
  if nExBot.EventBus and nExBot.EventBus.emit then
    nExBot.EventBus.emit("module:reloaded", { name = moduleName, success = result ~= nil })
  end
  
  return result ~= nil
end

-- Reload all non-core modules
nExBot.reloadAll = function(includeCore)
  info("[HotReload] Reloading all " .. (includeCore and "" or "non-core ") .. "modules...")
  local reloaded = 0
  local failed = 0
  
  for _, moduleName in ipairs(moduleLoadOrder) do
    if includeCore or not coreModules[moduleName] then
      if nExBot.reloadModule(moduleName) then
        reloaded = reloaded + 1
      else
        failed = failed + 1
      end
    end
  end
  
  info("[HotReload] Reload complete: " .. reloaded .. " succeeded, " .. failed .. " failed")
  return reloaded, failed
end

-- List all loaded modules
nExBot.listModules = function()
  info("[HotReload] Loaded modules:")
  for _, moduleName in ipairs(moduleLoadOrder) do
    local info_data = loadedModules[moduleName]
    local status = info_data.loaded and "✓" or "✗"
    local core = info_data.isCore and " [CORE]" or ""
    local time = info_data.loadTime and (" (" .. info_data.loadTime .. "ms)") or ""
    print("  " .. status .. " " .. moduleName .. core .. time)
  end
  return loadedModules
end

-- Get module info
nExBot.getModuleInfo = function(moduleName)
  return loadedModules[moduleName:lower()]
end

-- Check if module is loaded
nExBot.isModuleLoaded = function(moduleName)
  local info_data = loadedModules[moduleName:lower()]
  return info_data and info_data.loaded or false
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
  "state_machine",  -- Finite State Machine architecture (Feature 32)
  "performance_optimizer", -- Performance optimizations (Features 24-27)
  "combat_intelligence",   -- Combat AI system (Features 11-15)
  
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
  "smart_hunt",     -- Smart hunting analytics (supply prediction, route optimization)
  "spy_level",      -- Spy level display
  "supplies",       -- Supply management
  "depositer_config", -- Depositer settings
  "npc_talk",       -- NPC interaction
  "xeno_menu",      -- Xeno-style menu
  "hold_target",    -- Hold target feature
  "cavebot_control_panel" -- CaveBot control panel
}

-- Load all scripts with tracking
for i = 1, #scripts do
  loadScript(scripts[i], false)
end

-- Setup private scripts section
setDefaultTab("Main")
UI.Separator()
UI.Label("Private Scripts:")
UI.Separator()

-- ============================================
-- MACRO PERFORMANCE MONITOR (Performance Fix)
-- ============================================

-- Global macro performance tracking
nExBot.macroStats = {
  slowWarnings = 0,
  lastSlowWarning = 0,
  performanceLog = {}
}

-- Monitor for slow macros and provide warnings
macro(5000, "Macro Performance Monitor", function()
  local currentTime = now
  
  -- Reset slow warning counter every 5 minutes
  if currentTime - nExBot.macroStats.lastSlowWarning > 300000 then
    nExBot.macroStats.slowWarnings = 0
    nExBot.macroStats.lastSlowWarning = currentTime
  end
  
  -- If we have too many slow warnings, suggest optimizations
  if nExBot.macroStats.slowWarnings > 10 then
    warn("[nExBot] High macro load detected. Consider disabling unused features or increasing macro intervals.")
    nExBot.macroStats.slowWarnings = 0 -- Reset to avoid spam
  end
end)
