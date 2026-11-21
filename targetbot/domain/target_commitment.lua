local ReleaseReason = ReleaseReason or dofile("targetbot/domain/release_reasons.lua")

local TargetCommitmentManager = {}

local DEFAULT_HOLD_MS = {
  FINISH_KILL = 5000,
  PULL_ANCHOR = 8000,
  LURE_ANCHOR = 8000,
  STICKINESS = 3000,
  ENGAGEMENT = 2000,
}

local NEVER_BLOCKS = {
  [ReleaseReason.TARGET_DEAD] = true,
  [ReleaseReason.TARGET_REMOVED] = true,
  [ReleaseReason.TARGET_DIFFERENT_FLOOR] = true,
  [ReleaseReason.SAFETY_ABORT] = true,
  [ReleaseReason.CONFIRMED_HARD_UNREACHABLE] = true,
  [ReleaseReason.MANUAL_OVERRIDE] = true,
  [ReleaseReason.TARGETBOT_DISABLED] = true,
}

local state = {
  commitments = {},
  activeId = nil,
  generation = 0,
}

function TargetCommitmentManager.acquire(targetId, reason, healthPercent, config)
  config = config or {}
  if state.activeId and state.activeId ~= targetId then
    state.commitments[state.activeId] = nil
  end
  state.generation = state.generation + 1
  local now = nExBot.Shared.nowMs()
  local holdMs = config.minimumHoldMs or DEFAULT_HOLD_MS[reason] or 0

  state.commitments[targetId] = {
    targetId = targetId,
    reason = reason,
    startedAt = now,
    healthAtAcquisition = healthPercent,
    minimumHoldUntil = now + holdMs,
    releasePolicy = "DEAD_UNSAFE_MANUAL_OR_CONFIRMED_UNREACHABLE",
    generation = state.generation,
  }
  state.activeId = targetId
  return state.commitments[targetId]
end

function TargetCommitmentManager.isActive(targetId)
  local c = state.commitments[targetId]
  if not c then return false, nil end
  return true, c
end

function TargetCommitmentManager.release(targetId, reason, generation)
  local c = state.commitments[targetId]
  if not c then return false, "NO_COMMITMENT" end
  if generation and generation ~= c.generation then return false, "STALE_GENERATION" end
  if not ReleaseReason.isValid(reason) then return false, "INVALID_REASON" end

  state.commitments[targetId] = nil
  if state.activeId == targetId then state.activeId = nil end
  state.generation = state.generation + 1
  return true, reason
end

function TargetCommitmentManager.blocksRelease(targetId, proposedReason)
  local c = state.commitments[targetId]
  if not c then return false end
  if NEVER_BLOCKS[proposedReason] then return false end

  local now = nExBot.Shared.nowMs()
  if now < c.minimumHoldUntil then return true end
  return false
end

function TargetCommitmentManager.getActive()
  if not state.activeId then return nil end
  return state.commitments[state.activeId]
end

function TargetCommitmentManager.reset()
  state.commitments = {}
  state.activeId = nil
end

function TargetCommitmentManager.getGeneration()
  return state.generation
end

return TargetCommitmentManager
