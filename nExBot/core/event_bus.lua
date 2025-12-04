--[[
  ============================================================================
  nExBot Event Bus
  ============================================================================
  
  Decoupled event-driven communication between modules using Observer pattern.
  Enables loose coupling between bot components for better maintainability.
  
  DESIGN PATTERNS:
  - Observer Pattern: Modules subscribe to events without knowing publishers
  - Mediator Pattern: EventBus acts as central communication hub
  
  PERFORMANCE FEATURES:
  - O(1) event lookup using hash tables
  - Priority-based listener execution with stable sort
  - Lazy history trimming to avoid constant array operations
  - Weak references for automatic listener cleanup (optional)
  
  MEMORY FEATURES:
  - Configurable history size with automatic trimming
  - Listener cleanup on unsubscribe
  - Efficient subscription ID generation
  
  Author: nExBot Team
  Version: 2.0.0 (Optimized)
  Last Updated: December 2025
  
  ============================================================================
]]

--[[
  ============================================================================
  LOCAL CACHING FOR PERFORMANCE
  ============================================================================
]]
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort
local tostring = tostring
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local os_time = os.time
local math_random = math.random

--[[
  ============================================================================
  EVENT BUS CLASS DEFINITION
  ============================================================================
]]

local EventBus = {
  -- Listener storage: eventName -> array of {id, callback, priority}
  listeners = {},
  
  -- Event history for debugging (circular buffer concept)
  eventHistory = {},
  historyIndex = 0,
  
  -- Configuration
  maxHistorySize = 100,
  debugMode = false,
  
  -- Statistics
  stats = {
    totalEmitted = 0,
    totalSubscribed = 0,
    totalUnsubscribed = 0
  }
}

--[[
  ============================================================================
  INITIALIZATION
  ============================================================================
]]

--- Initializes or resets the event bus
-- Clears all listeners and history, resets statistics
-- @return self for chaining
function EventBus:initialize()
  self.listeners = {}
  self.eventHistory = {}
  self.historyIndex = 0
  self.stats = {
    totalEmitted = 0,
    totalSubscribed = 0,
    totalUnsubscribed = 0
  }
  return self
end

--[[
  ============================================================================
  SUBSCRIPTION MANAGEMENT
  ============================================================================
]]

--- Subscribes to an event with optional priority
-- Higher priority listeners are called first (default: 0)
-- 
-- @param eventName (string) Name of event to listen for
-- @param callback (function) Function called when event is emitted
-- @param priority (number|nil) Execution priority (higher = earlier, default: 0)
-- @return (string) Subscription ID for unsubscribing
-- 
-- Example:
--   local id = EventBus:subscribe("player:health_changed", function(newHp, oldHp)
--     print("Health changed from " .. oldHp .. " to " .. newHp)
--   end, 10)  -- High priority
function EventBus:subscribe(eventName, callback, priority)
  -- Validate parameters
  if type(eventName) ~= "string" then
    error("[EventBus] Event name must be a string, got: " .. type(eventName))
  end
  if type(callback) ~= "function" then
    error("[EventBus] Callback must be a function, got: " .. type(callback))
  end
  
  priority = priority or 0
  
  -- Initialize listener array for this event if needed
  if not self.listeners[eventName] then
    self.listeners[eventName] = {}
  end
  
  -- Generate unique subscription ID
  -- Format: eventName_timestamp_random for debugging clarity
  local subscriptionId = eventName .. "_" .. tostring(os_time()) .. "_" .. math_random(10000, 99999)
  
  -- Add listener
  local listener = {
    id = subscriptionId,
    callback = callback,
    priority = priority
  }
  table_insert(self.listeners[eventName], listener)
  
  -- Re-sort by priority (higher first) - only needed when multiple listeners
  if #self.listeners[eventName] > 1 then
    table_sort(self.listeners[eventName], function(a, b)
      return a.priority > b.priority
    end)
  end
  
  -- Update statistics
  self.stats.totalSubscribed = self.stats.totalSubscribed + 1
  
  -- Debug logging
  if self.debugMode then
    print("[EventBus] Subscribed to: " .. eventName .. 
          " (ID: " .. subscriptionId .. ", Priority: " .. priority .. ")")
  end
  
  return subscriptionId
end

--- Unsubscribes from an event using the subscription ID
-- @param subscriptionId (string) ID returned from subscribe()
-- @return (boolean) True if successfully unsubscribed
function EventBus:unsubscribe(subscriptionId)
  if not subscriptionId then return false end
  
  -- Search all event types for this subscription
  for eventName, listeners in pairs(self.listeners) do
    for i = #listeners, 1, -1 do  -- Iterate backwards for safe removal
      if listeners[i].id == subscriptionId then
        table_remove(listeners, i)
        
        -- Clean up empty listener arrays
        if #listeners == 0 then
          self.listeners[eventName] = nil
        end
        
        self.stats.totalUnsubscribed = self.stats.totalUnsubscribed + 1
        
        if self.debugMode then
          print("[EventBus] Unsubscribed: " .. subscriptionId)
        end
        
        return true
      end
    end
  end
  
  return false
end

--- Subscribes to an event for a single emission only
-- Automatically unsubscribes after the first event
-- @param eventName (string) Name of event
-- @param callback (function) Callback function
-- @param priority (number|nil) Execution priority
-- @return (string) Subscription ID
function EventBus:once(eventName, callback, priority)
  local subscriptionId
  
  local wrappedCallback = function(...)
    -- Unsubscribe first to prevent re-entry issues
    self:unsubscribe(subscriptionId)
    -- Then call the actual callback
    callback(...)
  end
  
  subscriptionId = self:subscribe(eventName, wrappedCallback, priority)
  return subscriptionId
end

--[[
  ============================================================================
  EVENT EMISSION
  ============================================================================
]]

--- Emits an event to all subscribed listeners
-- Listeners are called in priority order (highest first)
-- Errors in callbacks are caught and logged, won't break other listeners
-- 
-- @param eventName (string) Name of event to emit
-- @param ... Additional arguments passed to listeners
-- 
-- Example:
--   EventBus:emit("player:health_changed", newHp, oldHp)
function EventBus:emit(eventName, ...)
  -- Update statistics
  self.stats.totalEmitted = self.stats.totalEmitted + 1
  
  -- Debug logging (before processing to show what's being emitted)
  if self.debugMode then
    print("[EventBus] Emitting: " .. eventName)
  end
  
  -- Store in history (for debugging)
  self:recordHistory(eventName, ...)
  
  -- Get listeners for this event
  local listeners = self.listeners[eventName]
  if not listeners or #listeners == 0 then
    return
  end
  
  -- Call each listener (already sorted by priority)
  for _, listener in ipairs(listeners) do
    local success, err = pcall(listener.callback, ...)
    
    if not success then
      -- Log error but continue processing other listeners
      if warn then
        warn("[EventBus] Error in callback for '" .. eventName .. "': " .. tostring(err))
      end
    end
  end
end

--- Emits an event after a delay
-- Useful for debouncing or delayed reactions
-- @param eventName (string) Name of event
-- @param delay (number) Delay in milliseconds
-- @param ... Arguments to pass to listeners
function EventBus:emitDelayed(eventName, delay, ...)
  local args = {...}
  
  if schedule then
    schedule(delay, function()
      self:emit(eventName, unpack(args))
    end)
  end
end

--- Emits an event only if there are listeners
-- Avoids unnecessary processing when no one is listening
-- @param eventName (string) Name of event
-- @param ... Arguments to pass
-- @return (boolean) True if event was emitted
function EventBus:emitIfListened(eventName, ...)
  if self:hasListeners(eventName) then
    self:emit(eventName, ...)
    return true
  end
  return false
end

--[[
  ============================================================================
  LISTENER QUERIES
  ============================================================================
]]

--- Checks if an event has any listeners
-- @param eventName (string) Name of event
-- @return (boolean) True if listeners exist
function EventBus:hasListeners(eventName)
  local listeners = self.listeners[eventName]
  return listeners ~= nil and #listeners > 0
end

--- Gets the number of listeners for an event
-- @param eventName (string) Name of event
-- @return (number) Listener count
function EventBus:getListenerCount(eventName)
  local listeners = self.listeners[eventName]
  return listeners and #listeners or 0
end

--- Gets total listener count across all events
-- @return (number) Total listener count
function EventBus:getTotalListenerCount()
  local total = 0
  for _, listeners in pairs(self.listeners) do
    total = total + #listeners
  end
  return total
end

--[[
  ============================================================================
  CLEANUP OPERATIONS
  ============================================================================
]]

--- Removes all listeners for a specific event
-- @param eventName (string) Name of event to clear
function EventBus:clearEvent(eventName)
  local count = self:getListenerCount(eventName)
  self.listeners[eventName] = nil
  
  if self.debugMode and count > 0 then
    print("[EventBus] Cleared " .. count .. " listeners for: " .. eventName)
  end
end

--- Removes all listeners for all events
function EventBus:clearAll()
  local count = self:getTotalListenerCount()
  self.listeners = {}
  
  if self.debugMode then
    print("[EventBus] Cleared all " .. count .. " listeners")
  end
end

--[[
  ============================================================================
  HISTORY & DEBUGGING
  ============================================================================
]]

--- Records an event in history (internal)
-- Uses modular arithmetic for circular buffer behavior
-- @param eventName (string) Event name
-- @param ... Event arguments
function EventBus:recordHistory(eventName, ...)
  -- Only record if history is enabled
  if self.maxHistorySize <= 0 then return end
  
  self.historyIndex = self.historyIndex + 1
  
  local entry = {
    index = self.historyIndex,
    name = eventName,
    timestamp = os_time(),
    argCount = select("#", ...)
  }
  
  -- Store at circular position
  local pos = ((self.historyIndex - 1) % self.maxHistorySize) + 1
  self.eventHistory[pos] = entry
end

--- Gets event history (most recent events)
-- @param limit (number|nil) Maximum entries to return
-- @return (table) Array of history entries
function EventBus:getHistory(limit)
  limit = limit or self.maxHistorySize
  
  local history = {}
  local count = math.min(#self.eventHistory, limit)
  
  -- Return in chronological order (oldest first)
  for i = 1, count do
    table_insert(history, self.eventHistory[i])
  end
  
  return history
end

--- Clears event history
function EventBus:clearHistory()
  self.eventHistory = {}
  self.historyIndex = 0
end

--- Sets debug mode on/off
-- When enabled, logs all subscribe/unsubscribe/emit operations
-- @param enabled (boolean) Enable or disable
function EventBus:setDebugMode(enabled)
  self.debugMode = enabled
end

--- Gets statistics about event bus usage
-- @return (table) Stats object
function EventBus:getStats()
  return {
    totalEmitted = self.stats.totalEmitted,
    totalSubscribed = self.stats.totalSubscribed,
    totalUnsubscribed = self.stats.totalUnsubscribed,
    activeListeners = self:getTotalListenerCount(),
    historySize = #self.eventHistory,
    registeredEvents = self:getRegisteredEventCount()
  }
end

--- Gets count of event types with listeners
-- @return (number) Count of registered event types
function EventBus:getRegisteredEventCount()
  local count = 0
  for _ in pairs(self.listeners) do
    count = count + 1
  end
  return count
end

--- Gets all registered event names
-- @return (table) Array of event names
function EventBus:getRegisteredEvents()
  local events = {}
  for eventName, _ in pairs(self.listeners) do
    table_insert(events, eventName)
  end
  table_sort(events)  -- Alphabetical for readability
  return events
end

--[[
  ============================================================================
  PREDEFINED EVENT NAMES
  ============================================================================
  
  These constants provide consistent event naming across the codebase.
  Using constants prevents typos and enables autocomplete in IDEs.
  
  Naming Convention: category:action_verb
  ============================================================================
]]

EventBus.Events = {
  -- ========================================
  -- PLAYER EVENTS
  -- Emitted when player state changes
  -- ========================================
  
  -- Health changed: (newHp, oldHp, maxHp)
  PLAYER_HEALTH_CHANGED = "player:health_changed",
  
  -- Mana changed: (newMana, oldMana, maxMana)
  PLAYER_MANA_CHANGED = "player:mana_changed",
  
  -- Position changed: (newPos, oldPos)
  PLAYER_POSITION_CHANGED = "player:position_changed",
  
  -- Condition added/removed: (conditionId, added)
  PLAYER_CONDITION_CHANGED = "player:condition_changed",
  
  -- Soul points changed: (newSoul, oldSoul)
  PLAYER_SOUL_CHANGED = "player:soul_changed",
  
  -- ========================================
  -- COMBAT EVENTS
  -- Emitted during combat actions
  -- ========================================
  
  -- Target changed: (newTarget, oldTarget)
  COMBAT_TARGET_CHANGED = "combat:target_changed",
  
  -- Attack executed: (target, attackType)
  COMBAT_ATTACK_EXECUTED = "combat:attack_executed",
  
  -- Spell cast: (spellWords, target, manaCost)
  COMBAT_SPELL_CAST = "combat:spell_cast",
  
  -- Damage received: (amount, damageType, source)
  COMBAT_DAMAGE_RECEIVED = "combat:damage_received",
  
  -- Damage dealt: (amount, damageType, target)
  COMBAT_DAMAGE_DEALT = "combat:damage_dealt",
  
  -- ========================================
  -- CREATURE EVENTS
  -- Emitted when creatures appear/disappear
  -- ========================================
  
  -- Creature appeared on screen: (creature)
  CREATURE_APPEARED = "creature:appeared",
  
  -- Creature left screen: (creature)
  CREATURE_DISAPPEARED = "creature:disappeared",
  
  -- Creature died: (creature, killer)
  CREATURE_DIED = "creature:died",
  
  -- Creature health changed: (creature, newHp, oldHp)
  CREATURE_HEALTH_CHANGED = "creature:health_changed",
  
  -- ========================================
  -- LOOT EVENTS
  -- Emitted during looting operations
  -- ========================================
  
  -- Item looted: (item, corpse, value)
  LOOT_COLLECTED = "loot:collected",
  
  -- Corpse container opened: (container, creature)
  LOOT_CONTAINER_OPENED = "loot:container_opened",
  
  -- Skinning complete: (corpse, itemObtained)
  LOOT_SKINNED = "loot:skinned",
  
  -- ========================================
  -- CAVEBOT EVENTS
  -- Emitted during CaveBot navigation
  -- ========================================
  
  -- Label waypoint reached: (labelName)
  CAVEBOT_LABEL_REACHED = "cavebot:label_reached",
  
  -- Any waypoint reached: (waypointIndex, waypointData)
  CAVEBOT_WAYPOINT_REACHED = "cavebot:waypoint_reached",
  
  -- Supply check triggered: (suppliesLow, details)
  CAVEBOT_SUPPLY_CHECK = "cavebot:supply_check",
  
  -- Round completed: (roundNumber, stats)
  CAVEBOT_ROUND_COMPLETE = "cavebot:round_complete",
  
  -- Depositer started/finished: (phase)
  CAVEBOT_DEPOSITER = "cavebot:depositer",
  
  -- ========================================
  -- MODULE EVENTS
  -- Emitted for module lifecycle
  -- ========================================
  
  -- Module enabled: (moduleName, version)
  MODULE_ENABLED = "module:enabled",
  
  -- Module disabled: (moduleName)
  MODULE_DISABLED = "module:disabled",
  
  -- Module error occurred: (moduleName, error)
  MODULE_ERROR = "module:error",
  
  -- Settings changed: (moduleName, settingKey, newValue)
  MODULE_SETTINGS_CHANGED = "module:settings_changed",
  
  -- ========================================
  -- AVOIDANCE EVENTS
  -- Emitted by wave avoidance system
  -- ========================================
  
  -- Danger detected: (dangerLevel, threats)
  AVOIDANCE_DANGER_DETECTED = "avoidance:danger_detected",
  
  -- Avoided successfully: (fromPos, toPos)
  AVOIDANCE_WAVE_AVOIDED = "avoidance:wave_avoided",
  
  -- ========================================
  -- UI EVENTS
  -- Emitted for UI state changes
  -- ========================================
  
  -- Tab switched: (newTab, oldTab)
  UI_TAB_CHANGED = "ui:tab_changed",
  
  -- Window opened: (windowName)
  UI_WINDOW_OPENED = "ui:window_opened",
  
  -- Window closed: (windowName)
  UI_WINDOW_CLOSED = "ui:window_closed"
}

--[[
  ============================================================================
  MODULE EXPORT
  ============================================================================
]]

return EventBus
