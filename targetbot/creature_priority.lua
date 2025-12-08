--[[
  Optimized Priority Calculation System
  
  Uses a weighted scoring algorithm that considers:
  1. Health state (critical monsters get highest priority to prevent escapes)
  2. Distance (closer = more dangerous and easier to kill)
  3. Current target (maintain focus to finish kills)
  4. Configuration priority (user-defined importance)
  5. Group optimization (for AoE attacks)
  
  The algorithm uses pre-computed weights and early exits for performance.
]]

-- Priority weights (tunable constants)
local WEIGHT_CRITICAL_HEALTH = 60    -- HP <= 15%
local WEIGHT_LOW_HEALTH = 35         -- HP <= 25%
local WEIGHT_WOUNDED = 18            -- HP <= 35%
local WEIGHT_CURRENT_TARGET = 12     -- Currently attacking this monster
local WEIGHT_TARGET_WOUNDED = 15     -- Current target is wounded
local WEIGHT_ADJACENT = 12           -- Distance == 1
local WEIGHT_CLOSE = 8               -- Distance == 2
local WEIGHT_NEAR = 5                -- Distance <= 3
local WEIGHT_MEDIUM = 2              -- Distance <= 5
local WEIGHT_CHASE_LOW = 10          -- Chase mode + low HP

-- Pre-computed distance-to-weight lookup for O(1) access
local DISTANCE_WEIGHTS = {
  [1] = 12, [2] = 8, [3] = 5, [4] = 3, [5] = 2,
  [6] = 1, [7] = 1, [8] = 0, [9] = 0, [10] = 0
}

-- Diamond arrow pattern for paladin optimization
local diamondArrowArea = {
  {0, 1}, {1, 0}, {0, -1}, {-1, 0},
  {1, 1}, {1, -1}, {-1, 1}, {-1, -1}
}

local largeRuneArea = {
  {0, 1}, {1, 0}, {0, -1}, {-1, 0},
  {1, 1}, {1, -1}, {-1, 1}, {-1, -1},
  {0, 2}, {2, 0}, {0, -2}, {-2, 0}
}

TargetBot.Creature.calculatePriority = function(creature, config, path)
  local priority = 0
  local pathLength = #path
  local healthPercent = creature:getHealthPercent()
  
  -- Early exit for out of range targets
  local maxDistance = config.maxDistance
  if pathLength > maxDistance then
    -- Exception: nearly dead monsters get reduced but non-zero priority
    if healthPercent <= 20 and pathLength <= maxDistance + 3 then
      return config.priority * 0.3  -- Reduced priority, still targetable
    end
    
    -- Cancel attack if using rpSafe mode and target is out of range
    if config.rpSafe then
      local currentTarget = g_game.getAttackingCreature()
      if currentTarget == creature then
        g_game.cancelAttackAndFollow()
      end
    end
    return 0
  end
  
  -- Base priority from config
  priority = config.priority
  
  -- Health-based priority (CRITICAL for kill efficiency)
  -- Uses exponential scaling for low health to ensure kills
  if healthPercent <= 15 then
    priority = priority + WEIGHT_CRITICAL_HEALTH
    -- Extra bonus for single-hit killable monsters
    if healthPercent <= 5 then
      priority = priority + 20
    end
  elseif healthPercent <= 25 then
    priority = priority + WEIGHT_LOW_HEALTH
  elseif healthPercent <= 35 then
    priority = priority + WEIGHT_WOUNDED
  elseif healthPercent <= 50 then
    priority = priority + 8
  elseif healthPercent <= 70 then
    priority = priority + 3
  end
  
  -- Current target bonus (target stickiness to finish kills)
  local currentTarget = g_game.getAttackingCreature()
  if currentTarget == creature then
    priority = priority + WEIGHT_CURRENT_TARGET
    
    -- Extra priority for wounded current target
    if healthPercent < 50 then
      priority = priority + WEIGHT_TARGET_WOUNDED
    end
    if healthPercent < 25 then
      priority = priority + 10  -- Don't let it escape!
    end
  end
  
  -- Distance-based priority using lookup table
  local distWeight = DISTANCE_WEIGHTS[pathLength] or 0
  priority = priority + distWeight
  
  -- Chase mode bonus for low health monsters
  if config.chase and healthPercent < 30 then
    priority = priority + WEIGHT_CHASE_LOW
  end
  
  -- Paladin diamond arrow optimization
  if config.diamondArrows then
    local creaturePos = creature:getPosition()
    local mobCount = getCreaturesInArea(creaturePos, diamondArrowArea, 2)
    priority = priority + (mobCount * 5)
    
    -- RP safe mode check
    if config.rpSafe then
      if getCreaturesInArea(creaturePos, largeRuneArea, 3) > 0 then
        if currentTarget == creature then
          g_game.cancelAttackAndFollow()
        end
        return 0
      end
    end
  end
  
  return priority
end