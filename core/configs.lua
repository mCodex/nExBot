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
  
  Priority order for profile sources:
  1. UnifiedStorage (per-character, if available)
  2. CharacterProfiles mapping (legacy)
  3. Current storage._configs (fallback)
]]
local function earlyRestoreProfiles()
  local charName = getCharacterName()
  if not charName then return end
  
  -- Ensure storage._configs exists
  storage._configs = storage._configs or {}
  
  -- Try UnifiedStorage first (per-character isolation)
  -- Note: UnifiedStorage may not be loaded yet at this point, so we also check CharacterProfiles
  local targetbotConfig = nil
  local cavebotConfig = nil
  
  -- Check CharacterProfiles mapping
  local charProfiles = CharacterProfiles[charName]
  if charProfiles then
    cavebotConfig = charProfiles.cavebotProfile
    targetbotConfig = charProfiles.targetbotProfile
  end
  
  -- Restore CaveBot profile before cavebot.lua loads
  if cavebotConfig and type(cavebotConfig) == "string" then
    local cavebotFile = "/bot/" .. configName .. "/cavebot_configs/" .. cavebotConfig .. ".cfg"
    if g_resources.fileExists(cavebotFile) then
      storage._configs.cavebot_configs = storage._configs.cavebot_configs or {}
      storage._configs.cavebot_configs.selected = cavebotConfig
    end
  end
  
  -- Restore TargetBot profile before targetbot loads
  if targetbotConfig and type(targetbotConfig) == "string" then
    local targetFile = "/bot/" .. configName .. "/targetbot_configs/" .. targetbotConfig .. ".json"
    if g_resources.fileExists(targetFile) then
      storage._configs.targetbot_configs = storage._configs.targetbot_configs or {}
      storage._configs.targetbot_configs.selected = targetbotConfig
    end
  end
end

-- Run early restoration NOW, before cavebot/targetbot modules load
earlyRestoreProfiles()

-- Late profile restoration from UnifiedStorage (runs after UnifiedStorage is loaded)
local function lateRestoreFromUnifiedStorage()
  if not UnifiedStorage or not UnifiedStorage.isReady or not UnifiedStorage.isReady() then 
    -- Retry after a delay if not ready yet
    schedule(500, lateRestoreFromUnifiedStorage)
    return 
  end
  
  local charName = getCharacterName()
  if not charName then return end
  
  -- Restore from UnifiedStorage (overrides if present)
  local targetbotConfig = UnifiedStorage.get("targetbot.selectedConfig")
  local targetbotEnabled = UnifiedStorage.get("targetbot.enabled")
  local cavebotConfig = UnifiedStorage.get("cavebot.selectedConfig")
  local cavebotEnabled = UnifiedStorage.get("cavebot.enabled")
  
  -- Restore TargetBot config
  if targetbotConfig and type(targetbotConfig) == "string" and targetbotConfig ~= "" then
    local targetFile = "/bot/" .. configName .. "/targetbot_configs/" .. targetbotConfig .. ".json"
    if g_resources.fileExists(targetFile) then
      local currentSelected = storage._configs and storage._configs.targetbot_configs and storage._configs.targetbot_configs.selected
      if currentSelected ~= targetbotConfig then
        -- Set storage so dropdown picks up the right config
        storage._configs = storage._configs or {}
        storage._configs.targetbot_configs = storage._configs.targetbot_configs or {}
        storage._configs.targetbot_configs.selected = targetbotConfig
        
        -- Apply profile change after a small delay
        schedule(200, function()
          if TargetBot and TargetBot.setCurrentProfile then
            pcall(function() 
              TargetBot.setCurrentProfile(targetbotConfig)
              -- Restore saved enabled state (ONLY if not explicitly disabled by user)
              if targetbotEnabled == false and TargetBot.setOff then
                TargetBot.setOff()
              elseif targetbotEnabled == true and TargetBot.setOn and not TargetBot.explicitlyDisabled then
                TargetBot.setOn()
              end
            end)
          end
        end)
      elseif targetbotEnabled ~= nil then
        -- Same config, just restore enabled state
        schedule(200, function()
          if TargetBot then
            -- CRITICAL: Respect explicitlyDisabled flag - user turned it off manually
            if targetbotEnabled == true and TargetBot.setOn and not TargetBot.explicitlyDisabled then
              pcall(function() TargetBot.setOn() end)
            elseif targetbotEnabled == false and TargetBot.setOff then
              pcall(function() TargetBot.setOff() end)
            end
          end
        end)
      end
    end
  end
  
  -- Restore CaveBot config
  if cavebotConfig and type(cavebotConfig) == "string" and cavebotConfig ~= "" then
    local cavebotFile = "/bot/" .. configName .. "/cavebot_configs/" .. cavebotConfig .. ".cfg"
    if g_resources.fileExists(cavebotFile) then
      local currentSelected = storage._configs and storage._configs.cavebot_configs and storage._configs.cavebot_configs.selected
      if currentSelected ~= cavebotConfig then
        -- Set storage so dropdown picks up the right config
        storage._configs = storage._configs or {}
        storage._configs.cavebot_configs = storage._configs.cavebot_configs or {}
        storage._configs.cavebot_configs.selected = cavebotConfig
        
        -- Apply profile change after a small delay
        schedule(200, function()
          if CaveBot and CaveBot.setCurrentProfile then
            pcall(function() 
              CaveBot.setCurrentProfile(cavebotConfig)
              -- Restore saved enabled state
              if cavebotEnabled == false and CaveBot.setOff then
                CaveBot.setOff()
              elseif cavebotEnabled == true and CaveBot.setOn then
                CaveBot.setOn()
              end
            end)
          end
        end)
      elseif cavebotEnabled ~= nil then
        -- Same config, just restore enabled state
        schedule(200, function()
          if CaveBot then
            if cavebotEnabled == true and CaveBot.setOn then
              pcall(function() CaveBot.setOn() end)
            elseif cavebotEnabled == false and CaveBot.setOff then
              pcall(function() CaveBot.setOff() end)
            end
          end
        end)
      end
    end
  end
end

-- Schedule late restoration after UnifiedStorage is loaded
-- Use longer delay to ensure modules are fully initialized
schedule(800, function()
  lateRestoreFromUnifiedStorage()
end)

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
-- Now checks UnifiedStorage first for per-character isolation
function ProfileStorage.get(key)
  -- Check UnifiedStorage first (per-character isolation)
  if UnifiedStorage and UnifiedStorage.isReady and UnifiedStorage.isReady() then
    local unifiedValue = UnifiedStorage.get("tools." .. key)
    if unifiedValue ~= nil then
      return unifiedValue
    end
  end
  
  -- Fall back to profile storage
  local data = loadToolsConfig()
  if data[key] ~= nil then
    return data[key]
  end
  return DEFAULTS[key]
end

-- Set a setting value and auto-save
-- Now also saves to UnifiedStorage for per-character persistence
function ProfileStorage.set(key, value)
  local data = loadToolsConfig()
  data[key] = value
  saveToolsConfig()
  
  -- Also save to UnifiedStorage for character isolation
  if UnifiedStorage and UnifiedStorage.isReady and UnifiedStorage.isReady() then
    UnifiedStorage.set("tools." .. key, value)
  end
  
  -- Emit change event for real-time sync
  if EventBus and EventBus.emitSettingChange then
    EventBus.emitSettingChange("tools." .. key, value)
  end
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