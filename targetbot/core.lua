--[[
  TargetBot Core Module v1.0
  
  High-performance targeting system with:
  - Pure functions for testability and reliability
  - O(1) lookups with optimized data structures
  - Event-driven updates to minimize CPU usage
  - Statistical analysis for better decision making
  - DRY/SRP/SOLID principles throughout
  
  Architecture:
  - TargetCore: Core algorithms (pure functions)
  - TargetState: State management (single source of truth)
  - TargetMetrics: Performance tracking and analysis
]]

-- MODULE NAMESPACE

TargetCore = TargetCore or {}

-- Use shared ClientHelper aliases (loaded by _Loader.lua)
local getClient = nExBot.Shared.getClient
local getClientVersion = nExBot.Shared.getClientVersion

-- CONSTANTS (Centralized, immutable)

TargetCore.CONSTANTS = {
  -- Creature types
  CREATURE_TYPE = {
    PLAYER = 0,
    MONSTER = 1,
    NPC = 2,
    SUMMON = 3
  },
  
  -- Direction vectors (cardinal + diagonal)
  DIRECTIONS = {
    NORTH     = {x = 0, y = -1, index = 0},
    EAST      = {x = 1, y = 0, index = 1},
    SOUTH     = {x = 0, y = 1, index = 2},
    WEST      = {x = -1, y = 0, index = 3},
    NORTHEAST = {x = 1, y = -1, index = 4},
    SOUTHEAST = {x = 1, y = 1, index = 5},
    SOUTHWEST = {x = -1, y = 1, index = 6},
    NORTHWEST = {x = -1, y = -1, index = 7}
  },
  
  -- Direction index to vector (O(1) lookup)
  DIR_VECTORS = Directions.DIR_TO_OFFSET,
  
  -- Adjacent offsets (pre-computed for iteration)
  ADJACENT_OFFSETS = {
    {x = 0, y = -1},  -- N
    {x = 1, y = 0},   -- E
    {x = 0, y = 1},   -- S
    {x = -1, y = 0},  -- W
    {x = 1, y = -1},  -- NE
    {x = 1, y = 1},   -- SE
    {x = -1, y = 1},  -- SW
    {x = -1, y = -1}  -- NW
  },
  
  -- Priority weights (tunable) v2.3
  -- IMPROVED: Stronger target stickiness to prevent erratic switching and leaving monsters behind
  PRIORITY = {
    CRITICAL_HEALTH = 100,   -- HP <= 10% (INCREASED from 80)
    VERY_LOW_HEALTH = 70,    -- HP <= 20% (INCREASED from 55)
    LOW_HEALTH = 45,         -- HP <= 30% (INCREASED from 35)
    WOUNDED = 25,            -- HP <= 50% (INCREASED from 18)
    CURRENT_TARGET = 70,     -- Already attacking (INCREASED from 50)
    CURRENT_WOUNDED = 55,    -- Attacking + wounded (INCREASED from 40)
    CURRENT_LOW_HP = 80,     -- Attacking + critical HP (INCREASED from 60)
    ADJACENT = 14,           -- Distance 1
    CLOSE = 10,              -- Distance 2
    NEAR = 6,                -- Distance 3
    MEDIUM = 3,              -- Distance 4-5
    CHASE_BONUS = 12,        -- Chase mode active
    AOE_BONUS = 8,           -- Per monster in AOE range
    SWITCH_PENALTY = 35,     -- Penalty for switching from wounded target (INCREASED from 20)
  },
  
  -- Distance weight lookup (O(1))
  DISTANCE_WEIGHTS = {
    [1] = 14, [2] = 10, [3] = 6, [4] = 3, [5] = 3,
    [6] = 1, [7] = 1, [8] = 0, [9] = 0, [10] = 0
  },
  
  -- Timing constants
  TIMING = {
    PATH_CACHE_TTL = 400,       -- Path valid for 400ms
    CREATURE_CACHE_TTL = 5000,  -- Creature entry valid for 5s
    FULL_UPDATE_INTERVAL = 600, -- Full recalc every 600ms
    AVOIDANCE_COOLDOWN = 250,   -- Min time between avoidance moves
    POSITION_STICKINESS = 400,  -- Stay at safe pos for 400ms
  },
  
  -- Wave attack patterns (common monster beam widths)
  WAVE_PATTERNS = {
    NARROW = 1,   -- 1 tile wide beam
    MEDIUM = 2,   -- 2 tiles wide
    WIDE = 3,     -- 3 tiles wide (great energy beam)
  }
}

-- Shorthand references
local CONST = TargetCore.CONSTANTS
local DIRS = CONST.ADJACENT_OFFSETS
local DIR_VEC = CONST.DIR_VECTORS
local PRIO = CONST.PRIORITY
local DIST_W = CONST.DISTANCE_WEIGHTS
local TIMING = CONST.TIMING

-- Geometry export for reuse by other modules
TargetCore.Geometry = TargetCore.Geometry or {}

function TargetCore.isAdjacent(pos1, pos2)
  local dx = math.abs(pos1.x - pos2.x)
  local dy = math.abs(pos1.y - pos2.y)
  return dx <= 1 and dy <= 1 and (dx + dy) > 0
end

function TargetCore.getDirection(pos1, pos2)
  local dx = pos2.x - pos1.x
  local dy = pos2.y - pos1.y
  if dx == 0 and dy < 0 then return 0 end
  if dx > 0 and dy == 0 then return 1 end
  if dx == 0 and dy > 0 then return 2 end
  if dx < 0 and dy == 0 then return 3 end
  if dx > 0 and dy < 0 then return 4 end
  if dx > 0 and dy > 0 then return 5 end
  if dx < 0 and dy > 0 then return 6 end
  if dx < 0 and dy < 0 then return 7 end
  return nil
end

TargetCore.Geometry.DIRECTIONS = CONST.DIRECTIONS
TargetCore.Geometry.DIR_VECTORS = CONST.DIR_VECTORS
TargetCore.Geometry.ADJACENT_OFFSETS = CONST.ADJACENT_OFFSETS
TargetCore.Geometry.getDirection = TargetCore.getDirection
TargetCore.Geometry.chebyshevDistance = TargetCore.chebyshevDistance
TargetCore.Geometry.manhattanDistance = TargetCore.manhattanDistance
TargetCore.Geometry.isAdjacent = TargetCore.isAdjacent

-- PATH SAFETY HELPERS (Pure-ish functions operating on map API)
-- Exported so cavebot and other modules can share the same logic

TargetCore.PathSafety = TargetCore.PathSafety or {}

-- Load FloorItems constants if available (single source of truth)
local FloorItems = (function()
  local ok, fi = pcall(dofile, "/constants/floor_items.lua")
  if ok and fi then return fi end
  ok, fi = pcall(dofile, "/core/constants/floor_items.lua")
  if ok and fi then return fi end
  return nil
end)()

-- Minimal minimap colors that typically indicate stairs/ramps/holes
TargetCore.PathSafety.FLOOR_CHANGE_COLORS = (FloorItems and FloorItems.FLOOR_CHANGE_COLORS) or {
  [210] = true, [211] = true, [212] = true, [213] = true,
  -- Additional colors that may indicate floor changes
  [214] = true, [215] = true, [216] = true, [217] = true,
}

-- Comprehensive floor-change item ids (using constants or fallback)
TargetCore.PathSafety.FLOOR_CHANGE_ITEMS = (FloorItems and FloorItems.FLOOR_CHANGE) or {
  -- === STAIRS DOWN ===
  [414] = true, [415] = true, [416] = true, [417] = true,
  [428] = true, [429] = true, [430] = true, [431] = true,
  -- === STAIRS UP ===
  [432] = true, [433] = true, [434] = true, [435] = true,
  -- === WOODEN STAIRS ===
  [1949] = true, [1950] = true, [1951] = true,
  [1952] = true, [1953] = true, [1954] = true, [1955] = true,
  -- === RAMPS (MOST COMMON CAUSE OF ACCIDENTAL FLOOR CHANGES) ===
  [1956] = true, [1957] = true, [1958] = true, [1959] = true,
  [1385] = true, [1396] = true, [1397] = true, [1398] = true,
  [1399] = true, [1400] = true, [1401] = true, [1402] = true,
  [4834] = true, [4835] = true, [4836] = true, [4837] = true,
  [4838] = true, [4839] = true, [4840] = true, [4841] = true,
  [6915] = true, [6916] = true, [6917] = true, [6918] = true,
  [7545] = true, [7546] = true, [7547] = true, [7548] = true,
  -- === LADDERS ===
  [1219] = true, [1386] = true, [3678] = true, [5543] = true,
  -- === ROPE SPOTS ===
  [384] = true, [386] = true, [418] = true,
  -- === HOLES & PITFALLS ===
  [294] = true, [369] = true, [370] = true, [383] = true,
  [392] = true, [408] = true, [409] = true, [410] = true,
  [469] = true, [470] = true, [482] = true, [484] = true,
  -- === TRAPDOORS ===
  [423] = true, [424] = true, [425] = true,
  -- === SEWER GRATES ===
  [426] = true, [427] = true,
  -- === TELEPORTS & PORTALS ===
  [502] = true, [1387] = true, [2129] = true, [2130] = true, [8709] = true,
  -- === ADDITIONAL FLOOR CHANGE ITEMS ===
  -- More teleports and portals
  [1948] = true, [1947] = true, [7765] = true, [7766] = true,
  [7767] = true, [7768] = true, [7769] = true, [7770] = true,
  [7771] = true, [7772] = true,
  -- Magic forcefields
  [2128] = true, [2131] = true, [2132] = true, [2133] = true,
  -- Additional holes and depressions
  [293] = true, [385] = true, [387] = true, [388] = true,
  [389] = true, [390] = true, [391] = true, [395] = true,
  [396] = true, [397] = true, [398] = true, [399] = true,
  [400] = true, [401] = true, [402] = true, [403] = true,
  [404] = true, [405] = true, [406] = true, [407] = true,
  -- More stairs and ramps
  [4352] = true, [4353] = true, [4354] = true, [4355] = true,
  [4356] = true, [4357] = true, [4358] = true, [4359] = true,
  [4360] = true, [4361] = true, [4362] = true, [4363] = true,
  [4364] = true, [4365] = true, [4366] = true, [4367] = true,
  -- Underground ramps
  [8710] = true, [8711] = true, [8712] = true, [8713] = true,
  [8714] = true, [8715] = true, [8716] = true, [8717] = true,
}

-- Check if tile position is a floor-change tile (no caching here)
function TargetCore.PathSafety.isFloorChangeTile(pos)
  if not pos then return false end
  local Client = getClient()
  local color = (Client and Client.getMinimapColor) and Client.getMinimapColor(pos) or (g_map and g_map.getMinimapColor and g_map.getMinimapColor(pos)) or 0
  if color and TargetCore.PathSafety.FLOOR_CHANGE_COLORS[color] then return true end
  local tile = (Client and Client.getTile) and Client.getTile(pos) or (g_map and g_map.getTile and g_map.getTile(pos))
  if not tile then return false end
  local ground = tile:getGround()
  if ground and TargetCore.PathSafety.FLOOR_CHANGE_ITEMS[ground:getId()] then return true end
  local useThing = tile:getTopUseThing()
  if useThing and useThing:isItem() and TargetCore.PathSafety.FLOOR_CHANGE_ITEMS[useThing:getId()] then return true end
  local topThing = tile:getTopThing()
  if topThing and topThing:isItem() and TargetCore.PathSafety.FLOOR_CHANGE_ITEMS[topThing:getId()] then return true end
  return false
end

-- Validate that target position is safe for movement (same Z-level, no floor changes)
function TargetCore.PathSafety.isPositionSafeForMovement(targetPos, currentPos)
  if not targetPos or not currentPos then return false end
  
  -- Must be same Z-level (critical safety check)
  if targetPos.z ~= currentPos.z then return false end
  
  -- Must not be a floor change tile
  if TargetCore.PathSafety.isFloorChangeTile(targetPos) then return false end
  
  -- Must be a walkable tile
  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(targetPos) or (g_map and g_map.getTile and g_map.getTile(targetPos))
  if not tile or not tile:isWalkable() then return false end
  
  -- Should not have creatures (unless it's the target we're chasing)
  local hasCreature = tile.hasCreature and tile:hasCreature()
  if hasCreature then
    -- Allow if it's the creature we're targeting
    local creatures = tile:getCreatures()
    if creatures then
      local attackingCreature = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
      for _, creature in ipairs(creatures) do
        if creature and creature:getId() ~= (attackingCreature and attackingCreature:getId()) then
          return false
        end
      end
    end
  end
  
  return true
end

-- Simple tile safe check
function TargetCore.PathSafety.isTileSafe(pos, allowFloorChange)
  if not pos then return false end
  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(pos) or (g_map and g_map.getTile and g_map.getTile(pos))
  if not tile then return false end
  if not tile:isWalkable() then return false end
  local hasCreature = tile.hasCreature and tile:hasCreature()
  if hasCreature then return false end
  if not allowFloorChange and TargetCore.PathSafety.isFloorChangeTile(pos) then return false end
  return true
end

-- Check if a path (direction indices) crosses a floor-change tile
function TargetCore.PathSafety.pathCrossesFloorChange(path, startPos, maxSteps)
  if not path or #path == 0 then return false end
  local probe = {x = startPos.x, y = startPos.y, z = startPos.z}
  local limit = maxSteps and math.min(#path, maxSteps) or #path
  for i = 1, limit do
    local offset = TargetCore.Geometry and TargetCore.Geometry.DIR_VECTORS and TargetCore.Geometry.DIR_VECTORS[path[i]] or nil
    if offset then
      probe = {x = probe.x + offset.x, y = probe.y + offset.y, z = probe.z}
      if TargetCore.PathSafety.isFloorChangeTile(probe) then
        return true
      end
    end
  end
  return false
end

-- Recursive reachable check (bounded DFS) using isTileSafe
function TargetCore.PathSafety.recursiveReachable(startPos, destPos, depth, maxNodes)
  depth = depth or 6
  maxNodes = maxNodes or 500
  local visited = {}
  local nodes = 0
  local function key(p) return p.x .. ":" .. p.y .. ":" .. p.z end
  local function dfs(p, d)
    if nodes > maxNodes then
      return false
    end
    nodes = nodes + 1
    if p.x == destPos.x and p.y == destPos.y and p.z == destPos.z then return true end
    if d <= 0 then return false end
    visited[key(p)] = true
    for i = 1, #CONST.ADJACENT_OFFSETS do
      local off = CONST.ADJACENT_OFFSETS[i]
      local np = {x = p.x + off.x, y = p.y + off.y, z = p.z}
      if not visited[key(np)] and TargetCore.PathSafety.isTileSafe(np, false) then
        if dfs(np, d - 1) then return true end
      end
    end
    return false
  end
  local res = dfs(startPos, depth)

  return res
end

-- Quick neighbor search + BFS fallback to find safe reachable tile near dest
function TargetCore.PathSafety.findSafeAlternate(playerPos, destPos, maxDist, opts)
  opts = opts or {}
  local ignoreFields = opts.ignoreFields or false
  -- quick neighbor check
  for i = 1, #CONST.ADJACENT_OFFSETS do
    local off = CONST.ADJACENT_OFFSETS[i]
    local cand = {x = destPos.x + off.x, y = destPos.y + off.y, z = destPos.z}
    if not (cand.x == playerPos.x and cand.y == playerPos.y) and TargetCore.PathSafety.isTileSafe(cand, false) then
      local path = findPath(playerPos, cand, maxDist, {ignoreNonPathable = true, ignoreCreatures = true, ignoreFields = ignoreFields})
      if path and #path > 0 and not TargetCore.PathSafety.pathCrossesFloorChange(path, playerPos) then
        return cand, path
      end
    end
  end
  -- small additional diagnostic: if no candidate found, optionally try to widen search if debug enabled

  -- BFS fallback (small radius)
  local radius = opts.radius or 3
  local queue = {{x = destPos.x, y = destPos.y, z = destPos.z}}
  local seen = {}
  local function k(p) return p.x..","..p.y end
  seen[k(destPos)] = true
  local qi = 1
  while qi <= #queue do
    local cur = queue[qi]
    qi = qi + 1
    if TargetCore.PathSafety.isTileSafe(cur, false) then
      local path = findPath(playerPos, cur, maxDist, {ignoreNonPathable = true, ignoreCreatures = true, ignoreFields = ignoreFields})
      if path and #path > 0 and not TargetCore.PathSafety.pathCrossesFloorChange(path, playerPos) then
        return cur, path
      end
    end
    if math.abs(cur.x - destPos.x) < radius and math.abs(cur.y - destPos.y) < radius then
      for i = 1, #CONST.ADJACENT_OFFSETS do
        local off = CONST.ADJACENT_OFFSETS[i]
        local np = {x = cur.x + off.x, y = cur.y + off.y, z = cur.z}
        if not seen[k(np)] then
          seen[k(np)] = true
          table.insert(queue, np)
        end
      end
    end
  end

  return nil, nil
end

-- PURE UTILITY FUNCTIONS

-- Calculate Manhattan distance (pure)
function TargetCore.manhattanDistance(pos1, pos2)
  return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

-- Calculate Chebyshev distance (max of dx, dy - used in Tibia) (pure)
function TargetCore.chebyshevDistance(pos1, pos2)
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

-- METRICS & ANALYTICS

TargetCore.Metrics = {
  targetsKilled = 0,
  targetsSwitched = 0,
  avoidancesMoved = 0,
  pathsCalculated = 0,
  cacheHits = 0,
  cacheMisses = 0,
  avgPriorityCalcTime = 0,
  lastReset = 0
}

-- OTCLIENT NATIVE API HELPERS
-- 
-- Wrappers for OTClient's game API to handle version differences and
-- provide caching to reduce unnecessary API calls

TargetCore.Native = {
  -- Cached chase mode to avoid redundant setChaseMode calls
  lastChaseMode = nil,
  lastFollowCreature = nil,
  
  -- Chase mode constants (OTClient uses these)
  CHASE_MODE = {
    STAND = 0,        -- Don't chase (DontChase)
    CHASE = 1         -- Chase opponent (ChaseOpponent)
  }
}

-- Set chase mode with caching (avoids redundant packets)
-- This function now also emits EventBus events for coordination
-- @param mode: 0 = Stand, 1 = Chase
-- @return boolean: true if mode was changed
function TargetCore.Native.setChaseMode(mode)
  if TargetCore.Native.lastChaseMode == mode then
    return false  -- No change needed
  end
  
  if MovementCoordinator and MovementCoordinator.setChaseMode then
    MovementCoordinator.setChaseMode(mode == 1)
    TargetCore.Native.lastChaseMode = mode
    
    -- Emit EventBus event for coordination with other modules
    if EventBus then
      pcall(function()
        EventBus.emit("targetbot/chase_mode_set", mode, mode == 1 and "chase" or "stand")
      end)
    end
    
    return true
  end
  return false
end

-- Get current chase mode (cached, synced with native API)
function TargetCore.Native.getChaseMode()
  if g_game.getChaseMode then
    TargetCore.Native.lastChaseMode = g_game.getChaseMode()
  end
  return TargetCore.Native.lastChaseMode or 0
end

-- Sync cache with native API (call when external changes may have occurred)
function TargetCore.Native.syncChaseMode()
  if g_game.getChaseMode then
    TargetCore.Native.lastChaseMode = g_game.getChaseMode()
  end
end

-- Follow creature with validation
-- @param creature: creature to follow
-- @return boolean: true if follow was initiated
-- 
-- WARNING: g_game.follow() CANCELS the current attack!
-- For monsters, use setChaseMode(1) + g_game.attack() instead.
-- This function is only safe for following players (party members, etc.)
function TargetCore.Native.followCreature(creature)
  if not creature or creature:isDead() then
    return false
  end
  
  -- IMPORTANT: Don't use g_game.follow() for monsters - it cancels attack!
  -- Check if creature is a monster
  local isMonster = creature.isMonster and creature:isMonster()
  if isMonster then
    -- For monsters, just ensure chase mode is set - attack handles the rest
    TargetCore.Native.setChaseMode(TargetCore.Native.CHASE_MODE.CHASE)
    TargetCore.Native.lastFollowCreature = creature:getId()
    return true  -- Return true but don't call g_game.follow()
  end
  
  -- Check if already following this creature
  local currentFollow = g_game.getFollowingCreature and g_game.getFollowingCreature()
  if currentFollow and currentFollow:getId() == creature:getId() then
    return true  -- Already following
  end
  
  -- For non-monsters (players), we can safely use g_game.follow()
  
  -- Use g_game.follow if available, otherwise fall back to bot's follow()
  if g_game.follow then
    g_game.follow(creature)
  else
    SafeCall.global("follow", creature)
  end
  
  TargetCore.Native.lastFollowCreature = creature:getId()
  return true
end

-- Cancel following with state cleanup
function TargetCore.Native.cancelFollow()
  if g_game.cancelFollow then
    g_game.cancelFollow()
  end
  TargetCore.Native.lastFollowCreature = nil
end

-- Check if currently following a creature
-- @return creature or nil
function TargetCore.Native.getFollowingCreature()
  if g_game.getFollowingCreature then
    return g_game.getFollowingCreature()
  end
  return nil
end

-- Check if following a specific creature
-- @param creature: creature to check
-- @return boolean
function TargetCore.Native.isFollowing(creature)
  if not creature then return false end
  local following = TargetCore.Native.getFollowingCreature()
  return following and following:getId() == creature:getId()
end

-- INITIALIZATION

-- Toggle to enable debug prints
TargetCore.DEBUG = TargetCore.DEBUG or false
if TargetCore.DEBUG then print("[TargetCore] v1.0 loaded") end
