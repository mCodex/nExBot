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

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

TargetCore = TargetCore or {}

-- ============================================================================
-- CONSTANTS (Centralized, immutable)
-- ============================================================================

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
  DIR_VECTORS = {
    [0] = {x = 0, y = -1},   -- North
    [1] = {x = 1, y = 0},    -- East
    [2] = {x = 0, y = 1},    -- South
    [3] = {x = -1, y = 0},   -- West
    [4] = {x = 1, y = -1},   -- NorthEast
    [5] = {x = 1, y = 1},    -- SouthEast
    [6] = {x = -1, y = 1},   -- SouthWest
    [7] = {x = -1, y = -1}   -- NorthWest
  },
  
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
  
  -- Priority weights (tunable)
  PRIORITY = {
    CRITICAL_HEALTH = 80,    -- HP <= 10%
    VERY_LOW_HEALTH = 55,    -- HP <= 20%
    LOW_HEALTH = 35,         -- HP <= 30%
    WOUNDED = 18,            -- HP <= 50%
    CURRENT_TARGET = 15,     -- Already attacking
    CURRENT_WOUNDED = 25,    -- Attacking + wounded
    ADJACENT = 14,           -- Distance 1
    CLOSE = 10,              -- Distance 2
    NEAR = 6,                -- Distance 3
    MEDIUM = 3,              -- Distance 4-5
    CHASE_BONUS = 12,        -- Chase mode active
    AOE_BONUS = 8,           -- Per monster in AOE range
  },
  
  -- Distance weight lookup (O(1))
  DISTANCE_WEIGHTS = {
    [1] = 14, [2] = 10, [3] = 6, [4] = 3, [5] = 3,
    [6] = 1, [7] = 1, [8] = 0, [9] = 0, [10] = 0
  },
  
  -- Timing constants
  TIMING = {
    PATH_CACHE_TTL = 250,       -- Path valid for 250ms
    CREATURE_CACHE_TTL = 5000,  -- Creature entry valid for 5s
    FULL_UPDATE_INTERVAL = 400, -- Full recalc every 400ms
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

-- ============================================================================
-- PURE UTILITY FUNCTIONS
-- ============================================================================

-- Calculate Manhattan distance (pure)
function TargetCore.manhattanDistance(pos1, pos2)
  return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

-- Calculate Chebyshev distance (max of dx, dy - used in Tibia) (pure)
function TargetCore.chebyshevDistance(pos1, pos2)
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

-- Check if position is adjacent (distance 1) (pure)
function TargetCore.isAdjacent(pos1, pos2)
  local dx = math.abs(pos1.x - pos2.x)
  local dy = math.abs(pos1.y - pos2.y)
  return dx <= 1 and dy <= 1 and (dx + dy) > 0
end

-- Check if position is diagonal from another (pure)
function TargetCore.isDiagonal(pos1, pos2)
  local dx = math.abs(pos1.x - pos2.x)
  local dy = math.abs(pos1.y - pos2.y)
  return dx == 1 and dy == 1
end

-- Get direction from pos1 to pos2 (pure)
function TargetCore.getDirection(pos1, pos2)
  local dx = pos2.x - pos1.x
  local dy = pos2.y - pos1.y
  
  if dx == 0 and dy < 0 then return 0 end  -- North
  if dx > 0 and dy == 0 then return 1 end  -- East
  if dx == 0 and dy > 0 then return 2 end  -- South
  if dx < 0 and dy == 0 then return 3 end  -- West
  if dx > 0 and dy < 0 then return 4 end   -- NE
  if dx > 0 and dy > 0 then return 5 end   -- SE
  if dx < 0 and dy > 0 then return 6 end   -- SW
  if dx < 0 and dy < 0 then return 7 end   -- NW
  
  return nil
end

-- Clamp value between min and max (pure)
function TargetCore.clamp(value, min, max)
  if value < min then return min end
  if value > max then return max end
  return value
end

-- Linear interpolation (pure)
function TargetCore.lerp(a, b, t)
  return a + (b - a) * TargetCore.clamp(t, 0, 1)
end

-- ============================================================================
-- WAVE AVOIDANCE SYSTEM (Pure Functions)
-- ============================================================================

--[[
  Wave Attack Detection Algorithm:
  
  Monsters face the player when attacking. A beam/wave attack hits tiles
  in a cone AHEAD of the monster. We check if player is in this danger zone.
  
  For each monster:
  1. Get monster direction
  2. Calculate if player is in the "front arc"
  3. Front arc = player is in the direction monster faces, within beam width
]]

-- Check if position is in monster's front attack arc (pure)
-- @param targetPos: position to check
-- @param monsterPos: monster position
-- @param monsterDir: monster direction (0-7)
-- @param range: attack range (default 5)
-- @param width: beam width (default 1)
-- @return boolean
function TargetCore.isInFrontArc(targetPos, monsterPos, monsterDir, range, width)
  range = range or 5
  width = width or 1
  
  local dirVec = DIR_VEC[monsterDir]
  if not dirVec then return false end
  
  local dx = targetPos.x - monsterPos.x
  local dy = targetPos.y - monsterPos.y
  local dist = math.max(math.abs(dx), math.abs(dy))
  
  -- Must be within range and not at same position
  if dist == 0 or dist > range then
    return false
  end
  
  -- Cardinal directions (N/E/S/W)
  if dirVec.x == 0 then
    -- North/South: player must be in that direction, within width sideways
    local inDirection = (dy * dirVec.y) > 0
    local withinWidth = math.abs(dx) <= width
    return inDirection and withinWidth
    
  elseif dirVec.y == 0 then
    -- East/West: player must be in that direction, within width vertically
    local inDirection = (dx * dirVec.x) > 0
    local withinWidth = math.abs(dy) <= width
    return inDirection and withinWidth
    
  else
    -- Diagonal directions: check if in the quadrant
    local inX = (dirVec.x > 0 and dx > 0) or (dirVec.x < 0 and dx < 0)
    local inY = (dirVec.y > 0 and dy > 0) or (dirVec.y < 0 and dy < 0)
    -- For diagonals, also check proximity to the diagonal line
    local onDiagonal = math.abs(math.abs(dx) - math.abs(dy)) <= width
    return inX and inY and onDiagonal
  end
end

-- Calculate danger score for a position (pure)
-- @param pos: position to evaluate
-- @param monsters: array of {creature, pos, dir} objects
-- @return dangerScore (0 = safe, higher = more dangerous)
function TargetCore.calculatePositionDanger(pos, monsters)
  local danger = 0
  
  for i = 1, #monsters do
    local m = monsters[i]
    if m.creature and not m.creature:isDead() then
      local mpos = m.pos or m.creature:getPosition()
      local mdir = m.dir or m.creature:getDirection()
      local dist = TargetCore.chebyshevDistance(pos, mpos)
      
      -- In front arc = high danger (wave attack)
      if TargetCore.isInFrontArc(pos, mpos, mdir, 6, 1) then
        danger = danger + 30
      end
      
      -- Adjacent = melee danger
      if dist == 1 then
        danger = danger + 15
      elseif dist == 2 then
        danger = danger + 5
      end
    end
  end
  
  return danger
end

-- Find safest adjacent tile (pure)
-- @param playerPos: current position
-- @param monsters: array of monster data
-- @param currentTarget: target creature (optional, to maintain attack range)
-- @param getTileFunc: function(pos) -> tile (dependency injection for testing)
-- @return {pos, danger, score} or nil
function TargetCore.findSafestTile(playerPos, monsters, currentTarget, getTileFunc)
  getTileFunc = getTileFunc or function(p) return g_map.getTile(p) end
  
  local currentDanger = TargetCore.calculatePositionDanger(playerPos, monsters)
  
  -- If current position is safe, don't move
  if currentDanger == 0 then
    return nil
  end
  
  local candidates = {}
  local targetPos = currentTarget and currentTarget:getPosition()
  
  -- Check all 8 adjacent tiles
  for i = 1, 8 do
    local dir = DIRS[i]
    local checkPos = {
      x = playerPos.x + dir.x,
      y = playerPos.y + dir.y,
      z = playerPos.z
    }
    
    local tile = getTileFunc(checkPos)
    if tile and tile:isWalkable() and not tile:hasCreature() then
      local danger = TargetCore.calculatePositionDanger(checkPos, monsters)
      
      -- Calculate composite score (lower = better)
      local score = danger * 10  -- Primary: minimize danger
      
      -- Secondary: maintain distance to target
      if targetPos then
        local targetDist = TargetCore.chebyshevDistance(checkPos, targetPos)
        -- Prefer staying within attack range (1-4 tiles)
        if targetDist > 4 then
          score = score + (targetDist - 4) * 5
        elseif targetDist == 0 then
          score = score + 10  -- Don't walk onto target
        end
      end
      
      -- Prefer cardinal directions (easier movement)
      if dir.x == 0 or dir.y == 0 then
        score = score - 2
      end
      
      candidates[#candidates + 1] = {
        pos = checkPos,
        danger = danger,
        score = score
      }
    end
  end
  
  if #candidates == 0 then
    return nil
  end
  
  -- Sort by score (lowest first)
  table.sort(candidates, function(a, b) return a.score < b.score end)
  
  -- Return best if it's safer than current
  local best = candidates[1]
  if best.danger < currentDanger then
    return best
  end
  
  return nil
end

-- ============================================================================
-- PRIORITY CALCULATION (Pure Functions)
-- ============================================================================

--[[
  Priority Algorithm:
  
  Uses weighted scoring with exponential scaling for critical factors.
  Designed to:
  1. FINISH kills (high priority for low HP monsters)
  2. MAINTAIN focus (bonus for current target)
  3. OPTIMIZE efficiency (consider distance and AOE potential)
  4. RESPECT configuration (user-defined base priority)
]]

-- Calculate target priority (pure)
-- @param params: {creature, config, path, isCurrentTarget, nearbyMonsters}
-- @return priority score (higher = attack first)
function TargetCore.calculatePriority(params)
  local creature = params.creature
  local config = params.config
  local pathLength = params.pathLength or (#params.path or 99)
  local isCurrentTarget = params.isCurrentTarget
  local nearbyMonstersCount = params.nearbyMonsters or 0
  
  -- Early exit: out of range
  local maxDist = config.maxDistance or 10
  if pathLength > maxDist then
    -- Exception: nearly dead monsters still get some priority
    local hp = creature:getHealthPercent()
    if hp <= 15 and pathLength <= maxDist + 2 then
      return config.priority * 0.4
    end
    return 0
  end
  
  local priority = config.priority or 1
  local hp = creature:getHealthPercent()
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- HEALTH-BASED PRIORITY (Most important - finish kills!)
  -- Uses exponential scaling for critical health
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if hp <= 5 then
    -- One-hit kill potential - HIGHEST priority
    priority = priority + PRIO.CRITICAL_HEALTH + 30
  elseif hp <= 10 then
    priority = priority + PRIO.CRITICAL_HEALTH
  elseif hp <= 20 then
    priority = priority + PRIO.VERY_LOW_HEALTH
  elseif hp <= 30 then
    priority = priority + PRIO.LOW_HEALTH
  elseif hp <= 50 then
    priority = priority + PRIO.WOUNDED
  elseif hp <= 70 then
    priority = priority + 5
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- CURRENT TARGET BONUS (Target stickiness to finish kills)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if isCurrentTarget then
    priority = priority + PRIO.CURRENT_TARGET
    
    -- Extra bonus for wounded current target (DON'T SWITCH!)
    if hp < 50 then
      priority = priority + PRIO.CURRENT_WOUNDED
    end
    if hp < 20 then
      priority = priority + 15  -- Critical - finish this kill
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- DISTANCE-BASED PRIORITY (Prefer closer targets)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  local distWeight = DIST_W[pathLength] or 0
  priority = priority + distWeight
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- CHASE MODE BONUS
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if config.chase and hp < 35 then
    priority = priority + PRIO.CHASE_BONUS
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- AOE OPTIMIZATION (Diamond arrows, spell areas)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if config.diamondArrows and nearbyMonstersCount > 1 then
    priority = priority + (nearbyMonstersCount - 1) * PRIO.AOE_BONUS
  end
  
  return priority
end

-- ============================================================================
-- POSITIONING ALGORITHMS (Pure Functions)
-- ============================================================================

-- Count walkable adjacent tiles (escape routes) (pure)
function TargetCore.countEscapeRoutes(pos, getTileFunc)
  getTileFunc = getTileFunc or function(p) return g_map.getTile(p) end
  local count = 0
  
  for i = 1, 8 do
    local dir = DIRS[i]
    local checkPos = {
      x = pos.x + dir.x,
      y = pos.y + dir.y,
      z = pos.z
    }
    local tile = getTileFunc(checkPos)
    if tile and tile:isWalkable() then
      count = count + 1
    end
  end
  
  return count
end

-- Check if position is trapped (no escape routes) (pure)
function TargetCore.isTrapped(pos, getTileFunc)
  return TargetCore.countEscapeRoutes(pos, getTileFunc) == 0
end

-- Score a position for repositioning (pure)
-- @param pos: position to evaluate
-- @param context: {playerPos, targetPos, monsters, anchorPos, anchorRange}
-- @return score (higher = better position)
function TargetCore.scorePosition(pos, context, getTileFunc)
  getTileFunc = getTileFunc or function(p) return g_map.getTile(p) end
  
  local score = 0
  
  -- Factor 1: Escape routes (most important)
  local escapeRoutes = TargetCore.countEscapeRoutes(pos, getTileFunc)
  score = score + escapeRoutes * 15
  
  -- Factor 2: Danger from monsters
  if context.monsters then
    local danger = TargetCore.calculatePositionDanger(pos, context.monsters)
    score = score - danger * 2
  end
  
  -- Factor 3: Distance to target (maintain attack range)
  if context.targetPos then
    local targetDist = TargetCore.chebyshevDistance(pos, context.targetPos)
    if targetDist <= 1 then
      score = score + 25  -- Adjacent is ideal for melee
    elseif targetDist <= 3 then
      score = score + 15  -- Good range
    elseif targetDist <= 5 then
      score = score + 5   -- Acceptable
    else
      score = score - (targetDist - 5) * 3  -- Penalize too far
    end
  end
  
  -- Factor 4: Anchor constraint
  if context.anchorPos and context.anchorRange then
    local anchorDist = TargetCore.chebyshevDistance(pos, context.anchorPos)
    if anchorDist > context.anchorRange then
      return -9999  -- Invalid position - violates anchor
    end
  end
  
  -- Factor 5: Movement cost
  if context.playerPos then
    local moveDist = TargetCore.manhattanDistance(pos, context.playerPos)
    score = score - moveDist * 2
  end
  
  return score
end

-- Find best position in radius (pure)
-- @param centerPos: center of search
-- @param radius: search radius
-- @param context: scoring context
-- @return {pos, score} or nil
function TargetCore.findBestPosition(centerPos, radius, context, getTileFunc)
  getTileFunc = getTileFunc or function(p) return g_map.getTile(p) end
  
  local best = nil
  local bestScore = -9999
  
  for dx = -radius, radius do
    for dy = -radius, radius do
      if dx ~= 0 or dy ~= 0 then
        local checkPos = {
          x = centerPos.x + dx,
          y = centerPos.y + dy,
          z = centerPos.z
        }
        
        local tile = getTileFunc(checkPos)
        if tile and tile:isWalkable() and not tile:hasCreature() then
          local score = TargetCore.scorePosition(checkPos, context, getTileFunc)
          
          if score > bestScore then
            bestScore = score
            best = {pos = checkPos, score = score}
          end
        end
      end
    end
  end
  
  return best
end

-- ============================================================================
-- METRICS & ANALYTICS
-- ============================================================================

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

function TargetCore.Metrics.reset()
  TargetCore.Metrics.targetsKilled = 0
  TargetCore.Metrics.targetsSwitched = 0
  TargetCore.Metrics.avoidancesMoved = 0
  TargetCore.Metrics.pathsCalculated = 0
  TargetCore.Metrics.cacheHits = 0
  TargetCore.Metrics.cacheMisses = 0
  TargetCore.Metrics.avgPriorityCalcTime = 0
  TargetCore.Metrics.lastReset = now
end

function TargetCore.Metrics.getCacheHitRate()
  local total = TargetCore.Metrics.cacheHits + TargetCore.Metrics.cacheMisses
  if total == 0 then return 0 end
  return TargetCore.Metrics.cacheHits / total * 100
end

-- ============================================================================
-- OTCLIENT NATIVE API HELPERS
-- 
-- Wrappers for OTClient's game API to handle version differences and
-- provide caching to reduce unnecessary API calls
-- ============================================================================

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
-- @param mode: 0 = Stand, 1 = Chase
-- @return boolean: true if mode was changed
function TargetCore.Native.setChaseMode(mode)
  if TargetCore.Native.lastChaseMode == mode then
    return false  -- No change needed
  end
  
  if g_game.setChaseMode then
    g_game.setChaseMode(mode)
    TargetCore.Native.lastChaseMode = mode
    return true
  end
  return false
end

-- Get current chase mode (cached)
function TargetCore.Native.getChaseMode()
  if g_game.getChaseMode then
    TargetCore.Native.lastChaseMode = g_game.getChaseMode()
  end
  return TargetCore.Native.lastChaseMode or 0
end

-- Follow creature with validation
-- @param creature: creature to follow
-- @return boolean: true if follow was initiated
function TargetCore.Native.followCreature(creature)
  if not creature or creature:isDead() then
    return false
  end
  
  -- Check if already following this creature
  local currentFollow = g_game.getFollowingCreature and g_game.getFollowingCreature()
  if currentFollow and currentFollow:getId() == creature:getId() then
    return true  -- Already following
  end
  
  -- Set chase mode to chase opponent for better pathfinding
  TargetCore.Native.setChaseMode(TargetCore.Native.CHASE_MODE.CHASE)
  
  -- Use g_game.follow if available, otherwise fall back to bot's follow()
  if g_game.follow then
    g_game.follow(creature)
  elseif follow then
    follow(creature)
  else
    return false
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

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

print("[TargetCore] v1.0 loaded (Pure functions, SOLID principles)")
