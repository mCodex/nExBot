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

-- SafeCreature is loaded early in boot; require it (no inline duplication)
if not SafeCreature then
  warn("[FriendHealer] SafeCreature module not loaded – friend healer disabled")
  return
end
local SC = SafeCreature

-- Module version for debugging
FriendHealerEnhanced.VERSION = "3.0.1"

-- CONSTANTS

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

-- PRIVATE STATE

local _state = {
  friends = {},
  lastScan = 0,
  bestTarget = nil,
  config = nil,
  subscriptions = {},
  enabled = true,
  healCount = 0,
  potionCount = 0,
  runeCount = 0,
  spellCount = 0
}

-- COOLDOWN INTEGRATION (delegates to BotCore.Cooldown — single source of truth)

local function isHealingGroupOnCooldown()
  if BotCore.Cooldown and BotCore.Cooldown.isHealingOnCooldown then
    return BotCore.Cooldown.isHealingOnCooldown()
  end
  return false
end

local function isPotionOnCooldown()
  if BotCore.Cooldown and BotCore.Cooldown.canUsePotion then
    return not BotCore.Cooldown.canUsePotion()
  end
  return false
end

-- ponytail: rune cooldown reuses potion group (group 6) — BotCore.Cooldown
-- doesn't expose a rune-specific check yet; add if rune cooldowns diverge.
local function isRuneOnCooldown()
  return isPotionOnCooldown()
end

local function markHealingUsed()
  if BotCore.Cooldown and BotCore.Cooldown.markHealingUsed then
    BotCore.Cooldown.markHealingUsed(SPELL_COOLDOWN_MS)
  end
end

-- HOTKEY-STYLE ITEM USAGE (delegates to BotCore.Items)

local function useItemOnFriend(itemId, friend)
  if not itemId or not friend then return false end
  if isPotionOnCooldown() then return false end

  if BotCore.Items and BotCore.Items.useOn then
    return BotCore.Items.useOn(itemId, friend, 0)
  end

  -- ponytail: fallback for when BotCore.Items isn't loaded yet
  if g_game and g_game.useInventoryItemWith then
    g_game.useInventoryItemWith(itemId, friend, 0)
    return true
  end
  return false
end

-- Cast healing spell on friend
local function castHealSpellOnFriend(spellName, friendName, manaCost)
  if not spellName or not friendName then return false end
  if isHealingGroupOnCooldown() then return false end

  manaCost = manaCost or 0
  local currentMana = (BotCore.Stats and BotCore.Stats.getMp) and BotCore.Stats.getMp()
    or (mana and mana()) or 0
  if currentMana < manaCost then return false end

  local fullSpell = string.format('%s "%s"', spellName, friendName)
  if say then
    say(fullSpell)
    markHealingUsed()
    if HuntAnalytics and HuntAnalytics.trackHealSpell then
      HuntAnalytics.trackHealSpell(fullSpell, manaCost)
    end
    return true
  end
  return false
end

-- PURE FUNCTIONS: Targeting (delegates to BotCore.Stats)

local function getSelfHpPercent()
  if BotCore.Stats and BotCore.Stats.getHpPercent then
    return BotCore.Stats.getHpPercent()
  end
  if hppercent then return hppercent() end
  return 100
end

local function getSelfMpPercent()
  if BotCore.Stats and BotCore.Stats.getMpPercent then
    return BotCore.Stats.getMpPercent()
  end
  if manapercent then return manapercent() end
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

-- Check if creature matches friend conditions (improved with SafeCreature module)
-- Vocation short-code to condition key mapping (DRY: single map, no if-chains)
local VOC_CONDITION_MAP = {
  EK = "knights", RP = "paladins", ED = "druids", MS = "sorcerers", MN = "monks"
}

local function isFriendForHealing(creature, config)
  if not creature then return false end
  if not SC.isPlayer(creature) then return false end
  
  local okLocal, isLocal = pcall(function() return creature:isLocalPlayer() end)
  if okLocal and isLocal then return false end
  
  local name = SC.getName(creature)
  if not name then return false end
  
  -- Custom player list has highest priority (with custom HP threshold)
  if config.customPlayers and config.customPlayers[name] then
    return true, config.customPlayers[name]
  end
  
  -- Vocation filtering via VocationUtils (DRY: uses shared lookup map)
  local vocConditions = config.conditions or {}
  if VocationUtils and VocationUtils.getCreatureVocationShort then
    local short = VocationUtils.getCreatureVocationShort(creature)
    local condKey = short and VOC_CONDITION_MAP[short]
    if condKey then
      if not vocConditions[condKey] then return false end
    end
  end
  
  -- Group filtering: party, guild, friends list
  if vocConditions.party then
    local okP, isP = pcall(function() return creature:isPartyMember() end)
    if okP and isP then return true end
  end
  if vocConditions.guild then
    local okE, emb = pcall(function() return creature:getEmblem() end)
    if okE and emb == 1 then return true end
  end
  -- Integrate with global isFriend() from lib.lua (uses storage.playerList.friendList)
  if vocConditions.friends then
    local globalFriend = _G.isFriend and _G.isFriend(creature)
    if globalFriend then return true end
  end
  
  return false
end

-- Alias for backward compat (local scope)
local isFriend = isFriendForHealing

-- Calculate urgency score for friend
local function calculateUrgency(hpPercent, distance)
  if not hpPercent or hpPercent >= 100 then return 0 end
  
  local urgency = 100 - hpPercent
  local distancePenalty = (distance or 0) * 2
  urgency = urgency - distancePenalty
  
  return math.max(0, math.min(100, urgency))
end

-- HEALING ACTIONS (Fully integrated with UI config)

-- Count friends in range for area heals (improved with safe API calls)
local function countFriendsInRange(config, maxRange)
  local count = 0
  local spectators = getSpectators and getSpectators() or {}
  
  for _, spec in ipairs(spectators) do
    -- Safely check if player
    local okPlayer, isPlayer = pcall(function() return spec:isPlayer() end)
    local okLocal, isLocal = pcall(function() return spec:isLocalPlayer() end)
    
    if okPlayer and isPlayer and (not okLocal or not isLocal) then
      local okHp, hp = pcall(function() return spec:getHealthPercent() end)
      local okPos, pos = pcall(function() return spec:getPosition() end)
      
      if okHp and hp then
        local dist = (okPos and pos and distanceFromPlayer) and distanceFromPlayer(pos) or 99
        local isFriendMatch = isFriend(spec, config)
        
        if isFriendMatch and dist <= maxRange and hp < (config.settings and config.settings.healAt or 80) then
          count = count + 1
        end
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
--   config.useTioSio          - Enable exura tio sio spell
--   config.useMasRes          - Enable exura gran mas res (area heal)
--   config.customSpell        - Enable custom healing spell
--   config.customSpellName    - Name of custom spell
--   config.settings.healAt    - HP% threshold to heal (default 80)
--   config.settings.granSioAt - HP% threshold for gran sio (default 40)
--   config.settings.tioSioAt  - HP% threshold for tio sio (default 65)
--   config.settings.itemRange - Max range for item use (default 6)
--   config.settings.masResPlayers - Min players for mas res (default 2)
--   config.settings.healthItem - UH rune ID (default 3160)
--   config.settings.manaItem  - Mana potion ID (default 268)
--   config.settings.minPlayerHp - Min self HP% to help friends
--   config.settings.minPlayerMp - Min self MP% to help friends
--
-- Build ally spell list from config flags
local function buildAllySpellList(config, healAt, granSioAt, tioSioAt, distance)
  local list = {}
  if config.customSpell and config.customSpellName and distance <= 7 then
    list[#list + 1] = {name = config.customSpellName, key = config.customSpellName:lower(), hp = healAt, mpCost = 100, cd = 1100, prio = 1}
  end
  if config.useGranSio and distance <= 7 then
    list[#list + 1] = {name = "exura gran sio", key = "exura_gran_sio", hp = granSioAt, mpCost = 140, cd = 1100, prio = 2}
  end
  if config.useTioSio and distance <= 7 then
    list[#list + 1] = {name = "exura tio sio", key = "exura_tio_sio", hp = tioSioAt, mpCost = 120, cd = 1100, prio = 3}
  end
  if config.useSio and distance <= 7 then
    list[#list + 1] = {name = "exura sio", key = "exura_sio", hp = healAt, mpCost = 100, cd = 1100, prio = 4}
  end
  return list
end

function FriendHealerEnhanced.planHealAction(friend, friendHp, config)
  if not friend or not config then return nil end
  
  local settings = config.settings or {}
  local selfHp = getSelfHpPercent()
  local selfMp = getSelfMpPercent()
  
  -- Safely get friend properties
  local okName, friendName = pcall(function() return friend:getName() end)
  local okPos, friendPos = pcall(function() return friend:getPosition() end)
  if not okName or not friendName then return nil end
  
  local distance = (okPos and friendPos and distanceFromPlayer) and distanceFromPlayer(friendPos) or 99
  
  -- Config values from UI
  local healAt = settings.healAt or 80
  local granSioAt = settings.granSioAt or 40
  local tioSioAt = settings.tioSioAt or 65
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
  
  -- ========== DELEGATE SPELL SELECTION TO HEALENGINE ==========
  -- Build spell list from config priorities and let HealEngine pick the best
  if HealEngine and HealEngine.evaluateAlly then
    local spellList = buildAllySpellList(config, healAt, granSioAt, tioSioAt, distance)
    if #spellList > 0 then
      local engineAction = HealEngine.evaluateAlly(friend, friendHp, spellList)
      if engineAction then
        return {
          type = "spell",
          spell = engineAction.name,
          targetName = friendName,
          manaCost = engineAction.mana or 100,
          urgency = calculateUrgency(friendHp, distance),
          source = "healEngine"
        }
      end
    end
  end
  
  -- ========== EXURA GRAN MAS RES (area heal, requires min players) ==========
  if config.useMasRes and friendHp < healAt then
    local friendsNeedingHeal = countFriendsInRange(config, 7)
    if friendsNeedingHeal >= masResPlayers then
      if not isHealingGroupOnCooldown() then
        return {
          type = "area_spell",
          spell = "exura gran mas res",
          manaCost = 150,
          friendCount = friendsNeedingHeal,
          urgency = calculateUrgency(friendHp, distance),
          source = "masRes"
        }
      end
    end
  end
  
  -- ========== HEALTH ITEM / UH RUNE (hotkey-style) ==========
  if config.useHealthItem and friendHp < healAt then
    local okShoot, canShoot = pcall(function() return friend:canShoot() end)
    if not isRuneOnCooldown() and distance <= itemRange and (not okShoot or canShoot) then
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
  
  -- ========== MANA ITEM (for supporting mage friends) ==========
  if config.useManaItem then
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
    local success = useItemOnFriend(action.runeId, action.target)
    if success then
      markHealingUsed()
      _state.healCount = _state.healCount + 1
      if EventBus then
        EventBus.emit("friend:heal_rune", action.name, action.runeId, action.source)
      end
    end
    return success

  elseif action.type == "potion" or action.type == "mana_potion" then
    local success = useItemOnFriend(action.potionId, action.target)
    if success then
      _state.potionCount = _state.potionCount + 1
      if EventBus then
        EventBus.emit("friend:heal_potion", action.name, action.potionId, action.source)
      end
    end
    return success
    
  elseif action.type == "spell" then
    -- Single target heal spell (exura sio, exura tio sio, exura gran sio, custom)
    local success = castHealSpellOnFriend(action.spell, action.targetName, action.manaCost)
    if success then
      _state.spellCount = (_state.spellCount or 0) + 1
      if EventBus then
        EventBus.emit("friend:heal_spell", action.targetName, action.spell, action.source)
      end
    end
    return success
    
  elseif action.type == "area_spell" then
    if isHealingGroupOnCooldown() then return false end
    local currentMana = (BotCore.Stats and BotCore.Stats.getMp) and BotCore.Stats.getMp()
      or (mana and mana()) or 0
    if currentMana < action.manaCost then return false end
    if say then
      say(action.spell)
      _state.spellCount = _state.spellCount + 1
      markHealingUsed()
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

-- MAIN TICK AND SCANNING

-- Find best friend to heal from spectators (improved with safe API calls)
function FriendHealerEnhanced.findBestTarget(config)
  local spectators = getSpectators and getSpectators() or {}
  local selfHp = getSelfHpPercent()
  local bestTarget = nil
  local bestUrgency = 0
  
  for _, spec in ipairs(spectators) do
    -- Safely check if this is a friend
    local isFriendMatch, customHp = isFriend(spec, config)
    if isFriendMatch then
      -- Safely get creature properties
      local okHp, hp = pcall(function() return spec:getHealthPercent() end)
      local okPos, pos = pcall(function() return spec:getPosition() end)
      local okName, name = pcall(function() return spec:getName() end)
      local okShoot, canShoot = pcall(function() return spec:canShoot() end)
      
      -- Skip if we can't get basic info
      if okHp and okName and hp and name then
        local dist = (okPos and pos and distanceFromPlayer) and distanceFromPlayer(pos) or 99
        
        -- Check if in healing range
        if dist <= 7 and (not okShoot or canShoot) then
          local healThreshold = customHp or config.settings and config.settings.healAt or 80
          
          if hp < healThreshold then
            local shouldHeal = shouldHealFriend(selfHp, hp)
            if shouldHeal then
              local urgency = calculateUrgency(hp, dist)
              if urgency > bestUrgency then
                bestTarget = {
                  creature = spec,
                  name = name,
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
  end
  
  return bestTarget
end

-- Main tick function (improved with safe getters)
function FriendHealerEnhanced.tick()
  if not _state.enabled or not _state.config then return false end
  
  -- Rate limit scanning
  local currentTime = now or os.time() * 1000
  if (currentTime - _state.lastScan) < SCAN_INTERVAL_MS then
    -- Use cached target for faster response
    if _state.bestTarget and _state.bestTarget.creature then
      -- Safely get current HP
      local ok, hp = pcall(function() return _state.bestTarget.creature:getHealthPercent() end)
      if ok and hp and hp < 100 then
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

-- EVENTBUS INTEGRATION (Improved for accuracy and performance)

-- DRY: Reuse SafeCreature instead of duplicating pcall wrappers
local safeGetName = SC.getName
local safeGetHpPercent = SC.getHealthPercent
local safeIsDead = SC.isDead

function FriendHealerEnhanced.setupEventListeners()
  if not EventBus then return end
  
  -- Clean up old subscriptions
  FriendHealerEnhanced.cleanup()
  
  -- PRIORITY 1: React to friend:health event (directly emitted for friends/party members)
  -- This is more efficient as it's pre-filtered by EventBus
  _state.subscriptions[#_state.subscriptions + 1] = EventBus.on("friend:health", function(creature, percent, oldPercent)
    if not _state.enabled or not _state.config then return end
    if not creature then return end
    
    local name = safeGetName(creature)
    if not name then return end
    
    -- Check if this is a friend according to our config
    local isFriendMatch = isFriend(creature, _state.config)
    if not isFriendMatch then return end
    
    -- Calculate drop
    local drop = (oldPercent or 100) - percent
    
    -- Update tracking
    _state.friends[name] = {
      creature = creature,
      lastHp = percent,
      lastUpdate = now or os.time() * 1000
    }
    
    -- React immediately if:
    -- 1. Significant drop (10%+) OR
    -- 2. Friend is below critical threshold
    local healAt = _state.config.settings and _state.config.settings.healAt or 80
    local shouldReact = (drop >= 10 and percent < 70) or (percent < healAt and percent < 50)
    
    if shouldReact then
      -- React with minimal delay for responsiveness
      schedule(15, function()
        if not safeIsDead(creature) then
          local currentHp = safeGetHpPercent(creature) or percent
          local action = FriendHealerEnhanced.planHealAction(creature, currentHp, _state.config)
          FriendHealerEnhanced.executeAction(action)
        end
      end)
    end
  end, 80)  -- Very high priority for friend healing
  
  -- PRIORITY 2: React to creature:health for any creatures (backup)
  _state.subscriptions[#_state.subscriptions + 1] = EventBus.on("creature:health", function(creature, percent, oldPercent)
    if not _state.enabled or not _state.config then return end
    if not creature then return end
    
    -- Skip local player
    local okLocal, isLocal = pcall(function() return creature:isLocalPlayer() end)
    if okLocal and isLocal then return end
    
    -- Only process players
    local okPlayer, isPlayer = pcall(function() return creature:isPlayer() end)
    if not okPlayer or not isPlayer then return end
    
    local name = safeGetName(creature)
    if not name then return end
    
    -- Check if this is a friend
    local isFriendMatch = isFriend(creature, _state.config)
    if not isFriendMatch then return end
    
    -- Calculate drop
    local prevHp = _state.friends[name] and _state.friends[name].lastHp or (oldPercent or 100)
    local drop = prevHp - percent
    
    -- Update tracking
    _state.friends[name] = {
      creature = creature,
      lastHp = percent,
      lastUpdate = now or os.time() * 1000
    }
    
    -- React to significant drops
    if drop >= 10 and percent < 70 then
      schedule(25, function()
        if not safeIsDead(creature) then
          local currentHp = safeGetHpPercent(creature) or percent
          local action = FriendHealerEnhanced.planHealAction(creature, currentHp, _state.config)
          FriendHealerEnhanced.executeAction(action)
        end
      end)
    end
  end, 50)  -- Medium-high priority (lower than friend:health)
  
  -- React to friend appearing (track HP)
  _state.subscriptions[#_state.subscriptions + 1] = EventBus.on("player:appear", function(creature)
    if not _state.enabled or not _state.config then return end
    if not creature then return end
    
    local isFriendMatch = isFriend(creature, _state.config)
    if isFriendMatch then
      local name = safeGetName(creature)
      local hp = safeGetHpPercent(creature)
      if name and hp then
        _state.friends[name] = {
          creature = creature,
          lastHp = hp,
          lastUpdate = now or os.time() * 1000
        }
      end
    end
  end, 30)
  
  -- Clean up when friend disappears
  _state.subscriptions[#_state.subscriptions + 1] = EventBus.on("player:disappear", function(creature)
    if creature then
      local name = safeGetName(creature)
      if name then
        _state.friends[name] = nil
      end
    end
  end, 30)
end

-- PUBLIC API

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

-- BACKWARD COMPATIBILITY (for new_healer.lua integration)

-- Event handler: Friend health changed (legacy API - EventBus handles this internally)
function FriendHealerEnhanced.onFriendHealthChange(creature, newHpPercent, oldHpPercent)
  if not _state.enabled then return end
  if not creature then return end
  
  -- Skip local player (safe)
  local ok, isLocal = pcall(function() return creature:isLocalPlayer() end)
  if ok and isLocal then return end
  
  local config = _state.config
  if not config or not config.enabled then return end
  
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
