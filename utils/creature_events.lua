--[[
  Creature Event Coordinator v1.0
  
  Centralizes creature event handling to reduce duplicate EventBus registrations.
  Instead of 10+ modules each registering their own EventBus.on("creature:move"),
  this module registers ONCE and dispatches to all subscribers efficiently.
  
  BENEFITS:
  - Single EventBus registration per event type (vs 10+ registrations)
  - Priority-based dispatch for handlers
  - Automatic cleanup of stale handlers
  - Performance tracking
  
  USAGE:
    local CreatureEvents = require("utils.creature_events")
    
    CreatureEvents.onMove("myModule", function(creature, oldPos, newPos)
      -- Handle creature movement
    end, 50)  -- priority 50 (higher = runs first)
    
    CreatureEvents.onAppear("myModule", function(creature)
      -- Handle creature appearing
    end)
]]

local CreatureEvents = {}
CreatureEvents.VERSION = "1.0"
CreatureEvents.DEBUG = false

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================

-- Handler storage: eventType -> {name -> {handler, priority}}
local handlers = {
  move = {},
  appear = {},
  disappear = {},
  death = {},
  turn = {},
  healthChange = {}
}

-- Sorted handler lists (rebuilt when handlers change)
local sortedHandlers = {
  move = {},
  appear = {},
  disappear = {},
  death = {},
  turn = {},
  healthChange = {}
}

-- Performance stats
local stats = {
  eventsProcessed = 0,
  handlersInvoked = 0,
  errors = 0
}

-- Registered flag
local registered = false

-- SafeCreature for safe access
local SC = SafeCreature

-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

-- Rebuild sorted handler list for an event type
local function rebuildSorted(eventType)
  local sorted = {}
  for name, data in pairs(handlers[eventType]) do
    sorted[#sorted + 1] = {
      name = name,
      handler = data.handler,
      priority = data.priority or 50
    }
  end
  
  -- Sort by priority (higher first)
  table.sort(sorted, function(a, b)
    return a.priority > b.priority
  end)
  
  sortedHandlers[eventType] = sorted
end

-- Dispatch event to all handlers
local function dispatch(eventType, ...)
  stats.eventsProcessed = stats.eventsProcessed + 1
  
  local handlerList = sortedHandlers[eventType]
  if not handlerList then return end
  
  for i = 1, #handlerList do
    local entry = handlerList[i]
    local ok, err = pcall(entry.handler, ...)
    stats.handlersInvoked = stats.handlersInvoked + 1
    
    if not ok then
      stats.errors = stats.errors + 1
      if CreatureEvents.DEBUG then
        print("[CreatureEvents] Error in " .. entry.name .. ": " .. tostring(err))
      end
    end
  end
end

-- ============================================================================
-- EVENT REGISTRATION (called once at startup)
-- ============================================================================

local function registerEventBusHandlers()
  if registered then return end
  registered = true
  
  -- Only register if EventBus exists
  if not EventBus or not EventBus.on then
    if CreatureEvents.DEBUG then
      print("[CreatureEvents] EventBus not available, using fallback hooks")
    end
    
    -- Fallback: use OTClient hooks directly
    if onCreatureMove then
      onCreatureMove(function(creature, oldPos)
        local newPos = SC and SC.getPosition(creature) or nil
        dispatch("move", creature, oldPos, newPos)
      end)
    end
    
    if onCreatureAppear then
      onCreatureAppear(function(creature)
        dispatch("appear", creature)
      end)
    end
    
    if onCreatureDisappear then
      onCreatureDisappear(function(creature)
        dispatch("disappear", creature)
      end)
    end
    
    if onCreatureTurn then
      onCreatureTurn(function(creature, direction)
        dispatch("turn", creature, direction)
      end)
    end
    
    return
  end
  
  -- Register with EventBus (preferred)
  EventBus.on("creature:move", function(creature, oldPos, newPos)
    dispatch("move", creature, oldPos, newPos)
  end, 100)  -- High priority to run before other handlers
  
  EventBus.on("creature:appear", function(creature)
    dispatch("appear", creature)
  end, 100)
  
  EventBus.on("creature:disappear", function(creature)
    dispatch("disappear", creature)
  end, 100)
  
  EventBus.on("creature:death", function(creature)
    dispatch("death", creature)
  end, 100)
  
  EventBus.on("creature:turn", function(creature, direction)
    dispatch("turn", creature, direction)
  end, 100)
  
  EventBus.on("creature:healthChange", function(creature, oldHp, newHp)
    dispatch("healthChange", creature, oldHp, newHp)
  end, 100)
  
  if CreatureEvents.DEBUG then
    print("[CreatureEvents] Registered with EventBus")
  end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Register a handler for creature move events
-- @param name: unique handler name
-- @param handler: function(creature, oldPos, newPos)
-- @param priority: higher runs first (default 50)
function CreatureEvents.onMove(name, handler, priority)
  handlers.move[name] = { handler = handler, priority = priority or 50 }
  rebuildSorted("move")
  registerEventBusHandlers()
end

-- Register a handler for creature appear events
-- @param name: unique handler name
-- @param handler: function(creature)
-- @param priority: higher runs first (default 50)
function CreatureEvents.onAppear(name, handler, priority)
  handlers.appear[name] = { handler = handler, priority = priority or 50 }
  rebuildSorted("appear")
  registerEventBusHandlers()
end

-- Register a handler for creature disappear events
-- @param name: unique handler name
-- @param handler: function(creature)
-- @param priority: higher runs first (default 50)
function CreatureEvents.onDisappear(name, handler, priority)
  handlers.disappear[name] = { handler = handler, priority = priority or 50 }
  rebuildSorted("disappear")
  registerEventBusHandlers()
end

-- Register a handler for creature death events
-- @param name: unique handler name
-- @param handler: function(creature)
-- @param priority: higher runs first (default 50)
function CreatureEvents.onDeath(name, handler, priority)
  handlers.death[name] = { handler = handler, priority = priority or 50 }
  rebuildSorted("death")
  registerEventBusHandlers()
end

-- Register a handler for creature turn events
-- @param name: unique handler name
-- @param handler: function(creature, direction)
-- @param priority: higher runs first (default 50)
function CreatureEvents.onTurn(name, handler, priority)
  handlers.turn[name] = { handler = handler, priority = priority or 50 }
  rebuildSorted("turn")
  registerEventBusHandlers()
end

-- Register a handler for creature health change events
-- @param name: unique handler name
-- @param handler: function(creature, oldHp, newHp)
-- @param priority: higher runs first (default 50)
function CreatureEvents.onHealthChange(name, handler, priority)
  handlers.healthChange[name] = { handler = handler, priority = priority or 50 }
  rebuildSorted("healthChange")
  registerEventBusHandlers()
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Remove a handler
-- @param eventType: "move", "appear", "disappear", "death", "turn", "healthChange"
-- @param name: handler name to remove
function CreatureEvents.remove(eventType, name)
  if handlers[eventType] then
    handlers[eventType][name] = nil
    rebuildSorted(eventType)
  end
end

-- Get performance stats
function CreatureEvents.getStats()
  local handlerCount = 0
  for _, typeHandlers in pairs(handlers) do
    for _ in pairs(typeHandlers) do
      handlerCount = handlerCount + 1
    end
  end
  
  return {
    eventsProcessed = stats.eventsProcessed,
    handlersInvoked = stats.handlersInvoked,
    errors = stats.errors,
    handlerCount = handlerCount,
    avgHandlersPerEvent = stats.eventsProcessed > 0 
      and (stats.handlersInvoked / stats.eventsProcessed) 
      or 0
  }
end

-- Reset stats
function CreatureEvents.resetStats()
  stats.eventsProcessed = 0
  stats.handlersInvoked = 0
  stats.errors = 0
end

-- ============================================================================
-- EXPORT
-- ============================================================================

-- Export to global (no _G in OTClient sandbox)
if not CreatureEvents then CreatureEvents = CreatureEvents end

return CreatureEvents
