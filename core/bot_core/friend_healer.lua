--[[
  BotCore: Friend Healer Module v3.0
  
  High-performance, event-driven friend healing system.
  Fully integrated with EventBus and HealEngine.
  
  Design Principles:
    - Event-Driven: Instant response via EventBus
    - Lazy Config: Safe access even before init
    - Priority-Based: Self-healing ALWAYS takes precedence
    - DRY: Uses HealEngine for spell execution
    - SOLID: Single responsibility, easy to extend
    - High Accuracy: Validates targets, checks cooldowns
  
  Priority Order (hardcoded for safety):
    1. Self HP critical (<30%) - NEVER heal friends
    2. Self HP low (<50%) - NEVER heal friends  
    3. Friend HP critical (<30%) - Emergency friend heal
    4. Self HP medium (<80%) - Prefer self-heal
    5. Friend HP low (<50%) - Friend needs help
    6. Normal operation - Heal whoever needs it most
    
  v3.0 Changes:
    - Removed _G references (nil in sandboxed environment)
    - Added safe config getter with defaults
    - Single EventBus registration with deduplication
    - Improved target validation with pcall safety
    - Real-time config sync with HealEngine
    - Better party/guild/custom player detection
    - Accurate HP threshold handling per-player
    - Added debug logging
]]

BotCore.FriendHealer = BotCore.FriendHealer or {}
local FriendHealer = BotCore.FriendHealer

-- Module version for debugging
FriendHealer.VERSION = "3.0.0"

-- ============================================================================
-- LOGGING
-- ============================================================================

local VERBOSE = false -- Set to true for debug output

local function logDebug(msg)
  if VERBOSE then warn("[FriendHealer] " .. msg) end
end

local function logWarn(msg)
  warn("[FriendHealer] " .. msg)
end

-- ============================================================================
-- LAZY MODULE LOADING
-- ============================================================================

-- Get HealEngine at runtime (lazy loading)
local function getHealEngine()
  if HealEngine then return HealEngine end
  local ok, eng = pcall(function()
    if storage and storage.botFolder then
      return dofile(storage.botFolder .. "/core/heal_engine.lua")
    end
  end)
  if ok and eng then 
    HealEngine = eng
    return eng 
  end
  return nil
end

-- Get HealContext at runtime (lazy loading)
local function getHealContext()
  if HealContext then return HealContext end
  local ok, ctx = pcall(function()
    if storage and storage.botFolder then
      return dofile(storage.botFolder .. "/core/heal_context.lua")
    end
  end)
  if ok and ctx then 
    HealContext = ctx
    return ctx 
  end
  return nil
end

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local SELF_CRITICAL_HP = 30      -- Below this: NEVER heal friends
local SELF_LOW_HP = 50           -- Below this: NEVER heal friends
local SELF_MEDIUM_HP = 80        -- Below this: Prefer self-heal
local FRIEND_CRITICAL_HP = 30    -- Friend emergency threshold
local FRIEND_LOW_HP = 50         -- Friend needs urgent help
local MAX_HEAL_RANGE = 7         -- Maximum range for sio spells
local SCAN_INTERVAL_MS = 100     -- How often to scan for friends
local HEAL_COOLDOWN_MS = 1000    -- Minimum time between heals

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

local _state = {
  -- Configuration reference (set by init)
  config = nil,
  
  -- Module enabled state
  enabled = false,
  
  -- Cached friend list
  friends = {},
  
  -- Best target from last scan
  bestTarget = nil,
  
  -- Timing
  lastScan = 0,
  lastHeal = 0,
  
  -- EventBus registration tracking
  eventBusRegistered = false
}

-- ============================================================================
-- SAFE CONFIG ACCESS
-- ============================================================================

-- Safe config getter (returns defaults if config not ready)
local function getConfig()
  local cfg = _state.config
  if not cfg then
    return {
      enabled = false,
      customPlayers = {},
      conditions = {
        party = true,
        guild = false,
        friends = false,
        botserver = false,
        knights = true,
        paladins = true,
        druids = false,
        sorcerers = false
      },
      settings = {
        healAt = 80,
        granSioAt = 40,
        minPlayerHp = 80,
        minPlayerMp = 50
      },
      useSio = true,
      useGranSio = true
    }
  end
  return cfg
end

-- ============================================================================
-- PLAYER STATS HELPERS
-- ============================================================================

local function getSelfHpPercent()
  if BotCore.Stats and BotCore.Stats.getHpPercent then
    return BotCore.Stats.getHpPercent()
  end
  if hppercent then return hppercent() end
  if player then
    local ok, hp, maxHp = pcall(function() 
      return player:getHealth(), player:getMaxHealth() 
    end)
    if ok and maxHp and maxHp > 0 then return (hp / maxHp) * 100 end
  end
  return 100
end

local function getSelfMpPercent()
  if BotCore.Stats and BotCore.Stats.getMpPercent then
    return BotCore.Stats.getMpPercent()
  end
  if manapercent then return manapercent() end
  if player then
    local ok, mp, maxMp = pcall(function()
      return player:getMana(), player:getMaxMana()
    end)
    if ok and maxMp and maxMp > 0 then return (mp / maxMp) * 100 end
  end
  return 100
end

local function getCurrentMana()
  if mana then return mana() end
  if player and player.getMana then 
    local ok, m = pcall(function() return player:getMana() end)
    if ok then return m end
  end
  return 0
end

-- ============================================================================
-- PURE FUNCTIONS: Health Calculations
-- ============================================================================

-- Calculate heal urgency score (0-100, higher = more urgent)
local function calculateUrgency(hpPercent, distanceFromPlayer)
  if not hpPercent or hpPercent >= 100 then return 0 end
  
  -- Base urgency: inverse of HP (100 - HP)
  local urgency = 100 - hpPercent
  
  -- Distance penalty: further = less urgent
  local distancePenalty = (distanceFromPlayer or 0) * 2
  urgency = urgency - distancePenalty
  
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

-- ============================================================================
-- CREATURE VALIDATION (with pcall safety)
-- ============================================================================

-- Get creature name safely
local function getCreatureName(creature)
  if not creature then return nil end
  local ok, name = pcall(function() return creature:getName() end)
  if ok and name and name ~= "" then return name end
  return nil
end

-- Get creature HP safely
local function getCreatureHp(creature)
  if not creature then return 100 end
  local ok, hp = pcall(function() return creature:getHealthPercent() end)
  if ok and hp then return hp end
  return 100
end

-- Get creature position safely
local function getCreaturePos(creature)
  if not creature then return nil end
  local ok, pos = pcall(function() return creature:getPosition() end)
  if ok and pos then return pos end
  return nil
end

-- Calculate distance from player to position
local function getDistanceToPlayer(pos)
  if not pos then return 99 end
  if distanceFromPlayer then
    local ok, dist = pcall(distanceFromPlayer, pos)
    if ok and dist then return dist end
  end
  -- Fallback: manual calculation
  if player then
    local ok, playerPos = pcall(function() return player:getPosition() end)
    if ok and playerPos then
      local dx = math.abs(pos.x - playerPos.x)
      local dy = math.abs(pos.y - playerPos.y)
      return math.max(dx, dy)
    end
  end
  return 99
end

-- Check if creature can be shot (line of sight)
local function canShootCreature(creature)
  if not creature then return false end
  local ok, canShoot = pcall(function() return creature:canShoot() end)
  if ok then return canShoot end
  return true -- Assume yes if we can't check
end

-- Check if creature is a valid heal candidate
local function isValidCreature(creature)
  if not creature then return false end
  local ok, isPlayer = pcall(function() return creature:isPlayer() end)
  if not ok or not isPlayer then return false end
  local ok2, isLocal = pcall(function() return creature:isLocalPlayer() end)
  if ok2 and isLocal then return false end
  return true
end

-- ============================================================================
-- CONDITION MATCHING (with pcall safety)
-- ============================================================================

-- Check if creature matches configured conditions
local function matchesConditions(creature, config)
  if not isValidCreature(creature) then return false end
  
  local name = getCreatureName(creature)
  if not name then return false end
  
  -- Check custom player list first (highest priority)
  if config.customPlayers and config.customPlayers[name] then
    logDebug("matchesConditions: " .. name .. " is in custom list")
    return true
  end
  
  -- Check party membership
  if config.conditions.party then
    local ok, isParty = pcall(function() return creature:isPartyMember() end)
    if ok and isParty then 
      logDebug("matchesConditions: " .. name .. " is party member")
      return true 
    end
  end
  
  -- Check guild membership (emblem = 1 means same guild)
  if config.conditions.guild then
    local ok, emblem = pcall(function() return creature:getEmblem() end)
    if ok and emblem == 1 then 
      logDebug("matchesConditions: " .. name .. " is guild member")
      return true 
    end
  end
  
  -- Check friends list (OTClient VIP list)
  if config.conditions.friends then
    if isFriend and type(isFriend) == "function" then
      local ok, result = pcall(isFriend, creature)
      if ok and result then 
        logDebug("matchesConditions: " .. name .. " is in friends list")
        return true 
      end
    end
  end
  
  -- Check BotServer members
  if config.conditions.botserver then
    if nExBot and nExBot.BotServerMembers and nExBot.BotServerMembers[name] then
      logDebug("matchesConditions: " .. name .. " is BotServer member")
      return true
    end
  end
  
  return false
end

-- Check vocation filter
local function matchesVocation(creature, config)
  -- If checkPlayer is not enabled, allow all
  if not storage or not storage.extras or not storage.extras.checkPlayer then
    return true
  end
  
  local ok, specText = pcall(function() return creature:getText() or "" end)
  if not ok or not specText or specText == "" then 
    return true -- No info available, allow
  end
  
  -- Check each vocation - if detected and not allowed, return false
  if specText:find("EK") and not config.conditions.knights then return false end
  if specText:find("RP") and not config.conditions.paladins then return false end
  if specText:find("ED") and not config.conditions.druids then return false end
  if specText:find("MS") and not config.conditions.sorcerers then return false end
  
  return true
end

-- ============================================================================
-- TARGET SELECTION
-- ============================================================================

-- Find best healing target from spectators
local function findBestTarget(config, selfHpPercent)
  local bestTarget = nil
  local bestUrgency = 0
  
  -- Get spectators
  local spectators = {}
  if getSpectators then
    local ok, specs = pcall(getSpectators)
    if ok and specs then spectators = specs end
  end
  
  for _, creature in ipairs(spectators) do
    -- Skip non-matching creatures
    if matchesConditions(creature, config) and matchesVocation(creature, config) then
      local name = getCreatureName(creature)
      local hp = getCreatureHp(creature)
      local pos = getCreaturePos(creature)
      local dist = getDistanceToPlayer(pos)
      
      -- Check if in healing range and has line of sight
      if dist <= MAX_HEAL_RANGE and canShootCreature(creature) then
        -- Get custom HP threshold for this player
        local customHp = config.customPlayers and config.customPlayers[name]
        local healThreshold = customHp or config.settings.healAt or 80
        
        -- Check if needs healing
        if hp <= healThreshold then
          local urgency = calculateUrgency(hp, dist)
          
          -- Should we heal this friend?
          local shouldHeal, reason = shouldHealFriend(selfHpPercent, hp, urgency)
          
          if shouldHeal and urgency > bestUrgency then
            bestTarget = {
              creature = creature,
              name = name,
              hp = hp,
              distance = dist,
              urgency = urgency,
              reason = reason,
              customHp = customHp
            }
            bestUrgency = urgency
            logDebug(string.format("Found target: %s hp=%d%% dist=%d urgency=%.1f", 
              name, hp, dist, urgency))
          end
        end
      end
    end
  end
  
  return bestTarget
end



-- Mark that we used a heal
local function markHealUsed()
  local currentTime = now or os.time() * 1000
  _state.lastHeal = currentTime
  
  if BotCore.Cooldown and BotCore.Cooldown.markHealingUsed then
    BotCore.Cooldown.markHealingUsed(HEAL_COOLDOWN_MS)
  elseif BotCore.Priority and BotCore.Priority.markExhausted then
    BotCore.Priority.markExhausted("healing", HEAL_COOLDOWN_MS)
  end
end

-- Check if healing is on cooldown
local function isHealingOnCooldown()
  if BotCore.Cooldown and BotCore.Cooldown.isHealingOnCooldown then
    return BotCore.Cooldown.isHealingOnCooldown()
  end
  if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
    return modules.game_cooldown.isGroupCooldownIconActive(2)
  end
  return false
end

-- ============================================================================
-- HEAL EXECUTION
-- ============================================================================

-- Execute heal on target using HealEngine or direct cast
local function executeHeal(target, config)
  if not target or not target.creature or not target.name then 
    return false 
  end
  
  -- Check cooldown first
  if isHealingOnCooldown() then
    logDebug("Heal on cooldown, skipping")
    return false
  end
  
  local engine = getHealEngine()
  local context = getHealContext()
  
  -- Try HealEngine first (proper cooldown sync, mana checks)
  if engine and engine.planFriend and engine.execute then
    local snap = context and context.get() or {}
    
    -- Ensure currentMana is passed
    if not snap.currentMana then
      snap.currentMana = getCurrentMana()
    end
    
    -- Check protection zone
    if not snap.inPz then
      if getInPz then
        local ok, inPz = pcall(getInPz)
        if ok then snap.inPz = inPz end
      end
    end
    
    if snap.inPz then
      logDebug("In protection zone, skipping heal")
      return false
    end
    
    local action = engine.planFriend(snap, target)
    if action then
      local success = engine.execute(action)
      if success then
        markHealUsed()
        logDebug(string.format("Healed %s with %s", target.name, action.name or "spell"))
        return true
      end
    end
  end
  
  -- Fallback: Direct spell cast
  if say then
    local hp = target.hp or 100
    local granSioAt = config.settings.granSioAt or 40
    
    -- Choose spell based on HP
    local spellName = "exura sio"
    if hp <= granSioAt and config.useGranSio then
      spellName = "exura gran sio"
    end
    
    -- Check mana
    local currentMana = getCurrentMana()
    local requiredMana = spellName == "exura gran sio" and 140 or 100
    
    if currentMana < requiredMana then
      logDebug(string.format("Insufficient mana for %s (need %d, have %d)", 
        spellName, requiredMana, currentMana))
      return false
    end
    
    -- Cast spell
    say(string.format('%s "%s"', spellName, target.name))
    markHealUsed()
    logDebug(string.format("Fallback heal: %s on %s", spellName, target.name))
    return true
  end
  
  return false
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Initialize with config reference
function FriendHealer.init(config)
  _state.config = config
  _state.enabled = config and config.enabled or false
  logDebug(string.format("Initialized v%s with enabled=%s", FriendHealer.VERSION, tostring(_state.enabled)))
  
  -- Sync HealEngine friend spells
  FriendHealer.syncHealEngineSpells()
end

-- Set enabled state
function FriendHealer.setEnabled(enabled)
  _state.enabled = enabled
  logDebug(string.format("setEnabled: %s", tostring(enabled)))
  
  -- Also sync to HealEngine
  local engine = getHealEngine()
  if engine and engine.setFriendHealingEnabled then
    engine.setFriendHealingEnabled(enabled)
  end
end

-- Check if enabled
function FriendHealer.isEnabled()
  return _state.enabled and _state.config and _state.config.enabled
end

-- Get current best target (for UI display)
function FriendHealer.getBestTarget()
  return _state.bestTarget
end

-- Sync friend spells to HealEngine based on current config
function FriendHealer.syncHealEngineSpells()
  local config = getConfig()
  local engine = getHealEngine()
  
  if not engine then
    logDebug("syncHealEngineSpells: HealEngine not available")
    return
  end
  
  -- Enable/disable friend healing in engine
  if engine.setFriendHealingEnabled then
    engine.setFriendHealingEnabled(_state.enabled and config.enabled)
  end
  
  -- Configure spells if function available
  if not engine.setFriendSpells then
    logDebug("syncHealEngineSpells: setFriendSpells not available")
    return
  end
  
  local friendSpells = {}
  local healAt = config.settings.healAt or 80
  local granSioAt = config.settings.granSioAt or 40
  
  if config.useGranSio then
    table.insert(friendSpells, {
      name = "exura gran sio",
      hp = granSioAt,
      mpCost = 140,
      cd = 1100,
      prio = 1
    })
  end
  
  if config.useSio then
    table.insert(friendSpells, {
      name = "exura sio",
      hp = healAt,
      mpCost = 100,
      cd = 1100,
      prio = 2
    })
  end
  
  if config.customSpell and config.customSpellName and config.customSpellName ~= "Custom Spell" then
    table.insert(friendSpells, {
      name = config.customSpellName,
      hp = healAt,
      mpCost = 50,
      cd = 1100,
      prio = 3
    })
  end
  
  if #friendSpells > 0 then
    engine.setFriendSpells(friendSpells)
    logDebug(string.format("Synced %d friend spells to HealEngine", #friendSpells))
  end
end

-- Main tick function - called by macro
function FriendHealer.tick()
  if not FriendHealer.isEnabled() then return false end

  local config = getConfig()
  
  -- Get self HP/MP using safe helpers
  local selfHpPercent = getSelfHpPercent()
  local selfMpPercent = getSelfMpPercent()
  
  -- SAFETY: Never heal friends if self is in danger
  if selfHpPercent < SELF_LOW_HP then
    _state.bestTarget = nil
    return false
  end
  
  -- Check minimum HP/MP requirements from config
  local minSelfHp = config.settings.minPlayerHp or 80
  local minSelfMp = config.settings.minPlayerMp or 50
  
  if selfHpPercent < minSelfHp or selfMpPercent < minSelfMp then
    _state.bestTarget = nil
    return false
  end
  
  -- Rate limit scanning
  local currentTime = now or os.time() * 1000
  if (currentTime - _state.lastScan) < SCAN_INTERVAL_MS then
    -- Use cached target if still valid
    if _state.bestTarget and _state.bestTarget.creature then
      local hp = getCreatureHp(_state.bestTarget.creature)
      local customHp = config.customPlayers and config.customPlayers[_state.bestTarget.name]
      local healThreshold = customHp or config.settings.healAt or 80
      
      if hp <= healThreshold and hp < 100 then
        return executeHeal(_state.bestTarget, config)
      else
        _state.bestTarget = nil
      end
    end
    return false
  end
  _state.lastScan = currentTime
  
  -- Find best target (spectators are fetched inside)
  local bestTarget = findBestTarget(config, selfHpPercent)
  _state.bestTarget = bestTarget
  
  -- Execute heal if target found
  if bestTarget then
    return executeHeal(bestTarget, config)
  end
  
  return false
end

-- Event handler: Friend health changed (for instant response)
function FriendHealer.onFriendHealthChange(creature, newHpPercent, oldHpPercent)
  if not FriendHealer.isEnabled() then return end
  if not creature then return end
  
  -- Skip local player
  local ok, isLocal = pcall(function() return creature:isLocalPlayer() end)
  if ok and isLocal then return end
  
  local config = getConfig()
  if not config.enabled then return end
  
  -- Get creature name
  local name = getCreatureName(creature)
  if not name then return end
  
  -- Check if this is a configured friend
  if not matchesConditions(creature, config) then return end
  
  -- Get self HP for safety check
  local selfHpPercent = getSelfHpPercent()
  
  -- Safety check: don't heal friends if self is low
  if selfHpPercent < SELF_LOW_HP then return end
  
  -- Check min HP/MP requirements
  local minSelfHp = config.settings.minPlayerHp or 80
  local minSelfMp = config.settings.minPlayerMp or 50
  local selfMpPercent = getSelfMpPercent()
  
  if selfHpPercent < minSelfHp or selfMpPercent < minSelfMp then return end
  
  -- Get custom HP threshold for this player
  local customHp = config.customPlayers and config.customPlayers[name]
  local healThreshold = customHp or config.settings.healAt or 80
  
  -- Check if friend needs healing
  if newHpPercent > healThreshold then return end
  
  -- Calculate urgency based on HP drop
  local drop = (oldHpPercent or 100) - (newHpPercent or 100)
  local urgency = calculateUrgency(newHpPercent, 3) -- Assume medium distance
  
  -- For event-driven healing, respond to significant drops or low HP
  if urgency > 30 or drop >= 10 or newHpPercent < FRIEND_CRITICAL_HP then
    -- Get distance for range check
    local pos = getCreaturePos(creature)
    local dist = getDistanceToPlayer(pos)
    
    -- Check if in healing range
    if dist <= MAX_HEAL_RANGE and canShootCreature(creature) then
      local target = {
        creature = creature,
        name = name,
        hp = newHpPercent,
        distance = dist,
        urgency = urgency,
        reason = "event_response",
        customHp = customHp
      }
      
      -- Update cached target
      _state.bestTarget = target
      
      logDebug(string.format("Event heal: %s dropped to %d%% (was %d%%)", 
        name, newHpPercent, oldHpPercent or 100))
      
      -- Execute heal immediately
      executeHeal(target, config)
    end
  end
end

-- ============================================================================
-- EVENTBUS REGISTRATION (Single point, with deduplication)
-- ============================================================================

local function registerEventBusHandlers()
  -- Prevent double registration
  if _state.eventBusRegistered then 
    logDebug("EventBus handlers already registered")
    return true 
  end
  
  if not EventBus then 
    logDebug("EventBus not available")
    return false 
  end
  
  -- Subscribe to friend health changes with high priority (150)
  EventBus.on("friend:health", function(creature, newHp, oldHp)
    FriendHealer.onFriendHealthChange(creature, newHp, oldHp)
  end, 150)
  
  -- Also listen to generic creature health for backup
  -- (catches party members before they're detected as friends)
  EventBus.on("creature:health", function(creature, newHp, oldHp)
    -- Skip monsters
    local ok, isPlayer = pcall(function() return creature:isPlayer() end)
    if not ok or not isPlayer then return end
    
    -- Skip local player
    local ok2, isLocal = pcall(function() return creature:isLocalPlayer() end)
    if ok2 and isLocal then return end
    
    -- Forward to handler (it will check conditions)
    FriendHealer.onFriendHealthChange(creature, newHp, oldHp)
  end, 100)
  
  _state.eventBusRegistered = true
  logDebug("EventBus handlers registered successfully")
  return true
end

-- Initialize EventBus handlers
registerEventBusHandlers()

-- ============================================================================
-- EXPORT
-- ============================================================================

BotCore.FriendHealer = FriendHealer
logDebug("FriendHealer v" .. FriendHealer.VERSION .. " loaded")
