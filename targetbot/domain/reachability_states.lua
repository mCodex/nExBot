ReachabilityState = {}

ReachabilityState.ATTACKABLE_NOW = "ATTACKABLE_NOW"
ReachabilityState.REPOSITION_REQUIRED = "REPOSITION_REQUIRED"
ReachabilityState.TEMPORARILY_BLOCKED = "TEMPORARILY_BLOCKED"
ReachabilityState.VISIBILITY_UNKNOWN = "VISIBILITY_UNKNOWN"
ReachabilityState.PATH_API_UNAVAILABLE = "PATH_API_UNAVAILABLE"
ReachabilityState.MOVING_TARGET = "MOVING_TARGET"
ReachabilityState.DIFFERENT_FLOOR = "DIFFERENT_FLOOR"
ReachabilityState.REMOVED = "REMOVED"
ReachabilityState.CONFIRMED_HARD_UNREACHABLE = "CONFIRMED_HARD_UNREACHABLE"

local HARD_RELEASE = {
  [ReachabilityState.DIFFERENT_FLOOR] = true,
  [ReachabilityState.REMOVED] = true,
  [ReachabilityState.CONFIRMED_HARD_UNREACHABLE] = true,
}

local TEMPORARY = {
  [ReachabilityState.TEMPORARILY_BLOCKED] = true,
  [ReachabilityState.VISIBILITY_UNKNOWN] = true,
  [ReachabilityState.PATH_API_UNAVAILABLE] = true,
  [ReachabilityState.MOVING_TARGET] = true,
  [ReachabilityState.REPOSITION_REQUIRED] = true,
}

function ReachabilityState.isHardRelease(state)
  return HARD_RELEASE[state] == true
end

function ReachabilityState.isTemporary(state)
  return TEMPORARY[state] == true
end

function ReachabilityState.isAttackable(state)
  return state == ReachabilityState.ATTACKABLE_NOW
end

return ReachabilityState
