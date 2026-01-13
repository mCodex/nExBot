local targetbotMacro = nil
local config = nil
local lastAction = 0
local cavebotAllowance = 0
local lureEnabled = true

-- MonsterAI automatic integration (hidden internals, not exposed to UI/storage)
local MONSTERAI_INTEGRATION = true
local MONSTERAI_IMMINENT_ACTION = "avoid"  -- "avoid" = attempt escape, "wait" = pause attacking
local MONSTERAI_MIN_CONF = 0.6
local monsterAIWaitUntil = 0

local dangerValue = 0
local looterStatus = ""
-- initialization state
local pendingEnable = false
local pendingEnableDesired = nil
local moduleInitialized = false
local _lastTargetbotSlowWarn = 0

-- Local cached reference to local player (updated on relogin)
local player = g_game and g_game.getLocalPlayer() or nil

-- Safe function calls to prevent "attempt to call global function (a nil value)" errors
local SafeCall = SafeCall or require("core.safe_call")

-- Compatibility: robust safe unpack (works when neither table.unpack nor unpack exist)
local function _unpack(tbl)
  if not tbl then return end
  if table and table.unpack then return table.unpack(tbl) end
  if unpack then return unpack(tbl) end
  local n = #tbl
  if n == 0 then return end
  if n == 1 then return tbl[1] end
  if n == 2 then return tbl[1], tbl[2] end
  if n == 3 then return tbl[1], tbl[2], tbl[3] end
  if n == 4 then return tbl[1], tbl[2], tbl[3], tbl[4] end
  if n == 5 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5] end
  if n == 6 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6] end
  if n == 7 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7] end
  if n == 8 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7], tbl[8] end
  if n == 9 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7], tbl[8], tbl[9] end
  if n == 10 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7], tbl[8], tbl[9], tbl[10] end
  if n == 11 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7], tbl[8], tbl[9], tbl[10], tbl[11] end
  if n == 12 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7], tbl[8], tbl[9], tbl[10], tbl[11], tbl[12] end
  -- Fallback: return first 12 elements
  return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7], tbl[8], tbl[9], tbl[10], tbl[11], tbl[12]
end

-- Attack watchdog to recover from indecision (rate-limited)
local attackWatchdog = {
  lastForce = 0,
  attempts = 0,
  cooldown = 800,
  maxAttempts = 2
}

-- Aggressive relogin recovery: force re-attempts for a short window after relogin
local reloginRecovery = {
  active = false,       -- whether the aggressive recovery is active
  endTime = 0,          -- when to stop aggressive retries
  duration = 5000,      -- default aggressive recovery duration (ms)
  lastAttempt = 0,      -- last forced attempt timestamp
  interval = 400        -- attempt every 400ms while active
}

-- Pull System state (shared with CaveBot)
TargetBot = TargetBot or {}
TargetBot.smartPullActive = false  -- When true, CaveBot pauses waypoint walking

-- Use TargetBotCore if available (DRY principle)
local Core = TargetCore or {}
-- Spectator cache to reduce expensive g_map.getSpectatorsInRange calls
local SpectatorCache = SpectatorCache or (type(require) == 'function' and (function() local ok, mod = pcall(require, "utils.spectator_cache"); if ok then return mod end; return nil end)() or nil)

-- Creature type constants for clarity
local CREATURE_TYPE = {
  PLAYER = 0,
  MONSTER = 1,      -- Targetable monster
  NPC = 2,
  SUMMON = 3        -- Non-targetable (other player's summons)
}

-- Pre-allocated constants for pathfinding (PERFORMANCE: avoid table creation in loop)
local PATH_PARAMS = {
  ignoreLastCreature = true,
  ignoreNonPathable = true,
  ignoreCost = true,
  ignoreCreatures = true,
  allowOnlyVisibleTiles = true,  -- OTCLIENT API: Safety first
  precision = 1
}

-- OTCLIENT API: Enhanced pathfinding parameters for different scenarios
local PATH_PARAMS_AGGRESSIVE = {
  ignoreLastCreature = true,
  ignoreNonPathable = true,
  ignoreCost = true,
  ignoreCreatures = false,  -- Allow weaving through creatures for evasion
  allowOnlyVisibleTiles = true,
  precision = 0  -- Faster for emergency moves
}

local PATH_PARAMS_CONSERVATIVE = {
  ignoreLastCreature = true,
  ignoreNonPathable = true,
  ignoreCost = true,
  ignoreCreatures = true,
  allowOnlyVisibleTiles = true,
  allowUnseen = false,  -- Never use unseen tiles for safety
  precision = 2  -- More precise for positioning
}

-- Pre-allocated status strings (PERFORMANCE: avoid string concatenation)
local STATUS_ATTACKING = "Attacking"
local STATUS_ATTACKING_LURE_OFF = "Attacking (luring off)"
local STATUS_PULLING = "Pulling (using CaveBot)"
local STATUS_WAITING = "Waiting"
local STATUS_ATTACK_PREFIX = "Attack & "

--------------------------------------------------------------------------------
-- PERFORMANCE: Optimized Creature Cache
-- Uses event-driven updates with LRU eviction and TargetCore integration
--------------------------------------------------------------------------------
local CreatureCache = {
  monsters = {},          -- {id -> {creature, path, params, lastUpdate, priority}}
  monsterCount = 0,
  bestTarget = nil,
  bestPriority = 0,
  totalDanger = 0,
  dirty = true,           -- Flag to recalculate on next tick
  lastFullUpdate = 0,
  FULL_UPDATE_INTERVAL = 400,  -- Reduced for faster adaptation
  PATH_TTL = 250,         -- Path cache valid for 250ms (faster invalidation)
  lastCleanup = 0,
  CLEANUP_INTERVAL = 1500,
  -- LRU eviction
  accessOrder = {},       -- Array of IDs in access order
  maxSize = 50            -- Max cached creatures
}

-- Mark cache as dirty (needs recalculation)
local function invalidateCache()
  CreatureCache.dirty = true
end

-- Helper to set UI status text on the right side only when changed (reduces layout churn)
local _lastStatusRight = nil
local function setStatusRight(text)
  if not ui or not ui.status or not ui.status.right then return end
  local cur = nil
  pcall(function() cur = ui.status.right:getText() end)
  if cur ~= text then
    pcall(function() ui.status.right:setText(text) end)
    _lastStatusRight = text
  end
end

-- Safe creature text setter: only set when different to avoid constant layout updates
local function setCreatureTextSafe(creature, text)
  if not creature or not text then return end
  pcall(function()
    local cur = nil
    if type(creature.getText) == 'function' then cur = creature:getText() end
    if cur ~= text then creature:setText(text) end
  end)
end

-- Generic safe setter for UI labels/widgets
local function setWidgetTextSafe(widget, text)
  if not widget or not text then return end
  pcall(function()
    local cur = nil
    if type(widget.getText) == 'function' then cur = widget:getText() end
    if cur ~= text then widget:setText(text) end
  end)
end

-- Event-driven hooks: mark cache dirty and optionally schedule a quick recalc
-- Default no-op in case EventBus or debounce util isn't available (prevents nil calls)
local debouncedInvalidateAndRecalc = function() end
if EventBus then
  -- Safe debounce factory (works even if nExBot.EventUtil isn't initialized yet)
  local function makeDebounce(ms, fn)
    if nExBot and nExBot.EventUtil and nExBot.EventUtil.debounce then
      return nExBot.EventUtil.debounce(ms, fn)
    end
    local scheduled = false
    return function(...)
      if scheduled then return end
      scheduled = true
      local args = {...}
      schedule(ms, function()
        scheduled = false
        pcall(fn, _unpack(args))
      end)
    end
  end

  -- Debounced invalidation + optional immediate lightweight recalc for responsiveness
  -- Assign to outer variable (do NOT use local here) so external callers use the debounce
  -- IMPROVED: Faster debounce (50ms) for quicker monster detection
  debouncedInvalidateAndRecalc = makeDebounce(50, function()
    invalidateCache()
    -- Also refresh live count for accuracy
    if EventTargeting and EventTargeting.refreshLiveCount then
      EventTargeting.refreshLiveCount()
    end
    -- Schedule a lightweight recalc to update cache quickly (non-blocking)
    schedule(20, function()
      pcall(function()
        if recalculateBestTarget then
          recalculateBestTarget()
        end
      end)
    end)
  end)

  EventBus.on("monster:appear", function(creature)
    if creature then debouncedInvalidateAndRecalc() end
  end, 20)

  EventBus.on("monster:disappear", function(creature)
    debouncedInvalidateAndRecalc()
  end, 20)

  EventBus.on("creature:move", function(creature, oldPos)
    -- Safe check for monster
    local okMonster, isMonster = pcall(function() return creature and creature:isMonster() end)
    if okMonster and isMonster then
      debouncedInvalidateAndRecalc()
    end
  end, 20)

  EventBus.on("monster:health", function(creature, percent)
    debouncedInvalidateAndRecalc()
  end, 20)

  EventBus.on("player:move", function(newPos, oldPos)
    -- Player movement changes proximity; trigger recalculation
    debouncedInvalidateAndRecalc()
  end, 10)

  EventBus.on("combat:target", function(creature, oldCreature)
    debouncedInvalidateAndRecalc()
  end, 20)

  -- MonsterAI: React to imminent attacks and threat notifications
  EventBus.on("monsterai/imminent_attack", function(creature, data)
    -- data: { confidence = 0..1, timeToAttack = ms, reason = "wave"|"melee", ... }
    if not MONSTERAI_INTEGRATION then return end
    if not creature or not data then return end
    local conf = data.confidence or 0
    if conf < MONSTERAI_MIN_CONF then return end

    -- Compute simple escape tile away from monster
    local okP, ppos = pcall(function() return player and player:getPosition() end)
    local okC, cpos = pcall(function() return creature and creature:getPosition() end)
    if not okP or not okC or not ppos or not cpos then return end

    local dx = (ppos.x - cpos.x)
    local dy = (ppos.y - cpos.y)
    local moveX = (dx ~= 0) and (dx > 0 and 1 or -1) or 0
    local moveY = (dy ~= 0) and (dy > 0 and 1 or -1) or 0
    local escapePos = { x = ppos.x + moveX, y = ppos.y + moveY, z = ppos.z }

    local action = MONSTERAI_IMMINENT_ACTION
    if action == "avoid" then
      if MovementCoordinator and MovementCoordinator.Intent and MovementCoordinator.CONSTANTS then
        MovementCoordinator.Intent.register(
          MovementCoordinator.CONSTANTS.INTENT.EMERGENCY_ESCAPE,
          escapePos,
          math.min(0.95, conf),
          "monsterai_imminent",
          { src = creature, tta = data.timeToAttack }
        )
      end
      -- Pause attacking briefly to let movement coordinator act
      monsterAIWaitUntil = now + math.max(900, data.timeToAttack or 900)
    elseif action == "wait" then
      -- Pause attacking but don't register a move intent
      monsterAIWaitUntil = now + math.max(800, data.timeToAttack or 800)
    end

    -- Force cache/invalidation so we re-evaluate target priorities asap
    invalidateCache()
  end, 50)

  EventBus.on("monsterai/threat_detected", function(creature, data)
    if not MONSTERAI_INTEGRATION then return end
    -- Record AI threat and force a recalc so priorities react quickly
    if creature then
      local okId, id = pcall(function() return creature and creature:getId() end)
      if okId and id and CreatureCache.monsters[id] then
        -- store last known threat for display or debug
        CreatureCache.monsters[id].lastAIThreat = data
      end
    end
    invalidateCache()
  end, 40)

  --------------------------------------------------------------------------------
  -- FOLLOW PLAYER INTEGRATION (Party Hunt Support)
  -- When Force Follow mode is active, TargetBot should reduce aggression
  -- to allow the follower to catch up with the party leader
  --------------------------------------------------------------------------------
  local followPlayerForceMode = false
  local followPlayerForceExpiry = 0
  local FORCE_FOLLOW_COMBAT_WINDOW_MS = 2500  -- How long to allow combat before forcing follow
  
  -- Listen for force follow mode activation from tools.lua
  EventBus.on("followplayer/force_follow", function(leaderPos, distance)
    pcall(function()
      followPlayerForceMode = true
      followPlayerForceExpiry = now + FORCE_FOLLOW_COMBAT_WINDOW_MS
      -- When force follow triggers, allow CaveBot/walking immediately
      -- This ensures the follower can catch up to the leader
      cavebotAllowance = now + 100
    end)
  end, 100)  -- High priority to ensure timely response
  
  -- Listen for follow player being enabled/disabled
  EventBus.on("followplayer/enabled", function(playerName)
    pcall(function()
      -- Reset force mode when following starts
      followPlayerForceMode = false
      followPlayerForceExpiry = 0
    end)
  end, 80)
  
  EventBus.on("followplayer/disabled", function()
    pcall(function()
      -- Clear force mode when following stops
      followPlayerForceMode = false
      followPlayerForceExpiry = 0
    end)
  end, 80)
  
  -- Export force follow check for use in main targeting loop
  TargetBot.isForceFollowActive = function()
    if not followPlayerForceMode then return false end
    if now > followPlayerForceExpiry then
      followPlayerForceMode = false
      return false
    end
    return true
  end
  
  -- Allow external access to reset force follow (e.g., when monsters are all dead)
  TargetBot.clearForceFollow = function()
    followPlayerForceMode = false
    followPlayerForceExpiry = 0
  end
end

-- Fallback: If EventBus isn't available (older clients or different environments), hook into global creature events
if not EventBus then
  if onCreatureAppear then
    onCreatureAppear(function(creature)
      if creature then
        invalidateCache()
        -- Debounced recalc to reduce CPU churn on rapid events
        if debouncedInvalidateAndRecalc then debouncedInvalidateAndRecalc() end
      end
    end)
  end
  if onCreatureDisappear then
    onCreatureDisappear(function(creature)
      invalidateCache()
      if debouncedInvalidateAndRecalc then debouncedInvalidateAndRecalc() end
    end)
  end
  if onCreatureMove then
    onCreatureMove(function(creature, oldPos)
      -- Safe check for monster
      local okMonster, isMonster = pcall(function() return creature and creature:isMonster() end)
      if okMonster and isMonster then
        invalidateCache()
        if debouncedInvalidateAndRecalc then debouncedInvalidateAndRecalc() end
      end
    end)
  end
end

-- Reset attack watchdog on relogin (player health re-appears)
if onPlayerHealthChange then
  onPlayerHealthChange(function(healthPercent)
    if healthPercent and healthPercent > 0 then
      attackWatchdog.attempts = 0
      attackWatchdog.lastForce = 0
      -- Start an aggressive relogin recovery window if TargetBot was enabled before or is currently on
      if TargetBot and TargetBot.isOn and (TargetBot.isOn() or storage.targetbotEnabled == true) then
        reloginRecovery.active = true
        reloginRecovery.endTime = now + reloginRecovery.duration
        reloginRecovery.lastAttempt = 0

        -- Force immediate cache refresh and attempt recovery hits
        -- Update local player reference (in case object changed on relogin)
        player = g_game and g_game.getLocalPlayer() or player
        debouncedInvalidateAndRecalc()

        -- If TargetBot was previously enabled via storage, ensure it's on now to allow recovery
        if storage.targetbotEnabled == true and not TargetBot.isOn() then
          pcall(function() TargetBot.setOn() end)
        end

        -- Update UI status so user sees recovery in progress
        if ui and ui.status and ui.status.right then setStatusRight("Recovering...") end

        -- Schedule repeated attempts (aggressive recovery window)
        if targetbotMacro then
          local function attemptRecovery()
            -- Only attempt recovery runs if targetbot should be enabled
            if storage.targetbotEnabled == true or TargetBot.isOn() then
              pcall(targetbotMacro)
              -- After macro run, try recalc and a direct attack as a backup
              local ok2, best2 = pcall(function() return recalculateBestTarget() end)
              if ok2 then
                local count = CreatureCache.monsterCount or 0
                if ui and ui.status and ui.status.right then
                  if best2 and best2.creature then
                    setStatusRight("Recovering ("..tostring(count)..") best: "..best2.creature:getName())
                  else
                    setStatusRight("Recovering ("..tostring(count)..")")
                  end
                end
                if best2 and best2.creature then pcall(function() g_game.attack(best2.creature) end) end
              end
            end
          end
          schedule(200, attemptRecovery)
          schedule(600, attemptRecovery)
          schedule(1200, attemptRecovery)
          schedule(2500, attemptRecovery)
          schedule(5000, attemptRecovery)
          schedule(8000, attemptRecovery)
          schedule(12000, attemptRecovery)
        end

        -- Mark recovery window active (already set) and let watchdog handle disabling later
      end
    end
  end)
end

-- LRU eviction helper: move ID to end of access order
local function touchCreature(id)
  local order = CreatureCache.accessOrder
  -- Remove existing position
  for i = #order, 1, -1 do
    if order[i] == id then
      table.remove(order, i)
      break
    end
  end
  -- Add to end (most recently used)
  order[#order + 1] = id
end

-- LRU eviction: remove oldest entries when over capacity
local function evictOldestCreatures()
  local order = CreatureCache.accessOrder
  while #order > CreatureCache.maxSize do
    local oldestId = table.remove(order, 1)
    if CreatureCache.monsters[oldestId] then
      CreatureCache.monsters[oldestId] = nil
      CreatureCache.monsterCount = CreatureCache.monsterCount - 1
    end
  end
end

-- Clean up stale cache entries (improved with LRU)
local function cleanupCache()
  if now - CreatureCache.lastCleanup < CreatureCache.CLEANUP_INTERVAL then
    return
  end
  
  local cutoff = now - 3000  -- Reduced from 5s to 3s for faster cleanup
  local newMonsters = {}
  local newOrder = {}
  local count = 0
  
  -- Keep only recent entries in access order
  for i = 1, #CreatureCache.accessOrder do
    local id = CreatureCache.accessOrder[i]
    local data = CreatureCache.monsters[id]
    if data and data.lastUpdate > cutoff and data.creature and not data.creature:isDead() then
      newMonsters[id] = data
      newOrder[#newOrder + 1] = id
      count = count + 1
    end
  end
  
  CreatureCache.monsters = newMonsters
  CreatureCache.accessOrder = newOrder
  CreatureCache.monsterCount = count
  CreatureCache.lastCleanup = now
  invalidateCache()
end

-- Update a single creature in cache (called on events)
-- Improved with LRU tracking, distance-based filtering, and safe API calls
local function updateCreatureInCache(creature)
  -- Safe check for dead creature
  local okDead, isDead = pcall(function() return creature and creature:isDead() end)
  if not creature or (okDead and isDead) then
    local okId, id = pcall(function() return creature and creature:getId() end)
    if okId and id and CreatureCache.monsters[id] then
      CreatureCache.monsters[id] = nil
      CreatureCache.monsterCount = CreatureCache.monsterCount - 1
      -- Remove from access order
      for i = #CreatureCache.accessOrder, 1, -1 do
        if CreatureCache.accessOrder[i] == id then
          table.remove(CreatureCache.accessOrder, i)
          break
        end
      end
    end
    invalidateCache()
    return
  end
  
  -- Safe check for monster
  local okMonster, isMonster = pcall(function() return creature:isMonster() end)
  if not okMonster or not isMonster then return end
  
  -- Safe get ID and positions
  local okId, id = pcall(function() return creature:getId() end)
  if not okId or not id then return end
  
  local okPos, pos = pcall(function() return player:getPosition() end)
  local okCpos, cpos = pcall(function() return creature:getPosition() end)
  if not okPos or not pos or not okCpos or not cpos then return end
  
  -- Use TargetBotCore distance if available, otherwise calculate
  local dist
  if Core.Geometry and Core.Geometry.chebyshevDistance then
    dist = Core.Geometry.chebyshevDistance(pos, cpos)
  else
    dist = math.max(math.abs(pos.x - cpos.x), math.abs(pos.y - cpos.y))
  end
  
  -- Skip if too far (reduced from 10 to 8 for better performance)
  if dist > 8 then
    if CreatureCache.monsters[id] then
      CreatureCache.monsters[id] = nil
      CreatureCache.monsterCount = CreatureCache.monsterCount - 1
      for i = #CreatureCache.accessOrder, 1, -1 do
        if CreatureCache.accessOrder[i] == id then
          table.remove(CreatureCache.accessOrder, i)
          break
        end
      end
    end
    return
  end
  
  local entry = CreatureCache.monsters[id]
  if not entry then
    entry = { 
      creature = creature, 
      lastUpdate = now,
      distance = dist
    }
    CreatureCache.monsters[id] = entry
    CreatureCache.monsterCount = CreatureCache.monsterCount + 1
    touchCreature(id)
    -- Check if we need to evict
    evictOldestCreatures()
  else
    entry.creature = creature
    entry.lastUpdate = now
    entry.distance = dist
    touchCreature(id)
  end
  
  -- Recalculate path if needed
  if not entry.path or now - (entry.pathTime or 0) > CreatureCache.PATH_TTL then
    entry.path = findPath(pos, cpos, 10, PATH_PARAMS)
    entry.pathTime = now
  end
  
  invalidateCache()
end

-- Remove creature from cache (with LRU cleanup)
local function removeCreatureFromCache(creature)
  if not creature then return end
  local id = creature:getId()
  if CreatureCache.monsters[id] then
    CreatureCache.monsters[id] = nil
    CreatureCache.monsterCount = CreatureCache.monsterCount - 1
    -- Remove from LRU order
    for i = #CreatureCache.accessOrder, 1, -1 do
      if CreatureCache.accessOrder[i] == id then
        table.remove(CreatureCache.accessOrder, i)
        break
      end
    end
    invalidateCache()
  end
end

--------------------------------------------------------------------------------
-- EventBus Integration for Event-Driven Targeting
--------------------------------------------------------------------------------
if EventBus then
  -- Monster appears - add to cache
  EventBus.on("monster:appear", function(creature)
    updateCreatureInCache(creature)
  end, 50)
  
  -- Monster disappears - remove from cache
  EventBus.on("monster:disappear", function(creature)
    removeCreatureFromCache(creature)
  end, 50)
  
  -- Monster health changes - update priority (high priority for targeting decisions)
  EventBus.on("monster:health", function(creature, percent)
    if percent <= 0 then
      removeCreatureFromCache(creature)
    else
      -- Invalidate to recalculate priority for wounded monsters
      invalidateCache()
    end
  end, 80)
  
  -- Player moves - need to recalculate paths
  EventBus.on("player:move", function(newPos, oldPos)
    -- Invalidate all paths on player movement
    for id, data in pairs(CreatureCache.monsters) do
      data.path = nil
      data.pathTime = nil
    end
    invalidateCache()
  end, 60)
  
  -- Target changes
  local lastCombatTargetId = nil
  EventBus.on("combat:target", function(creature, oldCreature)
    invalidateCache()

    local newId = creature and creature:getId() or nil
    if newId ~= lastCombatTargetId then
      if creature then
        -- Combat started
        storage.targetbotCombatActive = true
        pcall(function()
          EventBus.emit("targetbot/combat_start", creature, { id = newId, pos = creature:getPosition() })
        end)
      else
        -- Combat ended
        storage.targetbotCombatActive = false
        pcall(function() EventBus.emit("targetbot/combat_end") end)
      end
      lastCombatTargetId = newId
    end
  end, 70)

  -- Monitor player health to emit emergency events
  EventBus.on("player:health", function(health, maxHealth, oldHealth, oldMax)
    local cfg = ProfileStorage and ProfileStorage.get and ProfileStorage.get('targetPriority') or {}
    local threshold = cfg and cfg.emergencyHP or 25
    local percent = 100
    if maxHealth and maxHealth > 0 then percent = math.floor(health / maxHealth * 100) end
    if percent <= threshold and not storage.targetbotEmergency then
      storage.targetbotEmergency = true
      pcall(function() EventBus.emit("targetbot/emergency", percent) end)
    elseif percent > threshold and storage.targetbotEmergency then
      storage.targetbotEmergency = false
      pcall(function() EventBus.emit("targetbot/emergency_cleared", percent) end)
    end
  end, 90)
  
  -- ============================================================================
  -- EVENT-DRIVEN MOVEMENT INTENTS (Chase, KeepDistance, FinishKill)
  -- React instantly to creature movements instead of polling
  -- ============================================================================
  
  -- Track active movement config (set by creature_attack when processing targets)
  TargetBot.ActiveMovementConfig = TargetBot.ActiveMovementConfig or {
    chase = false,
    keepDistance = false,
    keepDistanceRange = 4,
    finishKillThreshold = 30,
    anchor = nil,
    anchorRange = 5
  }
  
  -- Event-driven keepDistance: when target moves, adjust position
  EventBus.on("creature:move", function(creature, oldPos)
    -- Safe check for monster
    local okMonster, isMonster = pcall(function() return creature and creature:isMonster() end)
    if not okMonster or not isMonster then return end
    
    -- Check if this is our current target
    local target = g_game and g_game.getAttackingCreature and g_game.getAttackingCreature()
    if not target then return end
    
    -- Safe ID comparison
    local okCid, cid = pcall(function() return creature:getId() end)
    local okTid, tid = pcall(function() return target:getId() end)
    if not okCid or not okTid or cid ~= tid then return end
    
    local config = TargetBot.ActiveMovementConfig
    if not config then return end
    
    -- Safe position access
    local okPpos, playerPos = pcall(function() return player and player:getPosition() end)
    local okCpos, creaturePos = pcall(function() return creature:getPosition() end)
    if not okPpos or not playerPos or not okCpos or not creaturePos then return end
    
    local dist = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
    
    -- KeepDistance: target moved, check if we need to reposition
    if config.keepDistance then
      local keepRange = config.keepDistanceRange or 4
      
      -- Only react if distance changed significantly
      if dist < keepRange - 1 or dist > keepRange + 2 then
        -- Calculate ideal position
        local dx = creaturePos.x - playerPos.x
        local dy = creaturePos.y - playerPos.y
        local currentDist = math.sqrt(dx * dx + dy * dy)
        
        if currentDist > 0 then
          local ratio = keepRange / currentDist
          local keepPos = {
            x = math.floor(creaturePos.x - dx * ratio + 0.5),
            y = math.floor(creaturePos.y - dy * ratio + 0.5),
            z = playerPos.z
          }
          
          -- Check anchor constraint
          local anchorValid = true
          if config.anchor then
            local anchorDist = math.max(
              math.abs(keepPos.x - config.anchor.x),
              math.abs(keepPos.y - config.anchor.y)
            )
            anchorValid = anchorDist <= (config.anchorRange or 5)
          end
          
          if anchorValid and MovementCoordinator and MovementCoordinator.Intent then
            local confidence = 0.55
            if dist < keepRange - 1 then
              confidence = 0.70  -- Too close - higher urgency
            end
            
            MovementCoordinator.Intent.register(
              MovementCoordinator.CONSTANTS.INTENT.KEEP_DISTANCE,
              keepPos,
              confidence,
              "keepdist_event",
              {triggered = "target_move", currentDist = dist, targetDist = keepRange}
            )
          end
        end
      end
    end
    
    -- Chase: target moved away, register chase intent
    if config.chase and not config.keepDistance and dist > 1 then
      -- Confidence values adjusted to pass CHASE threshold (0.60)
      local confidence = 0.62  -- Base now passes threshold
      if dist <= 3 then confidence = 0.68 end
      if dist >= 5 then confidence = 0.75 end
      
      -- Check anchor constraint
      local anchorValid = true
      if config.anchor then
        local anchorDist = math.max(
          math.abs(creaturePos.x - config.anchor.x),
          math.abs(creaturePos.y - config.anchor.y)
        )
        anchorValid = anchorDist <= (config.anchorRange or 5)
      end
      
      if anchorValid and MovementCoordinator and MovementCoordinator.Intent then
        MovementCoordinator.Intent.register(
          MovementCoordinator.CONSTANTS.INTENT.CHASE,
          creaturePos,
          confidence,
          "chase_target_move",
          {triggered = "target_move", dist = dist}
        )
      end
    end
  end, 15)  -- Medium-high priority
  
  -- Event-driven finish kill: when low-HP target moves
  EventBus.on("monster:health", function(creature, percent)
    if not creature then return end
    
    -- Check if this is our target (safe)
    local target = g_game and g_game.getAttackingCreature and g_game.getAttackingCreature()
    if not target then return end
    
    -- Safe ID comparison
    local okCid, cid = pcall(function() return creature:getId() end)
    local okTid, tid = pcall(function() return target:getId() end)
    if not okCid or not okTid or cid ~= tid then return end
    
    local config = TargetBot.ActiveMovementConfig
    local threshold = config and config.finishKillThreshold or 30
    
    if percent and percent < threshold and percent > 0 then
      -- Safe position access
      local okPpos, playerPos = pcall(function() return player and player:getPosition() end)
      local okCpos, creaturePos = pcall(function() return creature:getPosition() end)
      if not okPpos or not playerPos or not okCpos or not creaturePos then return end
      
      local dist = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
      
      if dist > 1 and MovementCoordinator and MovementCoordinator.Intent then
        local confidence = 0.65
        if percent < 15 then confidence = 0.80 end
        if percent < 10 then confidence = 0.90 end
        
        MovementCoordinator.Intent.register(
          MovementCoordinator.CONSTANTS.INTENT.FINISH_KILL,
          creaturePos,
          confidence,
          "finish_kill_hp",
          {triggered = "health_change", hp = percent, dist = dist}
        )
      end
    end
  end, 25)
  
  -- Emit event when target is acquired for other modules
  EventBus.on("combat:target", function(creature, oldCreature)
    if creature and MovementCoordinator then
      -- Notify MovementCoordinator of new target for chase tracking (safe)
      pcall(function()
        local okPos, pos = pcall(function() return creature:getPosition() end)
        EventBus.emit("targetbot/target_acquired", creature, okPos and pos or nil)
      end)
    end
  end, 65)
end

--------------------------------------------------------------------------------
-- NATIVE CHASE MODE ENFORCEMENT (EventBus-Driven)
-- 
-- When TargetBot has "Chase" enabled for the current target config, force the
-- client's native chase mode to stay active. This uses the OTClient API:
--   g_game.setChaseMode(0) = DontChase (Stand)
--   g_game.setChaseMode(1) = ChaseOpponent (Chase)
-- 
-- The client emits "onChaseModeChange" when the UI or other modules change it.
-- We listen for this and re-enforce chase mode if TargetBot requires it.
--------------------------------------------------------------------------------

-- Chase mode enforcement state
local ChaseModeEnforcer = {
  enabled = false,               -- Whether enforcement is active
  lastEnforcedMode = nil,        -- Last mode we enforced
  lastEnforceTime = 0,           -- Timestamp of last enforcement
  enforceCooldown = 100,         -- Minimum ms between enforcements to avoid spam
  shouldChase = false,           -- Current desired chase state from config
  keepDistance = false           -- Keep distance mode (overrides chase)
}

-- Update chase mode based on current config
local function updateChaseModeFromConfig()
  local config = TargetBot.ActiveMovementConfig
  if not config then return end
  
  ChaseModeEnforcer.shouldChase = config.chase == true
  ChaseModeEnforcer.keepDistance = config.keepDistance == true
end

-- Enforce the chase mode based on TargetBot config
local function enforceChaseModeNow()
  if not TargetBot.isOn or not TargetBot.isOn() then
    ChaseModeEnforcer.enabled = false
    return
  end
  
  -- Rate limiting
  local currentTime = now or (os.time() * 1000)
  if (currentTime - ChaseModeEnforcer.lastEnforceTime) < ChaseModeEnforcer.enforceCooldown then
    return
  end
  
  updateChaseModeFromConfig()
  
  -- Determine desired mode: chase=1, keepDistance or no chase=0
  local desiredMode = 0  -- Default: Stand
  if ChaseModeEnforcer.shouldChase and not ChaseModeEnforcer.keepDistance then
    desiredMode = 1  -- ChaseOpponent
  end
  
  -- Only enforce if we're actively attacking
  local isAttacking = g_game.isAttacking and g_game.isAttacking()
  if not isAttacking then
    ChaseModeEnforcer.enabled = false
    return
  end
  
  ChaseModeEnforcer.enabled = true
  
  -- Check current mode and enforce if different
  local currentMode = g_game.getChaseMode and g_game.getChaseMode() or 0
  if currentMode ~= desiredMode then
    if g_game.setChaseMode then
      g_game.setChaseMode(desiredMode)
      ChaseModeEnforcer.lastEnforcedMode = desiredMode
      ChaseModeEnforcer.lastEnforceTime = currentTime
      
      -- Emit event for other modules
      if EventBus then
        pcall(function()
          EventBus.emit("targetbot/chase_mode_enforced", desiredMode, desiredMode == 1 and "chase" or "stand")
        end)
      end
    end
  end
end

-- EventBus integration for chase mode enforcement
if EventBus then
  -- When target is acquired, enforce chase mode
  EventBus.on("targetbot/target_acquired", function(creature, creaturePos)
    pcall(function()
      enforceChaseModeNow()
    end)
  end, 60)
  
  -- When combat starts, enforce chase mode
  EventBus.on("targetbot/combat_start", function(creature, data)
    pcall(function()
      enforceChaseModeNow()
    end)
  end, 60)
  
  -- When combat ends, reset enforcement
  EventBus.on("targetbot/combat_end", function()
    pcall(function()
      ChaseModeEnforcer.enabled = false
    end)
  end, 60)
  
  -- Listen for player movement - re-check chase mode
  EventBus.on("player:move", function(newPos, oldPos)
    if ChaseModeEnforcer.enabled then
      pcall(function()
        enforceChaseModeNow()
      end)
    end
  end, 5)  -- Low priority, after other handlers
  
  -- Listen for target movement - re-check chase mode
  EventBus.on("creature:move", function(creature, oldPos)
    if not ChaseModeEnforcer.enabled then return end
    
    -- Safe check if this is our target
    local target = g_game.getAttackingCreature and g_game.getAttackingCreature()
    if not target then return end
    
    local okCid, cid = pcall(function() return creature:getId() end)
    local okTid, tid = pcall(function() return target:getId() end)
    if okCid and okTid and cid == tid then
      pcall(function()
        enforceChaseModeNow()
      end)
    end
  end, 5)
end

-- Hook into OTClient's native chase mode change callback
-- This fires when the UI or other modules change chase mode
if g_game and type(g_game) == "table" then
  -- Use connect to listen for onChaseModeChange if available
  local function onNativeChaseModeChange(newMode)
    if not ChaseModeEnforcer.enabled then return end
    if not TargetBot.isOn or not TargetBot.isOn() then return end
    
    updateChaseModeFromConfig()
    
    local desiredMode = 0
    if ChaseModeEnforcer.shouldChase and not ChaseModeEnforcer.keepDistance then
      desiredMode = 1
    end
    
    -- If someone changed it to something we don't want, re-enforce after a short delay
    if newMode ~= desiredMode then
      schedule(50, function()
        if ChaseModeEnforcer.enabled and TargetBot.isOn and TargetBot.isOn() then
          enforceChaseModeNow()
        end
      end)
    end
  end
  
  -- Try to connect to the native callback
  pcall(function()
    connect(g_game, { onChaseModeChange = onNativeChaseModeChange })
  end)
end

-- Public API for other modules
TargetBot.ChaseModeEnforcer = ChaseModeEnforcer
TargetBot.enforceChaseModeNow = enforceChaseModeNow

-- PERFORMANCE: Path cache for backward compatibility (optimized)
local PathCache = {
  paths = {},
  TTL = 500,
  lastCleanup = 0,
  cleanupInterval = 2000,
  size = 0,
  maxSize = 30
}

-- Pre-allocated cache entry to reduce GC
local cacheEntryPool = {}

local function acquireCacheEntry()
  local entry = table.remove(cacheEntryPool)
  return entry or { path = nil, timestamp = 0 }
end

local function releaseCacheEntry(entry)
  if #cacheEntryPool < 20 then
    entry.path = nil
    entry.timestamp = 0
    cacheEntryPool[#cacheEntryPool + 1] = entry
  end
end

local function cleanupPathCache()
  if now - PathCache.lastCleanup < PathCache.cleanupInterval then
    return
  end
  
  local cutoff = now - PathCache.TTL
  for id, data in pairs(PathCache.paths) do
    if data.timestamp < cutoff then
      releaseCacheEntry(data)
      PathCache.paths[id] = nil
      PathCache.size = PathCache.size - 1
    end
  end
  PathCache.lastCleanup = now
end

-- ui
local configWidget = UI.Config()
local ui = UI.createWidget("TargetBotPanel")

ui.list = ui.listPanel.list -- shortcut
TargetBot.targetList = ui.list
TargetBot.Looting.setup()

-- Setup eat food feature if available
if TargetBot.EatFood and TargetBot.EatFood.setup then
  TargetBot.EatFood.setup()
end

ui.status.left:setText("Status:")
setStatusRight("Off")
ui.target.left:setText("Target:")
setWidgetTextSafe(ui.target.right, "-")
ui.config.left:setText("Config:")
setWidgetTextSafe(ui.config.right, "-")
ui.danger.left:setText("Danger:")
setWidgetTextSafe(ui.danger.right, "0")

if ui and ui.editor and ui.editor.debug then ui.editor.debug:destroy() end

local oldTibia = g_game.getClientVersion() < 960

-- config, its callback is called immediately, data can be nil
-- Config setup moved down to after macro (to ensure macro and recalc exist before callback runs)
-- See vBot for reference: https://github.com/Vithrax/vBot

-- Setup UI tooltips
ui.editor.buttons.add:setTooltip("Add a new creature targeting configuration.\nDefine which creatures to attack and how.")
ui.editor.buttons.edit:setTooltip("Edit the selected creature targeting configuration.\nModify priority, distance, and behavior settings.")
ui.editor.buttons.remove:setTooltip("Remove the selected creature targeting configuration.\nThis action cannot be undone.")

ui.configButton:setTooltip("Show/hide the target editor panel.\nUse to add, edit, or remove creature configurations.")

-- setup ui
ui.editor.buttons.add.onClick = function()
  TargetBot.Creature.edit(nil, function(newConfig)
    TargetBot.Creature.addConfig(newConfig, true)
    TargetBot.save()
  end)
end

ui.editor.buttons.edit.onClick = function()
  local entry = ui.list:getFocusedChild()
  if not entry then return end
  TargetBot.Creature.edit(entry.value, function(newConfig)
    entry:setText(newConfig.name)
    entry.value = newConfig
    TargetBot.Creature.resetConfigsCache()
    TargetBot.save()
  end)
end

ui.editor.buttons.remove.onClick = function()
  local entry = ui.list:getFocusedChild()
  if not entry then return end
  entry:destroy()
  TargetBot.Creature.resetConfigsCache()
  TargetBot.save()
end

-- public function, you can use them in your scripts
TargetBot.isActive = function() -- return true if attacking or looting takes place
  return lastAction + 300 > now
end

TargetBot.isCaveBotActionAllowed = function()
  return cavebotAllowance > now
end

TargetBot.setStatus = function(text)
  setStatusRight(text)
end

TargetBot.getStatus = function()
  local t = nil
  pcall(function() t = ui.status.right:getText() end)
  return t
end

TargetBot.isOn = function()
  if not config then return false end
  -- config.isOn may be a function or a boolean
  if type(config.isOn) == 'function' then
    local ok, res = pcall(config.isOn)
    return ok and not not res
  end
  if type(config.isOn) == 'boolean' then
    return config.isOn
  end
  return false
end

TargetBot.isOff = function()
  if not config or not config.isOff then return true end
  return config.isOff()
end

TargetBot.setOn = function(val)
  if val == false then  
    return TargetBot.setOff(true)
  end
  config.setOn()  -- This triggers callback which handles storage
end

TargetBot.setOff = function(val)
  if val == false then  
    return TargetBot.setOn(true)
  end
  config.setOff()  -- This triggers callback which handles storage
end

TargetBot.getCurrentProfile = function()
  return storage._configs.targetbot_configs.selected
end

-- Use shared BotConfigName from configs.lua (DRY)
local botConfigName = BotConfigName or modules.game_bot.contentsPanel.config:getCurrentOption().text
TargetBot.setCurrentProfile = function(name)
  if not g_resources.fileExists("/bot/"..botConfigName.."/targetbot_configs/"..name..".json") then
    return warn("there is no targetbot profile with that name!")
  end
  TargetBot.setOff()
  storage._configs.targetbot_configs.selected = name
  -- Save character's profile preference for multi-client support
  if setCharacterProfile then
    setCharacterProfile("targetbotProfile", name)
  end
  TargetBot.setOn()
end

TargetBot.delay = function(value)
  targetbotMacro.delay = now + value
end

TargetBot.save = function()
  local data = {targeting={}, looting={}}
  for _, entry in ipairs(ui.list:getChildren()) do
    table.insert(data.targeting, entry.value)
  end
  TargetBot.Looting.save(data.looting)
  config.save(data)
end

TargetBot.allowCaveBot = function(time)
  cavebotAllowance = now + time
end

TargetBot.disableLuring = function()
  lureEnabled = false
end

TargetBot.enableLuring = function()
  lureEnabled = true
end

-- Relogin recovery configuration and controls
TargetBot.setReloginRecoveryDuration = function(ms)
  if type(ms) == 'number' and ms >= 0 then
    reloginRecovery.duration = ms
  end
end

TargetBot.enableReloginRecovery = function(duration)
  if type(duration) == 'number' and duration >= 0 then
    reloginRecovery.duration = duration
  end
  reloginRecovery.active = true
  reloginRecovery.endTime = now + reloginRecovery.duration
  reloginRecovery.lastAttempt = 0
end

TargetBot.disableReloginRecovery = function()
  reloginRecovery.active = false
  reloginRecovery.endTime = 0
  reloginRecovery.lastAttempt = 0
end

TargetBot.Danger = function()
  return dangerValue
end

TargetBot.lootStatus = function()
  return looterStatus
end


-- attacks
local lastSpell = 0



local function doSay(text)
  if type(text) ~= 'string' or text:len() < 1 then return false end
  -- primary: global say
  if type(say) == 'function' then
    local ok, res = SafeCall.call(say, text)
    if ok then return true end
    warn("[TargetBot] doSay: say(...) failed")
    return false
  end
  -- fallback: g_game.say
  if g_game and type(g_game.say) == 'function' then
    local ok, res = SafeCall.call(g_game.say, text)
    if ok then return true end
    warn("[TargetBot] doSay: g_game.say(...) failed")
    return false
  end
  -- fallback: g_game.talk or g_game.talkLocal
  if g_game and type(g_game.talk) == 'function' then
    local ok, res = SafeCall.call(g_game.talk, text)
    if ok then return true end
    warn("[TargetBot] doSay: g_game.talk(...) failed")
    return false
  end
  if g_game and type(g_game.talkLocal) == 'function' then
    local ok, res = SafeCall.call(g_game.talkLocal, text)
    if ok then return true end
    warn("[TargetBot] doSay: g_game.talkLocal(...) failed")
    return false
  end
  return false
end

TargetBot.saySpell = function(text, delay)
  if type(text) ~= 'string' or text:len() < 1 then return false end
  if not delay then delay = 500 end
  if lastSpell + delay < now then
    if not doSay(text) then
      warn("[TargetBot] no suitable say/talk method; cannot cast: " .. tostring(text))
      return false
    end
    lastSpell = now
    return true
  end
  return false
end

TargetBot.sayAttackSpell = function(text, delay)
  if type(text) ~= 'string' or text:len() < 1 then return end
  if not delay then delay = 2000 end
  
  -- Use new AttackSystem if available (EventBus integration, better cooldown tracking)
  if BotCore and BotCore.AttackSystem and BotCore.AttackSystem.isEnabled and BotCore.AttackSystem.isEnabled() then
    return BotCore.AttackSystem.executeSingleSpell(text, delay)
  end
  
  if lastAttackSpell + delay < now then
    say(text)
    lastAttackSpell = now
    -- Track attack spell for Hunt Analyzer
    if HuntAnalytics and HuntAnalytics.trackAttackSpell then
      HuntAnalytics.trackAttackSpell(text, 0)  -- Mana cost unknown from here
    end
    return true
  end
  return false
end

local lastItemUse = 0
local lastRuneAttack = 0

TargetBot.useItem = function(item, subType, target, delay)
  -- Prefer AttackBot implementation if available
  if AttackBot and type(AttackBot.useItem) == 'function' then
    return AttackBot.useItem(item, subType, target, delay)
  end
  if not delay then delay = 200 end
  if lastItemUse + delay < now then
    warn("[TargetBot] useItem called but AttackBot.useItem not available; item=" .. tostring(item))
    lastItemUse = now
  end
  return false
end

TargetBot.useAttackItem = function(item, subType, target, delay)
  -- Prefer AttackBot implementation if available
  if AttackBot and type(AttackBot.useAttackItem) == 'function' then
    return AttackBot.useAttackItem(item, subType, target, delay)
  end
  if not delay then delay = 2000 end
  
  -- Use new AttackSystem if available (EventBus integration, better cooldown tracking)
  if BotCore and BotCore.AttackSystem and BotCore.AttackSystem.isEnabled and BotCore.AttackSystem.isEnabled() then
    return BotCore.AttackSystem.executeSingleRune(item, target, delay)
  end
  
  if lastRuneAttack + delay < now then
    warn("[TargetBot] useAttackItem called but AttackBot.useAttackItem not available; item=" .. tostring(item))
    lastRuneAttack = now
  else
    warn("[TargetBot] Rune on cooldown: last=" .. tostring(lastRuneAttack) .. ", now=" .. tostring(now) .. ", delay=" .. tostring(delay))
  end
  return false
end

TargetBot.canLure = function()
  return lureEnabled
end

-- Kill Before Walk: Always enabled - wait for monsters to be killed before walking
-- This is the default behavior. DynamicLure and SmartPull can bypass when needed.
TargetBot.isKillBeforeWalkEnabled = function()
  return true  -- Always ON
end

-- Check if there are any targetable monsters on screen
-- IMPROVED: Uses EventTargeting live count for accuracy, falls back to cache
TargetBot.hasTargetableMonsters = function()
  -- PRIORITY 1: Use EventTargeting live count (most accurate)
  if EventTargeting and EventTargeting.getLiveMonsterCount then
    local liveCount = EventTargeting.getLiveMonsterCount()
    if liveCount > 0 then
      return true
    end
  end
  -- PRIORITY 2: Fall back to cache
  return CreatureCache.monsterCount > 0
end

-- Get count of targetable monsters on screen
-- IMPROVED: Uses EventTargeting live count for accuracy
TargetBot.getTargetableMonsterCount = function()
  -- PRIORITY 1: Use EventTargeting live count (most accurate)
  if EventTargeting and EventTargeting.getLiveMonsterCount then
    local liveCount = EventTargeting.getLiveMonsterCount()
    if liveCount > 0 then
      return liveCount
    end
  end
  -- PRIORITY 2: Fall back to cache
  return CreatureCache.monsterCount or 0
end

-- Helper function to check if creature is targetable
local function isTargetableCreature(creature)
  if not creature then return false end
  
  -- Safe check for isDead
  local okDead, isDead = pcall(function() return creature:isDead() end)
  if okDead and isDead then return false end
  
  -- Safe check for isMonster
  local okMonster, isMonster = pcall(function() return creature:isMonster() end)
  if not okMonster or not isMonster then return false end
  
  -- Health check - skip monsters with 0 HP
  local okHp, hp = pcall(function() return creature:getHealthPercent() end)
  if okHp and hp and hp <= 0 then return false end
  
  -- Old Tibia clients don't have creature types
  if oldTibia then
    return true
  end
  
  -- For new Tibia, check creature type to exclude other player's summons
  local okType, creatureType = pcall(function() return creature:getType() end)
  if okType and creatureType then
    return creatureType < 3
  end
  
  return true  -- Default to true if we can't determine type
end

--------------------------------------------------------------------------------
-- Optimized Main TargetBot Loop
-- Uses EventBus-driven cache for reduced CPU usage and better accuracy
-- Only recalculates when cache is dirty (events occurred)
--------------------------------------------------------------------------------

-- Helper: process a creature into target params (returns params, path) - pure helper to reduce duplication
-- IMPROVED: Enhanced path validation to reject blocked/unreachable creatures
local function processCandidate(creature, pos)
  if not creature or creature:isDead() or not isTargetableCreature(creature) then return nil, nil end
  local cpos = creature:getPosition()
  if not cpos then return nil, nil end
  
  -- CRITICAL: Verify path exists and is reachable
  local path = findPath(pos, cpos, 10, PATH_PARAMS)
  if not path or #path == 0 then 
    -- No path found - creature is unreachable
    return nil, nil 
  end
  
  -- ADDITIONAL CHECK: Verify path doesn't cross blocked tiles
  -- This catches cases where findPath returns a path but it's actually blocked
  local pathLength = #path
  if pathLength > 15 then
    -- For long paths, do a quick walkability check on first few tiles
    local probe = {x = pos.x, y = pos.y, z = pos.z}
    for i = 1, math.min(5, pathLength) do
      local dir = path[i]
      local offset = nil
      -- Get offset for direction
      if dir == North or dir == 0 then offset = {x = 0, y = -1}
      elseif dir == East or dir == 1 then offset = {x = 1, y = 0}
      elseif dir == South or dir == 2 then offset = {x = 0, y = 1}
      elseif dir == West or dir == 3 then offset = {x = -1, y = 0}
      elseif dir == NorthEast or dir == 4 then offset = {x = 1, y = -1}
      elseif dir == SouthEast or dir == 5 then offset = {x = 1, y = 1}
      elseif dir == SouthWest or dir == 6 then offset = {x = -1, y = 1}
      elseif dir == NorthWest or dir == 7 then offset = {x = -1, y = -1}
      end
      
      if offset then
        probe = {x = probe.x + offset.x, y = probe.y + offset.y, z = probe.z}
        local tile = g_map.getTile(probe)
        if tile and not tile:isWalkable() then
          -- Path crosses a blocked tile - creature is unreachable
          return nil, nil
        end
      end
    end
  end
  
  local params = TargetBot.Creature.calculateParams(creature, path)
  
  -- ADDITIONAL CHECK: Verify priority is non-zero (creature is actually targetable)
  if not params or not params.config or params.priority <= 0 then
    return nil, nil
  end
  
  return params, path
end

-- Recalculate best target from cache
-- IMPROVED: Uses live creature detection for accuracy
-- FIXED: Only count creatures with valid reachable paths
local function recalculateBestTarget()
  local pos = player:getPosition()
  if not pos then return end
  
  local bestTarget = nil
  local bestPriority = 0
  local totalDanger = 0
  local targetCount = 0
  local reachableCount = 0  -- NEW: Track only reachable creatures
  local unreachableCount = 0  -- NEW: Track blocked path creatures

  -- IMPROVED: Get creatures from live detection first
  local creatures = nil
  local liveCount, liveCreatures = 0, nil
  if EventTargeting and EventTargeting.getLiveMonsterCount then
    liveCount, liveCreatures = EventTargeting.getLiveMonsterCount()
  end
  
  -- If we have live creatures, use those as the authoritative source
  if liveCreatures and #liveCreatures > 0 then
    creatures = liveCreatures
  elseif CreatureCache.monsterCount > 0 and not CreatureCache.dirty then
    -- Fall back to cache only if live detection found nothing
    -- This handles edge cases where EventTargeting hasn't initialized
    local cacheCreatures = {}
    for id, data in pairs(CreatureCache.monsters) do
      if data.creature and not data.creature:isDead() then
        cacheCreatures[#cacheCreatures + 1] = data.creature
      end
    end
    creatures = cacheCreatures
  end
  
  -- If still no creatures, do a fresh scan
  if not creatures or #creatures == 0 then
    creatures = (MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby)
      and MovementCoordinator.MonsterCache.getNearby(10)
      or (SpectatorCache and SpectatorCache.getNearby(10, 10)
      or g_map.getSpectatorsInRange(pos, false, 10, 10))
  end
  
  if not creatures then return nil, 0, 0 end
  
  -- Rebuild cache from live creatures
  CreatureCache.monsters = {}
  CreatureCache.monsterCount = 0
  
  local playerZ = pos.z
  for i = 1, #creatures do
    local creature = creatures[i]
    if creature and isTargetableCreature(creature) then
      local okPos, cpos = pcall(function() return creature:getPosition() end)
      if okPos and cpos and cpos.z == playerZ then
        local okId, id = pcall(function() return creature:getId() end)
        id = id or i
        
        -- Calculate path and params
        local params, path = processCandidate(creature, pos)
        
        -- FIXED: Only add to cache if creature has a valid reachable path
        -- Creatures with blocked paths should not be counted as targetable
        if path and params and params.config then
          -- Creature is reachable - add to cache
          CreatureCache.monsters[id] = {
            creature = creature,
            path = path,
            pathTime = now,
            lastUpdate = now,
            reachable = true  -- Mark as reachable
          }
          CreatureCache.monsterCount = CreatureCache.monsterCount + 1
          reachableCount = reachableCount + 1
          targetCount = targetCount + 1
          totalDanger = totalDanger + (params.danger or 0)
          
          if params.priority > bestPriority then
            bestPriority = params.priority
            bestTarget = params
          end
        else
          -- Creature has blocked path - don't add to active targeting
          -- Track for display purposes only
          unreachableCount = unreachableCount + 1
        end
      end
    end
  end
  
  CreatureCache.lastFullUpdate = now
  
  -- Update cache state
  CreatureCache.bestTarget = bestTarget
  CreatureCache.bestPriority = bestPriority
  CreatureCache.totalDanger = totalDanger
  CreatureCache.dirty = false
  CreatureCache.unreachableCount = unreachableCount  -- Track blocked creatures

  return bestTarget, reachableCount, totalDanger
end

-- If we deferred enabling steps because core functions weren't ready, perform them now (with retries)
local function performPendingEnableOnce()
  if not pendingEnable then
    -- Nothing to do
    return true
  end
  if type(recalculateBestTarget) ~= 'function' or not (targetbotMacro and (type(targetbotMacro) == 'function' or type(targetbotMacro.setOn) == 'function')) then
    -- core not ready yet; will retry silently
    return false
  end
  pendingEnable = false
  -- performing deferred enable steps (core ready)
  -- If user requested a particular enabled state, apply it
  if pendingEnableDesired ~= nil then
    pcall(function()
      if targetbotMacro and type(targetbotMacro.setOn) == 'function' then
        targetbotMacro.setOn(pendingEnableDesired)
        targetbotMacro.delay = nil
      end
    end)
    pendingEnableDesired = nil
  end
  pcall(function() primeCreatureCache() end)
  invalidateCache()
  if debouncedInvalidateAndRecalc then debouncedInvalidateAndRecalc() end
  schedule(10, function() pcall(function() if type(recalculateBestTarget) == 'function' then recalculateBestTarget() end end) end)
  schedule(20, function() pcall(function() if type(targetbotMacro) == 'function' then targetbotMacro() elseif targetbotMacro and type(targetbotMacro.setOn) == 'function' then targetbotMacro.setOn(true) end end) end)
  return true
end

-- Schedule multiple retries with exponential backoff to cover different load timings
schedule(20, performPendingEnableOnce)
schedule(200, function() if not performPendingEnableOnce() then end end)
schedule(600, function() if not performPendingEnableOnce() then end end)
schedule(1600, function() if not performPendingEnableOnce() then warn('[TargetBot] post-init: deferred enable attempts exhausted') end end)

-- Prime the CreatureCache directly from current spectators (used when enabling targetbot)
local function primeCreatureCache()
  local p = player and player:getPosition()
  if not p then return end
  local creatures = (SpectatorCache and SpectatorCache.getNearby(10, 10)) or g_map.getSpectatorsInRange(p, false, 10, 10)
  if not creatures or #creatures == 0 then
    return
  end

  CreatureCache.monsters = {}
  CreatureCache.monsterCount = 0
  local snapshotCreatures = {}
  for i = 1, #creatures do
    local creature = creatures[i]
    if isTargetableCreature(creature) then
      local id = creature:getId()
      CreatureCache.monsters[id] = {
        creature = creature,
        path = nil,
        pathTime = 0,
        lastUpdate = now
      }
      table.insert(snapshotCreatures, { id = id, pos = creature:getPosition(), creature = creature })
      CreatureCache.monsterCount = CreatureCache.monsterCount + 1
    end
  end
  CreatureCache.lastFullUpdate = now
  CreatureCache.dirty = false
  CreatureCache.primeSnapshot = { ts = now, pos = p, creatures = snapshotCreatures }
end

-- Main TargetBot loop - optimized with EventBus caching
-- IMPROVED: Faster macro interval (200ms) for better responsiveness
local lastRecalcTime = 0
local RECALC_COOLDOWN_MS = 100  -- IMPROVED: Faster recalc cooldown
targetbotMacro = macro(200, function()
  local _msStart = os.clock()
  if not config or not config.isOn or not config.isOn() then
    return
  end

  -- Prevent execution before login is complete to avoid freezing
  if not g_game.isOnline() then return end

  -- If MonsterAI requested an imminent-attack pause, honor it briefly
  if monsterAIWaitUntil and now < monsterAIWaitUntil then
    cavebotAllowance = now + 100
    setStatusRight("Evading (MonsterAI)")
    return
  end

  -- TargetBot never triggers friend-heal; keep that path dormant to save cycles
  if HealEngine and HealEngine.setFriendHealingEnabled then
    HealEngine.setFriendHealingEnabled(false)
  end
  
  -- FAST PATH: If EventTargeting already has a valid target, use it
  -- This skips the expensive recalculation when event-driven targeting is handling things
  if EventTargeting and EventTargeting.isInCombat and EventTargeting.isInCombat() then
    local eventTarget = EventTargeting.getCurrentTarget and EventTargeting.getCurrentTarget()
    if eventTarget and not eventTarget:isDead() then
      -- EventTargeting is handling combat - just ensure we're attacking
      local currentAttack = g_game.getAttackingCreature and g_game.getAttackingCreature()
      if not currentAttack or currentAttack:getId() ~= eventTarget:getId() then
        -- Sync our attack target with EventTargeting's choice
        pcall(function() g_game.attack(eventTarget) end)
      end
      -- Let EventTargeting handle movement coordination
      setStatusRight("Targeting (Event)")
      lastAction = now
      return
    end
  end

  -- Danger-based auto-stop disabled per user request (no-op)
  -- if HealContext and HealContext.isDanger and HealContext.isDanger() then
  --   TargetBot.clearWalk()
  --   TargetBot.stopAttack(true)
  --   setStatusRight(STATUS_WAITING)
  --   return
  -- end
  
  local pos = player:getPosition()
  if not pos then return end
  
  -- Periodic cache cleanup
  cleanupCache()
  cleanupPathCache()
  
  -- Handle walking if destination is set
  TargetBot.walk()
  
  -- Check for looting first (event-driven: only process when dirty or when actively looting)
  local shouldProcessLoot = TargetBot.Looting.isDirty and TargetBot.Looting.isDirty() or (#TargetBot.Looting.list > 0)
  local lootResult = false
  if shouldProcessLoot then
    lootResult = TargetBot.Looting.process()
    TargetBot.Looting.clearDirty()
  end
  if lootResult then
    lastAction = now
    looterStatus = TargetBot.Looting.getStatus and TargetBot.Looting.getStatus() or "Looting"
    return
  else
    looterStatus = ""
  end
  
  -- Get best target (uses cache when possible)
    local bestTarget, targetCount, totalDanger
    -- If cache is clean and recent and we recalculated very recently, use cached values to avoid heavy work
    if not CreatureCache.dirty and (now - (CreatureCache.lastFullUpdate or 0)) < (CreatureCache.FULL_UPDATE_INTERVAL or 400) and (now - lastRecalcTime) < RECALC_COOLDOWN_MS then
      bestTarget = CreatureCache.bestTarget
      targetCount = 0
      totalDanger = CreatureCache.totalDanger or 0
    else
      lastRecalcTime = now
      bestTarget, targetCount, totalDanger = recalculateBestTarget()
    end
  
  -- IMPROVED: Get live monster count from EventTargeting (most accurate)
  local liveMonsterCount = 0
  if EventTargeting and EventTargeting.getLiveMonsterCount then
    liveMonsterCount = EventTargeting.getLiveMonsterCount()
  else
    liveMonsterCount = CreatureCache.monsterCount or 0
  end
  
  if not bestTarget then
    setWidgetTextSafe(ui.target.right, "-")
    setWidgetTextSafe(ui.danger.right, "0")
    setWidgetTextSafe(ui.config.right, "-")
    dangerValue = 0
    
    -- FIXED: Check for unreachable creatures (blocked paths)
    -- If there are only unreachable creatures, allow CaveBot to proceed immediately
    local unreachableCount = CreatureCache.unreachableCount or 0
    local reachableOnScreen = CreatureCache.monsterCount or 0
    
    -- Check if there are REACHABLE monsters on screen
    if reachableOnScreen > 0 then
      -- There are reachable monsters but no valid target (edge case)
      setStatusRight("Targeting (" .. tostring(reachableOnScreen) .. ")")
      if EventTargeting and EventTargeting.refreshLiveCount then
        EventTargeting.refreshLiveCount()
      end
      invalidateCache()
      cavebotAllowance = now + 300
      return
    elseif unreachableCount > 0 then
      -- All creatures have blocked paths - allow CaveBot to proceed
      -- Don't waste time trying to attack creatures we can't reach
      setStatusRight("Blocked (" .. tostring(unreachableCount) .. ")")
      cavebotAllowance = now + 100  -- Allow CaveBot immediately
      return
    end
    
    cavebotAllowance = now + 100
    setStatusRight(STATUS_WAITING)
    return
  end
  
  -- Update danger value
  dangerValue = totalDanger
  setWidgetTextSafe(ui.danger.right, tostring(totalDanger))
  
  -- PARTY HUNT: Check if force follow mode is active
  -- When force follow is triggered and combat window expires, pause targeting to let follower catch up
  if TargetBot.isForceFollowActive and TargetBot.isForceFollowActive() then
    -- Allow CaveBot to walk (which triggers follow movement)
    cavebotAllowance = now + 100
    setStatusRight("Following Leader")
    -- Still show target info but don't attack
    if bestTarget.creature then
      pcall(function() setWidgetTextSafe(ui.target.right, bestTarget.creature:getName() .. " (paused)") end)
    end
    return
  end
  
  -- Attack best target
  if bestTarget.creature and bestTarget.config then

    lastAction = now
    setWidgetTextSafe(ui.target.right, bestTarget.creature:getName())
    setWidgetTextSafe(ui.config.right, bestTarget.config.name or "-")
    
    -- KILL BEFORE WALK: Block CaveBot while we have monsters to kill
    -- DynamicLure and SmartPull can bypass by calling allowCaveBot() in creature_attack.lua
    -- Do NOT set cavebotAllowance here - this keeps CaveBot paused until all monsters are dead
    -- IMPROVED: Use live count for accurate status
    local displayCount = liveMonsterCount > 0 and liveMonsterCount or targetCount
    setStatusRight("Killing (" .. tostring(displayCount) .. ")")

    -- Delegate to unified attack/walk logic from creature_attack
    -- This ensures chase, positioning, avoidance and AttackBot integration run correctly
    -- DynamicLure/SmartPull will call allowCaveBot() if lure conditions are met
    pcall(function() TargetBot.Creature.attack(bestTarget, targetCount, false) end)
  else
    setWidgetTextSafe(ui.target.right, "-")
    setWidgetTextSafe(ui.config.right, "-")
    
    -- No valid target config - check if monsters still exist
    -- IMPROVED: Use live count for accuracy
    if liveMonsterCount > 0 then
      setStatusRight("Clearing (" .. tostring(liveMonsterCount) .. ")")
      -- FIXED: Set cavebotAllowance to prevent indefinite blocking
      cavebotAllowance = now + 300
      return
    end
    
    cavebotAllowance = now + 100
    setStatusRight(STATUS_WAITING)
  end

  -- Check macro execution time (throttled warning)
  local _msElapsed = os.clock() - _msStart
  if _msElapsed > 0.1 and (now - (_lastTargetbotSlowWarn or 0)) > 5000 then
    warn("[TargetBot] Slow macro detected: " .. tostring(math.floor(_msElapsed * 1000)) .. "ms")
    _lastTargetbotSlowWarn = now
  end
end)

-- Module ready: mark initialized and attempt to process pending enable immediately
moduleInitialized = true
pcall(function() performPendingEnableOnce() end)

-- Config setup (moved here so macro/recalc are defined before callback runs)
config = Config.setup("targetbot_configs", configWidget, "json", function(name, enabled, data)
  -- Save character's profile preference when profile changes (multi-client support)
  if enabled and name and name ~= "" and setCharacterProfile then
    setCharacterProfile("targetbotProfile", name)
  end

  if not data then
    setStatusRight("Off")
    if targetbotMacro and targetbotMacro.setOff then
      return targetbotMacro.setOff() 
    end
    return
  end
  TargetBot.Creature.resetConfigs()
  for _, value in ipairs(data["targeting"] or {}) do
    TargetBot.Creature.addConfig(value)
  end
  TargetBot.Looting.update(data["looting"] or {})

  -- Determine final enabled state:
  local finalEnabled = enabled
  if not TargetBot._initialized then
    TargetBot._initialized = true
    if storage.targetbotEnabled == true or storage.targetbotEnabled == false then
      finalEnabled = storage.targetbotEnabled
    end
  else
    if enabled == (data and data.enabled) then
      storage.targetbotEnabled = nil
    else
      storage.targetbotEnabled = enabled
    end
  end

  -- Update UI to reflect final state
  if finalEnabled then
    setStatusRight("On")
  else
    setStatusRight("Off")
  end

  if targetbotMacro and targetbotMacro.setOn then
    targetbotMacro.setOn(finalEnabled)
    targetbotMacro.delay = nil
  end
  -- Force immediate cache refresh & recalc when enabling so existing monsters are picked up
  if finalEnabled then
    player = g_game and g_game.getLocalPlayer() or player
    pcall(function() primeCreatureCache() end)
    invalidateCache()
    if debouncedInvalidateAndRecalc then debouncedInvalidateAndRecalc() end
    schedule(50, function() pcall(function() if type(recalculateBestTarget) == 'function' then recalculateBestTarget() end end) end)
    schedule(100, function() pcall(function() if targetbotMacro then pcall(targetbotMacro) end end) end)
  end
  lureEnabled = true
end)

-- Stop attacking the current target
TargetBot.stopAttack = function(clearWalk)


-- Module load diagnostics: print whether key functions are available shortly after load
-- Module init check (silent): mark module as initialized after a short delay and attempt pending enable
schedule(1500, function()
  moduleInitialized = true
  pcall(function() performPendingEnableOnce() end)
  -- Startup sanity log to confirm TargetBot module loaded
  -- warn("[TargetBot] module initialized. TargetBot._removed=" .. tostring(TargetBot and TargetBot._removed) .. ", TargetBot.isOn=" .. tostring(TargetBot and TargetBot.isOn and TargetBot.isOn()))
end)


  if clearWalk then
    TargetBot.clearWalk()
  end
  -- OTClient has a built-in autoAttackTarget() that toggles attack
  -- Calling it when attacking will stop the attack
  if autoAttackTarget then
    autoAttackTarget(nil)
  end
end

-- Note: Profile restoration is handled early in configs.lua
-- before Config.setup() is called, so the dropdown loads correctly



-- End of TargetBot module
