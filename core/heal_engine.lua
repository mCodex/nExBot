--[[
  Heal Engine v2.0 - Safety-Critical Healing System
  
  This is the core healing decision engine for HealBot and FriendHealer.
  CRITICAL MODULE: Player death can occur if this fails!
  
  Design Principles:
    - SRP: Single responsibility for each function
    - DRY: No duplicate logic, shared utilities
    - KISS: Simple, readable, predictable logic
    - SOLID: Open for extension, closed for modification
    - Safety-First: Player self-healing ALWAYS has priority
  
  Cooldown Integration:
    - Uses BotCore.Cooldown as single source of truth
    - Shares exhaustion state with FriendHealer
    - Falls back to local tracking if BotCore unavailable
  
  v2.0 Changes:
    - Fixed spell eligibility logic (mana cost was not checked!)
    - Fixed HP threshold comparison bugs
    - Added emergency fallback healing
    - Unified cooldown management with BotCore
    - Reduced event debounce for faster reaction
    - Added detailed logging for debugging
]]

-- ============================================================================
-- MODULE INITIALIZATION
-- ============================================================================

HealEngine = HealEngine or {}

local VERSION = "2.0.0"

-- ============================================================================
-- PRIVATE STATE (Encapsulated)
-- ============================================================================

-- Local cooldown tracking (shared across sessions)
local cooldowns = {}

-- Feature toggles (controlled by HealBot UI)
local options = {
  selfSpells = false,
  potions = false,
  friendHeals = false,
}

-- Spell/Potion lists (populated by HealBot)
local selfSpells = {}
local selfPotions = {}

-- Friend healing spells (default config)
local friendSpells = {
  { name = "exura gran sio", key = "exura gran sio", hp = 50, mpCost = 140, cd = 1100, prio = 1 },
  { name = "exura sio", key = "exura sio", hp = 80, mpCost = 100, cd = 1100, prio = 2 },
}

-- Emergency fallback spell (last resort when HP critical)
local emergencySpell = { name = "exura vita", key = "exura_vita_emergency", cd = 1500, mpCost = 40 }

-- Event debounce (25ms for burst damage protection)
local lastEventHeal = 0
local EVENT_DEBOUNCE_MS = 25

-- ============================================================================
-- LOGGING
-- ============================================================================

local VERBOSE = (type(nExBotVerbose) == "boolean" and nExBotVerbose) or false

local function logDebug(msg)
  if VERBOSE then warn("[HealEngine] " .. msg) end
end

local function logWarn(msg)
  warn("[HealEngine] " .. msg)
end

local function logCritical(msg)
  warn("[HealEngine][CRITICAL] " .. msg)
end

-- Optional potion debug mode (opt-in): when enabled, HealEngine will emit
-- short diagnostics about why potions were/weren't selected or used.
local _potionDebug = false
function HealEngine.setPotionDebug(flag)
  _potionDebug = not not flag
end

-- ============================================================================
-- TIME UTILITIES
-- ============================================================================

local function nowMs()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

-- ============================================================================
-- COOLDOWN MANAGEMENT (Unified with BotCore.Cooldown)
-- ============================================================================

-- Check if healing group cooldown is active
local function isHealingGroupOnCooldown()
  if BotCore and BotCore.Cooldown and BotCore.Cooldown.isHealingOnCooldown then
    return BotCore.Cooldown.isHealingOnCooldown()
  end
  if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
    return modules.game_cooldown.isGroupCooldownIconActive(2)
  end
  return false
end

-- Alias for backwards compatibility
local function healingGroupReady()
  return not isHealingGroupOnCooldown()
end

-- Check if potion exhaustion is active
local function isPotionOnCooldown()
  if BotCore and BotCore.Cooldown and BotCore.Cooldown.canUsePotion then
    return not BotCore.Cooldown.canUsePotion()
  end
  if nExBot and nExBot.isUsingPotion then return true end
  if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
    return modules.game_cooldown.isGroupCooldownIconActive(6)
  end
  return false
end

-- Alias for backwards compatibility
local function potionReady()
  return not isPotionOnCooldown()
end

-- Check individual action cooldown
local function ready(key, cd)
  if not key then return true end
  local last = cooldowns[key] or 0
  return (nowMs() - last) >= (cd or 1000)
end

-- Mark action as used
local function stamp(key)
  if key then
    cooldowns[key] = nowMs()
  end
end

-- Mark healing action used (notify BotCore.Cooldown for FriendHealer sync)
local function markHealingUsed(cd)
  if BotCore and BotCore.Cooldown and BotCore.Cooldown.markHealingUsed then
    BotCore.Cooldown.markHealingUsed(cd or 1100)
  end
end

-- Mark potion used
local function markPotionUsed()
  if BotCore and BotCore.Cooldown and BotCore.Cooldown.markPotionUsed then
    BotCore.Cooldown.markPotionUsed()
  end
end

-- ============================================================================
-- STAT ACCESSORS (Safe fallbacks)
-- ============================================================================

local function getHpPercent()
  if hppercent then return hppercent() or 0 end
  if player and player.getHealthPercent then return player:getHealthPercent() or 0 end
  return 100
end

local function getMpPercent()
  if manapercent then return manapercent() or 0 end
  if player and player.getManaPercent then return player:getManaPercent() or 0 end
  return 100
end

local function getCurrentMana()
  if mana then return mana() or 0 end
  if player and player.getMana then return player:getMana() or 0 end
  return 0
end

local function getInPz()
  if isInPz then return isInPz() end
  return false
end

local function canUseItem()
  return potionReady()
end

-- ============================================================================
-- POTION USAGE (Safe wrapper - now prioritizes hotkey-style usage)
-- ============================================================================

local function useItemSafe(itemId)
  if not itemId or itemId <= 0 then return false end

  -- Primary: prefer BotCore.Items abstraction when available
  if BotCore and BotCore.Items and BotCore.Items.useOn then
    local ok, res = SafeCall.call(BotCore.Items.useOn, itemId, player)
    if ok then return true end
  end

  -- Try client hotkey-style API (works with closed containers on many OTC clients)
  if g_game and g_game.useInventoryItemWith and player then
    local ok, res = SafeCall.call(g_game.useInventoryItemWith, itemId, player, 0)
    if ok then return true end
  end

  -- Fallback: direct useInventoryItem (some clients support this)
  if g_game and g_game.useInventoryItem then
    local ok, res = SafeCall.call(g_game.useInventoryItem, itemId)
    if ok then return true end
  end

  -- Try to find the actual item instance in player's containers and useWith it
  if g_game and g_game.findPlayerItem and player then
    local ok, inst = SafeCall.call(g_game.findPlayerItem, itemId)
    if ok and inst then
      local ok2, res2 = SafeCall.call(g_game.useWith, inst, player)
      if ok2 then return true end
    end
  end

  -- Legacy fallback: global findItem + SafeCall
  if findItem and player then
    local item = findItem(itemId)
    if item then
      SafeCall.useWith(item, player)
      return true
    end
  end

  -- Nothing worked
  logDebug(string.format("useItemSafe: failed to use item id=%s", tostring(itemId)))
  return false
end

local function canUseItem()
  return potionReady()
end

-- ============================================================================
-- LIST MANAGEMENT
-- ============================================================================

local function sortByPrio(list)
  if not list or #list <= 1 then return end
  table.sort(list, function(a, b)
    if a.hp and b.hp and a.hp ~= b.hp then
      return a.hp < b.hp
    end
    return (a.prio or 999) < (b.prio or 999)
  end)
end
sortByPrio(friendSpells)

-- ============================================================================
-- PUBLIC API: Configuration
-- ============================================================================

-- Configure feature usage; accepts partial table {selfSpells?, potions?, friendHeals?}
function HealEngine.configure(opts)
  if not opts then return end
  if opts.selfSpells ~= nil then options.selfSpells = opts.selfSpells end
  if opts.potions ~= nil then options.potions = opts.potions end
  if opts.friendHeals ~= nil then options.friendHeals = opts.friendHeals end
  logDebug(string.format("configure: selfSpells=%s potions=%s friendHeals=%s",
    tostring(options.selfSpells), tostring(options.potions), tostring(options.friendHeals)))
end

-- Set custom spell list (from HealBot configuration)
function HealEngine.setCustomSpells(spellList)
  if spellList and type(spellList) == "table" then
    local normalized = {}
    for i, s in ipairs(spellList) do
      if s and s.name then
        table.insert(normalized, {
          name = s.name,
          key = (s.key or s.name):lower(),
          hp = s.hp,
          mp = s.mp,
          op = s.op or s.sign or "<",
          mana = s.mana or s.cost or 0,
          cd = s.cd or 1100,
          prio = s.prio or i
        })
      end
    end
    selfSpells = normalized
    sortByPrio(selfSpells)
    logDebug(string.format("setCustomSpells: loaded %d spells", #selfSpells))
    if #selfSpells == 0 then
      -- Silently attempt resync if UI has spells but engine doesn't
      if HealBot and HealBot.applyHealEngineToggles then
        pcall(HealBot.applyHealEngineToggles)
      end
    end
  end
  -- Clear pending flag
  HealEngine._pendingSpells = nil
end

-- Emergency fallback spell (used when configured spells fail and HP critical)
-- Last line of defense against player death
local fallbackSpell = { name = "exura vita", key = "exura_vita_emergency", cd = 1500, mpCost = 40 }

-- Set custom potion list (from HealBot configuration)  
function HealEngine.setCustomPotions(potionList)
  if potionList and type(potionList) == "table" then
    local normalized = {}
    for i, p in ipairs(potionList) do
      if p then
        table.insert(normalized, {
          id = p.id,
          hp = p.hp,
          mp = p.mp,
          key = p.key or (p.id and tostring(p.id)) or ("potion_" .. i),
          cd = p.cd or 1000,
          prio = p.prio or i
        })
      end
    end
    selfPotions = normalized
    sortByPrio(selfPotions)
    logDebug(string.format("setCustomPotions: loaded %d potions", #selfPotions))
  end
  -- Clear pending flag
  HealEngine._pendingPotions = nil
end

-- Debug helper: attempt to use a potion by id (returns true on success)
function HealEngine.tryUsePotionById(itemId)
  if not itemId or itemId <= 0 then return false end
  local action = { kind = "potion", id = itemId, key = "potion_test_" .. tostring(itemId), cd = 1000, name = "potion_test", potionType = "mana" }
  if _potionDebug then warn(string.format("[HealEngine][POTION_DEBUG] tryUsePotionById: attempting to use id=%d", itemId)) end
  local ok = execute(action)
  if _potionDebug then warn(string.format("[HealEngine][POTION_DEBUG] tryUsePotionById: result=%s", tostring(ok))) end
  return ok
end

function HealEngine.setSelfSpellsEnabled(flag)
  options.selfSpells = not not flag
end

function HealEngine.setPotionsEnabled(flag)
  options.potions = not not flag
end

function HealEngine.setFriendHealingEnabled(flag)
  options.friendHeals = not not flag
end

-- Public status for debugging: returns current toggles and counts
function HealEngine.getStatus()
  return {
    version = VERSION,
    selfSpells = options.selfSpells,
    potions = options.potions,
    friendHeals = options.friendHeals,
    spellsLoaded = #selfSpells,
    potionsLoaded = #selfPotions,
    healingGroupOnCooldown = isHealingGroupOnCooldown(),
    potionOnCooldown = isPotionOnCooldown()
  }
end

-- Get loaded spells for debugging
function HealEngine.getLoadedSpells()
  return selfSpells
end

-- Get loaded potions for debugging
function HealEngine.getLoadedPotions()
  return selfPotions
end

-- Select best self action based on snapshot
-- CRITICAL: This is the main healing decision function!
function HealEngine.planSelf(snap)
  local hp = snap.hp or getHpPercent()
  local mp = snap.mp or getMpPercent()
  local inPz = snap.inPz
  if inPz == nil then inPz = getInPz() end
  local emergency = false -- Emergency disabled by user request

  logDebug(string.format("planSelf: hp=%.1f mp=%.1f spells=%d potions=%d emergency=%s inPz=%s", 
    hp, mp, #selfSpells, #selfPotions, tostring(emergency), tostring(inPz)))

  -- Pick up any pending spells/potions queued by HealBot
  if HealEngine._pendingSpells and type(HealEngine._pendingSpells) == "table" and #selfSpells == 0 then
    local ok, err = pcall(function() HealEngine.setCustomSpells(HealEngine._pendingSpells) end)
    if ok then
      logDebug(string.format("Picked up _pendingSpells, loaded=%d", #selfSpells))
    else
      logWarn(string.format("Failed to pick up _pendingSpells: %s", tostring(err)))
    end
  end
  if HealEngine._pendingPotions and type(HealEngine._pendingPotions) == "table" and #selfPotions == 0 then
    local ok, err = pcall(function() HealEngine.setCustomPotions(HealEngine._pendingPotions) end)
    if ok then
      logDebug(string.format("Picked up _pendingPotions, loaded=%d", #selfPotions))
    else
      logWarn(string.format("Failed to pick up _pendingPotions: %s", tostring(err)))
    end
  end

  -- Skip potions in PZ to avoid waste unless HP is critical
  local allowPotion = not inPz or hp <= 30
  
  -- Get current mana (absolute value, not percent) for mana cost check
  local currentMana = getCurrentMana()
  
  -- Pure predicate: decide if a spell is eligible to be cast based on current snapshot
  -- CRITICAL FIX: Now properly checks mana cost and HP threshold independently
  local function spellEligible(spell)
    if not spell then return false, "no_spell" end
    if not spell.name or spell.name == "" then return false, "invalid_spell_name" end
    
    local reasons = {}
    
    -- STEP 1: Check HP threshold (primary healing trigger)
    -- For healing spells, we want to cast when HP is AT OR BELOW the threshold
    local triggerMet = false
    
    if spell.hp then
      local op = spell.op or "<"
      if op == ">" or op == ">=" then
        -- "Above" condition: cast when HP >= threshold (unusual for healing)
        if hp >= spell.hp then
          triggerMet = true
        else
          table.insert(reasons, string.format("hp_below_threshold(%.1f<%d)", hp, spell.hp))
        end
      else
        -- "Below" condition (default): cast when HP <= threshold
        if hp <= spell.hp then
          triggerMet = true
        else
          table.insert(reasons, string.format("hp_above_threshold(%.1f>%d)", hp, spell.hp))
        end
      end
    end
    
    -- STEP 2: Check MP threshold (for mana-triggered spells like mana regen)
    -- Only applies if NO HP threshold is set (pure mana spells)
    if spell.mp and not spell.hp then
      local op = spell.op or "<"
      if op == ">" or op == ">=" then
        if mp >= spell.mp then
          triggerMet = true
        else
          table.insert(reasons, string.format("mp_below_threshold(%.1f<%d)", mp, spell.mp))
        end
      else
        if mp <= spell.mp then
          triggerMet = true
        else
          table.insert(reasons, string.format("mp_above_threshold(%.1f>%d)", mp, spell.mp))
        end
      end
    end
    
    -- If no trigger threshold met, spell is not eligible
    if not triggerMet then
      return false, #reasons > 0 and table.concat(reasons, "; ") or "no_trigger_met"
    end
    
    -- STEP 3: CRITICAL - Check if we have enough mana to cast the spell!
    -- This was MISSING in the original code and caused spells to fail silently!
    local manaCost = spell.mana or spell.cost or spell.mpCost or 0
    if manaCost > 0 and currentMana < manaCost then
      return false, string.format("insufficient_mana(%d<%d_required)", currentMana, manaCost)
    end
    
    -- STEP 4: Check healing group cooldown (shared with FriendHealer)
    if not healingGroupReady() then
      return false, "healing_group_cooldown"
    end
    
    -- STEP 5: Check individual spell cooldown
    if not ready(spell.key, spell.cd or 1100) then
      return false, "spell_individual_cooldown"
    end
    
    return true, nil
  end


  if options.selfSpells and #selfSpells > 0 then
    local rejectReasons = {}
    for _, spell in ipairs(selfSpells) do
      local ok, reason = spellEligible(spell)
      if ok then
        return {kind = "spell", name = spell.name, key = spell.key, cd = spell.cd, mana = spell.mana or spell.mana or 0}
      else
        table.insert(rejectReasons, string.format('%s => %s', spell.name or '<noname>', tostring(reason)))
      end
    end
    -- Log reasons why configured spells were not used (helpful debugging)
    if #rejectReasons > 0 then
      logDebug('[HealEngine] No eligible spells. Reasons: ' .. table.concat(rejectReasons, ' | '))
    end
    
    -- EMERGENCY FALLBACK: disabled per user request
    -- This block would cast a fallback spell when HP critically low. It has been disabled.
    -- if (emergency or hp <= 15) and fallbackSpell and healingGroupReady() and ready(fallbackSpell.key, fallbackSpell.cd) then
    --   local fallbackManaCost = fallbackSpell.mpCost or 40
    --   if currentMana >= fallbackManaCost then
    --     logCritical(string.format('EMERGENCY FALLBACK: casting %s (HP=%.1f%%, mana=%d)', fallbackSpell.name, hp, currentMana))
    --     return { kind = "spell", name = fallbackSpell.name, key = fallbackSpell.key, cd = fallbackSpell.cd, mana = fallbackManaCost }
    --   else
    --     logCritical(string.format('EMERGENCY FALLBACK FAILED: not enough mana for %s (need %d, have %d)', fallbackSpell.name, fallbackManaCost, currentMana))
    --   end
    -- end
  end


  if options.potions and #selfPotions > 0 then
    for _, pot in ipairs(selfPotions) do
      -- Get the actual potion name - prefer pot.name, then try to look up by ID
      local potionName = pot.name
      if not potionName and pot.id then
        -- Try to get item name from game data
        if g_things and g_things.getThingType then
          local thing = g_things.getThingType(pot.id, ThingCategoryItem)
          if thing then
            if thing.getName then
              local name = thing:getName()
              if name and name ~= "" then potionName = name:lower() end
            elseif thing.getMarketData then
              local marketData = thing:getMarketData()
              if marketData and marketData.name and marketData.name ~= "" then
                potionName = marketData.name:lower()
              end
            end
          end
        end
      end
      potionName = potionName or ("potion #" .. (pot.id or 0))

      -- Evaluate reasons for not selecting this pot


      if pot.hp and hp <= pot.hp and allowPotion and ready(pot.key, pot.cd) and canUseItem() then
        if VERBOSE then print("[HealBot] Executing potion: " .. tostring(potionName) .. " (id=" .. tostring(pot.id) .. ") for HP " .. tostring(hp) .. "% <= " .. tostring(pot.hp) .. "%") end
        return {kind = "potion", id = pot.id, key = pot.key, cd = pot.cd, name = potionName, potionType = "heal"}
      end

      if pot.mp and mp <= pot.mp and allowPotion and ready(pot.key, pot.cd) and canUseItem() then
        if VERBOSE then print("[HealBot] Executing potion: " .. tostring(potionName) .. " (id=" .. tostring(pot.id) .. ") for MP " .. tostring(mp) .. "% <= " .. tostring(pot.mp) .. "%") end
        return {kind = "potion", id = pot.id, key = pot.key, cd = pot.cd, name = potionName, potionType = "mana"}
      end
    end
  end

  logDebug("planSelf: no action selected")
  return nil
end

-- Debug helper: simulate a self snapshot and print planned action
function HealEngine.debugPlan(hp, mp, inPz)
  local snap = { hp = hp or getHpPercent(), mp = mp or getMpPercent(), inPz = inPz }
  local action = HealEngine.planSelf(snap)
  if not action then
    print(string.format("HealEngine.debugPlan: no action for hp=%.1f mp=%.1f inPz=%s", snap.hp, snap.mp, tostring(snap.inPz)))
    return nil
  end
  if action.kind == "potion" then
    print(string.format("HealEngine.debugPlan: selected potion id=%d name=%s type=%s", action.id or 0, action.name or "-", action.potionType or "-"))
  elseif action.kind == "spell" then
    print(string.format("HealEngine.debugPlan: selected spell %s", action.name or "-"))
  else
    print("HealEngine.debugPlan: selected action of kind=" .. tostring(action.kind))
  end
  return action
end

-- Select best friend action; target must include name and hp
-- IMPORTANT: Shares cooldowns with self-healing via BotCore.Cooldown
function HealEngine.planFriend(snap, target)
  if not options.friendHeals then return nil end
  if not target or not target.name then return nil end
  
  local hp = target.hp or 100
  local currentMana = snap.currentMana or getCurrentMana()
  local inPz = snap.inPz
  if inPz == nil then inPz = getInPz() end
  
  -- Don't heal friends in protection zone
  if inPz then return nil end
  
  for _, spell in ipairs(friendSpells) do
    local hpThreshold = spell.hp or 0
    local mpCost = spell.mpCost or spell.mp or 0
    
    -- Check if friend needs healing
    if hp <= hpThreshold then
      -- CRITICAL: Check if we have enough mana to cast!
      if currentMana >= mpCost then
        -- Check cooldowns (shared with self-healing)
        if healingGroupReady() and ready(spell.key, spell.cd or 1100) then
          logDebug(string.format("planFriend: healing '%s' (hp=%d%%) with %s", target.name, hp, spell.name))
          return {
            kind = "spell",
            name = string.format('%s "%s"', spell.name, target.name),
            key = spell.key,
            cd = spell.cd or 1100
          }
        end
      else
        logDebug(string.format("planFriend: insufficient mana for %s (need %d, have %d)", spell.name, mpCost, currentMana))
      end
    end
  end
  return nil
end

function HealEngine.execute(action)
  if not action then return false end
  
  if action.kind == "spell" then
    -- Cast the spell
    if say then
      say(action.name)
    else
      logWarn("execute: 'say' function not available!")
      return false
    end
    
    -- Mark cooldowns
    stamp(action.key)
    markHealingUsed(action.cd or 1100)
    
    -- Track for analytics
    if HuntAnalytics and HuntAnalytics.trackHealSpell then
      HuntAnalytics.trackHealSpell(action.name, action.mana or 0)
    end
    
    logDebug(string.format("execute: cast spell '%s'", action.name))
    return true
    
  elseif action.kind == "potion" then
    -- Use the potion (simplified like vBot for better OTCv8 compatibility)
    if useWith and player then
      useWith(action.id, player)
      -- Mark cooldowns
      stamp(action.key)
      markPotionUsed()
      
      -- Track for analytics
      if HuntAnalytics and HuntAnalytics.trackPotion then
        local potionType = action.potionType or "other"
        HuntAnalytics.trackPotion(action.name or "potion", potionType)
      end
      
      logDebug(string.format("execute: used potion '%s' (id=%d)", action.name or "?", action.id))
      return true
    else
      logWarn("execute: useWith or player not available for potion")
      return false
    end
  end
  
  return false
end

-- Event-driven fast-heal watcher: listen to player health/mana changes
-- CRITICAL: This provides instant reaction to damage for player safety!
do
  local registered = false
  local _lastStatEvent = 0
  local _debounceMs = 25 -- Reduced from 50ms for faster burst damage response

  local function handleSnapshot()
    local nowTime = nowMs()
    if (nowTime - _lastStatEvent) < _debounceMs then return end
    _lastStatEvent = nowTime

    local hpNow = getHpPercent()
    local mpNow = getMpPercent()
    local currentMana = getCurrentMana()

    logDebug(string.format("handleSnapshot triggered: hp=%.1f mp=%.1f mana=%d", hpNow, mpNow, currentMana))

    local snap = {
      hp = hpNow,
      mp = mpNow,
      currentMana = currentMana,
      inPz = getInPz(),
      emergency = false -- Emergency disabled by user request
    }

    local action = HealEngine.planSelf(snap)
    if action then
      logDebug(string.format("handleSnapshot executing: %s", action.name or "unknown"))
      HealEngine.execute(action)
    end
  end

  -- Primary: EventBus if available
  if EventBus then
    EventBus.on("player:health", function(health, maxHealth, oldHealth, oldMaxHealth)
      local hpNow = health and maxHealth and maxHealth > 0 and (health / maxHealth) * 100 or getHpPercent()
      local hpOld = oldHealth and oldMaxHealth and oldMaxHealth > 0 and (oldHealth / oldMaxHealth) * 100 or hpNow
      logDebug(string.format("player:health event: hpNow=%.1f hpOld=%.1f", hpNow, hpOld))
      if hpNow < hpOld then handleSnapshot() end
    end)

    EventBus.on("player:mana", function(mana, maxMana, oldMana, oldMaxMana)
      local mpNow = mana and maxMana and maxMana > 0 and (mana / maxMana) * 100 or getMpPercent()
      local mpOld = oldMana and oldMaxMana and oldMaxMana > 0 and (oldMana / oldMaxMana) * 100 or mpNow
      if mpNow < mpOld then handleSnapshot() end
    end)
    registered = true
  end

  -- Fallbacks for environments lacking EventBus: try client callback hooks
  if not registered then
    if type(onPlayerHealthChange) == 'function' then
      onPlayerHealthChange(function(healthPercent)
        -- healthPercent is absolute percent value
        handleSnapshot()
      end)
      registered = true
    end

    if type(onPlayerManaChange) == 'function' then
      onPlayerManaChange(function(manaPercent)
        handleSnapshot()
      end)
      registered = true
    end
  end

  if not registered then
    logWarn("HealEngine: no event source found (EventBus or onPlayerHealthChange). Active polling may be required.")
  end
end

logDebug("HealEngine v2.0 loaded - Safety-critical healing system")

return HealEngine


