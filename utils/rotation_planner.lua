-- Rotation Planner: Priority-based spell selection algorithm
-- Purpose: Decide which spell to cast next based on situation and validator results
-- Architecture: Precompute context once, then iterate spells for O(N) selection

---@class RotationPlanner
---@field spellRegistry SpellRegistry
---@field validators SpellValidators
---@field cooldownManager table

local RotationPlanner = {}

-- ============================================================================
-- Context Building: Snapshot of current game state
-- ============================================================================

---Build a context snapshot for spell validation
---Captures: player state, creature state, surrounding monsters, resources
---Purpose: Avoid repeated expensive calls during iteration
---@param targetCreature Creature|nil Creature being targeted
---@param evaluationType "attack"|"heal"|"utility" Type of evaluation
---@return table Context snapshot with all data validators need
local function buildContext(targetCreature, evaluationType)
  local player = player
  local targetList = getTargetList()
  local monstersInRange = {}
  local nearbyCreatures = {}
  
  -- Build creatures in range (for area effects)
  if targetList then
    for _, creature in pairs(targetList) do
      if creature ~= player and not creature:isRemoved() then
        local dist = creature:getDistance(player:getPosition())
        if dist > 0 then
          table.insert(nearbyCreatures, {creature = creature, distance = dist})
        end
      end
    end
  end
  
  -- Sort by distance for proximity checks
  table.sort(nearbyCreatures, function(a, b) return a.distance < b.distance end)
  
  local context = {
    -- Player state
    player = player,
    playerPos = player:getPosition(),
    playerHealth = player:getHealth(),
    playerMaxHealth = player:getMaxHealth(),
    playerHealthPercent = (player:getHealth() / player:getMaxHealth()) * 100,
    playerMana = player:getMana(),
    playerMaxMana = player:getMaxMana(),
    playerLevel = player:getLevel(),
    playerVocation = player:getVocation(),
    isMoving = player:isMoving(),
    isWalking = player:isWalking(),
    
    -- Target creature state
    creature = targetCreature,
    creaturePos = targetCreature and targetCreature:getPosition() or nil,
    creatureHealth = targetCreature and targetCreature:getHealth() or 0,
    creatureMaxHealth = targetCreature and targetCreature:getMaxHealth() or 0,
    distance = targetCreature and targetCreature:getDistance(player:getPosition()) or 0,
    
    -- Nearby creatures (for area/heal decisions)
    nearbyCreatures = nearbyCreatures,
    monstersInRange = nearbyCreatures, -- Alias for compatibility
    
    -- Evaluation context
    situation = evaluationType,
    evaluationType = evaluationType,
    timestamp = g_clock.millis(),
    
    -- Injected managers
    cooldownManager = nil, -- Injected by setManagers()
    validators = nil,      -- Injected by setManagers()
  }
  
  return context
end

---Filter monsters by distance (expensive operation, done once)
---@param creatures table[] {creature, distance} pairs
---@param maxDistance number
---@return table[] Filtered creatures within distance
local function filterByDistance(creatures, maxDistance)
  if maxDistance == 0 then return creatures end
  
  local result = {}
  for _, entry in ipairs(creatures) do
    if entry.distance <= maxDistance then
      table.insert(result, entry.creature)
    end
  end
  return result
end

-- ============================================================================
-- Priority Rotation Algorithm: First-Eligible Wins
-- ============================================================================

---Plan next spell to cast given current situation
---Iterates through registered spells in order, returns first valid one
---Optimization: Build context once, reuse for all validation checks
---@param spellRegistry SpellRegistry Spell definitions
---@param validators SpellValidators Validator framework
---@param targetCreature Creature|nil Target creature (for attack spells)
---@param evaluationType "attack"|"heal"|"utility" Type of planning
---@param debugLogging boolean Print validation fail reasons
---@return Spell|nil Best eligible spell, or nil if none valid
function RotationPlanner.plan(spellRegistry, validators, targetCreature, evaluationType, debugLogging)
  evaluationType = evaluationType or "attack"
  
  -- Build context once for all validators
  local context = buildContext(targetCreature, evaluationType)
  
  -- Track rejection reasons for debug logging
  local rejectionLog = {}
  
  -- Iterate spells in registration order (priority)
  for spell, spellName in spellRegistry:iterate() do
    -- Apply spell's custom validators if specified
    local spellValidators = spell.validators or {}
    local validatorList = {"mana", "cooldown", "target", "range", "safety", "resource"}
    
    -- Add custom validators if spell specifies them
    for customName, enabled in pairs(spellValidators) do
      if enabled and not table.find(validatorList, customName) then
        table.insert(validatorList, customName)
      end
    end
    
    -- Validate spell against all applicable validators
    local allValid, results = validators.registry:validateSpell(spell, context, validatorList)
    
    if allValid then
      if debugLogging then
        logger:debug(("[SPELL] Selected %s (all validators passed)"):format(spellName))
      end
      return spell, spellName
    else
      -- Log rejection reasons
      local summary = validators.registry:summarizeResults(results)
      rejectionLog[spellName] = summary.failed
      
      if debugLogging then
        local reasons = {}
        for validator, reason in pairs(summary.failed) do
          table.insert(reasons, validator .. ": " .. reason)
        end
        logger:debug(("[SPELL] Rejected %s (%s)"):format(spellName, table.concat(reasons, " | ")))
      end
    end
  end
  
  if debugLogging then
    logger:debug("[SPELL] No eligible spell found")
  end
  
  return nil, nil, rejectionLog
end

-- ============================================================================
-- Chain Planning: Queue follow-up spells after primary cast
-- ============================================================================

---Plan a chain of spells to execute in sequence
---Each spell's chainTo field specifies the next spell in the chain
---Useful for multi-stage combos (e.g., stun → weak spell → damage)
---@param startSpell Spell First spell in chain
---@param spellRegistry SpellRegistry For lookups
---@param maxChainLength number Max spells in chain (safety)
---@return Spell[] Chain of spells [startSpell, chainedSpell1, chainedSpell2, ...]
function RotationPlanner.planChain(startSpell, spellRegistry, maxChainLength)
  maxChainLength = maxChainLength or 5
  
  local chain = {startSpell}
  local current = startSpell
  
  while #chain < maxChainLength and current.chainTo do
    local nextSpell = spellRegistry:get(current.chainTo)
    if not nextSpell then
      break
    end
    
    table.insert(chain, nextSpell)
    current = nextSpell
  end
  
  return chain
end

-- ============================================================================
-- Healing Plan: Select best healing spell for a friend
-- ============================================================================

---Plan healing for a specific friend
---Compares heal amounts and selects most efficient spell within constraints
---@param targetFriend Creature Friend to heal
---@param healSpellRegistry SpellRegistry|nil Filtered spell list (optional)
---@param minHealthPercent number Only heal if below this percent
---@param debugLogging boolean
---@return Spell|nil Best healing spell for friend
function RotationPlanner.planHeal(targetFriend, healSpellRegistry, minHealthPercent, debugLogging)
  if not targetFriend or targetFriend:isRemoved() or not targetFriend:isAlive() then
    return nil
  end
  
  local healthPercent = (targetFriend:getHealth() / targetFriend:getMaxHealth()) * 100
  if healthPercent >= minHealthPercent then
    if debugLogging then
      logger:debug(("[HEAL] %s health too high: %.1f%% (min %.1f%%)"):format(
        targetFriend:getName(), healthPercent, minHealthPercent))
    end
    return nil
  end
  
  -- Build healing context
  local context = buildContext(targetFriend, "heal")
  context.minHealthPercent = minHealthPercent
  context.creature = targetFriend
  
  -- Find first valid healing spell
  local validatorList = {"mana", "cooldown", "range", "resource"}
  
  if healSpellRegistry then
    for spell, spellName in healSpellRegistry:iterate() do
      local allValid = select(1, validators.registry:validateSpell(spell, context, validatorList))
      if allValid then
        if debugLogging then
          logger:debug(("[HEAL] Selected %s for %s (%.1f%%)"):format(
            spellName, targetFriend:getName(), healthPercent))
        end
        return spell, spellName
      end
    end
  end
  
  if debugLogging then
    logger:debug(("[HEAL] No valid spell for %s"):format(targetFriend:getName()))
  end
  
  return nil
end

-- ============================================================================
-- Multi-Monster Area Plan: Select AoE spell for clustered enemies
-- ============================================================================

---Plan AoE damage for group of monsters
---Selects area spell that hits most monsters simultaneously
---@param monstersNearby Creature[] List of nearby creatures
---@param areaSpellRegistry SpellRegistry|nil Filtered list of AoE spells
---@param minMonstersRequired number Only use if >= this many monsters
---@param debugLogging boolean
---@return Spell|nil, number Best AoE spell and monster count it hits
function RotationPlanner.planAreaDamage(monstersNearby, areaSpellRegistry, minMonstersRequired, debugLogging)
  minMonstersRequired = minMonstersRequired or 2
  
  if not monstersNearby or #monstersNearby < minMonstersRequired then
    return nil, 0
  end
  
  local context = buildContext(nil, "attack")
  context.monstersInRange = monstersNearby
  
  local validatorList = {"mana", "cooldown", "safety", "resource"}
  
  if areaSpellRegistry then
    for spell, spellName in areaSpellRegistry:iterate() do
      if spell.targetType == "area" then
        local allValid = select(1, validators.registry:validateSpell(spell, context, validatorList))
        if allValid then
          -- Count monsters within area radius
          local player = player
          local hitCount = 0
          for _, creature in ipairs(monstersNearby) do
            if creature:getDistance(player:getPosition()) <= spell.areaRadius then
              hitCount = hitCount + 1
            end
          end
          
          if hitCount >= minMonstersRequired then
            if debugLogging then
              logger:debug(("[AoE] Selected %s (hits %d monsters)"):format(spellName, hitCount))
            end
            return spell, hitCount
          end
        end
      end
    end
  end
  
  return nil, 0
end

-- ============================================================================
-- Planner Configuration and Setup
-- ============================================================================

---Create new RotationPlanner instance with dependencies
---@param spellRegistry SpellRegistry
---@param spellValidators SpellValidators
---@param cooldownManager table
---@return table Planner instance
function RotationPlanner:new(spellRegistry, spellValidators, cooldownManager)
  local instance = {
    spellRegistry = spellRegistry,
    validators = spellValidators,
    cooldownManager = cooldownManager,
  }
  
  setmetatable(instance, self)
  self.__index = self
  
  return instance
end

---Inject manager references (cooldownManager, validators)
---Called after all components are created
function RotationPlanner:setManagers(cooldownManager, validators)
  self.cooldownManager = cooldownManager
  self.validators = validators
end

---Plan with instance method (cleaner API)
---@param targetCreature Creature|nil
---@param evaluationType "attack"|"heal"|"utility"
---@param debugLogging boolean
---@return Spell|nil, string|nil
function RotationPlanner:planNext(targetCreature, evaluationType, debugLogging)
  return RotationPlanner.plan(self.spellRegistry, self.validators, targetCreature, evaluationType, debugLogging)
end

return RotationPlanner
