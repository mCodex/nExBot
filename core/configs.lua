--[[ 
    Configs for modules
    Based on Kondrah storage method  
    
    Multi-client support: Stores per-character profile preferences
    so each character remembers their last active profile.
    
    Profile Storage: All bot input values are stored per-profile,
    allowing different configurations for different hunting spots.
    
    Design Principles Applied:
    - DRY: Shared helper functions for config loading/saving
    - SRP: Character profiles managed in one place
    - KISS: Simple, focused functions
--]]

-- Shared config name (DRY: single source of truth)
BotConfigName = modules.game_bot.contentsPanel.config:getCurrentOption().text
local configName = BotConfigName

-- Directory setup
local function ensureDirectory(path)
  if not g_resources.directoryExists(path) then
    g_resources.makeDir(path)
  end
end

ensureDirectory("/bot/".. configName .."/nExBot_configs/")
for i = 1, 10 do
  ensureDirectory("/bot/".. configName .."/nExBot_configs/profile_"..i)
end

local profile = g_settings.getNumber('profile')

--[[
  Character Profile Manager (SRP: single responsibility for character profiles)
  
  Stores which profile each character was using, so when running
  multiple clients, each character remembers their own settings.
]]
local charProfileFile = "/bot/" .. configName .. "/nExBot_configs/character_profiles.json"
CharacterProfiles = {}

-- Load character profiles mapping
local function loadCharacterProfiles()
  if not g_resources.fileExists(charProfileFile) then return end
  local status, result = pcall(function()
    return json.decode(g_resources.readFileContents(charProfileFile))
  end)
  if status and result then
    CharacterProfiles = result
  end
end
loadCharacterProfiles()

-- Save character profiles mapping
function saveCharacterProfiles()
  local status, result = pcall(function()
    return json.encode(CharacterProfiles, 2)
  end)
  if status then
    g_resources.writeFileContents(charProfileFile, result)
  end
end

-- Get current character name (with safety check)
function getCharacterName()
  -- Try global player first (OTClient bot framework provides this)
  if player and player.getName then
    local status, name = pcall(function() return player:getName() end)
    if status and name then return name end
  end
  -- Fallback to g_game.getLocalPlayer()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:getName() or nil
end

--[[
  EARLY PROFILE RESTORATION
  This runs BEFORE cavebot/targetbot modules load their Config.setup()
  So the storage will have the correct profile when the dropdown initializes
]]
local function earlyRestoreProfiles()
  local charName = getCharacterName()
  if not charName then return end
  
  local charProfiles = CharacterProfiles[charName]
  if not charProfiles then return end
  
  -- Ensure storage._configs exists
  storage._configs = storage._configs or {}
  
  -- Restore CaveBot profile before cavebot.lua loads
  if charProfiles.cavebotProfile and type(charProfiles.cavebotProfile) == "string" then
    local cavebotFile = "/bot/" .. configName .. "/cavebot_configs/" .. charProfiles.cavebotProfile .. ".cfg"
    if g_resources.fileExists(cavebotFile) then
      storage._configs.cavebot_configs = storage._configs.cavebot_configs or {}
      storage._configs.cavebot_configs.selected = charProfiles.cavebotProfile
    end
  end
  
  -- Restore TargetBot profile before targetbot loads
  if charProfiles.targetbotProfile and type(charProfiles.targetbotProfile) == "string" then
    local targetFile = "/bot/" .. configName .. "/targetbot_configs/" .. charProfiles.targetbotProfile .. ".json"
    if g_resources.fileExists(targetFile) then
      storage._configs.targetbot_configs = storage._configs.targetbot_configs or {}
      storage._configs.targetbot_configs.selected = charProfiles.targetbotProfile
    end
  end
end

-- Run early restoration NOW, before cavebot/targetbot modules load
earlyRestoreProfiles()

-- Get character's last used profile for a specific bot
function getCharacterProfile(botType)
  local charName = getCharacterName()
  if not charName then return nil end
  local charProfiles = CharacterProfiles[charName]
  return charProfiles and charProfiles[botType] or nil
end

-- Save character's current profile for a specific bot
function setCharacterProfile(botType, profileNum)
  local charName = getCharacterName()
  if not charName then 
    warn("[nExBot] Cannot save profile - character name not available")
    return 
  end
  CharacterProfiles[charName] = CharacterProfiles[charName] or {}
  CharacterProfiles[charName][botType] = profileNum
  saveCharacterProfiles()
end

--[[
  DRY: Helper function for loading JSON config files
]]
local function loadJsonConfig(filePath, configName)
  if not g_resources.fileExists(filePath) then return {} end
  local status, result = pcall(function() 
    return json.decode(g_resources.readFileContents(filePath)) 
  end)
  if not status then
    onError("Error reading " .. configName .. " config (" .. filePath .. "). Details: " .. result)
    return {}
  end
  return result
end

-- Config file paths
local profilePath = "/bot/" .. configName .. "/nExBot_configs/profile_".. profile .. "/"
local healBotFile = profilePath .. "HealBot.json"
local attackBotFile = profilePath .. "AttackBot.json"
local suppliesFile = profilePath .. "Supplies.json"

-- Load configs using DRY helper
HealBotConfig = loadJsonConfig(healBotFile, "HealBot")
AttackBotConfig = loadJsonConfig(attackBotFile, "AttackBot")
SuppliesConfig = loadJsonConfig(suppliesFile, "Supplies")

-- DRY: Config file mapping (single source of truth)
local configMapping = {
  heal = { file = healBotFile, data = function() return HealBotConfig end },
  atk = { file = attackBotFile, data = function() return AttackBotConfig end },
  supply = { file = suppliesFile, data = function() return SuppliesConfig end }
}

function nExBotConfigSave(file)
  if not file then return end
  
  local config = configMapping[file:lower()]
  if not config then return end

  local status, result = pcall(function() 
    return json.encode(config.data(), 2) 
  end)
  if not status then
    return onError("Error saving " .. file .. " config. Details: " .. result)
  end
  
  if result:len() > 100 * 1024 * 1024 then
    return onError("Config file too large (>100MB), not saved")
  end

  -- Attempt to write file and capture any io errors
  local okWrite, writeErr = pcall(function() g_resources.writeFileContents(config.file, result) end)
  if not okWrite then
    return onError("Error writing " .. file .. " config. Details: " .. tostring(writeErr))
  end

  -- Verify by re-reading the file and comparing the encoded JSON
  local okRead, readResult = pcall(function() return g_resources.readFileContents(config.file) end)
  if okRead and readResult == result then
    return true
  else
    warn("[nExBot] Verification failed saving config '" .. file .. "'")
    return false
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PROFILE STORAGE SYSTEM
-- Unified per-profile storage for all bot input values
-- ═══════════════════════════════════════════════════════════════════════════

--[[
  ProfileStorage - Manages per-profile bot settings
  
  Unlike HealBot/AttackBot which use individual JSON files,
  this handles miscellaneous settings (mana training, dropper, etc.)
  that are stored in a single ToolsConfig.json per profile.
  
  Usage:
    ProfileStorage.get("manaTraining")           -- Get a setting
    ProfileStorage.set("manaTraining", value)    -- Set and auto-save
    ProfileStorage.getDefault("manaTraining")    -- Get default value
]]

ProfileStorage = {}

-- File path for tools config (per-profile)
local toolsConfigFile = profilePath .. "ToolsConfig.json"

-- Default values for all profile-based settings
local DEFAULTS = {
  manaTraining = {
    spell = "exura",
    minManaPercent = 80
  },
  autoTradeMessage = "nExBot is online!",
  autoEquip = {},
  dropper = {
    enabled = false,
    trashItems = { 283, 284, 285 },
    useItems = { 21203, 14758 },
    capItems = { 21175 }
  },
  eatFromCorpses = false,
  cavebotSell = { 23544, 3081 },
  targetPriority = {
    enabled = true,
    emergencyHP = 25,
    combatTimeout = 12,
    scanRadius = 2
  },
  -- Macro toggle states (all default to false/off)
  -- NOTE: These defaults are also defined in bot_database.lua SCHEMA.
  -- This duplication was originally for backward compatibility with legacy code
  -- that read from ProfileStorage before BotDB was loaded. As of loader changes,
  -- bot_database.lua is loaded before configs.lua, so BotDB is available when configs loads.
  -- The duplication is retained for safety and until all legacy code is refactored.
  -- BotDB.getSchema().macros is the authoritative source for new code.
  macroStates = {
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
    fishing = false
  }
}

-- Internal cache for profile settings
local _profileData = nil

-- Load profile tools config
local function loadToolsConfig()
  if _profileData then return _profileData end
  
  if not g_resources.fileExists(toolsConfigFile) then
    _profileData = {}
    return _profileData
  end
  
  local status, result = pcall(function()
    return json.decode(g_resources.readFileContents(toolsConfigFile))
  end)
  
  if status and type(result) == "table" then
    _profileData = result
  else
    _profileData = {}
  end
  
  return _profileData
end

-- Save profile tools config
local function saveToolsConfig()
  if not _profileData then return end
  
  local status, result = pcall(function()
    return json.encode(_profileData, 2)
  end)
  
  if not status then
    warn("[ProfileStorage] Error encoding config: " .. tostring(result))
    return
  end
  
  -- Ensure directory exists before writing
  local dirPath = profilePath
  if not g_resources.directoryExists(dirPath) then
    g_resources.makeDir(dirPath)
  end
  
  g_resources.writeFileContents(toolsConfigFile, result)
end

-- Get a setting value (with default fallback)
function ProfileStorage.get(key)
  local data = loadToolsConfig()
  if data[key] ~= nil then
    return data[key]
  end
  return DEFAULTS[key]
end

-- Set a setting value and auto-save
function ProfileStorage.set(key, value)
  local data = loadToolsConfig()
  data[key] = value
  saveToolsConfig()
end

-- Get default value for a key
function ProfileStorage.getDefault(key)
  return DEFAULTS[key]
end

-- Get all profile data
function ProfileStorage.getAll()
  return loadToolsConfig()
end

-- Force save (for batch updates)
function ProfileStorage.save()
  saveToolsConfig()
end

-- Force reload from disk
function ProfileStorage.reload()
  _profileData = nil
  loadToolsConfig()
end

-- Initialize: Load profile data on startup
loadToolsConfig()

-- Migrate existing storage.* values to ProfileStorage if they exist
-- This ensures backward compatibility with existing configs
local function migrateFromStorage()
  local migrated = false
  local data = loadToolsConfig()
  
  -- Only migrate if ProfileStorage is empty (first run after update)
  local hasData = false
  for k, v in pairs(data) do
    hasData = true
    break
  end
  if hasData then return end
  
  -- Migrate manaTraining
  if storage.manaTraining and type(storage.manaTraining) == "table" then
    data.manaTraining = storage.manaTraining
    migrated = true
  end
  
  -- Migrate autoTradeMessage
  if storage.autoTradeMessage and type(storage.autoTradeMessage) == "string" then
    data.autoTradeMessage = storage.autoTradeMessage
    migrated = true
  end
  
  -- Migrate autoEquip
  if storage.autoEquip and type(storage.autoEquip) == "table" then
    data.autoEquip = storage.autoEquip
    migrated = true
  end
  
  -- Migrate dropper
  if storage.dropper and type(storage.dropper) == "table" then
    data.dropper = storage.dropper
    migrated = true
  end
  
  -- Migrate eatFromCorpses
  if storage.eatFromCorpses ~= nil then
    data.eatFromCorpses = storage.eatFromCorpses
    migrated = true
  end
  
  -- Migrate cavebotSell
  if storage.cavebotSell and type(storage.cavebotSell) == "table" then
    data.cavebotSell = storage.cavebotSell
    migrated = true
  end
  
  if migrated then
    _profileData = data
    saveToolsConfig()
  end
end

migrateFromStorage()