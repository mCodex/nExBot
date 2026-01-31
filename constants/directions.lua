--[[
  Direction Constants - Single Source of Truth
  
  Consolidates direction mappings, vectors, and adjacency offsets
  that were duplicated across path_utils.lua, walking.lua, creature_position.lua
  
  USAGE:
    dofile("constants/directions.lua")  -- Loads Directions globally
    local offset = Directions.DIR_TO_OFFSET[North]
    local dir = Directions.getDirectionFromOffset(1, 0)
]]

-- Declare as global (not local) so it's accessible after dofile
Directions = Directions or {}

-- ============================================================================
-- DIRECTION CONSTANTS (from OTClient)
-- These should match the global constants defined by OTClient
-- ============================================================================

-- Define locals if globals don't exist (for standalone testing)
local _North = North or 0
local _East = East or 1
local _South = South or 2
local _West = West or 3
local _NorthEast = NorthEast or 4
local _SouthEast = SouthEast or 5
local _SouthWest = SouthWest or 6
local _NorthWest = NorthWest or 7

-- ============================================================================
-- DIRECTION TO OFFSET MAPPING
-- ============================================================================

Directions.DIR_TO_OFFSET = {
  [_North]     = { x =  0, y = -1 },
  [_East]      = { x =  1, y =  0 },
  [_South]     = { x =  0, y =  1 },
  [_West]      = { x = -1, y =  0 },
  [_NorthEast] = { x =  1, y = -1 },
  [_SouthEast] = { x =  1, y =  1 },
  [_SouthWest] = { x = -1, y =  1 },
  [_NorthWest] = { x = -1, y = -1 },
}

-- ============================================================================
-- OFFSET TO DIRECTION MAPPING (String key for fast lookup)
-- ============================================================================

Directions.OFFSET_TO_DIR = {
  ["0,-1"]  = _North,
  ["1,0"]   = _East,
  ["0,1"]   = _South,
  ["-1,0"]  = _West,
  ["1,-1"]  = _NorthEast,
  ["1,1"]   = _SouthEast,
  ["-1,1"]  = _SouthWest,
  ["-1,-1"] = _NorthWest,
}

-- ============================================================================
-- DIRECTION ARRAYS
-- ============================================================================

-- Cardinal directions only (4 directions)
Directions.CARDINAL = { _North, _East, _South, _West }

-- Diagonal directions only (4 directions)
Directions.DIAGONAL = { _NorthEast, _SouthEast, _SouthWest, _NorthWest }

-- All 8 directions in clockwise order
Directions.ALL = { 
  _North, _NorthEast, _East, _SouthEast, 
  _South, _SouthWest, _West, _NorthWest 
}

-- Adjacent offsets (same as ALL but as offset tables)
Directions.ADJACENT_OFFSETS = {
  { x =  0, y = -1 },  -- North
  { x =  1, y = -1 },  -- NorthEast
  { x =  1, y =  0 },  -- East
  { x =  1, y =  1 },  -- SouthEast
  { x =  0, y =  1 },  -- South
  { x = -1, y =  1 },  -- SouthWest
  { x = -1, y =  0 },  -- West
  { x = -1, y = -1 },  -- NorthWest
}

-- ============================================================================
-- OPPOSITE DIRECTIONS
-- ============================================================================

Directions.OPPOSITE = {
  [_North]     = _South,
  [_East]      = _West,
  [_South]     = _North,
  [_West]      = _East,
  [_NorthEast] = _SouthWest,
  [_SouthEast] = _NorthWest,
  [_SouthWest] = _NorthEast,
  [_NorthWest] = _SouthEast,
}

-- ============================================================================
-- DIRECTION NAMES (for debugging)
-- ============================================================================

Directions.NAMES = {
  [_North]     = "North",
  [_East]      = "East",
  [_South]     = "South",
  [_West]      = "West",
  [_NorthEast] = "NorthEast",
  [_SouthEast] = "SouthEast",
  [_SouthWest] = "SouthWest",
  [_NorthWest] = "NorthWest",
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
  Get offset for direction
  @param dir number direction constant
  @return table {x, y} or nil
]]
function Directions.getOffset(dir)
  return Directions.DIR_TO_OFFSET[dir]
end

--[[
  Get direction from offset
  @param dx number x offset (-1, 0, 1)
  @param dy number y offset (-1, 0, 1)
  @return number direction constant or nil
]]
function Directions.getDirectionFromOffset(dx, dy)
  local key = tostring(dx) .. "," .. tostring(dy)
  return Directions.OFFSET_TO_DIR[key]
end

--[[
  Get direction from position A to position B
  @param fromPos Position
  @param toPos Position
  @return number direction constant or nil
]]
function Directions.getDirectionTo(fromPos, toPos)
  if not fromPos or not toPos then return nil end
  
  local dx = toPos.x - fromPos.x
  local dy = toPos.y - fromPos.y
  
  -- Clamp to -1, 0, 1
  if dx > 0 then dx = 1 elseif dx < 0 then dx = -1 end
  if dy > 0 then dy = 1 elseif dy < 0 then dy = -1 end
  
  return Directions.getDirectionFromOffset(dx, dy)
end

--[[
  Get opposite direction
  @param dir number direction constant
  @return number opposite direction
]]
function Directions.getOpposite(dir)
  return Directions.OPPOSITE[dir]
end

--[[
  Check if direction is cardinal (N/E/S/W)
  @param dir number direction constant
  @return boolean
]]
function Directions.isCardinal(dir)
  return dir == _North or dir == _East or dir == _South or dir == _West
end

--[[
  Check if direction is diagonal
  @param dir number direction constant
  @return boolean
]]
function Directions.isDiagonal(dir)
  return dir == _NorthEast or dir == _SouthEast or dir == _SouthWest or dir == _NorthWest
end

--[[
  Get position after moving in direction
  @param pos Position
  @param dir number direction constant
  @return Position new position
]]
function Directions.positionInDirection(pos, dir)
  if not pos or not dir then return nil end
  
  local offset = Directions.DIR_TO_OFFSET[dir]
  if not offset then return nil end
  
  return {
    x = pos.x + offset.x,
    y = pos.y + offset.y,
    z = pos.z
  }
end

--[[
  Get all adjacent positions
  @param pos Position
  @param includeDiagonals boolean (default true)
  @return array of positions
]]
function Directions.getAdjacentPositions(pos, includeDiagonals)
  if not pos then return {} end
  
  includeDiagonals = includeDiagonals ~= false  -- Default true
  
  local directions = includeDiagonals and Directions.ALL or Directions.CARDINAL
  local result = {}
  
  for _, dir in ipairs(directions) do
    local offset = Directions.DIR_TO_OFFSET[dir]
    result[#result + 1] = {
      x = pos.x + offset.x,
      y = pos.y + offset.y,
      z = pos.z
    }
  end
  
  return result
end

--[[
  Calculate Manhattan distance between two positions
  @param pos1 Position
  @param pos2 Position
  @return number
]]
function Directions.manhattanDistance(pos1, pos2)
  if not pos1 or not pos2 then return 999999 end
  return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

--[[
  Calculate Chebyshev distance (diagonal counts as 1)
  @param pos1 Position
  @param pos2 Position
  @return number
]]
function Directions.chebyshevDistance(pos1, pos2)
  if not pos1 or not pos2 then return 999999 end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

--[[
  Calculate Euclidean distance
  @param pos1 Position
  @param pos2 Position
  @return number
]]
function Directions.euclideanDistance(pos1, pos2)
  if not pos1 or not pos2 then return 999999 end
  local dx = pos1.x - pos2.x
  local dy = pos1.y - pos2.y
  return math.sqrt(dx * dx + dy * dy)
end

--[[
  Rotate direction clockwise
  @param dir number direction constant
  @param steps number how many 45-degree steps (default 1)
  @return number new direction
]]
function Directions.rotateClockwise(dir, steps)
  steps = steps or 1
  
  -- Find current index in ALL array
  local currentIdx = 0
  for i, d in ipairs(Directions.ALL) do
    if d == dir then
      currentIdx = i
      break
    end
  end
  
  if currentIdx == 0 then return dir end
  
  -- Rotate
  local newIdx = ((currentIdx - 1 + steps) % 8) + 1
  return Directions.ALL[newIdx]
end

--[[
  Rotate direction counter-clockwise
  @param dir number direction constant
  @param steps number how many 45-degree steps (default 1)
  @return number new direction
]]
function Directions.rotateCounterClockwise(dir, steps)
  return Directions.rotateClockwise(dir, -(steps or 1))
end

return Directions
