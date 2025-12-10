--[[
  BotCore: Creatures Module
  
  High-performance creature utility functions with memoization.
  Consolidates creature-related operations from lib.lua, AttackBot, and TargetBot.
  
  Features:
    - Cached monster/player counting (100ms TTL)
    - Shape-based counting (square, circle, diamond, cone)
    - Pre-computed direction offsets
    - Friend/enemy lookup optimization
]]

local Creatures = {}
BotCore.Creatures = Creatures

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local CACHE_TTL = 100  -- Cache TTL in ms
local FRIEND_CACHE_TTL = 5000  -- Friend list cache TTL

-- Cache state
local cache = {
  monsters = {},
  players = {},
  spectators = {},
  lastUpdate = 0,
  friendList = {},
  friendListTime = 0,
  enemyList = {},
  enemyListTime = 0
}

-- ============================================================================
-- SHAPE CONSTANTS (exported for external use)
-- ============================================================================

Creatures.SHAPE = {
  SQUARE = 1,   -- Chebyshev distance (default Tibia range)
  CIRCLE = 2,   -- Euclidean distance (true circle)
  DIAMOND = 3,  -- Manhattan distance (rotated square)
  CROSS = 4,    -- Cardinal directions only
  CONE = 5      -- Directional cone
}

-- Pre-computed direction vectors for cone
local CONE_DIRECTIONS = {
  [0] = {x = 0, y = -1},  -- North
  [1] = {x = 1, y = 0},   -- East
  [2] = {x = 0, y = 1},   -- South
  [3] = {x = -1, y = 0}   -- West
}

-- Cache client version (doesn't change)
local isOldClient = g_game.getClientVersion() < 960

-- ============================================================================
-- PURE FUNCTIONS
-- ============================================================================

-- Pure function: Check if position is within shape
-- @param dx: x distance from center (absolute)
-- @param dy: y distance from center (absolute)
-- @param range: maximum range
-- @param shape: shape type (SHAPE enum)
-- @param direction: player direction (0-3) for cone shape
-- @param coneAngle: cone half-angle in tiles (default 1)
-- @return boolean
local function isInShape(dx, dy, range, shape, direction, coneAngle)
  shape = shape or Creatures.SHAPE.SQUARE
  
  if shape == Creatures.SHAPE.SQUARE then
    return math.max(dx, dy) <= range
    
  elseif shape == Creatures.SHAPE.CIRCLE then
    return (dx * dx + dy * dy) <= (range * range)
    
  elseif shape == Creatures.SHAPE.DIAMOND then
    return (dx + dy) <= range
    
  elseif shape == Creatures.SHAPE.CROSS then
    return (dx == 0 or dy == 0) and math.max(dx, dy) <= range
    
  elseif shape == Creatures.SHAPE.CONE then
    direction = direction or 0
    coneAngle = coneAngle or 1
    
    local dir = CONE_DIRECTIONS[direction]
    if not dir then return false end
    
    if dir.y ~= 0 then
      local inFront = (dy * dir.y) > 0
      local withinSpread = dx <= coneAngle
      local withinRange = dy <= range
      return inFront and withinSpread and withinRange
    else
      local inFront = (dx * dir.x) > 0
      local withinSpread = dy <= coneAngle
      local withinRange = dx <= range
      return inFront and withinSpread and withinRange
    end
  end
  
  return false
end

-- Export for external use
Creatures.isInShape = isInShape

-- ============================================================================
-- CACHE MANAGEMENT
-- ============================================================================

local function invalidateCache()
  cache.monsters = {}
  cache.players = {}
  cache.spectators = {}
  cache.lastUpdate = now
end

-- Invalidate on position change
if onPlayerPositionChange then
  onPlayerPositionChange(function()
    invalidateCache()
  end)
end

-- ============================================================================
-- MONSTER COUNTING
-- ============================================================================

-- Get monster count with caching and shape support
-- @param range: maximum range (default 10)
-- @param options: optional table {shape, multifloor, direction, coneAngle, center, filter}
-- @return number
function Creatures.getMonsterCount(range, options)
  range = range or 10
  options = options or {}
  
  local shape = options.shape or Creatures.SHAPE.SQUARE
  local multifloor = options.multifloor
  local direction = options.direction or (player and player:getDirection())
  local coneAngle = options.coneAngle or 1
  local center = options.center or (player and player:getPosition())
  local filter = options.filter
  
  if not center then return 0 end
  
  -- Generate cache key
  local cacheKey = string.format("%d_%d_%s_%d", range, shape, tostring(multifloor), direction or 0)
  
  -- Check cache
  if now - cache.lastUpdate < CACHE_TTL then
    if cache.monsters[cacheKey] and not filter then
      return cache.monsters[cacheKey]
    end
  else
    invalidateCache()
  end
  
  -- Count monsters
  local count = 0
  local px, py = center.x, center.y
  
  for _, spec in pairs(getSpectators(multifloor)) do
    if spec:isMonster() and (isOldClient or spec:getType() < 3) then
      if not filter or filter(spec) then
        local specPos = spec:getPosition()
        local dx = math.abs(specPos.x - px)
        local dy = math.abs(specPos.y - py)
        
        if isInShape(dx, dy, range, shape, direction, coneAngle) then
          count = count + 1
        end
      end
    end
  end
  
  -- Cache result (only if no custom filter)
  if not filter then
    cache.monsters[cacheKey] = count
  end
  
  return count
end

-- Convenience functions
function Creatures.getMonstersInRange(range, multifloor)
  return Creatures.getMonsterCount(range, {multifloor = multifloor})
end

function Creatures.getMonstersCircle(range, multifloor)
  return Creatures.getMonsterCount(range, {shape = Creatures.SHAPE.CIRCLE, multifloor = multifloor})
end

function Creatures.getMonstersDiamond(range, multifloor)
  return Creatures.getMonsterCount(range, {shape = Creatures.SHAPE.DIAMOND, multifloor = multifloor})
end

function Creatures.getMonstersCone(range, spread, multifloor)
  return Creatures.getMonsterCount(range, {shape = Creatures.SHAPE.CONE, coneAngle = spread or 1, multifloor = multifloor})
end

-- ============================================================================
-- PLAYER COUNTING
-- ============================================================================

-- Get player count (non-party, non-local) with caching
-- @param range: maximum range (default 10)
-- @param multifloor: check multiple floors
-- @return number
function Creatures.getPlayerCount(range, multifloor)
  range = range or 10
  
  local cacheKey = string.format("players_%d_%s", range, tostring(multifloor))
  
  if now - cache.lastUpdate < CACHE_TTL and cache.players[cacheKey] then
    return cache.players[cacheKey]
  end
  
  local count = 0
  local playerPos = player:getPosition()
  local px, py = playerPos.x, playerPos.y
  
  for _, spec in pairs(getSpectators(multifloor)) do
    if spec:isPlayer() and not spec:isLocalPlayer() then
      local specPos = spec:getPosition()
      local dx = math.abs(specPos.x - px)
      local dy = math.abs(specPos.y - py)
      
      if math.max(dx, dy) <= range then
        local shield = spec:getShield()
        local emblem = spec:getEmblem()
        if not ((shield ~= 1 and spec:isPartyMember()) or emblem == 1) then
          count = count + 1
        end
      end
    end
  end
  
  cache.players[cacheKey] = count
  return count
end

-- ============================================================================
-- DISTANCE UTILITIES
-- ============================================================================

-- Get distance from player to a position
-- @param coords: position table with x, y, z
-- @return number or false
function Creatures.distanceFromPlayer(coords)
  if not coords then return false end
  return getDistanceBetween(pos(), coords)
end

-- ============================================================================
-- TARGET UTILITIES
-- ============================================================================

-- Get current target creature
-- @return creature or nil
function Creatures.getTarget()
  if not g_game.isAttacking() then return nil end
  return g_game.getAttackingCreature()
end

-- Get target position
-- @param getDistance: if true, return distance instead of position
-- @return position or number or nil
function Creatures.getTargetPos(getDistance)
  local target = Creatures.getTarget()
  if not target then return nil end
  
  local targetPos = target:getPosition()
  if getDistance then
    return Creatures.distanceFromPlayer(targetPos)
  end
  return targetPos
end

-- Check if target is in range
-- @param range: maximum range
-- @return boolean
function Creatures.isTargetInRange(range)
  local dist = Creatures.getTargetPos(true)
  return dist ~= nil and dist <= (range or 1)
end

-- ============================================================================
-- CREATURES IN AREA (pattern-based)
-- ============================================================================

-- Get creatures in area by pattern
-- @param pos: center position
-- @param pattern: pattern string
-- @param creatureType: 1=all, 2=monsters, 3=players
-- @return number
function Creatures.getInArea(centerPos, pattern, creatureType)
  creatureType = creatureType or 1
  
  local specs = 0
  local monsters = 0
  local players = 0
  
  for _, spec in pairs(getSpectators(centerPos, pattern)) do
    if spec ~= player then
      specs = specs + 1
      if spec:isMonster() and (isOldClient or spec:getType() < 3) then
        monsters = monsters + 1
      elseif spec:isPlayer() and not isFriend(spec:getName()) then
        players = players + 1
      end
    end
  end
  
  if creatureType == 1 then
    return specs
  elseif creatureType == 2 then
    return monsters
  else
    return players
  end
end

-- ============================================================================
-- SAFETY CHECKS
-- ============================================================================

-- Check if area is safe (no non-friend players)
-- @param range: check range
-- @param multifloor: check multiple floors
-- @param padding: additional range for other floors
-- @return boolean
function Creatures.isSafe(range, multifloor, padding)
  if not multifloor and padding then
    multifloor = false
    padding = false
  end
  
  for _, spec in pairs(getSpectators(multifloor)) do
    if spec:isPlayer() and not spec:isLocalPlayer() and not isFriend(spec:getName()) then
      local specZ = spec:getPosition().z
      local dist = Creatures.distanceFromPlayer(spec:getPosition())
      
      if specZ == posz() and dist <= range then
        return false
      end
      
      if multifloor and padding and specZ ~= posz() and dist <= (range + padding) then
        return false
      end
    end
  end
  
  return true
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Log successful load
if logInfo then
  logInfo("[BotCore] Creatures module loaded")
end

return Creatures
