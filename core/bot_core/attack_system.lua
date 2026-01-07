--[[
  BotCore: Unified Attack System v1.0
  
  High-performance attack system using hotkey-style rune/potion usage
  and EventBus for instant reaction to combat events.
  
  Features:
    - Hotkey-style item usage (works without open backpack)
    - EventBus integration for instant reactions
    - Shared cooldown management with HealBot/FriendHealer
    - Priority-based attack selection
    - AOE attack optimization with monster clustering
    - Anti-waste system (don't use expensive runes on low HP targets)
  
  Design Principles:
    - SRP: Single responsibility for each function
    - DRY: Uses shared BotCore modules
    - Event-Driven: Responds to combat state changes
    - Performance: Memoized calculations, minimal allocations
    
  Cooldown Groups (OTClient standard):
    1 = Attack spells
    2 = Healing spells  
    3 = Support spells
    4 = Special spells
    6 = Potion/Rune exhaustion
]]

BotCore.AttackSystem = BotCore.AttackSystem or {}
local AttackSystem = BotCore.AttackSystem

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local RUNE_COOLDOWN_MS = 2000      -- Default rune exhaustion
local SPELL_COOLDOWN_MS = 2000     -- Default attack spell cooldown
local AOE_COOLDOWN_MS = 2000       -- AOE attack cooldown
local POTION_COOLDOWN_MS = 1000    -- Throwing potion cooldown
local MIN_HP_FOR_RUNE = 15         -- Don't waste runes on targets below this HP%

-- Attack types for priority ordering
local ATTACK_TYPE = {
  AOE_SPELL = 1,
  AOE_RUNE = 2,
  SINGLE_SPELL = 3,
  SINGLE_RUNE = 4,
  BASIC = 5
}

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _state = {
  -- Last attack timestamps
  lastRuneAttack = 0,
  lastSpellAttack = 0,
  lastAOEAttack = 0,
  lastPotionAttack = 0,
  
  -- Attack tracking for analytics
  attackCount = 0,
  runeCount = 0,
  spellCount = 0,
  
  -- Configuration (set by TargetBot)
  config = nil,
  
  -- Event subscriptions
  subscriptions = {},
  
  -- Enabled state (DEFAULT: true for hotkey-style attacks)
  enabled = true
}

-- ============================================================================
-- COOLDOWN INTEGRATION (Uses BotCore.Cooldown as single source of truth)
-- ============================================================================

-- Check if attack group cooldown is active
local function isAttackGroupOnCooldown()
  if BotCore.Cooldown and BotCore.Cooldown.isAttackOnCooldown then
    return BotCore.Cooldown.isAttackOnCooldown()
  end
  if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
    return modules.game_cooldown.isGroupCooldownIconActive(1)
  end
  return false
end

-- Check if rune exhaustion is active (group 6)
local function isRuneOnCooldown()
  if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
    return modules.game_cooldown.isGroupCooldownIconActive(6)
  end
  local currentTime = now or os.time() * 1000
  return currentTime < _state.lastRuneAttack + RUNE_COOLDOWN_MS
end

-- Check if specific spell is on cooldown
local function isSpellOnCooldown(spellId)
  if BotCore.Cooldown and BotCore.Cooldown.isSpellOnCooldown then
    return BotCore.Cooldown.isSpellOnCooldown(spellId)
  end
  if modules and modules.game_cooldown and modules.game_cooldown.isCooldownIconActive then
    return modules.game_cooldown.isCooldownIconActive(spellId)
  end
  return false
end

-- Check if can use attack action with custom delay
local function canAttack(lastTime, delay)
  local currentTime = now or os.time() * 1000
  return currentTime >= lastTime + (delay or SPELL_COOLDOWN_MS)
end

-- ============================================================================
-- HOTKEY-STYLE ITEM USAGE (High-performance, works without open backpack)
-- ============================================================================

-- Use item on target using hotkey-style API
-- @param itemId: rune/potion ID
-- @param target: creature to attack
-- @param subType: optional subType for fluid containers
-- @return boolean success
local function useItemOnTarget(itemId, target, subType)
  if not itemId or not target then return false end
  
  -- Use BotCore.Items if available (consolidated implementation)
  if BotCore.Items and BotCore.Items.useOn then
    return BotCore.Items.useOn(itemId, target, subType)
  end
  
  -- Fallback: Direct implementation
  local thing = g_things.getThingType(itemId)
  if not thing or not thing:isFluidContainer() then
    subType = g_game.getClientVersion() >= 860 and 0 or 1
  end
  
  -- Method 1: Modern clients (780+) - use inventory item directly (like hotkey)
  if g_game.getClientVersion() >= 780 and g_game.useInventoryItemWith then
    g_game.useInventoryItemWith(itemId, target, subType)
    return true
  end
  
  -- Method 2: Legacy clients - find item and use with target
  if g_game.findPlayerItem then
    local tmpItem = g_game.findPlayerItem(itemId, subType)
    if tmpItem then
      g_game.useWith(tmpItem, target, subType)
      return true
    end
  end
  
  -- Method 3: Use findItem as fallback
  if findItem then
    local item = findItem(itemId)
    if item then
      g_game.useWith(item, target, subType)
      return true
    end
  end
  
  return false
end

-- ============================================================================
-- PURE FUNCTIONS: Attack Planning
-- ============================================================================

-- Count monsters in range for AOE attacks
-- @param centerPos: center position for AOE
-- @param radius: AOE radius
-- @return number of monsters, boolean hasPlayers
local function countMonstersInRange(centerPos, radius)
  local creatures = g_map.getSpectatorsInRange(centerPos, false, radius, radius)
  local monsterCount = 0
  local hasPlayers = false
  
  for i = 1, #creatures do
    local c = creatures[i]
    if c:isMonster() and not c:isDead() then
      monsterCount = monsterCount + 1
    elseif c:isPlayer() and not c:isLocalPlayer() then
      hasPlayers = true
    end
  end
  
  return monsterCount, hasPlayers
end

-- Check if target is worth using expensive attack on
-- @param target: creature
-- @param minHp: minimum HP% to warrant attack
-- @return boolean
local function isWorthAttacking(target, minHp)
  if not target then return false end
  local hp = target:getHealthPercent()
  return hp >= (minHp or MIN_HP_FOR_RUNE)
end

-- Check if player has enough mana for spell
-- @param manaCost: spell mana cost
-- @return boolean
local function hasEnoughMana(manaCost)
  if not manaCost or manaCost <= 0 then return true end
  local currentMana = mana and mana() or (player and player:getMana() or 0)
  return currentMana >= manaCost
end

-- Check if in protection zone (can't attack from PZ)
local function isInPz()
  if isInPz then return isInPz() end
  return false
end

-- ============================================================================
-- ATTACK EXECUTION
-- ============================================================================

-- Execute AOE spell attack
-- @param spellText: spell incantation
-- @param delay: cooldown delay
-- @param config: attack configuration
-- @return boolean success
function AttackSystem.executeAOESpell(spellText, delay, config)
  if not spellText or spellText:len() < 2 then return false end
  if isInPz() then return false end
  if isAttackGroupOnCooldown() then return false end
  if not canAttack(_state.lastAOEAttack, delay) then return false end
  
  -- Check mana requirement
  local manaCost = config and config.aoeMana or 0
  if not hasEnoughMana(manaCost) then return false end
  
  -- Check minimum mana setting
  local minMana = config and config.minMana or 0
  local currentMana = mana and mana() or 0
  if currentMana < minMana then return false end
  
  -- Execute spell
  if say then
    say(spellText)
    _state.lastAOEAttack = now or os.time() * 1000
    _state.lastSpellAttack = _state.lastAOEAttack
    _state.spellCount = _state.spellCount + 1
    _state.attackCount = _state.attackCount + 1
    
    -- Track for analytics
    if HuntAnalytics and HuntAnalytics.trackAttackSpell then
      HuntAnalytics.trackAttackSpell(spellText, manaCost)
    end
    
    -- Emit event for other systems
    if EventBus then
      EventBus.emit("attack:aoe_spell", spellText, manaCost)
    end
    
    return true
  end
  
  return false
end

-- Execute AOE rune attack
-- @param runeId: rune item ID
-- @param target: creature to center attack on
-- @param delay: cooldown delay
-- @param config: attack configuration
-- @return boolean success
function AttackSystem.executeAOERune(runeId, target, delay, config)
  if not runeId or runeId <= 100 then return false end
  if not target then return false end
  if isInPz() then return false end
  if isRuneOnCooldown() then return false end
  if not canAttack(_state.lastAOEAttack, delay) then return false end
  
  -- Check if worth using (anti-waste)
  if not isWorthAttacking(target, config and config.aoeMinTargetHp or MIN_HP_FOR_RUNE) then
    return false
  end
  
  -- Execute rune attack
  if useItemOnTarget(runeId, target, 0) then
    local currentTime = now or os.time() * 1000
    _state.lastAOEAttack = currentTime
    _state.lastRuneAttack = currentTime
    _state.runeCount = _state.runeCount + 1
    _state.attackCount = _state.attackCount + 1
    
    -- Track for analytics
    if HuntAnalytics and HuntAnalytics.trackRune then
      HuntAnalytics.trackRune(runeId, "aoe")
    end
    
    -- Emit event for other systems
    if EventBus then
      EventBus.emit("attack:aoe_rune", runeId, target)
    end
    
    return true
  end
  
  return false
end

-- Execute single-target spell attack
-- @param spellText: spell incantation
-- @param delay: cooldown delay
-- @param config: attack configuration
-- @return boolean success
function AttackSystem.executeSingleSpell(spellText, delay, config)
  if not spellText or spellText:len() < 2 then return false end
  if isInPz() then return false end
  if isAttackGroupOnCooldown() then return false end
  if not canAttack(_state.lastSpellAttack, delay) then return false end
  
  -- Check mana requirement
  local manaCost = config and config.spellMana or 0
  if not hasEnoughMana(manaCost) then return false end
  
  -- Check minimum mana setting
  local minMana = config and config.minMana or 0
  local currentMana = mana and mana() or 0
  if currentMana < minMana then return false end
  
  -- Execute spell
  if say then
    say(spellText)
    _state.lastSpellAttack = now or os.time() * 1000
    _state.spellCount = _state.spellCount + 1
    _state.attackCount = _state.attackCount + 1
    
    -- Track for analytics
    if HuntAnalytics and HuntAnalytics.trackAttackSpell then
      HuntAnalytics.trackAttackSpell(spellText, manaCost)
    end
    
    -- Emit event for other systems
    if EventBus then
      EventBus.emit("attack:single_spell", spellText, manaCost)
    end
    
    return true
  end
  
  return false
end

-- Execute single-target rune attack
-- @param runeId: rune item ID
-- @param target: creature to attack
-- @param delay: cooldown delay
-- @param config: attack configuration
-- @return boolean success
function AttackSystem.executeSingleRune(runeId, target, delay, config)
  if not runeId or runeId <= 100 then return false end
  if not target then return false end
  if isInPz() then return false end
  if isRuneOnCooldown() then return false end
  if not canAttack(_state.lastRuneAttack, delay) then return false end
  
  -- Check if worth using (anti-waste)
  local minHp = config and config.singleMinTargetHp or MIN_HP_FOR_RUNE
  if not isWorthAttacking(target, minHp) then
    return false
  end
  
  -- Execute rune attack
  if useItemOnTarget(runeId, target, 0) then
    local currentTime = now or os.time() * 1000
    _state.lastRuneAttack = currentTime
    _state.runeCount = _state.runeCount + 1
    _state.attackCount = _state.attackCount + 1
    
    -- Track for analytics
    if HuntAnalytics and HuntAnalytics.trackRune then
      HuntAnalytics.trackRune(runeId, "single")
    end
    
    -- Emit event for other systems
    if EventBus then
      EventBus.emit("attack:single_rune", runeId, target)
    end
    
    return true
  end
  
  return false
end

-- ============================================================================
-- HIGH-LEVEL ATTACK PLANNING
-- ============================================================================

--[[
  Plan the best attack action based on current combat state.
  
  Priority order:
    1. AOE spell (if enough monsters clustered)
    2. AOE rune (if enough monsters clustered and worth it)
    3. Single-target spell (always efficient)
    4. Single-target rune (if target HP warrants it)
  
  @param target: current attack target creature
  @param config: attack configuration from TargetBot
  @return action table or nil
]]
function AttackSystem.planAttack(target, config)
  if not target or not config then return nil end
  if isInPz() then return nil end
  
  local targetPos = target:getPosition()
  local targetHp = target:getHealthPercent()
  local currentTime = now or os.time() * 1000
  
  -- ========== AOE SPELL ==========
  if config.useGroupAttack and config.groupAttackSpell and config.groupAttackSpell:len() > 1 then
    local radius = config.groupAttackRadius or 3
    local minTargets = config.groupAttackTargets or 3
    local monsterCount, hasPlayers = countMonstersInRange(targetPos, radius)
    
    if monsterCount >= minTargets then
      if config.groupAttackIgnorePlayers or not hasPlayers then
        if canAttack(_state.lastAOEAttack, config.groupAttackDelay or AOE_COOLDOWN_MS) then
          if not isAttackGroupOnCooldown() then
            local minMana = config.minMana or 0
            local currentMana = mana and mana() or 0
            if currentMana >= minMana then
              return {
                type = ATTACK_TYPE.AOE_SPELL,
                spell = config.groupAttackSpell,
                delay = config.groupAttackDelay or AOE_COOLDOWN_MS,
                monsters = monsterCount
              }
            end
          end
        end
      end
    end
  end
  
  -- ========== AOE RUNE ==========
  if config.useGroupAttackRune and config.groupAttackRune and config.groupAttackRune > 100 then
    local radius = config.groupRuneAttackRadius or 3
    local minTargets = config.groupRuneAttackTargets or 3
    local monsterCount, hasPlayers = countMonstersInRange(targetPos, radius)
    
    if monsterCount >= minTargets then
      if config.groupAttackIgnorePlayers or not hasPlayers then
        if canAttack(_state.lastAOEAttack, config.groupRuneAttackDelay or AOE_COOLDOWN_MS) then
          if not isRuneOnCooldown() then
            -- Anti-waste: don't use expensive AOE rune if target is almost dead
            if isWorthAttacking(target, config.aoeMinTargetHp or MIN_HP_FOR_RUNE) then
              return {
                type = ATTACK_TYPE.AOE_RUNE,
                runeId = config.groupAttackRune,
                target = target,
                delay = config.groupRuneAttackDelay or AOE_COOLDOWN_MS,
                monsters = monsterCount
              }
            end
          end
        end
      end
    end
  end
  
  -- ========== SINGLE TARGET SPELL ==========
  if config.useSpellAttack and config.attackSpell and config.attackSpell:len() > 1 then
    if canAttack(_state.lastSpellAttack, config.attackSpellDelay or SPELL_COOLDOWN_MS) then
      if not isAttackGroupOnCooldown() then
        local minMana = config.minMana or 0
        local currentMana = mana and mana() or 0
        if currentMana >= minMana then
          return {
            type = ATTACK_TYPE.SINGLE_SPELL,
            spell = config.attackSpell,
            delay = config.attackSpellDelay or SPELL_COOLDOWN_MS
          }
        end
      end
    end
  end
  
  -- ========== SINGLE TARGET RUNE ==========
  if config.useRuneAttack and config.attackRune and config.attackRune > 100 then
    if canAttack(_state.lastRuneAttack, config.attackRuneDelay or RUNE_COOLDOWN_MS) then
      if not isRuneOnCooldown() then
        -- Anti-waste: don't use rune if target is almost dead
        local minHp = config.singleMinTargetHp or MIN_HP_FOR_RUNE
        if isWorthAttacking(target, minHp) then
          return {
            type = ATTACK_TYPE.SINGLE_RUNE,
            runeId = config.attackRune,
            target = target,
            delay = config.attackRuneDelay or RUNE_COOLDOWN_MS
          }
        end
      end
    end
  end
  
  return nil
end

-- Execute a planned attack action
-- @param action: action from planAttack()
-- @param config: attack configuration
-- @return boolean success
function AttackSystem.executeAction(action, config)
  if not action then return false end
  
  if action.type == ATTACK_TYPE.AOE_SPELL then
    return AttackSystem.executeAOESpell(action.spell, action.delay, config)
    
  elseif action.type == ATTACK_TYPE.AOE_RUNE then
    return AttackSystem.executeAOERune(action.runeId, action.target, action.delay, config)
    
  elseif action.type == ATTACK_TYPE.SINGLE_SPELL then
    return AttackSystem.executeSingleSpell(action.spell, action.delay, config)
    
  elseif action.type == ATTACK_TYPE.SINGLE_RUNE then
    return AttackSystem.executeSingleRune(action.runeId, action.target, action.delay, config)
  end
  
  return false
end

-- Combined plan + execute (convenience function)
-- @param target: current attack target
-- @param config: attack configuration
-- @return boolean success
function AttackSystem.attack(target, config)
  local action = AttackSystem.planAttack(target, config)
  return AttackSystem.executeAction(action, config)
end

-- ============================================================================
-- EVENTBUS INTEGRATION
-- ============================================================================

-- Setup EventBus listeners for reactive attacks
function AttackSystem.setupEventListeners()
  if not EventBus then return end
  
  -- Clean up old subscriptions
  AttackSystem.cleanup()
  
  -- React to new target being set
  _state.subscriptions[#_state.subscriptions + 1] = EventBus.on("combat:target", function(creature, oldCreature)
    if creature and _state.enabled and _state.config then
      -- Immediate attack on new target (if ready)
      schedule(50, function()
        if creature and not creature:isDead() then
          AttackSystem.attack(creature, _state.config)
        end
      end)
    end
  end, 50)
  
  -- React to monster health dropping (finish off low HP targets)
  _state.subscriptions[#_state.subscriptions + 1] = EventBus.on("monster:health", function(creature, percent)
    if not _state.enabled or not _state.config then return end
    
    -- Current target optimization: try to finish off
    local currentTarget = g_game.getAttackingCreature and g_game.getAttackingCreature()
    if currentTarget and currentTarget == creature and percent > 0 and percent < 20 then
      -- Target is low HP, prioritize attack
      schedule(25, function()
        if creature and not creature:isDead() then
          -- Only use spells for finishing (save runes)
          if _state.config.useSpellAttack and _state.config.attackSpell then
            AttackSystem.executeSingleSpell(_state.config.attackSpell, _state.config.attackSpellDelay, _state.config)
          end
        end
      end)
    end
  end, 40)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Initialize attack system
function AttackSystem.init(config)
  _state.config = config
  _state.enabled = true
  AttackSystem.setupEventListeners()
end

-- Set configuration
function AttackSystem.setConfig(config)
  _state.config = config
end

-- Enable/disable
function AttackSystem.setEnabled(enabled)
  _state.enabled = enabled
end

-- Check if enabled
function AttackSystem.isEnabled()
  return _state.enabled
end

-- Get statistics
function AttackSystem.getStats()
  return {
    attackCount = _state.attackCount,
    runeCount = _state.runeCount,
    spellCount = _state.spellCount
  }
end

-- Reset statistics
function AttackSystem.resetStats()
  _state.attackCount = 0
  _state.runeCount = 0
  _state.spellCount = 0
end

-- Cleanup event subscriptions
function AttackSystem.cleanup()
  for _, unsub in ipairs(_state.subscriptions) do
    if type(unsub) == "function" then
      unsub()
    end
  end
  _state.subscriptions = {}
end

-- ============================================================================
-- BACKWARDS COMPATIBILITY BRIDGE
-- ============================================================================

-- These functions maintain compatibility with existing TargetBot code
-- while using the new optimized implementation under the hood

-- Legacy: Use attack item (rune) on target
-- @deprecated Use AttackSystem.executeSingleRune instead
function AttackSystem.useAttackItem(item, subType, target, delay)
  return AttackSystem.executeSingleRune(item, target, delay, _state.config)
end

-- Legacy: Say attack spell
-- @deprecated Use AttackSystem.executeSingleSpell instead
function AttackSystem.sayAttackSpell(text, delay)
  return AttackSystem.executeSingleSpell(text, delay, _state.config)
end

return AttackSystem
