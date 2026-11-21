IntelligencePullState = {}
local PullState = IntelligencePullState
PullState.__index = PullState

function PullState.new(options)
  options = options or {}
  return setmetatable({
    state = "idle",
    enterDistance = options.enterDistance or 5,
    exitDistance = options.exitDistance or 2,
    ttl = options.ttl or 250,
  }, PullState)
end

function PullState:update(observation, context)
  observation, context = observation or {}, context or {}
  local generations = context.generations or {}
  local generation = observation.snapshotGeneration or 0
  if generation < (generations.snapshot or 0) then return nil, "stale_snapshot_generation" end
  if observation.safe == false then
    self.state = "aborted"
    return nil, "unsafe_pull"
  end
  if not observation.participantId or type(observation.distance) ~= "number" then
    return nil, "invalid_pull_observation"
  end
  if observation.distance <= self.exitDistance then
    self.state = "completed"
    return nil
  end
  if self.state ~= "pulling" then
    if observation.distance < self.enterDistance then return nil end
    self.state = "pulling"
  end

  local now = context.now or 0
  return {
    domain = "movement", action = "pull", source = "Pull",
    priority = 65, safety = 1,
    confidence = math.min(1, observation.distance / self.enterDistance),
    createdAt = now, expiresAt = now + self.ttl,
    snapshotGeneration = generation, routeGeneration = generations.route or 0,
    evidence = { participantId = observation.participantId, distance = observation.distance },
  }
end

return PullState
