--[[
  AntiRS Protection System
  
  Detects murder warnings and takes protective action:
  - Stops CaveBot and TargetBot
  - Cancels current attack/follow
  - Unequips weapon (if equipped)
  - Forces safe exit
  
  Uses OTClient's g_game.getUnjustifiedPoints() for frag tracking.
]]

setDefaultTab("Tools")

-- State tracking (resets on script reload)
local fragsSinceStart = 0
local lastFragTime = 0
local isExiting = false

-- Configuration
local CONFIG = {
  fragThreshold = 6,        -- Trigger when killsToRs() falls below this
  consecutiveFragLimit = 1, -- Also trigger if X frags in quick succession
  exitDelayMs = 100,        -- Delay before force exit (allows weapon unequip)
}

-- Safe wrapper for killsToRs (defined in lib.lua)
local function getKillsToRedSkull()
  if not g_game or not g_game.getUnjustifiedPoints then
    return 99 -- Safe default if API unavailable
  end
  
  local ok, points = pcall(function()
    return g_game.getUnjustifiedPoints()
  end)
  
  if not ok or not points then return 99 end
  
  return math.min(
    points.killsDayRemaining or 99,
    points.killsWeekRemaining or 99,
    points.killsMonthRemaining or 99
  )
end

-- Safely stop all attacking/following
local function stopCombat()
  if g_game and g_game.cancelAttackAndFollow then
    pcall(function() g_game.cancelAttackAndFollow() end)
  end
end

-- Safely disable bots
local function disableBots()
  if CaveBot and CaveBot.setOff then
    pcall(function() CaveBot.setOff() end)
  end
  if TargetBot and TargetBot.setOff then
    pcall(function() TargetBot.setOff() end)
  end
  if EquipManager and EquipManager.setOff then
    pcall(function() EquipManager.setOff() end)
  end
end

-- Safely unequip left hand item (weapon)
local function unequipWeapon()
  if not g_game or not g_game.equipItemId then return false end
  
  local leftItem = nil
  if getLeft and type(getLeft) == "function" then
    leftItem = getLeft()
  end
  
  if leftItem and leftItem.getId then
    local itemId = leftItem:getId()
    if itemId and itemId > 0 then
      pcall(function() g_game.equipItemId(itemId) end)
      return true
    end
  end
  
  return false
end

-- Force exit game safely
local function forceExitGame()
  if modules and modules.game_interface and modules.game_interface.forceExit then
    pcall(function() modules.game_interface.forceExit() end)
  end
end

-- Main protection action
local function executeAntiRsProtection()
  if isExiting then return end
  isExiting = true
  
  -- Step 1: Stop combat immediately
  stopCombat()
  
  -- Step 2: Disable bots
  disableBots()
  
  -- Step 3: Try to unequip weapon, then exit
  schedule(CONFIG.exitDelayMs, function()
    unequipWeapon()
    schedule(50, function()
      forceExitGame()
    end)
  end)
end

-- Create the macro (empty function - logic is in event handler)
local antiRsMacro = macro(50, "AntiRS & Msg", function() end)
BotDB.registerMacro(antiRsMacro, "antiRs")

-- Listen for murder warning messages
onTextMessage(function(mode, text)
  if not antiRsMacro.isOn() then return end
  if not text then return end
  
  -- Check for murder warning message
  if not text:find("Warning! The murder of") then return end
  
  -- Track frags
  fragsSinceStart = fragsSinceStart + 1
  lastFragTime = now
  
  -- Get current kills remaining to red skull
  local killsLeft = getKillsToRedSkull()
  
  -- Murder detected - logged to storage silently
  
  -- Trigger protection if:
  -- 1. Kills remaining is below threshold OR
  -- 2. Multiple frags in this session (might be rapid killing)
  if killsLeft < CONFIG.fragThreshold or fragsSinceStart > CONFIG.consecutiveFragLimit then
    warn("[AntiRS] PROTECTION TRIGGERED! Stopping all activities and exiting...")
    executeAntiRsProtection()
  end
end)