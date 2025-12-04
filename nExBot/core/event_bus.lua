--[[
  NexBot Event Bus
  Decoupled event-driven communication between modules
  Implements Observer pattern for loose coupling
  
  Author: NexBot Team
  Version: 1.0.0
]]

local EventBus = {
  listeners = {},
  eventHistory = {},
  maxHistorySize = 100,
  debugMode = false
}

-- Initialize the event bus
function EventBus:initialize()
  self.listeners = {}
  self.eventHistory = {}
  return self
end

-- Subscribe to an event
-- @param eventName string - Name of the event to listen for
-- @param callback function - Function to call when event is emitted
-- @param priority number (optional) - Higher priority callbacks are called first
-- @return string - Subscription ID for unsubscribing
function EventBus:subscribe(eventName, callback, priority)
  if type(eventName) ~= "string" then
    error("[EventBus] Event name must be a string")
  end
  if type(callback) ~= "function" then
    error("[EventBus] Callback must be a function")
  end
  
  priority = priority or 0
  
  if not self.listeners[eventName] then
    self.listeners[eventName] = {}
  end
  
  local subscriptionId = eventName .. "_" .. tostring(os.time()) .. "_" .. math.random(10000)
  
  table.insert(self.listeners[eventName], {
    id = subscriptionId,
    callback = callback,
    priority = priority
  })
  
  -- Sort by priority (higher first)
  table.sort(self.listeners[eventName], function(a, b)
    return a.priority > b.priority
  end)
  
  if self.debugMode then
    print("[EventBus] Subscribed to: " .. eventName .. " (ID: " .. subscriptionId .. ")")
  end
  
  return subscriptionId
end

-- Unsubscribe from an event
-- @param subscriptionId string - The ID returned from subscribe()
function EventBus:unsubscribe(subscriptionId)
  for eventName, listeners in pairs(self.listeners) do
    for i, listener in ipairs(listeners) do
      if listener.id == subscriptionId then
        table.remove(listeners, i)
        if self.debugMode then
          print("[EventBus] Unsubscribed: " .. subscriptionId)
        end
        return true
      end
    end
  end
  return false
end

-- Emit an event to all subscribers
-- @param eventName string - Name of the event to emit
-- @param ... - Arguments to pass to callbacks
function EventBus:emit(eventName, ...)
  if self.debugMode then
    print("[EventBus] Emitting: " .. eventName)
  end
  
  -- Store in history
  table.insert(self.eventHistory, {
    name = eventName,
    timestamp = os.time(),
    args = {...}
  })
  
  -- Trim history if too large
  while #self.eventHistory > self.maxHistorySize do
    table.remove(self.eventHistory, 1)
  end
  
  local listeners = self.listeners[eventName]
  if not listeners then return end
  
  for _, listener in ipairs(listeners) do
    local success, err = pcall(listener.callback, ...)
    if not success then
      warn("[EventBus] Error in callback for " .. eventName .. ": " .. tostring(err))
    end
  end
end

-- Emit an event asynchronously (with delay)
-- @param eventName string - Name of the event
-- @param delay number - Delay in milliseconds
-- @param ... - Arguments to pass to callbacks
function EventBus:emitDelayed(eventName, delay, ...)
  local args = {...}
  schedule(delay, function()
    self:emit(eventName, unpack(args))
  end)
end

-- Check if there are any listeners for an event
-- @param eventName string - Name of the event
-- @return boolean
function EventBus:hasListeners(eventName)
  return self.listeners[eventName] and #self.listeners[eventName] > 0
end

-- Get the number of listeners for an event
-- @param eventName string - Name of the event
-- @return number
function EventBus:getListenerCount(eventName)
  if not self.listeners[eventName] then return 0 end
  return #self.listeners[eventName]
end

-- Remove all listeners for a specific event
-- @param eventName string - Name of the event
function EventBus:clearEvent(eventName)
  self.listeners[eventName] = nil
end

-- Remove all listeners
function EventBus:clearAll()
  self.listeners = {}
end

-- Enable debug mode
function EventBus:setDebugMode(enabled)
  self.debugMode = enabled
end

-- Get event history (for debugging)
function EventBus:getHistory()
  return self.eventHistory
end

-- Predefined events
EventBus.Events = {
  -- Player events
  PLAYER_HEALTH_CHANGED = "player:health_changed",
  PLAYER_MANA_CHANGED = "player:mana_changed",
  PLAYER_POSITION_CHANGED = "player:position_changed",
  PLAYER_CONDITION_CHANGED = "player:condition_changed",
  
  -- Combat events
  COMBAT_TARGET_CHANGED = "combat:target_changed",
  COMBAT_ATTACK_EXECUTED = "combat:attack_executed",
  COMBAT_SPELL_CAST = "combat:spell_cast",
  COMBAT_DAMAGE_RECEIVED = "combat:damage_received",
  
  -- Creature events
  CREATURE_APPEARED = "creature:appeared",
  CREATURE_DISAPPEARED = "creature:disappeared",
  CREATURE_DIED = "creature:died",
  
  -- Loot events
  LOOT_COLLECTED = "loot:collected",
  LOOT_CONTAINER_OPENED = "loot:container_opened",
  
  -- CaveBot events
  CAVEBOT_LABEL_REACHED = "cavebot:label_reached",
  CAVEBOT_WAYPOINT_REACHED = "cavebot:waypoint_reached",
  CAVEBOT_SUPPLY_CHECK = "cavebot:supply_check",
  
  -- Module events
  MODULE_ENABLED = "module:enabled",
  MODULE_DISABLED = "module:disabled",
  MODULE_ERROR = "module:error"
}

return EventBus
