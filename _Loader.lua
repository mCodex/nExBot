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

-- Suppress noisy debug prints by default. Set `nExBot.showDebug = true` in console to allow them.
nExBot.showDebug = nExBot.showDebug or false
nExBot.suppressDebugPrefixes = nExBot.suppressDebugPrefixes or {"[HealBot]", "[MonsterInspector]"}
-- Opt-in slow-op instrumentation. Enable with `nExBot.slowOpInstrumentation = true`.
nExBot.slowOpInstrumentation = nExBot.slowOpInstrumentation or false
local _orig_print = print
print = function(...)
  if nExBot.showDebug then return _orig_print(...) end
  -- Safely inspect first argument without relying on 'select' (may be missing in some environments)
  local first = (...)
  local firstStr = nil
  if type(first) == "string" then
    firstStr = first
  else
    local ok, s = pcall(tostring, first)
    if ok then firstStr = s end
  end
  if firstStr then
    for _, p in ipairs(nExBot.suppressDebugPrefixes) do
      if firstStr:sub(1, #p) == p then
        return
      end
    end
  end
  return _orig_print(...)
end



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
    if type(k) == "number" and k % 1 == 0 and k > 0 then
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

-- Sanitize storage on startup (non-blocking, chunked to avoid freezing)
local function sanitizeStorage()
  if not storage then return end
  local sanitizeStart = os.clock()
  local keys = {}
  for k, v in pairs(storage) do
    if type(v) == "table" then keys[#keys + 1] = k end
  end

  local idx = 1
  local chunkSize = 20 -- process 20 keys per tick
  local function processChunk()
    local stopAt = math.min(idx + chunkSize - 1, #keys)
    for i = idx, stopAt do
      local k = keys[i]
      if type(storage[k]) == 'table' then
        storage[k] = sanitizeTable(storage[k], k, 0)
      end
    end
    idx = stopAt + 1
    if idx <= #keys then
      schedule(50, processChunk)
    else
      loadTimes["sanitize"] = math.floor((os.clock() - sanitizeStart) * 1000)
    end
  end
  -- Start asynchronous sanitization
  schedule(1, processChunk)
end

-- Run sanitizer before loading any modules (non-blocking)
sanitizeStorage()

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

-- List of optional modules that should not show warnings if missing
local OPTIONAL_MODULES = {
  ["HealBot"] = true,
  ["bot_core/init"] = true,
}

-- Load a script with timing and error isolation
local function loadScript(name, category)
  local scriptStart = os.clock()
  local status, result = pcall(function()
    return dofile("/core/" .. name .. ".lua")
  end)
  
  local elapsed = math.floor((os.clock() - scriptStart) * 1000)
  loadTimes[name] = elapsed
  
  if not status then
    local errorMsg = tostring(result)
    nExBot.loadErrors = nExBot.loadErrors or {}
    nExBot.loadErrors[name] = errorMsg
    
    -- Silence warnings for:
    -- 1. Optional modules (listed above)
    -- 2. "not found" errors (file doesn't exist)
    local isOptional = OPTIONAL_MODULES[name]
    local isNotFound = errorMsg:match("not found") or errorMsg:match("No such file")
    
    if not isOptional and not isNotFound then
      warn("[nExBot] Failed to load '" .. name .. "' (" .. elapsed .. "ms): " .. errorMsg)
    end
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
  "safe_call",        -- Safe function call utilities (MUST load after lib)
  "new_cavebot_lib",  -- CaveBot library
  "configs",          -- Configuration system
  "bot_database",     -- Unified database (BotDB) - load AFTER configs
  "character_db",     -- Per-character database (CharacterDB) - for multi-client
})

-- 2. Architecture Layer (Event system, state management)
loadCategory("architecture", {
  "event_bus",            -- Centralized event bus
  "unified_storage",      -- Per-character unified storage (MUST load after event_bus)
  "door_items",           -- Door item database
  "global_config",        -- Global configuration
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
  "ingame_editor",     -- In-game script editor
  "Dropper",           -- Item dropper
  "Containers",        -- Container manager
  "container_opener",  -- Advanced container opening (BFS graph traversal)
  "quiver_manager",    -- Quiver management
  "quiver_label",      -- Quiver labels
  "tools",             -- Miscellaneous tools
  "antiRs",            -- Anti-RS protection
  "depot_withdraw",    -- Depot withdrawal
  "eat_food",          -- Auto eat food
  "equip",             -- Equipment utilities
  "exeta",             -- Exeta res handler
  "outfit_cloner",     -- Outfit cloning via right-click menu
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
-- PRIVATE SCRIPTS AUTO-LOADER
-- ============================================================================
-- Automatically loads user scripts from the /private folder
-- Scripts control their own tab using setDefaultTab() inside the script
-- 
-- Folder Structure:
--   private/
--   ├── my_script.lua
--   ├── hunting/
--   │   └── lure_helper.lua
--   └── utils/
--       └── mana_trainer.lua
--
-- On bot restart, it automatically detects new/removed files.
-- ============================================================================

local PRIVATE_PATH = "/bot/" .. configName .. "/private"
local PRIVATE_DOFILE_PATH = "/private"

-- Recursively collect all .lua files from a directory
local function collectLuaFiles(folderPath, dofileBase, collected)
    collected = collected or {}
    
    local status, items = pcall(function()
        return g_resources.listDirectoryFiles(folderPath, false, false)
    end)
    
    if not status or not items then
        return collected
    end
    
    for i = 1, #items do
        local item = items[i]
        local fullPath = folderPath .. "/" .. item
        local dofilePath = dofileBase .. "/" .. item
        
        -- Check if it's a lua file
        if item:match("%.lua$") then
            collected[#collected + 1] = {
                name = item,
                path = dofilePath
            }
        -- Check if it's a directory (no extension)
        elseif not item:match("%.") then
            -- Try to recurse into it as a folder
            local subStatus, subItems = pcall(function()
                return g_resources.listDirectoryFiles(fullPath, false, false)
            end)
            if subStatus and subItems then
                collectLuaFiles(fullPath, dofilePath, collected)
            end
        end
    end
    
    return collected
end

-- Load private scripts
local function loadPrivateScripts()
    -- Check if private folder exists
    local status, items = pcall(function()
        return g_resources.listDirectoryFiles(PRIVATE_PATH, false, false)
    end)
    
    if not status or not items or #items == 0 then
        return  -- Private folder doesn't exist or is empty
    end
    
    local privateStart = os.clock()
    
    -- Collect all lua files recursively
    local luaFiles = collectLuaFiles(PRIVATE_PATH, PRIVATE_DOFILE_PATH)
    
    if #luaFiles == 0 then
        return
    end
    
    -- Sort for consistent load order
    table.sort(luaFiles, function(a, b) return a.path < b.path end)
    
    local loadedCount = 0
    
    -- Load each script
    for i = 1, #luaFiles do
        local file = luaFiles[i]
        local scriptStart = os.clock()
        
        local loadStatus, err = pcall(function()
            dofile(file.path)
        end)
        
        local elapsed = math.floor((os.clock() - scriptStart) * 1000)
        
        if loadStatus then
            loadedCount = loadedCount + 1
            loadTimes["private:" .. file.name] = elapsed
        else
            warn("[Private] Failed to load '" .. file.path .. "': " .. tostring(err))
            nExBot.loadErrors = nExBot.loadErrors or {}
            nExBot.loadErrors["private:" .. file.name] = tostring(err)
        end
    end
    
    loadTimes["_private_total"] = math.floor((os.clock() - privateStart) * 1000)
    
    if loadedCount > 0 then
        info("[nExBot] Loaded " .. loadedCount .. " private script(s) in " .. loadTimes["_private_total"] .. "ms")
    end
end

-- Run the private scripts loader
loadPrivateScripts()

-- Initialize optional boot diagnostics (safe, tiny, runs only if enabled via ProfileStorage)
-- schedule(100, function() pcall(require, 'utils.boot_diagnostics') end)

-- Return to Main tab
setDefaultTab("Main")