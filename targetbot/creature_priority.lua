-- Optimized priority calculation with reduced function calls and early returns
TargetBot.Creature.calculatePriority = function(creature, config, path)
  local priority = 0
  local currentTarget = g_game.getAttackingCreature()
  local pathLength = #path

  -- extra priority if it's current target (most common check first)
  if currentTarget == creature then
    priority = 1
  end

  -- check if distance is ok - early return for out of range targets
  local maxDistance = config.maxDistance
  if pathLength > maxDistance then
    if config.rpSafe and currentTarget == creature then
      g_game.cancelAttackAndFollow()
    end
    return priority
  end

  -- add config priority (always done if in range)
  priority = priority + config.priority
  
  -- extra priority for close distance (common case optimization)
  if pathLength == 1 then
    priority = priority + 10
  elseif pathLength <= 3 then
    priority = priority + 5
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

  -- extra priority for low health - optimized with fewer comparisons
  local healthPercent = creature:getHealthPercent()
  if config.chase and healthPercent < 30 then
    priority = priority + 5
  elseif healthPercent < 20 then
    priority = priority + 2.5
  elseif healthPercent < 40 then
    priority = priority + 1.5
  elseif healthPercent < 60 then
    priority = priority + 0.5
  elseif healthPercent < 80 then
    priority = priority + 0.2
  end

  return priority
end