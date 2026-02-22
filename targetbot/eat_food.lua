--[[
  nExBot - Eat Food from Corpses (State & Config Module)

  Provides toggle state, food ID lookup, regeneration check, and
  "You are full" server message detection.
  Actual food eating is handled by looting.lua during corpse processing.
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

-- Regeneration thresholds (in deciseconds: 1 sec = 10 ds)
local REGEN_EAT_THRESHOLD = 400   -- Eat when regen < 40 seconds
local REGEN_FULL_THRESHOLD = 600  -- Consider full when regen >= 60 seconds

-- "You are full" detection state
local isPlayerFull = false
local fullDetectedTime = 0
local FULL_COOLDOWN = 30000
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

-- Get player regeneration time (deciseconds). Returns 0 if unavailable.
local function getRegenTime()
  -- Use core module export if available
  if nExBot and nExBot.Food and nExBot.Food.getRegenTime then
    return nExBot.Food.getRegenTime()
  end
  -- Inline fallback
  if player and player.getRegenerationTime then
    local ok, regen = pcall(function() return player:getRegenerationTime() end)
    if ok then return regen end
  end
  if player and player.regeneration then
    local ok, regen = pcall(function() return player:regeneration() end)
    if ok then return regen end
  end
  return 0
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
  -- Primary: check regeneration time (reliable, no server message needed)
  local regen = getRegenTime()
  if regen >= REGEN_FULL_THRESHOLD then
    return true
  end
  -- Secondary: "You are full" server message (fallback for edge cases)
  return isPlayerFull and not hasFullCooldownExpired()
end

-- Should the looting pipeline eat food right now?
-- Combines enabled check, regen threshold, and full detection.
TargetBot.EatFood.shouldEat = function()
  if not eatFromCorpsesEnabled then return false end
  local regen = getRegenTime()
  if regen >= REGEN_EAT_THRESHOLD then return false end
  if isPlayerFull and not hasFullCooldownExpired() then return false end
  return true
end

TargetBot.EatFood.getRegenTime = function()
  return getRegenTime()
end

TargetBot.EatFood.resetFullStatus = function()
  isPlayerFull = false
  fullDetectedTime = 0
end