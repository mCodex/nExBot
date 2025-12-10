--[[
  BotCore: Friend Healer Module
  
  High-performance friend healing system integrated with BotCore.
  Shares exhaustion with HealBot for seamless priority management.
  
  Design Principles:
    - Pure Functions: All calculations are stateless
    - Event-Driven: Responds instantly to health changes
    - Priority-Based: Self-healing ALWAYS takes precedence
    - DRY: Uses shared BotCore.Cooldown for exhaustion
    - SOLID: Single responsibility, easy to extend
    - Performance: Memoized target selection, minimal iteration
  
  Priority Order (hardcoded for safety):
    1. Self HP critical (<30%) - NEVER heal friends
    2. Self HP low (<50%) - NEVER heal friends  
    3. Friend HP critical (<30%) - Emergency friend heal
    4. Self HP medium (<80%) - Prefer self-heal
    5. Friend HP low (<50%) - Friend needs help
    6. Normal operation - Heal whoever needs it most
]]

BotCore.FriendHealer = BotCore.FriendHealer or {}
local FriendHealer = BotCore.FriendHealer

-- ============================================================================
-- CONSTANTS (Performance: avoid table lookups in hot path)
-- ============================================================================

local SELF_CRITICAL_HP = 30      -- Below this: NEVER heal friends
local SELF_LOW_HP = 50           -- Below this: NEVER heal friends
local SELF_MEDIUM_HP = 80        -- Below this: Prefer self-heal
local FRIEND_CRITICAL_HP = 30    -- Friend emergency threshold
local FRIEND_LOW_HP = 50         -- Friend needs urgent help

local SCAN_INTERVAL_MS = 100     -- How often to scan for friends
local HEAL_COOLDOWN_MS = 1000    -- Minimum time between heals

-- Spell cooldown IDs (OTClient standard)
local SPELL_EXURA_SIO = 130
local SPELL_EXURA_GRAN_SIO = 131  
local SPELL_EXURA_MAS_RES = 132

-- Vocation detection patterns
local VOC_PATTERNS = {
  knight = { "EK", "Knight" },
  paladin = { "RP", "Paladin" },
  druid = { "ED", "Druid" },
  sorcerer = { "MS", "Sorcerer" }
}

-- ============================================================================
-- PRIVATE STATE (Memoization)
-- ============================================================================

local _state = {
  -- Cached friend list { name = { creature, lastHp, lastUpdate, priority } }
  friends = {},
  
  -- Last scan timestamp
  lastScan = 0,
  
  -- Last heal action timestamp
  lastHeal = 0,
  
  -- Best target from last scan
  bestTarget = nil,
  
  -- Configuration reference (set by init)
  config = nil,
  
  -- Module enabled state
  enabled = false
}

-- ============================================================================
-- PURE FUNCTIONS: Health Calculations
-- ============================================================================

-- Calculate heal urgency score (0-100, higher = more urgent)
-- Pure function: no side effects
local function calculateUrgency(hpPercent, isFriend, distanceFromPlayer)
  if not hpPercent or hpPercent >= 100 then return 0 end
  
  -- Base urgency: inverse of HP (100 - HP)
  local urgency = 100 - hpPercent
  
  -- Distance penalty: further = less urgent (can't heal if too far)
  local distancePenalty = (distanceFromPlayer or 0) * 2
  urgency = urgency - distancePenalty
  
  -- Friend modifier: slightly lower priority than self
  if isFriend then
    urgency = urgency * 0.9
  end
  
  return math.max(0, math.min(100, urgency))
end

-- Determine if we should heal friend over self
-- Pure function: returns decision based on both health states
local function shouldHealFriend(selfHpPercent, friendHpPercent, friendUrgency)
  -- RULE 1: Self is critical - NEVER heal friends
  if selfHpPercent < SELF_CRITICAL_HP then
    return false, "self_critical"
  end
  
  -- RULE 2: Self is low - NEVER heal friends
  if selfHpPercent < SELF_LOW_HP then
    return false, "self_low"
  end
  
  -- RULE 3: Friend is critical - ALWAYS help (if self is ok)
  if friendHpPercent < FRIEND_CRITICAL_HP then
    return true, "friend_critical"
  end
  
  -- RULE 4: Self is medium - Prefer self (but not mandatory)
  if selfHpPercent < SELF_MEDIUM_HP then
    return false, "self_medium"
  end
  
  -- RULE 5: Friend is low - Help them
  if friendHpPercent < FRIEND_LOW_HP then
    return true, "friend_low"
  end
  
  -- RULE 6: Both are fine - Heal based on urgency
  return friendUrgency > 30, "normal"
end

-- Calculate best heal spell for friend
-- Pure function: returns spell info based on HP and config
local function getBestHealSpell(friendHpPercent, config)
  local spells = {}
  
  -- Strong heal for critical friends
  if friendHpPercent < 40 and config.useGranSio then
    table.insert(spells, {
      name = "exura gran sio",
      spellId = SPELL_EXURA_GRAN_SIO,
      group = 2,
      priority = 1
    })
  end
  
  -- Normal sio for low friends
  if config.useSio then
    table.insert(spells, {
      name = "exura sio",
      spellId = SPELL_EXURA_SIO,
      group = 2,
      priority = 2
    })
  end
  
  -- Custom spell if configured
  if config.customSpell and config.customSpellName then
    table.insert(spells, {
      name = config.customSpellName,
      spellId = nil,  -- Unknown ID
      group = 2,
      priority = 3
    })
  end
  
  return spells
end

-- ============================================================================
-- PURE FUNCTIONS: Target Selection
-- ============================================================================

-- Check if creature matches configured conditions
-- Pure function: returns true/false based on creature and config
local function matchesConditions(creature, config)
  if not creature or not creature:isPlayer() then return false end
  if creature:isLocalPlayer() then return false end
  
  local name = creature:getName()
  
  -- Check custom player list first (highest priority)
  if config.customPlayers and config.customPlayers[name] then
    return true
  end
  
  -- Check party membership
  if config.conditions.party and creature:isPartyMember() then
    return true
  end
  
  -- Check guild membership (emblem = 1 means same guild)
  if config.conditions.guild and creature:getEmblem() == 1 then
    return true
  end
  
  -- Check friends list
  if config.conditions.friends and isFriend and isFriend(creature) then
    return true
  end
  
  -- Check BotServer members
  if config.conditions.botserver and nExBot and nExBot.BotServerMembers then
    if nExBot.BotServerMembers[name] then
      return true
    end
  end
  
  return false
end

-- Check vocation filter
-- Pure function: returns true if creature matches vocation filter
local function matchesVocation(creature, config)
  if not storage or not storage.extras or not storage.extras.checkPlayer then
    return true  -- Can't check, allow
  end
  
  local specText = creature:getText() or ""
  if specText:len() == 0 then return true end  -- No info, allow
  
  -- Check each vocation
  if specText:find("EK") and not config.conditions.knights then return false end
  if specText:find("RP") and not config.conditions.paladins then return false end
  if specText:find("ED") and not config.conditions.druids then return false end
  if specText:find("MS") and not config.conditions.sorcerers then return false end
  
  return true
end

-- Find best healing target from spectators
-- Semi-pure: reads spectators but doesn't modify state
local function findBestTarget(spectators, config, selfHpPercent)
  local bestTarget = nil
  local bestUrgency = 0
  local targetsInRange = 0  -- For mas res calculation
  
  for _, spec in ipairs(spectators) do
    -- Skip non-matching creatures
    if matchesConditions(spec, config) and matchesVocation(spec, config) then
      local hp = spec:getHealthPercent()
      local pos = spec:getPosition()
      local dist = pos and distanceFromPlayer and distanceFromPlayer(pos) or 99
      
      -- Check if in healing range (typically 7 tiles for sio)
      if dist <= 7 and spec:canShoot() then
        -- Count for mas res
        if dist <= 3 and hp < 90 then
          targetsInRange = targetsInRange + 1
        end
        
        -- Check if needs healing
        local customHp = config.customPlayers and config.customPlayers[spec:getName()]
        local healThreshold = customHp or config.settings.healAt or 80
        
        if hp < healThreshold then
          local urgency = calculateUrgency(hp, true, dist)
          
          -- Should we heal this friend?
          local shouldHeal, reason = shouldHealFriend(selfHpPercent, hp, urgency)
          
          if shouldHeal and urgency > bestUrgency then
            bestTarget = {
              creature = spec,
              name = spec:getName(),
              hp = hp,
              distance = dist,
              urgency = urgency,
              reason = reason,
              customHp = customHp
            }
            bestUrgency = urgency
          end
        end
      end
    end
  end
  
  return bestTarget, targetsInRange
end

-- ============================================================================
-- COOLDOWN INTEGRATION (Uses BotCore.Cooldown)
-- ============================================================================

-- Check if we can cast healing spell (shared with HealBot)
local function canCastHeal()
  -- Use BotCore cooldown manager if available
  if BotCore.Cooldown and BotCore.Cooldown.isHealingOnCooldown then
    if BotCore.Cooldown.isHealingOnCooldown() then
      return false
    end
  end
  
  -- Fallback to direct check
  if modules and modules.game_cooldown then
    if modules.game_cooldown.isGroupCooldownIconActive(2) then
      return false
    end
  end
  
  return true
end

-- Check if specific spell is ready
local function canCastSpell(spellId)
  if not spellId then return true end  -- Unknown spell, try anyway
  
  -- Use BotCore cooldown manager
  if BotCore.Cooldown and BotCore.Cooldown.isSpellOnCooldown then
    return not BotCore.Cooldown.isSpellOnCooldown(spellId)
  end
  
  -- Fallback
  if modules and modules.game_cooldown then
    return not modules.game_cooldown.isCooldownIconActive(spellId)
  end
  
  return true
end

-- Check if can use healing item
local function canUseHealItem()
  -- Use BotCore cooldown manager
  if BotCore.Cooldown and BotCore.Cooldown.canUsePotion then
    return BotCore.Cooldown.canUsePotion()
  end
  
  -- Fallback: check nExBot potion state
  if nExBot and nExBot.isUsingPotion then
    return false
  end
  
  return true
end

-- Mark that we used a heal (update shared cooldown)
local function markHealUsed()
  local currentTime = now or os.time() * 1000
  _state.lastHeal = currentTime
  
  -- Update BotCore cooldown if available
  if BotCore.Priority and BotCore.Priority.markExhausted then
    BotCore.Priority.markExhausted("healing", HEAL_COOLDOWN_MS)
  end
end

-- ============================================================================
-- ACTION EXECUTION
-- ============================================================================

-- Execute heal on target
-- Returns true if action was taken
local function executeHeal(target, config, targetsInRange)
  if not target or not target.creature then return false end
  
  local name = target.name
  local hp = target.hp
  local dist = target.distance
  
  -- Check settings
  local masResPlayers = config.settings.masResPlayers or 2
  local itemRange = config.settings.itemRange or 6
  local healthItemId = config.settings.healthItem or 3160
  local manaItemId = config.settings.manaItem or 268
  local granSioThreshold = config.settings.granSioAt or 40
  
  -- Priority 1: Mas Res if multiple friends need healing
  if targetsInRange >= masResPlayers and canCast and canCast("exura gran mas res") then
    if canCastHeal() and canCastSpell(SPELL_EXURA_MAS_RES) then
      say("exura gran mas res")
      markHealUsed()
      return true
    end
  end
  
  -- Priority 2: Gran Sio for critical friends
  if hp <= granSioThreshold and canCast and canCast('exura gran sio "' .. name) then
    if canCastHeal() and canCastSpell(SPELL_EXURA_GRAN_SIO) then
      say('exura gran sio "' .. name)
      markHealUsed()
      return true
    end
  end
  
  -- Priority 3: Normal Sio
  if canCast and canCast('exura sio "' .. name) then
    if canCastHeal() then
      say('exura sio "' .. name)
      markHealUsed()
      return true
    end
  end
  
  -- Priority 4: Health item if in range
  if dist <= itemRange and findItem and findItem(healthItemId) then
    if canUseHealItem() then
      useWith(healthItemId, target.creature)
      markHealUsed()
      if BotCore.Cooldown and BotCore.Cooldown.markPotionUsed then
        BotCore.Cooldown.markPotionUsed()
      end
      return true
    end
  end
  
  return false
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Initialize with config reference
function FriendHealer.init(config)
  _state.config = config
  _state.enabled = true
end

-- Set enabled state
function FriendHealer.setEnabled(enabled)
  _state.enabled = enabled
end

-- Check if enabled
function FriendHealer.isEnabled()
  return _state.enabled and _state.config and _state.config.enabled
end

-- Get current best target (for UI display)
function FriendHealer.getBestTarget()
  return _state.bestTarget
end

-- Main tick function - called by macro
-- Returns true if action was taken
function FriendHealer.tick()
  if not FriendHealer.isEnabled() then return false end
  
  local config = _state.config
  if not config then return false end
  
  -- Get self HP
  local selfHpPercent = 100
  if BotCore.Stats and BotCore.Stats.getHpPercent then
    selfHpPercent = BotCore.Stats.getHpPercent()
  elseif hppercent then
    selfHpPercent = hppercent()
  end
  
  -- SAFETY: Never heal friends if self is in danger
  if selfHpPercent < SELF_LOW_HP then
    _state.bestTarget = nil
    return false
  end
  
  -- Check minimum mana/hp requirements from config
  local minSelfHp = config.settings.minPlayerHp or 80
  local minSelfMp = config.settings.minPlayerMp or 50
  
  local selfMpPercent = 100
  if BotCore.Stats and BotCore.Stats.getMpPercent then
    selfMpPercent = BotCore.Stats.getMpPercent()
  elseif manapercent then
    selfMpPercent = manapercent()
  end
  
  if selfHpPercent < minSelfHp or selfMpPercent < minSelfMp then
    _state.bestTarget = nil
    return false
  end
  
  -- Rate limit scanning
  local currentTime = now or os.time() * 1000
  if (currentTime - _state.lastScan) < SCAN_INTERVAL_MS then
    -- Use cached target if still valid
    if _state.bestTarget and _state.bestTarget.creature then
      local hp = _state.bestTarget.creature:getHealthPercent()
      if hp and hp < 100 then
        return executeHeal(_state.bestTarget, config, 0)
      end
    end
    return false
  end
  _state.lastScan = currentTime
  
  -- Get spectators
  local spectators = getSpectators and getSpectators() or {}
  
  -- Find best target
  local bestTarget, targetsInRange = findBestTarget(spectators, config, selfHpPercent)
  _state.bestTarget = bestTarget
  
  -- Execute heal if target found
  if bestTarget then
    return executeHeal(bestTarget, config, targetsInRange)
  end
  
  return false
end

-- Event handler: Friend health changed (for instant response)
function FriendHealer.onFriendHealthChange(creature, newHpPercent, oldHpPercent)
  if not FriendHealer.isEnabled() then return end
  if not creature or creature:isLocalPlayer() then return end
  
  local config = _state.config
  if not config then return end
  
  -- Only react to significant drops
  local drop = (oldHpPercent or 100) - newHpPercent
  if drop < 10 then return end
  
  -- Check if this is a friend
  if not matchesConditions(creature, config) then return end
  
  -- Get self HP
  local selfHpPercent = hppercent and hppercent() or 100
  
  -- Safety check
  if selfHpPercent < SELF_LOW_HP then return end
  
  -- Check urgency
  local urgency = calculateUrgency(newHpPercent, true, 3)
  if urgency > 50 then
    -- This is urgent! Try to heal immediately
    local target = {
      creature = creature,
      name = creature:getName(),
      hp = newHpPercent,
      distance = 3,  -- Approximate
      urgency = urgency,
      reason = "event_response"
    }
    
    executeHeal(target, config, 0)
  end
end

-- ============================================================================
-- EXPORT
-- ============================================================================

BotCore.FriendHealer = FriendHealer
