local ReplayEvaluator = {}
ReplayEvaluator.__index = ReplayEvaluator

function ReplayEvaluator.new(config)
  config = config or {}
  return setmetatable({
    decisionLog = config.decisionLog,
    modelInterface = config.modelInterface,
    lastMetrics = { accuracy = 0, improvement = 0, avgAdjustment = 0, sampleCount = 0 },
  }, ReplayEvaluator)
end

function ReplayEvaluator:replay(logs, model)
  logs = logs or (self.decisionLog and self.decisionLog:getLogs({}) or {})
  model = model or self.modelInterface
  if #logs == 0 then
    self.lastMetrics = { accuracy = 0, improvement = 0, avgAdjustment = 0, sampleCount = 0 }
    return self.lastMetrics
  end

  local correct, totalAdjustment, totalImprovement = 0, 0, 0
  for _, decision in ipairs(logs) do
    local prediction = nil
    if model and model.predict then
      prediction = model:predict(decision.features or {})
    end
    if prediction then
      local baseline = decision.baseline or {}
      local matches = prediction.actionable
      if matches then correct = correct + 1 end
      local adj = prediction.probability - (baseline.value or 0)
      totalAdjustment = totalAdjustment + adj
      if adj > 0 then totalImprovement = totalImprovement + 1 end
    end
  end

  local n = #logs
  self.lastMetrics = {
    accuracy = correct / n,
    improvement = totalImprovement / n,
    avgAdjustment = totalAdjustment / n,
    sampleCount = n,
  }
  return self.lastMetrics
end

function ReplayEvaluator:getMetrics()
  return self.lastMetrics
end

nExBot = nExBot or {}
nExBot.IntelligenceReplayEvaluator = ReplayEvaluator

return ReplayEvaluator
