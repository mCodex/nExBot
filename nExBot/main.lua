--[[
  nExBot Main Entry Point
  Loads and initializes all modules
  
  Author: nExBot Team
  Version: 1.0.0
  Date: December 2025
]]

local version = "1.0.0"
local currentVersion
local available = false

-- Safe logging helper (uses logInfo if available, otherwise print)
local function log(message)
  if logInfo then
    logInfo(message)
  elseif print then
    print("[nExBot] " .. message)
  end
end

-- Initialize global nExBot namespace
nExBot = {
  version = version,
  modules = {},
  initialized = false
}

-- Module references
nExBot.Core = nil
nExBot.EventBus = nil
nExBot.BotState = nil

-- Storage check and initialization
storage.checkVersion = storage.checkVersion or 0

-- Version check (once per 12 hours)
if os.time() > storage.checkVersion + (12 * 60 * 60) then
  storage.checkVersion = os.time()
end

-- Display header
UI.Label("nExBot v".. version .." - Advanced Bot Framework")
UI.Separator()

-- Load core modules
local function loadCoreModules()
  local success, err = pcall(function()
    -- Load nlib first (provides logInfo and other utility functions)
    dofile("/nExBot/core/nlib.lua")
    
    -- Load core infrastructure
    nExBot.Core = {
      EventBus = dofile("/nExBot/core/event_bus.lua"),
      BotState = dofile("/nExBot/core/bot_state.lua"),
      DistanceCalculator = dofile("/nExBot/core/distance_calculator.lua"),
      PerformanceMonitor = dofile("/nExBot/core/performance_monitor.lua")
    }
    
    -- Initialize core modules (with nil checks)
    nExBot.EventBus = nExBot.Core.EventBus
    nExBot.BotState = nExBot.Core.BotState
    
    if nExBot.EventBus and nExBot.EventBus.initialize then
      nExBot.EventBus:initialize()
    end
    
    if nExBot.BotState and nExBot.BotState.initialize then
      nExBot.BotState:initialize()
    end
    
    log("Core modules loaded successfully")
  end)
  
  if not success then
    warn("[nExBot] Failed to load core modules: " .. tostring(err))
    return false
  end
  
  return true
end

-- Load feature modules
local function loadFeatureModules()
  local success, err = pcall(function()
    -- Combat modules
    nExBot.modules.AutoHaste = dofile("/nExBot/modules/combat/auto_haste.lua")
    nExBot.modules.SpellRegistry = dofile("/nExBot/modules/combat/spell_registry.lua")
    
    -- Pathfinding modules
    nExBot.modules.PathCache = dofile("/nExBot/modules/pathfinding/path_cache.lua")
    nExBot.modules.OptimizedAStar = dofile("/nExBot/modules/pathfinding/optimized_astar.lua")
    
    -- Luring modules
    nExBot.modules.LuringPatterns = dofile("/nExBot/modules/luring/luring_patterns.lua")
    nExBot.modules.CreatureTracker = dofile("/nExBot/modules/luring/creature_tracker.lua")
    nExBot.modules.LuringManager = dofile("/nExBot/modules/luring/luring_manager.lua")
    
    -- Targeting modules
    nExBot.modules.PriorityTargetManager = dofile("/nExBot/modules/targeting/priority_target_manager.lua")
    nExBot.modules.DynamicSpellSelector = dofile("/nExBot/modules/targeting/dynamic_spell_selector.lua")
    
    -- Memory modules
    nExBot.modules.ObjectPool = dofile("/nExBot/modules/memory/object_pool.lua")
    nExBot.modules.WeakReferenceTracker = dofile("/nExBot/modules/memory/weak_reference_tracker.lua")
    
    -- AI Waypoint modules
    nExBot.modules.WaypointRecorder = dofile("/nExBot/modules/waypoints/waypoint_recorder.lua")
    nExBot.modules.AutoDiscovery = dofile("/nExBot/modules/waypoints/auto_discovery.lua")
    nExBot.modules.RouteOptimizer = dofile("/nExBot/modules/waypoints/route_optimizer.lua")
    nExBot.modules.PathPredictor = dofile("/nExBot/modules/waypoints/path_predictor.lua")
    nExBot.modules.WaypointClustering = dofile("/nExBot/modules/waypoints/waypoint_clustering.lua")
    nExBot.modules.AutoRouteGenerator = dofile("/nExBot/modules/waypoints/auto_route_generator.lua")
    
    -- Survival modules
    nExBot.modules.EatFood = dofile("/nExBot/modules/survival/eat_food.lua")
    
    -- Container modules
    nExBot.modules.ContainerManager = dofile("/nExBot/modules/container/container_manager.lua")
    
    -- Loot modules
    nExBot.modules.CorpseLoot = dofile("/nExBot/modules/loot/corpse_looting.lua")
    nExBot.modules.SkinningManager = dofile("/nExBot/modules/loot/skinning_manager.lua")
    
    -- Movement modules
    nExBot.modules.DoorAutomation = dofile("/nExBot/modules/movement/door_automation.lua")
    
    log("Feature modules loaded successfully")
  end)
  
  if not success then
    warn("[nExBot] Failed to load feature modules: " .. tostring(err))
    return false
  end
  
  return true
end

-- Load Tools panel modules
local function loadToolsModules()
  local success, err = pcall(function()
    -- Import styles
    importStyle("/nExBot/modules/tools/tools.otui")
    
    -- Tools modules
    dofile("/nExBot/modules/tools/smart_fishing.lua")
    dofile("/nExBot/modules/tools/smart_mount.lua")
    dofile("/nExBot/modules/tools/containers.lua")
    dofile("/nExBot/modules/tools/dropper.lua")
    dofile("/nExBot/modules/tools/extras.lua")
    
    -- Avoidance modules (AI-powered)
    dofile("/nExBot/modules/avoidance/wave_avoidance_ui.lua")
    
    log("Tools modules loaded successfully")
  end)
  
  if not success then
    warn("[nExBot] Failed to load Tools modules: " .. tostring(err))
    return false
  end
  
  return true
end

-- Load Main tab modules (vBot-style)
local function loadMainTabModules()
  local success, err = pcall(function()
    -- Import styles
    importStyle("/nExBot/modules/main/main.otui")
    
    -- Main tab modules
    dofile("/nExBot/modules/main/combo_bot.lua")
    dofile("/nExBot/modules/main/friend_healer.lua")
    dofile("/nExBot/modules/main/pushmax.lua")
    
    log("Main tab modules loaded successfully")
  end)
  
  if not success then
    warn("[nExBot] Failed to load Main tab modules: " .. tostring(err))
    return false
  end
  
  return true
end

-- Load Regen tab modules (vBot-style)
local function loadRegenTabModules()
  local success, err = pcall(function()
    -- Import styles
    importStyle("/nExBot/modules/regen/regen.otui")
    
    -- Regen tab modules
    dofile("/nExBot/modules/regen/healbot.lua")
    dofile("/nExBot/modules/regen/auto_equip.lua")
    
    log("Regen tab modules loaded successfully")
  end)
  
  if not success then
    warn("[nExBot] Failed to load Regen tab modules: " .. tostring(err))
    return false
  end
  
  return true
end

-- Load Cave tab modules (vBot-style)
local function loadCaveTabModules()
  local success, err = pcall(function()
    -- Import styles
    importStyle("/nExBot/modules/cave/cave.otui")
    
    -- Cave tab modules (main cavebot must be loaded first)
    dofile("/nExBot/modules/cave/cavebot.lua")
    
    log("Cave tab modules loaded successfully")
  end)
  
  if not success then
    warn("[nExBot] Failed to load Cave tab modules: " .. tostring(err))
    return false
  end
  
  return true
end

-- Load Target tab modules (vBot-style)
local function loadTargetTabModules()
  local success, err = pcall(function()
    -- Import styles
    importStyle("/nExBot/modules/target/target.otui")
    
    -- Target tab modules (main targetbot loads creature editor and looting)
    dofile("/nExBot/modules/target/targetbot.lua")
    
    log("Target tab modules loaded successfully")
  end)
  
  if not success then
    warn("[nExBot] Failed to load Target tab modules: " .. tostring(err))
    return false
  end
  
  return true
end

-- Initialize the bot
local function initializenExBot()
  if nExBot.initialized then
    return true
  end
  
  -- Load core
  if not loadCoreModules() then
    return false
  end
  
  -- Load features
  if not loadFeatureModules() then
    -- Continue anyway, core features should work
    warn("[nExBot] Some feature modules failed to load, continuing with available modules")
  end
  
  -- Load vBot-style tab modules
  if not loadMainTabModules() then
    warn("[nExBot] Some Main tab modules failed to load, continuing with available modules")
  end
  
  if not loadRegenTabModules() then
    warn("[nExBot] Some Regen tab modules failed to load, continuing with available modules")
  end
  
  if not loadCaveTabModules() then
    warn("[nExBot] Some Cave tab modules failed to load, continuing with available modules")
  end
  
  if not loadTargetTabModules() then
    warn("[nExBot] Some Target tab modules failed to load, continuing with available modules")
  end
  
  -- Load tools panel modules
  if not loadToolsModules() then
    warn("[nExBot] Some Tools modules failed to load, continuing with available modules")
  end
  
  -- Emit initialization event (only if EventBus loaded successfully)
  if nExBot.EventBus then
    nExBot.EventBus:emit(nExBot.EventBus.Events.MODULE_ENABLED, "nExBot", version)
  end
  
  nExBot.initialized = true
  log("Initialization complete")
  
  return true
end

-- Public API
nExBot.getModule = function(name)
  return nExBot.modules[name]
end

nExBot.isInitialized = function()
  return nExBot.initialized
end

nExBot.getVersion = function()
  return version
end

nExBot.getEventBus = function()
  return nExBot.EventBus
end

nExBot.getState = function()
  return nExBot.BotState
end

-- Initialize
initializenExBot()

-- Schedule update check display
schedule(5000, function()
  if available and currentVersion and currentVersion ~= version then
    UI.Separator()
    UI.Label("New nExBot version available: v"..currentVersion)
    UI.Button("Download Update", function() 
      g_platform.openUrl("https://github.com/YOUR_USERNAME/nExBot") 
    end)
    UI.Separator()
  end
end)
