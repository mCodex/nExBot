PullPlanner = {}
local PullPlanner_MT = {}
PullPlanner_MT.__index = PullPlanner_MT

function PullPlanner.new(options)
  options = options or {}
  return setmetatable({
    currentPlan = nil,
    enterDistance = options.enterDistance or 5,
    exitDistance = options.exitDistance or 2,
  }, PullPlanner_MT)
end

function PullPlanner_MT:plan(observation, context)
  observation = observation or {}
  context = context or {}
  local now = context.now or 0
  local config = context.config or {}
  local smartPullRange = config.smartPullRange or self.enterDistance
  local exitDistance = config.exitDistance or self.exitDistance

  local participantId = observation.participantId
  local distance = observation.distance
  local currentPos = observation.currentPos
  local safe = observation.safe
  local targetHp = observation.targetHp

  if not participantId or type(distance) ~= "number" then
    return nil, "INVALID_OBSERVATION"
  end

  if distance <= exitDistance then
    return nil, "PULL_TOO_CLOSE"
  end

  if distance > smartPullRange then
    return nil, "PULL_TOO_FAR"
  end

  if safe == false then
    return nil, "UNSAFE_PULL"
  end

  if not currentPos then
    return nil, "NO_DESTINATION"
  end

  local destination = {x = currentPos.x, y = currentPos.y, z = currentPos.z}

  local plan = {
    kind = "PULL",
    pullTargetId = participantId,
    destination = destination,
    path = {},
    expectedParticipants = {participantId},
    attackPolicy = "KEEP_ATTACKING",
    progressMetric = "distance_closing",
    progressDeadlineMs = now + 5000,
    completionConditions = {"TARGET_IN_RANGE"},
    abortConditions = {"TARGET_LOST", "NO_PROGRESS", "SAFETY_ABORT"},
    evidence = { participantId = participantId, distance = distance },
  }

  self.currentPlan = plan
  return plan
end

function PullPlanner_MT:checkProgress(plan, observation)
  plan = plan or self.currentPlan
  if not plan then
    return "ABORTED", "NO_PLAN"
  end

  observation = observation or {}
  local distance = observation.distance
  local participantId = observation.participantId
  local safe = observation.safe

  if participantId and participantId ~= plan.pullTargetId then
    return "ABORTED", "TARGET_LOST"
  end

  if safe == false then
    return "ABORTED", "SAFETY_ABORT"
  end

  if type(distance) ~= "number" then
    return "ABORTED", "TARGET_LOST"
  end

  if distance <= (plan.evidence and plan.evidence.exitDistance or 2) then
    return "COMPLETED", "TARGET_IN_RANGE"
  end

  local now = observation.now or 0
  if now > plan.progressDeadlineMs then
    return "STALLED", "NO_PROGRESS"
  end

  return "IN_PROGRESS"
end

function PullPlanner_MT:reset()
  self.currentPlan = nil
end

return PullPlanner
