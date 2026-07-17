IntelligenceFeaturePipeline = {}
IntelligenceFeaturePipeline.__index = IntelligenceFeaturePipeline

local NAMES = {
  "playerHpRatio", "playerManaRatio", "targetHpRatio", "targetDistance",
  "nearbyMonsterCount", "meleeMonsterCount", "rangedMonsterCount", "waveMonsterCount",
  "estimatedIncomingDps", "estimatedBurst", "currentLureSize", "routeCongestion",
  "pathLength", "recentPotionUsage", "xpRate", "latencyClass", "observationQuality",
}

local function bounded(value, maximum)
  value, maximum = tonumber(value) or 0, maximum or 1
  return math.max(0, math.min(1, maximum > 0 and value / maximum or 0))
end

function IntelligenceFeaturePipeline.new(options)
  options = options or {}
  return setmetatable({
    maxDistance = options.maxDistance or 15,
    maxCreatures = options.maxCreatures or 20,
    maxDps = options.maxDps or 1000,
    maxBurst = options.maxBurst or 1000,
    maxPathLength = options.maxPathLength or 100,
    maxPotions = options.maxPotions or 20,
    maxXpRate = options.maxXpRate or 10000000,
  }, IntelligenceFeaturePipeline)
end

function IntelligenceFeaturePipeline:extractCombat(snapshot, context)
  snapshot, context = snapshot or {}, context or {}
  local player = snapshot.player or {}
  local target = (snapshot.creaturesById or {})[context.targetId] or {}
  return {
    version = 1,
    names = NAMES,
    values = {
      bounded(player.healthRatio), bounded(player.manaRatio), bounded(target.healthRatio or target.healthPercent, target.healthRatio and 1 or 100),
      bounded(target.distance, self.maxDistance), bounded(#(snapshot.visibleMonsters or snapshot.creatures or {}), self.maxCreatures),
      bounded(context.meleeCount, self.maxCreatures), bounded(context.rangedCount, self.maxCreatures), bounded(context.waveCount, self.maxCreatures),
      bounded(context.estimatedIncomingDps, self.maxDps), bounded(context.estimatedBurst, self.maxBurst),
      bounded(context.lureSize, self.maxCreatures), bounded(context.routeCongestion), bounded(context.pathLength, self.maxPathLength),
      bounded(context.recentPotionUsage, self.maxPotions), bounded(context.xpRate, self.maxXpRate),
      bounded(context.latencyClass, 3), bounded(context.observationQuality),
    },
  }
end

return IntelligenceFeaturePipeline
