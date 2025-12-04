--[[
  nExBot Dynamic Spell Selector
  Intelligently selects optimal spell/rune based on situation
  
  Features:
  - AOE vs Single target selection
  - Mana efficiency calculation
  - Target count optimization
  - Cooldown awareness
  - Resource availability check
  
  Author: nExBot Team
  Version: 1.0.0
]]

local DynamicSpellSelector = {
  enabled = false,
  spellRegistry = {},
  lastCast = {},
  playerVocation = nil
}

-- Spell effect types
local SPELL_TYPES = {
  SINGLE = "single",
  AOE = "aoe",
  BEAM = "beam",
  WAVE = "wave",
  RUNE = "rune",
  SUPPORT = "support"
}

-- Default spell database
local DEFAULT_SPELLS = {
  -- Knight spells
  ["exori"] = {
    type = SPELL_TYPES.AOE,
    range = 1,
    manaCost = 115,
    avgDamage = 200,
    cooldown = 2000,
    vocations = {1, 11}
  },
  ["exori gran"] = {
    type = SPELL_TYPES.AOE,
    range = 1,
    manaCost = 340,
    avgDamage = 400,
    cooldown = 4000,
    vocations = {1, 11}
  },
  ["exori min"] = {
    type = SPELL_TYPES.WAVE,
    range = 3,
    manaCost = 200,
    avgDamage = 300,
    cooldown = 4000,
    minTargets = 2,
    vocations = {1, 11}
  },
  
  -- Paladin spells
  ["exori san"] = {
    type = SPELL_TYPES.SINGLE,
    range = 4,
    manaCost = 25,
    avgDamage = 120,
    cooldown = 2000,
    vocations = {2, 12}
  },
  ["exori con"] = {
    type = SPELL_TYPES.SINGLE,
    range = 7,
    manaCost = 25,
    avgDamage = 100,
    cooldown = 2000,
    vocations = {2, 12}
  },
  ["exevo mas san"] = {
    type = SPELL_TYPES.AOE,
    range = 6,
    manaCost = 150,
    avgDamage = 250,
    cooldown = 8000,
    minTargets = 2,
    vocations = {2, 12}
  },
  
  -- Sorcerer spells
  ["exori flam"] = {
    type = SPELL_TYPES.SINGLE,
    range = 3,
    manaCost = 25,
    avgDamage = 100,
    cooldown = 2000,
    vocations = {3, 13}
  },
  ["exori vis"] = {
    type = SPELL_TYPES.SINGLE,
    range = 3,
    manaCost = 25,
    avgDamage = 100,
    cooldown = 2000,
    vocations = {3, 13}
  },
  ["exevo flam hur"] = {
    type = SPELL_TYPES.WAVE,
    range = 6,
    manaCost = 300,
    avgDamage = 400,
    cooldown = 4000,
    minTargets = 2,
    vocations = {3, 13}
  },
  ["exevo gran mas flam"] = {
    type = SPELL_TYPES.AOE,
    range = 5,
    manaCost = 1100,
    avgDamage = 600,
    cooldown = 40000,
    minTargets = 3,
    vocations = {3, 13}
  },
  
  -- Druid spells
  ["exori frigo"] = {
    type = SPELL_TYPES.SINGLE,
    range = 3,
    manaCost = 25,
    avgDamage = 100,
    cooldown = 2000,
    vocations = {4, 14}
  },
  ["exori tera"] = {
    type = SPELL_TYPES.SINGLE,
    range = 3,
    manaCost = 25,
    avgDamage = 100,
    cooldown = 2000,
    vocations = {4, 14}
  },
  ["exevo frigo hur"] = {
    type = SPELL_TYPES.WAVE,
    range = 6,
    manaCost = 300,
    avgDamage = 400,
    cooldown = 4000,
    minTargets = 2,
    vocations = {4, 14}
  },
  ["exevo gran mas frigo"] = {
    type = SPELL_TYPES.AOE,
    range = 5,
    manaCost = 1100,
    avgDamage = 600,
    cooldown = 40000,
    minTargets = 3,
    vocations = {4, 14}
  },
  
  -- Runes (all vocations)
  ["avalanche"] = {
    type = SPELL_TYPES.RUNE,
    range = 4,
    manaCost = 0,
    avgDamage = 200,
    cooldown = 2000,
    minTargets = 2,
    itemId = 3161
  },
  ["great fireball"] = {
    type = SPELL_TYPES.RUNE,
    range = 4,
    manaCost = 0,
    avgDamage = 200,
    cooldown = 2000,
    minTargets = 2,
    itemId = 3191
  },
  ["sudden death"] = {
    type = SPELL_TYPES.RUNE,
    range = 3,
    manaCost = 0,
    avgDamage = 300,
    cooldown = 2000,
    itemId = 3155
  }
}

-- Create new instance
function DynamicSpellSelector:new(options)
  options = options or {}
  
  local instance = {
    enabled = false,
    spellRegistry = {},
    lastCast = {},
    playerVocation = nil,
    debugMode = options.debug or false
  }
  
  setmetatable(instance, { __index = self })
  
  -- Register default spells
  for name, data in pairs(DEFAULT_SPELLS) do
    instance.spellRegistry[name] = data
  end
  
  return instance
end

-- Get current time
local function getCurrentTime()
  return g_clock and g_clock.millis() or (now or 0)
end

-- Get player mana
local function getPlayerMana()
  local localPlayer = player or (g_game and g_game.getLocalPlayer())
  if localPlayer and localPlayer.getMana then
    return localPlayer:getMana()
  end
  return 0
end

-- Get player vocation
local function getPlayerVocation()
  local localPlayer = player or (g_game and g_game.getLocalPlayer())
  if localPlayer and localPlayer.getVocation then
    return localPlayer:getVocation()
  end
  return 0
end

-- Calculate distance
local function calculateDistance(pos1, pos2)
  if not pos1 or not pos2 then return 20 end
  return math.sqrt(
    math.pow(pos1.x - pos2.x, 2) +
    math.pow(pos1.y - pos2.y, 2)
  )
end

-- Register a custom spell
function DynamicSpellSelector:registerSpell(name, data)
  self.spellRegistry[name:lower()] = data
  return self
end

-- Check if spell is on cooldown
function DynamicSpellSelector:isOnCooldown(spellName)
  local lastCast = self.lastCast[spellName:lower()]
  if not lastCast then return false end
  
  local spellData = self.spellRegistry[spellName:lower()]
  if not spellData then return false end
  
  local currentTime = getCurrentTime()
  return (currentTime - lastCast) < spellData.cooldown
end

-- Check if spell can be cast (mana, cooldown, vocation)
function DynamicSpellSelector:canCast(spellName)
  local spellData = self.spellRegistry[spellName:lower()]
  if not spellData then return false end
  
  -- Check cooldown
  if self:isOnCooldown(spellName) then
    return false
  end
  
  -- Check mana
  local playerMana = getPlayerMana()
  if playerMana < spellData.manaCost then
    return false
  end
  
  -- Check vocation
  if spellData.vocations then
    local playerVoc = getPlayerVocation()
    local vocFound = false
    for _, voc in ipairs(spellData.vocations) do
      if voc == playerVoc then
        vocFound = true
        break
      end
    end
    if not vocFound then
      return false
    end
  end
  
  -- Check item availability for runes
  if spellData.type == SPELL_TYPES.RUNE and spellData.itemId then
    local item = findItem and findItem(spellData.itemId)
    if not item then
      return false
    end
  end
  
  return true
end

-- Filter creatures by range
function DynamicSpellSelector:filterCreaturesInRange(creatures, range, fromPos)
  if not creatures then return {} end
  
  local localPlayer = player or (g_game and g_game.getLocalPlayer())
  fromPos = fromPos or (localPlayer and localPlayer:getPosition())
  if not fromPos then return {} end
  
  local inRange = {}
  
  for _, creature in ipairs(creatures) do
    local distance = calculateDistance(fromPos, creature:getPosition())
    if distance <= range then
      table.insert(inRange, creature)
    end
  end
  
  return inRange
end

-- Calculate spell efficiency (damage per mana)
function DynamicSpellSelector:calculateEfficiency(spellName, targetCount)
  local spellData = self.spellRegistry[spellName:lower()]
  if not spellData then return 0 end
  
  targetCount = targetCount or 1
  local totalDamage = spellData.avgDamage * targetCount
  local manaCost = math.max(spellData.manaCost, 1)
  
  return totalDamage / manaCost
end

-- Find best AOE spell for current situation
function DynamicSpellSelector:findBestAOE(creatures, playerStats)
  local bestSpell = nil
  local bestScore = -1
  
  for spellName, spellData in pairs(self.spellRegistry) do
    if spellData.type == SPELL_TYPES.AOE or spellData.type == SPELL_TYPES.WAVE then
      if self:canCast(spellName) then
        local inRange = self:filterCreaturesInRange(creatures, spellData.range)
        local targetCount = #inRange
        
        -- Check minimum targets
        local minTargets = spellData.minTargets or 1
        if targetCount >= minTargets then
          local efficiency = self:calculateEfficiency(spellName, targetCount)
          local score = efficiency * targetCount  -- Favor hitting more targets
          
          if score > bestScore then
            bestScore = score
            bestSpell = {
              name = spellName,
              data = spellData,
              efficiency = efficiency,
              targetCount = targetCount
            }
          end
        end
      end
    end
  end
  
  return bestSpell
end

-- Find best single target spell
function DynamicSpellSelector:findBestSingleTarget(creature, playerStats)
  if not creature then return nil end
  
  local creatureHealth = creature.getHealth and creature:getHealth() or 100
  local bestSpell = nil
  local bestScore = -1
  
  local localPlayer = player or (g_game and g_game.getLocalPlayer())
  local playerPos = localPlayer and localPlayer:getPosition()
  local creaturePos = creature:getPosition()
  local distance = calculateDistance(playerPos, creaturePos)
  
  for spellName, spellData in pairs(self.spellRegistry) do
    if spellData.type == SPELL_TYPES.SINGLE then
      if self:canCast(spellName) and distance <= spellData.range then
        local efficiency = self:calculateEfficiency(spellName)
        local killPotential = spellData.avgDamage / math.max(creatureHealth, 1)
        local score = (efficiency * 0.6) + (killPotential * 0.4)
        
        if score > bestScore then
          bestScore = score
          bestSpell = {
            name = spellName,
            data = spellData,
            efficiency = efficiency,
            killPotential = killPotential
          }
        end
      end
    end
  end
  
  return bestSpell
end

-- Select best spell for current situation
function DynamicSpellSelector:selectBestSpell(creatures, currentTarget, playerStats)
  local nearbyCreatures = self:filterCreaturesInRange(creatures, 8)
  
  if #nearbyCreatures == 0 then
    return nil
  end
  
  -- Try AOE if multiple targets
  if #nearbyCreatures >= 2 then
    local aoeSpell = self:findBestAOE(nearbyCreatures, playerStats)
    if aoeSpell then
      if self.debugMode then
        print(string.format("[SpellSelector] Selected AOE: %s (efficiency: %.2f, targets: %d)",
          aoeSpell.name, aoeSpell.efficiency, aoeSpell.targetCount))
      end
      return aoeSpell
    end
  end
  
  -- Fall back to single target
  if currentTarget then
    local singleSpell = self:findBestSingleTarget(currentTarget, playerStats)
    if singleSpell then
      if self.debugMode then
        print(string.format("[SpellSelector] Selected Single: %s (efficiency: %.2f)",
          singleSpell.name, singleSpell.efficiency))
      end
      return singleSpell
    end
  end
  
  return nil
end

-- Cast a spell
function DynamicSpellSelector:castSpell(spellName)
  local spellData = self.spellRegistry[spellName:lower()]
  if not spellData then return false end
  
  if spellData.type == SPELL_TYPES.RUNE then
    -- Use rune
    if spellData.itemId and g_game then
      local target = g_game.getAttackingCreature and g_game.getAttackingCreature()
      if target then
        g_game.useInventoryItemWith(spellData.itemId, target)
        self.lastCast[spellName:lower()] = getCurrentTime()
        return true
      end
    end
  else
    -- Say spell
    if say then
      say(spellName)
      self.lastCast[spellName:lower()] = getCurrentTime()
      return true
    end
  end
  
  return false
end

-- Record spell cast (for external spell casts)
function DynamicSpellSelector:recordCast(spellName)
  self.lastCast[spellName:lower()] = getCurrentTime()
end

-- Get available spells for current vocation
function DynamicSpellSelector:getAvailableSpells()
  local playerVoc = getPlayerVocation()
  local available = {}
  
  for name, data in pairs(self.spellRegistry) do
    if not data.vocations or #data.vocations == 0 then
      table.insert(available, {name = name, data = data})
    else
      for _, voc in ipairs(data.vocations) do
        if voc == playerVoc then
          table.insert(available, {name = name, data = data})
          break
        end
      end
    end
  end
  
  return available
end

-- Enable/disable
function DynamicSpellSelector:enable()
  self.enabled = true
  return self
end

function DynamicSpellSelector:disable()
  self.enabled = false
  return self
end

function DynamicSpellSelector:toggle()
  self.enabled = not self.enabled
  return self
end

function DynamicSpellSelector:isEnabled()
  return self.enabled
end

-- Set debug mode
function DynamicSpellSelector:setDebugMode(enabled)
  self.debugMode = enabled
  return self
end

-- Get status
function DynamicSpellSelector:getStatus()
  return {
    enabled = self.enabled,
    registeredSpells = #self.spellRegistry,
    vocation = getPlayerVocation(),
    mana = getPlayerMana()
  }
end

return DynamicSpellSelector
