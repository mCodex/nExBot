--[[
  nExBot - Tibia Bot for OTClientV8 and OpenTibiaBR
  Main Loader Script
  
  This file loads all UI styles and scripts in the correct order.
  Core libraries must be loaded before dependent modules.
]]--

local startTime = os.clock()
local loadTimes = {}

-- Initialize global nExBot namespace if not exists
nExBot = nExBot or {}
nExBot.loadTimes = loadTimes

-- ============================================================================
-- CENTRALIZED PATH RESOLUTION (single source of truth)
-- ============================================================================

local ok, configName = pcall(function()
  return modules.game_bot.contentsPanel.config:getCurrentOption().text
end)
if not ok or not configName or configName == "" then
  warn("[nExBot] Failed to resolve bot config name — cannot initialize.")
  return
end

nExBot.paths = {
  config   = configName,
  base     = "/bot/" .. configName,
  core     = "/bot/" .. configName .. "/core",
  private  = "/bot/" .. configName .. "/private",
}

local P = nExBot.paths  -- shorthand for this file

-- Read version from file or storage fallback
do
  local versionStr = nil
  local ok, content = pcall(g_resources.readFileContents, P.base .. "/version")
  if ok and content then versionStr = content:match("^%s*(.-)%s*$") end
  if not versionStr and storage and storage.updaterInstalledVersion then
    versionStr = storage.updaterInstalledVersion
  end
  nExBot.version = versionStr or "0.0.0"
end

-- Detect mod-overlay: write a probe to user-data and read it back.
-- If the read returns stale/different content, mods are shadowing writes
-- and auto-updates won't take effect.
do
  local probe = P.base .. "/_probe"
  local marker = tostring(os.time())
  pcall(g_resources.writeFileContents, probe, marker)
  local okR, readBack = pcall(g_resources.readFileContents, probe)
  local match = okR and readBack and readBack:match("^%s*(.-)%s*$") == marker
  pcall(g_resources.deleteFile, probe)
  if not match then
    nExBot.isModInstall = true
    warn("[nExBot] Bot is running from a mod folder — auto-updates are disabled.")
    warn("[nExBot] To enable auto-updates, move the bot to the /bot/ folder in your client's data directory (e.g. %AppData% or ~/.local/share).")
  end
end

-- Suppress noisy debug prints by default
nExBot.showDebug = nExBot.showDebug or false
nExBot.suppressDebugPrefixes = nExBot.suppressDebugPrefixes or {"[HealBot]", "[MonsterInspector]"}
nExBot.slowOpInstrumentation = nExBot.slowOpInstrumentation or false

-- NativeProfiler removed: wrapping every callback with pcall+os.clock added
-- significant aggregate overhead during bulk events (z-change floor transitions).

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
  
  local configFiles = g_resources.listDirectoryFiles(P.core, true, false)
  for i = 1, #configFiles do
    local file = configFiles[i]
    local ext = file:split(".")
    local extension = ext[#ext]:lower()
    if extension == "ui" or extension == "otui" then
      -- Ensure full path: if file doesn't start with '/' it's just a filename
      local fullPath = file
      if file:sub(1,1) ~= "/" then
        fullPath = P.core .. "/" .. file
      end
      styleFiles[#styleFiles + 1] = fullPath
    end
  end
  
  -- Load theme.otui first — base classes must exist before child styles
  local themeFile = P.core .. "/theme.otui"
  local themeLoaded = false
  for i = #styleFiles, 1, -1 do
    if styleFiles[i] == themeFile or styleFiles[i]:match("theme%.otui$") then
      table.remove(styleFiles, i)
      themeLoaded = true
    end
  end
  if themeLoaded then
    local ok, err = pcall(function() g_ui.importStyle(themeFile) end)
    if not ok then
      warn("[nExBot] CRITICAL: Failed to load theme.otui: " .. tostring(err))
    end
  end

  local failedStyles = {}
  for i = 1, #styleFiles do
    local ok, err = pcall(function() g_ui.importStyle(styleFiles[i]) end)
    if not ok then
      failedStyles[#failedStyles + 1] = styleFiles[i] .. ": " .. tostring(err)
    end
  end
  
  if #failedStyles > 0 then
    warn("[nExBot] Failed to load " .. #failedStyles .. " style(s): " .. table.concat(failedStyles, "; "))
  end
  
  loadTimes["styles"] = math.floor((os.clock() - styleStart) * 1000)
  loadTimes["_styles_count"] = #styleFiles
  loadTimes["_styles_failed"] = #failedStyles
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
-- Detection runs inline to avoid dependency on adapter loading success.
-- We re-use the same fingerprint logic from acl/init.lua but self-contained.
do
  local detected = false

  -- Try ACL module first (may have been loaded in Phase 1)
  local aclStatus, acl = pcall(function()
    return dofile("/core/acl/init.lua")
  end)
  if aclStatus and acl and acl.getClientType then
    local ctype = acl.getClientType()
    if ctype and ctype ~= 0 then
      nExBot.clientType = ctype
      nExBot.clientName = acl.getClientName()
      nExBot.isOTCv8 = (ctype == 1)
      nExBot.isOpenTibiaBR = (ctype == 2)
      detected = true
    end
  end

  -- Fallback: lightweight inline fingerprint if ACL failed or returned UNKNOWN
  if not detected then
    local isOTBR = false

    -- Check OTBR-only module files on disk
    if g_resources and type(g_resources.fileExists) == "function" then
      local otbrPaths = {
        "/modules/game_cyclopedia/game_cyclopedia.otmod",
        "/modules/game_forge/game_forge.otmod",
        "/modules/game_healthcircle/game_healthcircle.otmod",
      }
      for i = 1, #otbrPaths do
        if g_resources.fileExists(otbrPaths[i]) then
          isOTBR = true
          break
        end
      end
    end

    -- Check OTBR-exclusive APIs (only if moveRaw is absent — moveRaw means OTCv8)
    if not isOTBR then
      local hasMoveRaw = g_game and type(g_game.moveRaw) == "function"
      if not hasMoveRaw then
        if g_game and type(g_game.forceWalk) == "function" then
          isOTBR = true
        end
      end
    end

    if isOTBR then
      nExBot.clientType = 2
      nExBot.clientName = "OpenTibiaBR"
      nExBot.isOTCv8 = false
      nExBot.isOpenTibiaBR = true
    else
      nExBot.clientType = 1
      nExBot.clientName = "OTCv8"
      nExBot.isOTCv8 = true
      nExBot.isOpenTibiaBR = false
    end
  end

  if not nExBot._clientPrinted then
    nExBot._clientPrinted = true
    print("[nExBot] Client detected: " .. tostring(nExBot.clientName) .. " (" .. tostring(nExBot.clientType) .. ")")
  end
end

-- Re-check detection after startup when globals are more likely to exist
local function autoDetectClient(attempt, maxAttempts)
  schedule(1500, function()
    local ok, acl = pcall(function()
      return dofile("/core/acl/init.lua")
    end)
    if ok and acl and acl.refreshDetection then
      local prevType = nExBot.clientType
      local prevName = nExBot.clientName
      local newType = acl.refreshDetection()
      nExBot.clientType = newType
      nExBot.clientName = acl.getClientName()
      nExBot.isOTCv8 = acl.isOTCv8()
      nExBot.isOpenTibiaBR = acl.isOpenTibiaBR()

      if newType ~= prevType or nExBot.clientName ~= prevName then
        print("[nExBot] Client detected (late): " .. tostring(nExBot.clientName) .. " (" .. tostring(newType) .. ")")
      end

      if nExBot.isOpenTibiaBR then
        return
      end

      if attempt >= maxAttempts then
        if acl.getDetectionInfo then
          local info = acl.getDetectionInfo()
          if info and info.signals then
            local keys = {}
            for k, v in pairs(info.signals) do
              if v then
                table.insert(keys, k)
              end
            end
            print("[nExBot] Client signals: signals=" .. table.concat(keys, ","))
          end
        end
        return
      end
    end

    autoDetectClient(attempt + 1, maxAttempts)
  end)
end

autoDetectClient(1, 8)

-- ============================================================================
-- PHASE 2: CONSTANTS
-- ============================================================================
loadCategory("constants", {
  "constants/floor_items",
  "constants/food_items",
  "constants/directions",
}, "/")

-- ============================================================================
-- PHASE 3: UTILS (Core shared utilities)
-- ============================================================================
loadCategory("utils", {
  "utils/shared",
  "utils/ring_buffer",
  "utils/client_helper",
  "utils/safe_creature",
  "utils/weak_cache",
  "utils/vocation_utils",
  "utils/event_debouncer",
  "utils/path_utils",
  "utils/path_strategy",
  "utils/waypoint_navigator",
}, "/")

-- ============================================================================
-- PHASE 4: CORE LIBRARIES (Legacy compatibility)
-- ============================================================================
loadScript("updater", "core")  -- Load updater first so its UI appears above main.lua
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
-- PHASE 5: C++ WIDGET STYLING HOOKS
-- ============================================================================
-- macro() creates BotSwitch widgets and UI.Button() creates BotButton widgets.
-- These C++-created widgets use hardcoded defaults. We apply NxSwitch/NxButton
-- OTUI styles to override the C++ state-based rendering.
do
  local accent = "#3be4d0"
  local muted  = "#a4aece"
  local text   = "#f5f7ff"
  local font   = "verdana-11px-rounded"

  -- All known macro keys from BotDB.registerMacro calls in the codebase
  local macroKeys = {
    "exetaLowHp", "exetaIfPlayer", "exetaAmpRes",
    "autoHaste", "autoMount", "antiRs",
    "holdTarget", "depotWithdraw",
    "castFood", "eatFood", "manaTraining",
    "quiverManager", "exchangeMoney", "autoTradeMsg",
  }

  -- Probe available methods on the widget and apply the best approach
  local function styleMacro(m)
    if not m or not m.button then return end
    local btn = m.button
    -- Probe: dump all available methods for diagnostics (first call only)
    if not nExBot._btnMethodsProbed then
      nExBot._btnMethodsProbed = true
      local methods = {}
      -- Check known OTClient widget methods
      local probes = {
        "setStyle", "applyStyle", "setStyleClass", "updateStyle",
        "setFont", "setColor", "setBackgroundColor", "setOpacity",
        "setHeight", "setWidth", "setOn", "setOff", "isOn",
        "getStyleName", "getClassName", "getStyle",
        "setImageColor", "setIconColor", "setTextColor",
      }
      for _, name in ipairs(probes) do
        local has = (btn[name] ~= nil)
        methods[#methods + 1] = name .. "=" .. tostring(has)
      end
      warn("[nExBot PHASE 5] BotSwitch methods: " .. table.concat(methods, ", "))
    end
    -- Try setStyle("NxSwitch") first — applies full OTUI style incl. $on/$!on
    local ok1 = pcall(function() btn:setStyle("NxSwitch") end)
    if ok1 then return end -- success, no need for manual fallback
    -- Fallback: manual font + color
    pcall(function() btn:setFont(font) end)
    pcall(function() btn:setColor(m:isOn() and accent or muted) end)
  end

  -- Style all macros + wrap onSwitch for future toggles
  local function styleAllMacros()
    if not BotDB or not BotDB.getMacro then
      warn("[nExBot PHASE 5] BotDB.getMacro not available")
      return
    end
    local count = 0
    local missing = {}
    for _, key in ipairs(macroKeys) do
      local m = BotDB.getMacro(key)
      if m then
        styleMacro(m)
        -- Wrap onSwitch to re-apply style on toggle
        local prev = m.onSwitch
        m.onSwitch = function(ref)
          if prev then prev(ref) end
          pcall(function()
            if ref and ref.button then
              -- setStyle persists across state changes, but setColor doesn't
              local okS = pcall(function() ref.button:setStyle("NxSwitch") end)
              if not okS then
                ref.button:setColor(ref:isOn() and accent or muted)
              end
            end
          end)
        end
        count = count + 1
      else
        missing[#missing + 1] = key
      end
    end
    warn("[nExBot PHASE 5] Styled " .. count .. "/" .. #macroKeys .. " macros")
    if #missing > 0 then
      warn("[nExBot PHASE 5] Missing: " .. table.concat(missing, ", "))
    end
  end

  -- Run after all modules have loaded (PHASE 9-11 complete)
  schedule(3000, styleAllMacros)

  -- ── UI.Button (BotButton) styling ─────────────────────────────────────
  if UI and UI.Button then
    local _origBtn = UI.Button
    local newBtn = function(...)
      local btn = _origBtn(...)
      if btn then
        -- Try setStyle("NxButton") first
        local ok = pcall(function() btn:setStyle("NxButton") end)
        if not ok then
          pcall(function() btn:setFont(font) end)
          pcall(function() btn:setColor(text) end)
        end
      end
      return btn
    end
    local ok = pcall(function()
      if rawset then rawset(UI, "Button", newBtn) end
    end)
    if not ok then
      UI.Button = newBtn
    end
  end
end

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

-- ============================================================================
-- STARTUP PROFILING SUMMARY
-- ============================================================================

-- Collect and sort all module load times for analysis
local function getTopSlowestModules(n)
  local modules = {}
  for name, time in pairs(loadTimes) do
    if not name:match("^_") then
      modules[#modules + 1] = { name = name, time = time }
    end
  end
  table.sort(modules, function(a, b) return a.time > b.time end)
  local top = {}
  for i = 1, math.min(n, #modules) do
    top[i] = modules[i]
  end
  return top
end

-- Always show top 5 slowest modules when debug is enabled
if nExBot.showDebug then
  local top5 = getTopSlowestModules(5)
  print("[nExBot] Startup profiling - Top 5 slowest modules:")
  for i, m in ipairs(top5) do
    print(string.format("  %d. %s: %dms", i, m.name, m.time))
  end
  print(string.format("  Total startup time: %dms", totalTime))
end

-- Export profiling helper for runtime analysis
nExBot.getTopSlowestModules = getTopSlowestModules
nExBot.printStartupProfile = function()
  local top = getTopSlowestModules(10)
  print("[nExBot] Startup Profile (Top 10):")
  for i, m in ipairs(top) do
    print(string.format("  %d. %s: %dms", i, m.name, m.time))
  end
  print(string.format("  Total: %dms", loadTimes["_total"] or 0))
end

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
        return g_resources.listDirectoryFiles(P.private, false, false)
    end)
    
    if not status or not items or #items == 0 then
        return
    end
    
    local privateStart = os.clock()
    local luaFiles = collectLuaFiles(P.private, PRIVATE_DOFILE_PATH)
    
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

-- ============================================================================
-- ACTIVATE UNIFIED TICK SYSTEM
-- ============================================================================
-- Start the consolidated tick system now that all modules are loaded
-- This reduces ~30+ separate macro timers to a single 50ms master tick
if UnifiedTick and UnifiedTick.start then
  schedule(100, function()
    UnifiedTick.start()
    if nExBot.showDebug then
      print("[nExBot] UnifiedTick master loop activated")
    end
  end)
end
