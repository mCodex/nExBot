IntelligenceDynamicLureState = {}
local DynamicLureState = IntelligenceDynamicLureState
DynamicLureState.__index = DynamicLureState

function DynamicLureState.new(options)
  options = options or {}
  return setmetatable({
    state = "idle",
    minCount = options.minCount or options.enterCount or 3,
    maxCount = options.maxCount or 6,
    ttl = options.ttl or 250,
  }, DynamicLureState)
end

function DynamicLureState:update(observation, context)
  observation, context = observation or {}, context or {}
  local generations = context.generations or {}
  local generation = observation.snapshotGeneration or 0
  if generation < (generations.snapshot or 0) then return nil, "stale_snapshot_generation" end
  if observation.safe == false then
    self.state = "aborted"
    return nil, "unsafe_lure"
  end

  local participants = observation.creatures or {}
  local minCount = observation.minCount or self.minCount
  local maxCount = observation.maxCount or self.maxCount
  if #participants == 0 then
    self.state = "idle"
    return nil
  end
  if #participants >= maxCount then
    self.state = "completed"
    return nil
  end
  if self.state == "idle" or self.state == "aborted" or self.state == "completed" then
    if #participants >= minCount then return nil end
    self.state = "gathering"
  end

  local now = context.now or 0
  local evidenceParticipants = {}
  for index, id in ipairs(participants) do evidenceParticipants[index] = id end
  return {
    domain = "movement", action = "lure", source = "DynamicLure",
    priority = 60, safety = 1, confidence = math.min(1, 0.5 + (minCount - #participants) / minCount * 0.3),
    createdAt = now, expiresAt = now + self.ttl,
    snapshotGeneration = generation, combatGeneration = generations.combat or 0,
    evidence = { count = #participants, participants = evidenceParticipants },
  }
end

return DynamicLureState
