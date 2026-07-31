local TargetCandidateEvaluator = {}
local E = TargetCandidateEvaluator

local function getHp(context)
  if context.creatureHpPercent then return context.creatureHpPercent end
  return 100
end

local function calcSafetyTier(state, pathCost, playerHp)
  if state == ReachabilityState.ATTACKABLE_NOW then
    if playerHp > 50 and pathCost <= 7 then return 3 end
    return 2
  end
  if state == ReachabilityState.REPOSITION_REQUIRED then
    if playerHp > 30 then return 1 end
    return 1
  end
  if state == ReachabilityState.TEMPORARILY_BLOCKED then
    if playerHp > 30 then return 1 end
    return 1
  end
  return 0
end

local function calcCommitmentTier(commitment, hp)
  if not commitment then return 0 end
  if hp < 30 then return 2 end
  return 1
end

local function calcKillCompletion(hp)
  if hp <= 5 then return 1.0 end
  if hp <= 10 then return 0.9 end
  if hp <= 20 then return 0.75 end
  if hp <= 30 then return 0.6 end
  if hp <= 50 then return 0.4 end
  if hp <= 70 then return 0.2 end
  return 0.1
end

local function calcReachabilityConfidence(state)
  if state == ReachabilityState.ATTACKABLE_NOW then return 1.0 end
  if state == ReachabilityState.REPOSITION_REQUIRED then return 0.7 end
  if state == ReachabilityState.TEMPORARILY_BLOCKED then return 0.3 end
  return 0.0
end

function E.evaluate(creature, context)
  local hp = getHp(context)
  local pathCost = (context.reachabilityPath and #context.reachabilityPath) or 99

  return {
    safetyTier = calcSafetyTier(context.reachabilityState, pathCost, context.playerHpPercent or 100),
    commitmentTier = calcCommitmentTier(context.commitment, hp),
    configuredPriority = (context.config and context.config.priority) or 1,
    killCompletionScore = calcKillCompletion(hp),
    reachabilityConfidence = calcReachabilityConfidence(context.reachabilityState),
    attackContinuityScore = context.isCurrentTarget and 1.0 or 0.0,
    pathCost = pathCost,
    tacticalUtility = 0.5,
    learnedUtility = 0.5,
  }
end

function E.compare(scoreA, scoreB)
  local A, B = scoreA, scoreB

  if A.safetyTier ~= B.safetyTier then
    return (A.safetyTier > B.safetyTier) and "A" or "B", "safetyTier"
  end

  if A.commitmentTier ~= B.commitmentTier then
    return (A.commitmentTier > B.commitmentTier) and "A" or "B", "commitmentTier"
  end

  if A.configuredPriority ~= B.configuredPriority then
    return (A.configuredPriority > B.configuredPriority) and "A" or "B", "configuredPriority"
  end

  if A.killCompletionScore ~= B.killCompletionScore then
    return (A.killCompletionScore > B.killCompletionScore) and "A" or "B", "killCompletionScore"
  end

  if A.attackContinuityScore ~= B.attackContinuityScore then
    return (A.attackContinuityScore > B.attackContinuityScore) and "A" or "B", "attackContinuityScore"
  end

  if A.reachabilityConfidence ~= B.reachabilityConfidence then
    return (A.reachabilityConfidence > B.reachabilityConfidence) and "A" or "B", "reachabilityConfidence"
  end

  if A.pathCost ~= B.pathCost then
    return (A.pathCost < B.pathCost) and "A" or "B", "pathCost"
  end

  if A.tacticalUtility ~= B.tacticalUtility then
    return (A.tacticalUtility > B.tacticalUtility) and "A" or "B", "tacticalUtility"
  end

  if A.learnedUtility ~= B.learnedUtility then
    return (A.learnedUtility > B.learnedUtility) and "A" or "B", "learnedUtility"
  end

  return "A", "equal"
end

function E.shouldSwitch(currentScore, candidateScore, hysteresisMargin)
  hysteresisMargin = hysteresisMargin or 0

  if currentScore.commitmentTier > 0 and candidateScore.commitmentTier < currentScore.commitmentTier then
    return false, "committed_target_protection"
  end

  local winner, reason = E.compare(currentScore, candidateScore)
  if winner ~= "B" then
    return false, reason == "equal" and "equal" or "current_wins"
  end

  local margin =
    (candidateScore.safetyTier - currentScore.safetyTier) * 3
    + (candidateScore.commitmentTier - currentScore.commitmentTier) * 2
    + (candidateScore.configuredPriority - currentScore.configuredPriority) * 0.01
    + (candidateScore.killCompletionScore - currentScore.killCompletionScore)
    + (candidateScore.attackContinuityScore - currentScore.attackContinuityScore)
    + (candidateScore.reachabilityConfidence - currentScore.reachabilityConfidence)
    + (currentScore.pathCost - candidateScore.pathCost) * 0.01
    + (candidateScore.tacticalUtility - currentScore.tacticalUtility)
    + (candidateScore.learnedUtility - currentScore.learnedUtility)

  if margin >= hysteresisMargin then
    return true, reason
  end

  return false, "hysteresis"
end

return TargetCandidateEvaluator
