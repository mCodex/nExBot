local IntelligenceEventSchema = {}

IntelligenceEventSchema.SCHEMA_VERSION = 1

IntelligenceEventSchema.TYPES = {
  decision_created = "decision_created",
  decision_selected = "decision_selected",
  decision_rejected = "decision_rejected",
  action_started = "action_started",
  action_progress = "action_progress",
  action_completed = "action_completed",
  action_failed = "action_failed",
  encounter_started = "encounter_started",
  encounter_updated = "encounter_updated",
  encounter_closed = "encounter_closed",
  loot_episode_started = "loot_episode_started",
  loot_item_observed = "loot_item_observed",
  loot_move_attempted = "loot_move_attempted",
  loot_move_verified = "loot_move_verified",
  loot_episode_closed = "loot_episode_closed",
  route_segment_started = "route_segment_started",
  route_segment_progress = "route_segment_progress",
  route_segment_closed = "route_segment_closed",
  hunt_started = "hunt_started",
  hunt_closed = "hunt_closed",
  resource_delta = "resource_delta",
  player_intervention = "player_intervention",
  model_prediction = "model_prediction",
  model_observation = "model_observation",
  guardrail_triggered = "guardrail_triggered",
}

local COMMON_FIELDS = {
  "eventId", "timestamp", "schemaVersion", "source", "sessionId", "characterKey",
}

IntelligenceEventSchema.REQUIRED_FIELDS = {
  decision_created = { "decisionId", "decisionType", "candidates" },
  decision_selected = { "decisionId", "selectedCandidateId", "selectionSource" },
  decision_rejected = { "decisionId", "rejectionReason" },
  action_started = { "actionId", "decisionId", "actionType" },
  action_progress = { "actionId", "progress" },
  action_completed = { "actionId", "outcome" },
  action_failed = { "actionId", "failureReason" },
  encounter_started = { "encounterId", "targetInstanceId" },
  encounter_updated = {},
  encounter_closed = { "encounterId", "closureReason" },
  loot_episode_started = { "lootEpisodeId", "corpseId" },
  loot_item_observed = { "lootEpisodeId", "itemId" },
  loot_move_attempted = { "lootEpisodeId", "itemId" },
  loot_move_verified = { "lootEpisodeId", "itemId", "captured" },
  loot_episode_closed = { "lootEpisodeId", "closureReason" },
  route_segment_started = { "segmentId", "routeId" },
  route_segment_progress = { "segmentId" },
  route_segment_closed = { "segmentId", "closureReason" },
  hunt_started = { "huntId" },
  hunt_closed = { "huntId", "closureReason" },
  resource_delta = { "resourceType", "delta" },
  player_intervention = { "interventionType" },
  model_prediction = { "modelName", "prediction" },
  model_observation = { "modelName", "observation" },
  guardrail_triggered = { "guardrailType", "reason" },
}

local valid_set = {}
for name in pairs(IntelligenceEventSchema.TYPES) do
  valid_set[name] = true
end

function IntelligenceEventSchema.isValidType(typeName)
  if type(typeName) ~= "string" then return false end
  return valid_set[typeName] == true
end

function IntelligenceEventSchema.requiredFieldsFor(typeName)
  if not IntelligenceEventSchema.isValidType(typeName) then return nil end
  local type_fields = IntelligenceEventSchema.REQUIRED_FIELDS[typeName] or {}
  local result = {}
  for _, f in ipairs(COMMON_FIELDS) do table.insert(result, f) end
  for _, f in ipairs(type_fields) do table.insert(result, f) end
  return result
end

function IntelligenceEventSchema.hasField(typeName, fieldName)
  if not IntelligenceEventSchema.isValidType(typeName) then return false end
  local fields = IntelligenceEventSchema.requiredFieldsFor(typeName)
  for _, f in ipairs(fields) do
    if f == fieldName then return true end
  end
  return false
end

nExBot = nExBot or {}
nExBot.IntelligenceEventSchema = IntelligenceEventSchema

return IntelligenceEventSchema
