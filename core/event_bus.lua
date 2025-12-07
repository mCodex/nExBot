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

-- Private state
local listeners = {}
local eventQueue = {}
local processing = false

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
  table.insert(eventQueue, {event = event, args = {...}})
end

-- Process all queued events
function EventBus.flush()
  if processing then return end
  processing = true
  
  while #eventQueue > 0 do
    local item = table.remove(eventQueue, 1)
    EventBus.emit(item.event, table.unpack(item.args))
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

--------------------------------------------------------------------------------
-- OTClient Native Event Registration
-- Register once, dispatch through EventBus
--------------------------------------------------------------------------------

-- Creature events
if onCreatureAppear then
  onCreatureAppear(function(creature)
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

if onCreatureHealthPercentChange then
  onCreatureHealthPercentChange(function(creature, percent)
    EventBus.emit("creature:health", creature, percent)
    if creature:isMonster() then
      EventBus.emit("monster:health", creature, percent)
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

-- Periodic flush for queued events
macro(50, function()
  EventBus.flush()
end)