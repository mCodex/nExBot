--[[
  ============================================================================
  nExBot Main Entry Point
  ============================================================================
  
  Loads and initializes all modules with optimized loading order.
  
  LOADING ORDER:
  1. Core utilities (nlib.lua) - Provides logging and helpers
  2. Core infrastructure (BotState, ItemCache) - Foundation
  3. Tab modules (Main, Regen, Cave, Target, Tools) - UI
  4. Feature modules (Pathfinding, Combat, etc.) - Optional
  
  TAB ORGANIZATION:
  ─────────────────────────────────────────────────────────────────────────────
  Main:    ComboBot, Friend Healer, PushMax
  Regen:   HealBot, Conditions, Auto Equip
  Cave:    CaveBot, Depositor, Supply Check
  Target:  TargetBot, Creature Editor, Looting
  Tools:   Fishing, Mount, Containers, Dropper, Wave Avoidance
  
  Author: nExBot Team
  Version: 2.0.0 (Optimized)
  Date: December 2025
  
  ============================================================================
]]

local version = "2.0.0"
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
nExBot.ItemCache = nil

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
      BotState = dofile("/nExBot/core/bot_state.lua"),
      ItemCache = dofile("/nExBot/core/item_cache.lua"),
      DistanceCalculator = dofile("/nExBot/core/distance_calculator.lua"),
      PerformanceMonitor = dofile("/nExBot/core/performance_monitor.lua")
    }
    
    -- Initialize core modules (with nil checks)
    nExBot.BotState = nExBot.Core.BotState
    nExBot.ItemCache = nExBot.Core.ItemCache
    
    if nExBot.BotState and nExBot.BotState.initialize then
      nExBot.BotState:initialize()
    end
    
    -- ItemCache auto-starts on player login
    
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
    
    -- Targeting modules (Intelligent TargetBot)
    nExBot.modules.IntelligentTargetBot = dofile("/nExBot/modules/target/intelligent_targetbot.lua")
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
    
    -- Avoidance modules (AI-powered)
    nExBot.modules.WaveAvoidance = dofile("/nExBot/modules/avoidance/wave_avoidance.lua")
    
    log("Feature modules loaded successfully")
  end)
  
  if not success then
    warn("[nExBot] Failed to load feature modules: " .. tostring(err))
    return false
  end
  
  return true
end

-- Load nExBot Design System and styles
local function loadDesignSystem()
  local success, err = pcall(function()
    -- Core design system (must load first)
    importStyle("/nExBot/styles/nexbot_theme.otui")
    
    -- Module-specific styles (extend the design system)
    importStyle("/nExBot/styles/healbot.otui")
    importStyle("/nExBot/styles/attackbot.otui")
    importStyle("/nExBot/styles/extras.otui")
    importStyle("/nExBot/styles/alarms.otui")
    importStyle("/nExBot/styles/supplies.otui")
    importStyle("/nExBot/styles/stashing.otui")
    importStyle("/nExBot/styles/botserver.otui")
    importStyle("/nExBot/styles/tools.otui")
    importStyle("/nExBot/styles/main_tabs.otui")
    
    log("Design system loaded successfully")
  end)
  
  if not success then
    warn("[nExBot] Failed to load design system: " .. tostring(err))
    return false
  end
  
  return true
end

-- Load Tools panel modules
local function loadToolsModules()
  local success, err = pcall(function()
    -- Import styles
    importStyle("/nExBot/modules/tools/tools.otui")
    
    -- Automation and utility modules
    dofile("/nExBot/modules/tools/automation.lua")
    dofile("/nExBot/modules/tools/eat_food.lua")
    dofile("/nExBot/modules/tools/hold_target.lua")
    
    -- Tools modules (consolidated)
    dofile("/nExBot/modules/tools/smart_fishing.lua")
    dofile("/nExBot/modules/tools/smart_mount.lua")
    dofile("/nExBot/modules/tools/containers.lua")
    dofile("/nExBot/modules/tools/dropper.lua")
    
    -- Avoidance UI (uses wave_avoidance.lua engine)
    dofile("/nExBot/modules/avoidance/wave_avoidance_ui.lua")
    
    log("Tools modules loaded successfully")
  end)
  
  if not success then
    warn("[nExBot] Failed to load Tools modules: " .. tostring(err))
    return false
  end
  
  return true
end

-- Load Main tab modules
local function loadMainTabModules()
  local success, err = pcall(function()
    -- Import styles
    importStyle("/nExBot/modules/main/main.otui")
    
    -- Load main tab modules
    dofile("/nExBot/modules/main/alarms.lua")
    dofile("/nExBot/modules/main/attackbot.lua")
    
    -- Load consolidated main tab
    dofile("/nExBot/modules/main/main_tab.lua")
    
    log("Main tab modules loaded successfully")
  end)
  
  if not success then
    warn("[nExBot] Failed to load Main tab modules: " .. tostring(err))
    return false
  end
  
  return true
end

-- Load Regen tab modules
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

-- Load Cave tab modules
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

-- Load Target tab modules (intelligent targeting)
local function loadTargetTabModules()
  local success, err = pcall(function()
    -- Import styles
    importStyle("/nExBot/modules/target/target.otui")
    
    -- Load consolidated target tab with intelligent engine
    dofile("/nExBot/modules/target/target_tab.lua")
    
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
  
  -- Load design system first
  if not loadDesignSystem() then
    warn("[nExBot] Design system failed to load, continuing with default styles")
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
  
  -- Load tab modules
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

nExBot.getState = function()
  return nExBot.BotState
end

--- Gets the Item Cache for inventory management
-- @return (ItemCache) The item cache instance
nExBot.getItemCache = function()
  return nExBot.ItemCache
end

--- Counts items using the intelligent cache (works with closed backpacks)
-- @param itemId (number) Item ID to count
-- @return (number) Total count across all containers
nExBot.countItem = function(itemId)
  if nExBot.ItemCache then
    return nExBot.ItemCache:getItemCount(itemId)
  end
  return itemAmount(itemId)  -- Fallback to standard function
end

--- Uses an item from the cache (works with closed backpacks)
-- @param itemId (number) Item ID to use
-- @param target (Creature|table|nil) Optional target
-- @return (boolean) True if item was used
nExBot.useItem = function(itemId, target)
  if nExBot.ItemCache then
    return nExBot.ItemCache:useItem(itemId, target)
  end
  return false
end

--- Uses a potion on the player (works with closed backpacks)
-- @param itemId (number) Potion item ID
-- @return (boolean) True if potion was used
nExBot.usePotion = function(itemId)
  if nExBot.ItemCache then
    return nExBot.ItemCache:usePotion(itemId)
  end
  return false
end

--- Uses a rune on a target (works with closed backpacks)
-- @param itemId (number) Rune item ID
-- @param target (Creature) Target creature
-- @return (boolean) True if rune was used
nExBot.useRune = function(itemId, target)
  if nExBot.ItemCache then
    return nExBot.ItemCache:useRune(itemId, target)
  end
  return false
end

--- Checks if an item exists in any container
-- @param itemId (number) Item ID to check
-- @return (boolean) True if item exists
nExBot.hasItem = function(itemId)
  if nExBot.ItemCache then
    return nExBot.ItemCache:hasItem(itemId)
  end
  return itemAmount(itemId) > 0
end

--- Refreshes the item cache (forces full rescan)
nExBot.refreshItemCache = function()
  if nExBot.ItemCache then
    nExBot.ItemCache:refresh()
  end
end

--- Gets item cache statistics
-- @return (table) Cache statistics
nExBot.getItemCacheStats = function()
  if nExBot.ItemCache then
    return nExBot.ItemCache:getStats()
  end
  return {}
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
