--[[
  nExBot Luring Patterns
  Generates movement patterns for creature luring
  
  Patterns:
  - Circular: Classic circle around a point
  - Spiral: Expanding/contracting spiral
  - Figure Eight: Infinity pattern
  - Random Walk: Unpredictable movement
  
  Author: nExBot Team
  Version: 1.0.0
]]

local LuringPatterns = {}

-- Pattern type constants
LuringPatterns.TYPES = {
  CIRCULAR = "circular",
  SPIRAL = "spiral",
  FIGURE_EIGHT = "figure_eight",
  RANDOM_WALK = "random_walk",
  RECTANGLE = "rectangle",
  ZIGZAG = "zigzag"
}

-- Generate circular luring pattern
-- @param centerPos table - Center position {x, y, z}
-- @param radius number - Circle radius in tiles
-- @param density number - Number of waypoints (higher = smoother)
-- @return table - Array of waypoint positions
function LuringPatterns:generateCircular(centerPos, radius, density)
  local waypoints = {}
  density = density or 12
  radius = radius or 5
  
  local angleStep = (2 * math.pi) / density
  
  for i = 0, density - 1 do
    local angle = i * angleStep
    local x = centerPos.x + math.cos(angle) * radius
    local y = centerPos.y + math.sin(angle) * radius
    
    table.insert(waypoints, {
      x = math.floor(x + 0.5),
      y = math.floor(y + 0.5),
      z = centerPos.z,
      angle = angle
    })
  end
  
  return waypoints
end

-- Generate expanding/contracting spiral pattern
-- @param centerPos table - Center position
-- @param startRadius number - Starting radius
-- @param endRadius number - Ending radius
-- @param turns number - Number of full rotations
-- @param density number - Points per turn
-- @return table - Array of waypoint positions
function LuringPatterns:generateSpiral(centerPos, startRadius, endRadius, turns, density)
  local waypoints = {}
  turns = turns or 2
  density = density or 12
  startRadius = startRadius or 2
  endRadius = endRadius or 6
  
  local totalPoints = turns * density
  local angleStep = (2 * math.pi) / density
  local radiusStep = (endRadius - startRadius) / totalPoints
  
  for i = 0, totalPoints - 1 do
    local angle = i * angleStep
    local radius = startRadius + (i * radiusStep)
    
    local x = centerPos.x + math.cos(angle) * radius
    local y = centerPos.y + math.sin(angle) * radius
    
    table.insert(waypoints, {
      x = math.floor(x + 0.5),
      y = math.floor(y + 0.5),
      z = centerPos.z,
      radius = radius
    })
  end
  
  return waypoints
end

-- Generate figure-eight (infinity) pattern
-- @param centerPos table - Center position
-- @param sizeX number - Horizontal size
-- @param sizeY number - Vertical size
-- @param density number - Number of waypoints
-- @return table - Array of waypoint positions
function LuringPatterns:generateFigureEight(centerPos, sizeX, sizeY, density)
  local waypoints = {}
  density = density or 24
  sizeX = sizeX or 5
  sizeY = sizeY or 3
  
  local angleStep = (4 * math.pi) / density
  
  for i = 0, density - 1 do
    local angle = i * angleStep
    local x = centerPos.x + math.cos(angle) * sizeX
    local y = centerPos.y + (math.sin(angle) * math.cos(angle)) * sizeY * 2
    
    table.insert(waypoints, {
      x = math.floor(x + 0.5),
      y = math.floor(y + 0.5),
      z = centerPos.z
    })
  end
  
  return waypoints
end

-- Generate rectangle pattern
-- @param centerPos table - Center position
-- @param width number - Rectangle width
-- @param height number - Rectangle height
-- @return table - Array of waypoint positions
function LuringPatterns:generateRectangle(centerPos, width, height)
  local waypoints = {}
  width = width or 6
  height = height or 4
  
  local halfW = math.floor(width / 2)
  local halfH = math.floor(height / 2)
  
  -- Top edge (left to right)
  for x = -halfW, halfW do
    table.insert(waypoints, {
      x = centerPos.x + x,
      y = centerPos.y - halfH,
      z = centerPos.z
    })
  end
  
  -- Right edge (top to bottom)
  for y = -halfH + 1, halfH do
    table.insert(waypoints, {
      x = centerPos.x + halfW,
      y = centerPos.y + y,
      z = centerPos.z
    })
  end
  
  -- Bottom edge (right to left)
  for x = halfW - 1, -halfW, -1 do
    table.insert(waypoints, {
      x = centerPos.x + x,
      y = centerPos.y + halfH,
      z = centerPos.z
    })
  end
  
  -- Left edge (bottom to top)
  for y = halfH - 1, -halfH + 1, -1 do
    table.insert(waypoints, {
      x = centerPos.x - halfW,
      y = centerPos.y + y,
      z = centerPos.z
    })
  end
  
  return waypoints
end

-- Generate zigzag pattern
-- @param startPos table - Starting position
-- @param direction string - "horizontal" or "vertical"
-- @param length number - Length of zigzag
-- @param width number - Width of zigzag
-- @param segments number - Number of zigzag segments
-- @return table - Array of waypoint positions
function LuringPatterns:generateZigzag(startPos, direction, length, width, segments)
  local waypoints = {}
  direction = direction or "horizontal"
  length = length or 8
  width = width or 3
  segments = segments or 4
  
  local segmentLength = length / segments
  
  for i = 0, segments do
    local isEven = (i % 2) == 0
    
    if direction == "horizontal" then
      table.insert(waypoints, {
        x = startPos.x + (i * segmentLength),
        y = startPos.y + (isEven and 0 or width),
        z = startPos.z
      })
    else
      table.insert(waypoints, {
        x = startPos.x + (isEven and 0 or width),
        y = startPos.y + (i * segmentLength),
        z = startPos.z
      })
    end
  end
  
  return waypoints
end

-- Generate random walk pattern
-- @param startPos table - Starting position
-- @param steps number - Number of random steps
-- @param maxStep number - Maximum step distance
-- @return table - Array of waypoint positions
function LuringPatterns:generateRandomWalk(startPos, steps, maxStep)
  local waypoints = {}
  steps = steps or 10
  maxStep = maxStep or 2
  
  local current = {x = startPos.x, y = startPos.y, z = startPos.z}
  table.insert(waypoints, {x = current.x, y = current.y, z = current.z})
  
  for i = 1, steps do
    local dx = math.random(-maxStep, maxStep)
    local dy = math.random(-maxStep, maxStep)
    
    current = {
      x = current.x + dx,
      y = current.y + dy,
      z = current.z
    }
    
    table.insert(waypoints, {x = current.x, y = current.y, z = current.z})
  end
  
  return waypoints
end

-- Validate waypoints (check if they're walkable)
-- @param waypoints table - Array of waypoint positions
-- @return table - Filtered array of walkable waypoints
function LuringPatterns:validateWaypoints(waypoints)
  local valid = {}
  
  for _, wp in ipairs(waypoints) do
    local tile = g_map and g_map.getTile(wp)
    if tile and tile:isWalkable() then
      table.insert(valid, wp)
    end
  end
  
  return valid
end

-- Generate pattern by type
-- @param patternType string - Pattern type from TYPES
-- @param centerPos table - Center/start position
-- @param options table - Pattern-specific options
-- @return table - Array of waypoint positions
function LuringPatterns:generate(patternType, centerPos, options)
  options = options or {}
  
  local waypoints
  
  if patternType == self.TYPES.CIRCULAR then
    waypoints = self:generateCircular(centerPos, options.radius, options.density)
  elseif patternType == self.TYPES.SPIRAL then
    waypoints = self:generateSpiral(centerPos, options.startRadius, options.endRadius, options.turns, options.density)
  elseif patternType == self.TYPES.FIGURE_EIGHT then
    waypoints = self:generateFigureEight(centerPos, options.sizeX, options.sizeY, options.density)
  elseif patternType == self.TYPES.RECTANGLE then
    waypoints = self:generateRectangle(centerPos, options.width, options.height)
  elseif patternType == self.TYPES.ZIGZAG then
    waypoints = self:generateZigzag(centerPos, options.direction, options.length, options.width, options.segments)
  elseif patternType == self.TYPES.RANDOM_WALK then
    waypoints = self:generateRandomWalk(centerPos, options.steps, options.maxStep)
  else
    -- Default to circular
    waypoints = self:generateCircular(centerPos, options.radius or 5, options.density or 12)
  end
  
  -- Validate if requested
  if options.validate then
    waypoints = self:validateWaypoints(waypoints)
  end
  
  return waypoints
end

-- Reverse pattern (for returning)
-- @param waypoints table - Original waypoints
-- @return table - Reversed waypoints
function LuringPatterns:reverse(waypoints)
  local reversed = {}
  for i = #waypoints, 1, -1 do
    table.insert(reversed, waypoints[i])
  end
  return reversed
end

-- Get pattern iterator
-- @param waypoints table - Waypoint array
-- @param loop boolean - Whether to loop back to start
-- @return function - Iterator function
function LuringPatterns:iterator(waypoints, loop)
  local index = 0
  local direction = 1
  
  return function()
    index = index + direction
    
    if index > #waypoints then
      if loop then
        index = 1
      else
        direction = -1
        index = #waypoints - 1
      end
    elseif index < 1 then
      direction = 1
      index = 2
    end
    
    return waypoints[index]
  end
end

return LuringPatterns
