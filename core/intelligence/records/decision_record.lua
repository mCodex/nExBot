local VALID_DECISION_TYPES = {
  target_select = true,
  target_switch = true,
  movement = true,
  loot = true,
  path_mode = true,
}

local REQUIRED_FIELDS = {
  "decisionId", "sessionId", "huntId", "encounterId",
  "routeGeneration", "decisionType", "candidates", "baseline",
}

local DEFAULT_PREDICTION = {
  modelName = "",
  modelVersion = 0,
  value = 0,
  confidence = 0,
  evidence = 0,
  calibrated = false,
  abstained = false,
  adjustment = 0,
}

local DecisionRecord = {}
DecisionRecord.__index = DecisionRecord

function DecisionRecord.new(_config)
  local self = setmetatable({}, DecisionRecord)
  return self
end

function DecisionRecord:create(config)
  if not config then return nil end

  for _, field in ipairs(REQUIRED_FIELDS) do
    if config[field] == nil then return nil end
  end

  if not VALID_DECISION_TYPES[config.decisionType] then return nil end

  local prediction = {}
  for k, v in pairs(DEFAULT_PREDICTION) do prediction[k] = v end
  if config.prediction then
    for k, v in pairs(config.prediction) do prediction[k] = v end
  end

  return {
    decisionId = config.decisionId,
    sessionId = config.sessionId,
    huntId = config.huntId,
    encounterId = config.encounterId,
    routeGeneration = config.routeGeneration,
    decisionType = config.decisionType,
    createdAt = os.time(),
    expiresAt = 0,
    baseline = config.baseline,
    candidates = config.candidates,
    featureSchemaVersion = 1,
    features = config.features or {},
    missingMask = config.missingMask or {},
    prediction = prediction,
    selectedCandidateId = config.baseline.selectedCandidateId,
    selectionSource = "baseline",
    propensity = 1.0,
  }
end

function DecisionRecord:close(decision, outcome)
  if not decision or not outcome then return nil end
  decision.outcome = outcome
  decision.outcome.closedAt = os.time()
  return decision
end

function DecisionRecord:validate(decision)
  if type(decision) ~= "table" then return false end
  if type(decision.decisionId) ~= "string" then return false end
  if type(decision.sessionId) ~= "string" then return false end
  if type(decision.huntId) ~= "string" then return false end
  if type(decision.encounterId) ~= "string" then return false end
  if type(decision.createdAt) ~= "number" then return false end
  if not VALID_DECISION_TYPES[decision.decisionType] then return false end
  if type(decision.candidates) ~= "table" then return false end
  if type(decision.baseline) ~= "table" then return false end
  return true
end

nExBot = nExBot or {}
nExBot.IntelligenceDecisionRecord = DecisionRecord

return DecisionRecord
