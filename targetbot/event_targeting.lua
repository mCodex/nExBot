--[[
  Event-Driven Targeting System v2.0
  
  High-performance monster detection and targeting using EventBus.
  IMPROVED: More accurate monster counting using direct g_map API calls.
  
  Features:
  - Instant monster detection when creatures appear on screen
  - ACCURATE monster counting using g_map.getSpectators directly
  - Path validation for reachable targets (uses existing pathfinding)
  - Automatic target acquisition for monsters in targetbot config
  - Smooth chase integration using MovementCoordinator
  - CaveBot pause coordination (respects dynamicLure/smartPull)
  - O(1) lookups with optimized caching
  
  Architecture:
  - EventTargeting.LiveMonsterCount: Direct API count (most accurate)
  - EventTargeting.Cache: Fast creature tracking with LRU eviction
  - EventTargeting.PathValidator: Validates reachability
  - EventTargeting.TargetAcquisition: Instant target selection
  - EventTargeting.CombatCoordinator: CaveBot integration
]]

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

EventTargeting = EventTargeting or {}
EventTargeting.VERSION = "2.0"
EventTargeting.DEBUG = false

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================

local SafeCall = SafeCall or require("core.safe_call")

-- ============================================================================
-- CONSTANTS (Tunable for performance)
-- ============================================================================

EventTargeting.CONSTANTS = {
  -- Detection range (tiles from player) - matches visible screen
  DETECTION_RANGE = 8,            -- 8 tiles = visible screen area
  
  -- Maximum distance to chase a target
  MAX_CHASE_RANGE = 10,
  
  -- Path validation settings
  PATH_CACHE_TTL = 200,           -- Path valid for 200ms (faster invalidation)
  PATH_MAX_LENGTH = 15,           -- Max path length to consider reachable
  
  -- Target acquisition timing
  ACQUISITION_COOLDOWN = 50,      -- Reduced from 100ms for faster targeting
  INSTANT_ATTACK_THRESHOLD = 5,   -- Attack immediately if within this range
  
  -- Cache settings
  CREATURE_CACHE_SIZE = 100,      -- Increased for larger spawns
  CREATURE_CACHE_TTL = 3000,      -- Reduced to 3s for faster cleanup
  
  -- Combat coordination
  COMBAT_PAUSE_DURATION = 300,    -- How long to pause CaveBot when engaging
  LURE_CHECK_INTERVAL = 150,      -- Faster lure checks (was 250)
  
  -- Performance thresholds
  MAX_PROCESS_PER_TICK = 10,      -- Increased for faster processing
  DEBOUNCE_INTERVAL = 25,         -- Reduced from 50ms for faster response
  
  -- LIVE COUNTING - uses direct API for accuracy
  LIVE_COUNT_INTERVAL = 100,      -- How often to refresh live count
  LIVE_COUNT_RANGE = 8            -- Range for live monster counting
}

local CONST = EventTargeting.CONSTANTS

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================

-- Fast creature cache with path info
local creatureCache = {
  entries = {},           -- {id -> {creature, path, pathTime, priority, config, lastSeen}}
  count = 0,
  accessOrder = {},       -- LRU tracking
  lastCleanup = 0,
  CLEANUP_INTERVAL = 1500
}

-- Target state
local targetState = {
  currentTarget = nil,
  currentTargetId = nil,
  lastAcquisition = 0,
  pendingTargets = {},    -- Queue of targets to evaluate
  combatActive = false,
  lastCombatCheck = 0
}

-- Cached player reference
local player = g_game and g_game.getLocalPlayer() or nil

-- Path validation parameters (reuse to avoid allocations)
local PATH_PARAMS = {
  ignoreLastCreature = true,
  ignoreNonPathable = true,
  ignoreCost = true,
  ignoreCreatures = true
}

-- ============================================================================
-- LIVE MONSTER COUNTING (Direct API - Most Accurate)
-- Uses g_map.getSpectators/getSpectatorsInRange directly for accurate counting
-- This bypasses the cache which may have stale data
-- ============================================================================

local liveMonsterState = {
  count = 0,              -- Live count from direct API call
  lastUpdate = 0,         -- When we last updated
  creatures = {},         -- Array of live monster references
  oldTibia = g_game and g_game.getClientVersion and g_game.getClientVersion() < 960 or false
}

-- Check if a creature is a targetable monster (not summon)
local function isTargetableMonster(creature)
  if not creature then return false end
  
  -- Check basic conditions
  local ok, isDead = pcall(function() return creature:isDead() end)
  if ok and isDead then return false end
  
  local ok2, isMonster = pcall(function() return creature:isMonster() end)
  if not ok2 or not isMonster then return false end
  
  -- Health check - skip dead monsters
  local okHp, hp = pcall(function() return creature:getHealthPercent() end)
  if okHp and hp and hp <= 0 then return false end
  
  -- For old Tibia, all monsters are targetable
  if liveMonsterState.oldTibia then return true end
  
  -- For new Tibia, check creature type to exclude other player's summons
  local okType, creatureType = pcall(function() return creature:getType() end)
  if okType and creatureType then
    -- Type 0 = player, 1 = monster, 2 = NPC, 3+ = summons
    return creatureType < 3
  end
  
  return true  -- Default to true if we can't determine type
end

-- Get live count of targetable monsters using direct API
-- This is the AUTHORITATIVE count - always accurate
function EventTargeting.getLiveMonsterCount()
  local currentTime = now or (os.time() * 1000)
  
  -- Update cached player reference
  if not player or not player:getPosition() then
    player = g_game and g_game.getLocalPlayer() or player
  end
  if not player then return 0, {} end
  
  local playerPos = player:getPosition()
  if not playerPos then return 0, {} end
  
  -- Only refresh if interval elapsed (but with a short interval for accuracy)
  if (currentTime - liveMonsterState.lastUpdate) < CONST.LIVE_COUNT_INTERVAL then
    return liveMonsterState.count, liveMonsterState.creatures
  end
  
  -- Get creatures using the most reliable API available
  local creatures = nil
  local range = CONST.LIVE_COUNT_RANGE
  
  -- Try getSpectatorsInRange first (most common)
  if g_map and g_map.getSpectatorsInRange then
    creatures = g_map.getSpectatorsInRange(playerPos, false, range, range)
  elseif g_map and g_map.getSpectators then
    creatures = g_map.getSpectators(playerPos, false)
  end
  
  if not creatures then
    return liveMonsterState.count, liveMonsterState.creatures
  end
  
  -- Count targetable monsters on same floor
  local count = 0
  local monsters = {}
  local playerZ = playerPos.z
  
  for i = 1, #creatures do
    local creature = creatures[i]
    if isTargetableMonster(creature) then
      local okPos, cpos = pcall(function() return creature:getPosition() end)
      if okPos and cpos and cpos.z == playerZ then
        count = count + 1
        monsters[#monsters + 1] = creature
      end
    end
  end
  
  -- Update state
  liveMonsterState.count = count
  liveMonsterState.creatures = monsters
  liveMonsterState.lastUpdate = currentTime
  
  return count, monsters
end

-- Check if there are ANY monsters on screen (fast check)
function EventTargeting.hasAnyMonsters()
  local count = EventTargeting.getLiveMonsterCount()
  return count > 0
end

-- Force refresh of live count (useful after events)
function EventTargeting.refreshLiveCount()
  liveMonsterState.lastUpdate = 0
  return EventTargeting.getLiveMonsterCount()
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Chebyshev distance (O(1))
local function chebyshev(p1, p2)
  if not p1 or not p2 then return 999 end
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

-- Manhattan distance (O(1))
local function manhattan(p1, p2)
  if not p1 or not p2 then return 999 end
  return math.abs(p1.x - p2.x) + math.abs(p1.y - p2.y)
end

-- Check if creature is on same floor
local function sameFloor(p1, p2)
  return p1 and p2 and p1.z == p2.z
end

-- Update player reference (on relogin)
local function updatePlayerRef()
  player = g_game and g_game.getLocalPlayer() or player
end

-- ============================================================================
-- FLOOR CHANGE DETECTION (Prevents chasing across stairs/ropes)
-- ============================================================================

-- Floor-change items (subset for performance)
local FLOOR_CHANGE_ITEMS = {
  [414]=true,[415]=true,[416]=true,[417]=true,[428]=true,[429]=true,[430]=true,[431]=true,
  [432]=true,[433]=true,[434]=true,[435]=true,[1949]=true,[1950]=true,[1951]=true,[1952]=true,
  [1219]=true,[1386]=true,[3678]=true,[5543]=true,[384]=true,[386]=true,[418]=true,
  [294]=true,[369]=true,[370]=true,[383]=true,[392]=true,[408]=true,[409]=true,[410]=true,
}

local FLOOR_CHANGE_COLORS = {
  [210] = true, [211] = true, [212] = true, [213] = true,
}

-- Check if position is a floor-change tile
local function isFloorChangeTile(pos)
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isFloorChangeTile then
    return TargetCore.PathSafety.isFloorChangeTile(pos)
  end
  if not pos then return false end
  local color = g_map.getMinimapColor(pos)
  if FLOOR_CHANGE_COLORS[color] then return true end
  local tile = g_map.getTile(pos)
  if not tile then return false end
  local ground = tile:getGround()
  if ground and FLOOR_CHANGE_ITEMS[ground:getId()] then return true end
  local topUse = tile:getTopUseThing()
  if topUse and topUse:isItem() and FLOOR_CHANGE_ITEMS[topUse:getId()] then return true end
  return false
end

-- ============================================================================
-- CACHE MANAGEMENT
-- ============================================================================

-- Touch entry (move to end of LRU)
local function touchEntry(id)
  local order = creatureCache.accessOrder
  for i = #order, 1, -1 do
    if order[i] == id then
      table.remove(order, i)
      break
    end
  end
  order[#order + 1] = id
end

-- Evict oldest entries when over capacity
local function evictOldEntries()
  local order = creatureCache.accessOrder
  while #order > CONST.CREATURE_CACHE_SIZE do
    local oldestId = table.remove(order, 1)
    if creatureCache.entries[oldestId] then
      creatureCache.entries[oldestId] = nil
      creatureCache.count = creatureCache.count - 1
    end
  end
end

-- Cleanup stale entries (improved with safe API calls)
local function cleanupCache()
  if now - creatureCache.lastCleanup < creatureCache.CLEANUP_INTERVAL then
    return
  end
  
  local cutoff = now - CONST.CREATURE_CACHE_TTL
  local newEntries = {}
  local newOrder = {}
  local count = 0
  
  for i = 1, #creatureCache.accessOrder do
    local id = creatureCache.accessOrder[i]
    local entry = creatureCache.entries[id]
    if entry and entry.lastSeen > cutoff then
      local creature = entry.creature
      -- Safe dead check
      local okDead, isDead = pcall(function() return creature and creature:isDead() end)
      if creature and (not okDead or not isDead) then
        newEntries[id] = entry
        newOrder[#newOrder + 1] = id
        count = count + 1
      end
    end
  end
  
  creatureCache.entries = newEntries
  creatureCache.accessOrder = newOrder
  creatureCache.count = count
  creatureCache.lastCleanup = now
end

-- ============================================================================
-- PATH VALIDATION
-- ============================================================================

EventTargeting.PathValidator = {}

-- Check if path is valid and within range
-- Returns: path, pathLength, isReachable
function EventTargeting.PathValidator.validate(playerPos, targetPos)
  if not playerPos or not targetPos then
    return nil, 999, false
  end
  
  -- Must be on same floor
  if playerPos.z ~= targetPos.z then
    return nil, 999, false
  end
  
  -- Check if target is on a floor-change tile (don't chase there)
  if isFloorChangeTile(targetPos) then
    return nil, 999, false
  end
  
  -- Check if adjacent (no path needed)
  local dist = chebyshev(playerPos, targetPos)
  if dist <= 1 then
    return {}, 0, true
  end
  
  -- Check if too far
  if dist > CONST.MAX_CHASE_RANGE then
    return nil, dist, false
  end
  
  -- Find path
  local path = nil
  if findPath then
    path = findPath(playerPos, targetPos, CONST.MAX_CHASE_RANGE, PATH_PARAMS)
  elseif getPath then
    path = getPath(playerPos, targetPos, CONST.MAX_CHASE_RANGE, PATH_PARAMS)
  end
  
  if not path then
    return nil, dist, false
  end
  
  local pathLen = #path
  if pathLen > CONST.PATH_MAX_LENGTH then
    return path, pathLen, false  -- Path exists but too long
  end
  
  -- Check if path crosses floor-change tiles
  if pathLen > 0 then
    local DIR_OFFSET = {
      [North or 0] = {x = 0, y = -1},
      [East or 1] = {x = 1, y = 0},
      [South or 2] = {x = 0, y = 1},
      [West or 3] = {x = -1, y = 0},
      [NorthEast or 4] = {x = 1, y = -1},
      [SouthEast or 5] = {x = 1, y = 1},
      [SouthWest or 6] = {x = -1, y = 1},
      [NorthWest or 7] = {x = -1, y = -1}
    }
    local probe = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
    for i = 1, pathLen do
      local off = DIR_OFFSET[path[i]]
      if off then
        probe.x = probe.x + off.x
        probe.y = probe.y + off.y
        if isFloorChangeTile(probe) then
          return nil, pathLen, false  -- Path crosses floor change
        end
      end
    end
  end
  
  return path, pathLen, true
end

-- Get cached or fresh path
-- Get cached or fresh path (improved with safe API calls)
function EventTargeting.PathValidator.getPath(creature)
  if not creature then return nil, 999, false end
  
  -- Safe ID access
  local okId, id = pcall(function() return creature:getId() end)
  if not okId or not id then return nil, 999, false end
  
  local entry = creatureCache.entries[id]
  
  -- Check cached path
  if entry and entry.path and (now - entry.pathTime) < CONST.PATH_CACHE_TTL then
    return entry.path, #entry.path, true
  end
  
  -- Calculate fresh path
  updatePlayerRef()
  if not player then return nil, 999, false end
  
  -- Safe position access
  local okPpos, playerPos = pcall(function() return player:getPosition() end)
  local okCpos, creaturePos = pcall(function() return creature:getPosition() end)
  
  if not okPpos or not playerPos or not okCpos or not creaturePos then
    return nil, 999, false
  end
  
  return EventTargeting.PathValidator.validate(playerPos, creaturePos)
end

-- ============================================================================
-- TARGET ACQUISITION (Event-Driven)
-- ============================================================================

EventTargeting.TargetAcquisition = {}

-- Check if creature is in targetbot config (improved with safe API calls)
function EventTargeting.TargetAcquisition.isValidTarget(creature)
  if not creature then return false end
  
  -- Safe dead check
  local okDead, isDead = pcall(function() return creature:isDead() end)
  if okDead and isDead then return false end
  
  -- Safe monster check
  local okMonster, isMonster = pcall(function() return creature:isMonster() end)
  if not okMonster or not isMonster then return false end
  
  -- Check against targetbot configs
  if TargetBot and TargetBot.Creature and TargetBot.Creature.getConfigs then
    local configs = TargetBot.Creature.getConfigs(creature)
    return configs and #configs > 0
  end
  
  return false
end

-- Calculate target priority (higher = better) - improved with safe API calls
-- FIXED: Now properly uses config.priority for multi-monster priority detection
function EventTargeting.TargetAcquisition.calculatePriority(creature, path)
  if not creature then return 0 end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- PREFER TargetBot.Creature.calculateParams for consistency with main loop
  -- This ensures the same priority logic is used everywhere
  -- ═══════════════════════════════════════════════════════════════════════════
  if TargetBot and TargetBot.Creature and TargetBot.Creature.calculateParams then
    local params = TargetBot.Creature.calculateParams(creature, path or {})
    if params and params.priority and params.priority > 0 then
      -- Return the calculated priority directly - this uses the full algorithm
      -- including config.priority, health bonuses, distance, etc.
      return params.priority
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- FALLBACK: Manual calculation if TargetBot.Creature not available
  -- ═══════════════════════════════════════════════════════════════════════════
  local priority = 0  -- Start at 0, build up from config priority
  
  -- Safe HP access
  local okHp, hp = pcall(function() return creature:getHealthPercent() end)
  hp = (okHp and hp) or 100
  
  local pathLen = path and #path or 10
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- CONFIG PRIORITY: The user-defined priority is THE PRIMARY FACTOR
  -- This is what distinguishes different monster types
  -- ═══════════════════════════════════════════════════════════════════════════
  if TargetBot and TargetBot.Creature and TargetBot.Creature.getConfigs then
    local configs = TargetBot.Creature.getConfigs(creature)
    if configs and #configs > 0 then
      -- Find highest priority config for this creature
      local highestConfigPriority = 0
      local highestDanger = 0
      for i = 1, #configs do
        local cfg = configs[i]
        if cfg.priority and cfg.priority > highestConfigPriority then
          highestConfigPriority = cfg.priority
          highestDanger = cfg.danger or 0
        end
      end
      -- Config priority is multiplied by 100 to make it the dominant factor
      -- A monster with priority 2 will ALWAYS beat priority 1 unless critically wounded
      priority = priority + (highestConfigPriority * 100)
      priority = priority + (highestDanger * 2)
    else
      -- No config found = not a valid target
      return 0
    end
  end
  
  -- HP-based priority (wounded targets get higher priority)
  if hp <= 10 then
    priority = priority + 80
  elseif hp <= 20 then
    priority = priority + 55
  elseif hp <= 30 then
    priority = priority + 35
  elseif hp <= 50 then
    priority = priority + 18
  end
  
  -- Distance priority (closer = better)
  if pathLen <= 1 then
    priority = priority + 20
  elseif pathLen <= 2 then
    priority = priority + 15
  elseif pathLen <= 3 then
    priority = priority + 10
  elseif pathLen <= 5 then
    priority = priority + 5
  end
  
  -- Current attack target bonus (safe)
  local currentTarget = g_game and g_game.getAttackingCreature and g_game.getAttackingCreature()
  if currentTarget then
    local okCid, cid = pcall(function() return creature:getId() end)
    local okTid, tid = pcall(function() return currentTarget:getId() end)
    if okCid and okTid and cid == tid then
      priority = priority + 25
      -- Extra bonus for wounded current target
      if hp < 50 then
        priority = priority + 20
      end
    end
  end
  
  return priority
end

-- Process a newly appeared creature (improved with safe API calls)
function EventTargeting.TargetAcquisition.processCreature(creature)
  if not creature then return end
  if not EventTargeting.TargetAcquisition.isValidTarget(creature) then return end
  
  updatePlayerRef()
  if not player then return end
  
  -- Safe access to positions and ID
  local okId, id = pcall(function() return creature:getId() end)
  local okPpos, playerPos = pcall(function() return player:getPosition() end)
  local okCpos, creaturePos = pcall(function() return creature:getPosition() end)
  
  if not okId or not id or not okPpos or not playerPos or not okCpos or not creaturePos then return end
  
  -- Check same floor and range
  if not sameFloor(playerPos, creaturePos) then return end
  local dist = chebyshev(playerPos, creaturePos)
  if dist > CONST.DETECTION_RANGE then return end
  
  -- Validate path
  local path, pathLen, reachable = EventTargeting.PathValidator.validate(playerPos, creaturePos)
  
  -- Calculate priority
  local priority = EventTargeting.TargetAcquisition.calculatePriority(creature, path)
  
  -- Update cache
  local entry = creatureCache.entries[id]
  if not entry then
    entry = {}
    creatureCache.entries[id] = entry
    creatureCache.count = creatureCache.count + 1
  end
  
  entry.creature = creature
  entry.path = path
  entry.pathTime = now
  entry.priority = priority
  entry.reachable = reachable
  entry.lastSeen = now
  entry.distance = dist
  
  touchEntry(id)
  evictOldEntries()
  
  -- Check if this should be our target
  if reachable then
    EventTargeting.TargetAcquisition.evaluateTarget(creature, priority, path)
  end
  
  if EventTargeting.DEBUG then
    print("[EventTargeting] Processed: " .. creature:getName() .. 
          " dist=" .. dist .. " priority=" .. priority .. " reachable=" .. tostring(reachable))
  end
end

-- Evaluate if we should switch to this target
function EventTargeting.TargetAcquisition.evaluateTarget(creature, priority, path)
  if not creature then return end
  
  -- Skip if TargetBot is disabled
  if TargetBot and TargetBot.isOn and not TargetBot.isOn() then
    return
  end
  
  -- Check cooldown
  if now - targetState.lastAcquisition < CONST.ACQUISITION_COOLDOWN then
    -- Queue for later evaluation
    table.insert(targetState.pendingTargets, {
      creature = creature,
      priority = priority,
      path = path,
      time = now
    })
    return
  end
  
  local currentTarget = g_game and g_game.getAttackingCreature and g_game.getAttackingCreature()
  
  -- If no current target, acquire immediately
  if not currentTarget or currentTarget:isDead() then
    EventTargeting.TargetAcquisition.acquireTarget(creature, path)
    return
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- IMPROVED: Check CONFIG PRIORITY first for instant high-priority switching
  -- Config priority differences should override other factors
  -- ═══════════════════════════════════════════════════════════════════════════
  local newConfigPriority = 0
  local currentConfigPriority = 0
  
  if TargetBot and TargetBot.Creature and TargetBot.Creature.getConfigs then
    -- Get new creature's config priority
    local newConfigs = TargetBot.Creature.getConfigs(creature)
    if newConfigs and #newConfigs > 0 then
      for i = 1, #newConfigs do
        local cfg = newConfigs[i]
        if cfg.priority and cfg.priority > newConfigPriority then
          newConfigPriority = cfg.priority
        end
      end
    end
    
    -- Get current target's config priority
    local currentConfigs = TargetBot.Creature.getConfigs(currentTarget)
    if currentConfigs and #currentConfigs > 0 then
      for i = 1, #currentConfigs do
        local cfg = currentConfigs[i]
        if cfg.priority and cfg.priority > currentConfigPriority then
          currentConfigPriority = cfg.priority
        end
      end
    end
    
    -- If new creature has HIGHER config priority, switch immediately!
    -- This is the KEY fix for the user's issue
    if newConfigPriority > currentConfigPriority then
      if EventTargeting.DEBUG then
        local name = creature:getName() or "Unknown"
        local currentName = currentTarget:getName() or "Unknown"
        print("[EventTargeting] Priority switch: " .. name .. " (priority=" .. newConfigPriority .. 
              ") > " .. currentName .. " (priority=" .. currentConfigPriority .. ")")
      end
      EventTargeting.TargetAcquisition.acquireTarget(creature, path)
      return
    end
  end
  
  -- Compare calculated priorities (for same config priority level)
  local currentPriority = 0
  local currentId = currentTarget:getId()
  local currentEntry = creatureCache.entries[currentId]
  
  if currentEntry then
    currentPriority = currentEntry.priority or 0
  else
    -- Calculate current target priority
    local currentPath, _, _ = EventTargeting.PathValidator.getPath(currentTarget)
    currentPriority = EventTargeting.TargetAcquisition.calculatePriority(currentTarget, currentPath)
  end
  
  -- Switch if new target has significantly higher priority (same config level)
  -- Use lower threshold since config priority is already checked above
  local priorityThreshold = 50  -- Within same config priority tier
  if priority > currentPriority + priorityThreshold then
    EventTargeting.TargetAcquisition.acquireTarget(creature, path)
  end
end

-- Acquire a new target
function EventTargeting.TargetAcquisition.acquireTarget(creature, path)
  -- CRITICAL: Do not attack if TargetBot is disabled
  if TargetBot and TargetBot.isOn and not TargetBot.isOn() then
    return
  end
  
  if not creature or creature:isDead() then return end
  
  updatePlayerRef()
  if not player then return end
  
  local id = creature:getId()
  local playerPos = player:getPosition()
  local creaturePos = creature:getPosition()
  if not playerPos or not creaturePos then return end
  
  local dist = chebyshev(playerPos, creaturePos)
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- PATH VALIDATION: Never attack unreachable targets
  -- Verify path exists before attacking (prevents attacking through walls, etc.)
  -- ═══════════════════════════════════════════════════════════════════════════
  if dist > 1 then
    -- Re-validate path if not provided or stale
    if not path then
      local validatedPath, pathLen, reachable = EventTargeting.PathValidator.validate(playerPos, creaturePos)
      if not reachable then
        if EventTargeting.DEBUG then
          print("[EventTargeting] BLOCKED: " .. creature:getName() .. " is unreachable (no path)")
        end
        return  -- Do NOT attack unreachable targets
      end
      path = validatedPath
    end
  end
  
  -- Attack the creature
  if g_game and g_game.attack then
    g_game.attack(creature)
  end
  
  targetState.currentTarget = creature
  targetState.currentTargetId = id
  targetState.lastAcquisition = now
  targetState.combatActive = true
  
  -- Emit combat start event
  if EventBus then
    EventBus.emit("targeting/acquired", creature, dist, path)
  end
  
  -- Register chase intent if not adjacent
  if dist > 1 and path and #path > 0 then
    EventTargeting.CombatCoordinator.registerChaseIntent(creature, creaturePos, dist)
  end
  
  -- Pause CaveBot walking
  EventTargeting.CombatCoordinator.pauseCaveBot()
  
  if EventTargeting.DEBUG then
    print("[EventTargeting] Acquired target: " .. creature:getName() .. " dist=" .. dist)
  end
end

-- Process pending targets (called from macro)
function EventTargeting.TargetAcquisition.processPending()
  if #targetState.pendingTargets == 0 then return end
  
  -- Find best pending target
  local best = nil
  local bestPriority = 0
  local validTargets = {}
  
  for i = 1, #targetState.pendingTargets do
    local pending = targetState.pendingTargets[i]
    if pending.creature and not pending.creature:isDead() then
      -- Re-validate path for pending targets (they may have become unreachable)
      local stillReachable = true
      updatePlayerRef()
      if player then
        local playerPos = player:getPosition()
        local creaturePos = pending.creature:getPosition()
        if playerPos and creaturePos and chebyshev(playerPos, creaturePos) > 1 then
          local _, _, reachable = EventTargeting.PathValidator.validate(playerPos, creaturePos)
          stillReachable = reachable
        end
      end
      
      if stillReachable and pending.priority > bestPriority then
        bestPriority = pending.priority
        best = pending
      end
      -- Keep recent valid targets that are still reachable
      if now - pending.time < 500 and stillReachable then
        table.insert(validTargets, pending)
      end
    end
  end
  
  targetState.pendingTargets = validTargets
  
  if best then
    EventTargeting.TargetAcquisition.evaluateTarget(best.creature, best.priority, best.path)
  end
end

-- ============================================================================
-- COMBAT COORDINATOR (CaveBot Integration)
-- ============================================================================

EventTargeting.CombatCoordinator = {}

-- Check if lure mode is active (should NOT pause CaveBot)
function EventTargeting.CombatCoordinator.isLureModeActive()
  -- Check dynamicLure
  if TargetBot and TargetBot.ActiveMovementConfig then
    local config = TargetBot.ActiveMovementConfig
    if config.dynamicLure then
      return true
    end
  end
  
  -- Check smartPull (this actually PAUSES cavebot, but let targetbot handle it)
  if TargetBot and TargetBot.smartPullActive then
    return true  -- SmartPull is active, don't interfere
  end
  
  -- Check if CaveBot has lure waypoint active
  if CaveBot and CaveBot.isLuring then
    local isLuring = false
    pcall(function() isLuring = CaveBot.isLuring() end)
    if isLuring then return true end
  end
  
  return false
end

-- Check if we should pause CaveBot walking
function EventTargeting.CombatCoordinator.shouldPauseCaveBot()
  -- Don't pause if lure mode is active
  if EventTargeting.CombatCoordinator.isLureModeActive() then
    return false
  end
  
  -- Check if we're in combat with a valid target
  local currentTarget = g_game and g_game.getAttackingCreature and g_game.getAttackingCreature()
  if not currentTarget or currentTarget:isDead() then
    return false
  end
  
  -- Verify target is in our config
  if not EventTargeting.TargetAcquisition.isValidTarget(currentTarget) then
    return false
  end
  
  return true
end

-- Pause CaveBot walking during combat
function EventTargeting.CombatCoordinator.pauseCaveBot()
  if not EventTargeting.CombatCoordinator.shouldPauseCaveBot() then
    return
  end
  
  -- Set combat active flag for CaveBot to check
  targetState.combatActive = true
  storage.eventTargetingCombat = true
  
  -- Reset CaveBot walking if available
  if CaveBot and CaveBot.resetWalking then
    pcall(function() CaveBot.resetWalking() end)
  end
  
  if EventTargeting.DEBUG then
    print("[EventTargeting] CaveBot paused for combat")
  end
end

-- Resume CaveBot walking after combat
function EventTargeting.CombatCoordinator.resumeCaveBot()
  targetState.combatActive = false
  storage.eventTargetingCombat = false
  
  if EventTargeting.DEBUG then
    print("[EventTargeting] CaveBot resumed")
  end
end

-- Register chase intent with MovementCoordinator
function EventTargeting.CombatCoordinator.registerChaseIntent(creature, targetPos, dist)
  if not MovementCoordinator or not MovementCoordinator.Intent then
    return
  end
  
  -- Calculate confidence based on distance and HP
  local confidence = 0.55  -- Base passes CHASE threshold
  if dist <= 2 then confidence = 0.68 end
  if dist <= 4 then confidence = 0.72 end
  if dist > 5 then confidence = 0.80 end
  
  -- Boost for wounded targets
  local hp = creature:getHealthPercent() or 100
  if hp < 30 then
    confidence = math.min(0.95, confidence + 0.15)
  elseif hp < 50 then
    confidence = math.min(0.90, confidence + 0.08)
  end
  
  -- Register intent
  local INTENT = MovementCoordinator.CONSTANTS.INTENT
  MovementCoordinator.Intent.register(
    INTENT.CHASE,
    targetPos,
    confidence,
    "event_targeting_chase",
    {triggered = "creature_appear", hp = hp, dist = dist}
  )
end

-- Check combat status periodically
function EventTargeting.CombatCoordinator.checkCombatStatus()
  if now - targetState.lastCombatCheck < CONST.LURE_CHECK_INTERVAL then
    return
  end
  targetState.lastCombatCheck = now
  
  local currentTarget = g_game and g_game.getAttackingCreature and g_game.getAttackingCreature()
  
  if not currentTarget or currentTarget:isDead() then
    -- Combat ended
    if targetState.combatActive then
      EventTargeting.CombatCoordinator.resumeCaveBot()
      targetState.currentTarget = nil
      targetState.currentTargetId = nil
      
      -- Emit combat end event
      if EventBus then
        EventBus.emit("targeting/combat_end")
      end
    end
    return
  end
  
  -- Combat still active - ensure CaveBot is paused
  if not targetState.combatActive and EventTargeting.CombatCoordinator.shouldPauseCaveBot() then
    EventTargeting.CombatCoordinator.pauseCaveBot()
  end
end

-- ============================================================================
-- EVENTBUS INTEGRATION (High-Performance Event Handlers)
-- ============================================================================

-- Debounce helper
local lastProcessTime = 0
local pendingCreatures = {}

local function debouncedProcess()
  if now - lastProcessTime < CONST.DEBOUNCE_INTERVAL then
    return
  end
  lastProcessTime = now
  
  -- Process up to MAX_PROCESS_PER_TICK creatures
  local processed = 0
  while #pendingCreatures > 0 and processed < CONST.MAX_PROCESS_PER_TICK do
    local creature = table.remove(pendingCreatures, 1)
    if creature and not creature:isDead() then
      EventTargeting.TargetAcquisition.processCreature(creature)
      processed = processed + 1
    end
  end
end

-- Register EventBus handlers
if EventBus then
  -- Monster appeared - queue for processing
  -- IMPROVED: Instant high-priority monster detection and target switching
  EventBus.on("monster:appear", function(creature)
    if not creature then return end
    
    -- Quick distance check before queuing
    updatePlayerRef()
    if not player then return end
    
    local playerPos = player:getPosition()
    local creaturePos = creature:getPosition()
    if not sameFloor(playerPos, creaturePos) then return end
    
    local dist = chebyshev(playerPos, creaturePos)
    if dist > CONST.DETECTION_RANGE then return end
    
    -- ═══════════════════════════════════════════════════════════════════════════
    -- HIGH-PRIORITY MONSTER DETECTION
    -- Immediately check if this monster has higher priority than current target
    -- This ensures priority-based targeting works when different monsters are configured
    -- ═══════════════════════════════════════════════════════════════════════════
    local isHighPriority = false
    local newPriority = 0
    local newConfigPriority = 0
    
    -- Get the new creature's config priority
    if TargetBot and TargetBot.Creature and TargetBot.Creature.getConfigs then
      local configs = TargetBot.Creature.getConfigs(creature)
      if configs and #configs > 0 then
        for i = 1, #configs do
          local cfg = configs[i]
          if cfg.priority and cfg.priority > newConfigPriority then
            newConfigPriority = cfg.priority
          end
        end
      end
    end
    
    -- Check if this is a higher priority than current target
    local currentTarget = g_game and g_game.getAttackingCreature and g_game.getAttackingCreature()
    if newConfigPriority > 0 and currentTarget and not currentTarget:isDead() then
      local currentConfigPriority = 0
      if TargetBot and TargetBot.Creature and TargetBot.Creature.getConfigs then
        local currentConfigs = TargetBot.Creature.getConfigs(currentTarget)
        if currentConfigs and #currentConfigs > 0 then
          for i = 1, #currentConfigs do
            local cfg = currentConfigs[i]
            if cfg.priority and cfg.priority > currentConfigPriority then
              currentConfigPriority = cfg.priority
            end
          end
        end
      end
      
      -- If new monster has HIGHER config priority, mark for immediate processing
      if newConfigPriority > currentConfigPriority then
        isHighPriority = true
        if EventTargeting.DEBUG then
          local name = creature:getName() or "Unknown"
          local currentName = currentTarget:getName() or "Unknown"
          print("[EventTargeting] HIGH PRIORITY: " .. name .. " (priority=" .. newConfigPriority .. 
                ") > " .. currentName .. " (priority=" .. currentConfigPriority .. ")")
        end
      end
    elseif newConfigPriority > 0 and (not currentTarget or currentTarget:isDead()) then
      -- No current target - this is a valid high-priority target
      isHighPriority = true
    end
    
    -- High-priority or close creatures - process immediately for instant targeting
    if isHighPriority or dist <= CONST.INSTANT_ATTACK_THRESHOLD then
      EventTargeting.TargetAcquisition.processCreature(creature)
      
      -- Emit high priority event for other systems
      if isHighPriority and EventBus then
        pcall(function()
          EventBus.emit("targeting/high_priority_appear", creature, newConfigPriority, dist)
        end)
      end
    else
      -- Queue for batch processing
      table.insert(pendingCreatures, creature)
    end
  end, 30)  -- High priority
  
  -- Monster disappeared - remove from cache
  EventBus.on("monster:disappear", function(creature)
    if not creature then return end
    local id = creature:getId()
    
    if creatureCache.entries[id] then
      creatureCache.entries[id] = nil
      creatureCache.count = creatureCache.count - 1
      
      -- Remove from access order
      for i = #creatureCache.accessOrder, 1, -1 do
        if creatureCache.accessOrder[i] == id then
          table.remove(creatureCache.accessOrder, i)
          break
        end
      end
    end
    
    -- Check if this was our target
    if targetState.currentTargetId == id then
      targetState.currentTarget = nil
      targetState.currentTargetId = nil
      -- Try to find next target
      EventTargeting.TargetAcquisition.processPending()
    end
  end, 25)
  
  -- Monster health changed - update priority
  EventBus.on("monster:health", function(creature, percent, oldPercent)
    if not creature then return end
    local id = creature:getId()
    local entry = creatureCache.entries[id]
    
    if entry then
      -- Recalculate priority
      local newPriority = EventTargeting.TargetAcquisition.calculatePriority(creature, entry.path)
      local priorityChange = newPriority - (entry.priority or 0)
      entry.priority = newPriority
      entry.lastSeen = now
      touchEntry(id)
      
      -- If priority increased significantly, reevaluate as target
      if priorityChange > 20 and entry.reachable then
        EventTargeting.TargetAcquisition.evaluateTarget(creature, newPriority, entry.path)
      end
    end
  end, 20)
  
  -- Creature moved - update path cache
  EventBus.on("creature:move", function(creature, oldPos)
    if not creature or not creature:isMonster() then return end
    
    local id = creature:getId()
    local entry = creatureCache.entries[id]
    
    if entry then
      -- Invalidate path cache
      entry.path = nil
      entry.pathTime = 0
      entry.lastSeen = now
      touchEntry(id)
      
      -- If this is our current target, register new chase intent
      if targetState.currentTargetId == id then
        updatePlayerRef()
        if player then
          local playerPos = player:getPosition()
          local creaturePos = creature:getPosition()
          local dist = chebyshev(playerPos, creaturePos)
          
          if dist > 1 and sameFloor(playerPos, creaturePos) then
            EventTargeting.CombatCoordinator.registerChaseIntent(creature, creaturePos, dist)
          end
        end
      end
    end
  end, 15)
  
  -- Player moved - update distances and paths
  EventBus.on("player:move", function(newPos, oldPos)
    -- Invalidate all path caches on player move
    for id, entry in pairs(creatureCache.entries) do
      entry.path = nil
      entry.pathTime = 0
    end
    
    -- Check if combat status changed
    EventTargeting.CombatCoordinator.checkCombatStatus()
  end, 10)
  
  -- Combat target changed
  EventBus.on("combat:target", function(creature, oldCreature)
    if creature then
      targetState.currentTarget = creature
      targetState.currentTargetId = creature:getId()
      targetState.lastAcquisition = now
      
      -- Ensure CaveBot is paused
      EventTargeting.CombatCoordinator.pauseCaveBot()
    else
      -- Target cleared
      if targetState.combatActive then
        EventTargeting.CombatCoordinator.resumeCaveBot()
      end
      targetState.currentTarget = nil
      targetState.currentTargetId = nil
    end
  end, 35)
  
  -- Player health change (relogin detection)
  EventBus.on("player:health", function(health, maxHealth, oldHealth, oldMax)
    if health and health > 0 and (not oldHealth or oldHealth == 0) then
      -- Player relogged
      updatePlayerRef()
      creatureCache.entries = {}
      creatureCache.accessOrder = {}
      creatureCache.count = 0
      targetState.currentTarget = nil
      targetState.currentTargetId = nil
      targetState.combatActive = false
      pendingCreatures = {}
      
      if EventTargeting.DEBUG then
        print("[EventTargeting] Reset on relogin")
      end
    end
  end, 50)
end

-- ============================================================================
-- MAIN PROCESSING MACRO
-- ============================================================================

-- Scan interval for full screen scan (catch any monsters EventBus missed)
local lastFullScan = 0
local FULL_SCAN_INTERVAL = 150  -- IMPROVED: Scan every 150ms for faster detection

-- Full screen scan - catches monsters that EventBus may have missed
-- IMPROVED: Uses the live count system for accurate detection
local function scanVisibleMonsters()
  updatePlayerRef()
  if not player then return end
  
  local playerPos = player:getPosition()
  if not playerPos then return end
  
  -- IMPROVED: First refresh live count
  local liveCount, liveCreatures = EventTargeting.getLiveMonsterCount()
  
  -- If live count found monsters, process them
  if liveCreatures and #liveCreatures > 0 then
    local currentTime = now or (os.time() * 1000)
    local processedCount = 0
    for i = 1, #liveCreatures do
      local creature = liveCreatures[i]
      if creature then
        local okId, id = pcall(function() return creature:getId() end)
        if okId and id then
          -- Only process if not already in cache or cache entry is stale
          local entry = creatureCache.entries[id]
          if not entry or (currentTime - (entry.lastSeen or 0)) > 500 then
            -- Queue for processing
            table.insert(pendingCreatures, creature)
            processedCount = processedCount + 1
            if processedCount >= 8 then break end  -- Process more per scan
          end
        end
      end
    end
    
    if EventTargeting.DEBUG and processedCount > 0 then
      print("[EventTargeting] Full scan queued " .. processedCount .. " creatures (live count: " .. liveCount .. ")")
    end
    return
  end
  
  -- Fallback: Use direct API if live count didn't work
  local creatures = nil
  local range = CONST.DETECTION_RANGE
  
  if g_map and g_map.getSpectatorsInRange then
    creatures = g_map.getSpectatorsInRange(playerPos, false, range, range)
  end
  
  if not creatures or #creatures == 0 then return end
  
  local currentTime = now or (os.time() * 1000)
  local processedCount = 0
  local playerZ = playerPos.z
  for i = 1, #creatures do
    local creature = creatures[i]
    if isTargetableMonster(creature) then
      local okPos, cpos = pcall(function() return creature:getPosition() end)
      if okPos and cpos and cpos.z == playerZ then
        local okId, id = pcall(function() return creature:getId() end)
        if okId and id then
          -- Only process if not already in cache or cache entry is stale
          local entry = creatureCache.entries[id]
          if not entry or (currentTime - (entry.lastSeen or 0)) > 500 then
            -- Queue for processing
            table.insert(pendingCreatures, creature)
            processedCount = processedCount + 1
            if processedCount >= 8 then break end
          end
        end
      end
    end
  end
  
  if EventTargeting.DEBUG and processedCount > 0 then
    print("[EventTargeting] Full scan queued " .. processedCount .. " creatures (fallback)")
  end
end

-- Fast macro for processing queued creatures and combat checks
-- IMPROVED: Runs at 50ms for faster response
macro(50, function()
  -- Skip if TargetBot is off
  if TargetBot and TargetBot.isOn and not TargetBot.isOn() then
    return
  end
  
  -- Update time (use global 'now' if available, else fallback)
  local currentTime = now or (os.time() * 1000)
  
  -- Periodic full screen scan to catch any monsters EventBus missed
  if (currentTime - lastFullScan) >= FULL_SCAN_INTERVAL then
    lastFullScan = currentTime
    scanVisibleMonsters()
  end
  
  -- Process debounced creatures
  debouncedProcess()
  
  -- Process pending target evaluations
  EventTargeting.TargetAcquisition.processPending()
  
  -- Check combat status
  EventTargeting.CombatCoordinator.checkCombatStatus()
  
  -- Periodic cleanup
  cleanupCache()
end)

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Get current combat state
function EventTargeting.isInCombat()
  return targetState.combatActive
end

-- Get current target
function EventTargeting.getCurrentTarget()
  return targetState.currentTarget
end

-- Get cached creature count
function EventTargeting.getCacheCount()
  return creatureCache.count
end

-- Force target acquisition
function EventTargeting.forceAcquire(creature)
  if creature and not creature:isDead() then
    EventTargeting.TargetAcquisition.processCreature(creature)
  end
end

-- Get all reachable targets
function EventTargeting.getReachableTargets()
  local targets = {}
  for id, entry in pairs(creatureCache.entries) do
    if entry.reachable and entry.creature and not entry.creature:isDead() then
      targets[#targets + 1] = {
        creature = entry.creature,
        priority = entry.priority,
        distance = entry.distance,
        path = entry.path
      }
    end
  end
  
  -- Sort by priority
  table.sort(targets, function(a, b)
    return a.priority > b.priority
  end)
  
  return targets
end

-- Debug: Print cache status
function EventTargeting.debugStatus()
  print("[EventTargeting] Cache: " .. creatureCache.count .. " creatures")
  print("[EventTargeting] Combat: " .. tostring(targetState.combatActive))
  if targetState.currentTarget then
    print("[EventTargeting] Target: " .. targetState.currentTarget:getName())
  end
end

-- ============================================================================
-- CAVEBOT INTEGRATION HOOK
-- ============================================================================

-- Export function for CaveBot to check
function EventTargeting.shouldPauseCaveBot()
  return EventTargeting.CombatCoordinator.shouldPauseCaveBot()
end

-- Export combat active state
-- Returns true if there are monsters on screen to kill
-- This helps CaveBot know when to pause and wait for monsters to die
-- IMPROVED: Uses LIVE monster count from direct API for accuracy
function EventTargeting.isCombatActive()
  -- PRIORITY 1: Use live count from direct API (most accurate)
  local liveCount = EventTargeting.getLiveMonsterCount()
  if liveCount > 0 then
    return true
  end
  
  -- PRIORITY 2: Check TargetBot cache as backup
  if TargetBot and TargetBot.hasTargetableMonsters and TargetBot.hasTargetableMonsters() then
    return true
  end
  
  -- PRIORITY 3: Check our local cache
  if creatureCache.count > 0 then
    return true
  end
  
  -- Original logic: combat state AND not in lure mode
  return targetState.combatActive and not EventTargeting.CombatCoordinator.isLureModeActive()
end

-- Get authoritative monster count for external modules
function EventTargeting.getMonsterCount()
  local count = EventTargeting.getLiveMonsterCount()
  return count
end

-- ============================================================================
-- NATIVE OTCLIENT CALLBACK INTEGRATION
-- Direct hook into OTClient's onCreatureAppear for fastest possible detection
-- This bypasses EventBus for even faster high-priority monster switching
-- ============================================================================

-- Register native callback if available (fastest path)
if onCreatureAppear then
  onCreatureAppear(function(creature)
    if not creature then return end
    if not creature:isMonster() then return end
    if creature:isDead() then return end
    
    -- Skip if TargetBot is off
    if TargetBot and TargetBot.isOn and not TargetBot.isOn() then
      return
    end
    
    -- Quick validation
    updatePlayerRef()
    if not player then return end
    
    local okPpos, playerPos = pcall(function() return player:getPosition() end)
    local okCpos, creaturePos = pcall(function() return creature:getPosition() end)
    if not okPpos or not playerPos or not okCpos or not creaturePos then return end
    if playerPos.z ~= creaturePos.z then return end
    
    local dist = chebyshev(playerPos, creaturePos)
    if dist > CONST.DETECTION_RANGE then return end
    
    -- Check if this is a high-priority monster
    if TargetBot and TargetBot.Creature and TargetBot.Creature.getConfigs then
      local configs = TargetBot.Creature.getConfigs(creature)
      if configs and #configs > 0 then
        local newConfigPriority = 0
        for i = 1, #configs do
          local cfg = configs[i]
          if cfg.priority and cfg.priority > newConfigPriority then
            newConfigPriority = cfg.priority
          end
        end
        
        -- Check current target's priority
        local currentTarget = g_game and g_game.getAttackingCreature and g_game.getAttackingCreature()
        if newConfigPriority > 0 then
          local currentConfigPriority = 0
          if currentTarget and not currentTarget:isDead() then
            local currentConfigs = TargetBot.Creature.getConfigs(currentTarget)
            if currentConfigs and #currentConfigs > 0 then
              for i = 1, #currentConfigs do
                local cfg = currentConfigs[i]
                if cfg.priority and cfg.priority > currentConfigPriority then
                  currentConfigPriority = cfg.priority
                end
              end
            end
          end
          
          -- INSTANT SWITCH for higher priority monster!
          if newConfigPriority > currentConfigPriority then
            if EventTargeting.DEBUG then
              local name = creature:getName() or "Unknown"
              print("[EventTargeting] NATIVE: High priority monster appeared: " .. name .. 
                    " (priority=" .. newConfigPriority .. ")")
            end
            
            -- Immediate attack!
            if g_game and g_game.attack then
              g_game.attack(creature)
            end
            
            -- Also update our state
            local okId, id = pcall(function() return creature:getId() end)
            if okId and id then
              targetState.currentTarget = creature
              targetState.currentTargetId = id
              targetState.lastAcquisition = now or (os.time() * 1000)
              targetState.combatActive = true
            end
            
            -- Emit event for other systems
            if EventBus then
              pcall(function()
                EventBus.emit("targeting/high_priority_appear", creature, newConfigPriority, dist)
              end)
            end
            return
          end
        end
      end
    end
    
    -- Not high priority - let normal flow handle it via EventBus
  end)
  
  if EventTargeting.DEBUG then
    print("[EventTargeting] Native onCreatureAppear callback registered")
  end
end

print("[EventTargeting] Module loaded v" .. EventTargeting.VERSION)
