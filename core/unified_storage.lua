--[[
  ═══════════════════════════════════════════════════════════════════════════
  UNIFIED STORAGE - Per-Character State Management with EventBus Persistence
  ═══════════════════════════════════════════════════════════════════════════
  
  Version: 1.0.1 (ClientService refactor for cross-client compatibility)
  
  Purpose:
  - Provides COMPLETE per-CHARACTER storage isolation for multi-client setups
  - Each character gets their own JSON file for ALL configurations
  - Prevents configuration overlap between characters running simultaneously
  - Real-time persistence via EventBus (no data loss on crash/disconnect)
  
  Architecture (SOLID Principles):
  - SRP: Single Responsibility - One module for unified character storage
  - OCP: Open/Closed - Extensible via modules without modifying core
  - LSP: Modules use consistent interface
  - ISP: Clean, minimal public API
  - DIP: Depends on abstractions (EventBus), not concretions
  
  Key Features:
  - Character-based isolation (not profile-based)
  - Debounced writes for performance
  - EventBus integration for real-time persistence
  - Automatic migration from legacy profile storage
  - Schema validation with defaults
  - Dirty tracking for efficient saves
  
  File Structure:
    /bot/{config}/nExBot_configs/characters/{charName}/
      ├── UnifiedStorage.json    (all settings)
      ├── CharacterDB.json       (legacy, for backward compat)
      └── backups/
          └── UnifiedStorage_{timestamp}.json
  
  Usage:
    UnifiedStorage.get("targetbot.priority")         -- Read nested value
    UnifiedStorage.set("targetbot.priority", value)  -- Write with auto-save
    UnifiedStorage.getModule("targetbot")            -- Get entire module config
    UnifiedStorage.setModule("targetbot", config)    -- Set entire module config
    UnifiedStorage.batch({...})                      -- Batch updates (single save)
    UnifiedStorage.onReady(function() ... end)       -- Wait for player to be available
]]--

-- ═══════════════════════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════

local CONFIG = {
  SAVE_DEBOUNCE_MS = 300,       -- Batch saves within this window (fast response)
  BACKUP_INTERVAL_MS = 300000,  -- Backup every 5 minutes
  MAX_FILE_SIZE = 10 * 1024 * 1024,  -- 10MB max
  SCHEMA_VERSION = 1,
  MAX_BACKUPS = 5,              -- Keep last 5 backups
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CLIENT SERVICE HELPERS (Cross-client compatibility: OTCv8 / OpenTibiaBR)
-- ═══════════════════════════════════════════════════════════════════════════

-- ClientService helper for cross-client compatibility
local function getClient()
  return ClientService or _G.ClientService
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SCHEMA DEFINITION (Single Source of Truth for All Defaults)
-- ═══════════════════════════════════════════════════════════════════════════

local SCHEMA = {
  version = CONFIG.SCHEMA_VERSION,
  characterName = "",
  createdAt = 0,
  lastModified = 0,
  
  -- Targetbot settings
  targetbot = {
    enabled = false,
    selectedConfig = "",
    priority = {
      enabled = true,
      emergencyHP = 25,
      combatTimeout = 12,
      scanRadius = 2,
    },
    monsterPatterns = {},
    combatActive = false,
    emergency = false,
  },
  
  -- Cavebot settings
  cavebot = {
    enabled = false,
    selectedConfig = "",
    walking = {
      pathSmoothingEnabled = true,
      floorChangeDelay = 200,
      stuckTimeout = 5000,
    },
  },
  
  -- Healbot settings
  healbot = {
    enabled = false,
    rules = {},
  },
  
  -- Attackbot settings
  attackbot = {
    enabled = false,
    rules = {},
  },
  
  -- New healer (friend healer)
  newHealer = {
    enabled = false,
    priorities = {},
    settings = {},
    conditions = {},
    customPlayers = {},
  },
  
  -- Macro toggle states
  macros = {
    exchangeMoney = false,
    autoTradeMsg = false,
    autoHaste = false,
    autoMount = false,
    manaTraining = false,
    eatFood = false,
    antiRs = false,
    holdTarget = false,
    exetaLowHp = false,
    exetaIfPlayer = false,
    depotWithdraw = false,
    quiverManager = false,
    fishing = false,
  },
  
  -- Tool settings
  tools = {
    manaTraining = {
      spell = "exura",
      minManaPercent = 80,
    },
    autoTradeMessage = "nExBot is online!",
    fishing = {
      dropFish = true,
    },
  },
  
  -- Dropper settings
  dropper = {
    enabled = false,
    trashItems = {},
    useItems = {},
    capItems = {},
  },
  
  -- Equipment settings
  equipper = {
    enabled = false,
    rules = {},
    activeRule = nil,
  },
  
  -- Container settings
  containers = {
    purse = true,
    autoMinimize = true,
    autoOpenOnLogin = false,
    containerList = {},
  },
  
  -- Supplies settings
  supplies = {
    eatFromCorpses = false,
    sellItems = {},
  },
  
  -- Combobot settings
  combobot = {
    enabled = false,
    spell = "",
    attack = "",
    follow = "",
  },
  
  -- Analytics
  analytics = {
    showOnStartup = false,
  },
  
  -- Extras
  extras = {
    looting = 40,
    lootLast = false,
  },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PURE UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

-- Deep clone a table (pure function, no side effects)
local function deepClone(obj)
  if type(obj) ~= "table" then return obj end
  local clone = {}
  for k, v in pairs(obj) do
    clone[k] = deepClone(v)
  end
  return clone
end

-- Deep merge two tables (source into target, returns new table)
local function deepMerge(target, source)
  if type(target) ~= "table" then return deepClone(source) end
  if type(source) ~= "table" then return target end
  
  local result = deepClone(target)
  for k, v in pairs(source) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deepMerge(result[k], v)
    else
      result[k] = deepClone(v)
    end
  end
  return result
end

-- Get nested value by dot-separated path (pure function)
local function getPath(obj, path)
  if type(obj) ~= "table" or type(path) ~= "string" then
    return nil
  end
  
  local current = obj
  for key in path:gmatch("[^%.]+") do
    if type(current) ~= "table" then return nil end
    current = current[key]
  end
  return current
end

-- Set nested value by dot-separated path (returns new table, no mutation)
local function setPath(obj, path, value)
  if type(path) ~= "string" then return obj end
  
  local result = deepClone(obj) or {}
  local current = result
  local keys = {}
  
  for key in path:gmatch("[^%.]+") do
    keys[#keys + 1] = key
  end
  
  for i = 1, #keys - 1 do
    local key = keys[i]
    if type(current[key]) ~= "table" then
      current[key] = {}
    end
    current = current[key]
  end
  
  if #keys > 0 then
    current[keys[#keys]] = value
  end
  
  return result
end

-- Sanitize character name for filesystem
local function sanitizeCharName(name)
  if not name then return nil end
  return name:gsub("[/\\:*?\"<>|]", "_"):lower()
end

-- Get timestamp
local function getTimestamp()
  return os.time()
end

-- Sanitize data against schema (ensures proper defaults)
local function sanitizeData(data, schema)
  if type(schema) ~= "table" then
    return data ~= nil and data or schema
  end
  
  local result = {}
  
  -- Copy schema defaults first
  for k, v in pairs(schema) do
    if type(v) == "table" and not (v[1] ~= nil) then -- Not an array
      local dataValue = (type(data) == "table") and data[k] or nil
      result[k] = sanitizeData(dataValue, v)
    else
      if type(data) == "table" and data[k] ~= nil then
        result[k] = data[k]
      else
        result[k] = deepClone(v)
      end
    end
  end
  
  -- Preserve extra keys from data not in schema
  if type(data) == "table" then
    for k, v in pairs(data) do
      if result[k] == nil then
        result[k] = deepClone(v)
      end
    end
  end
  
  return result
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PRIVATE STATE
-- ═══════════════════════════════════════════════════════════════════════════

local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text

local _state = {
  cache = nil,           -- In-memory cache
  dirty = false,         -- Has unsaved changes
  saveScheduled = false, -- Is a save pending
  initialized = false,   -- Has been loaded
  charName = nil,        -- Character name (sanitized)
  basePath = nil,        -- Base path for this character
  dbFile = nil,          -- Full path to UnifiedStorage.json
  readyCallbacks = {},   -- Callbacks waiting for initialization
  backupScheduled = false,
  lastBackup = 0,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- FILE I/O (Isolated side effects)
-- ═══════════════════════════════════════════════════════════════════════════

-- Get character name safely
local function getCharName()
  if _state.charName then return _state.charName end
  
  -- Try global player first
  if player and player.getName then
    local ok, name = pcall(function() return player:getName() end)
    if ok and name then
      _state.charName = sanitizeCharName(name)
      return _state.charName
    end
  end
  
  -- Fallback to g_game.getLocalPlayer() with ClientService
  local Client = getClient()
  local localPlayer = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  if localPlayer and localPlayer:getName() then
    _state.charName = sanitizeCharName(localPlayer:getName())
    return _state.charName
  end
  
  return nil
end

-- Build paths for current character
local function buildPaths()
  local charName = getCharName()
  if not charName then return false end
  
  _state.basePath = "/bot/" .. configName .. "/nExBot_configs/characters/" .. charName .. "/"
  _state.dbFile = _state.basePath .. "UnifiedStorage.json"
  return true
end

-- Ensure directory exists
local function ensureDir()
  if not _state.basePath then return end
  
  local parentPath = "/bot/" .. configName .. "/nExBot_configs/characters/"
  if not g_resources.directoryExists(parentPath) then
    g_resources.makeDir(parentPath)
  end
  
  if not g_resources.directoryExists(_state.basePath) then
    g_resources.makeDir(_state.basePath)
  end
  
  local backupPath = _state.basePath .. "backups/"
  if not g_resources.directoryExists(backupPath) then
    g_resources.makeDir(backupPath)
  end
end

-- Read file from disk
local function readFile()
  if not _state.dbFile then return nil end
  if not g_resources.fileExists(_state.dbFile) then return nil end
  
  local status, content = pcall(function()
    return g_resources.readFileContents(_state.dbFile)
  end)
  
  if not status or not content then return nil end
  
  local parseStatus, data = pcall(function()
    return json.decode(content)
  end)
  
  if not parseStatus or type(data) ~= "table" then return nil end
  return data
end

-- Write file to disk
local function writeFile(data)
  if not _state.dbFile or not data then return false end
  
  -- Update lastModified
  data.lastModified = getTimestamp()
  
  local encodeStatus, content = pcall(function()
    return json.encode(data, 2)
  end)
  
  if not encodeStatus or not content then return false end
  if #content > CONFIG.MAX_FILE_SIZE then 
    warn("[UnifiedStorage] File too large, not saving")
    return false 
  end
  
  ensureDir()
  
  local writeStatus = pcall(function()
    g_resources.writeFileContents(_state.dbFile, content)
  end)
  
  if writeStatus then
    -- Emit save event for debugging/telemetry
    if EventBus then
      EventBus.emit("storage:saved", _state.charName, #content)
    end
  end
  
  return writeStatus
end

-- Create backup
local function createBackup()
  if not _state.cache or not _state.dbFile then return end
  
  local backupPath = _state.basePath .. "backups/"
  local timestamp = os.date("%Y%m%d_%H%M%S")
  local backupFile = backupPath .. "UnifiedStorage_" .. timestamp .. ".json"
  
  local content = json.encode(_state.cache, 2)
  if content then
    pcall(function()
      g_resources.writeFileContents(backupFile, content)
    end)
  end
  
  -- Cleanup old backups
  pcall(function()
    local files = g_resources.listDirectoryFiles(backupPath, false, false)
    if files and #files > CONFIG.MAX_BACKUPS then
      table.sort(files)
      for i = 1, #files - CONFIG.MAX_BACKUPS do
        g_resources.deleteFile(backupPath .. files[i])
      end
    end
  end)
  
  _state.lastBackup = getTimestamp()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CORE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

-- Load data from file
local function load()
  if _state.initialized and _state.cache then return _state.cache end
  
  if not buildPaths() then
    -- Player not available yet, return empty schema but don't cache
    return deepClone(SCHEMA)
  end
  
  local fileData = readFile()
  _state.cache = sanitizeData(fileData, SCHEMA)
  
  -- Set character name in data
  local rawName = nil
  if player and player.getName then
    pcall(function() rawName = player:getName() end)
  end
  if not rawName then
    local Client = getClient()
    local lp = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
    if lp then rawName = lp:getName() end
  end
  _state.cache.characterName = rawName or _state.charName
  
  -- Set createdAt if new
  if not _state.cache.createdAt or _state.cache.createdAt == 0 then
    _state.cache.createdAt = getTimestamp()
  end
  
  _state.initialized = true
  
  -- Fire ready callbacks
  for _, callback in ipairs(_state.readyCallbacks) do
    pcall(callback)
  end
  _state.readyCallbacks = {}
  
  -- Emit initialization event
  if EventBus then
    EventBus.emit("storage:initialized", _state.charName)
  end
  
  return _state.cache
end

-- Schedule debounced save
local function scheduleSave()
  if _state.saveScheduled then return end
  _state.saveScheduled = true
  
  schedule(CONFIG.SAVE_DEBOUNCE_MS, function()
    _state.saveScheduled = false
    if _state.dirty and _state.cache then
      writeFile(_state.cache)
      _state.dirty = false
      
      -- Check if backup is needed
      local now = getTimestamp()
      if now - _state.lastBackup > (CONFIG.BACKUP_INTERVAL_MS / 1000) then
        createBackup()
      end
    end
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MIGRATION FROM LEGACY STORAGE
-- ═══════════════════════════════════════════════════════════════════════════

local function migrateFromLegacy()
  if not _state.cache then return end
  if _state.cache.migratedFromLegacy then return end
  
  local migrated = false
  
  -- Migrate from global storage table
  if storage then
    -- Migrate targetbot settings
    if storage.targetbotEnabled ~= nil then
      _state.cache.targetbot.enabled = storage.targetbotEnabled
      migrated = true
    end
    if storage._configs and storage._configs.targetbot_configs and storage._configs.targetbot_configs.selected then
      _state.cache.targetbot.selectedConfig = storage._configs.targetbot_configs.selected
      migrated = true
    end
    if storage.monsterPatterns then
      _state.cache.targetbot.monsterPatterns = deepClone(storage.monsterPatterns)
      migrated = true
    end
    
    -- Migrate cavebot settings
    if storage._configs and storage._configs.cavebot_configs and storage._configs.cavebot_configs.selected then
      _state.cache.cavebot.selectedConfig = storage._configs.cavebot_configs.selected
      migrated = true
    end
    
    -- Migrate extras
    if storage.extras then
      _state.cache.extras = deepMerge(_state.cache.extras, storage.extras)
      migrated = true
    end
    
    -- Migrate newHealer
    if storage.newHealer then
      _state.cache.newHealer = deepMerge(_state.cache.newHealer, storage.newHealer)
      migrated = true
    end
    
    -- Migrate combobot
    if storage.combobot then
      _state.cache.combobot = deepMerge(_state.cache.combobot, storage.combobot)
      migrated = true
    end
  end
  
  -- Migrate from ProfileStorage if available
  if ProfileStorage and ProfileStorage.getAll then
    local profileData = ProfileStorage.getAll()
    if profileData then
      -- Merge manaTraining
      if profileData.manaTraining then
        _state.cache.tools.manaTraining = deepMerge(_state.cache.tools.manaTraining, profileData.manaTraining)
        migrated = true
      end
      
      -- Merge dropper
      if profileData.dropper then
        _state.cache.dropper = deepMerge(_state.cache.dropper, profileData.dropper)
        migrated = true
      end
      
      -- Merge targetPriority
      if profileData.targetPriority then
        _state.cache.targetbot.priority = deepMerge(_state.cache.targetbot.priority, profileData.targetPriority)
        migrated = true
      end
      
      -- Merge macroStates
      if profileData.macroStates then
        _state.cache.macros = deepMerge(_state.cache.macros, profileData.macroStates)
        migrated = true
      end
    end
  end
  
  -- Migrate from CharacterDB if available
  if CharacterDB and CharacterDB.get then
    local charData = CharacterDB.get()
    if charData then
      -- Merge equipper
      if charData.equipper then
        _state.cache.equipper = deepMerge(_state.cache.equipper, charData.equipper)
        migrated = true
      end
      
      -- Merge containers
      if charData.containers then
        _state.cache.containers = deepMerge(_state.cache.containers, charData.containers)
        migrated = true
      end
      
      -- Merge macros
      if charData.macros then
        _state.cache.macros = deepMerge(_state.cache.macros, charData.macros)
        migrated = true
      end
    end
  end
  
  if migrated then
    _state.cache.migratedFromLegacy = true
    _state.cache.migrationDate = getTimestamp()
    _state.dirty = true
    scheduleSave()
    
    if EventBus then
      EventBus.emit("storage:migrated", _state.charName)
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API: UnifiedStorage
-- ═══════════════════════════════════════════════════════════════════════════

UnifiedStorage = {}

-- Check if UnifiedStorage is ready (player is logged in)
function UnifiedStorage.isReady()
  return getCharName() ~= nil and _state.initialized
end

-- Wait for UnifiedStorage to be ready
function UnifiedStorage.onReady(callback)
  if UnifiedStorage.isReady() then
    pcall(callback)
  else
    table.insert(_state.readyCallbacks, callback)
  end
end

-- Get current character name
function UnifiedStorage.getCharacterName()
  return _state.charName or getCharName()
end

-- Get a value by path (pure read, no side effects)
-- @param path: dot-separated path like "targetbot.priority.enabled"
-- @return: the value or nil
function UnifiedStorage.get(path)
  local data = load()
  if not path then return data end
  return getPath(data, path)
end

-- Set a value by path (triggers debounced save)
-- @param path: dot-separated path like "targetbot.priority.enabled"
-- @param value: the value to set
-- @return: success boolean
function UnifiedStorage.set(path, value)
  if not buildPaths() then
    return false
  end
  
  local data = load()
  _state.cache = setPath(data, path, value)
  _state.dirty = true
  scheduleSave()
  
  -- Emit change event for real-time sync
  if EventBus then
    EventBus.emit("storage:changed", path, value, _state.charName)
  end
  
  return true
end

-- Get with default fallback
-- @param path: dot-separated path
-- @param default: value to return if path is nil
function UnifiedStorage.getOr(path, default)
  local value = UnifiedStorage.get(path)
  if value == nil then return default end
  return value
end

-- Toggle a boolean value
-- @param path: dot-separated path
-- @return: the new value
function UnifiedStorage.toggle(path)
  local current = UnifiedStorage.get(path)
  local newValue = not current
  UnifiedStorage.set(path, newValue)
  return newValue
end

-- Get entire module configuration
function UnifiedStorage.getModule(moduleName)
  return UnifiedStorage.get(moduleName) or deepClone(SCHEMA[moduleName] or {})
end

-- Set entire module configuration
function UnifiedStorage.setModule(moduleName, config)
  return UnifiedStorage.set(moduleName, config)
end

-- Batch update multiple values (single save)
-- @param updates: table of {path = value} pairs
function UnifiedStorage.batch(updates)
  if type(updates) ~= "table" then return end
  
  local data = load()
  for path, value in pairs(updates) do
    data = setPath(data, path, value)
  end
  _state.cache = data
  _state.dirty = true
  scheduleSave()
  
  -- Emit batch change event
  if EventBus then
    EventBus.emit("storage:batchChanged", updates, _state.charName)
  end
end

-- Force save immediately (bypasses debounce)
function UnifiedStorage.save()
  if _state.cache then
    writeFile(_state.cache)
    _state.dirty = false
  end
end

-- Force reload from disk
function UnifiedStorage.reload()
  _state.initialized = false
  _state.cache = nil
  _state.charName = nil
  load()
end

-- Create manual backup
function UnifiedStorage.backup()
  createBackup()
end

-- Get the schema (for debugging)
function UnifiedStorage.getSchema()
  return deepClone(SCHEMA)
end

-- Get storage stats
function UnifiedStorage.getStats()
  return {
    characterName = _state.charName,
    initialized = _state.initialized,
    dirty = _state.dirty,
    lastBackup = _state.lastBackup,
    basePath = _state.basePath,
  }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EVENTBUS INTEGRATION
-- ═══════════════════════════════════════════════════════════════════════════

-- Listen to config changes and persist immediately
local function setupEventBusListeners()
  if not EventBus then return end
  
  -- Listen to targetbot config changes
  EventBus.on("targetbot:configChanged", function(configName)
    UnifiedStorage.set("targetbot.selectedConfig", configName)
  end)
  
  -- Listen to cavebot config changes
  EventBus.on("cavebot:configChanged", function(configName)
    UnifiedStorage.set("cavebot.selectedConfig", configName)
  end)
  
  -- Listen to macro toggles
  EventBus.on("macro:toggled", function(macroName, enabled)
    UnifiedStorage.set("macros." .. macroName, enabled)
  end)
  
  -- Listen to module enable/disable
  EventBus.on("module:toggled", function(moduleName, enabled)
    UnifiedStorage.set(moduleName .. ".enabled", enabled)
  end)
  
  -- Listen to monster pattern updates
  EventBus.on("monsterAI:patternUpdated", function(monsterName, pattern)
    local patterns = UnifiedStorage.get("targetbot.monsterPatterns") or {}
    patterns[monsterName] = pattern
    UnifiedStorage.set("targetbot.monsterPatterns", patterns)
  end)
  
  -- Save on logout/disconnect
  EventBus.on("player:logout", function()
    UnifiedStorage.save()
  end)
  
  -- Periodic backup via EventBus tick
  EventBus.on("tick:slow", function()
    local now = getTimestamp()
    if now - _state.lastBackup > (CONFIG.BACKUP_INTERVAL_MS / 1000) then
      if _state.cache and _state.initialized then
        createBackup()
      end
    end
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

-- Helper to check if local player is available (cross-client compatible)
local function hasLocalPlayer()
  local Client = getClient()
  local localPlayer = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  return localPlayer ~= nil
end

-- Try to initialize immediately if player is available
if hasLocalPlayer() then
  load()
  migrateFromLegacy()
end

-- Setup EventBus listeners after a short delay (allow EventBus to be loaded first)
schedule(100, function()
  setupEventBusListeners()
  
  -- If not initialized yet, try again
  if not _state.initialized and hasLocalPlayer() then
    load()
    migrateFromLegacy()
  end
end)

-- Export to global namespace
nExBot = nExBot or {}
nExBot.UnifiedStorage = UnifiedStorage

-- ═══════════════════════════════════════════════════════════════════════════
-- COMPATIBILITY LAYER
-- Provides backward compatibility with old storage patterns
-- ═══════════════════════════════════════════════════════════════════════════

-- Create a proxy that mirrors UnifiedStorage to the old storage table
-- This allows gradual migration of existing code
local function createStorageProxy()
  if not storage then return end
  
  -- When reading storage.targetbotEnabled, redirect to UnifiedStorage
  local proxyMT = {
    __index = function(t, k)
      -- Check if we have this in UnifiedStorage first
      if k == "targetbotEnabled" then
        return UnifiedStorage.get("targetbot.enabled")
      elseif k == "targetbotCombatActive" then
        return UnifiedStorage.get("targetbot.combatActive")
      elseif k == "targetbotEmergency" then
        return UnifiedStorage.get("targetbot.emergency")
      elseif k == "monsterPatterns" then
        return UnifiedStorage.get("targetbot.monsterPatterns")
      end
      -- Fall back to original storage
      return rawget(t, k)
    end,
    __newindex = function(t, k, v)
      -- Intercept writes and redirect to UnifiedStorage
      if k == "targetbotEnabled" then
        UnifiedStorage.set("targetbot.enabled", v)
      elseif k == "targetbotCombatActive" then
        UnifiedStorage.set("targetbot.combatActive", v)
      elseif k == "targetbotEmergency" then
        UnifiedStorage.set("targetbot.emergency", v)
      elseif k == "monsterPatterns" then
        UnifiedStorage.set("targetbot.monsterPatterns", v)
      else
        -- Write to original storage for non-proxied keys
        rawset(t, k, v)
      end
    end
  }
  
  -- Note: We can't set metatable on storage directly as it may already have one
  -- Instead, we'll update the modules to use UnifiedStorage directly
end

-- Run compatibility setup after initialization
schedule(200, createStorageProxy)
