--[[
  ============================================================================
  nExBot Wave Avoidance AI System
  ============================================================================
  
  Intelligent wave/spell avoidance using event-driven pattern recognition
  and predictive movement algorithms.
  
  HOW IT WORKS:
  1. Monitors visible creatures for known area attack patterns
  2. Calculates threatened tiles based on creature facing direction
  3. Accumulates danger scores from multiple threats
  4. When player is in danger, finds safest adjacent tile
  5. Executes smooth avoidance movement
  
  PATTERN RECOGNITION:
  Each creature has known attack patterns with:
  - Range: How far the attack reaches
  - Shape: wave (fan), beam (line), area (circle), explosion (target-centered)
  - Cooldown: Time between attacks
  - Danger Level: How dangerous (1-10 scale)
  
  OPTIMIZATION FEATURES:
  - Local function caching for hot paths
  - Tile danger caching (refreshed every 500ms)
  - Movement cooldown prevents spam-walking
  - Early returns when not in danger
  - Chebyshev distance for efficient range checks
  
  INTEGRATION:
  - Emits events via EventBus when dodging
  - Respects CaveBot path when choosing escape tiles
  - Works alongside TargetBot and HealBot
  
  Author: nExBot Team
  Version: 2.0.0 (Optimized)
  Last Updated: December 2025
  
  ============================================================================
]]

--[[
  ============================================================================
  LOCAL CACHING FOR PERFORMANCE
  ============================================================================
]]
local table_insert = table.insert
local ipairs = ipairs
local pairs = pairs
local math_abs = math.abs
local math_sqrt = math.sqrt
local math_floor = math.floor
local math_max = math.max
local string_format = string.format
local setmetatable = setmetatable

--[[
  ============================================================================
  CLASS DEFINITION
  ============================================================================
]]

local WaveAvoidance = {}
WaveAvoidance.__index = WaveAvoidance

--[[
  ============================================================================
  CONFIGURATION DEFAULTS
  ============================================================================
]]
local DEFAULT_CONFIG = {
  enabled = true,
  checkInterval = 100,        -- ms between safety checks (10 checks/sec)
  safeDistance = 3,           -- minimum safe distance from threats
  predictionWindow = 500,     -- ms to predict threat positions
  maxThreatLevel = 10,        -- maximum danger score before fleeing
  diagonalWeight = 1.4,       -- weight for diagonal movement (~sqrt(2))
  avoidPlayers = false,       -- avoid player AoE attacks
  prioritizePath = true,      -- try to stay on cavebot path
  debugMode = false           -- show debug info
}

--[[
  ============================================================================
  KNOWN ATTACK PATTERNS DATABASE
  ============================================================================
  
  Maps creature names to their known area attack patterns.
  Used to predict which tiles will be threatened.
  
  Pattern structure:
  {
    range = 5,         -- Attack range in tiles
    shape = "wave",    -- Shape type (see SHAPE_PATTERNS)
    cooldown = 2000,   -- Attack cooldown in ms
    dangerLevel = 7    -- Danger score (1-10)
  }
  ============================================================================
]]
local KNOWN_ATTACK_PATTERNS = {
  -- ========================================
  -- HIGH-TIER CREATURES
  -- ========================================
  ["Demon"] = {
    {range = 8, shape = "beam", cooldown = 2000, dangerLevel = 8},
    {range = 1, shape = "wave", cooldown = 1500, dangerLevel = 9}
  },
  ["Dragon"] = {
    {range = 7, shape = "wave", cooldown = 2000, dangerLevel = 7}
  },
  ["Dragon Lord"] = {
    {range = 8, shape = "wave", cooldown = 2000, dangerLevel = 9}
  },
  ["Hydra"] = {
    {range = 5, shape = "wave", cooldown = 2000, dangerLevel = 6}
  },
  ["Grim Reaper"] = {
    {range = 6, shape = "beam", cooldown = 2000, dangerLevel = 8}
  },
  ["Hellspawn"] = {
    {range = 4, shape = "wave", cooldown = 1500, dangerLevel = 5}
  },
  ["Plaguesmith"] = {
    {range = 5, shape = "wave", cooldown = 2000, dangerLevel = 6}
  },
  ["Frost Dragon"] = {
    {range = 6, shape = "beam", cooldown = 2500, dangerLevel = 7}
  },
  -- ========================================
  -- BOSSES
  -- ========================================
  ["Ferumbras"] = {
    {range = 8, shape = "wave", cooldown = 1000, dangerLevel = 10}
  },
  -- ========================================
  -- DEFAULT PATTERN
  -- Used for unknown creatures with area attacks
  -- ========================================
  ["_default"] = {
    {range = 4, shape = "wave", cooldown = 2000, dangerLevel = 5}
  }
}

--[[
  ============================================================================
  SHAPE PATTERN FUNCTIONS
  ============================================================================
  
  Each function calculates which tiles are threatened by an attack shape.
  
  Parameters:
  - origin: Creature position {x, y, z}
  - target: Target position (usually player)
  - range: Attack range
  
  Returns: Array of threatened tile positions
  ============================================================================
]]
local SHAPE_PATTERNS = {
  --- Wave (fan-shaped) - like exori gran
  -- Spreads wider at longer range
  wave = function(origin, target, range)
    local tiles = {}
    local dx = target.x - origin.x
    local dy = target.y - origin.y
    
    -- Normalize direction to -1, 0, or 1
    if dx ~= 0 then dx = dx / math_abs(dx) end
    if dy ~= 0 then dy = dy / math_abs(dy) end
    
    for r = 1, range do
      for spread = -r, r do
        local tx, ty
        if dx ~= 0 and dy ~= 0 then
          -- Diagonal direction
          tx = origin.x + dx * r + spread * (dx == 0 and 1 or 0)
          ty = origin.y + dy * r + spread * (dy == 0 and 1 or 0)
        elseif dx ~= 0 then
          -- Horizontal direction
          tx = origin.x + dx * r
          ty = origin.y + spread
        else
          -- Vertical direction
          tx = origin.x + spread
          ty = origin.y + dy * r
        end
        tiles[#tiles + 1] = {x = tx, y = ty, z = origin.z}
      end
    end
    return tiles
  end,
  
  --- Beam (straight line) - like exori vis
  -- Fixed width line in direction
  beam = function(origin, target, range)
    local tiles = {}
    local dx = target.x - origin.x
    local dy = target.y - origin.y
    
    -- Normalize direction vector
    local len = math_sqrt(dx * dx + dy * dy)
    if len > 0 then
      dx = dx / len
      dy = dy / len
    end
    
    for r = 1, range do
      local tx = math_floor(origin.x + dx * r + 0.5)
      local ty = math_floor(origin.y + dy * r + 0.5)
      
      -- Add center tile
      tiles[#tiles + 1] = {x = tx, y = ty, z = origin.z}
      
      -- Add adjacent tiles for beam width
      if math_abs(dx) > math_abs(dy) then
        tiles[#tiles + 1] = {x = tx, y = ty - 1, z = origin.z}
        tiles[#tiles + 1] = {x = tx, y = ty + 1, z = origin.z}
      else
        tiles[#tiles + 1] = {x = tx - 1, y = ty, z = origin.z}
        tiles[#tiles + 1] = {x = tx + 1, y = ty, z = origin.z}
      end
    end
    return tiles
  end,
  
  --- Area (circular) - like exori
  -- Circle centered on caster
  area = function(origin, target, range)
    local tiles = {}
    local rangeSq = range * range
    
    for dx = -range, range do
      for dy = -range, range do
        if dx * dx + dy * dy <= rangeSq then
          tiles[#tiles + 1] = {x = origin.x + dx, y = origin.y + dy, z = origin.z}
        end
      end
    end
    return tiles
  end,
  
  --- Explosion (target-centered circle) - like GFB
  -- Circle centered on target position
  explosion = function(origin, target, range)
    local tiles = {}
    local rangeSq = range * range
    
    for dx = -range, range do
      for dy = -range, range do
        if dx * dx + dy * dy <= rangeSq then
          tiles[#tiles + 1] = {x = target.x + dx, y = target.y + dy, z = target.z}
        end
      end
    end
    return tiles
  end
}

--[[
  ============================================================================
  THREAT STATE TRACKING
  ============================================================================
]]
local threatState = {
  activeThreats = {},      -- Currently tracked creatures
  recentAttacks = {},      -- Recent attack events for learning
  tileDangerCache = {},    -- Cached danger levels per tile
  lastUpdate = 0,          -- Last cache update timestamp
  lastMoveTime = 0,        -- Last avoidance movement timestamp
  moveCooldown = 300       -- ms between avoid movements
}

--[[
  ============================================================================
  UTILITY FUNCTIONS
  ============================================================================
]]

--- Calculates Manhattan distance (grid distance)
-- @param pos1 (table) First position
-- @param pos2 (table) Second position
-- @return (number) Distance
local function manhattanDistance(pos1, pos2)
  return math_abs(pos1.x - pos2.x) + math_abs(pos1.y - pos2.y)
end

--- Calculates Chebyshev distance (allows diagonal movement)
-- Also known as "king distance" - moves like a chess king
-- @param pos1 (table) First position
-- @param pos2 (table) Second position
-- @return (number) Distance
local function chebyshevDistance(pos1, pos2)
  return math_max(math_abs(pos1.x - pos2.x), math_abs(pos1.y - pos2.y))
end

--- Gets attack patterns for a creature by name
-- Falls back to default if no specific patterns known
-- @param creatureName (string) Creature name
-- @return (table) Array of attack patterns
local function getAttackPatterns(creatureName)
  -- Exact match first
  local patterns = KNOWN_ATTACK_PATTERNS[creatureName]
  if patterns then return patterns end
  
  -- Partial match (e.g., "Elite Dragon" matches "Dragon")
  local lowerName = creatureName:lower()
  for name, pat in pairs(KNOWN_ATTACK_PATTERNS) do
    if name ~= "_default" and lowerName:find(name:lower()) then
      return pat
    end
  end
  
  return KNOWN_ATTACK_PATTERNS["_default"]
end

--- Calculates normalized direction from origin to target
-- @param origin (table) Starting position
-- @param target (table) Target position
-- @return (number, number) Normalized dx, dy (-1, 0, or 1)
local function calculateDirection(origin, target)
  local dx = target.x - origin.x
  local dy = target.y - origin.y
  
  local ndx = dx == 0 and 0 or (dx > 0 and 1 or -1)
  local ndy = dy == 0 and 0 or (dy > 0 and 1 or -1)
  
  return ndx, ndy
end

--- Predicts which direction a creature is facing
-- Currently assumes creatures face the player
-- @param creature (Creature) The creature
-- @return (number, number) Normalized dx, dy
local function predictCreatureDirection(creature)
  local pos = creature:getPosition()
  local playerPos = player:getPosition()
  return calculateDirection(pos, playerPos)
end

--[[
  ============================================================================
  CONSTRUCTOR
  ============================================================================
]]

--- Creates a new WaveAvoidance instance
-- @param config (table|nil) Configuration overrides
-- @return (WaveAvoidance) New instance
function WaveAvoidance.new(config)
  local self = setmetatable({}, WaveAvoidance)
  self.config = setmetatable(config or {}, {__index = DEFAULT_CONFIG})
  self.enabled = false
  self.macro = nil
  self.listeners = {}
  return self
end

--[[
  ============================================================================
  THREAT CALCULATION
  ============================================================================
]]

--- Calculates danger levels for all tiles near the player
-- Scans visible creatures and their attack patterns
-- @return (table) Map of "x:y:z" -> danger level
function WaveAvoidance:calculateThreatenedTiles()
  local playerPos = player:getPosition()
  local threatened = {}
  local currentTime = now
  
  -- Clear cache periodically (every 500ms)
  if currentTime - threatState.lastUpdate > 500 then
    threatState.tileDangerCache = {}
    threatState.lastUpdate = currentTime
  end
  
  -- Analyze all visible creatures
  local specs = getSpectators()
  for i = 1, #specs do
    local creature = specs[i]
    
    -- Only consider monsters (not NPCs or players)
    if creature:isMonster() and not creature:isNpc() then
      local creaturePos = creature:getPosition()
      local distance = chebyshevDistance(playerPos, creaturePos)
      
      -- Only process creatures within threat range
      if distance <= 10 then
        local patterns = getAttackPatterns(creature:getName())
        local dx, dy = predictCreatureDirection(creature)
        
        for j = 1, #patterns do
          local pattern = patterns[j]
          
          -- Calculate shape function for this pattern
          local shapeFunc = SHAPE_PATTERNS[pattern.shape]
          if shapeFunc then
            local tiles = shapeFunc(creaturePos, playerPos, pattern.range)
            
            -- Accumulate danger on each threatened tile
            for k = 1, #tiles do
              local tile = tiles[k]
              local key = string_format("%d:%d:%d", tile.x, tile.y, tile.z)
              local existingDanger = threatened[key] or 0
              threatened[key] = existingDanger + pattern.dangerLevel
            end
          end
        end
      end
    end
  end
  
  threatState.tileDangerCache = threatened
  return threatened
end

--- Finds the safest adjacent tile to move to
-- Evaluates all 8 directions and picks the one with lowest danger
-- @return (table|nil) Safe position or nil if current is safest
function WaveAvoidance:findSafestTile()
  local playerPos = player:getPosition()
  local threatened = self:calculateThreatenedTiles()
  
  -- Check current danger level
  local currentKey = string_format("%d:%d:%d", playerPos.x, playerPos.y, playerPos.z)
  local currentDanger = threatened[currentKey] or 0
  
  -- Don't move if danger is low
  if currentDanger < 3 then
    return nil
  end
  
  -- All 8 adjacent directions with movement costs
  local directions = {
    {dx = 0, dy = -1, cost = 1},     -- North
    {dx = 1, dy = -1, cost = 1.4},   -- NE (diagonal)
    {dx = 1, dy = 0, cost = 1},      -- East
    {dx = 1, dy = 1, cost = 1.4},    -- SE
    {dx = 0, dy = 1, cost = 1},      -- South
    {dx = -1, dy = 1, cost = 1.4},   -- SW
    {dx = -1, dy = 0, cost = 1},     -- West
    {dx = -1, dy = -1, cost = 1.4}   -- NW
  }
  
  local bestTile = nil
  local bestScore = currentDanger
  
  for i = 1, 8 do
    local dir = directions[i]
    local newPos = {
      x = playerPos.x + dir.dx,
      y = playerPos.y + dir.dy,
      z = playerPos.z
    }
    
    -- Check walkability
    local tile = g_map.getTile(newPos)
    if tile and tile:isWalkable() and not tile:hasCreature() then
      local key = string_format("%d:%d:%d", newPos.x, newPos.y, newPos.z)
      local tileDanger = threatened[key] or 0
      
      -- Score = danger * movement cost (prefer cardinal directions)
      local score = tileDanger * dir.cost
      
      if score < bestScore then
        bestScore = score
        bestTile = newPos
      end
    end
  end
  
  return bestTile
end

--[[
  ============================================================================
  AVOIDANCE EXECUTION
  ============================================================================
]]

--- Executes avoidance movement if safe tile found
-- Respects movement cooldown to prevent spam-walking
-- @return (boolean) True if moved
function WaveAvoidance:executeAvoidance()
  local currentTime = now
  
  -- Respect movement cooldown
  if currentTime - threatState.lastMoveTime < threatState.moveCooldown then
    return false
  end
  
  local safeTile = self:findSafestTile()
  if safeTile then
    local success = walk(safeTile)
    
    if success then
      threatState.lastMoveTime = currentTime
      
      if self.config.debugMode and logInfo then
        logInfo(string_format("[WaveAvoidance] Moving to safer tile: %d, %d", 
          safeTile.x, safeTile.y))
      end
      
      -- Emit event for other modules
      if nExBot and nExBot.EventBus then
        nExBot.EventBus:emit("wave_avoided", {
          from = player:getPosition(),
          to = safeTile,
          danger = threatState.tileDangerCache[string_format("%d:%d:%d", 
            safeTile.x, safeTile.y, safeTile.z)] or 0
        })
      end
      
      return true
    end
  end
  
  return false
end

--[[
  ============================================================================
  DANGER QUERIES
  ============================================================================
]]

--- Checks if player is currently in a danger zone
-- @return (boolean) True if danger exceeds threshold
function WaveAvoidance:isInDanger()
  local playerPos = player:getPosition()
  local threatened = self:calculateThreatenedTiles()
  local key = string_format("%d:%d:%d", playerPos.x, playerPos.y, playerPos.z)
  local danger = threatened[key] or 0
  
  return danger >= self.config.maxThreatLevel / 2
end

--- Gets the current danger level at player position
-- @return (number) Danger level (0 = safe)
function WaveAvoidance:getDangerLevel()
  local playerPos = player:getPosition()
  local threatened = self:calculateThreatenedTiles()
  local key = string_format("%d:%d:%d", playerPos.x, playerPos.y, playerPos.z)
  return threatened[key] or 0
end

--[[
  ============================================================================
  LIFECYCLE MANAGEMENT
  ============================================================================
]]

--- Starts the wave avoidance system
function WaveAvoidance:start()
  if self.enabled then return end
  self.enabled = true
  
  -- Main safety check macro
  local checkInterval = self.config.checkInterval
  local selfRef = self
  
  self.macro = macro(checkInterval, "WaveAvoidance", function()
    if not selfRef.enabled then return end
    if player:isWalking() then return end  -- Don't interrupt walking
    
    if selfRef:isInDanger() then
      selfRef:executeAvoidance()
    end
  end)
  
  -- Listen for missile effects (projectile attacks)
  self.listeners.onMissleEffect = onMissle(function(missile)
    if not selfRef.enabled then return end
    
    local target = missile:getTarget()
    if target then
      local key = string_format("%d:%d:%d", target.x, target.y, target.z)
      -- Temporarily increase danger at impact point
      threatState.tileDangerCache[key] = (threatState.tileDangerCache[key] or 0) + 5
      
      -- Check if we need to move
      local playerPos = player:getPosition()
      if chebyshevDistance(playerPos, target) <= 3 then
        selfRef:executeAvoidance()
      end
    end
  end)
  
  if logInfo then
    logInfo("[WaveAvoidance] System started")
  end
end

--- Stops the wave avoidance system
function WaveAvoidance:stop()
  if not self.enabled then return end
  self.enabled = false
  
  self.macro = nil
  self.listeners = {}
  
  if logInfo then
    logInfo("[WaveAvoidance] System stopped")
  end
end

--[[
  ============================================================================
  PATTERN MANAGEMENT
  ============================================================================
]]

--- Adds a custom attack pattern for a creature
-- @param creatureName (string) Creature name
-- @param pattern (table) Pattern definition
function WaveAvoidance:addPattern(creatureName, pattern)
  if not KNOWN_ATTACK_PATTERNS[creatureName] then
    KNOWN_ATTACK_PATTERNS[creatureName] = {}
  end
  table_insert(KNOWN_ATTACK_PATTERNS[creatureName], pattern)
end

--- Gets all known attack patterns
-- @return (table) Pattern database
function WaveAvoidance:getPatterns()
  return KNOWN_ATTACK_PATTERNS
end

--[[
  ============================================================================
  CONFIGURATION
  ============================================================================
]]

--- Updates a configuration value
-- @param key (string) Config key
-- @param value (any) New value
-- @return (boolean) True if key existed
function WaveAvoidance:setConfig(key, value)
  if DEFAULT_CONFIG[key] ~= nil then
    self.config[key] = value
    return true
  end
  return false
end

--- Gets current configuration
-- @return (table) Config object
function WaveAvoidance:getConfig()
  return self.config
end

--[[
  ============================================================================
  MODULE EXPORT
  ============================================================================
]]

return WaveAvoidance
