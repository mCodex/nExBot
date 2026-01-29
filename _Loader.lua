--[[
  nExBot - Tibia Bot for OTClientV8 and OpenTibiaBR
  Main Loader Script v2.0 (Restructured Architecture)
  
  This file loads all UI styles and scripts in the correct order.
  Core libraries must be loaded before dependent modules.
  
  Architecture v2.0:
  - features/ - Feature modules (healing, targeting, cavebot, etc.)
  - lib/      - Shared utility libraries (object_pool, player_utils, etc.)
  - tools/    - Tool macros (fishing, auto_haste, etc.)
  - core/     - Legacy core modules (backward compatible)
  - private/  - User private scripts
  
  Optimization Best Practices Applied:
  1. Lazy loading for non-critical modules
  2. Deferred UI creation
  3. Batch style loading
  4. Error isolation per module
  5. Startup timing metrics
  6. Storage sanitization (sparse array prevention)
  7. Client abstraction via ACL pattern
]]--

local startTime = os.clock()
local loadTimes = {}

local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
local CORE_PATH = "/bot/" .. configName .. "/core"
local LIB_PATH = "/bot/" .. configName .. "/lib"
local TOOLS_PATH = "/bot/" .. configName .. "/tools"
local FEATURES_PATH = "/bot/" .. configName .. "/features"

-- Initialize global nExBot namespace if not exists
nExBot = nExBot or {}
nExBot.loadTimes = loadTimes
nExBot.version = "2.0.0"

-- Suppress noisy debug prints by default
nExBot.showDebug = nExBot.showDebug or false
nExBot.suppressDebugPrefixes = nExBot.suppressDebugPrefixes or {"[HealBot]", "[MonsterInspector]"}
nExBot.slowOpInstrumentation = nExBot.slowOpInstrumentation or false

local _orig_print = print
print = function(...)
  if nExBot.showDebug then return _orig_print(...) end
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
  return count > 0 and (maxIndex - minIndex + 1 > count)
end

local function sanitizeTable(tbl, path, depth)
  if type(tbl) ~= "table" or depth > 5 then return tbl end
  
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
  
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      tbl[k] = sanitizeTable(v, path .. "." .. tostring(k), depth + 1)
    end
  end
  
  return tbl
end

local function sanitizeStorage()
  if not storage then return end
  local sanitizeStart = os.clock()
  local keys = {}
  for k, v in pairs(storage) do
    if type(v) == "table" then keys[#keys + 1] = k end
  end

  local idx = 1
  local chunkSize = 20
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
  schedule(1, processChunk)
end

sanitizeStorage()

-- ============================================================================
-- OPTIMIZED STYLE LOADING
-- ============================================================================

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
  
  for i = 1, #styleFiles do
    pcall(function() g_ui.importStyle(styleFiles[i]) end)
  end
  
  loadTimes["styles"] = math.floor((os.clock() - styleStart) * 1000)
end

-- ============================================================================
-- SCRIPT LOADING UTILITIES
-- ============================================================================

local OPTIONAL_MODULES = {
  ["HealBot"] = true,
  ["bot_core/init"] = true,
}

local function loadScript(name, category, basePath)
  basePath = basePath or "/core/"
  local scriptStart = os.clock()
  local status, result = pcall(function()
    return dofile(basePath .. name .. ".lua")
  end)
  
  local elapsed = math.floor((os.clock() - scriptStart) * 1000)
  loadTimes[name] = elapsed
  
  if not status then
    local errorMsg = tostring(result)
    nExBot.loadErrors = nExBot.loadErrors or {}
    nExBot.loadErrors[name] = errorMsg
    
    local isOptional = OPTIONAL_MODULES[name]
    local isNotFound = errorMsg:match("not found") or errorMsg:match("No such file")
    
    if not isOptional and not isNotFound then
      warn("[nExBot] Failed to load '" .. name .. "' (" .. elapsed .. "ms): " .. errorMsg)
    end
    return nil
  end
  
  return result
end

local function loadCategory(categoryName, scripts, basePath)
  local catStart = os.clock()
  for i = 1, #scripts do
    loadScript(scripts[i], categoryName, basePath)
  end
  loadTimes["_category_" .. categoryName] = math.floor((os.clock() - catStart) * 1000)
end

-- ============================================================================
-- LOAD STYLES FIRST
-- ============================================================================
loadStyles()

-- ============================================================================
-- PHASE 1: ACL AND CLIENT ABSTRACTION
-- ============================================================================
loadCategory("acl", {
  "acl/init",
  "client_service",
})

loadCategory("acl_compat", {
  "acl/compat",
})

-- Store client info
do
  local aclStatus, acl = pcall(function()
    return dofile("/core/acl/init.lua")
  end)
  if aclStatus and acl then
    nExBot.clientType = acl.getClientType()
    nExBot.clientName = acl.getClientName()
    nExBot.isOTCv8 = acl.isOTCv8()
    nExBot.isOpenTibiaBR = acl.isOpenTibiaBR()
  else
    nExBot.clientType = 1
    nExBot.clientName = "OTCv8"
    nExBot.isOTCv8 = true
    nExBot.isOpenTibiaBR = false
  end
end

-- ============================================================================
-- PHASE 2: CONSTANTS
-- ============================================================================
loadCategory("constants", {
  "constants/floor_items",
  "constants/food_items",
  "constants/directions",
  "constants/attack_patterns",
})

-- ============================================================================
-- PHASE 3: UTILS (Core shared utilities)
-- ============================================================================
loadCategory("utils", {
  "utils/ring_buffer",
  "utils/client_helper",
  "utils/safe_creature",
  "utils/weak_cache",
  "utils/creature_events",
})

-- ============================================================================
-- PHASE 4: CORE LIBRARIES (Legacy compatibility)
-- ============================================================================
loadCategory("core", {
  "main",
  "items",
  "lib",
  "safe_call",
  "new_cavebot_lib",
  "configs",
  "bot_database",
  "character_db",
})

-- ============================================================================
-- PHASE 6: ARCHITECTURE LAYER
-- ============================================================================
loadCategory("architecture", {
  "event_bus",
  "unified_storage",
  "unified_tick",
  "creature_cache",
  "door_items",
  "global_config",
  "bot_core/init",
})

-- ============================================================================
-- PHASE 8: LEGACY FEATURE MODULES
-- ============================================================================
loadCategory("features_legacy", {
  "extras",
  "cavebot",
  "alarms",
  "Conditions",
  "Equipper",
  "pushmax",
  "combo",
  "HealBot",
  "new_healer",
  "AttackBot",
})

-- ============================================================================
-- PHASE 9: LEGACY TOOLS
-- ============================================================================
loadCategory("tools_legacy", {
  "ingame_editor",
  "Dropper",
  "Containers",
  "container_opener",
  "quiver_manager",
  "quiver_label",
  "tools",
  "antiRs",
  "depot_withdraw",
  "eat_food",
  "equip",
  "exeta",
  "outfit_cloner",
})

-- ============================================================================
-- PHASE 11: ANALYTICS AND UI
-- ============================================================================
loadCategory("analytics", {
  "analyzer",
  "smart_hunt",
  "spy_level",
  "supplies",
  "depositer_config",
  "npc_talk",
  "xeno_menu",
  "hold_target",
  "cavebot_control_panel",
})

-- NOTE: TargetBot scripts are loaded by core/cavebot.lua (in features_legacy phase)
-- to avoid duplicating the loading, we don't load them again here.

-- NOTE: CaveBot scripts are loaded by core/cavebot.lua (in features_legacy phase)
-- to avoid duplicating the loading, we don't load them again here.

-- ============================================================================
-- STARTUP COMPLETE
-- ============================================================================

local totalTime = math.floor((os.clock() - startTime) * 1000)
loadTimes["_total"] = totalTime

if totalTime > 1000 then
  warn("[nExBot] Slow startup: " .. totalTime .. "ms")
  local slowModules = {}
  for name, time in pairs(loadTimes) do
    if time > 100 and not name:match("^_") then
      slowModules[#slowModules + 1] = name .. ":" .. time .. "ms"
    end
  end
  if #slowModules > 0 then
    warn("[nExBot] Slow modules: " .. table.concat(slowModules, ", "))
  end
else
  info("[nExBot v" .. nExBot.version .. "] Loaded in " .. totalTime .. "ms")
end

-- ============================================================================
-- PRIVATE SCRIPTS AUTO-LOADER
-- ============================================================================

local PRIVATE_PATH = "/bot/" .. configName .. "/private"
local PRIVATE_DOFILE_PATH = "/private"

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
        
        if item:match("%.lua$") then
            collected[#collected + 1] = {
                name = item,
                path = dofilePath
            }
        elseif not item:match("%.") then
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

local function loadPrivateScripts()
    local status, items = pcall(function()
        return g_resources.listDirectoryFiles(PRIVATE_PATH, false, false)
    end)
    
    if not status or not items or #items == 0 then
        return
    end
    
    local privateStart = os.clock()
    local luaFiles = collectLuaFiles(PRIVATE_PATH, PRIVATE_DOFILE_PATH)
    
    if #luaFiles == 0 then
        return
    end
    
    table.sort(luaFiles, function(a, b) return a.path < b.path end)
    
    local loadedCount = 0
    
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
        info("[nExBot] Loaded " .. loadedCount .. " private script(s)")
    end
end

loadPrivateScripts()

-- Return to Main tab
setDefaultTab("Main")

-- Export nExBot API summary
nExBot.API = {
  Healing = nExBot.Healing,
  Attacking = nExBot.Attacking,
  Targeting = nExBot.Targeting,
  CaveBot = nExBot.CaveBot,
  Equipment = nExBot.Equipment,
  Analyzer = nExBot.Analyzer,
  SessionManager = nExBot.SessionManager,
  LootTracker = nExBot.LootTracker,
  BossTracker = nExBot.BossTracker,
}
