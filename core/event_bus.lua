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

-- Startup safeguard: filter known problematic spawners (configurable via ProfileStorage.get("startupFilterPlayers"))
local startupFilter = {}
do
  local ok, list = pcall(function() return ProfileStorage and ProfileStorage.get("startupFilterPlayers") end)
  if ok and type(list) == "table" then
    for _, n in ipairs(list) do startupFilter[tostring(n)] = true end
  end
  -- Add a default safe entry for the reported problematic name
  startupFilter["Elderane"] = true
end

local startupCounts = {} -- { [name] = {first=ts, count=n, warned=true} }
local STARTUP_WINDOW_MS = 10000 -- 10s window
local STARTUP_THRESHOLD = 5 -- ignore after this many appears within window

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

-- Subscribe to an event (one-time only)
-- @param event string: Event name
-- @param callback function: Handler function
function EventBus.once(event, callback)
  local unsubscribe
  unsubscribe = EventBus.on(event, function(...)
    unsubscribe()
    callback(...)
  end)
  return unsubscribe
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

  processing = false
end

-- Remove all listeners for an event
-- @param event string: Event name (optional, clears all if nil)
function EventBus.clear(event)
  if event then
    listeners[event] = nil
  else
    listeners = {}
  end
end

-- Get listener count for debugging
-- @param event string: Event name (optional)
-- @return number: Listener count
function EventBus.listenerCount(event)
  if event then
    return listeners[event] and #listeners[event] or 0
  end
  
  local total = 0
  for _, handlers in pairs(listeners) do
    total = total + #handlers
  end
  return total
end

-- Get number of queued events currently waiting to be processed
function EventBus.queueSize()
  return math.max(0, eventQueue.tail - eventQueue.head + 1)
end

--------------------------------------------------------------------------------
-- OTClient Native Event Registration
-- Register once, dispatch through EventBus
--------------------------------------------------------------------------------

-- Creature events
if onCreatureAppear then
  onCreatureAppear(function(creature)
    -- Startup filter: protect from bursty spawns of problematic names (e.g., 'Elderane')
    local ok, name = pcall(function() return creature:getName() end)
    if ok and name and startupFilter[name] then
      local now = math.floor(os.clock() * 1000)
      local rec = startupCounts[name]
      if not rec or (now - rec.first) > STARTUP_WINDOW_MS then
        rec = { first = now, count = 0, warned = false }
        startupCounts[name] = rec
      end
      rec.count = rec.count + 1
      if rec.count > STARTUP_THRESHOLD then
        if not rec.warned then
          warn("[EventBus] Ignoring repeated spawn of '" .. tostring(name) .. "' (count=" .. tostring(rec.count) .. "), protecting main loop")
          pcall(function()
            if ProfileStorage then
              ProfileStorage.set("bootFreezeLast", { name = name, count = rec.count, ts = now })
            end
          end)
          rec.warned = true
        end
        -- return -- drop this appear event to avoid heavy processing
      end
    end

    if creature:isMonster() then
      EventBus.emit("monster:appear", creature)
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
    if creature:isMonster() then
      EventBus.emit("monster:disappear", creature)
    elseif creature:isPlayer() then
      EventBus.emit("player:disappear", creature)
    end
    EventBus.emit("creature:disappear", creature)
  end)
end

-- Track creature health for detecting changes
local creatureHealthCache = {}
setmetatable(creatureHealthCache, { __mode = "k" }) -- Weak keys for auto-cleanup

if onCreatureHealthPercentChange then
  onCreatureHealthPercentChange(function(creature, percent)
    -- Get cached old HP (default to 100 if not tracked)
    local oldPercent = creatureHealthCache[creature] or 100
    creatureHealthCache[creature] = percent
    
    -- Emit with both old and new values for proper change detection
    EventBus.emit("creature:health", creature, percent, oldPercent)
    
    if creature:isMonster() then
      EventBus.emit("monster:health", creature, percent, oldPercent)
    elseif creature:isPlayer() and not creature:isLocalPlayer() then
      -- Emit dedicated friend/player health event for FriendHealer
      EventBus.emit("friend:health", creature, percent, oldPercent)
    end
  end)
end

-- Player events
if onPlayerPositionChange then
  onPlayerPositionChange(function(newPos, oldPos)
    EventBus.emit("player:move", newPos, oldPos)
  end)
end

if onManaChange then
  onManaChange(function(localPlayer, mana, maxMana, oldMana, oldMaxMana)
    EventBus.emit("player:mana", mana, maxMana, oldMana, oldMaxMana)
  end)
end

if onHealthChange then
  onHealthChange(function(localPlayer, health, maxHealth, oldHealth, oldMaxHealth)
    EventBus.emit("player:health", health, maxHealth, oldHealth, oldMaxHealth)

    -- Emit a damage event when player's health drops so modules can correlate source
    if oldHealth and health and oldHealth > health then
      local damage = oldHealth - health
      -- Best-effort attribution: search nearby monsters and pick best candidate
      local playerPos = nil
      local ok, lp = pcall(function() return g_game and g_game.getLocalPlayer and g_game.getLocalPlayer() end)
      if ok and lp then pcall(function() playerPos = lp:getPosition() end) end
      if not playerPos and player and player.getPosition then pcall(function() playerPos = player:getPosition() end) end

      local bestMonster, bestScore = nil, 0
      if playerPos then
        local radius = (MonsterAI and MonsterAI.CONSTANTS and MonsterAI.CONSTANTS.DAMAGE and MonsterAI.CONSTANTS.DAMAGE.CORRELATION_RADIUS) or 7
        local threshold = (MonsterAI and MonsterAI.CONSTANTS and MonsterAI.CONSTANTS.DAMAGE and MonsterAI.CONSTANTS.DAMAGE.CORRELATION_THRESHOLD) or 0.4

        local creatures = (MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby)
          and MovementCoordinator.MonsterCache.getNearby(radius)
          or g_map.getSpectatorsInRange(playerPos, false, radius, radius)

        local nowt = now or (g_clock and g_clock.millis and g_clock.millis()) or (os.time() * 1000)
        -- FIXED: Add nil check for creatures before iterating
        if creatures then
          for i = 1, #creatures do
            local m = creatures[i]
            -- FIXED: Properly capture both pcall return values
            local okm, isValidMonster = pcall(function() return m and m:isMonster() and not m:isDead() end)
            if okm and isValidMonster and m then
              local mpos
              pcall(function() mpos = m:getPosition() end)
              if mpos then
                local dist = math.max(math.abs(playerPos.x - mpos.x), math.abs(playerPos.y - mpos.y))
                local score = 1 / (1 + dist)

                -- Boost score with MonsterAI tracker info if available
                local okid, mid = pcall(function() return m and m:getId() end)
                if okid and mid and MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.monsters then
                  local data = MonsterAI.Tracker.monsters[mid]
                  if data then
                    if data.lastWaveTime and math.abs(nowt - data.lastWaveTime) < 800 then score = score + 1.2 end
                    if data.lastAttackTime and math.abs(nowt - data.lastAttackTime) < 1500 then score = score + 0.8 end
                  end
                end

                -- Prefer monsters facing player when possible
                if MonsterAI and MonsterAI.Predictor and MonsterAI.Predictor.isFacingPosition then
                  local okf, facing = pcall(function() return MonsterAI.Predictor.isFacingPosition(mpos, m:getDirection(), playerPos) end)
                  if okf and facing then score = score + 0.6 end
                end

                if score > bestScore then bestScore = score; bestMonster = m end
              end
            end
          end
        end

        if bestScore and bestScore >= threshold then
          EventBus.emit("player:damage", damage, bestMonster)
        else
          EventBus.emit("player:damage", damage, nil)
        end
      else
        -- No player position available: emit damage with unknown source
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

-- Tile events
if onAddThing then
  onAddThing(function(tile, thing)
    EventBus.emit("tile:add", tile, thing)
  end)
end

if onRemoveThing then
  onRemoveThing(function(tile, thing)
    EventBus.emit("tile:remove", tile, thing)
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

-- Equipment check macro (runs every 200ms, lightweight)
macro(200, function()
  checkEquipmentChanges()
end)

-- Periodic flush for queued events
macro(25, function()
  EventBus.flush()
end)