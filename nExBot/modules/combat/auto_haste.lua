--[[
  NexBot Auto Haste Module
  Automatically casts haste spells based on character vocation
  
  Features:
  - Vocation-based spell selection
  - Mana threshold management
  - Cooldown tracking
  - Configurable toggle and settings
  
  Author: NexBot Team
  Version: 1.0.0
]]

local AutoHaste = {
  enabled = false,
  lastCastTime = 0,
  castCooldown = 6000,  -- 6 seconds in milliseconds
  vocation = nil,
  initialized = false
}

-- Configuration
local CONFIG = {
  enabled = false,
  castThreshold = 80,  -- Mana percentage threshold
  
  -- Vocation spell mapping
  vocations = {
    -- Promoted vocations (best haste spells)
    ["Master Sorcerer"] = { spell = "utani gran hur", minMana = 100, level = 55 },
    ["Elder Druid"]     = { spell = "utani gran hur", minMana = 100, level = 55 },
    ["Royal Paladin"]   = { spell = "utani hur", minMana = 60, level = 14 },
    ["Elite Knight"]    = { spell = "utani hur", minMana = 60, level = 14 },
    
    -- Unpromoted vocations
    ["Sorcerer"] = { spell = "utani hur", minMana = 60, level = 14 },
    ["Druid"]    = { spell = "utani hur", minMana = 60, level = 14 },
    ["Paladin"]  = { spell = "utani hur", minMana = 60, level = 14 },
    ["Knight"]   = { spell = "utani hur", minMana = 60, level = 14 },
  },
  
  -- Haste condition ID for checking if already hasted
  hasteConditionId = 10  -- Tibia haste condition
}

-- Vocation ID to name mapping
local VOCATION_NAMES = {
  [0] = "None",
  [1] = "Knight",
  [2] = "Paladin",
  [3] = "Sorcerer",
  [4] = "Druid",
  [5] = "Master Sorcerer",  -- Some servers use this
  [6] = "Elder Druid",
  [7] = "Royal Paladin",
  [8] = "Elite Knight",
  [9] = "Sorcerer",
  [10] = "Druid",
  [11] = "Knight",
  [12] = "Paladin",
  [13] = "Elite Knight",
  [14] = "Royal Paladin",
  [15] = "Master Sorcerer",
  [16] = "Elder Druid"
}

-- Initialize the Auto Haste module
function AutoHaste:initialize()
  self.lastCastTime = 0
  self.initialized = true
  self.vocation = self:getPlayerVocation()
  return self
end

-- Get player's vocation name
function AutoHaste:getPlayerVocation()
  if not player then return nil end
  
  local vocId = player:getVocation()
  if not vocId then return nil end
  
  return VOCATION_NAMES[vocId] or "Unknown"
end

-- Get vocation configuration
function AutoHaste:getVocationConfig()
  local vocation = self:getPlayerVocation()
  if not vocation then return nil end
  
  return CONFIG.vocations[vocation]
end

-- Check if player currently has haste
function AutoHaste:hasHaste()
  if not player then return true end -- Assume hasted if no player
  
  -- Check for speed boost states
  local states = player:getStates()
  if states and (states.haste or states.strongHaste) then
    return true
  end
  
  -- Alternative: Check by speed comparison
  local baseSpeed = player:getBaseSpeed and player:getBaseSpeed() or 0
  local currentSpeed = player:getSpeed and player:getSpeed() or 0
  
  return currentSpeed > baseSpeed * 1.2  -- 20% speed increase indicates haste
end

-- Check if we should cast haste
function AutoHaste:shouldCast()
  if not self.enabled then return false end
  if not self.initialized then self:initialize() end
  if not player then return false end
  
  -- Check cooldown
  local currentTime = g_clock and g_clock.millis() or (now or 0)
  if (currentTime - self.lastCastTime) < self.castCooldown then
    return false
  end
  
  -- Check if already hasted
  if self:hasHaste() then
    return false
  end
  
  -- Get vocation config
  local vocationConfig = self:getVocationConfig()
  if not vocationConfig then
    return false
  end
  
  -- Check level requirement
  if level and level() < vocationConfig.level then
    return false
  end
  
  -- Check mana
  local currentMana = mana and mana() or 0
  local maxMana = maxmana and maxmana() or 1
  local manaPercentage = (currentMana / maxMana) * 100
  
  -- Must have enough mana percentage and absolute mana
  if manaPercentage < CONFIG.castThreshold then
    return false
  end
  
  if currentMana < vocationConfig.minMana then
    return false
  end
  
  return true
end

-- Cast the appropriate haste spell
function AutoHaste:cast()
  if not self:shouldCast() then
    return false
  end
  
  local vocationConfig = self:getVocationConfig()
  if not vocationConfig then
    return false
  end
  
  -- Cast the spell
  if say then
    say(vocationConfig.spell)
    self.lastCastTime = g_clock and g_clock.millis() or (now or 0)
    
    -- Log if available
    if logInfo then
      logInfo("Auto Haste: Cast " .. vocationConfig.spell)
    end
    
    return true
  end
  
  return false
end

-- Enable auto haste
function AutoHaste:enable()
  self.enabled = true
  if not self.initialized then
    self:initialize()
  end
  return self
end

-- Disable auto haste
function AutoHaste:disable()
  self.enabled = false
  return self
end

-- Toggle auto haste
function AutoHaste:toggle()
  if self.enabled then
    return self:disable()
  else
    return self:enable()
  end
end

-- Check if enabled
function AutoHaste:isEnabled()
  return self.enabled
end

-- Set mana threshold
function AutoHaste:setThreshold(percentage)
  CONFIG.castThreshold = math.max(0, math.min(100, percentage))
  return self
end

-- Get mana threshold
function AutoHaste:getThreshold()
  return CONFIG.castThreshold
end

-- Get current status
function AutoHaste:getStatus()
  return {
    enabled = self.enabled,
    vocation = self:getPlayerVocation(),
    hasHaste = self:hasHaste(),
    threshold = CONFIG.castThreshold,
    spell = self:getVocationConfig() and self:getVocationConfig().spell or "none"
  }
end

-- Register custom vocation spell
function AutoHaste:registerVocation(vocationName, spellConfig)
  if type(vocationName) ~= "string" or type(spellConfig) ~= "table" then
    return false
  end
  
  CONFIG.vocations[vocationName] = {
    spell = spellConfig.spell or "utani hur",
    minMana = spellConfig.minMana or 60,
    level = spellConfig.level or 14
  }
  
  return true
end

-- Create the macro for auto haste
function AutoHaste:createMacro(interval)
  interval = interval or 500
  
  local self_ref = self
  macro(interval, function()
    self_ref:cast()
  end)
end

return AutoHaste
