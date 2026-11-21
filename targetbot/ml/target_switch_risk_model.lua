TargetSwitchRiskModel = {}
TargetSwitchRiskModel.__index = TargetSwitchRiskModel

local MAX_WEIGHT = 10

function TargetSwitchRiskModel.new(options)
  options = options or {}
  return setmetatable({
    _weights = {},
    _sampleCount = 0,
    _learningRate = options.learningRate or 0.01,
    _regularization = options.regularization or 0.1,
    _minSamples = options.minSamples or 20,
    _mode = "SHADOW",
  }, TargetSwitchRiskModel)
end

function TargetSwitchRiskModel:predict(features)
  if features.hasCommitment == 1 then
    return { probability = 1.0, confidence = 1, sampleCount = self._sampleCount, mode = self._mode }
  end
  if self._sampleCount < self._minSamples then
    return { probability = 0.5, confidence = 0, sampleCount = self._sampleCount, mode = self._mode }
  end
  local z = 0
  for key, value in pairs(features) do
    if type(value) == "number" then
      z = z + (self._weights[key] or 0) * value
    end
  end
  z = math.max(-500, math.min(500, z))
  local prob = 1 / (1 + math.exp(-z))
  local conf = math.min(1, self._sampleCount / 100)
  return { probability = prob, confidence = conf, sampleCount = self._sampleCount, mode = self._mode }
end

function TargetSwitchRiskModel:observe(switchedAway, targetStillAlive, features)
  self._sampleCount = self._sampleCount + 1
  local pred = self:predict(features).probability
  local target = (switchedAway and targetStillAlive) and 1 or 0
  local err = pred - target
  for key, value in pairs(features) do
    if type(value) == "number" then
      local w = self._weights[key] or 0
      w = w - self._learningRate * (err * value + self._regularization * w)
      w = math.max(-MAX_WEIGHT, math.min(MAX_WEIGHT, w))
      self._weights[key] = w
    end
  end
end

function TargetSwitchRiskModel:getSampleCount()
  return self._sampleCount
end

function TargetSwitchRiskModel:reset()
  self._weights = {}
  self._sampleCount = 0
end

return TargetSwitchRiskModel
