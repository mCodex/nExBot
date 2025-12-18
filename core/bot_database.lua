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
-- MACRO REGISTRATION SYSTEM (Simplified - KISS Principle)
-- Uses OTClient's NATIVE storage._macros[name] for persistence
-- OTClient already handles this automatically for NAMED macros!
-- ═══════════════════════════════════════════════════════════════════════════

local _registeredMacros = {}

--[[
  Register a macro for automatic state persistence.
  
  IMPORTANT: OTClient already persists state for NAMED macros automatically!
  When you create: macro(500, "Auto Mount", function() ... end)
  OTClient stores state in: storage._macros["Auto Mount"]
  
  This function:
  1. Ensures storage._macros table exists
  2. Explicitly initializes state to false if never set (prevents "start as true")
  3. Applies saved state immediately
  4. Tracks macro for programmatic access
  
  @param macroRef: the macro object from macro()
  @param key: unique key (used for _registeredMacros lookup, not storage)
  @param onEnable: optional callback when macro is turned ON
]]--
function BotDB.registerMacro(macroRef, key, onEnable)
  if not macroRef then return end
  if not storage then return end
  
  -- Ensure storage._macros exists (OTClient creates this automatically, but be safe)
  if not storage._macros then
    storage._macros = {}
  end
  
  -- Get the macro's display name (used by OTClient for persistence)
  local macroName = macroRef.name
  if not macroName or macroName == "" then
    -- For unnamed macros, use the key
    macroName = key
  end
  
  -- CRITICAL: Initialize to false if never set (prevents "start as true" bug)
  -- OTClient sets enabled=true for unnamed macros by default
  if storage._macros[macroName] == nil then
    storage._macros[macroName] = false
  end
  
  -- Get the saved state
  local savedState = (storage._macros[macroName] == true)
  
  -- Apply saved state - this uses OTClient's native setOn which updates storage._macros
  if macroRef.setOn then
    if savedState then
      macroRef:setOn()
    else
      macroRef:setOff()
    end
  end
  
  -- Fire onEnable callback if restoring to ON state
  if savedState and onEnable then
    schedule(100, onEnable)
  end
  
  -- Track registered macro for programmatic access
  _registeredMacros[key] = macroRef
end

-- Get registered macro by key
function BotDB.getMacro(key)
  return _registeredMacros[key]
end

-- Get current state of a registered macro
function BotDB.getMacroState(key)
  local macro = _registeredMacros[key]
  if macro and macro.isOn then
    return macro:isOn()
  end
  return false
end

-- Manually set macro state (for programmatic control)
function BotDB.setMacroState(key, enabled)
  local macro = _registeredMacros[key]
  if not macro then return end
  
  if enabled then
    if macro.setOn then macro:setOn() end
  else
    if macro.setOff then macro:setOff() end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MIGRATION SYSTEM
-- One-time migration from legacy storage keys to new format
-- ═══════════════════════════════════════════════════════════════════════════

local function migrateOldData()
  if not storage then return end
  
  -- Ensure storage._macros exists
  if not storage._macros then
    storage._macros = {}
  end
  
  -- Migrate old *Enabled keys to storage._macros format
  -- Maps: old key -> macro display name
  local legacyMappings = {
    exchangeMoneyEnabled = "Exchange Money",
    autoTradeMsgEnabled = "Send message on trade",
    autoHasteEnabled = "Auto Haste",
    autoMountEnabled = "Auto Mount",
    manaTrainingEnabled = "Mana Training",
    eatFoodEnabled = "Eat Food",
    fishingEnabled = "Fishing",
    followPlayerEnabled = "Follow Player",
  }
  
  for oldKey, macroName in pairs(legacyMappings) do
    -- Only migrate if old key exists and macro state not already set
    if storage[oldKey] ~= nil and storage._macros[macroName] == nil then
      storage._macros[macroName] = (storage[oldKey] == true)
    end
  end
  
  -- Also migrate from macro_* format (previous implementation)
  local macroKeyMappings = {
    macro_exchangeMoney = "Exchange Money",
    macro_autoTradeMsg = "Send message on trade",
    macro_autoHaste = "Auto Haste",
    macro_autoMount = "Auto Mount",
    macro_manaTraining = "Mana Training",
    macro_eatFood = "Eat Food",
    macro_fishing = "Fishing",
    macro_followPlayer = "Follow Player",
  }
  
  for oldKey, macroName in pairs(macroKeyMappings) do
    if storage[oldKey] ~= nil and storage._macros[macroName] == nil then
      storage._macros[macroName] = (storage[oldKey] == true)
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

-- Load BotDB file immediately (for profile-level settings)
load()

-- Run migration for macro states (per-character via storage)
migrateOldData()

-- Export globally
nExBot = nExBot or {}
nExBot.BotDB = BotDB
