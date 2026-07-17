local zChanging = nExBot.zChanging or function() return false end
local targetbotMacro = nil
local config = nil
lastAction = 0
local cavebotAllowance = 0
local lureEnabled = true
local recalculateBestTarget  -- forward declaration: defined at ~L2054, used by EventBus closures above it


-- Values based on PRIORITY_SCALE = 1000 (config priority 1 = 1000 base)
local STICKY_BONUS = 800       -- ~80% of one config priority level
local STICKY_BONUS_FINISH = 1200  -- extra bonus when target is low HP
local lastEngagementAt = 0     -- minimum engagement duration guard (ms)

local getClient = nExBot.Shared.getClient

local getClientVersion = nExBot.Shared.getClientVersion

if not nExBot.target_pathfinding then
  dofile("/targetbot/target_pathfinding.lua")
end
local targetPathfinding = nExBot.target_pathfinding

-- ═══════════════════════════════════════════════════════════════════════════
-- OPENTIBIABR TARGETING ENHANCEMENTS (v3.1)
-- Load enhanced targeting module for OpenTibiaBR-specific optimizations
-- Provides line-of-sight detection and pattern-based AoE helpers.
-- ═══════════════════════════════════════════════════════════════════════════
local OpenTibiaBRTargeting = nil

local function getOpenTibiaBRTargeting()
  if OpenTibiaBRTargeting ~= nil then return OpenTibiaBRTargeting end
  if nExBot and nExBot.OpenTibiaBRTargeting then
    OpenTibiaBRTargeting = nExBot.OpenTibiaBRTargeting
    return OpenTibiaBRTargeting
  end
  return nil
end

local function hasSightSpectators()
  local otbr = getOpenTibiaBRTargeting()
  return otbr and otbr.getVisibleCreatures ~= nil
end

-- Load PathUtils if available (shared module for creature validation)
local PathUtils = nil
local SharedHelpers = nExBot.SharedHelpers or {}
local function ensurePathUtils()
  if PathUtils then return PathUtils end
  SharedHelpers.ensurePathUtils()
  PathUtils = PathUtils  -- Re-check global after dofile
  return PathUtils
end
ensurePathUtils()

-- ═══════════════════════════════════════════════════════════════════════════
-- OPTIMIZED CREATURE VALIDATION (Reduce pcall overhead)
-- Single pcall wrapper that validates multiple creature properties at once
-- ═══════════════════════════════════════════════════════════════════════════
local function validateCreature(creature)
  if not creature then
    return { valid = false }
  end
  
  -- Fallback: single pcall to get all properties at once
  local ok, result = pcall(function()
    return {
      valid = true,
      isDead = creature:isDead(),
      isMonster = creature:isMonster(),
      isPlayer = creature:isPlayer(),
      isNpc = creature:isNpc(),
      id = creature:getId(),
      position = creature:getPosition(),
      name = creature:getName(),
      healthPercent = (type(creature.getHealthPercent) == "function" and creature:getHealthPercent()) or 100,
    }
  end)
  
  if not ok then
    return { valid = false }
  end
  
  return result
end

-- Quick dead check (single pcall, cached result)
local function isCreatureDead(creature)
  return SC.isDead(creature)
end

-- Quick ID check (single pcall)
local function getCreatureId(creature)
  return SC.getId(creature)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MONSTER DETECTION RANGE (v3.0)
-- IMPROVED: Increased range for better monster detection
-- This prevents the bot from leaving monsters behind when moving to waypoints
-- ═══════════════════════════════════════════════════════════════════════════
local MONSTER_DETECTION_RANGE = 14  -- INCREASED from 10 to 14 (covers full visible screen)
local MONSTER_TARGETING_RANGE = 12  -- INCREASED from 10 to 12 (targeting range)

local dangerValue = 0
local looterStatus = ""

-- ═══════════════════════════════════════════════════════════════════════════
-- ATTACK STATE MACHINE INTEGRATION (Default Attack System)
-- The AttackStateMachine is now the PRIMARY attack handler for TargetBot.
-- It provides linear, consistent targeting with automatic recovery.
-- ═══════════════════════════════════════════════════════════════════════════

-- initialization state
local pendingEnable = false
local pendingEnableDesired = nil
local moduleInitialized = false
local _lastTargetbotSlowWarn = 0

-- Local cached reference to local player (updated on relogin)
local Client = getClient()
local player = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer()) or nil

-- Safe function calls to prevent "attempt to call global function (a nil value)" errors
local SafeCall = SafeCall or require("core.safe_call")


local SC = SafeCreature or {}

-- Compatibility: robust safe unpack (works when neither table.unpack nor unpack exist)
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

-- Centralized attack controller (anti-spam + anti-zigzag switching)
-- IMPROVED: Faster intervals for more responsive attacking
local AttackController = {
  lastCommandTime = 0,
  lastTargetId = nil,
  lastReason = nil,
  minInterval = 100,        -- Reduced: Minimum time between any attack commands
  sameTargetInterval = 150, -- Reduced: Minimum time between same-target commands
  minSwitchInterval = 400,  -- Reduced: Minimum time between target switches
  lastConfirmedTime = 0,    -- When attack was last confirmed by server
  attackState = "idle"      -- idle, pending, confirmed
}

TargetBot.AttackController = AttackController

-- ═══════════════════════════════════════════════════════════════════════════
-- REQUEST ATTACK (Unified Attack Interface)
-- This is the SINGLE entry point for all attack requests in TargetBot.
-- Uses AttackStateMachine for state-based attack management.
-- OPTIMIZED: Uses consolidated validateCreature for reduced pcall overhead
-- ═══════════════════════════════════════════════════════════════════════════
TargetBot.requestAttack = function(creature, reason, force)
  if not creature then return false end
  if isCreatureDead(creature) then return false end
  local cfgs = TargetBot.Creature and TargetBot.Creature.getConfigs and TargetBot.Creature.getConfigs(creature)
  local config = cfgs and cfgs[1] or { name = "intelligence_runtime", priority = 1, chase = true }
  if not TargetBot.submitSelection then return false end
  return TargetBot.submitSelection({ creature = creature, config = config, priority = (config.priority or 1) * 1000 },
    1, reason or "TargetBotRequest")
end

-- Use TargetBotCore if available (DRY principle)
local Core = TargetCore or {}

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

-- Pre-allocated status strings (PERFORMANCE: avoid string concatenation)
local STATUS_WAITING = "Waiting"

-- PERFORMANCE: Optimized Creature Cache
-- Uses event-driven updates with LRU eviction and TargetCore integration
local monsterCache = {
  monsters = {},          -- {id -> {creature, path, params, lastUpdate, priority}}
  monsterCount = 0,
  bestTarget = nil,
  bestPriority = 0,
  totalDanger = 0,
  dirty = true,           -- Flag to recalculate on next tick
  lastFullUpdate = 0,
  FULL_UPDATE_INTERVAL = 400,  -- Reduced for faster adaptation
  PATH_TTL = 400,         -- Path cache valid for 400ms
  lastCleanup = 0,
  CLEANUP_INTERVAL = 1500,
  -- LRU eviction
  accessOrder = {},       -- Array of IDs in access order
  posMap = {},
  maxSize = 50            -- Max cached creatures
}

-- Mark cache as dirty (needs recalculation)
local function invalidateCache()
  monsterCache.dirty = true
end

local function clearPaths()
  for id, data in pairs(monsterCache.monsters) do
    data.path = nil
    data.pathTime = nil
  end
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
local SharedHelpers = nExBot.SharedHelpers or {}
  local makeDebounce = SharedHelpers.makeDebounce

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
end

-- LRU eviction helper: move ID to end of access order — O(1) via posMap
local function touchCreature(id)
  local order = monsterCache.accessOrder
  local pmap = monsterCache.posMap
  local oldIdx = pmap[id]
  if oldIdx then
    local last = #order
    if oldIdx ~= last then
      local movedId = order[last]
      order[oldIdx] = movedId
      pmap[movedId] = oldIdx
    end
    order[last] = id
    pmap[id] = last
  else
    order[#order + 1] = id
    pmap[id] = #order
  end
end

-- LRU eviction: remove oldest entries when over capacity
local function evictOldestCreatures()
  local order = monsterCache.accessOrder
  local pmap = monsterCache.posMap
  while #order > monsterCache.maxSize do
    local oldestId = order[1]
    local last = #order
    order[1] = order[last]
    pmap[order[1]] = 1
    order[last] = nil
    pmap[oldestId] = nil
    if monsterCache.monsters[oldestId] then
      monsterCache.monsters[oldestId] = nil
      monsterCache.monsterCount = monsterCache.monsterCount - 1
    end
  end
end

-- Clean up stale cache entries (improved with LRU)
local function cleanupCache()
  if now - monsterCache.lastCleanup < monsterCache.CLEANUP_INTERVAL then
    return
  end
  
  local cutoff = now - 3000  -- Reduced from 5s to 3s for faster cleanup
  local newMonsters = {}
  local newOrder = {}
  local newPmap = {}
  local count = 0
  
  -- Keep only recent entries in access order
  for i = 1, #monsterCache.accessOrder do
    local id = monsterCache.accessOrder[i]
    local data = monsterCache.monsters[id]
    if data and data.lastUpdate > cutoff and data.creature and not data.creature:isDead() then
      newMonsters[id] = data
      count = count + 1
      newOrder[count] = id
      newPmap[id] = count
    end
  end
  
  monsterCache.monsters = newMonsters
  monsterCache.accessOrder = newOrder
  monsterCache.posMap = newPmap
  monsterCache.monsterCount = count
  monsterCache.lastCleanup = now
  invalidateCache()
end

-- Update a single creature in cache (called on events)
-- OPTIMIZED: Uses consolidated validateCreature for reduced pcall overhead
local function updateCreatureInCache(creature)
  -- Use optimized validation (single pcall for all properties)
  local cv = validateCreature(creature)
  
  -- Handle dead or invalid creature
  if not cv.valid or cv.isDead then
    local id = cv.id or getCreatureId(creature)
    if id and monsterCache.monsters[id] then
      monsterCache.monsters[id] = nil
      monsterCache.monsterCount = monsterCache.monsterCount - 1
      -- Remove from access order — O(1) via posMap
      local idx = monsterCache.posMap[id]
      if idx then
        local order = monsterCache.accessOrder
        local last = #order
        if idx ~= last then
          local movedId = order[last]
          order[idx] = movedId
          monsterCache.posMap[movedId] = idx
        end
        order[last] = nil
        monsterCache.posMap[id] = nil
      end
    end
    invalidateCache()
    return
  end
  
  -- Skip non-monsters
  if not cv.isMonster then return end
  
  local id = cv.id
  if not id then return end
  
  -- Get player position (separate call as player is a different object)
  local pos = SC.getPosition(player)
  local cpos = cv.position
  if not pos or not cpos then return end
  
  -- Use TargetBotCore distance if available, otherwise calculate
  local dist
  if Core.Geometry and Core.Geometry.chebyshevDistance then
    dist = Core.Geometry.chebyshevDistance(pos, cpos)
  else
    dist = math.max(math.abs(pos.x - cpos.x), math.abs(pos.y - cpos.y))
  end
  
  -- Skip if too far (reduced from 10 to 8 for better performance)
  if dist > 8 then
    if monsterCache.monsters[id] then
      monsterCache.monsters[id] = nil
      monsterCache.monsterCount = monsterCache.monsterCount - 1
      local idx = monsterCache.posMap[id]
      if idx then
        local order = monsterCache.accessOrder
        local last = #order
        if idx ~= last then
          local movedId = order[last]
          order[idx] = movedId
          monsterCache.posMap[movedId] = idx
        end
        order[last] = nil
        monsterCache.posMap[id] = nil
      end
    end
    return
  end
  
  local entry = monsterCache.monsters[id]
  if not entry then
    entry = { 
      creature = creature, 
      lastUpdate = now,
      distance = dist
    }
    monsterCache.monsters[id] = entry
    monsterCache.monsterCount = monsterCache.monsterCount + 1
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
  if not entry.path or now - (entry.pathTime or 0) > monsterCache.PATH_TTL then
    entry.path = findPath(pos, cpos, 10, PATH_PARAMS)
    entry.pathTime = now
  end
  
  invalidateCache()
end

-- Public API for other modules
TargetBot.ChaseModeEnforcer = ChaseModeEnforcer
TargetBot.enforceChaseModeNow = enforceChaseModeNow

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

local oldTibia = getClientVersion() < 960

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
  return lastAction + 1000 > now
end

TargetBot.isCaveBotActionAllowed = function()
  return cavebotAllowance > now
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MONSTER DETECTION FOR CAVEBOT (v3.0)
-- Check if there are targetable monsters on screen that should block cavebot
-- This prevents the bot from leaving monsters behind
-- ═══════════════════════════════════════════════════════════════════════════
TargetBot.hasTargetableMonstersOnScreen = function()
  if not TargetBot.isOn() then return false end
  
  local p = player and player:getPosition()
  if not p then return false end
  
  -- Get all creatures in detection range
  local creatures = BotCore.Creatures.getNearby(MONSTER_DETECTION_RANGE, MONSTER_DETECTION_RANGE)
  
  if not creatures or #creatures == 0 then return false end
  
  local monsterCount = 0
  local playerZ = p.z
  
  for i = 1, #creatures do
    local creature = creatures[i]
    if creature then
      if SC.isMonster(creature) then
        if not SC.isDead(creature) then
          local cpos = SC.getPosition(creature)
          if cpos and cpos.z == playerZ then
            -- Check if this creature has a matching TargetBot config (it's targetable)
            local cfgs = TargetBot.Creature.getConfigs and TargetBot.Creature.getConfigs(creature)
            if cfgs and cfgs[1] then
              monsterCount = monsterCount + 1
            end
          end
        end
      end
    end
  end
  
  return monsterCount > 0, monsterCount
end

-- Check if bot should wait for monsters (stricter version)
TargetBot.shouldWaitForMonsters = function()
  -- If actively attacking, definitely wait
  if TargetBot.isActive() then return true end
  
  -- Check for targetable monsters on screen
  local hasMonsters, count = TargetBot.hasTargetableMonstersOnScreen()
  if hasMonsters then return true end
  
  -- Check MonsterAI engagement lock
  if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.isEngaged then
    local isEngaged = MonsterAI.Scenario.isEngaged()
    if isEngaged then return true end
  end
  
  return false
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

-- ═══════════════════════════════════════════════════════════════════════════
-- TARGETBOT ON/OFF HANDLERS v2.5 - Safer state management with persistence
-- Uses explicitlyDisabled flag to prevent auto-enable from any source
-- Flag is now persisted to storage to survive reloads
-- ═══════════════════════════════════════════════════════════════════════════

local function loadExplicitlyDisabledState()
  local storage = type(nExBotStorageGet) == "function" and nExBotStorageGet("targetbot") or nil
  if storage and storage.targetbotExplicitlyDisabled == true then
    return true
  end
  return false
end

TargetBot.explicitlyDisabled = loadExplicitlyDisabledState()

-- Timestamp of last user action (for debouncing)
TargetBot._lastUserToggle = 0

-- v2.4: setOn now checks explicitlyDisabled and has optional 'force' parameter
-- Regular calls from CaveBot/lure scripts will be blocked when explicitlyDisabled is true
-- Only direct user clicks (force=true) or clearing explicitlyDisabled first will work
TargetBot.setOn = function(val, force)
  if val == false then  
    return TargetBot.setOff(true)
  end
  
  -- CRITICAL: If explicitly disabled and this is NOT a forced (user-initiated) call, block it
  if TargetBot.explicitlyDisabled and not force then
    -- Don't enable - user explicitly turned it off
    return
  end
  
  -- Clear the explicit disable flag - user wants it ON (or force was used)
  TargetBot.explicitlyDisabled = false
  TargetBot._lastUserToggle = now or os.time() * 1000
  
  -- v2.5: Persist the flag to storage so it survives reloads
  if UnifiedStorage then
    UnifiedStorage.set("targetbot.explicitlyDisabled", false)
  end
  storage.targetbotExplicitlyDisabled = false
  
  -- Stop any pending recovery attempts
  reloginRecovery.active = false
  
  -- Save user's choice to storage BEFORE triggering config callback
  if UnifiedStorage then 
    UnifiedStorage.set("targetbot.enabled", true) 
  else 
    storage.targetbotEnabled = true 
  end
  
  -- Notify MonsterAI and other modules
  if EventBus then
    pcall(function() EventBus.emit("targetbot/enabled") end)
  end
  
  config.setOn()  -- This triggers callback which handles UI update
end

TargetBot.setOff = function(val)
  if val == false then  
    return TargetBot.setOn(true)
  end
  
  -- SET the explicit disable flag - user wants it OFF, prevent ALL auto-enable
  TargetBot.explicitlyDisabled = true
  TargetBot._lastUserToggle = now or os.time() * 1000
  
  -- v2.5: Persist the flag to storage so it survives reloads
  if UnifiedStorage then
    UnifiedStorage.set("targetbot.explicitlyDisabled", true)
  end
  storage.targetbotExplicitlyDisabled = true
  
  -- IMMEDIATELY stop all recovery and pending operations
  reloginRecovery.active = false
  reloginRecovery.endTime = 0
  attackWatchdog.attempts = 0
  attackWatchdog.lastForce = 0
  
  -- Clear any pending targets in EventTargeting
  if EventTargeting and EventTargeting.clearState then
    pcall(function() EventTargeting.clearState() end)
  end
  
  -- Cancel current attack
  pcall(function() ClientService.cancelAttackAndFollow() end)
  
  -- Save user's choice to storage BEFORE triggering config callback
  if UnifiedStorage then 
    UnifiedStorage.set("targetbot.enabled", false) 
  else 
    storage.targetbotEnabled = false 
  end
  
  -- Clear local target lock state
  if TargetBot.LocalTargetLock then
    TargetBot.LocalTargetLock.targetId = nil
    TargetBot.LocalTargetLock.targetHealth = nil
    TargetBot.LocalTargetLock.switchCount = 0
    TargetBot.LocalTargetLock.recentTargets = {}
  end
  
  -- Clear creature cache to stop targeting
  monsterCache.monsters = {}
  monsterCache.monsterCount = 0
  monsterCache.bestTarget = nil
  monsterCache.bestPriority = 0
  monsterCache.dirty = false
  monsterCache.accessOrder = {}
  monsterCache.posMap = {}
  
  -- Notify MonsterAI and other modules
  if EventBus then
    pcall(function() EventBus.emit("targetbot/disabled") end)
  end
  
  -- Update status
  setStatusRight("Off")
  
  config.setOff()  -- This triggers callback which handles UI update
end

-- Helper function to check if TargetBot should be active
-- This respects the explicitlyDisabled flag
TargetBot.canAttack = function()
  -- If explicitly disabled by user, NEVER allow attacks
  if TargetBot.explicitlyDisabled then
    return false
  end
  -- Check the normal isOn state
  if not TargetBot.isOn or not TargetBot.isOn() then
    return false
  end
  return true
end

TargetBot.getCurrentProfile = function()
  if UnifiedStorage and UnifiedStorage.get("targetbot.selectedConfig") then
    return UnifiedStorage.get("targetbot.selectedConfig")
  end
  return storage._configs.targetbot_configs.selected
end

-- Use shared BotConfigName from configs.lua (DRY)
local botConfigName = BotConfigName or modules.game_bot.contentsPanel.config:getCurrentOption().text
TargetBot.setCurrentProfile = function(name)
  if not g_resources.fileExists("/bot/"..botConfigName.."/targetbot_configs/"..name..".json") then
    return warn("there is no targetbot profile with that name!")
  end
  local wasOn = TargetBot.isOn()
  TargetBot.setOff()
  storage._configs.targetbot_configs.selected = name
  -- Save to UnifiedStorage for per-character persistence
  if UnifiedStorage then
    UnifiedStorage.set("targetbot.selectedConfig", name)
    if EventBus and EventBus.emitConfigChange then
      EventBus.emitConfigChange("targetbot", name)
    end
  end
  -- Save character's profile preference for multi-client support
  if setCharacterProfile then
    setCharacterProfile("targetbotProfile", name)
  end
  -- Only restore enabled state if not explicitly disabled by user
  if wasOn and not TargetBot.explicitlyDisabled then
    TargetBot.setOn()
  end
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
  local ms = tonumber(time) or 200
  if ms < 50 then
    ms = 50
  end
  cavebotAllowance = now + ms
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
  return monsterCache.monsterCount > 0
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
  return monsterCache.monsterCount or 0
end

-- Optimized Main TargetBot Loop
-- Uses EventBus-driven cache for reduced CPU usage and better accuracy
-- Only recalculates when cache is dirty (events occurred)

-- Process a single candidate creature for targeting
local function processCandidate(creature, pos, isCurrentTarget)
  if not creature or creature:isDead() or not targetPathfinding.isTargetableCreature(creature) then return nil, nil end
  local cpos = creature:getPosition()
  if not cpos then return nil, nil end
  local dist = math.max(math.abs(cpos.x - pos.x), math.abs(cpos.y - pos.y))
  if not TargetReachability or not TargetReachability.evaluate then return nil, nil end
  if TargetReachability.isQuarantined and TargetReachability.isQuarantined(creature) then return nil, nil end

  local configs = TargetBot.Creature.getConfigs and TargetBot.Creature.getConfigs(creature)
  local config = configs and configs[1] or nil
  local mode = config and (config.keepDistance or (config.distance or 1) > 1) and "ranged" or "melee"
  local evaluated = TargetReachability.evaluate(creature, {
    source = isCurrentTarget and "current_candidate" or "candidate",
    mode = mode,
    config = config,
    minDistance = mode == "ranged" and 1 or 1,
    maxDistance = mode == "ranged" and ((config and config.distance) or 7) or 1,
  })
  if not evaluated.attackable then
    TargetReachability.quarantine(creature, evaluated)
    return nil, nil
  end
  local path = evaluated.path

  local params = TargetBot.Creature.calculateParams(creature, path)
  if not params or not params.config then return nil, nil end
  if params.priority <= 0 and dist > 3 then return nil, nil end
  return params, path
end

-- Recalculate best target from cache
-- IMPROVED: Uses live creature detection for accuracy
-- FIXED: Only count creatures with valid reachable paths
recalculateBestTarget = function()
  local pos = player:getPosition()
  if not pos then return end

  local function getAdjustedPriority(creature, params, dist)
    if not creature or not params then return (params and params.priority) or 0 end
    local base = params.priority or 0
    local okHp, hp = pcall(function() return creature:getHealthPercent() end)
    hp = okHp and hp or 100
    if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.modifyPriority then
      local okId, id = pcall(function() return creature:getId() end)
      if okId and id then
        base = MonsterAI.Scenario.modifyPriority(id, base, hp)
      end
    end
    if dist then
      base = base + math.max(0, (8 - dist)) * 2
    end
    base = base + ((100 - hp) * 0.15)
    return base
  end

  local bestTarget = nil
  local bestPriority = 0
  local totalDanger = 0
  local targetCount = 0
  local reachableCount = 0  -- Track only reachable creatures
  local unreachableCount = 0  -- Track blocked path creatures
  
  -- v2.2: Track current target for stickiness - DO NOT lose it during recalculation
  local Client = getClient()
  local currentAttackTarget = ClientService.getAttackingCreature()
  local currentTargetId = currentAttackTarget and currentAttackTarget:getId() or nil
  local currentTargetStillValid = false  -- Will be set to true if current target is found

  -- IMPROVED: Get creatures from live detection first
  local creatures = nil
  local liveCount, liveCreatures = 0, nil
  if EventTargeting and EventTargeting.getLiveMonsterCount then
    liveCount, liveCreatures = EventTargeting.getLiveMonsterCount()
  end
  
  -- If we have live creatures, use those as the authoritative source
  if liveCreatures and #liveCreatures > 0 then
    creatures = liveCreatures
  elseif monsterCache.monsterCount > 0 and not monsterCache.dirty then
    -- Fall back to cache only if live detection found nothing
    -- This handles edge cases where EventTargeting hasn't initialized
    local cacheCreatures = {}
    for id, data in pairs(monsterCache.monsters) do
      if data.creature and not data.creature:isDead() then
        cacheCreatures[#cacheCreatures + 1] = data.creature
      end
    end
    creatures = cacheCreatures
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- OPENTIBIABR ENHANCEMENT: Use getSightSpectators for line-of-sight detection
  -- This gives us only creatures we can actually see (no obstacles between)
  -- Falls back to standard detection on non-OpenTibiaBR clients
  -- ═══════════════════════════════════════════════════════════════════════════
  if not creatures or #creatures == 0 then
    local otbr = getOpenTibiaBRTargeting()
    if otbr and hasSightSpectators() then
      -- Use OpenTibiaBR's optimized sight spectators
      local sightCreatures = otbr.getVisibleCreatures(pos, false)
      if sightCreatures and #sightCreatures > 0 then
        creatures = sightCreatures
      end
    end
  end
  
  -- If still no creatures, do a fresh scan with standard methods
  if not creatures or #creatures == 0 then
    creatures = BotCore.Creatures.getNearby(MONSTER_DETECTION_RANGE, MONSTER_DETECTION_RANGE)
  end
  
  if not creatures then return nil, 0, 0 end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- OPENTIBIABR ENHANCEMENT: Pre-calculate batch paths to all monsters
  -- Instead of calculating paths one by one, batch them for ~30-50% speedup
  -- ═══════════════════════════════════════════════════════════════════════════
  -- Rebuild cache from live creatures
  monsterCache.monsters = {}
  monsterCache.monsterCount = 0
  
  local playerZ = pos.z
  
  -- v2.2: First pass - find current target to ensure it's not skipped
  -- This prevents the "leaving monsters behind" issue
  local currentTargetParams = nil
  local currentTargetPath = nil
  
  for i = 1, #creatures do
    local creature = creatures[i]
    if creature and targetPathfinding.isTargetableCreature(creature) then
      local cpos = SC.getPosition(creature)
      if cpos and cpos.z == playerZ then
        local id = SC.getId(creature)
        id = id or i
        
        -- v2.2: Special handling for current target - be more lenient with path validation
        local isCurrentTarget = (currentTargetId and id == currentTargetId)
        
        -- Calculate path and params (pass isCurrentTarget for enhanced path finding)
        local dist = math.max(math.abs(cpos.x - pos.x), math.abs(cpos.y - pos.y))
        local params, path = processCandidate(creature, pos, isCurrentTarget)
        
        -- Current and new targets share the same authoritative validation.
        if path and params and params.config then
          params.priority = getAdjustedPriority(creature, params, dist)
          -- Creature is reachable - add to cache
          monsterCache.monsters[id] = {
            creature = creature,
            path = path,
            pathTime = now,
            lastUpdate = now,
            reachable = true
          }
          monsterCache.monsterCount = monsterCache.monsterCount + 1
          reachableCount = reachableCount + 1
          targetCount = targetCount + 1
          totalDanger = totalDanger + (params.danger or 0)
          
          -- v2.2: Track if current target is still valid
          if isCurrentTarget then
            currentTargetStillValid = true
            currentTargetParams = params
            currentTargetPath = path
          end
          
          if params.priority > bestPriority then
            bestPriority = params.priority
            bestTarget = params
          end
        else
          -- Creature has blocked path - don't add to active targeting
          unreachableCount = unreachableCount + 1
        end
      end
    end
  end
  
  -- v2.2: If current target is still valid, ensure it's not replaced by a marginally better target
  -- This implements "target stickiness" at the recalculation level

  -- threshold approach kept as safety net for edge cases
  if currentTargetStillValid and currentTargetParams and bestTarget then
    local currentHP = currentAttackTarget:getHealthPercent()
    if currentHP < 70 then
      local switchThreshold = 15
      if currentHP < 50 then switchThreshold = 25 end
      if currentHP < 30 then switchThreshold = 40 end
      if currentHP < 15 then switchThreshold = 75 end
      if bestTarget ~= currentTargetParams then
        local priorityAdvantage = bestTarget.priority - currentTargetParams.priority
        if priorityAdvantage < switchThreshold then
          bestTarget = currentTargetParams
          bestPriority = currentTargetParams.priority
        end
      end
    end
  end

  -- MonsterAI Scenario integration: prevent illegal switches (anti-zigzag)
  if currentTargetStillValid and currentTargetParams and bestTarget and bestTarget ~= currentTargetParams then
    if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.shouldAllowTargetSwitch then
      local okNewId, newId = pcall(function() return bestTarget.creature and bestTarget.creature:getId() end)
      local okNewHp, newHp = pcall(function() return bestTarget.creature and bestTarget.creature:getHealthPercent() end)
      if okNewId and newId then
        local allowed = MonsterAI.Scenario.shouldAllowTargetSwitch(newId, bestTarget.priority or 0, okNewHp and newHp or nil)
        if not allowed then
          bestTarget = currentTargetParams
          bestPriority = currentTargetParams.priority
        end
      end
    end
  end
  
  monsterCache.lastFullUpdate = now
  
  -- Update cache state
  monsterCache.bestTarget = bestTarget
  monsterCache.bestPriority = bestPriority
  monsterCache.totalDanger = totalDanger
  monsterCache.dirty = false
  monsterCache.unreachableCount = unreachableCount

  return bestTarget, reachableCount, totalDanger
end

local pendingEnable = false
local pendingEnableDesired = nil
local moduleInitialized = false

local function performPendingEnableOnce()
  if pendingEnable then return true end
  if type(recalculateBestTarget) ~= 'function' or not (targetbotMacro and (type(targetbotMacro) == 'function' or type(targetbotMacro.setOn) == 'function')) then
    return false
  end
  pendingEnable = true
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
  return true
end

local function primeCreatureCache()
  local pos = nil
  local Client = getClient()
  local p = Client and Client.getLocalPlayer and Client.getLocalPlayer()
  if p then pos = p:getPosition() end
  if not pos then return end
  local creatures = getSpectators(pos, false, false, 8) or {}
  local now = os.clock()
  monsterCache.monsters = {}
  monsterCache.monsterCount = 0
  local snapshotCreatures = {}
  for i = 1, #creatures do
    local creature = creatures[i]
    if targetPathfinding.isTargetableCreature and targetPathfinding.isTargetableCreature(creature) then
      local id = creature:getId()
      monsterCache.monsters[id] = {
        creature = creature,
        path = nil,
        pathTime = 0,
        lastUpdate = now
      }
      table.insert(snapshotCreatures, { id = id, pos = creature:getPosition(), creature = creature })
      monsterCache.monsterCount = monsterCache.monsterCount + 1
    end
  end
  monsterCache.lastFullUpdate = now
  monsterCache.dirty = false
  monsterCache.primeSnapshot = { ts = now, pos = pos, creatures = snapshotCreatures }
end

-- Schedule multiple retries with exponential backoff to cover different load timings
schedule(20, performPendingEnableOnce)
schedule(200, function() if not performPendingEnableOnce() then end end)
schedule(600, function() if not performPendingEnableOnce() then end end)
schedule(1600, function() if not performPendingEnableOnce() then warn('[TargetBot] post-init: deferred enable attempts exhausted') end end)

-- Module load diagnostics: print whether key functions are available shortly after load
-- Module init check (silent): mark module as initialized after a short delay and attempt pending enable
schedule(1500, function()
  moduleInitialized = true
  pcall(function() performPendingEnableOnce() end)
  -- Startup sanity log to confirm TargetBot module loaded
  -- warn("[TargetBot] module initialized. TargetBot._removed=" .. tostring(TargetBot and TargetBot._removed) .. ", TargetBot.isOn=" .. tostring(TargetBot and TargetBot.isOn and TargetBot.isOn()))
end)

-- Follow player integration state (used by target_events.lua EventBus handlers)
local followPlayerForceMode = false
local followPlayerForceExpiry = 0

TargetBot.isForceFollowActive = function()
  if not followPlayerForceMode then return false end
  if now > followPlayerForceExpiry then
    followPlayerForceMode = false
    return false
  end
  return true
end

TargetBot.clearForceFollow = function()
  followPlayerForceMode = false
  followPlayerForceExpiry = 0
end

-- Active movement config (set by creature_attack when processing targets)
TargetBot.ActiveMovementConfig = TargetBot.ActiveMovementConfig or {
  chase = false,
  keepDistance = false,
  keepDistanceRange = 4,
  finishKillThreshold = 30,
  anchor = nil,
  anchorRange = 5
}

local function executeIntelligenceSelection(selection, targetCount, source)
  local Intelligence = nExBot and nExBot.Intelligence
  if not Intelligence or not TargetProposal then return false end
  local proposal = TargetProposal.fromSelection(selection, {
    now = now,
    generations = Intelligence.lifecycle.generations,
  })
  if not proposal then return false end
  Intelligence.applyContextAdjustment(proposal, selection)
  Intelligence.activeCombatContext = proposal.contextKey
  proposal.source = source or proposal.source
  Intelligence.events:publish("TargetCandidateEvaluated", proposal, { source = proposal.source })
  local maxHealth = player and player.getMaxHealth and player:getMaxHealth() or 0
  local selected, rejected = Intelligence.decisions:select({ proposal }, Intelligence.lifecycle.generations, {
    healthRatio = maxHealth > 0 and player:getHealth() / maxHealth or 0,
    targetValid = selection.creature and not selection.creature:isDead(),
  })
  local features = Intelligence.features:extractCombat(Intelligence.currentSnapshot, { targetId = proposal.targetId })
  features.predictions = { targetUtility = Intelligence.models:predict("TargetUtilityModel", features) }
  if not Intelligence.optionalEnabled or Intelligence.optionalEnabled("replay") then
    Intelligence.replay:record({
      snapshotRef = Intelligence.currentSnapshot and Intelligence.currentSnapshot.generation,
      features = features,
      proposals = { proposal },
      selected = selected,
      rejected = rejected,
    })
  end
  if not selected then
    Intelligence.events:publish("TargetRejected", { proposal = proposal, rejected = rejected }, { source = "IntelligenceDecisionEngine" })
    return false
  end
  Intelligence.events:publish("TargetSelected", selected, { source = "IntelligenceDecisionEngine" })
  TargetBot.Creature.attack(selection, targetCount, false)
  return true
end
TargetBot.submitSelection = executeIntelligenceSelection

-- Main TargetBot loop - optimized with EventBus caching
-- PERFORMANCE: 250ms macro interval balances responsiveness and CPU usage
local lastRecalcTime = 0
local RECALC_COOLDOWN_MS = 150  -- PERFORMANCE: Increased from 100ms
local lastPathCacheCleanup = 0
targetbotMacro = macro(250, function()
  local _msStart = os.clock()
  
  if not config or not config.isOn or not config.isOn() then
    return
  end

  -- Z-change guard: pause target processing during floor transitions
  if zChanging() then
    return
  end
  
  -- CRITICAL: Respect explicit disable flag - user turned it off manually
  if TargetBot and TargetBot.explicitlyDisabled then
    return
  end

  -- Update AttackStateMachine (only when TargetBot is ON)
  if AttackStateMachine and AttackStateMachine.update then
    pcall(AttackStateMachine.update)
  end

  -- Prevent execution before login is complete to avoid freezing
  local Client = getClient()
  local isOnline = (Client and Client.isOnline) and Client.isOnline() or (g_game and g_game.isOnline and g_game.isOnline())
  if not isOnline then return end

  -- TargetBot never triggers friend-heal; keep that path dormant to save cycles
  if HealEngine and HealEngine.setFriendHealingEnabled then
    HealEngine.setFriendHealingEnabled(false)
  end
  
  -- FAST PATH: If EventTargeting already has a valid target, use it
  -- This skips the expensive recalculation when event-driven targeting is handling things
  -- BUT we still need to run the walk/positioning logic for features like:
  -- avoidAttacks, keepDistance, dynamicLure, smartPull, etc.
  if EventTargeting and EventTargeting.isInCombat and EventTargeting.isInCombat() then
    local eventTarget = EventTargeting.getCurrentTarget and EventTargeting.getCurrentTarget()
    if eventTarget and not eventTarget:isDead() then
      -- EventTargeting is handling combat - ensure we're attacking AND chase mode is set
      -- CRITICAL: Chase is only active if enabled AND keepDistance is disabled
      local chaseEnabled = TargetBot.ActiveMovementConfig and TargetBot.ActiveMovementConfig.chase
      local keepDistanceEnabled = TargetBot.ActiveMovementConfig and TargetBot.ActiveMovementConfig.keepDistance
      local useNativeChase = chaseEnabled and not keepDistanceEnabled
      
      MovementCoordinator.setChaseMode(useNativeChase)
      
      -- CRITICAL FIX: Still run creature_attack logic for movement features
      -- (avoidAttacks, keepDistance, dynamicLure, smartPull, rePosition, etc.)
      -- Get configs for this creature and build params
      local configs = TargetBot.Creature.getConfigs and TargetBot.Creature.getConfigs(eventTarget)
      if configs and #configs > 0 then
        local config = configs[1]  -- Use first matching config
        local targetCount = monsterCache.monsterCount or 1
        local params = {
          config = config,
          creature = eventTarget,
          danger = config.danger or 0,
          priority = config.priority or 1
        }
        -- Update MonsterAI target lock for anti-zigzag stability
        if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.lockTarget then
          local okId, id = pcall(function() return eventTarget:getId() end)
          local okHp, hp = pcall(function() return eventTarget:getHealthPercent() end)
          if okId and id then
            MonsterAI.Scenario.lockTarget(id, okHp and hp or 100)
          end
        end
        -- Run the full attack/walk logic with proper config
        pcall(executeIntelligenceSelection, params, targetCount, "EventTargeting")
      end
      
      setStatusRight("Targeting (Event)")
      lastAction = now
      return
    end
  end

  local pos = player:getPosition()
  if not pos then return end
  
  -- Periodic cache cleanup
  cleanupCache()
  targetPathfinding.cleanupPathCache()
  
  -- Handle walking if destination is set (safety check for load order)
  if TargetBot.walk then
    TargetBot.walk()
  end
  
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

    local Client_g = getClient()
    local currentAttack_g = ClientService.getAttackingCreature()
    if currentAttack_g and not currentAttack_g:isDead() and (now - lastEngagementAt) < 1500 then
      bestTarget = monsterCache.bestTarget
      targetCount = monsterCache.monsterCount or 0
      totalDanger = monsterCache.totalDanger or 0
    -- If cache is clean and recent and we recalculated very recently, use cached values to avoid heavy work
    elseif not monsterCache.dirty and (now - (monsterCache.lastFullUpdate or 0)) < (monsterCache.FULL_UPDATE_INTERVAL or 400) and (now - lastRecalcTime) < RECALC_COOLDOWN_MS then
      bestTarget = monsterCache.bestTarget
      targetCount = 0
      totalDanger = monsterCache.totalDanger or 0
    else
      lastRecalcTime = now
      bestTarget, targetCount, totalDanger = recalculateBestTarget()
    end

  -- MonsterAI scenario integration: prefer scenario optimal target when allowed
  local Client = getClient()
  local currentAttack = ClientService.getAttackingCreature()
  if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.getOptimalTarget then
    local optimal = MonsterAI.Scenario.getOptimalTarget()
    if optimal and optimal.creature and not optimal.creature:isDead() then
      local okPos, cpos = pcall(function() return optimal.creature:getPosition() end)
      if okPos and cpos and cpos.z == pos.z then
        local isCurrent = currentAttack and currentAttack:getId() == optimal.id
        local params, path = processCandidate(optimal.creature, pos, isCurrent)
        if params and params.config then
          local okSwitch = true
          if MonsterAI.Scenario.shouldAllowTargetSwitch and currentAttack and not isCurrent then
            local okHp, hp = pcall(function() return optimal.creature:getHealthPercent() end)
            okSwitch = MonsterAI.Scenario.shouldAllowTargetSwitch(optimal.id, params.priority or 100, okHp and hp or 100)
          end
          if okSwitch then
            bestTarget = params
          end
        end
      end
    end
  end
  
  -- IMPROVED: Get live monster count from EventTargeting (most accurate)
  local liveMonsterCount = 0
  if EventTargeting and EventTargeting.getLiveMonsterCount then
    liveMonsterCount = EventTargeting.getLiveMonsterCount()
  else
    liveMonsterCount = monsterCache.monsterCount or 0
  end

  if not bestTarget then
    setWidgetTextSafe(ui.target.right, "-")
    setWidgetTextSafe(ui.danger.right, "0")
    setWidgetTextSafe(ui.config.right, "-")
    dangerValue = 0
    
    -- FIXED: Check for unreachable creatures (blocked paths)
    -- If there are only unreachable creatures, allow CaveBot to proceed immediately
    local unreachableCount = monsterCache.unreachableCount or 0
    local reachableOnScreen = monsterCache.monsterCount or 0
    
    -- intelligence.0: Also check AttackStateMachine for skipped creatures
    local smSkippedCount = 0
    if AttackStateMachine and AttackStateMachine.getSkippedCount then
      smSkippedCount = AttackStateMachine.getSkippedCount()
    end
    local totalBlocked = unreachableCount + smSkippedCount
    
    -- Check if there are REACHABLE monsters on screen
    if reachableOnScreen > 0 and reachableOnScreen > smSkippedCount then
      -- There are reachable monsters but no valid target (edge case)
      setStatusRight("Targeting (" .. tostring(reachableOnScreen) .. ")")
      if EventTargeting and EventTargeting.refreshLiveCount then
        EventTargeting.refreshLiveCount()
      end
      invalidateCache()
      cavebotAllowance = now + 300
      return
    elseif totalBlocked > 0 then
      -- All creatures have blocked paths - allow CaveBot to proceed
      -- Don't waste time trying to attack creatures we can't reach
      setStatusRight("Blocked (" .. tostring(totalBlocked) .. ")")
      cavebotAllowance = now + 100  -- Allow CaveBot immediately
      
      -- Emit event for CaveBot to know it can proceed
      if EventBus and EventBus.emit then
        pcall(function()
          EventBus.emit("targetbot/all_blocked", totalBlocked)
        end)
      end
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

    -- Update MonsterAI target lock for anti-zigzag stability
    if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.lockTarget then
      local okId, id = pcall(function() return bestTarget.creature:getId() end)
      local okHp, hp = pcall(function() return bestTarget.creature:getHealthPercent() end)
      if okId and id then
        MonsterAI.Scenario.lockTarget(id, okHp and hp or 100)
      end
    end

    -- ═══════════════════════════════════════════════════════════════════════════
    -- LINEAR ATTACK SYSTEM: AttackStateMachine handles all attack persistence
    -- Ensures continuous attacking of same target until death - no fallbacks
    -- ═══════════════════════════════════════════════════════════════════════════
    local nowt = now or (os.time() * 1000)
    local okId, id = pcall(function() return bestTarget.creature:getId() end)
    
    if okId and id then
      local smState = AttackStateMachine.getState()

      -- Update AttackController based on state machine status
      if smState == "LOCKED" then
        AttackController.attackState = "confirmed"
        AttackController.lastConfirmedTime = nowt
        AttackController.lastTargetId = id
      elseif smState == "ENGAGING" then
        AttackController.attackState = "pending"
        AttackController.lastCommandTime = nowt
        AttackController.lastTargetId = id
      end
    end

    -- Delegate to unified attack/walk logic from creature_attack
    -- This ensures chase, positioning, avoidance and AttackBot integration run correctly
    -- DynamicLure/SmartPull will call allowCaveBot() if lure conditions are met
    pcall(executeIntelligenceSelection, bestTarget, targetCount, "TargetBot")
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
  -- Track if this callback was triggered by user clicking the switch
  -- The 'enabled' parameter comes from the UI switch state
  local isUserToggle = (TargetBot._initialized == true)  -- After init, changes are user-driven
  
  -- Save character's profile preference when profile changes (multi-client support)
  if enabled and name and name ~= "" then
    if setCharacterProfile then
      setCharacterProfile("targetbotProfile", name)
    end
    -- Persist to UnifiedStorage for character isolation
    if UnifiedStorage then
      UnifiedStorage.set("targetbot.selectedConfig", name)
    end
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

  -- Determine final enabled state (check UnifiedStorage first for character isolation)
  -- PRIORITY: stored enabled state ALWAYS takes precedence over config file's enabled state
  local finalEnabled = enabled
  local storedEnabled = (UnifiedStorage and UnifiedStorage.get("targetbot.enabled"))
  if storedEnabled == nil then
    storedEnabled = storage.targetbotEnabled
  end
  
  -- If user explicitly set an enabled state (true or false), always respect it
  if storedEnabled == true or storedEnabled == false then
    finalEnabled = storedEnabled
  end
  
  -- Track that we've initialized (for other purposes)
  if not TargetBot._initialized then
    TargetBot._initialized = true
  end

  -- v2.4: Handle user-initiated toggle via the UI switch
  -- If user clicked the switch AFTER init, update explicitlyDisabled accordingly
  if isUserToggle then
    if enabled == false then
      -- User clicked to disable - set explicitlyDisabled
      TargetBot.explicitlyDisabled = true
      TargetBot._lastUserToggle = now or os.time() * 1000
      finalEnabled = false
      -- v2.5: Persist explicitlyDisabled flag to storage
      if UnifiedStorage then 
        UnifiedStorage.set("targetbot.enabled", false)
        UnifiedStorage.set("targetbot.explicitlyDisabled", true)
      else 
        storage.targetbotEnabled = false 
      end
      storage.targetbotExplicitlyDisabled = true
    elseif enabled == true then
      -- User clicked to enable - clear explicitlyDisabled
      TargetBot.explicitlyDisabled = false
      TargetBot._lastUserToggle = now or os.time() * 1000
      finalEnabled = true
      -- v2.5: Persist explicitlyDisabled flag to storage
      if UnifiedStorage then 
        UnifiedStorage.set("targetbot.enabled", true)
        UnifiedStorage.set("targetbot.explicitlyDisabled", false)
      else 
        storage.targetbotEnabled = true 
      end
      storage.targetbotExplicitlyDisabled = false
    end
  else
    -- Not user-initiated - respect explicitlyDisabled flag
    if TargetBot.explicitlyDisabled then
      finalEnabled = false
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
  if clearWalk then
    TargetBot.clearWalk()
  end
  -- OTClient has a built-in autoAttackTarget() that toggles attack
  -- Calling it when attacking will stop the attack
  if autoAttackTarget then
    autoAttackTarget(nil)
  end
end

local function removeCreatureFromCache(creature)
  if not creature then return end
  local id = creature:getId() or tostring(creature)
  if monsterCache.monsters[id] then
    monsterCache.monsters[id] = nil
    monsterCache.monsterCount = monsterCache.monsterCount - 1
    local idx = monsterCache.posMap[id]
    if idx then
      local order = monsterCache.accessOrder
      local last = #order
      if idx ~= last then
        local movedId = order[last]
        order[idx] = movedId
        monsterCache.posMap[movedId] = idx
      end
      order[last] = nil
      monsterCache.posMap[id] = nil
    end
    invalidateCache()
  end
end

-- Note: Profile restoration is handled early in configs.lua
-- before Config.setup() is called, so the dropdown loads correctly

TargetBot.isOff = function()
  return not TargetBot or not TargetBot.isOn or not TargetBot.isOn()
end

-- Export internals for target_events.lua cross-module access
TargetBot.__internals = {
  invalidateCache = invalidateCache,
  clearPaths = clearPaths,
  recalculateBestTarget = recalculateBestTarget,
  getMonsterCount = function() return monsterCache.monsterCount or 0 end,
  debouncedInvalidateAndRecalc = debouncedInvalidateAndRecalc,
  updateCreatureInCache = updateCreatureInCache,
  removeCreatureFromCache = removeCreatureFromCache,
  attackWatchdog = attackWatchdog,
  reloginRecovery = reloginRecovery,
  ui = ui,
  setStatusRight = setStatusRight,
  targetbotMacro = targetbotMacro,
  setAllowance = function(v) cavebotAllowance = v end,
  followPlayerForceMode = false,
  followPlayerForceExpiry = 0
}

-- End of TargetBot module
