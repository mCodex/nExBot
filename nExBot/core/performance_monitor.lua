--[[
  nExBot Performance Monitor
  Tools for profiling and monitoring bot performance
  
  Author: nExBot Team
  Version: 1.0.0
]]

local PerformanceMonitor = {
  profiles = {},
  enabled = false,
  memorySnapshots = {},
  gcInterval = 60000,  -- 60 seconds
  lastGC = 0
}

-- Initialize the performance monitor
function PerformanceMonitor:initialize()
  self.profiles = {}
  self.memorySnapshots = {}
  self.lastGC = now or 0
  return self
end

-- Enable/disable profiling
function PerformanceMonitor:setEnabled(enabled)
  self.enabled = enabled
end

-- Start profiling a function/section
-- @param name string - Name of the section being profiled
-- @return number - Start time
function PerformanceMonitor:startProfile(name)
  if not self.enabled then return 0 end
  
  local startTime = g_clock and g_clock.millis() or os.time() * 1000
  
  if not self.profiles[name] then
    self.profiles[name] = {
      calls = 0,
      totalTime = 0,
      minTime = math.huge,
      maxTime = 0,
      avgTime = 0,
      lastStart = startTime
    }
  else
    self.profiles[name].lastStart = startTime
  end
  
  return startTime
end

-- End profiling a function/section
-- @param name string - Name of the section
-- @param startTime number - Start time from startProfile
-- @return number - Duration in milliseconds
function PerformanceMonitor:endProfile(name, startTime)
  if not self.enabled then return 0 end
  
  local endTime = g_clock and g_clock.millis() or os.time() * 1000
  local duration = endTime - startTime
  
  local profile = self.profiles[name]
  if profile then
    profile.calls = profile.calls + 1
    profile.totalTime = profile.totalTime + duration
    profile.minTime = math.min(profile.minTime, duration)
    profile.maxTime = math.max(profile.maxTime, duration)
    profile.avgTime = profile.totalTime / profile.calls
  end
  
  return duration
end

-- Profile a function call
-- @param name string - Name for the profile
-- @param func function - Function to profile
-- @param ... - Arguments to pass to the function
-- @return any - Result of the function, plus duration
function PerformanceMonitor:profileFunction(name, func, ...)
  local startTime = self:startProfile(name)
  local result = func(...)
  local duration = self:endProfile(name, startTime)
  
  if self.enabled then
    print(string.format("[PERF] %s took %dms", name, duration))
  end
  
  return result, duration
end

-- Get profile statistics
-- @param name string (optional) - Specific profile name
-- @return table - Profile statistics
function PerformanceMonitor:getStats(name)
  if name then
    return self.profiles[name]
  end
  return self.profiles
end

-- Get formatted report
-- @return string - Formatted performance report
function PerformanceMonitor:getReport()
  local lines = {"=== nExBot Performance Report ==="}
  
  -- Sort by total time
  local sorted = {}
  for name, data in pairs(self.profiles) do
    table.insert(sorted, {name = name, data = data})
  end
  table.sort(sorted, function(a, b)
    return a.data.totalTime > b.data.totalTime
  end)
  
  for _, item in ipairs(sorted) do
    local data = item.data
    table.insert(lines, string.format(
      "%s: calls=%d, total=%.2fms, avg=%.2fms, min=%.2fms, max=%.2fms",
      item.name,
      data.calls,
      data.totalTime,
      data.avgTime,
      data.minTime,
      data.maxTime
    ))
  end
  
  -- Memory info
  local mem = collectgarbage("count")
  table.insert(lines, string.format("Memory: %.2f KB", mem))
  
  return table.concat(lines, "\n")
end

-- Reset all profiles
function PerformanceMonitor:reset()
  self.profiles = {}
end

-- Track memory usage
function PerformanceMonitor:trackMemory()
  local mem = collectgarbage("count")
  table.insert(self.memorySnapshots, {
    time = os.time(),
    memory = mem
  })
  
  -- Keep only last 100 snapshots
  while #self.memorySnapshots > 100 do
    table.remove(self.memorySnapshots, 1)
  end
  
  if self.enabled then
    print(string.format("[MEM] Current: %.2f KB", mem))
  end
  
  return mem
end

-- Get memory trend
-- @return number - Average memory change per snapshot
function PerformanceMonitor:getMemoryTrend()
  if #self.memorySnapshots < 2 then return 0 end
  
  local first = self.memorySnapshots[1].memory
  local last = self.memorySnapshots[#self.memorySnapshots].memory
  
  return (last - first) / #self.memorySnapshots
end

-- Schedule periodic garbage collection
function PerformanceMonitor:scheduleGC(interval)
  interval = interval or self.gcInterval
  self.gcInterval = interval
  
  local self_ref = self
  local function doGC()
    local before = collectgarbage("count")
    collectgarbage("step")
    local after = collectgarbage("count")
    
    if self_ref.enabled then
      print(string.format("[GC] Collected %.2f KB (%.2f -> %.2f)", before - after, before, after))
    end
    
    self_ref.lastGC = now or 0
    schedule(interval, doGC)
  end
  
  schedule(interval, doGC)
end

-- Force full garbage collection
function PerformanceMonitor:forceGC()
  local before = collectgarbage("count")
  collectgarbage("collect")
  local after = collectgarbage("count")
  
  if self.enabled then
    print(string.format("[GC] Full collection: %.2f KB freed (%.2f -> %.2f)", 
      before - after, before, after))
  end
  
  return before - after
end

-- Check for potential memory leaks
-- @return table - Suspected leak locations
function PerformanceMonitor:checkLeaks()
  local trend = self:getMemoryTrend()
  local warnings = {}
  
  if trend > 10 then  -- More than 10KB average growth per snapshot
    table.insert(warnings, {
      type = "memory_growth",
      severity = "high",
      message = string.format("High memory growth detected: %.2f KB per snapshot", trend)
    })
  end
  
  -- Check for profiles with excessive time
  for name, data in pairs(self.profiles) do
    if data.avgTime > 50 then  -- More than 50ms average
      table.insert(warnings, {
        type = "slow_function",
        severity = "medium",
        name = name,
        message = string.format("%s has high average time: %.2fms", name, data.avgTime)
      })
    end
  end
  
  return warnings
end

return PerformanceMonitor
