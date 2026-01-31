--[[
  Attack Pattern Constants - Single Source of Truth
  
  Consolidates attack pattern IDs and area definitions that were duplicated
  across AttackBot.lua, targetbot files, and core modules.
  
  USAGE:
    dofile("constants/attack_patterns.lua")  -- Loads AttackPatterns globally
    local pattern = AttackPatterns.PATTERNS.WAVE_FRONT
    local area = AttackPatterns.getPatternArea(pattern)
]]

-- Declare as global (not local) so it's accessible after dofile
AttackPatterns = AttackPatterns or {}

-- ============================================================================
-- PATTERN IDs (matching OTClient conventions)
-- ============================================================================

AttackPatterns.PATTERNS = {
  -- Basic patterns
  SELF = 0,              -- Self only
  TARGET = 1,            -- Single target
  
  -- Area patterns
  WAVE_FRONT = 2,        -- Front wave (GFB style)
  WAVE_SIDE = 3,         -- Side wave
  BEAM_FRONT = 4,        -- Straight beam
  
  -- Multi-target
  GREAT_FIREBALL = 5,    -- 3x3 area
  ULTIMATE_EXPLOSION = 6, -- 3x3 area centered on target
  AVALANCHE = 7,         -- Thrown 3x3
  
  -- Beam patterns
  BEAM_3 = 8,            -- 3 tile beam
  BEAM_5 = 9,            -- 5 tile beam
  BEAM_7 = 10,           -- 7 tile beam
  BEAM_8 = 11,           -- 8 tile beam
  
  -- Circle patterns
  MAS_AREA = 12,         -- Large circle (mas spells)
  EXORI_AREA = 13,       -- Melee area
}

-- ============================================================================
-- PATTERN NAMES (for debugging)
-- ============================================================================

AttackPatterns.NAMES = {
  [0] = "Self",
  [1] = "Target",
  [2] = "Wave Front",
  [3] = "Wave Side",
  [4] = "Beam Front",
  [5] = "Great Fireball",
  [6] = "Ultimate Explosion",
  [7] = "Avalanche",
  [8] = "Beam 3",
  [9] = "Beam 5",
  [10] = "Beam 7",
  [11] = "Beam 8",
  [12] = "Mas Area",
  [13] = "Exori Area",
}

-- ============================================================================
-- PATTERN AREAS (offset arrays for each pattern)
-- ============================================================================

-- Standard 3x3 area centered on target
local AREA_3x3 = {
  {x = -1, y = -1}, {x = 0, y = -1}, {x = 1, y = -1},
  {x = -1, y = 0},  {x = 0, y = 0},  {x = 1, y = 0},
  {x = -1, y = 1},  {x = 0, y = 1},  {x = 1, y = 1},
}

-- 5x5 area for larger spells
local AREA_5x5 = {}
for dx = -2, 2 do
  for dy = -2, 2 do
    AREA_5x5[#AREA_5x5 + 1] = {x = dx, y = dy}
  end
end

-- Front wave pattern (cone shape)
local WAVE_FRONT = {
  {x = 0, y = -1},
  {x = -1, y = -2}, {x = 0, y = -2}, {x = 1, y = -2},
  {x = -2, y = -3}, {x = -1, y = -3}, {x = 0, y = -3}, {x = 1, y = -3}, {x = 2, y = -3},
  {x = -2, y = -4}, {x = -1, y = -4}, {x = 0, y = -4}, {x = 1, y = -4}, {x = 2, y = -4},
}

-- Melee area (adjacent tiles)
local EXORI_AREA = {
  {x = 0, y = -1},   -- North
  {x = 1, y = 0},    -- East
  {x = 0, y = 1},    -- South
  {x = -1, y = 0},   -- West
  {x = 1, y = -1},   -- NE
  {x = 1, y = 1},    -- SE
  {x = -1, y = 1},   -- SW
  {x = -1, y = -1},  -- NW
}

AttackPatterns.AREAS = {
  [0] = {{x = 0, y = 0}},  -- Self
  [1] = {{x = 0, y = 0}},  -- Target
  [2] = WAVE_FRONT,
  [5] = AREA_3x3,
  [6] = AREA_3x3,
  [7] = AREA_3x3,
  [12] = AREA_5x5,
  [13] = EXORI_AREA,
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get area offsets for a pattern
-- @param patternId: number
-- @return table of {x, y} offsets
function AttackPatterns.getPatternArea(patternId)
  return AttackPatterns.AREAS[patternId] or {{x = 0, y = 0}}
end

-- Get pattern name
-- @param patternId: number
-- @return string
function AttackPatterns.getPatternName(patternId)
  return AttackPatterns.NAMES[patternId] or "Unknown"
end

-- Check if pattern is area-based (hits multiple tiles)
-- @param patternId: number
-- @return boolean
function AttackPatterns.isAreaPattern(patternId)
  return patternId >= 2
end

-- Check if pattern requires target creature
-- @param patternId: number
-- @return boolean
function AttackPatterns.requiresTarget(patternId)
  return patternId ~= 0
end

-- ============================================================================
-- EXPORT
-- ============================================================================
  
-- Export to global (no _G in OTClient sandbox)
-- AttackPatterns is already global (declared without 'local')

return AttackPatterns
