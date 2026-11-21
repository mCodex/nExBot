ContextualFeatures = {}
ContextualFeatures.__index = ContextualFeatures

function ContextualFeatures.new()
  return setmetatable({}, ContextualFeatures)
end

function ContextualFeatures:extractCombat(context)
  context = context or {}
  local reach = context.reachabilityState or 0
  local reachConfidence = type(reach) == "number" and math.min(1, math.max(0, reach)) or 0
  local pathCost = math.min(1, math.max(0, (context.pathCost or 0) / 20))
  local monsterCount = math.min(1, math.max(0, (context.monsterCount or 0) / 10))
  local distance = math.min(1, math.max(0, (context.distance or 0) / 10))
  local targetHp = math.min(1, math.max(0, context.targetHp or 0))
  local playerHpPercent = math.min(1, math.max(0, context.playerHpPercent or 0))
  local recentSwitches = math.min(5, math.max(0, context.recentSwitches or 0))

  local features = {
    targetHp = targetHp,
    distance = distance,
    hasLOS = context.hasLOS and 1 or 0,
    isCurrentTarget = context.isCurrentTarget and 1 or 0,
    reachabilityConfidence = reachConfidence,
    pathCost = pathCost,
    monsterCount = monsterCount,
    playerHpPercent = playerHpPercent,
    recentSwitchCount = recentSwitches,
    hasCommitment = context.hasCommitment and 1 or 0,
    activeFeatureId = context.activeFeature or 0,
  }

  local parts = {}
  for key, value in pairs(features) do
    parts[#parts + 1] = key .. "=" .. tostring(value)
  end
  table.sort(parts)
  features.hash = table.concat(parts, "|")

  return features
end

return ContextualFeatures
