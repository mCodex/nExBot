IntelligenceObservationQuality = {}
local Quality = IntelligenceObservationQuality

function Quality.weight(observation, now, maxAgeMs)
  assert(type(observation) == "table" and type(now) == "number", "invalid observation")
  maxAgeMs = maxAgeMs or 5000
  local confidence = math.max(0, math.min(1, observation.confidence or 0))
  local completeness = math.max(0, math.min(1, observation.completeness or 1))
  local age = math.max(0, now - (observation.timestamp or now))
  return confidence * completeness * math.max(0, 1 - age / maxAgeMs)
end

return Quality
