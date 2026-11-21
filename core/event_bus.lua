--[[
  nExBot Event Bus
  
  Centralized event handling system following the Observer pattern.
  Reduces polling overhead by allowing modules to subscribe to specific events
  rather than running continuous macro loops.
  
  Principles:
  - Single Responsibility: Only handles event subscription and dispatch
  - Open/Closed: New events can be added without modifying existing code
  - DRY: Single registration point for all OTClient callbacks
  
  Usage:
    EventBus.on("creature:appear", function(creature) ... end)
    EventBus.on("player:move", function(oldPos, newPos) ... end)
    EventBus.emit("custom:event", data)
]]

EventBus = {}

-- Compatibility shim: Ensure table.unpack exists (Lua 5.1 fallback)
if not table.unpack and unpack then
  table.unpack = unpack
end

-- Private state
local listeners = {}
-- Ring buffer queue for events (head/tail indices) to avoid O(n) table.remove
local eventQueue = { head = 1, tail = 0 }
local processing = false
local FLUSH_BATCH = 100 -- max events processed per flush to avoid blocking

-- Z-change and tile burst guards: extracted to core/zchange_guard.lua
-- Loaded in Phase 6 before event_bus.lua
local ZChangeGuard = ZChangeGuard or {}

-- Local aliases for performance (avoid repeated table lookups)
local _zBurst = ZChangeGuard.checkBurst or function() return false end
local _zSet = ZChangeGuard.onZChange or function() end
local _tileBurst = ZChangeGuard.checkTileBurst or function() return false end
local nowMs = nExBot.Shared.nowMs

-- Subscribe to an event
-- @param event string: Event name (e.g., "creature:appear", "player:move")
-- @param callback function: Handler function
-- @param priority number: Optional priority (higher = called first)
-- @return function: Unsubscribe function
function EventBus.on(event, callback, priority)
  priority = priority or 0
  
  if not listeners[event] then
    listeners[event] = {}
  end
  
  local entry = {
    callback = callback,
    priority = priority
  }
  
  table.insert(listeners[event], entry)
  
  -- Sort by priority (descending)
  table.sort(listeners[event], function(a, b)
    return a.priority > b.priority
  end)
  
  -- Return unsubscribe function
  return function()
    for i, e in ipairs(listeners[event] or {}) do
      if e == entry then
        table.remove(listeners[event], i)
        break
      end
    end
  end
end

function EventBus.listenerCount(event)
  if event then return #(listeners[event] or {}) end
  local count = 0
  for _, entries in pairs(listeners) do count = count + #entries end
  return count
end

-- Emit an event to all subscribers
-- @param event string: Event name
-- @param ... any: Arguments to pass to handlers
function EventBus.emit(event, ...)
  local handlers = listeners[event]
  if not handlers then return end

  for i = 1, #handlers do
    local handler = handlers[i]
    local status, err = pcall(handler.callback, ...)
    if not status then
      warn("[EventBus] Error in handler for '" .. event .. "': " .. tostring(err))
    end
  end
end

-- Queue an event for deferred processing (useful for batching)
-- @param event string: Event name
-- @param ... any: Arguments to pass to handlers
function EventBus.queue(event, ...)
  -- Push to ring buffer queue
  eventQueue.tail = eventQueue.tail + 1
  eventQueue[eventQueue.tail] = { event = event, args = {...} }
  -- Telemetry

  -- Trim if backlog becomes excessive
  local size = math.max(0, eventQueue.tail - eventQueue.head + 1)
  if size > 2000 then
    local drop = math.floor(size / 2)
    for i = 1, drop do
      eventQueue[eventQueue.head] = nil
      eventQueue.head = eventQueue.head + 1
    end
    warn("[EventBus] High event backlog, dropped " .. tostring(drop) .. " oldest events")
  end
end

-- Process all queued events
function EventBus.flush()
  if processing then return end
  processing = true

  local processed = 0
  while processed < FLUSH_BATCH and eventQueue.head <= eventQueue.tail do
    local item = eventQueue[eventQueue.head]
    eventQueue[eventQueue.head] = nil
    eventQueue.head = eventQueue.head + 1
    if item then
      EventBus.emit(item.event, table.unpack(item.args))
    end
    processed = processed + 1
  end

  -- Compact ring buffer indices to prevent integer overflow over long sessions
  if eventQueue.head > 10000 and eventQueue.head > eventQueue.tail then
    eventQueue.head = 1
    eventQueue.tail = 0
  end

  processing = false
end

-- Get number of queued events currently waiting to be processed
-- OTClient Native Event Registration
-- Register once, dispatch through EventBus

-- Creature events
-- Throttle monster:appear events — 10 subscribers, expensive per-monster allocation
local _monsterAppearThrottle = {}
local MONSTER_APPEAR_THROTTLE_MS = 300

if onCreatureAppear then
  onCreatureAppear(function(creature)
    if _zBurst() then return end
    if creature:isMonster() then
      local cId = nil
      pcall(function() cId = creature:getId() end)
      local nowMs3 = nowMs()
      if not cId or not _monsterAppearThrottle[cId] or (nowMs3 - _monsterAppearThrottle[cId]) >= MONSTER_APPEAR_THROTTLE_MS then
        if cId then _monsterAppearThrottle[cId] = nowMs3 end
        EventBus.emit("monster:appear", creature)
      end
    elseif creature:isPlayer() then
      EventBus.emit("player:appear", creature)
    elseif creature:isNpc() then
      EventBus.emit("npc:appear", creature)
    end
    EventBus.emit("creature:appear", creature)
  end)
end

if onCreatureDisappear then
  onCreatureDisappear(function(creature)
    if _zBurst() then return end
    if creature:isMonster() then
      EventBus.emit("monster:disappear", creature)
    elseif creature:isPlayer() then
      EventBus.emit("player:disappear", creature)
    end
    EventBus.emit("creature:disappear", creature)
  end)
end

-- Track creature health for detecting changes and kills
local creatureHealthCache = {}
setmetatable(creatureHealthCache, { __mode = "k" }) -- Weak keys for auto-cleanup

-- Throttle monster:health events — too many subscribers, too frequent
local _monsterHealthThrottle = {}  -- { [creatureId] = lastEmitTime }
local MONSTER_HEALTH_THROTTLE_MS = 150  -- 150ms between emits per creature

-- Kill tracking: extracted to core/kill_tracker.lua
local KillTracker = KillTracker or {}

-- Clean up old throttle tables periodically
local _cleanupCounter = 0
local _creatureMoveLastEmit = {}
local function cleanupThrottleTables()
  local nowt = nowMs()
  -- Prune throttle tables every ~10 calls (every ~5s at 500ms interval)
  _cleanupCounter = _cleanupCounter + 1
  if _cleanupCounter >= 10 then
    _cleanupCounter = 0
    for id, t in pairs(_monsterHealthThrottle) do
      if (nowt - t) > 5000 then _monsterHealthThrottle[id] = nil end
    end
    for id, t in pairs(_monsterAppearThrottle) do
      if (nowt - t) > 5000 then _monsterAppearThrottle[id] = nil end
    end
    for id, t in pairs(_creatureMoveLastEmit) do
      if (nowt - t) > 5000 then _creatureMoveLastEmit[id] = nil end
    end
  end
end

if onCreatureHealthPercentChange then
  onCreatureHealthPercentChange(function(creature, percent)
    if _zBurst() then return end
    -- Get cached old HP (default to 100 if not tracked)
    local oldPercent = creatureHealthCache[creature] or 100
    creatureHealthCache[creature] = percent

    local nowMs2 = nowMs()

    -- Always emit creature:health (used by creature_cache, exeta, friend_healer — lightweight)
    EventBus.emit("creature:health", creature, percent, oldPercent)

    if creature:isMonster() then
      -- Throttle monster:health — 9 subscribers, expensive work
      local cId = nil
      pcall(function() cId = creature:getId() end)
      local isKill = percent <= 0 and oldPercent > 0
      if isKill or not cId or not _monsterHealthThrottle[cId] or (nowMs2 - _monsterHealthThrottle[cId]) >= MONSTER_HEALTH_THROTTLE_MS then
        if cId then _monsterHealthThrottle[cId] = nowMs2 end
        EventBus.emit("monster:health", creature, percent, oldPercent)
      end

      -- MONSTER KILLED: Detect when health drops to 0
      if isKill then
        local creatureId = nil
        local creatureName = nil
        local creaturePos = nil
        
        pcall(function() creatureId = creature:getId() end)
        pcall(function() creatureName = creature:getName() end)
        pcall(function() creaturePos = creature:getPosition() end)
        
        if creatureId and creaturePos then
          -- Delegate to KillTracker (domain logic)
          if KillTracker.recordKill then
            KillTracker.recordKill(creatureId, creatureName, creaturePos)
          end
          
          -- Emit monster:killed event with full info
          EventBus.emit("monster:killed", creature, creaturePos, creatureName)
        end
        
        -- Cleanup old entries periodically
        if KillTracker.cleanup then
          KillTracker.cleanup()
        end
      end
      
    elseif creature:isPlayer() and not creature:isLocalPlayer() then
      -- Emit dedicated friend/player health event for FriendHealer
      EventBus.emit("friend:health", creature, percent, oldPercent)
      
      -- Detect player death (for party members)
      if percent <= 0 and oldPercent > 0 then
        EventBus.emit("player:killed", creature)
      end
    end
  end)
end

-- Player events
local _playerMoveLastEmit = 0
local PLAYER_MOVE_THROTTLE_MS = 80  -- Don't emit more than 12x/sec
local _zCooldown = (ZChangeGuard and ZChangeGuard.zCooldownMs) or 150
if onPlayerPositionChange then
  onPlayerPositionChange(function(newPos, oldPos)
    if newPos and oldPos and newPos.z ~= oldPos.z then
      _zSet(oldPos, newPos)
      EventBus.emit("player:z_change", newPos, oldPos)
      schedule(_zCooldown + 50, function()
        EventBus.emit("player:z_change_settled", newPos, oldPos)
      end)
    end
    local nowMs4 = nowMs()
    if (nowMs4 - _playerMoveLastEmit) >= PLAYER_MOVE_THROTTLE_MS then
      _playerMoveLastEmit = nowMs4
      EventBus.emit("player:move", newPos, oldPos)
    end
  end)
end

if onManaChange then
  onManaChange(function(localPlayer, mana, maxMana, oldMana, oldMaxMana)
    EventBus.emit("player:mana", mana, maxMana, oldMana, oldMaxMana)
  end)
end

-- Damage attribution state (debounced to max 4x/sec)
local _damageAttrLastRun = 0
local _damageAttrMinInterval = 250
local _damageAttrCachedCreatures = nil
local _damageAttrCacheTime = 0
local _damageAttrCacheTTL = 200

local function attributeDamageSource(damage)
  local playerPos = nil
  local ok, lp = pcall(function() return g_game and g_game.getLocalPlayer and g_game.getLocalPlayer() end)
  if ok and lp then pcall(function() playerPos = lp:getPosition() end) end
  if not playerPos then
    EventBus.emit("player:damage", damage, nil)
    return
  end

  -- Skip heavy MonsterAI scoring when collection is disabled
  local useAI = MonsterAI and MonsterAI.COLLECT_ENABLED

  local radius = (useAI and MonsterAI.CONSTANTS and MonsterAI.CONSTANTS.DAMAGE and MonsterAI.CONSTANTS.DAMAGE.CORRELATION_RADIUS) or 7
  local threshold = (useAI and MonsterAI.CONSTANTS and MonsterAI.CONSTANTS.DAMAGE and MonsterAI.CONSTANTS.DAMAGE.CORRELATION_THRESHOLD) or 0.4

  -- Cache spectator list for 200ms to avoid repeated API calls
  local nowt = nowMs()
  if not _damageAttrCachedCreatures or (nowt - _damageAttrCacheTime) > _damageAttrCacheTTL then
    if BotCore and BotCore.Creatures and BotCore.Creatures.getNearby then
      _damageAttrCachedCreatures = BotCore.Creatures.getNearby(radius) or {}
    else
      _damageAttrCachedCreatures = {}
    end
    _damageAttrCacheTime = nowt
  end

  local creatures = _damageAttrCachedCreatures
  if not creatures then
    EventBus.emit("player:damage", damage, nil)
    return
  end

  local bestMonster, bestScore = nil, 0
  for i = 1, #creatures do
    local m = creatures[i]
    local okm, isValid = pcall(function() return m and m:isMonster() and not m:isDead() end)
    if okm and isValid then
      local mpos
      pcall(function() mpos = m:getPosition() end)
      if mpos then
        local dist = math.max(math.abs(playerPos.x - mpos.x), math.abs(playerPos.y - mpos.y))
        local score = 1 / (1 + dist)

        -- Only do expensive MonsterAI scoring when AI collection is active
        if useAI then
          local okid, mid = pcall(function() return m:getId() end)
          if okid and mid and MonsterAI.Tracker and MonsterAI.Tracker.monsters then
            local data = MonsterAI.Tracker.monsters[mid]
            if data then
              if data.lastWaveTime and math.abs(nowt - data.lastWaveTime) < 800 then score = score + 1.2 end
              if data.lastAttackTime and math.abs(nowt - data.lastAttackTime) < 1500 then score = score + 0.8 end
            end
          end
          if MonsterAI.Predictor and MonsterAI.Predictor.isFacingPosition then
            local okf, facing = pcall(function() return MonsterAI.Predictor.isFacingPosition(mpos, m:getDirection(), playerPos) end)
            if okf and facing then score = score + 0.6 end
          end
        end

        if score > bestScore then bestScore = score; bestMonster = m end
      end
    end
  end

  EventBus.emit("player:damage", damage, bestScore >= threshold and bestMonster or nil)
end

if onHealthChange then
  onHealthChange(function(localPlayer, health, maxHealth, oldHealth, oldMaxHealth)
    EventBus.emit("player:health", health, maxHealth, oldHealth, oldMaxHealth)

    if oldHealth and health and oldHealth > health then
      local damage = oldHealth - health
      -- Debounce: max 4 attributions per second to prevent CPU spikes
      local nowt = nowMs()
      if (nowt - _damageAttrLastRun) >= _damageAttrMinInterval then
        _damageAttrLastRun = nowt
        attributeDamageSource(damage)
      else
        -- Fast path: emit damage without attribution
        EventBus.emit("player:damage", damage, nil)
      end
    end
  end)
end

-- Container events
if onContainerOpen then
  onContainerOpen(function(container, previousContainer)
    EventBus.emit("container:open", container, previousContainer)
  end)
end

if onContainerClose then
  onContainerClose(function(container)
    EventBus.emit("container:close", container)
  end)
end

if onContainerUpdateItem then
  onContainerUpdateItem(function(container, slot, item, oldItem)
    EventBus.emit("container:update", container, slot, item, oldItem)
  end)
end

-- Combat events
if onAttackingCreatureChange then
  onAttackingCreatureChange(function(creature, oldCreature)
    EventBus.emit("combat:target", creature, oldCreature)
  end)
end

-- Text/Message events
if onTextMessage then
  onTextMessage(function(mode, text)
    EventBus.emit("message:text", mode, text)
  end)
end

if onTalk then
  onTalk(function(name, level, mode, text, channelId, pos)
    EventBus.emit("message:talk", name, level, mode, text, channelId, pos)
  end)
end

-- Tile events (filtered to items only — creature movement is handled by creature events)
-- Guarded by both z-change block AND tile-burst throttle to prevent city freezes.
if onAddThing then
  onAddThing(function(tile, thing)
    if _zBurst() then return end
    if _tileBurst() then return end
    if thing and thing.isItem and thing:isItem() then
      EventBus.emit("tile:add", tile, thing)
    end
  end)
end

if onRemoveThing then
  onRemoveThing(function(tile, thing)
    if _zBurst() then return end
    if _tileBurst() then return end
    if thing and thing.isItem and thing:isItem() then
      EventBus.emit("tile:remove", tile, thing)
    end
  end)
end

-- Equipment change tracking
-- Monitors player equipment slots and emits events when items change
local lastEquipment = {}
local EQUIPMENT_SLOTS = {
  [1] = "head",
  [2] = "neck",
  [3] = "back",
  [4] = "body",
  [5] = "right",  -- Right hand (shield/quiver)
  [6] = "left",   -- Left hand (weapon)
  [7] = "legs",
  [8] = "feet",
  [9] = "finger",
  [10] = "ammo"
}

-- Check if equipment changed
local function checkEquipmentChanges()
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end
  
  for slotId, slotName in pairs(EQUIPMENT_SLOTS) do
    local item = localPlayer:getInventoryItem(slotId)
    local currentId = item and item:getId() or 0
    local lastId = lastEquipment[slotId] or 0
    
    if currentId ~= lastId then
      lastEquipment[slotId] = currentId
      
      -- Emit specific slot change event
      EventBus.emit("equipment:" .. slotName, currentId, lastId, item)
      
      -- Emit generic equipment change event
      EventBus.emit("equipment:change", slotId, slotName, currentId, lastId, item)
      
      -- Emit weapon-specific events for quiver manager
      if slotId == 6 then -- Left hand (weapon)
        EventBus.emit("equipment:weapon", currentId, lastId, item)
      elseif slotId == 5 then -- Right hand (shield/quiver)
        EventBus.emit("equipment:shield", currentId, lastId, item)
      end
    end
  end
end

-- UNIFIED TICK INTEGRATION
-- Migrate polling macros to UnifiedTick for consolidated tick management

if UnifiedTick and UnifiedTick.register then
  -- Equipment check handler (200ms, LOW priority - UI updates)
  UnifiedTick.register("eventbus_equipment_check", {
    interval = 200,
    priority = UnifiedTick.Priority.LOW,
    handler = checkEquipmentChanges,
    group = "eventbus"
  })
  
  -- Event flush handler (50ms, NORMAL priority - event processing)
  -- Note: Running at 50ms instead of 25ms to match UnifiedTick master interval
  UnifiedTick.register("eventbus_flush", {
    interval = 50,
    priority = UnifiedTick.Priority.NORMAL,
    handler = function()
      EventBus.flush()
    end,
    group = "eventbus"
  })
  
  -- Slow tick handler (5000ms, IDLE priority - cleanup tasks)
  UnifiedTick.register("eventbus_slow_tick", {
    interval = 5000,
    priority = UnifiedTick.Priority.IDLE,
    handler = function()
      EventBus.emit("tick:slow")
      cleanupThrottleTables()
    end,
    group = "eventbus"
  })
else
  -- Fallback to standalone macros if UnifiedTick not available
  macro(200, function()
    checkEquipmentChanges()
  end)
  
  macro(25, function()
    EventBus.flush()
  end)
  
  macro(5000, function()
    EventBus.emit("tick:slow")
    cleanupThrottleTables()
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EXTENDED OTCLIENT API EVENTS
-- More comprehensive event coverage for smooth integration
-- ═══════════════════════════════════════════════════════════════════════════

-- Spell cooldown events
if onSpellCooldown then
  onSpellCooldown(function(iconId, duration)
    EventBus.emit("spell:cooldown", iconId, duration)
  end)
end

if onGroupSpellCooldown then
  onGroupSpellCooldown(function(iconId, duration)
    EventBus.emit("spell:groupCooldown", iconId, duration)
  end)
end

-- Creature walk events
local CREATURE_MOVE_THROTTLE_MS = 100
if onWalk then
  onWalk(function(creature, oldPos, newPos)
    if _zBurst() then return end
    EventBus.emit("creature:walk", creature, oldPos, newPos)
    -- Throttle creature:move — 14 subscribers, fires every walk step
    local cId = nil
    pcall(function() cId = creature:getId() end)
    local nowMs5 = nowMs()
    if not cId or not _creatureMoveLastEmit[cId] or (nowMs5 - _creatureMoveLastEmit[cId]) >= CREATURE_MOVE_THROTTLE_MS then
      if cId then _creatureMoveLastEmit[cId] = nowMs5 end
      EventBus.emit("creature:move", creature, oldPos)
    elseif cId then
      _creatureMovePending = _creatureMovePending or {}
      _creatureMovePending[cId] = {creature = creature, oldPos = oldPos}
      schedule(CREATURE_MOVE_THROTTLE_MS, function()
        local pending = _creatureMovePending and _creatureMovePending[cId]
        if pending then
          _creatureMovePending[cId] = nil
          _creatureMoveLastEmit[cId] = now or (os.time() * 1000)
          EventBus.emit("creature:move", pending.creature, pending.oldPos)
        end
      end)
    end
    if creature:isMonster() then
      EventBus.emit("monster:walk", creature, oldPos, newPos)
    elseif creature:isPlayer() then
      EventBus.emit("player:walk", creature, oldPos, newPos)
    end
  end)
end

-- Creature turn events
if onTurn then
  onTurn(function(creature, direction)
    if _zBurst() then return end
    EventBus.emit("creature:turn", creature, direction)
  end)
end

-- Missile (projectile) events
if onMissle then
  onMissle(function(missile)
    EventBus.emit("effect:missile", missile)
  end)
end

-- Animated text events (damage numbers, healing, etc.)
if onAnimatedText then
  onAnimatedText(function(thing, text)
    EventBus.emit("effect:animatedText", thing, text)
  end)
end

-- Static text events (creature speech bubbles)
if onStaticText then
  onStaticText(function(thing, text)
    EventBus.emit("effect:staticText", thing, text)
  end)
end

-- Use item events
if onUse then
  onUse(function(pos, itemId, stackPos, subType)
    EventBus.emit("item:use", pos, itemId, stackPos, subType)
  end)
end

if onUseWith then
  onUseWith(function(pos, itemId, target, subType)
    EventBus.emit("item:useWith", pos, itemId, target, subType)
  end)
end

-- Container item events
if onAddItem then
  onAddItem(function(container, slot, item)
    EventBus.emit("container:addItem", container, slot, item)
  end)
end

if onRemoveItem then
  onRemoveItem(function(container, slot, item)
    EventBus.emit("container:removeItem", container, slot, item)
  end)
end

-- Inventory change events
if onInventoryChange then
  onInventoryChange(function(player, slot, item, oldItem)
    EventBus.emit("inventory:change", player, slot, item, oldItem)
  end)
end

-- Player state change events (buffs, conditions)
if onStatesChange then
  onStatesChange(function(player, states, oldStates)
    EventBus.emit("player:statesChange", states, oldStates)
  end)
end

-- Modal dialog events
if onModalDialog then
  onModalDialog(function(id, title, message, buttons, enterButton, escapeButton, choices, priority)
    EventBus.emit("dialog:modal", id, title, message, buttons, enterButton, escapeButton, choices)
  end)
end

-- Channel events
if onChannelList then
  onChannelList(function(channels)
    EventBus.emit("channel:list", channels)
  end)
end

if onOpenChannel then
  onOpenChannel(function(channelId, channelName)
    EventBus.emit("channel:open", channelId, channelName)
  end)
end

if onCloseChannel then
  onCloseChannel(function(channelId)
    EventBus.emit("channel:close", channelId)
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LOOT MESSAGE PARSING
-- Parse loot messages to emit structured loot events
-- ═══════════════════════════════════════════════════════════════════════════

-- Listen for loot messages and parse them
EventBus.on("message:text", function(mode, text)
  -- Loot message mode is typically 19 or 20 depending on server
  if mode == 19 or mode == 20 then
    -- Pattern: "Loot of a <monster>: <items>"
    local monsterName = text:match("Loot of [an]* (.-):%s")
    if monsterName then
      local itemsStr = text:match(": (.+)$")
      EventBus.emit("loot:received", monsterName, itemsStr or "", text)
    end
  end
end, 10)

-- ═══════════════════════════════════════════════════════════════════════════
-- STORAGE PERSISTENCE EVENTS
-- These events are emitted by modules when settings change
-- UnifiedStorage listens to these for real-time persistence
-- ═══════════════════════════════════════════════════════════════════════════

-- Helper function to emit config change events
function EventBus.emitConfigChange(moduleName, configName)
  EventBus.emit(moduleName .. ":configChanged", configName)
end

-- Helper function to emit setting change events
function EventBus.emitSettingChange(path, value)
  EventBus.emit("setting:changed", path, value)
end
