-- Optimized priority calculation with reduced function calls and early returns
-- Enhanced with stronger low-health monster prioritization to prevent escapes
TargetBot.Creature.calculatePriority = function(creature, config, path)
  local priority = 0
  local currentTarget = g_game.getAttackingCreature()
  local pathLength = #path
  local healthPercent = creature:getHealthPercent()

  -- CRITICAL: Very high priority for nearly dead monsters to prevent escape
  -- This is checked first as it's the most important factor
  if healthPercent <= 15 then
    priority = priority + 50  -- Massive priority boost for nearly dead monsters
  elseif healthPercent <= 25 then
    priority = priority + 30  -- Very high priority for low health
  elseif healthPercent <= 35 then
    priority = priority + 15  -- High priority for wounded monsters
  end

  -- Extra priority if it's current target (keep attacking same target)
  if currentTarget == creature then
    priority = priority + 8  -- Increased from 1 for better target stickiness
    -- Even more priority if current target is wounded (don't let it escape!)
    if healthPercent < 50 then
      priority = priority + 10
    end
  end

  -- check if distance is ok - early return for out of range targets
  local maxDistance = config.maxDistance
  if pathLength > maxDistance then
    if config.rpSafe and currentTarget == creature then
      g_game.cancelAttackAndFollow()
    end
    -- Exception: if monster is nearly dead, still consider it even if far
    if healthPercent <= 20 and pathLength <= maxDistance + 3 then
      return priority * 0.5  -- Reduced but still possible to target
    end
    return 0
  end

  -- add config priority (always done if in range)
  priority = priority + config.priority
  
  -- extra priority for close distance (common case optimization)
  if pathLength == 1 then
    priority = priority + 10
  elseif pathLength == 2 then
    priority = priority + 7
  elseif pathLength <= 3 then
    priority = priority + 5
  elseif pathLength <= 5 then
    priority = priority + 2
  end

  -- extra priority for paladin diamond arrows
  if config.diamondArrows then
    local creaturePos = creature:getPosition()
    local mobCount = getCreaturesInArea(creaturePos, diamondArrowArea, 2)
    priority = priority + (mobCount * 4)

    if config.rpSafe then
      if getCreaturesInArea(creaturePos, largeRuneArea, 3) > 0 then
        if currentTarget == creature then
          g_game.cancelAttackAndFollow()
        end
        return 0
      end
    end
  end

  -- Additional low health priority scaling (stacks with initial check)
  -- This creates a smooth priority curve for damaged monsters
  if config.chase and healthPercent < 30 then
    priority = priority + 8
  elseif healthPercent < 20 then
    priority = priority + 5
  elseif healthPercent < 40 then
    priority = priority + 3
  elseif healthPercent < 60 then
    priority = priority + 1
  elseif healthPercent < 80 then
    priority = priority + 0.5
  end

  return priority
end