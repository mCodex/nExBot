IntelligenceLatencyClassifier = {}
local LatencyClassifier = IntelligenceLatencyClassifier
LatencyClassifier.__index = LatencyClassifier

function LatencyClassifier.new(options)
  options = options or {}
  local good, poor = options.goodMs or 100, options.poorMs or 250
  assert(good > 0 and poor > good, "invalid latency thresholds")
  return setmetatable({ goodMs = good, poorMs = poor, baseline = nil, alpha = options.alpha or 0.2 }, LatencyClassifier)
end

function LatencyClassifier:observe(milliseconds)
  assert(type(milliseconds) == "number" and milliseconds >= 0, "invalid latency")
  self.baseline = self.baseline and self.baseline + self.alpha * (milliseconds - self.baseline) or milliseconds
  if milliseconds <= self.goodMs then return "good" end
  if milliseconds <= self.poorMs then return "degraded" end
  return "poor"
end

function LatencyClassifier:threshold(baseMs, factor, maximumMs)
  factor, maximumMs = factor or 1, maximumMs or baseMs * 3
  return math.min(maximumMs, math.max(baseMs, baseMs + math.max(0, (self.baseline or 0) - self.goodMs) * factor))
end

return LatencyClassifier
