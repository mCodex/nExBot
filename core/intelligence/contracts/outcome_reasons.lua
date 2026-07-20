local IntelligenceOutcomeReasons = {}

IntelligenceOutcomeReasons.ClosureReason = {
  COMPLETED = "completed",
  TARGET_KILLED = "target_killed",
  TARGET_LOST = "target_lost",
  TARGET_UNREACHABLE = "target_unreachable",
  PLAYER_OVERRIDE = "player_override",
  BOT_DISABLED = "bot_disabled",
  ROUTE_CHANGED = "route_changed",
  PROFILE_CHANGED = "profile_changed",
  RECONNECT = "reconnect",
  GAME_END = "game_end",
  TIMEOUT = "timeout",
  SAFETY_ABORT = "safety_abort",
  INSUFFICIENT_CAPACITY = "insufficient_capacity",
  CONTAINER_UNAVAILABLE = "container_unavailable",
  CORPSE_EXPIRED = "corpse_expired",
  LOOT_COMPLETED = "loot_completed",
  LOOT_SKIPPED_BY_POLICY = "loot_skipped_by_policy",
  TELEPORT_OR_FLOOR_CHANGE = "teleport_or_floor_change",
  GENERATION_MISMATCH = "generation_mismatch",
  INVALIDATED = "invalidated",
}

local valid_set = {}
local ambiguous_set = {}

for _, v in pairs(IntelligenceOutcomeReasons.ClosureReason) do
  valid_set[v] = true
end

local ambiguous_reasons = {
  reconnect = true, player_override = true, game_end = true,
  teleport_or_floor_change = true, invalidated = true,
}
for k in pairs(ambiguous_reasons) do
  ambiguous_set[k] = true
end

function IntelligenceOutcomeReasons.isValid(reason)
  if type(reason) ~= "string" then return false end
  return valid_set[reason] == true
end

function IntelligenceOutcomeReasons.isAmbiguous(reason)
  if type(reason) ~= "string" then return false end
  return ambiguous_set[reason] == true
end

function IntelligenceOutcomeReasons.all()
  local list = {}
  for _, v in pairs(IntelligenceOutcomeReasons.ClosureReason) do
    table.insert(list, v)
  end
  table.sort(list)
  return list
end

nExBot = nExBot or {}
nExBot.IntelligenceOutcomeReasons = IntelligenceOutcomeReasons

return IntelligenceOutcomeReasons
