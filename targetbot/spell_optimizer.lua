--[[
  Spell Position Optimizer v1.0
  
  Optimizes player positioning for maximum spell/rune effectiveness.
  Integrates with AttackBot spell patterns to find positions that:
  - Hit the most monsters with AoE spells
  - Avoid wasting resources on empty tiles
  - Maintain safety while maximizing damage
  
  Features:
  - AoE spell area calculation
  - Optimal position scoring
  - Resource efficiency tracking
  - Cross-reference with configured spells
]]

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

SpellOptimizer = SpellOptimizer or {}
SpellOptimizer.VERSION = "1.0"

-- ============================================================================
-- CONSTANTS
-- ============================================================================

SpellOptimizer.CONSTANTS = {
  -- Spell area shapes (matches AttackBot patterns)
  SHAPE = {
    ADJACENT = 1,      -- 3x3 around player
    WAVE_SMALL = 2,    -- Small wave pattern
    WAVE_MEDIUM = 3,   -- Medium wave
    WAVE_LARGE = 4,    -- Large wave
    BEAM_SHORT = 5,    -- Short beam
    BEAM_LONG = 6,     -- Long beam
    BALL_SMALL = 7,    -- 3x3 ball (GFB, Avalanche target)
    BALL_LARGE = 8,    -- 5x5 ball
    CROSS = 9,         -- Cross pattern (explosion)
    ULT = 10           -- Ultimate explosion (mas spells)
  },
  
  -- Position scoring weights
  WEIGHTS = {
    MONSTER_HIT = 100,       -- Per monster hit by spell
    MONSTER_MISS = -20,      -- Per monster NOT hit when close
    DANGER_PENALTY = -50,    -- Per danger point
    DISTANCE_PENALTY = -5,   -- Per tile from current position
    STABILITY_BONUS = 30,    -- For staying in current position
    AOE_EFFICIENCY = 15,     -- Bonus for hitting 3+ monsters
    RESOURCE_SAVE = 40       -- Bonus for not wasting spell
  },
  
  -- Minimum requirements
  MIN_MONSTERS_FOR_AOE = 2,  -- Don't recommend AoE for single target
  MIN_CONFIDENCE = 0.5,       -- Minimum confidence to recommend move
  
  -- Position search radius
  SEARCH_RADIUS = 3
}

local CONST = SpellOptimizer.CONSTANTS
local WEIGHTS = CONST.WEIGHTS

-- ============================================================================
-- SPELL AREA DEFINITIONS
-- Pre-computed attack areas for each spell type
-- ============================================================================

SpellOptimizer.Areas = {
  -- Adjacent spells (exori, exori gran)
  [CONST.SHAPE.ADJACENT] = {
    {dx = -1, dy = -1}, {dx = 0, dy = -1}, {dx = 1, dy = -1},
    {dx = -1, dy = 0},                     {dx = 1, dy = 0},
    {dx = -1, dy = 1},  {dx = 0, dy = 1},  {dx = 1, dy = 1}
  },
  
  -- Small wave (gran frigo hur)
  [CONST.SHAPE.WAVE_SMALL] = function(direction)
    return SpellOptimizer.generateWaveArea(direction, 3, 1)
  end,
  
  -- Medium wave (flam hur, frigo hur)
  [CONST.SHAPE.WAVE_MEDIUM] = function(direction)
    return SpellOptimizer.generateWaveArea(direction, 5, 2)
  end,
  
  -- Large wave (gran flam hur)
  [CONST.SHAPE.WAVE_LARGE] = function(direction)
    return SpellOptimizer.generateWaveArea(direction, 7, 3)
  end,
  
  -- Short beam (vis lux)
  [CONST.SHAPE.BEAM_SHORT] = function(direction)
    return SpellOptimizer.generateBeamArea(direction, 5)
  end,
  
  -- Long beam (gran vis lux)
  [CONST.SHAPE.BEAM_LONG] = function(direction)
    return SpellOptimizer.generateBeamArea(direction, 7)
  end,
  
  -- Ball small (GFB, Avalanche - on target)
  [CONST.SHAPE.BALL_SMALL] = {
    {dx = -1, dy = -1}, {dx = 0, dy = -1}, {dx = 1, dy = -1},
    {dx = -1, dy = 0},  {dx = 0, dy = 0},  {dx = 1, dy = 0},
    {dx = -1, dy = 1},  {dx = 0, dy = 1},  {dx = 1, dy = 1}
  },
  
  -- Ball large (stronger AoE)
  [CONST.SHAPE.BALL_LARGE] = function()
    local area = {}
    for dx = -2, 2 do
      for dy = -2, 2 do
        table.insert(area, {dx = dx, dy = dy})
      end
    end
    return area
  end,
  
  -- Cross pattern (explosion rune)
  [CONST.SHAPE.CROSS] = {
    {dx = 0, dy = -1},
    {dx = -1, dy = 0}, {dx = 0, dy = 0}, {dx = 1, dy = 0},
    {dx = 0, dy = 1}
  },
  
  -- Ultimate explosion (mas vis, etc)
  [CONST.SHAPE.ULT] = function()
    local area = {}
    for dx = -3, 3 do
      for dy = -3, 3 do
        -- Diamond shape
        if math.abs(dx) + math.abs(dy) <= 4 then
          table.insert(area, {dx = dx, dy = dy})
        end
      end
    end
    return area
  end
}

-- Generate wave attack area based on direction
function SpellOptimizer.generateWaveArea(direction, length, width)
  local area = {}
  local dirVec = {
    [0] = {x = 0, y = -1},   -- North
    [1] = {x = 1, y = 0},    -- East
    [2] = {x = 0, y = 1},    -- South
    [3] = {x = -1, y = 0}    -- West
  }
  
  local vec = dirVec[direction] or dirVec[0]
  
  for dist = 1, length do
    for w = -width, width do
      local dx, dy
      if vec.x == 0 then
        -- North/South wave
        dx = w
        dy = dist * vec.y
      else
        -- East/West wave
        dx = dist * vec.x
        dy = w
      end
      table.insert(area, {dx = dx, dy = dy})
    end
  end
  
  return area
end

-- Generate beam attack area based on direction
function SpellOptimizer.generateBeamArea(direction, length)
  local area = {}
  local dirVec = {
    [0] = {x = 0, y = -1},
    [1] = {x = 1, y = 0},
    [2] = {x = 0, y = 1},
    [3] = {x = -1, y = 0}
  }
  
  local vec = dirVec[direction] or dirVec[0]
  
  for dist = 1, length do
    table.insert(area, {dx = dist * vec.x, dy = dist * vec.y})
  end
  
  return area
end

-- ============================================================================
-- POSITION SCORING
-- ============================================================================

-- Count monsters hit by a spell cast from a position
-- @param castPos: position spell is cast from (or target for runes)
-- @param shape: spell shape constant
-- @param direction: player direction (for directional spells)
-- @param monsters: array of monsters
-- @return hitCount, missedCount (missed = nearby but not hit)
function SpellOptimizer.countMonstersHit(castPos, shape, direction, monsters)
  local area = SpellOptimizer.Areas[shape]
  
  -- Handle function-based areas
  if type(area) == "function" then
    area = area(direction)
  end
  
  if not area then return 0, 0 end
  
  -- Build set of hit positions
  local hitPositions = {}
  for i = 1, #area do
    local offset = area[i]
    local key = (castPos.x + offset.dx) .. "," .. (castPos.y + offset.dy)
    hitPositions[key] = true
  end
  
  local hitCount = 0
  local missedCount = 0
  
  for i = 1, #monsters do
    local monster = monsters[i]
    if monster and not monster:isDead() then
      local mpos = monster:getPosition()
      local key = mpos.x .. "," .. mpos.y
      
      if hitPositions[key] then
        hitCount = hitCount + 1
      else
        -- Check if monster is close but missed
        local dist = math.max(
          math.abs(mpos.x - castPos.x),
          math.abs(mpos.y - castPos.y)
        )
        if dist <= 4 then  -- Within reasonable AoE range
          missedCount = missedCount + 1
        end
      end
    end
  end
  
  return hitCount, missedCount
end

-- Score a position for spell casting
-- @param position: position to evaluate
-- @param playerPos: current player position
-- @param shape: spell shape constant
-- @param direction: player direction
-- @param monsters: array of monsters
-- @param dangerAnalysis: result from MonsterAI danger analysis (optional)
-- @return score, details
function SpellOptimizer.scorePosition(position, playerPos, shape, direction, monsters, dangerAnalysis)
  local score = 0
  local details = {
    monstersHit = 0,
    monstersMissed = 0,
    danger = 0,
    distance = 0,
    efficiency = 0
  }
  
  -- Count monsters hit
  local hitCount, missedCount = SpellOptimizer.countMonstersHit(
    position, shape, direction, monsters
  )
  details.monstersHit = hitCount
  details.monstersMissed = missedCount
  
  -- Monster hit scoring
  score = score + hitCount * WEIGHTS.MONSTER_HIT
  score = score + missedCount * WEIGHTS.MONSTER_MISS
  
  -- AoE efficiency bonus
  if hitCount >= 3 then
    score = score + WEIGHTS.AOE_EFFICIENCY * (hitCount - 2)
  end
  
  -- Resource efficiency (don't cast if hitting 0-1 monsters)
  if hitCount >= CONST.MIN_MONSTERS_FOR_AOE then
    score = score + WEIGHTS.RESOURCE_SAVE
    details.efficiency = hitCount / math.max(1, hitCount + missedCount)
  elseif hitCount == 0 then
    score = score - WEIGHTS.RESOURCE_SAVE * 2  -- Heavy penalty for waste
  end
  
  -- Distance penalty
  local distance = math.max(
    math.abs(position.x - playerPos.x),
    math.abs(position.y - playerPos.y)
  )
  details.distance = distance
  score = score + distance * WEIGHTS.DISTANCE_PENALTY
  
  -- Stability bonus (prefer current position)
  if distance == 0 then
    score = score + WEIGHTS.STABILITY_BONUS
  end
  
  -- Danger penalty (from MonsterAI)
  if dangerAnalysis then
    local danger = dangerAnalysis.totalDanger or 0
    details.danger = danger
    score = score + danger * WEIGHTS.DANGER_PENALTY
  end
  
  return score, details
end

-- ============================================================================
-- OPTIMAL POSITION FINDER
-- ============================================================================

-- Find optimal position for casting a specific spell
-- @param spellShape: spell shape constant
-- @param monsters: array of monsters on screen
-- @param options: { minMonsters, maxDistance, avoidDanger }
-- @return bestPos, score, confidence, details
function SpellOptimizer.findOptimalPosition(spellShape, monsters, options)
  options = options or {}
  local minMonsters = options.minMonsters or CONST.MIN_MONSTERS_FOR_AOE
  local maxDistance = options.maxDistance or CONST.SEARCH_RADIUS
  local avoidDanger = options.avoidDanger ~= false
  
  local playerPos = player:getPosition()
  local playerDir = player:getDirection()
  
  if not playerPos or not monsters or #monsters == 0 then
    return nil, 0, 0, nil
  end
  
  local bestPos = nil
  local bestScore = -99999
  local bestDetails = nil
  
  -- Search positions around player
  for dx = -maxDistance, maxDistance do
    for dy = -maxDistance, maxDistance do
      local checkPos = {
        x = playerPos.x + dx,
        y = playerPos.y + dy,
        z = playerPos.z
      }
      
      -- Verify position is walkable (or is current position)
      local isCurrentPos = dx == 0 and dy == 0
      local isValid = isCurrentPos
      
      if not isCurrentPos then
        local tile = g_map.getTile(checkPos)
        isValid = tile and tile:isWalkable() and not tile:hasCreature()
      end
      
      if isValid then
        -- Get danger analysis if MonsterAI available
        local dangerAnalysis = nil
        if avoidDanger and MonsterAI and MonsterAI.Predictor then
          local danger, confidence = MonsterAI.Predictor.predictPositionDanger(
            checkPos, monsters
          )
          dangerAnalysis = { totalDanger = danger }
        end
        
        -- Score this position
        local score, details = SpellOptimizer.scorePosition(
          checkPos, playerPos, spellShape, playerDir, monsters, dangerAnalysis
        )
        
        -- Only consider if meets minimum monster requirement
        if details.monstersHit >= minMonsters and score > bestScore then
          bestScore = score
          bestPos = checkPos
          bestDetails = details
        end
      end
    end
  end
  
  -- Calculate confidence
  local confidence = 0
  if bestPos and bestDetails then
    -- Higher confidence with more data
    confidence = 0.5  -- Base
    if bestDetails.monstersHit >= 3 then confidence = confidence + 0.2 end
    if bestDetails.distance == 0 then confidence = confidence + 0.15 end
    if bestDetails.efficiency > 0.7 then confidence = confidence + 0.1 end
    if bestDetails.danger == 0 then confidence = confidence + 0.1 end
    confidence = math.min(confidence, 0.95)
  end
  
  return bestPos, bestScore, confidence, bestDetails
end

-- ============================================================================
-- SPELL RECOMMENDATION
-- Integrates with AttackBot to recommend best spell for situation
-- ============================================================================

SpellOptimizer.Recommendations = {}

-- Analyze current situation and recommend spell + position
-- @param configuredSpells: array of { shape, name, minTargets, cooldown }
-- @param monsters: array of monsters
-- @return { spellName, position, monstersHit, confidence }
function SpellOptimizer.Recommendations.analyze(configuredSpells, monsters)
  if not configuredSpells or #configuredSpells == 0 then
    return nil
  end
  
  local playerPos = player:getPosition()
  if not playerPos or not monsters or #monsters == 0 then
    return nil
  end
  
  local bestRecommendation = nil
  local bestScore = -99999
  
  for i = 1, #configuredSpells do
    local spell = configuredSpells[i]
    
    -- Find optimal position for this spell
    local optPos, score, confidence, details = SpellOptimizer.findOptimalPosition(
      spell.shape, monsters, { minMonsters = spell.minTargets or 2 }
    )
    
    if optPos and score > bestScore then
      bestScore = score
      bestRecommendation = {
        spellName = spell.name,
        position = optPos,
        monstersHit = details.monstersHit,
        efficiency = details.efficiency,
        confidence = confidence,
        needsMovement = details.distance > 0
      }
    end
  end
  
  return bestRecommendation
end

-- Check if current position is optimal for configured spells
-- @return isOptimal, bestAlternative
function SpellOptimizer.Recommendations.isPositionOptimal(configuredSpells, monsters)
  local playerPos = player:getPosition()
  if not playerPos then return true, nil end
  
  local recommendation = SpellOptimizer.Recommendations.analyze(configuredSpells, monsters)
  
  if not recommendation then
    return true, nil  -- No recommendation means current is fine
  end
  
  if not recommendation.needsMovement then
    return true, nil  -- Already at optimal
  end
  
  -- Only recommend move if confidence is high enough
  if recommendation.confidence >= CONST.MIN_CONFIDENCE then
    return false, recommendation
  end
  
  return true, nil
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

nExBot = nExBot or {}
nExBot.SpellOptimizer = SpellOptimizer

print("[SpellOptimizer] Spell Position Optimizer v" .. SpellOptimizer.VERSION .. " loaded")
