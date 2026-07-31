LurePlanner = {}
local LurePlanner_MT = {}
LurePlanner_MT.__index = LurePlanner_MT

function LurePlanner.new(options)
  options = options or {}
  return setmetatable({
    currentPlan = nil,
  }, LurePlanner_MT)
end

function LurePlanner_MT:plan(observation, context)
  observation = observation or {}
  context = context or {}
  local now = context.now or 0
  local config = context.config or {}
  local lureMin = config.lureMin or 3
  local lureMax = config.lureMax or 6
  local anchorRange = config.anchorRange or 5

  local creatureCount = observation.creatureCount or 0
  local targetId = observation.targetId
  local currentPos = observation.currentPos
  local hasCommitment = observation.hasCommitment
  local participantIds = observation.participantIds or {}
  local targetHp = observation.targetHp

  if creatureCount >= lureMax then
    return nil, "NO_VALID_LURE_PLAN"
  end

  if hasCommitment then
    return nil, "LURE_DEFERRED_FINISH_TARGET"
  end

  if not currentPos then
    return nil, "NO_VALID_LURE_PLAN"
  end

  local destination = {x = currentPos.x, y = currentPos.y, z = currentPos.z}

  local plan = {
    kind = "LURE",
    targetId = targetId,
    anchorTargetId = targetId,
    destination = destination,
    path = {},
    participantIds = participantIds,
    desiredCreatureCount = lureMax,
    attackPolicy = "KEEP_ATTACKING",
    startedAt = now,
    expectedDurationMs = 5000,
    progressDeadlineMs = now + 8000,
    abortConditions = {"TARGET_DEAD", "NO_PROGRESS_TIMEOUT", "SAFETY_ABORT"},
    evidence = { count = creatureCount },
  }

  self.currentPlan = plan
  return plan
end

function LurePlanner_MT:checkProgress(plan, observation)
  plan = plan or self.currentPlan
  if not plan then
    return "ABORTED", "NO_PLAN"
  end

  observation = observation or {}
  local creatureCount = observation.creatureCount or 0
  local targetId = observation.targetId
  local targetHp = observation.targetHp

  if targetHp and targetHp <= 0 then
    return "ABORTED", "TARGET_DEAD"
  end

  if creatureCount >= plan.desiredCreatureCount then
    return "COMPLETED", "CREATURE_COUNT_REACHED"
  end

  local now = observation.now or 0
  if now > plan.progressDeadlineMs then
    local lastCount = plan.evidence and plan.evidence.count or 0
    if creatureCount <= lastCount then
      return "STALLED", "NO_PROGRESS_TIMEOUT"
    end
  end

  return "IN_PROGRESS"
end

function LurePlanner_MT:reset()
  self.currentPlan = nil
end

return LurePlanner
