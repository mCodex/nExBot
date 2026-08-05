--[[
  navigation/retry.lua — the SINGLE retry owner.

  Exactly one component owns: attempt ID, attempt number, failure class,
  retry budget, escalation phase, backoff, terminal decision.
  No other module (goto action, path strategy, recovery, transitions) keeps
  its own retry counter for navigation.
]]

local domain = require("navigation.domain")
local D = domain

local RetryPolicy = {}

-- failure class -> escalation phase order (bounded retries per phase)
local PHASE_FOR_FAILURE = {
  [D.FAILURE.TEMPORARY_CREATURE_BLOCK] = D.RETRY_PHASE.WAIT_TEMPORARY_BLOCKER,
  [D.FAILURE.FIRST_STEP_BLOCKED] = D.RETRY_PHASE.REFRESH_CURRENT_PATH,
  [D.FAILURE.STALE_PATH] = D.RETRY_PHASE.REFRESH_CURRENT_PATH,
  [D.FAILURE.STATIC_TOPOLOGY_BLOCK] = D.RETRY_PHASE.ROUTE_EDGE_RECOVERY,
  [D.FAILURE.FIELD_BLOCK] = D.RETRY_PHASE.RESOLVE_OBSTACLE,
  [D.FAILURE.DOOR_REQUIRED] = D.RETRY_PHASE.RESOLVE_OBSTACLE,
  [D.FAILURE.TOOL_REQUIRED] = D.RETRY_PHASE.RESOLVE_OBSTACLE,
  [D.FAILURE.MISSING_TOOL] = D.RETRY_PHASE.FAILED_SAFE,
  [D.FAILURE.BROKEN_BRIDGE] = D.RETRY_PHASE.ROUTE_EDGE_RECOVERY,
  [D.FAILURE.BROKEN_BRIDGE_NO_ALTERNATE] = D.RETRY_PHASE.FAILED_SAFE,
  [D.FAILURE.PARTIAL_AUTOWALK] = D.RETRY_PHASE.REJOIN_CURRENT_EDGE,
  [D.FAILURE.SERVER_STEP_REJECTED] = D.RETRY_PHASE.RETRY_SAME_VALIDATED_STEP,
  [D.FAILURE.NO_POSITION_ACK] = D.RETRY_PHASE.RETRY_SAME_VALIDATED_STEP,
  [D.FAILURE.PATH_DIVERGENCE] = D.RETRY_PHASE.LOCAL_REPLAN,
  [D.FAILURE.WRONG_FLOOR] = D.RETRY_PHASE.ROUTE_EDGE_RECOVERY,
  [D.FAILURE.WRONG_TRANSITION_EXIT] = D.RETRY_PHASE.ROUTE_EDGE_RECOVERY,
  [D.FAILURE.ACTION_NO_EFFECT] = D.RETRY_PHASE.RESOLVE_OBSTACLE,
  [D.FAILURE.COMBAT_PREEMPTED] = D.RETRY_PHASE.WAIT_TEMPORARY_BLOCKER,
  [D.FAILURE.MANUAL_PREEMPTED] = D.RETRY_PHASE.WAIT_TEMPORARY_BLOCKER,
  [D.FAILURE.MAP_RELOADED] = D.RETRY_PHASE.REFRESH_CURRENT_PATH,
  [D.FAILURE.RECOVERY_TARGET_UNREACHABLE] = D.RETRY_PHASE.ROUTE_EDGE_RECOVERY,
  [D.FAILURE.ROUTE_CONFIGURATION_ERROR] = D.RETRY_PHASE.FAILED_SAFE,
}

-- Per-phase budgets: max attempts before escalating to the next phase.
local PHASE_BUDGET = {
  [D.RETRY_PHASE.RETRY_SAME_VALIDATED_STEP] = 2,
  [D.RETRY_PHASE.REFRESH_CURRENT_PATH] = 3,
  [D.RETRY_PHASE.WAIT_TEMPORARY_BLOCKER] = 4,
  [D.RETRY_PHASE.RESOLVE_OBSTACLE] = 2,
  [D.RETRY_PHASE.LOCAL_REPLAN] = 2,
  [D.RETRY_PHASE.REJOIN_CURRENT_EDGE] = 2,
  [D.RETRY_PHASE.BACKTRACK_CONFIRMED_ANCHOR] = 1,
  [D.RETRY_PHASE.ROUTE_EDGE_RECOVERY] = 2,
  [D.RETRY_PHASE.FAILED_SAFE] = 1,
}

-- Backoff (ms) per phase attempt.
local PHASE_BACKOFF = {
  [D.RETRY_PHASE.RETRY_SAME_VALIDATED_STEP] = 250,
  [D.RETRY_PHASE.REFRESH_CURRENT_PATH] = 500,
  [D.RETRY_PHASE.WAIT_TEMPORARY_BLOCKER] = 750,
  [D.RETRY_PHASE.RESOLVE_OBSTACLE] = 500,
  [D.RETRY_PHASE.LOCAL_REPLAN] = 300,
  [D.RETRY_PHASE.REJOIN_CURRENT_EDGE] = 500,
  [D.RETRY_PHASE.BACKTRACK_CONFIRMED_ANCHOR] = 250,
  [D.RETRY_PHASE.ROUTE_EDGE_RECOVERY] = 1000,
  [D.RETRY_PHASE.FAILED_SAFE] = 0,
}

-- Which failures are inherently terminal (no retry loop).
local TERMINAL = {
  [D.FAILURE.ROUTE_CONFIGURATION_ERROR] = true,
  [D.FAILURE.MISSING_TOOL] = true,
  [D.FAILURE.BROKEN_BRIDGE_NO_ALTERNATE] = true,
}

local ESCALATION_ORDER = {
  D.RETRY_PHASE.RETRY_SAME_VALIDATED_STEP,
  D.RETRY_PHASE.REFRESH_CURRENT_PATH,
  D.RETRY_PHASE.WAIT_TEMPORARY_BLOCKER,
  D.RETRY_PHASE.RESOLVE_OBSTACLE,
  D.RETRY_PHASE.LOCAL_REPLAN,
  D.RETRY_PHASE.REJOIN_CURRENT_EDGE,
  D.RETRY_PHASE.BACKTRACK_CONFIRMED_ANCHOR,
  D.RETRY_PHASE.ROUTE_EDGE_RECOVERY,
  D.RETRY_PHASE.FAILED_SAFE,
}

-- Create a fresh retry context for one route edge attempt.
function RetryPolicy.new(routeId, edgeId)
  return {
    routeId = routeId,
    edgeId = edgeId,
    attemptId = 1,
    phaseIndex = 1,
    phaseAttempts = 0,
    totalAttempts = 0,
    lastFailure = nil,
    lastPhase = nil,
    lastFailureAt = 0,
  }
end

--- Record a failure and compute the next action.
-- @param retry  retry context (mutated)
-- @param failure string  D.FAILURE.*
-- @param nowMs  number
-- @param opts   { hasProgress=bool, newEvidence=bool }
-- @return table { action = "RETRY"|"ESCALATE"|"WAIT"|"RECOVER"|"FAILED_SAFE",
--                 phase = RETRY_PHASE.*, attemptId, retryAfterMs, reason }
function RetryPolicy.recordFailure(retry, failure, nowMs, opts)
  opts = opts or {}
  retry.lastFailure = failure
  retry.lastFailureAt = nowMs
  if TERMINAL[failure] then
    return {
      action = "FAILED_SAFE", phase = D.RETRY_PHASE.FAILED_SAFE,
      attemptId = retry.attemptId, retryAfterMs = 0, reason = failure,
    }
  end

  local phase = PHASE_FOR_FAILURE[failure] or D.RETRY_PHASE.REFRESH_CURRENT_PATH

  -- Observed progress resets the phase counter (fresh evidence).
  if opts.hasProgress or opts.newEvidence then
    retry.phaseAttempts = 0
    retry.lastPhase = nil
  end

  if retry.lastPhase ~= phase then
    retry.lastPhase = phase
    retry.phaseAttempts = 1
    retry.attemptId = retry.attemptId + 1
    retry.totalAttempts = retry.totalAttempts + 1
    return {
      action = "RETRY", phase = phase, attemptId = retry.attemptId,
      retryAfterMs = PHASE_BACKOFF[phase] or 250, reason = failure,
    }
  end

  retry.phaseAttempts = retry.phaseAttempts + 1
  retry.attemptId = retry.attemptId + 1
  retry.totalAttempts = retry.totalAttempts + 1

  if retry.phaseAttempts > (PHASE_BUDGET[phase] or 2) then
    -- Escalate to the next phase.
    for i, p in ipairs(ESCALATION_ORDER) do
      if p == phase then
        local nextPhase = ESCALATION_ORDER[math.min(i + 1, #ESCALATION_ORDER)]
        retry.lastPhase = nextPhase
        retry.phaseAttempts = 1
        local action = (nextPhase == D.RETRY_PHASE.FAILED_SAFE) and "FAILED_SAFE"
          or (nextPhase == D.RETRY_PHASE.ROUTE_EDGE_RECOVERY or nextPhase == D.RETRY_PHASE.BACKTRACK_CONFIRMED_ANCHOR)
          and "RECOVER" or "ESCALATE"
        return {
          action = action, phase = nextPhase, attemptId = retry.attemptId,
          retryAfterMs = PHASE_BACKOFF[nextPhase] or 500, reason = failure,
        }
      end
    end
  end

  return {
    action = "RETRY", phase = phase, attemptId = retry.attemptId,
    retryAfterMs = PHASE_BACKOFF[phase] or 250, reason = failure,
  }
end

--- Reset retry state: called only after observed progress or an explicit
-- transition completion (never by refocusing alone).
function RetryPolicy.onProgress(retry)
  retry.phaseIndex = 1
  retry.phaseAttempts = 0
  retry.lastPhase = nil
  retry.attemptId = 1  -- the next dispatch is attempt #1 again
  retry.totalAttempts = 0
  retry.lastFailure = nil
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.retry"] = RetryPolicy end
return RetryPolicy