IntelligenceWaveBeamState = {}
local WaveBeamState = IntelligenceWaveBeamState
WaveBeamState.__index = WaveBeamState

function WaveBeamState.new(options)
  options = options or {}
  return setmetatable({
    state = "clear",
    enterConfidence = options.enterConfidence or 0.7,
    exitConfidence = options.exitConfidence or 0.4,
    ttl = options.ttl or 150,
  }, WaveBeamState)
end

local function aggregate(evidence)
  local score, weight, sources = 0, 0, {}
  for _, item in ipairs(evidence or {}) do
    local confidence = math.max(0, math.min(1, tonumber(item.confidence) or 0))
    local itemWeight = math.max(0, tonumber(item.weight) or 0)
    score, weight = score + confidence * itemWeight, weight + itemWeight
    if item.name then sources[item.name] = confidence end
  end
  return weight > 0 and score / weight or 0, sources
end

function WaveBeamState:update(observation, context)
  observation, context = observation or {}, context or {}
  local generations = context.generations or {}
  local generation = observation.snapshotGeneration or 0
  if generation < (generations.snapshot or 0) then return nil, "stale_snapshot_generation" end
  if observation.safe == false then
    self.state = "aborted"
    return nil, "unsafe_wave_avoidance"
  end
  if observation.kind ~= "wave" and observation.kind ~= "beam" then
    return nil, "invalid_threat_kind"
  end

  local confidence, sources = aggregate(observation.evidence)
  if self.state == "avoiding" then
    if confidence <= self.exitConfidence then
      self.state = "clear"
      return nil
    end
  elseif confidence >= self.enterConfidence then
    self.state = "avoiding"
  else
    self.state = confidence > 0 and "watching" or "clear"
    return nil
  end

  local now = context.now or 0
  return {
    domain = "movement", action = "avoid_" .. observation.kind, source = "WaveBeam",
    priority = 100, safety = 2, confidence = confidence,
    createdAt = now, expiresAt = now + self.ttl,
    snapshotGeneration = generation, combatGeneration = generations.combat or 0,
    evidence = { threatId = observation.threatId, kind = observation.kind, sources = sources },
  }
end

return WaveBeamState
