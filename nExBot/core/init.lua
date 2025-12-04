--[[
  NexBot Core Module
  Central initialization for all core components
  
  Author: NexBot Team
  Version: 1.0.0
  Date: December 2025
]]

local Core = {}

-- Load core modules
Core.EventBus = dofile("/NexBot/core/event_bus.lua")
Core.BotState = dofile("/NexBot/core/bot_state.lua")
Core.DistanceCalculator = dofile("/NexBot/core/distance_calculator.lua")
Core.PerformanceMonitor = dofile("/NexBot/core/performance_monitor.lua")

-- Initialize all core components
function Core.initialize()
  Core.EventBus:initialize()
  Core.BotState:initialize()
  return Core
end

return Core
