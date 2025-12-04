--[[
  nExBot Core Module
  Central initialization for all core components
  
  Author: nExBot Team
  Version: 1.0.0
  Date: December 2025
]]

local Core = {}

-- Load core modules
Core.EventBus = dofile("/nExBot/core/event_bus.lua")
Core.BotState = dofile("/nExBot/core/bot_state.lua")
Core.DistanceCalculator = dofile("/nExBot/core/distance_calculator.lua")
Core.PerformanceMonitor = dofile("/nExBot/core/performance_monitor.lua")

-- Initialize all core components
function Core.initialize()
  Core.EventBus:initialize()
  Core.BotState:initialize()
  return Core
end

return Core
