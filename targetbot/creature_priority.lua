--[[
  Optimized Priority Calculation System v1.0
  
  Integrates with TargetCore for pure function calculations.
  
  Features:
  1. Health-based priority with exponential scaling (finish kills!)
  2. Target stickiness (maintain focus on wounded targets)
  3. Distance optimization (closer = easier to kill)
  4. AOE optimization (for group attacks)
  5. RP Safe mode (avoid pulling extra monsters)
  
  The algorithm uses the centralized TargetCore.calculatePriority()
  with local configuration handling.
]]

-- Use TargetCore constants if available, otherwise define locally
local PRIO = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.PRIORITY) or {
  CRITICAL_HEALTH = 80,
  VERY_LOW_HEALTH = 55,
  LOW_HEALTH = 35,
  WOUNDED = 18,
  CURRENT_TARGET = 15,
  CURRENT_WOUNDED = 25,
  ADJACENT = 14,
  CLOSE = 10,
  NEAR = 6,
  MEDIUM = 3,
  CHASE_BONUS = 12,
  AOE_BONUS = 8,
}

local DIST_W = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.DISTANCE_WEIGHTS) or {
  [1] = 14, [2] = 10, [3] = 6, [4] = 3, [5] = 3,
  [6] = 1, [7] = 1, [8] = 0, [9] = 0, [10] = 0
}

-- Diamond arrow pattern for paladin optimization
local DIAMOND_ARROW_AREA = {
  {0, 1}, {1, 0}, {0, -1}, {-1, 0},
  {1, 1}, {1, -1}, {-1, 1}, {-1, -1}
}

local LARGE_RUNE_AREA = {
  {0, 1}, {1, 0}, {0, -1}, {-1, 0},
  {1, 1}, {1, -1}, {-1, 1}, {-1, -1},
  {0, 2}, {2, 0}, {0, -2}, {-2, 0}
}

-- Pure function: Get monsters in area around position
local function getMonstersInArea(pos, offsets, maxDist)
  local count = 0

  -- Prefer MonsterCache for performance and accuracy
  if MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby then
    local radius = maxDist or 8
    local nearby = MovementCoordinator.MonsterCache.getNearby(radius)
    if nearby then
      local areaSet = {}
      for i = 1, #offsets do
        local offset = offsets[i]
        local key = (pos.x + offset[1])..","..(pos.y + offset[2])
        areaSet[key] = true
      end
      for i = 1, #nearby do
        local c = nearby[i]
        if c and c:isMonster() and not c:isDead() then
          local p = c:getPosition()
          if p and areaSet[p.x..","..p.y] then
            count = count + 1
          end
        end
      end
      return count
    end
  end

  -- Fallback to map scan
  for i = 1, #offsets do
    local offset = offsets[i]
    local checkPos = {
      x = pos.x + offset[1],
      y = pos.y + offset[2],
      z = pos.z
    }

    local tile = g_map.getTile(checkPos)
    if tile then
      local creatures = tile:getCreatures()
      if creatures then
        for j = 1, #creatures do
          local c = creatures[j]
          if c:isMonster() and not c:isDead() then
            count = count + 1
          end
        end
      end
    end
  end

  return count
end

-- Main priority calculation function
TargetBot.Creature.calculatePriority = function(creature, config, path)
  local pathLength = path and #path or 99
  local hp = creature:getHealthPercent()
  local maxDist = config.maxDistance or 10
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- EARLY EXIT: Out of range
  -- ═══════════════════════════════════════════════════════════════════════════
  if pathLength > maxDist then
    -- Exception: nearly dead monsters still targetable (don't let them escape!)
    if hp <= 15 and pathLength <= maxDist + 2 then
      return config.priority * 0.4
    end
    
    -- RP Safe: Cancel attack on out-of-range target
    if config.rpSafe then
      local currentTarget = g_game.getAttackingCreature()
      if currentTarget == creature then
        g_game.cancelAttackAndFollow()
      end
    end
    return 0
  end
  
  local priority = config.priority or 1
  local currentTarget = g_game.getAttackingCreature()
  local isCurrentTarget = (currentTarget == creature)
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- HEALTH-BASED PRIORITY (Most critical - finish kills!)
  -- Exponential scaling for low health ensures we don't switch targets
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if hp <= 5 then
    -- One-hit kill - MAXIMUM priority
    priority = priority + PRIO.CRITICAL_HEALTH + 35
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
  -- CURRENT TARGET BONUS (Target stickiness)
  -- Prevents constant target switching, ensures kills complete
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if isCurrentTarget then
    priority = priority + PRIO.CURRENT_TARGET
    
    -- Progressive bonus for wounded targets
    if hp < 50 then
      priority = priority + PRIO.CURRENT_WOUNDED
    end
    if hp < 25 then
      priority = priority + 20  -- Don't switch when target almost dead!
    end
    if hp < 10 then
      priority = priority + 15  -- FINISH THIS KILL
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- DISTANCE-BASED PRIORITY (O(1) lookup)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  local distWeight = DIST_W[pathLength] or 0
  priority = priority + distWeight
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- CHASE MODE BONUS (Low health targets when chasing)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if config.chase and hp < 35 then
    priority = priority + PRIO.CHASE_BONUS
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- AOE OPTIMIZATION (Diamond arrows, spell areas)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if config.diamondArrows then
    local creaturePos = creature:getPosition()
    local aoeMonsters = getMonstersInArea(creaturePos, DIAMOND_ARROW_AREA, 2)
    priority = priority + aoeMonsters * PRIO.AOE_BONUS
    
    -- RP Safe mode: Check for dangerous pulls
    if config.rpSafe then
      local largeAreaMonsters = getMonstersInArea(creaturePos, LARGE_RUNE_AREA, 3)
      if largeAreaMonsters > 0 and not isCurrentTarget then
        -- Could pull extra monsters - reduce priority significantly
        priority = priority - largeAreaMonsters * 10
        
        -- If currently attacking this and would pull, cancel
        if isCurrentTarget and largeAreaMonsters >= 2 then
          g_game.cancelAttackAndFollow()
          return 0
        end
      end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- DANGER BONUS (Higher danger = need to kill faster)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if config.danger and config.danger > 0 then
    priority = priority + config.danger * 0.5
  end
  
  return priority
end