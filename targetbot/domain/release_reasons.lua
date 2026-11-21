ReleaseReason = {}

ReleaseReason.TARGET_DEAD = "TARGET_DEAD"
ReleaseReason.TARGET_REMOVED = "TARGET_REMOVED"
ReleaseReason.TARGET_DIFFERENT_FLOOR = "TARGET_DIFFERENT_FLOOR"
ReleaseReason.MANUAL_OVERRIDE = "MANUAL_OVERRIDE"
ReleaseReason.SAFETY_ABORT = "SAFETY_ABORT"
ReleaseReason.STRICT_FOLLOW_OVERRIDE = "STRICT_FOLLOW_OVERRIDE"
ReleaseReason.CONFIRMED_HARD_UNREACHABLE = "CONFIRMED_HARD_UNREACHABLE"
ReleaseReason.TARGET_TIMEOUT_WITH_EVIDENCE = "TARGET_TIMEOUT_WITH_EVIDENCE"
ReleaseReason.TARGETBOT_DISABLED = "TARGETBOT_DISABLED"

local VALID_REASONS = {}
for _, v in pairs(ReleaseReason) do VALID_REASONS[v] = true end

function ReleaseReason.isValid(reason)
  return VALID_REASONS[reason] == true
end

function ReleaseReason.isHardRelease(reason)
  return reason == ReleaseReason.TARGET_DEAD
    or reason == ReleaseReason.TARGET_REMOVED
    or reason == ReleaseReason.TARGET_DIFFERENT_FLOOR
    or reason == ReleaseReason.CONFIRMED_HARD_UNREACHABLE
end

return ReleaseReason
