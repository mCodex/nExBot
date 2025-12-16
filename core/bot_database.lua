--[[
  ═══════════════════════════════════════════════════════════════════════════
  BOT DATABASE - Unified State Management System
  ═══════════════════════════════════════════════════════════════════════════
  
  Architecture Principles:
  - SRP: Single Responsibility - One module for ALL persistent state
  - DRY: Single source of truth for all bot settings
  - SOLID: Open for extension, closed for modification
  - Pure Functions: No side effects in getters
  - Performance: Lazy loading, batch saves, memory caching
  
  Design:
  - All state in ONE JSON file per profile (BotDatabase.json)
  - Synchronous reads (cached in memory)
  - Debounced writes (batched for performance)
  - Schema validation with defaults
  - Migration support for old configs
  
  Usage:
    BotDB.get("macros.autoMount")           -- Read value
    BotDB.set("macros.autoMount", true)     -- Write value (auto-saved)
    BotDB.toggle("macros.autoMount")        -- Toggle boolean
    BotDB.registerMacro(macroRef, "autoMount")  -- Setup macro with persistence
]]--

-- ═══════════════════════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════

local CONFIG = {
  SAVE_DEBOUNCE_MS = 500,    -- Batch saves within this window
  MAX_FILE_SIZE = 10 * 1024 * 1024,  -- 10MB max
  SCHEMA_VERSION = 1,        -- For future migrations
}

-- ═══════════════════════════════════════════════════════════════════════════
-- SCHEMA DEFINITION (Single Source of Truth for All Defaults)
-- ═══════════════════════════════════════════════════════════════════════════

local SCHEMA = {
  version = CONFIG.SCHEMA_VERSION,
  
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
  autoEquip = {},
  
  -- Supply settings
  supplies = {
    eatFromCorpses = false,
    sellItems = {},
  },
  
  -- Analytics settings
  analytics = {
    showOnStartup = false,
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

-- Get nested value by dot-separated path (pure function)
-- Example: getPath({a = {b = 1}}, "a.b") => 1
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
-- Example: setPath({a = {b = 1}}, "a.b", 2) => {a = {b = 2}}
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

-- Validate and sanitize data against schema (ensures no sparse arrays)
local function sanitizeData(data, schema)
  if type(schema) ~= "table" then
    return data ~= nil and data or schema
  end
  
  local result = {}
  
  -- Copy all schema keys with defaults
  for k, v in pairs(schema) do
    if type(v) == "table" then
      local dataValue = (type(data) == "table") and data[k] or nil
      result[k] = sanitizeData(dataValue, v)
    else
      -- Use data value if exists, otherwise schema default
      if type(data) == "table" and data[k] ~= nil then
        result[k] = data[k]
      else
        result[k] = v
      end
    end
  end
  
  -- Preserve any extra keys from data that aren't in schema
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
-- FILE I/O (Isolated side effects)
-- ═══════════════════════════════════════════════════════════════════════════

-- Get config paths
local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
local profileNum = g_settings.getNumber('profile') or 1
local basePath = "/bot/" .. configName .. "/nExBot_configs/profile_" .. profileNum .. "/"
local dbFile = basePath .. "BotDatabase.json"

-- Ensure directory exists
local function ensureDir()
  if not g_resources.directoryExists(basePath) then
    g_resources.makeDir(basePath)
  end
end

-- Read file (isolated I/O)
local function readFile()
  if not g_resources.fileExists(dbFile) then
    return nil
  end
  
  local status, content = pcall(function()
    return g_resources.readFileContents(dbFile)
  end)
  
  if not status or not content then
    return nil
  end
  
  local parseStatus, data = pcall(function()
    return json.decode(content)
  end)
  
  if not parseStatus or type(data) ~= "table" then
    return nil
  end
  
  return data
end

-- Write file (isolated I/O)
local function writeFile(data)
  local status, content = pcall(function()
    return json.encode(data, 2)
  end)
  
  if not status or #content > CONFIG.MAX_FILE_SIZE then
    return false
  end
  
  ensureDir()
  
  local writeStatus = pcall(function()
    g_resources.writeFileContents(dbFile, content)
  end)
  
  return writeStatus
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DATABASE STATE (Module-private state)
-- ═══════════════════════════════════════════════════════════════════════════

local _cache = nil           -- In-memory cache
local _dirty = false         -- Has unsaved changes
local _saveScheduled = false -- Is a save pending
local _initialized = false   -- Has been loaded

-- ═══════════════════════════════════════════════════════════════════════════
-- INTERNAL FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

-- Load database into cache (only once)
local function load()
  if _initialized then return _cache end
  
  local rawData = readFile()
  _cache = sanitizeData(rawData, SCHEMA)
  _initialized = true
  
  return _cache
end

-- Schedule a debounced save
local function scheduleSave()
  if _saveScheduled then return end
  _saveScheduled = true
  
  schedule(CONFIG.SAVE_DEBOUNCE_MS, function()
    _saveScheduled = false
    if _dirty and _cache then
      writeFile(_cache)
      _dirty = false
    end
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API: BotDB
-- ═══════════════════════════════════════════════════════════════════════════

BotDB = {}

-- Get a value by path (pure read, no side effects)
-- @param path: dot-separated path like "macros.autoMount"
-- @return: the value or nil
function BotDB.get(path)
  local data = load()
  if not path then return data end
  return getPath(data, path)
end

-- Set a value by path (triggers debounced save)
-- @param path: dot-separated path like "macros.autoMount"
-- @param value: the value to set
function BotDB.set(path, value)
  local data = load()
  _cache = setPath(data, path, value)
  _dirty = true
  scheduleSave()
end

-- Toggle a boolean value
-- @param path: dot-separated path
-- @return: the new value
function BotDB.toggle(path)
  local current = BotDB.get(path)
  local newValue = not current
  BotDB.set(path, newValue)
  return newValue
end

-- Get with default fallback
-- @param path: dot-separated path
-- @param default: value to return if path is nil
function BotDB.getOr(path, default)
  local value = BotDB.get(path)
  if value == nil then return default end
  return value
end

-- Batch update multiple values (single save)
-- @param updates: table of {path = value} pairs
function BotDB.batch(updates)
  if type(updates) ~= "table" then return end
  
  local data = load()
  for path, value in pairs(updates) do
    data = setPath(data, path, value)
  end
  _cache = data
  _dirty = true
  scheduleSave()
end

-- Force save immediately (bypasses debounce)
function BotDB.save()
  if _cache then
    writeFile(_cache)
    _dirty = false
  end
end

-- Force reload from disk
function BotDB.reload()
  _initialized = false
  _cache = nil
  load()
end

-- Get the schema (for documentation/validation)
function BotDB.getSchema()
  return deepClone(SCHEMA)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MACRO REGISTRATION SYSTEM
-- Intercept setOn/setOff to persist state changes
-- ═══════════════════════════════════════════════════════════════════════════

local _registeredMacros = {}

-- Register a macro for automatic persistence
-- @param macroRef: the macro object from macro()
-- @param key: unique key like "autoMount" (maps to macros.autoMount)
-- @param onEnable: optional callback when macro is turned ON
function BotDB.registerMacro(macroRef, key, onEnable)
  if not macroRef then return end
  
  local path = "macros." .. key
  local savedState = BotDB.get(path) == true
  
  -- Check legacy storage for migration
  local legacyKey = key .. "Enabled"
  if storage and storage[legacyKey] ~= nil then
    savedState = storage[legacyKey] == true
    BotDB.set(path, savedState)
    storage[legacyKey] = nil
  end

  -- Special-case: persist manaTraining macro enabled state per-character (storage)
  local usePerCharacterStorage = (key == "manaTraining")
  if usePerCharacterStorage then
    if storage and storage.manaTrainingEnabled ~= nil then
      savedState = storage.manaTrainingEnabled == true
    else
      -- fallback to BotDB stored value
      savedState = BotDB.get(path) == true
    end
  end
  
  local initialized = false
  local originalSetOn = macroRef.setOn
  local originalSetOff = macroRef.setOff
  
  -- Wrap setOn with state persistence (only if original exists)
  if originalSetOn then
    macroRef.setOn = function(val)
      originalSetOn(val)
      
      if initialized then
        local newState = (val ~= false)
        if usePerCharacterStorage and storage then
          storage.manaTrainingEnabled = newState
        else
          BotDB.set(path, newState)
        end
        if newState and onEnable then
          schedule(50, onEnable)
        end
      end
    end
  end
  
  -- Wrap setOff with state persistence (only if original exists)
  if originalSetOff then
    macroRef.setOff = function(val)
      originalSetOff(val)
      
      if initialized then
        if usePerCharacterStorage and storage then
          storage.manaTrainingEnabled = false
        else
          BotDB.set(path, false)
        end
      end
    end
  end
  
  -- Set initial state
  -- Set initialized immediately to avoid race condition
  -- (user could toggle within 100ms of registration)
  initialized = true
  if originalSetOn then
    originalSetOn(savedState)
  end
  _registeredMacros[key] = macroRef
end

-- Get registered macro by key
function BotDB.getMacro(key)
  return _registeredMacros[key]
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MIGRATION SYSTEM
-- Migrate from old storage systems
-- ═══════════════════════════════════════════════════════════════════════════

local function migrateOldData()
  -- Only migrate if database is fresh (no existing data)
  if g_resources.fileExists(dbFile) then return end
  
  local migrated = {}
  
  -- Migrate from global storage
  if storage then
    -- Migrate macro states
    local macroKeys = {
      "exchangeMoneyEnabled", "autoTradeMsgEnabled", "autoHasteEnabled",
      "autoMountEnabled", "manaTrainingEnabled", "eatFoodEnabled",
      "antiRsEnabled", "holdTargetEnabled", "exetaLowHpEnabled",
      "exetaIfPlayerEnabled", "depotWithdrawEnabled", "quiverManagerEnabled",
      "fishingEnabled"
    }
    
    for _, legacyKey in ipairs(macroKeys) do
      if storage[legacyKey] ~= nil then
        local key = legacyKey:gsub("Enabled$", "")
        migrated["macros." .. key] = storage[legacyKey] == true
      end
    end
    
    -- Migrate tool settings
    if storage.manaTraining then
      migrated["tools.manaTraining"] = storage.manaTraining
    end
    if storage.autoTradeMessage then
      migrated["tools.autoTradeMessage"] = storage.autoTradeMessage
    end
    if storage.dropper then
      migrated["dropper"] = storage.dropper
    end
    if storage.autoEquip then
      migrated["autoEquip"] = storage.autoEquip
    end
  end
  
  -- Apply migrations (check if migrated has any keys)
  local hasMigrations = false
  for _ in pairs(migrated) do
    hasMigrations = true
    break
  end
  
  if hasMigrations then
    BotDB.batch(migrated)
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

-- Load immediately on module load (synchronous)
load()

-- Run migration
migrateOldData()

-- Migrate existing BotDB manaTraining macro state to per-character storage
-- This moves persistent macro-enabled state into `storage.manaTrainingEnabled`
-- so each character controls whether mana training is enabled independently.
local function migrateManaTrainingMacroToStorage()
  if not storage then return end
  -- If per-character flag already set, nothing to do
  if storage.manaTrainingEnabled ~= nil then return end
  local botdbState = BotDB.get("macros.manaTraining")
  if botdbState ~= nil then
    storage.manaTrainingEnabled = botdbState and true or false
    -- Optionally clear BotDB value to avoid duplication; keep it for safety
    -- BotDB.set("macros.manaTraining", nil)
  end
end
migrateManaTrainingMacroToStorage()

-- Ensure the manaTraining macro picks up per-character storage state if already registered.
schedule(200, function()
  if not storage then return end
  local macroRef = BotDB.getMacro and BotDB.getMacro("manaTraining") or nil
  if macroRef and macroRef.setOn and storage.manaTrainingEnabled ~= nil then
    -- Apply per-character enabled state immediately
    macroRef.setOn(storage.manaTrainingEnabled)
  end
end)

-- Export globally
nExBot = nExBot or {}
nExBot.BotDB = BotDB
