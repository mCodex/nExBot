--[[ 
    Configs for modules
    Based on Kondrah storage method  
    
    Multi-client support: Stores per-character profile preferences
    so each character remembers their last active profile.
    
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
      info("[nExBot] Pre-loaded CaveBot profile: " .. charProfiles.cavebotProfile .. " for " .. charName)
    end
  end
  
  -- Restore TargetBot profile before targetbot loads
  if charProfiles.targetbotProfile and type(charProfiles.targetbotProfile) == "string" then
    local targetFile = "/bot/" .. configName .. "/targetbot_configs/" .. charProfiles.targetbotProfile .. ".json"
    if g_resources.fileExists(targetFile) then
      storage._configs.targetbot_configs = storage._configs.targetbot_configs or {}
      storage._configs.targetbot_configs.selected = charProfiles.targetbotProfile
      info("[nExBot] Pre-loaded TargetBot profile: " .. charProfiles.targetbotProfile .. " for " .. charName)
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
  info("[nExBot] Saved " .. botType .. " = " .. tostring(profileNum) .. " for " .. charName)
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

  g_resources.writeFileContents(config.file, result)
end