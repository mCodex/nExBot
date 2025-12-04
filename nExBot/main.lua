--[[
  NexBot Main Entry Point
  Loads and initializes all modules
  
  Author: NexBot Team
  Version: 1.0.0
  Date: December 2025
]]

local version = "1.0.0"
local currentVersion
local available = false

-- Initialize global NexBot namespace
NexBot = {
  version = version,
  modules = {},
  initialized = false
}

-- Module references
NexBot.Core = nil
NexBot.EventBus = nil
NexBot.BotState = nil

-- Storage check and initialization
storage.checkVersion = storage.checkVersion or 0

-- Version check (once per 12 hours)
if os.time() > storage.checkVersion + (12 * 60 * 60) then
  storage.checkVersion = os.time()
  
  -- Note: Update URL for your repository
  -- HTTP.get("https://raw.githubusercontent.com/mcodex/NexBot/main/NexBot/version.txt", function(data, err)
  --   if err then
  --     warn("[NexBot updater]: Unable to check version:\n" .. err)
  --     return
  --   end
  --   currentVersion = data
  --   available = true
  -- end)
end

-- Display header
UI.Label("NexBot v".. version .." - Advanced Bot Framework")
UI.Button("Join Discord Community", function() 
  g_platform.openUrl("https://discord.gg/yhqBE4A") 
end)
UI.Separator()

-- Load core modules
local function loadCoreModules()
  local success, err = pcall(function()
    -- Load core infrastructure
    NexBot.Core = {
      EventBus = dofile("/NexBot/core/event_bus.lua"),
      BotState = dofile("/NexBot/core/bot_state.lua"),
      DistanceCalculator = dofile("/NexBot/core/distance_calculator.lua"),
      PerformanceMonitor = dofile("/NexBot/core/performance_monitor.lua")
    }
    
    -- Initialize core modules
    NexBot.EventBus = NexBot.Core.EventBus
    NexBot.BotState = NexBot.Core.BotState
    
    NexBot.EventBus:initialize()
    NexBot.BotState:initialize()
    
    logInfo("NexBot core modules loaded successfully")
  end)
  
  if not success then
    warn("[NexBot] Failed to load core modules: " .. tostring(err))
    return false
  end
  
  return true
end

-- Load feature modules
local function loadFeatureModules()
  local success, err = pcall(function()
    -- Combat modules
    NexBot.modules.AutoHaste = dofile("/NexBot/modules/combat/auto_haste.lua")
    NexBot.modules.SpellRegistry = dofile("/NexBot/modules/combat/spell_registry.lua")
    
    -- Pathfinding modules
    NexBot.modules.PathCache = dofile("/NexBot/modules/pathfinding/path_cache.lua")
    NexBot.modules.OptimizedAStar = dofile("/NexBot/modules/pathfinding/optimized_astar.lua")
    
    -- Luring modules
    NexBot.modules.LuringPatterns = dofile("/NexBot/modules/luring/luring_patterns.lua")
    NexBot.modules.CreatureTracker = dofile("/NexBot/modules/luring/creature_tracker.lua")
    NexBot.modules.LuringManager = dofile("/NexBot/modules/luring/luring_manager.lua")
    
    -- Targeting modules
    NexBot.modules.PriorityTargetManager = dofile("/NexBot/modules/targeting/priority_target_manager.lua")
    NexBot.modules.DynamicSpellSelector = dofile("/NexBot/modules/targeting/dynamic_spell_selector.lua")
    
    -- Memory modules
    NexBot.modules.ObjectPool = dofile("/NexBot/modules/memory/object_pool.lua")
    NexBot.modules.WeakReferenceTracker = dofile("/NexBot/modules/memory/weak_reference_tracker.lua")
    
    -- AI Waypoint modules
    NexBot.modules.WaypointRecorder = dofile("/NexBot/modules/waypoints/waypoint_recorder.lua")
    NexBot.modules.AutoDiscovery = dofile("/NexBot/modules/waypoints/auto_discovery.lua")
    NexBot.modules.RouteOptimizer = dofile("/NexBot/modules/waypoints/route_optimizer.lua")
    NexBot.modules.PathPredictor = dofile("/NexBot/modules/waypoints/path_predictor.lua")
    NexBot.modules.WaypointClustering = dofile("/NexBot/modules/waypoints/waypoint_clustering.lua")
    NexBot.modules.AutoRouteGenerator = dofile("/NexBot/modules/waypoints/auto_route_generator.lua")
    
    -- Survival modules
    NexBot.modules.EatFood = dofile("/NexBot/modules/survival/eat_food.lua")
    
    -- Container modules
    NexBot.modules.ContainerManager = dofile("/NexBot/modules/container/container_manager.lua")
    
    -- Loot modules
    NexBot.modules.CorpseLoot = dofile("/NexBot/modules/loot/corpse_looting.lua")
    NexBot.modules.SkinningManager = dofile("/NexBot/modules/loot/skinning_manager.lua")
    
    -- Movement modules
    NexBot.modules.DoorAutomation = dofile("/NexBot/modules/movement/door_automation.lua")
    
    logInfo("NexBot feature modules loaded successfully")
  end)
  
  if not success then
    warn("[NexBot] Failed to load feature modules: " .. tostring(err))
    return false
  end
  
  return true
end

-- Initialize the bot
local function initializeNexBot()
  if NexBot.initialized then
    return true
  end
  
  -- Load core
  if not loadCoreModules() then
    return false
  end
  
  -- Load features
  if not loadFeatureModules() then
    -- Continue anyway, core features should work
    warn("[NexBot] Some feature modules failed to load, continuing with available modules")
  end
  
  -- Emit initialization event
  NexBot.EventBus:emit(NexBot.EventBus.Events.MODULE_ENABLED, "NexBot", version)
  
  NexBot.initialized = true
  logInfo("NexBot initialization complete")
  
  return true
end

-- Public API
NexBot.getModule = function(name)
  return NexBot.modules[name]
end

NexBot.isInitialized = function()
  return NexBot.initialized
end

NexBot.getVersion = function()
  return version
end

NexBot.getEventBus = function()
  return NexBot.EventBus
end

NexBot.getState = function()
  return NexBot.BotState
end

-- Initialize
initializeNexBot()

-- Schedule update check display
schedule(5000, function()
  if available and currentVersion and currentVersion ~= version then
    UI.Separator()
    UI.Label("New NexBot version available: v"..currentVersion)
    UI.Button("Download Update", function() 
      g_platform.openUrl("https://github.com/YOUR_USERNAME/NexBot") 
    end)
    UI.Separator()
  end
end)
