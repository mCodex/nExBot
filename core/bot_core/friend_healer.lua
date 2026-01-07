--[[
  BotCore: Friend Healer v2.0 (Unified)
  
  High-performance friend healing system with hotkey-style potion/rune usage
  and EventBus integration for instant reaction to health changes.
  
  This is the DEFAULT and ONLY friend healer implementation.
  Replaces the old friend_healer.lua with full hotkey-style support.
  
  Features:
    - Hotkey-style potion usage on friends (works without open backpack)
    - EventBus integration for instant health drop reactions
    - Shared cooldown management with HealBot
    - Priority-based healing (self > critical friend > normal friend)
    - Support for healing runes (UH on friend)
    - Mana potion on friends (for druids supporting mages)
    
  Design Principles:
    - SRP: Single responsibility for each function
    - DRY: Uses shared BotCore modules
    - Event-Driven: Responds to friend health changes instantly
    - Safety-First: Self-healing ALWAYS takes precedence
    
  Potion Types Supported:
    - Ultimate Spirit Potion (on friends for emergency healing)
    - Great Spirit Potion
    - Mana potions (on friend mages)
    - Healing runes (UH)
]]

-- Initialize as both FriendHealerEnhanced and FriendHealer for full compatibility
BotCore.FriendHealerEnhanced = BotCore.FriendHealerEnhanced or {}
local FriendHealerEnhanced = BotCore.FriendHealerEnhanced

-- Also expose as BotCore.FriendHealer for backward compatibility with new_healer.lua
BotCore.FriendHealer = BotCore.FriendHealerEnhanced

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local SELF_CRITICAL_HP = 30      -- Below this: NEVER heal friends
local SELF_LOW_HP = 50           -- Below this: NEVER heal friends
local FRIEND_CRITICAL_HP = 30    -- Friend emergency threshold
local FRIEND_LOW_HP = 50         -- Friend needs urgent help

local HEAL_COOLDOWN_MS = 1000    -- Minimum time between heals
local POTION_COOLDOWN_MS = 1000  -- Potion exhaustion
local RUNE_COOLDOWN_MS = 1000    -- Rune exhaustion
local SPELL_COOLDOWN_MS = 1000   -- Healing spell cooldown

local SCAN_INTERVAL_MS = 100     -- How often to scan for friends

-- Common potion IDs
local POTION_IDS = {
  ULTIMATE_SPIRIT = 8472,
  GREAT_SPIRIT = 8473,
  SUPREME_HEALTH = 26031,
  ULTIMATE_HEALTH = 8483,
  GREAT_HEALTH = 239,
  GREAT_MANA = 238,
  ULTIMATE_MANA = 26029,
}

-- Healing rune IDs
local RUNE_IDS = {
  ULTIMATE_HEALING = 3160,  -- UH rune
  INTENSE_HEALING = 3152,   -- IH rune
}

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _state = {
  -- Cached friend list { name = { creature, lastHp, lastUpdate, priority } }
  friends = {},
  
  -- Last action timestamps
  lastHeal = 0,
  lastPotion = 0,
  lastRune = 0,
  lastSpell = 0,
  lastScan = 0,
  
  -- Best target from last scan
  bestTarget = nil,
  
  -- Configuration
  config = nil,
  
  -- Event subscriptions
  subscriptions = {},
  
  -- Enabled state (DEFAULT: true for hotkey-style friend healing)
  enabled = true,
  
  -- Statistics
  healCount = 0,
  potionCount = 0,
  runeCount = 0,
  spellCount = 0
}

-- ============================================================================
-- COOLDOWN INTEGRATION
-- ============================================================================

-- Check if healing group cooldown is active (group 2)
local function isHealingGroupOnCooldown()
  if BotCore.Cooldown and BotCore.Cooldown.isHealingOnCooldown then
    return BotCore.Cooldown.isHealingOnCooldown()
  end
  if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
    return modules.game_cooldown.isGroupCooldownIconActive(2)
  end
  return false
end

-- Check if potion exhaustion is active (group 6)
local function isPotionOnCooldown()
  if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
    return modules.game_cooldown.isGroupCooldownIconActive(6)
  end
  local currentTime = now or os.time() * 1000
  return currentTime < _state.lastPotion + POTION_COOLDOWN_MS
end

-- Check if rune exhaustion is active
local function isRuneOnCooldown()
  if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
    return modules.game_cooldown.isGroupCooldownIconActive(6)
  end
  local currentTime = now or os.time() * 1000
  return currentTime < _state.lastRune + RUNE_COOLDOWN_MS
end

-- Check if can use action with custom delay
local function canUseAction(lastTime, delay)
  local currentTime = now or os.time() * 1000
  return currentTime >= lastTime + (delay or HEAL_COOLDOWN_MS)
end

-- Mark healing action used
local function markHealingUsed()
  local currentTime = now or os.time() * 1000
  _state.lastHeal = currentTime
  
  -- Update BotCore cooldown if available
  if BotCore.Cooldown and BotCore.Cooldown.markHealingUsed then
    BotCore.Cooldown.markHealingUsed(SPELL_COOLDOWN_MS)
  end
end

-- ============================================================================
-- HOTKEY-STYLE ITEM USAGE
-- ============================================================================

-- Use potion on friend using hotkey-style API
-- @param potionId: potion item ID
-- @param friend: creature to heal
-- @return boolean success
local function usePotionOnFriend(potionId, friend)
  if not potionId or not friend then return false end
  if isPotionOnCooldown() then return false end
  
  -- Use BotCore.Items if available
  if BotCore.Items and BotCore.Items.useOn then
    local success = BotCore.Items.useOn(potionId, friend, 0)
    if success then
      _state.lastPotion = now or os.time() * 1000
      _state.potionCount = _state.potionCount + 1
      return true
    end
    return false
  end
  
  -- Fallback: Direct implementation
  if g_game.getClientVersion() >= 780 and g_game.useInventoryItemWith then
    g_game.useInventoryItemWith(potionId, friend, 0)
    _state.lastPotion = now or os.time() * 1000
    _state.potionCount = _state.potionCount + 1
    return true
  end
  
  -- Legacy fallback
  if g_game.findPlayerItem then
    local item = g_game.findPlayerItem(potionId, 0)
    if item then
      g_game.useWith(item, friend, 0)
      _state.lastPotion = now or os.time() * 1000
      _state.potionCount = _state.potionCount + 1
      return true
    end
  end
  
  return false
end

-- Use healing rune on friend using hotkey-style API
-- @param runeId: rune item ID
-- @param friend: creature to heal
-- @return boolean success
local function useRuneOnFriend(runeId, friend)
  if not runeId or not friend then return false end
  if isRuneOnCooldown() then return false end
  
  -- Use BotCore.Items if available
  if BotCore.Items and BotCore.Items.useOn then
    local success = BotCore.Items.useOn(runeId, friend, 0)
    if success then
      _state.lastRune = now or os.time() * 1000
      _state.runeCount = _state.runeCount + 1
      return true
    end
    return false
  end
  
  -- Fallback: Direct implementation
  if g_game.getClientVersion() >= 780 and g_game.useInventoryItemWith then
    g_game.useInventoryItemWith(runeId, friend, 0)
    _state.lastRune = now or os.time() * 1000
    _state.runeCount = _state.runeCount + 1
    return true
  end
  
  return false
end

-- Cast healing spell on friend
-- @param spellName: spell name (e.g., "exura sio")
-- @param friendName: friend's name
-- @param manaCost: mana cost of spell
-- @return boolean success
local function castHealSpellOnFriend(spellName, friendName, manaCost)
  if not spellName or not friendName then return false end
  if isHealingGroupOnCooldown() then return false end
  
  -- Check mana
  manaCost = manaCost or 0
  local currentMana = mana and mana() or (player and player:getMana() or 0)
  if currentMana < manaCost then return false end
  
  -- Cast the spell
  local fullSpell = string.format('%s "%s"', spellName, friendName)
  if say then
    say(fullSpell)
    _state.lastSpell = now or os.time() * 1000
    _state.spellCount = _state.spellCount + 1
    markHealingUsed()
    
    -- Track for analytics
    if HuntAnalytics and HuntAnalytics.trackHealSpell then
      HuntAnalytics.trackHealSpell(fullSpell, manaCost)
    end
    
    return true
  end
  
  return false
end

-- ============================================================================
-- PURE FUNCTIONS: Targeting
-- ============================================================================

-- Get self HP percent
local function getSelfHpPercent()
  if hppercent then return hppercent() end
  if BotCore.Stats and BotCore.Stats.getHpPercent then
    return BotCore.Stats.getHpPercent()
  end
  return 100
end

-- Get self mana percent
local function getSelfMpPercent()
  if manapercent then return manapercent() end
  if BotCore.Stats and BotCore.Stats.getMpPercent then
    return BotCore.Stats.getMpPercent()
  end
  return 100
end

-- Check if we should heal friend (safety first)
local function shouldHealFriend(selfHpPercent, friendHpPercent)
  -- RULE 1: Self is critical - NEVER heal friends
  if selfHpPercent < SELF_CRITICAL_HP then
    return false, "self_critical"
  end
  
  -- RULE 2: Self is low - NEVER heal friends
  if selfHpPercent < SELF_LOW_HP then
    return false, "self_low"
  end
  
  -- RULE 3: Friend is critical - ALWAYS help
  if friendHpPercent < FRIEND_CRITICAL_HP then
    return true, "friend_critical"
  end
  
  -- RULE 4: Friend is low - Help them
  if friendHpPercent < FRIEND_LOW_HP then
    return true, "friend_low"
  end
  
  return true, "normal"
end

-- Check if creature matches friend conditions
local function isFriend(creature, config)
  if not creature or not creature:isPlayer() then return false end
  if creature:isLocalPlayer() then return false end
  
  local name = creature:getName()
  
  -- Check custom player list first (with custom HP threshold)
  if config.customPlayers and config.customPlayers[name] then
    return true, config.customPlayers[name]  -- Returns custom HP threshold
  end
  
  -- ========== Vocation filtering ==========
  -- Get creature's vocation (if available via outfit or other means)
  local voc = nil
  if creature.getVocation then voc = creature:getVocation() end
  
  local vocConditions = config.conditions or {}
  local function checkVocation()
    -- If no vocation data available, allow all (fallback)
    if not voc then return true end
    
    local vocLower = type(voc) == "string" and voc:lower() or ""
    
    -- Check enabled vocations
    if vocConditions.knights and (voc == 8 or vocLower:find("knight")) then return true end
    if vocConditions.paladins and (voc == 7 or vocLower:find("paladin")) then return true end
    if vocConditions.druids and (voc == 6 or vocLower:find("druid")) then return true end
    if vocConditions.sorcerers and (voc == 5 or vocLower:find("sorcerer")) then return true end
    
    -- If any vocation filter is enabled but doesn't match, reject
    if vocConditions.knights or vocConditions.paladins or vocConditions.druids or vocConditions.sorcerers then
      return false
    end
    
    return true
  end
  
  if not checkVocation() then
    return false
  end
  
  -- ========== Group filtering ==========
  -- Check party membership
  if vocConditions.party and creature:isPartyMember() then
    return true
  end
  
  -- Check guild membership
  if vocConditions.guild and creature:getEmblem() == 1 then
    return true
  end
  
  -- Check friends list (g_game.isFriend)
  if vocConditions.friends then
    local friendCheck = g_game and g_game.isFriend and g_game.isFriend(name)
    if friendCheck then return true end
  end
  
  -- Check BotServer members
  if vocConditions.botserver and nExBot and nExBot.BotServerMembers then
    if nExBot.BotServerMembers[name] then
      return true
    end
  end
  
  return false
end

-- Calculate urgency score for friend
local function calculateUrgency(hpPercent, distance)
  if not hpPercent or hpPercent >= 100 then return 0 end
  
  local urgency = 100 - hpPercent
  local distancePenalty = (distance or 0) * 2
  urgency = urgency - distancePenalty
  
  return math.max(0, math.min(100, urgency))
end

-- ============================================================================
-- HEALING ACTIONS (Fully integrated with UI config)
-- ============================================================================

-- Count friends in range for area heals
local function countFriendsInRange(config, maxRange)
  local count = 0
  local spectators = getSpectators and getSpectators() or {}
  
  for _, spec in ipairs(spectators) do
    if spec:isPlayer() and not spec:isLocalPlayer() then
      local hp = spec:getHealthPercent()
      local pos = spec:getPosition()
      local dist = pos and distanceFromPlayer and distanceFromPlayer(pos) or 99
      local isFriendMatch = isFriend(spec, config)
      
      if isFriendMatch and dist <= maxRange and hp < (config.settings and config.settings.healAt or 80) then
        count = count + 1
      end
    end
  end
  
  return count
end

-- Plan the best healing action for a friend
-- @param friend: creature object
-- @param friendHp: friend's HP percent
-- @param config: healing configuration from UI
-- @return action table or nil
--
-- UI Config Fields Used:
--   config.useHealthItem      - Enable UH rune on friend (hotkey-style)
--   config.useManaItem        - Enable mana potion on friend
--   config.useSio             - Enable exura sio spell
--   config.useGranSio         - Enable exura gran sio spell
--   config.useMasRes          - Enable exura gran mas res (area heal)
--   config.customSpell        - Enable custom healing spell
--   config.customSpellName    - Name of custom spell
--   config.settings.healAt    - HP% threshold to heal (default 80)
--   config.settings.granSioAt - HP% threshold for gran sio (default 40)
--   config.settings.itemRange - Max range for item use (default 6)
--   config.settings.masResPlayers - Min players for mas res (default 2)
--   config.settings.healthItem - UH rune ID (default 3160)
--   config.settings.manaItem  - Mana potion ID (default 268)
--   config.settings.minPlayerHp - Min self HP% to help friends
--   config.settings.minPlayerMp - Min self MP% to help friends
--
function FriendHealerEnhanced.planHealAction(friend, friendHp, config)
  if not friend or not config then return nil end
  
  local settings = config.settings or {}
  local selfHp = getSelfHpPercent()
  local selfMp = getSelfMpPercent()
  local currentMana = mana and mana() or 0
  local friendName = friend:getName()
  local friendPos = friend:getPosition()
  local distance = friendPos and distanceFromPlayer and distanceFromPlayer(friendPos) or 99
  
  -- Config values from UI
  local healAt = settings.healAt or 80
  local granSioAt = settings.granSioAt or 40
  local itemRange = settings.itemRange or 6
  local masResPlayers = settings.masResPlayers or 2
  local minSelfHp = settings.minPlayerHp or 80
  local minSelfMp = settings.minPlayerMp or 50
  local healthItemId = settings.healthItem or RUNE_IDS.ULTIMATE_HEALING
  local manaItemId = settings.manaItem or POTION_IDS.GREAT_MANA
  
  -- Safety check - self first
  local shouldHeal, reason = shouldHealFriend(selfHp, friendHp)
  if not shouldHeal then
    return nil
  end
  
  -- Check minimum self requirements from UI
  if selfHp < minSelfHp or selfMp < minSelfMp then
    return nil
  end
  
  -- ========== PRIORITY 1: Custom Spell (user-defined spell like "exura" variations) ==========
  if config.customSpell and config.customSpellName and friendHp < healAt then
    local customSpell = config.customSpellName
    local manaCost = 100  -- Default, could be configurable
    if currentMana >= manaCost and not isHealingGroupOnCooldown() and distance <= 7 then
      return {
        type = "spell",
        spell = customSpell,
        targetName = friendName,
        manaCost = manaCost,
        urgency = calculateUrgency(friendHp, distance),
        source = "customSpell"
      }
    end
  end
  
  -- ========== PRIORITY 2: Exura Gran Sio (strong single target heal) ==========
  if config.useGranSio and friendHp < granSioAt then
    local manaCost = 140
    if currentMana >= manaCost and not isHealingGroupOnCooldown() and distance <= 7 then
      return {
        type = "spell",
        spell = "exura gran sio",
        targetName = friendName,
        manaCost = manaCost,
        urgency = calculateUrgency(friendHp, distance),
        source = "granSio"
      }
    end
  end
  
  -- ========== PRIORITY 3: Exura Sio (normal single target heal) ==========
  if config.useSio and friendHp < healAt then
    local manaCost = 100
    if currentMana >= manaCost and not isHealingGroupOnCooldown() and distance <= 7 then
      return {
        type = "spell",
        spell = "exura sio",
        targetName = friendName,
        manaCost = manaCost,
        urgency = calculateUrgency(friendHp, distance),
        source = "sio"
      }
    end
  end
  
  -- ========== PRIORITY 4: Exura Gran Mas Res (area heal, requires min players) ==========
  if config.useMasRes and friendHp < healAt then
    local friendsNeedingHeal = countFriendsInRange(config, 7)
    if friendsNeedingHeal >= masResPlayers then
      local manaCost = 150
      if currentMana >= manaCost and not isHealingGroupOnCooldown() then
        return {
          type = "area_spell",
          spell = "exura gran mas res",
          manaCost = manaCost,
          friendCount = friendsNeedingHeal,
          urgency = calculateUrgency(friendHp, distance),
          source = "masRes"
        }
      end
    end
  end
  
  -- ========== PRIORITY 5: Health Item / UH Rune (hotkey-style) ==========
  if config.useHealthItem and friendHp < healAt then
    if not isRuneOnCooldown() and distance <= itemRange and friend:canShoot() then
      return {
        type = "rune",
        runeId = healthItemId,
        target = friend,
        name = friendName,
        urgency = calculateUrgency(friendHp, distance),
        source = "healthItem"
      }
    end
  end
  
  -- ========== PRIORITY 6: Mana Item (for supporting mage friends) ==========
  -- Note: Mana potions typically require close range (distance <= 1)
  if config.useManaItem then
    -- Only use mana items if friend's mana is low (requires BotServer sync)
    -- For now, only use on friends explicitly marked for mana support
    if config.manaFriends and config.manaFriends[friendName] then
      if not isPotionOnCooldown() and distance <= 1 then
        return {
          type = "mana_potion",
          potionId = manaItemId,
          target = friend,
          name = friendName,
          source = "manaItem"
        }
      end
    end
  end
  
  return nil
end

-- Execute a planned healing action (with hotkey-style support)
-- @param action: action from planHealAction()
-- @return boolean success
function FriendHealerEnhanced.executeAction(action)
  if not action then return false end
  
  if action.type == "rune" then
    -- Hotkey-style UH rune on friend
    local success = useRuneOnFriend(action.runeId, action.target)
    if success then
      markHealingUsed()
      _state.healCount = (_state.healCount or 0) + 1
      if EventBus then
        EventBus.emit("friend:heal_rune", action.name, action.runeId, action.source)
      end
    end
    return success
    
  elseif action.type == "potion" or action.type == "mana_potion" then
    -- Hotkey-style potion on friend
    local success = usePotionOnFriend(action.potionId, action.target)
    if success then
      _state.potionCount = (_state.potionCount or 0) + 1
      if EventBus then
        EventBus.emit("friend:heal_potion", action.name, action.potionId, action.source)
      end
    end
    return success
    
  elseif action.type == "spell" then
    -- Single target heal spell (exura sio, exura gran sio, custom)
    local success = castHealSpellOnFriend(action.spell, action.targetName, action.manaCost)
    if success then
      _state.spellCount = (_state.spellCount or 0) + 1
      if EventBus then
        EventBus.emit("friend:heal_spell", action.targetName, action.spell, action.source)
      end
    end
    return success
    
  elseif action.type == "area_spell" then
    -- Area heal spell (exura gran mas res) - no target needed
    if isHealingGroupOnCooldown() then return false end
    
    local currentMana = mana and mana() or 0
    if currentMana < action.manaCost then return false end
    
    if say then
      say(action.spell)
      _state.lastSpell = now or os.time() * 1000
      _state.spellCount = (_state.spellCount or 0) + 1
      markHealingUsed()
      
      -- Track for analytics
      if HuntAnalytics and HuntAnalytics.trackHealSpell then
        HuntAnalytics.trackHealSpell(action.spell, action.manaCost)
      end
      
      if EventBus then
        EventBus.emit("friend:area_heal", action.spell, action.friendCount, action.source)
      end
      
      return true
    end
    return false
  end
  
  return false
end

-- ============================================================================
-- MAIN TICK AND SCANNING
-- ============================================================================

-- Find best friend to heal from spectators
function FriendHealerEnhanced.findBestTarget(config)
  local spectators = getSpectators and getSpectators() or {}
  local selfHp = getSelfHpPercent()
  local bestTarget = nil
  local bestUrgency = 0
  
  for _, spec in ipairs(spectators) do
    local isFriendMatch, customHp = isFriend(spec, config)
    if isFriendMatch then
      local hp = spec:getHealthPercent()
      local pos = spec:getPosition()
      local dist = pos and distanceFromPlayer and distanceFromPlayer(pos) or 99
      
      -- Check if in healing range
      if dist <= 7 and spec:canShoot() then
        local healThreshold = customHp or config.settings and config.settings.healAt or 80
        
        if hp < healThreshold then
          local shouldHeal = shouldHealFriend(selfHp, hp)
          if shouldHeal then
            local urgency = calculateUrgency(hp, dist)
            if urgency > bestUrgency then
              bestTarget = {
                creature = spec,
                name = spec:getName(),
                hp = hp,
                distance = dist,
                urgency = urgency,
                customHp = customHp
              }
              bestUrgency = urgency
            end
          end
        end
      end
    end
  end
  
  return bestTarget
end

-- Main tick function
function FriendHealerEnhanced.tick()
  if not _state.enabled or not _state.config then return false end
  
  -- Rate limit scanning
  local currentTime = now or os.time() * 1000
  if (currentTime - _state.lastScan) < SCAN_INTERVAL_MS then
    -- Use cached target
    if _state.bestTarget and _state.bestTarget.creature then
      local hp = _state.bestTarget.creature:getHealthPercent()
      if hp and hp < 100 then
        local action = FriendHealerEnhanced.planHealAction(
          _state.bestTarget.creature,
          hp,
          _state.config
        )
        return FriendHealerEnhanced.executeAction(action)
      end
    end
    return false
  end
  _state.lastScan = currentTime
  
  -- Find best target
  local bestTarget = FriendHealerEnhanced.findBestTarget(_state.config)
  _state.bestTarget = bestTarget
  
  if bestTarget then
    local action = FriendHealerEnhanced.planHealAction(
      bestTarget.creature,
      bestTarget.hp,
      _state.config
    )
    return FriendHealerEnhanced.executeAction(action)
  end
  
  return false
end

-- ============================================================================
-- EVENTBUS INTEGRATION
-- ============================================================================

function FriendHealerEnhanced.setupEventListeners()
  if not EventBus then return end
  
  -- Clean up old subscriptions
  FriendHealerEnhanced.cleanup()
  
  -- React to friend health drops (instant response)
  _state.subscriptions[#_state.subscriptions + 1] = EventBus.on("creature:health", function(creature, percent)
    if not _state.enabled or not _state.config then return end
    if not creature or creature:isLocalPlayer() then return end
    
    -- Check if this is a friend
    local isFriendMatch = isFriend(creature, _state.config)
    if not isFriendMatch then return end
    
    -- Check if HP dropped significantly (burst damage detection)
    local lastHp = _state.friends[creature:getName()] and _state.friends[creature:getName()].lastHp or 100
    local drop = lastHp - percent
    
    -- Update tracking
    _state.friends[creature:getName()] = {
      creature = creature,
      lastHp = percent,
      lastUpdate = now or os.time() * 1000
    }
    
    -- React to significant drops (10% or more)
    if drop >= 10 and percent < 70 then
      schedule(25, function()
        if creature and not creature:isDead() then
          local action = FriendHealerEnhanced.planHealAction(creature, percent, _state.config)
          FriendHealerEnhanced.executeAction(action)
        end
      end)
    end
  end, 60)  -- High priority
  
  -- React to friend appearing (track HP)
  _state.subscriptions[#_state.subscriptions + 1] = EventBus.on("player:appear", function(creature)
    if not _state.enabled or not _state.config then return end
    
    local isFriendMatch = isFriend(creature, _state.config)
    if isFriendMatch then
      _state.friends[creature:getName()] = {
        creature = creature,
        lastHp = creature:getHealthPercent(),
        lastUpdate = now or os.time() * 1000
      }
    end
  end, 30)
  
  -- Clean up when friend disappears
  _state.subscriptions[#_state.subscriptions + 1] = EventBus.on("player:disappear", function(creature)
    if creature then
      _state.friends[creature:getName()] = nil
    end
  end, 30)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function FriendHealerEnhanced.init(config)
  _state.config = config
  _state.enabled = true
  FriendHealerEnhanced.setupEventListeners()
end

function FriendHealerEnhanced.setConfig(config)
  _state.config = config
end

function FriendHealerEnhanced.setEnabled(enabled)
  _state.enabled = enabled
end

function FriendHealerEnhanced.isEnabled()
  return _state.enabled
end

function FriendHealerEnhanced.getBestTarget()
  return _state.bestTarget
end

function FriendHealerEnhanced.getStats()
  return {
    healCount = _state.healCount,
    potionCount = _state.potionCount,
    runeCount = _state.runeCount,
    spellCount = _state.spellCount
  }
end

function FriendHealerEnhanced.cleanup()
  for _, unsub in ipairs(_state.subscriptions) do
    if type(unsub) == "function" then
      unsub()
    end
  end
  _state.subscriptions = {}
  _state.friends = {}
end

-- ============================================================================
-- BACKWARD COMPATIBILITY (for new_healer.lua integration)
-- ============================================================================

-- Event handler: Friend health changed (legacy API - EventBus handles this internally)
function FriendHealerEnhanced.onFriendHealthChange(creature, newHpPercent, oldHpPercent)
  if not _state.enabled then return end
  if not creature or creature:isLocalPlayer() then return end
  
  local config = _state.config
  if not config then return end
  
  -- Only react to significant drops
  local drop = (oldHpPercent or 100) - newHpPercent
  if drop < 10 then return end
  
  -- Check if this is a friend
  local isFriendMatch = isFriend(creature, config)
  if not isFriendMatch then return end
  
  -- Get self HP
  local selfHpPercent = getSelfHpPercent()
  
  -- Safety check - never heal friends if we're low
  if selfHpPercent < SELF_LOW_HP then return end
  
  -- Check urgency
  local urgency = calculateUrgency(newHpPercent, 3)
  if urgency > 50 then
    -- This is urgent! Try to heal immediately
    local action = FriendHealerEnhanced.planHealAction(creature, newHpPercent, config)
    FriendHealerEnhanced.executeAction(action)
  end
end

return FriendHealerEnhanced
