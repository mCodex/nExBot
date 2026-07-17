IntelligenceRewardModel = {}
local RewardModel = IntelligenceRewardModel
RewardModel.__index = RewardModel

local function bounded(value)
  return math.max(0, math.min(1, tonumber(value) or 0))
end

function RewardModel.new(weights)
  weights = weights or {}
  return setmetatable({
    xpWeight = weights.xpWeight or 0.4,
    resourceWeight = weights.resourceWeight or 0.3,
    safetyWeight = weights.safetyWeight or 0.25,
    routeReliabilityWeight = weights.routeReliabilityWeight or 0.05,
  }, RewardModel)
end

function RewardModel:calculate(outcome)
  outcome = outcome or {}
  return self.xpWeight * bounded(outcome.xp)
    - self.resourceWeight * bounded(outcome.resourceCost)
    + self.safetyWeight * bounded(outcome.safety)
    + self.routeReliabilityWeight * bounded(outcome.routeReliability)
end

return RewardModel
