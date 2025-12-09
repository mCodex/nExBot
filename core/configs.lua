--[[ 
    Configs for modules
    Based on Kondrah storage method  
    
    Multi-client support: Stores per-character profile preferences
    so each character remembers their last active profile.
--]]
local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text

-- make nExBot config dir
if not g_resources.directoryExists("/bot/".. configName .."/nExBot_configs/") then
  g_resources.makeDir("/bot/".. configName .."/nExBot_configs/")
end

-- make profile dirs
for i=1,10 do
  local path = "/bot/".. configName .."/nExBot_configs/profile_"..i
  if not g_resources.directoryExists(path) then
    g_resources.makeDir(path)
  end
end

local profile = g_settings.getNumber('profile')

--[[
  Character Profile Manager
  
  Stores which profile each character was using, so when running
  multiple clients, each character remembers their own settings.
]]
local charProfileFile = "/bot/" .. configName .. "/nExBot_configs/character_profiles.json"
CharacterProfiles = {} -- {characterName = {healProfile = 1, attackProfile = 1, supplyProfile = 1}}

-- Load character profiles mapping
if g_resources.fileExists(charProfileFile) then
  local status, result = pcall(function()
    return json.decode(g_resources.readFileContents(charProfileFile))
  end)
  if status and result then
    CharacterProfiles = result
  end
end

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
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer then
    return localPlayer:getName()
  end
  return "Unknown"
end

-- Get character's last used profile for a specific bot
function getCharacterProfile(botType)
  local charName = getCharacterName()
  if CharacterProfiles[charName] and CharacterProfiles[charName][botType] then
    return CharacterProfiles[charName][botType]
  end
  return 1 -- default to profile 1
end

-- Save character's current profile for a specific bot
function setCharacterProfile(botType, profileNum)
  local charName = getCharacterName()
  if not CharacterProfiles[charName] then
    CharacterProfiles[charName] = {}
  end
  CharacterProfiles[charName][botType] = profileNum
  saveCharacterProfiles()
end

HealBotConfig = {}
local healBotFile = "/bot/" .. configName .. "/nExBot_configs/profile_".. profile .. "/HealBot.json"
AttackBotConfig = {}
local attackBotFile = "/bot/" .. configName .. "/nExBot_configs/profile_".. profile .. "/AttackBot.json"
SuppliesConfig = {}
local suppliesFile = "/bot/" .. configName .. "/nExBot_configs/profile_".. profile .. "/Supplies.json"


--healbot
if g_resources.fileExists(healBotFile) then
    local status, result = pcall(function() 
      return json.decode(g_resources.readFileContents(healBotFile)) 
    end)
    if not status then
      return onError("Error while reading config file (" .. healBotFile .. "). To fix this problem you can delete HealBot.json. Details: " .. result)
    end
    HealBotConfig = result
end

--attackbot
if g_resources.fileExists(attackBotFile) then
    local status, result = pcall(function() 
      return json.decode(g_resources.readFileContents(attackBotFile)) 
    end)
    if not status then
      return onError("Error while reading config file (" .. attackBotFile .. "). To fix this problem you can delete HealBot.json. Details: " .. result)
    end
    AttackBotConfig = result
end

--supplies
if g_resources.fileExists(suppliesFile) then
    local status, result = pcall(function() 
      return json.decode(g_resources.readFileContents(suppliesFile)) 
    end)
    if not status then
      return onError("Error while reading config file (" .. suppliesFile .. "). To fix this problem you can delete HealBot.json. Details: " .. result)
    end
    SuppliesConfig = result
end

function nExBotConfigSave(file)
  -- file can be either
  --- heal
  --- atk
  --- supply
  local configFile 
  local configTable
  if not file then return end
  file = file:lower()
  if file == "heal" then
      configFile = healBotFile
      configTable = HealBotConfig
  elseif file == "atk" then
      configFile = attackBotFile
      configTable = AttackBotConfig
  elseif file == "supply" then
      configFile = suppliesFile
      configTable = SuppliesConfig
  else
    return
  end

  local status, result = pcall(function() 
    return json.encode(configTable, 2) 
  end)
  if not status then
    return onError("Error while saving config. it won't be saved. Details: " .. result)
  end
  
  if result:len() > 100 * 1024 * 1024 then
    return onError("config file is too big, above 100MB, it won't be saved")
  end

  g_resources.writeFileContents(configFile, result)
end