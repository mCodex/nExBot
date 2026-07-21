local IntelligenceOutcomeReasons = nExBot.IntelligenceOutcomeReasons
  or dofile("core/intelligence/contracts/outcome_reasons.lua")

local OutcomeRecord = {}
OutcomeRecord.__index = OutcomeRecord

local VALID_MEASUREMENTS = {
  elapsedMs = true,
  progressTiles = true,
  targetHpDelta = true,
  damageTaken = true,
  resourceCost = true,
  xpDelta = true,
  lootValue = true,
  lootValueConfidence = true,
  itemsAvailable = true,
  itemsCaptured = true,
  manualIntervention = true,
}

local DEFAULT_MEASUREMENTS = {
  elapsedMs = 0,
  progressTiles = 0,
  targetHpDelta = 0,
  damageTaken = 0,
  resourceCost = 0,
  xpDelta = 0,
  lootValue = nil,
  lootValueConfidence = 0,
  itemsAvailable = nil,
  itemsCaptured = nil,
  manualIntervention = false,
}

function OutcomeRecord.new(_config)
  local self = setmetatable({}, OutcomeRecord)
  return self
end

function OutcomeRecord:create(config)
  if not config then return nil end
  if not config.decisionId then return nil end
  if not config.actionId then return nil end
  if not config.closureReason then return nil end
  if not IntelligenceOutcomeReasons.isValid(config.closureReason) then return nil end

  local measurements = {}
  for k, v in pairs(DEFAULT_MEASUREMENTS) do measurements[k] = v end
  if config.measurements then
    for k, v in pairs(config.measurements) do measurements[k] = v end
  end

  return {
    decisionId = config.decisionId,
    actionId = config.actionId,
    closedAt = os.time(),
    closureReason = config.closureReason,
    success = config.success,
    attributionConfidence = config.attributionConfidence or 0,
    measurements = measurements,
  }
end

function OutcomeRecord:validate(outcome)
  if type(outcome) ~= "table" then return false end
  if type(outcome.decisionId) ~= "string" then return false end
  if type(outcome.actionId) ~= "string" then return false end
  if type(outcome.closedAt) ~= "number" then return false end
  if not IntelligenceOutcomeReasons.isValid(outcome.closureReason) then return false end
  return true
end

function OutcomeRecord:measure(outcome, key, value)
  if not VALID_MEASUREMENTS[key] then return nil end
  outcome.measurements[key] = value
  return outcome
end

nExBot = nExBot or {}
nExBot.IntelligenceOutcomeRecord = OutcomeRecord

return OutcomeRecord
