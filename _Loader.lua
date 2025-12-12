--[[
  nExBot - Tibia Bot for OTClientV8
  Main Loader Script (Optimized)
  
  This file loads all UI styles and scripts in the correct order.
  Core libraries must be loaded before dependent modules.
  
  Optimization Best Practices Applied:
  1. Lazy loading for non-critical modules
  2. Deferred UI creation
  3. Batch style loading
  4. Error isolation per module
  5. Startup timing metrics
  6. Storage sanitization (sparse array prevention)
]]--

local startTime = os.clock()
local loadTimes = {}

local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
local CORE_PATH = "/bot/" .. configName .. "/core"

-- Initialize global nExBot namespace if not exists
nExBot = nExBot or {}
nExBot.loadTimes = loadTimes  -- Expose for debugging

-- ============================================================================
-- STORAGE SANITIZER (Fix sparse arrays that prevent saving)
-- ============================================================================

-- Recursively fix sparse arrays in storage
-- Sparse arrays have numeric keys with gaps (e.g., {[1]="a", [5]="b"})
-- JSON serialization fails on these tables
local function isSparseArray(tbl)
  if type(tbl) ~= "table" then return false end
  local minIndex, maxIndex, count = nil, nil, 0
  for k, v in pairs(tbl) do
    if type(k) == "number" and k % 1 == 0 then
      if not minIndex or k < minIndex then minIndex = k end
      if not maxIndex or k > maxIndex then maxIndex = k end
      count = count + 1
    end
  end
  -- It's sparse if numeric keys exist and there are gaps in the sequence
  -- (i.e., not all integer keys between minIndex and maxIndex are present)
  return count > 0 and (maxIndex - minIndex + 1 > count)
end

local function sanitizeTable(tbl, path, depth)
  if type(tbl) ~= "table" or depth > 5 then return tbl end
  
  -- If this table is a sparse array, convert numeric keys to strings
  if isSparseArray(tbl) then
    local fixed = {}
    for k, v in pairs(tbl) do
      if type(k) == "number" then
        fixed[tostring(k)] = sanitizeTable(v, path .. "." .. tostring(k), depth + 1)
      else
        fixed[k] = sanitizeTable(v, path .. "." .. tostring(k), depth + 1)
      end
    end
    warn("[nExBot] Fixed sparse array at: " .. path)
    return fixed
  end
  
  -- Recursively sanitize child tables
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      tbl[k] = sanitizeTable(v, path .. "." .. tostring(k), depth + 1)
    end
  end
  
  return tbl
end

-- Sanitize storage on startup
local function sanitizeStorage()
  if not storage then return end
  local sanitizeStart = os.clock()
  
  for k, v in pairs(storage) do
    if type(v) == "table" then
      storage[k] = sanitizeTable(v, k, 0)
    end
  end
  
  loadTimes["sanitize"] = math.floor((os.clock() - sanitizeStart) * 1000)
end

-- Run sanitizer before loading any modules
pcall(sanitizeStorage)

-- ============================================================================
-- OPTIMIZED STYLE LOADING
-- ============================================================================

-- Cache style files list to avoid repeated directory scans
local function loadStyles()
  local styleStart = os.clock()
  local styleFiles = {}
  
  local configFiles = g_resources.listDirectoryFiles(CORE_PATH, true, false)
  for i = 1, #configFiles do
    local file = configFiles[i]
    local ext = file:split(".")
    local extension = ext[#ext]:lower()
    if extension == "ui" or extension == "otui" then
      styleFiles[#styleFiles + 1] = file
    end
  end
  
  -- Batch load all styles
  for i = 1, #styleFiles do
    pcall(function() g_ui.importStyle(styleFiles[i]) end)
  end
  
  loadTimes["styles"] = math.floor((os.clock() - styleStart) * 1000)
end

-- ============================================================================
-- OPTIMIZED SCRIPT LOADING
-- ============================================================================

-- Load a script with timing and error isolation
local function loadScript(name, category)
  local scriptStart = os.clock()
  local status, result = pcall(function()
    return dofile("/core/" .. name .. ".lua")
  end)
  
  local elapsed = math.floor((os.clock() - scriptStart) * 1000)
  loadTimes[name] = elapsed
  
  if not status then
    warn("[nExBot] Failed to load '" .. name .. "' (" .. elapsed .. "ms): " .. tostring(result))
    return nil
  end
  
  return result
end

-- Load multiple scripts in a category
local function loadCategory(categoryName, scripts)
  local catStart = os.clock()
  for i = 1, #scripts do
    loadScript(scripts[i], categoryName)
  end
  loadTimes["_category_" .. categoryName] = math.floor((os.clock() - catStart) * 1000)
end

-- ============================================================================
-- LOAD STYLES FIRST
-- ============================================================================
loadStyles()

-- ============================================================================
-- SCRIPT CATEGORIES (Ordered by dependency)
-- ============================================================================

-- 1. Core Libraries (MUST load first, order matters)
loadCategory("core", {
  "main",             -- Main initialization
  "items",            -- Item definitions
  "lib",              -- Utility library
  "new_cavebot_lib",  -- CaveBot library
  "configs",          -- Configuration system
  "bot_database",     -- Unified database (BotDB) - load AFTER configs
})

-- 2. Architecture Layer (Event system, state management)
loadCategory("architecture", {
  "event_bus",            -- Centralized event bus
  "door_items",           -- Door item database
  "global_config",        -- Global configuration
  "state_machine",        -- FSM architecture
  "performance_optimizer", -- Performance optimizations
  "combat_intelligence",  -- Combat system
  "bot_core/init",        -- Unified BotCore system
})

-- 3. Feature Modules (Main bot features)
loadCategory("features", {
  "extras",       -- Extra settings
  "cavebot",      -- CaveBot integration
  "alarms",       -- Alarm system
  "Conditions",   -- Condition handlers
  "Equipper",     -- Equipment manager
  "pushmax",      -- Push maximizer
  "combo",        -- Combo system
  "HealBot",      -- Healing bot
  "new_healer",   -- Friend healer
  "AttackBot",    -- Attack bot
})

-- 4. Tools and Utilities (Non-critical, can be deferred)
loadCategory("tools", {
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
})

-- 5. Analytics and UI (Can be loaded last)
loadCategory("analytics", {
  "analyzer",       -- Session analyzer
  "smart_hunt",     -- Hunt analytics
  "spy_level",      -- Spy level display
  "supplies",       -- Supply management
  "depositer_config", -- Depositer settings
  "npc_talk",       -- NPC interaction
  "xeno_menu",      -- Xeno-style menu
  "hold_target",    -- Hold target feature
  "cavebot_control_panel", -- CaveBot control panel
})

-- ============================================================================
-- STARTUP COMPLETE
-- ============================================================================

local totalTime = math.floor((os.clock() - startTime) * 1000)
loadTimes["_total"] = totalTime

-- Log startup performance (only if slow)
if totalTime > 1000 then
  warn("[nExBot] Slow startup: " .. totalTime .. "ms")
  -- Find slowest modules
  local slowModules = {}
  for name, time in pairs(loadTimes) do
    if time > 100 and not name:match("^_") then
      slowModules[#slowModules + 1] = name .. ":" .. time .. "ms"
    end
  end
  if #slowModules > 0 then
    warn("[nExBot] Slow modules: " .. table.concat(slowModules, ", "))
  end
end

-- ============================================================================
-- PRIVATE SCRIPTS SECTION
-- ============================================================================

setDefaultTab("Main")
UI.Separator()
UI.Label("Private Scripts:")
UI.Separator()