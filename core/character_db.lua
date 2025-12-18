--[[
  ═══════════════════════════════════════════════════════════════════════════
  CHARACTER DATABASE - Per-Character State Management System
  ═══════════════════════════════════════════════════════════════════════════
  
  Purpose:
  - Provides per-CHARACTER storage isolation for multi-client setups
  - Each character gets their own JSON file for module configs
  - Prevents configuration overlap between characters
  
  Architecture:
  - Extends BotDB pattern with character-specific file paths
  - File path: /bot/{config}/nExBot_configs/characters/{charName}/CharacterDB.json
  - Lazy initialization (waits for player to be available)
  - Debounced writes for performance
  
  Usage:
    CharacterDB.get("equipper.rules")           -- Read value
    CharacterDB.set("equipper.rules", {})       -- Write value (auto-saved)
    CharacterDB.getModule("equipper")           -- Get entire module config
    CharacterDB.setModule("equipper", config)   -- Set entire module config
    
  Modules:
    - equipper: EQ Manager rules and settings
    - containers: Container setup configuration
]]--

-- ═══════════════════════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════

local CONFIG = {
  SAVE_DEBOUNCE_MS = 500,    -- Batch saves within this window
  MAX_FILE_SIZE = 5 * 1024 * 1024,  -- 5MB max
  SCHEMA_VERSION = 1,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- SCHEMA DEFINITION (Defaults for each module)
-- ═══════════════════════════════════════════════════════════════════════════

local SCHEMA = {
  version = CONFIG.SCHEMA_VERSION,
  
  -- Macro toggle states (per-character)
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
  
  -- Tool settings (per-character)
  tools = {
    manaTraining = {
      spell = "exura",
      minManaPercent = 80,
    },
    fishing = {
      dropFish = true,
    },
    followPlayer = {
      enabled = false,
      playerName = "",
    },
  },
  
  -- EQ Manager configuration
  equipper = {
    enabled = false,
    rules = {},
    bosses = {},
    activeRule = nil,
  },
  
  -- Container Panel configuration
  containers = {
    purse = true,
    autoMinimize = true,
    autoOpenOnLogin = false,
    sortEnabled = false,
    forceOpen = false,
    renameEnabled = false,
    lootBag = false,
    containerList = {},
    windowHeight = 200,
  },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PURE UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

-- Deep clone a table
local function deepClone(t)
  if type(t) ~= "table" then return t end
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = deepClone(v)
  end
  return copy
end

-- Get value by dot-path
local function getPath(data, path)
  if not data or not path then return nil end
  local parts = {}
  for part in path:gmatch("[^%.]+") do
    table.insert(parts, part)
  end
  local current = data
  for _, key in ipairs(parts) do
    if type(current) ~= "table" then return nil end
    current = current[key]
  end
  return current
end

-- Set value by dot-path
local function setPath(data, path, value)
  if not path then return data end
  local result = deepClone(data or {})
  local parts = {}
  for part in path:gmatch("[^%.]+") do
    table.insert(parts, part)
  end
  local current = result
  for i = 1, #parts - 1 do
    local key = parts[i]
    if type(current[key]) ~= "table" then
      current[key] = {}
    end
    current = current[key]
  end
  current[parts[#parts]] = value
  return result
end

-- Sanitize data against schema
local function sanitizeData(data, schema)
  local result = {}
  for k, v in pairs(schema) do
    if type(v) == "table" and not (v[1] ~= nil) then
      local dataValue = type(data) == "table" and data[k] or nil
      result[k] = sanitizeData(dataValue, v)
    else
      if type(data) == "table" and data[k] ~= nil then
        result[k] = data[k]
      else
        result[k] = v
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

-- Sanitize character name for filesystem
local function sanitizeCharName(name)
  if not name then return "unknown" end
  -- Replace invalid filesystem characters
  return name:gsub("[/\\:*?\"<>|]", "_"):lower()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FILE I/O (Isolated side effects)
-- ═══════════════════════════════════════════════════════════════════════════

local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
local _cache = nil
local _dirty = false
local _initialized = false
local _saveTimer = nil
local _charName = nil
local _basePath = nil
local _dbFile = nil

-- Get character name safely
local function getCharName()
  if _charName then return _charName end
  
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer and localPlayer:getName() then
    _charName = sanitizeCharName(localPlayer:getName())
    return _charName
  end
  return nil
end

-- Build paths for current character
local function buildPaths()
  local charName = getCharName()
  if not charName then return false end
  
  _basePath = "/bot/" .. configName .. "/nExBot_configs/characters/" .. charName .. "/"
  _dbFile = _basePath .. "CharacterDB.json"
  return true
end

-- Ensure directory exists
local function ensureDir()
  if not _basePath then return end
  if not g_resources.directoryExists(_basePath) then
    -- Create parent directories
    local parentPath = "/bot/" .. configName .. "/nExBot_configs/characters/"
    if not g_resources.directoryExists(parentPath) then
      g_resources.makeDir(parentPath)
    end
    g_resources.makeDir(_basePath)
  end
end

-- Read file
local function readFile()
  if not _dbFile then return nil end
  if not g_resources.fileExists(_dbFile) then return nil end
  
  local status, content = pcall(function()
    return g_resources.readFileContents(_dbFile)
  end)
  
  if not status or not content then return nil end
  
  local parseStatus, data = pcall(function()
    return json.decode(content)
  end)
  
  if not parseStatus or type(data) ~= "table" then return nil end
  return data
end

-- Write file
local function writeFile(data)
  if not _dbFile or not data then return false end
  
  local encodeStatus, content = pcall(function()
    return json.encode(data, 2)
  end)
  
  if not encodeStatus or not content then return false end
  if #content > CONFIG.MAX_FILE_SIZE then return false end
  
  ensureDir()
  
  local writeStatus = pcall(function()
    g_resources.writeFileContents(_dbFile, content)
  end)
  
  return writeStatus
end

-- Load data from file
local function load()
  if _initialized and _cache then return _cache end
  
  if not buildPaths() then
    -- Player not available yet, return empty schema but don't cache it
    -- This allows the next call to retry buildPaths
    return deepClone(SCHEMA)
  end
  
  local fileData = readFile()
  _cache = sanitizeData(fileData, SCHEMA)
  _initialized = true
  return _cache
end

-- Schedule debounced save
local _saveScheduled = false

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
-- PUBLIC API: CharacterDB
-- ═══════════════════════════════════════════════════════════════════════════

CharacterDB = {}

-- Check if CharacterDB is ready (player is logged in)
function CharacterDB.isReady()
  return getCharName() ~= nil
end

-- Get current character name
function CharacterDB.getCharacterName()
  return _charName or getCharName()
end

-- Get a value by path
function CharacterDB.get(path)
  local data = load()
  if not path then return data end
  return getPath(data, path)
end

-- Set a value by path (triggers debounced save)
function CharacterDB.set(path, value)
  -- Ensure paths are built before saving
  if not buildPaths() then
    -- Player not available, can't save per-character data
    return false
  end
  
  local data = load()
  _cache = setPath(data, path, value)
  _dirty = true
  scheduleSave()
  return true
end

-- Get with default fallback
function CharacterDB.getOr(path, default)
  local value = CharacterDB.get(path)
  if value == nil then return default end
  return value
end

-- Get entire module configuration
function CharacterDB.getModule(moduleName)
  return CharacterDB.get(moduleName) or deepClone(SCHEMA[moduleName] or {})
end

-- Set entire module configuration
function CharacterDB.setModule(moduleName, config)
  CharacterDB.set(moduleName, config)
end

-- Batch update multiple values
function CharacterDB.batch(updates)
  if type(updates) ~= "table" then return end
  
  local data = load()
  for path, value in pairs(updates) do
    data = setPath(data, path, value)
  end
  _cache = data
  _dirty = true
  scheduleSave()
end

-- Force save immediately
function CharacterDB.save()
  if _cache then
    writeFile(_cache)
    _dirty = false
  end
end

-- Force reload from disk
function CharacterDB.reload()
  _initialized = false
  _cache = nil
  _charName = nil
  load()
end

-- Get the schema
function CharacterDB.getSchema()
  return deepClone(SCHEMA)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MIGRATION: Import from legacy storage
-- ═══════════════════════════════════════════════════════════════════════════

function CharacterDB.migrateFromStorage(moduleName, legacyKey)
  if not storage then return false end
  if not storage[legacyKey] then return false end
  
  -- Check if we already have data (don't overwrite)
  local existing = CharacterDB.get(moduleName)
  if existing and next(existing.rules or existing.containerList or existing) then
    -- Already has data, skip migration
    return false
  end
  
  -- Migrate legacy data
  CharacterDB.setModule(moduleName, deepClone(storage[legacyKey]))
  return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

-- Try to initialize immediately if player is available
if g_game.getLocalPlayer() then
  load()
end

-- Export globally
nExBot = nExBot or {}
nExBot.CharacterDB = CharacterDB
