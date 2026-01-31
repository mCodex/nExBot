--[[
  Unified Tick System - Centralized Macro Management
  
  Consolidates 8+ separate macro loops (50-100ms each) into a single
  master tick that dispatches to handlers based on elapsed time.
  
  BEFORE: ~35-50 macro calls/second across multiple macros
  AFTER: Single 50ms master tick with priority-based dispatch
  
  ARCHITECTURE:
  - Master tick runs at 50ms (highest common frequency)
  - Handlers register with desired interval and priority
  - Healing remains on dedicated fast-path for safety
  - Event-driven updates reduce polling where possible
  
  DESIGN PRINCIPLES:
  - SRP: Each handler has single responsibility
  - KISS: Simple registration and dispatch
  - DRY: No duplicate timer logic across modules
  
  USAGE:
    UnifiedTick.register("myHandler", {
      interval = 200,
      priority = 5,
      handler = function(deltaTime) ... end
    })
]]

local UnifiedTick = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

UnifiedTick.MASTER_INTERVAL = 50  -- Master tick interval (ms)
UnifiedTick.DEBUG = false         -- Enable debug logging
UnifiedTick.ENABLED = true        -- Global enable flag

-- ============================================================================
-- PRIORITY LEVELS (Higher = runs first)
-- ============================================================================

UnifiedTick.Priority = {
  CRITICAL = 100,   -- Safety-critical (healing, emergency)
  HIGH = 75,        -- Combat-critical (targeting, attacking)
  NORMAL = 50,      -- Standard features (conditions, buffs)
  LOW = 25,         -- Background tasks (analytics, UI)
  IDLE = 10         -- Non-essential (cosmetics, logging)
}

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================

local handlers = {}           -- Registered tick handlers
local handlerOrder = {}       -- Sorted handler keys by priority
local lastTick = 0            -- Last master tick time
local tickCount = 0           -- Total ticks processed
local masterMacro = nil       -- Reference to the master macro

-- Performance tracking
local stats = {
  totalTicks = 0,
  totalHandlerCalls = 0,
  avgTickTime = 0,
  peakTickTime = 0,
  handlerStats = {}
}

-- Time helper
local function nowMs()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

-- ============================================================================
-- HANDLER REGISTRATION
-- ============================================================================

--[[
  Register a tick handler
  
  @param name string Unique handler name
  @param config table {
    interval: number (ms between calls),
    priority: number (higher = runs first),
    handler: function(deltaTime),
    enabled: boolean (default true),
    group: string (optional grouping for batch enable/disable)
  }
  @return boolean success
]]
function UnifiedTick.register(name, config)
  if not name or type(name) ~= "string" then
    warn("[UnifiedTick] Invalid handler name")
    return false
  end
  
  if not config or type(config.handler) ~= "function" then
    warn("[UnifiedTick] Invalid handler config for: " .. name)
    return false
  end
  
  local nowt = nowMs()
  
  handlers[name] = {
    name = name,
    interval = config.interval or 100,
    priority = config.priority or UnifiedTick.Priority.NORMAL,
    handler = config.handler,
    enabled = config.enabled ~= false,
    group = config.group or "default",
    lastRun = nowt,
    runCount = 0,
    totalTime = 0,
    avgTime = 0,
    errors = 0
  }
  
  -- Track stats
  stats.handlerStats[name] = {
    calls = 0,
    totalTime = 0,
    avgTime = 0,
    errors = 0
  }
  
  -- Rebuild sorted order
  UnifiedTick._rebuildOrder()
  
  if UnifiedTick.DEBUG then
    print(string.format("[UnifiedTick] Registered: %s (interval=%dms, priority=%d)",
      name, config.interval, config.priority))
  end
  
  return true
end

--[[
  Unregister a tick handler
  @param name string Handler name
  @return boolean success
]]
function UnifiedTick.unregister(name)
  if not handlers[name] then
    return false
  end
  
  handlers[name] = nil
  stats.handlerStats[name] = nil
  UnifiedTick._rebuildOrder()
  
  if UnifiedTick.DEBUG then
    print("[UnifiedTick] Unregistered: " .. name)
  end
  
  return true
end

--[[
  Enable/disable a handler
  @param name string Handler name
  @param enabled boolean
]]
function UnifiedTick.setEnabled(name, enabled)
  if handlers[name] then
    handlers[name].enabled = enabled
  end
end

--[[
  Enable/disable all handlers in a group
  @param group string Group name
  @param enabled boolean
]]
function UnifiedTick.setGroupEnabled(group, enabled)
  for name, handler in pairs(handlers) do
    if handler.group == group then
      handler.enabled = enabled
    end
  end
end

--[[
  Update handler interval at runtime
  @param name string Handler name
  @param interval number New interval (ms)
]]
function UnifiedTick.setInterval(name, interval)
  if handlers[name] and interval > 0 then
    handlers[name].interval = interval
  end
end

-- Rebuild sorted handler order by priority
function UnifiedTick._rebuildOrder()
  handlerOrder = {}
  for name, _ in pairs(handlers) do
    handlerOrder[#handlerOrder + 1] = name
  end
  
  table.sort(handlerOrder, function(a, b)
    return (handlers[a].priority or 0) > (handlers[b].priority or 0)
  end)
end

-- ============================================================================
-- MASTER TICK EXECUTION
-- ============================================================================

--[[
  Main tick function - called by master macro
  Dispatches to handlers based on their intervals
]]
function UnifiedTick._tick()
  if not UnifiedTick.ENABLED then return end
  
  local nowt = nowMs()
  local tickStart = os.clock()
  local deltaTime = nowt - lastTick
  lastTick = nowt
  tickCount = tickCount + 1
  
  local handlersRun = 0
  
  -- Process handlers in priority order
  for i = 1, #handlerOrder do
    local name = handlerOrder[i]
    local handler = handlers[name]
    
    if handler and handler.enabled then
      local elapsed = nowt - handler.lastRun
      
      -- Check if handler should run this tick
      if elapsed >= handler.interval then
        local handlerStart = os.clock()
        
        -- Run handler with error protection
        local ok, err = pcall(handler.handler, elapsed)
        
        local handlerTime = (os.clock() - handlerStart) * 1000
        handler.lastRun = nowt
        handler.runCount = handler.runCount + 1
        handler.totalTime = handler.totalTime + handlerTime
        handler.avgTime = handler.totalTime / handler.runCount
        handlersRun = handlersRun + 1
        
        -- Update stats
        local hs = stats.handlerStats[name]
        if hs then
          hs.calls = hs.calls + 1
          hs.totalTime = hs.totalTime + handlerTime
          hs.avgTime = hs.totalTime / hs.calls
        end
        
        if not ok then
          handler.errors = handler.errors + 1
          if hs then hs.errors = hs.errors + 1 end
          if UnifiedTick.DEBUG then
            warn("[UnifiedTick] Error in " .. name .. ": " .. tostring(err))
          end
        end
      end
    end
  end
  
  -- Update global stats
  local tickTime = (os.clock() - tickStart) * 1000
  stats.totalTicks = stats.totalTicks + 1
  stats.totalHandlerCalls = stats.totalHandlerCalls + handlersRun
  stats.avgTickTime = (stats.avgTickTime * 0.95) + (tickTime * 0.05)
  if tickTime > stats.peakTickTime then
    stats.peakTickTime = tickTime
  end
  
  -- Warn if tick is slow
  if tickTime > 20 and UnifiedTick.DEBUG then
    warn(string.format("[UnifiedTick] Slow tick: %.2fms (%d handlers)", tickTime, handlersRun))
  end
end

-- ============================================================================
-- LIFECYCLE MANAGEMENT
-- ============================================================================

--[[
  Start the unified tick system
  Creates the master macro if not already running
]]
function UnifiedTick.start()
  if masterMacro then
    return  -- Already running
  end
  
  lastTick = nowMs()
  
  -- Create master macro
  masterMacro = macro(UnifiedTick.MASTER_INTERVAL, function()
    UnifiedTick._tick()
  end)
  
  print("[UnifiedTick] Started (interval=" .. UnifiedTick.MASTER_INTERVAL .. "ms)")
end

--[[
  Stop the unified tick system
]]
function UnifiedTick.stop()
  if masterMacro then
    -- In OTClient, macros can be disabled by setting enabled to false
    -- or calling removeEvent if available
    if type(masterMacro) == "table" and masterMacro.setEnabled then
      masterMacro:setEnabled(false)
    end
    masterMacro = nil
  end
  
  print("[UnifiedTick] Stopped")
end

--[[
  Pause the unified tick system temporarily
]]
function UnifiedTick.pause()
  UnifiedTick.ENABLED = false
end

--[[
  Resume the unified tick system
]]
function UnifiedTick.resume()
  UnifiedTick.ENABLED = true
  lastTick = nowMs()
end

-- ============================================================================
-- STATISTICS AND DEBUGGING
-- ============================================================================

--[[
  Get tick system statistics
  @return table stats
]]
function UnifiedTick.getStats()
  return {
    enabled = UnifiedTick.ENABLED,
    totalTicks = stats.totalTicks,
    totalHandlerCalls = stats.totalHandlerCalls,
    avgTickTime = stats.avgTickTime,
    peakTickTime = stats.peakTickTime,
    handlerCount = #handlerOrder,
    handlers = stats.handlerStats
  }
end

--[[
  Get list of registered handlers with their stats
  @return array of handler info
]]
function UnifiedTick.getHandlers()
  local result = {}
  for i = 1, #handlerOrder do
    local name = handlerOrder[i]
    local handler = handlers[name]
    if handler then
      result[#result + 1] = {
        name = name,
        interval = handler.interval,
        priority = handler.priority,
        enabled = handler.enabled,
        group = handler.group,
        runCount = handler.runCount,
        avgTime = handler.avgTime,
        errors = handler.errors
      }
    end
  end
  return result
end

--[[
  Reset statistics
]]
function UnifiedTick.resetStats()
  stats.totalTicks = 0
  stats.totalHandlerCalls = 0
  stats.avgTickTime = 0
  stats.peakTickTime = 0
  
  for name, hs in pairs(stats.handlerStats) do
    hs.calls = 0
    hs.totalTime = 0
    hs.avgTime = 0
    hs.errors = 0
  end
  
  for name, handler in pairs(handlers) do
    handler.runCount = 0
    handler.totalTime = 0
    handler.avgTime = 0
    handler.errors = 0
  end
end

-- ============================================================================
-- PRE-DEFINED HANDLER TEMPLATES
-- Common handler patterns for easy migration
-- ============================================================================

--[[
  Create a condition check handler
  @param name string Handler name
  @param checkFn function Condition check function
  @param interval number Check interval (default 500ms)
]]
function UnifiedTick.registerConditionCheck(name, checkFn, interval)
  return UnifiedTick.register(name, {
    interval = interval or 500,
    priority = UnifiedTick.Priority.NORMAL,
    group = "conditions",
    handler = checkFn
  })
end

--[[
  Create a healing handler (high priority)
  @param name string Handler name
  @param healFn function Healing check function
  @param interval number Check interval (default 100ms)
]]
function UnifiedTick.registerHealingHandler(name, healFn, interval)
  return UnifiedTick.register(name, {
    interval = interval or 100,
    priority = UnifiedTick.Priority.CRITICAL,
    group = "healing",
    handler = healFn
  })
end

--[[
  Create a targeting handler (high priority)
  @param name string Handler name
  @param targetFn function Targeting logic function
  @param interval number Check interval (default 200ms)
]]
function UnifiedTick.registerTargetingHandler(name, targetFn, interval)
  return UnifiedTick.register(name, {
    interval = interval or 200,
    priority = UnifiedTick.Priority.HIGH,
    group = "targeting",
    handler = targetFn
  })
end

--[[
  Create a UI update handler (low priority)
  @param name string Handler name
  @param updateFn function UI update function
  @param interval number Update interval (default 300ms)
]]
function UnifiedTick.registerUIHandler(name, updateFn, interval)
  return UnifiedTick.register(name, {
    interval = interval or 300,
    priority = UnifiedTick.Priority.LOW,
    group = "ui",
    handler = updateFn
  })
end

--[[
  Create an analytics handler (idle priority)
  @param name string Handler name
  @param analyticsFn function Analytics function
  @param interval number Update interval (default 1000ms)
]]
function UnifiedTick.registerAnalyticsHandler(name, analyticsFn, interval)
  return UnifiedTick.register(name, {
    interval = interval or 1000,
    priority = UnifiedTick.Priority.IDLE,
    group = "analytics",
    handler = analyticsFn
  })
end

-- ============================================================================
-- EVENTBUS INTEGRATION
-- ============================================================================

-- Emit tick events for modules that prefer event-driven updates
function UnifiedTick._emitTickEvents()
  if not EventBus or not EventBus.emit then return end
  
  -- Emit general tick event every 100ms
  if tickCount % 2 == 0 then  -- Every 2 ticks = 100ms
    EventBus.emit("tick:100ms")
  end
  
  -- Emit slower tick events
  if tickCount % 4 == 0 then  -- Every 4 ticks = 200ms
    EventBus.emit("tick:200ms")
  end
  
  if tickCount % 10 == 0 then  -- Every 10 ticks = 500ms
    EventBus.emit("tick:500ms")
  end
  
  if tickCount % 20 == 0 then  -- Every 20 ticks = 1000ms
    EventBus.emit("tick:1000ms")
  end
end

-- ============================================================================
-- AUTO-START (Optional)
-- Uncomment to auto-start when module is loaded
-- ============================================================================

-- UnifiedTick.start()

return UnifiedTick
