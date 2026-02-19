--[[
  nExBot - Eat Food from Corpses (State & Config Module)

  Provides toggle state, food ID lookup, and "You are full" detection.
  Actual food eating is handled by looting.lua during normal corpse processing.
]]

-- Use centralized food items constants
if not FoodItems then
  dofile("constants/food_items.lua")
end

TargetBot.EatFood = {}

-- Use centralized food IDs from FoodItems constants
local FOOD_IDS = FoodItems.FOOD_IDS

-- State variables
local eatFromCorpsesEnabled = false

-- "You are full" detection state
local isPlayerFull = false
local fullDetectedTime = 0
local FULL_COOLDOWN = 60000
local FULL_MESSAGES = {
  "you are full",
  "you're full",
  "voce esta cheio",
  "estas lleno",
}

local function isFullMessage(text)
  if not text then return false end
  local lowerText = text:lower()
  for _, pattern in ipairs(FULL_MESSAGES) do
    if lowerText:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

local nowMs = nExBot.Shared.nowMs

-- Listen for server messages to detect "You are full"
onTextMessage(function(mode, text)
  if not eatFromCorpsesEnabled then return end
  if isFullMessage(text) then
    isPlayerFull = true
    fullDetectedTime = nowMs()
  end
end)

local function hasFullCooldownExpired()
  return (nowMs() - fullDetectedTime) > FULL_COOLDOWN
end

-- Profile storage helpers
local function getProfileSetting(key)
  if ProfileStorage then
    return ProfileStorage.get(key)
  end
  return storage[key]
end

local function setProfileSetting(key, value)
  if ProfileStorage then
    ProfileStorage.set(key, value)
  else
    storage[key] = value
  end
end

-- Initialize from profile storage
eatFromCorpsesEnabled = getProfileSetting("eatFromCorpses") or false

TargetBot.EatFood.isEnabled = function()
  return eatFromCorpsesEnabled
end

TargetBot.EatFood.setEnabled = function(enabled)
  eatFromCorpsesEnabled = enabled
  setProfileSetting("eatFromCorpses", enabled)
end

TargetBot.EatFood.toggle = function()
  eatFromCorpsesEnabled = not eatFromCorpsesEnabled
  setProfileSetting("eatFromCorpses", eatFromCorpsesEnabled)
  return eatFromCorpsesEnabled
end

TargetBot.EatFood.getFoodIds = function()
  return FOOD_IDS
end

TargetBot.EatFood.isFood = function(itemId)
  return FOOD_IDS[itemId] == true
end

TargetBot.EatFood.isPlayerFull = function()
  return isPlayerFull and not hasFullCooldownExpired()
end

TargetBot.EatFood.resetFullStatus = function()
  isPlayerFull = false
  fullDetectedTime = 0
end