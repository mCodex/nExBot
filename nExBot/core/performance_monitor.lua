--[[
  ============================================================================
  nExBot Performance Monitor
  ============================================================================
  
  Comprehensive profiling and monitoring tools for identifying bottlenecks
  and optimizing bot performance. Essential for debugging slow macros.
  
  FEATURES:
  - Function-level profiling with start/end timing
  - Memory tracking with trend analysis
  - Scheduled garbage collection
  - Leak detection heuristics
  - Formatted performance reports
  
  USAGE:
    local PM = require("core.performance_monitor")
    PM:initialize()
    PM:setEnabled(true)
    
    -- Profile a specific section
    local start = PM:startProfile("targeting")
    -- ... do targeting work ...
    PM:endProfile("targeting", start)
    
    -- Or use convenience wrapper
    local result = PM:profileFunction("calculation", myExpensiveFunc, arg1, arg2)
    
    -- Get report
    print(PM:getReport())
  
  PERFORMANCE NOTES:
  - Profiling adds ~0.1ms overhead per measurement
  - Disable profiling in production for maximum performance
  - Memory tracking triggers collectgarbage("count") which is lightweight
  
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
local table_concat = table.concat
local string_format = string.format
local pairs = pairs
local ipairs = ipairs
local math_min = math.min
local math_max = math.max
local math_huge = math.huge
local os_time = os.time
local collectgarbage = collectgarbage

--[[
  ============================================================================
  PERFORMANCE MONITOR CLASS
  ============================================================================
]]

local PerformanceMonitor = {
  -- ========================================
  -- CONFIGURATION
  -- ========================================
  enabled = false,        -- Master switch for profiling
  gcInterval = 60000,     -- Auto-GC interval in ms (60 seconds)
  maxSnapshots = 100,     -- Max memory snapshots to keep
  slowThreshold = 50,     -- Warn if avg time exceeds this (ms)
  
  -- ========================================
  -- PROFILE STORAGE
  -- Each profile tracks: calls, totalTime, minTime, maxTime, avgTime
  -- ========================================
  profiles = {},
  
  -- ========================================
  -- MEMORY TRACKING
  -- Array of {time, memory} snapshots
  -- ========================================
  memorySnapshots = {},
  lastGC = 0,
  
  -- ========================================
  -- TIMING HELPER
  -- Prefer g_clock.millis() for precision, fallback to os.time()
  -- ========================================
  getTime = nil  -- Initialized in init
}

--[[
  ============================================================================
  INITIALIZATION
  ============================================================================
]]

--- Initializes the performance monitor
-- Sets up timing function and clears previous data
-- @return self for chaining
function PerformanceMonitor:initialize()
  self.profiles = {}
  self.memorySnapshots = {}
  self.lastGC = now or 0
  
  -- ========================================
  -- TIMING FUNCTION SELECTION
  -- g_clock.millis() is preferred (millisecond precision)
  -- Fallback to os.time() * 1000 (second precision)
  -- ========================================
  if g_clock and g_clock.millis then
    self.getTime = function()
      return g_clock.millis()
    end
  else
    self.getTime = function()
      return os_time() * 1000
    end
  end
  
  return self
end

--- Enables or disables profiling
-- When disabled, profiling calls return immediately (minimal overhead)
-- @param enabled (boolean) True to enable profiling
function PerformanceMonitor:setEnabled(enabled)
  self.enabled = enabled
end

--[[
  ============================================================================
  PROFILING FUNCTIONS
  ============================================================================
]]

--- Starts profiling a named code section
-- Must be paired with endProfile() to record the measurement
-- 
-- @param name (string) Unique name for this profile section
-- @return (number) Start time to pass to endProfile()
-- 
-- Example:
--   local start = PM:startProfile("pathfinding:astar")
--   -- ... pathfinding code ...
--   PM:endProfile("pathfinding:astar", start)
function PerformanceMonitor:startProfile(name)
  -- Early return when disabled - minimal overhead
  if not self.enabled then return 0 end
  
  local startTime = self.getTime()
  
  -- Initialize profile data if first call
  if not self.profiles[name] then
    self.profiles[name] = {
      calls = 0,          -- Number of times profiled
      totalTime = 0,      -- Sum of all durations
      minTime = math_huge,-- Shortest duration seen
      maxTime = 0,        -- Longest duration seen
      avgTime = 0,        -- Running average
      lastStart = startTime
    }
  else
    self.profiles[name].lastStart = startTime
  end
  
  return startTime
end

--- Ends profiling and records the measurement
-- 
-- @param name (string) Profile name (must match startProfile)
-- @param startTime (number) Value returned by startProfile()
-- @return (number) Duration in milliseconds
function PerformanceMonitor:endProfile(name, startTime)
  -- Early return when disabled
  if not self.enabled then return 0 end
  
  local endTime = self.getTime()
  local duration = endTime - startTime
  
  local profile = self.profiles[name]
  if profile then
    profile.calls = profile.calls + 1
    profile.totalTime = profile.totalTime + duration
    profile.minTime = math_min(profile.minTime, duration)
    profile.maxTime = math_max(profile.maxTime, duration)
    profile.avgTime = profile.totalTime / profile.calls
  end
  
  return duration
end

--- Convenience wrapper to profile an entire function call
-- Automatically handles start/end timing
-- 
-- @param name (string) Profile name
-- @param func (function) Function to execute and profile
-- @param ... Arguments to pass to the function
-- @return (any) Function result, (number) Duration in ms
-- 
-- Example:
--   local path, duration = PM:profileFunction("astar", findPath, startPos, endPos)
function PerformanceMonitor:profileFunction(name, func, ...)
  local startTime = self:startProfile(name)
  local result = func(...)
  local duration = self:endProfile(name, startTime)
  
  -- Log slow functions when profiling is enabled
  if self.enabled and duration > 20 then
    print(string_format("[PERF] %s took %dms", name, duration))
  end
  
  return result, duration
end

--[[
  ============================================================================
  STATISTICS & REPORTING
  ============================================================================
]]

--- Gets profile statistics
-- @param name (string|nil) Specific profile name, or nil for all
-- @return (table) Profile data or all profiles
function PerformanceMonitor:getStats(name)
  if name then
    return self.profiles[name]
  end
  return self.profiles
end

--- Generates a formatted performance report
-- Sorted by total time (highest first)
-- 
-- @return (string) Multi-line formatted report
function PerformanceMonitor:getReport()
  local lines = {
    "═══════════════════════════════════════════",
    "         nExBot Performance Report         ",
    "═══════════════════════════════════════════"
  }
  
  -- ========================================
  -- SORT PROFILES BY TOTAL TIME
  -- ========================================
  local sorted = {}
  for name, data in pairs(self.profiles) do
    table_insert(sorted, {name = name, data = data})
  end
  table_sort(sorted, function(a, b)
    return a.data.totalTime > b.data.totalTime
  end)
  
  -- ========================================
  -- FORMAT EACH PROFILE
  -- ========================================
  if #sorted == 0 then
    table_insert(lines, "  No profiles recorded yet")
  else
    table_insert(lines, string_format(
      "%-25s %7s %10s %8s %8s %8s",
      "Name", "Calls", "Total", "Avg", "Min", "Max"
    ))
    table_insert(lines, string.rep("-", 70))
    
    for _, item in ipairs(sorted) do
      local data = item.data
      -- Truncate name if too long
      local displayName = item.name
      if #displayName > 25 then
        displayName = displayName:sub(1, 22) .. "..."
      end
      
      table_insert(lines, string_format(
        "%-25s %7d %9.1fms %7.2fms %7.2fms %7.2fms",
        displayName,
        data.calls,
        data.totalTime,
        data.avgTime,
        data.minTime == math_huge and 0 or data.minTime,
        data.maxTime
      ))
    end
  end
  
  -- ========================================
  -- MEMORY SUMMARY
  -- ========================================
  table_insert(lines, "───────────────────────────────────────────")
  local mem = collectgarbage("count")
  local trend = self:getMemoryTrend()
  table_insert(lines, string_format(
    "Memory: %.2f KB  |  Trend: %+.2f KB/snapshot",
    mem, trend
  ))
  
  table_insert(lines, "═══════════════════════════════════════════")
  
  return table_concat(lines, "\n")
end

--- Resets all collected profile data
function PerformanceMonitor:reset()
  self.profiles = {}
end

--[[
  ============================================================================
  MEMORY TRACKING
  ============================================================================
]]

--- Takes a memory snapshot for trend analysis
-- Call periodically to track memory growth over time
-- 
-- @return (number) Current memory usage in KB
function PerformanceMonitor:trackMemory()
  local mem = collectgarbage("count")
  
  table_insert(self.memorySnapshots, {
    time = os_time(),
    memory = mem
  })
  
  -- ========================================
  -- TRIM OLD SNAPSHOTS
  -- Keep only the most recent maxSnapshots entries
  -- Uses loop instead of single remove for bulk cleanup
  -- ========================================
  while #self.memorySnapshots > self.maxSnapshots do
    table_remove(self.memorySnapshots, 1)
  end
  
  -- Debug output when enabled
  if self.enabled then
    print(string_format("[MEM] Current: %.2f KB", mem))
  end
  
  return mem
end

--- Calculates memory growth trend
-- Positive = memory growing, Negative = memory shrinking
-- 
-- @return (number) Average KB change per snapshot
function PerformanceMonitor:getMemoryTrend()
  local count = #self.memorySnapshots
  if count < 2 then return 0 end
  
  local first = self.memorySnapshots[1].memory
  local last = self.memorySnapshots[count].memory
  
  return (last - first) / count
end

--[[
  ============================================================================
  GARBAGE COLLECTION MANAGEMENT
  ============================================================================
]]

--- Schedules periodic incremental garbage collection
-- Uses step() for minimal pause times (better than full collect)
-- 
-- @param interval (number|nil) Interval in ms (default: 60000)
function PerformanceMonitor:scheduleGC(interval)
  interval = interval or self.gcInterval
  self.gcInterval = interval
  
  -- Store reference to avoid closure issues
  local monitor = self
  
  local function doGC()
    local before = collectgarbage("count")
    -- step() is incremental - smaller pause than collect()
    collectgarbage("step")
    local after = collectgarbage("count")
    
    if monitor.enabled then
      local freed = before - after
      if freed > 0 then
        print(string_format(
          "[GC] Incremental: freed %.2f KB (%.2f -> %.2f)",
          freed, before, after
        ))
      end
    end
    
    monitor.lastGC = now or 0
    schedule(interval, doGC)
  end
  
  schedule(interval, doGC)
end

--- Forces a full garbage collection cycle
-- Use sparingly - causes noticeable pause
-- 
-- @return (number) KB of memory freed
function PerformanceMonitor:forceGC()
  local before = collectgarbage("count")
  collectgarbage("collect")
  local after = collectgarbage("count")
  local freed = before - after
  
  if self.enabled then
    print(string_format(
      "[GC] Full collection: %.2f KB freed (%.2f -> %.2f)", 
      freed, before, after
    ))
  end
  
  return freed
end

--[[
  ============================================================================
  DIAGNOSTICS
  ============================================================================
]]

--- Checks for potential performance issues and memory leaks
-- Returns warnings based on heuristic analysis
-- 
-- @return (table) Array of warning objects
-- 
-- Warning structure:
--   {type = "memory_growth"|"slow_function", severity = "high"|"medium"|"low",
--    name = "...", message = "..."}
function PerformanceMonitor:checkLeaks()
  local warnings = {}
  
  -- ========================================
  -- CHECK MEMORY GROWTH
  -- ========================================
  local trend = self:getMemoryTrend()
  
  if trend > 50 then
    -- Critical: >50KB per snapshot
    table_insert(warnings, {
      type = "memory_growth",
      severity = "critical",
      message = string_format(
        "Critical memory growth: %.2f KB per snapshot - likely leak",
        trend
      )
    })
  elseif trend > 10 then
    -- High: >10KB per snapshot
    table_insert(warnings, {
      type = "memory_growth",
      severity = "high",
      message = string_format(
        "High memory growth: %.2f KB per snapshot - investigate tables",
        trend
      )
    })
  elseif trend > 5 then
    -- Medium: >5KB per snapshot
    table_insert(warnings, {
      type = "memory_growth",
      severity = "medium",
      message = string_format(
        "Moderate memory growth: %.2f KB per snapshot",
        trend
      )
    })
  end
  
  -- ========================================
  -- CHECK SLOW FUNCTIONS
  -- ========================================
  for name, data in pairs(self.profiles) do
    if data.avgTime > self.slowThreshold then
      local severity = "medium"
      if data.avgTime > 100 then
        severity = "critical"
      elseif data.avgTime > 75 then
        severity = "high"
      end
      
      table_insert(warnings, {
        type = "slow_function",
        severity = severity,
        name = name,
        message = string_format(
          "%s: avg %.2fms (calls: %d, max: %.2fms)",
          name, data.avgTime, data.calls, data.maxTime
        )
      })
    end
  end
  
  -- ========================================
  -- CHECK FOR HIGH CALL COUNT
  -- Functions called excessively may indicate inefficiency
  -- ========================================
  for name, data in pairs(self.profiles) do
    if data.calls > 10000 and data.avgTime > 1 then
      table_insert(warnings, {
        type = "high_frequency",
        severity = "low",
        name = name,
        message = string_format(
          "%s called %d times (total: %.2fms) - consider caching",
          name, data.calls, data.totalTime
        )
      })
    end
  end
  
  return warnings
end

--- Gets a summary of current performance health
-- @return (string) "healthy", "warning", or "critical"
function PerformanceMonitor:getHealthStatus()
  local warnings = self:checkLeaks()
  
  for _, w in ipairs(warnings) do
    if w.severity == "critical" then
      return "critical"
    end
  end
  
  for _, w in ipairs(warnings) do
    if w.severity == "high" then
      return "warning"
    end
  end
  
  return "healthy"
end

--[[
  ============================================================================
  MODULE EXPORT
  ============================================================================
]]

return PerformanceMonitor
