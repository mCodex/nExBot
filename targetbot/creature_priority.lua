--[[
  Creature Priority — Minimal Facade v4.0

  All scoring logic lives in PriorityEngine (targetbot/priority_engine.lua).
  This file only provides the TargetBot.Creature.calculatePriority entry point
  expected by creature.lua and any external callers.

  AoE helpers (findBestAoEPosition, countAoEHits, getCreaturesInBeam) have been
  moved to OpenTibiaBRTargeting (targetbot/opentibiabr_targeting.lua) which is
  the canonical implementation.  Thin wrappers are kept here for backward compat.
]]

local DIST_W = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.DISTANCE_WEIGHTS) or {
  [1] = 14, [2] = 10, [3] = 6, [4] = 3, [5] = 3,
  [6] = 1,  [7] = 1,  [8] = 0, [9] = 0, [10] = 0
}

-- ═══════════════════════════════════════════════════════════════════════════
-- MAIN PRIORITY CALCULATION
-- ═══════════════════════════════════════════════════════════════════════════

TargetBot.Creature.calculatePriority = function(creature, config, path)
  -- Route through unified PriorityEngine
  if PriorityEngine and PriorityEngine.calculate then
    return PriorityEngine.calculate(creature, config, path)
  end

  -- Emergency fallback: basic config x 1000 + distance + hp
  local pathLength = path and #path or 99
  local maxDist = config.maxDistance or 10
  if pathLength > maxDist then return 0 end
  local hp = creature:getHealthPercent()
  local priority = (config.priority or 1) * 1000
  priority = priority + (DIST_W[pathLength] or 0)
  if hp <= 10 then priority = priority + 100
  elseif hp <= 30 then priority = priority + 45
  elseif hp <= 50 then priority = priority + 25 end
  return priority
end

-- ═══════════════════════════════════════════════════════════════════════════
-- AOE HELPERS — Thin wrappers delegating to OpenTibiaBRTargeting
-- ═══════════════════════════════════════════════════════════════════════════

local function getOTBR()
  if TargetBot.OpenTibiaBR then return TargetBot.OpenTibiaBR end
  return nil
end

TargetBot.Creature.findBestAoEPosition = function(range, patternType)
  local otbr = getOTBR()
  if otbr and otbr.findBestAoEPosition then
    local playerPos = player:getPosition()
    if not playerPos then return nil, 0 end
    local width  = (patternType == "diamond" or patternType == "small") and 3 or 5
    local height = width
    return otbr.findBestAoEPosition(playerPos, range, nil, width, height)
  end
  return nil, 0
end

TargetBot.Creature.countAoEHits = function(pos, patternType)
  if not pos then return 0 end
  local otbr = getOTBR()
  if otbr then
    if patternType == "diamond" or patternType == "small" then
      return otbr.countDiamondArrowHits and otbr.countDiamondArrowHits(pos) or 0
    end
    return otbr.countLargeAreaHits and otbr.countLargeAreaHits(pos) or 0
  end
  return 0
end

TargetBot.Creature.getCreaturesInBeam = function(direction, range)
  local otbr = getOTBR()
  if otbr and otbr.getCreaturesInFront then
    local playerPos = player:getPosition()
    if not playerPos then return {} end
    return otbr.getCreaturesInFront(playerPos, direction, range or 5)
  end
  return {}
end
