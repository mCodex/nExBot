local Registry = IntelligenceModelRegistry or dofile("core/intelligence/learning/model_registry.lua")

IntelligenceModelCatalog = {}
local Catalog = IntelligenceModelCatalog

local definitions = {
  { "TargetValueModel", "target_value", 20 },
  { "RouteReliabilityModel", "route_reliability", 20 },
  { "ResourceEfficiencyModel", "resource_efficiency", 20 },
  { "TimingModel", "timing", 15 },
  { "RiskAssessmentModel", "risk_assessment", 20 },
  { "LootOpportunityModel", "loot_opportunity", 15 },
  { "EnsembleMetaModel", "ensemble_meta", 30 },
}

local Model = {}
Model.__index = Model

local function copyState(state)
  return { successes = state.successes, failures = state.failures, samples = state.samples,
    evaluations = state.evaluations, correct = state.correct,
    features = state.features and { unpack(state.features) } or nil,
    predictions = state.predictions and { unpack(state.predictions) } or nil }
end

function Model:initialize(saved)
  self:reset()
  if saved then self:deserialize(saved) end
  return self
end

function Model:observe(observation)
  assert(type(observation) == "table", "observation required")
  local success = observation.success
  if success == nil then success = observation.label end
  assert(type(success) == "boolean", "boolean observation label required")
  local weight = math.max(0, math.min(observation.weight or 1, self.maxWeight))
  local features = self:extractFeatures(observation)
  self.pending[#self.pending + 1] = { success = success, weight = weight, features = features }
  if #self.pending > self.maxPending then table.remove(self.pending, 1) end
  return true
end

function Model:extractFeatures(observation)
  return observation.features or {}
end

function Model:update()
  if #self.pending == 0 then return false end
  self.checkpoint = copyState(self.state)
  for _, obs in ipairs(self.pending) do
    if obs.success then self.state.successes = self.state.successes + obs.weight
    else self.state.failures = self.state.failures + obs.weight end
    self.state.samples = self.state.samples + 1
    if obs.features and #self.state.features < 100 then
      self.state.features[#self.state.features + 1] = obs.features
    end
  end
  self.pending = {}
  return true
end

function Model:predict()
  local total = self.state.successes + self.state.failures
  local probability = total > 0 and (self.state.successes / total) or 0.5
  local evidence = self.state.samples
  local confidence = math.min(1, evidence / self.minSamples)
  local explanation = string.format("%s: %.3f from %d observations", self.capability, probability, evidence)
  if #self.state.features > 0 then
    local lastFeatures = self.state.features[#self.state.features]
    local featureNames = {}
    for k, _ in pairs(lastFeatures) do featureNames[#featureNames + 1] = k end
    if #featureNames > 0 then
      explanation = explanation .. " [features: " .. table.concat(featureNames, ", ") .. "]"
    end
  end
  return { probability = probability, confidence = confidence, evidence = evidence,
    uncertainty = 1 - confidence, explanation = explanation }
end

function Model:evaluate(success)
  assert(type(success) == "boolean", "boolean evaluation required")
  local predicted = self:predict().probability >= self.threshold
  self.state.evaluations = self.state.evaluations + 1
  if predicted == success then self.state.correct = self.state.correct + 1 end
  return predicted == success
end

function Model:serialize() return copyState(self.state) end

function Model:deserialize(saved)
  assert(type(saved) == "table", "model state required")
  for _, key in ipairs({ "successes", "failures", "samples", "evaluations", "correct" }) do
    assert(type(saved[key]) == "number" and saved[key] >= 0, "invalid model state: " .. key)
  end
  self.state = copyState(saved)
  self.pending, self.checkpoint = {}, nil
  return true
end

function Model:reset()
  self.state = { successes = 1, failures = 1, samples = 0, evaluations = 0, correct = 0, features = {} }
  self.pending, self.checkpoint = {}, nil
  return true
end

function Model:rollback()
  if not self.checkpoint then return false end
  self.state, self.checkpoint, self.pending = self.checkpoint, nil, {}
  return true
end

function Model:diagnostics()
  return { name = self.name, capability = self.capability, samples = self.state.samples,
    pending = #self.pending, confidence = self:predict().confidence,
    accuracy = self.state.evaluations == 0 and nil or self.state.correct / self.state.evaluations,
    memoryBudgetBytes = self.memoryBudgetBytes, cpuBudgetMicros = self.cpuBudgetMicros }
end

local function create(name, capability, minSamples)
  local model = setmetatable({ name = name, capability = capability, minSamples = minSamples,
    threshold = 0.5, maxPending = 64, maxWeight = 10, updateIntervalMs = 1000,
    cpuBudgetMicros = 250, memoryBudgetBytes = 4096 }, Model)
  return model:initialize()
end

-- TargetValueModel: predicts target value (XP, loot, difficulty)
local TargetValue = create("TargetValueModel", "target_value", 20)
function TargetValue:extractFeatures(obs)
  return { target_xp = obs.target_xp or 0, target_loot = obs.target_loot or 0,
    target_difficulty = obs.target_difficulty or 0 }
end

-- RouteReliabilityModel: predicts route success probability
local RouteReliability = create("RouteReliabilityModel", "route_reliability", 20)
function RouteReliability:extractFeatures(obs)
  return { route_distance = obs.route_distance or 0, route_danger = obs.route_danger or 0,
    route_known = obs.route_known and 1 or 0 }
end

-- ResourceEfficiencyModel: predicts resource cost efficiency
local ResourceEfficiency = create("ResourceEfficiencyModel", "resource_efficiency", 20)
function ResourceEfficiency:extractFeatures(obs)
  return { resource_cost = obs.resource_cost or 0, resource_gain = obs.resource_gain or 0,
    efficiency = obs.resource_gain and obs.resource_cost and
      (obs.resource_cost > 0 and obs.resource_gain / obs.resource_cost or 0) or 0 }
end

-- TimingModel: predicts optimal timing for actions
local Timing = create("TimingModel", "timing", 15)
function Timing:extractFeatures(obs)
  return { time_pressure = obs.time_pressure or 0, cooldown_remaining = obs.cooldown_remaining or 0,
    action_window = obs.action_window or 0 }
end

-- RiskAssessmentModel: predicts risk of death/near-death
local RiskAssessment = create("RiskAssessmentModel", "risk_assessment", 20)
function RiskAssessment:extractFeatures(obs)
  return { hp_ratio = obs.hp_ratio or 1, enemy_count = obs.enemy_count or 0,
    distance_to_safety = obs.distance_to_safety or 0 }
end

-- LootOpportunityModel: predicts loot opportunity quality
local LootOpportunity = create("LootOpportunityModel", "loot_opportunity", 15)
function LootOpportunity:extractFeatures(obs)
  return { loot_rarity = obs.loot_rarity or 0, loot_value = obs.loot_value or 0,
    competition = obs.competition or 0 }
end

-- EnsembleMetaModel: combines predictions from other models
local Ensemble = create("EnsembleMetaModel", "ensemble_meta", 30)
function Ensemble:reset()
  Model.reset(self)
  self.state.predictions = {}
  return true
end
function Ensemble:serialize()
  local s = copyState(self.state)
  s.predictions = self.state.predictions and { unpack(self.state.predictions) } or {}
  return s
end
function Ensemble:deserialize(saved)
  Model.deserialize(self, saved)
  self.state.predictions = saved.predictions or {}
  return true
end
function Ensemble:observe(obs)
  assert(type(obs) == "table", "observation required")
  local success = obs.success
  if success == nil then success = obs.label end
  assert(type(success) == "boolean", "boolean observation label required")
  local weight = math.max(0, math.min(obs.weight or 1, self.maxWeight))
  local prediction = obs.prediction or 0.5
  self.pending[#self.pending + 1] = { success = success, weight = weight, prediction = prediction }
  if #self.pending > self.maxPending then table.remove(self.pending, 1) end
  return true
end
function Ensemble:update()
  if #self.pending == 0 then return false end
  self.checkpoint = copyState(self.state)
  for _, obs in ipairs(self.pending) do
    if obs.success then self.state.successes = self.state.successes + obs.weight
    else self.state.failures = self.state.failures + obs.weight end
    self.state.samples = self.state.samples + 1
    if not self.state.predictions then self.state.predictions = {} end
    self.state.predictions[#self.state.predictions + 1] = obs.prediction
    if #self.state.predictions > 100 then table.remove(self.state.predictions, 1) end
  end
  self.pending = {}
  return true
end
function Ensemble:predict()
  local total = self.state.successes + self.state.failures
  local probability = total > 0 and (self.state.successes / total) or 0.5
  local evidence = self.state.samples
  local confidence = math.min(1, evidence / self.minSamples)
  local recentPredictions = {}
  local predictions = self.state.predictions or {}
  local start = math.max(1, #predictions - 9)
  for i = start, #predictions do
    recentPredictions[#recentPredictions + 1] = predictions[i]
  end
  local ensembleAverage = probability
  if #recentPredictions > 0 then
    local sum = 0
    for _, p in ipairs(recentPredictions) do sum = sum + p end
    ensembleAverage = sum / #recentPredictions
  end
  return { probability = ensembleAverage, confidence = confidence, evidence = evidence,
    uncertainty = 1 - confidence,
    explanation = string.format("%s: ensemble_avg=%.3f base=%.3f from %d observations, %d recent predictions",
      self.capability, ensembleAverage, probability, evidence, #recentPredictions) }
end

local models = {
  TargetValueModel = TargetValue,
  RouteReliabilityModel = RouteReliability,
  ResourceEfficiencyModel = ResourceEfficiency,
  TimingModel = Timing,
  RiskAssessmentModel = RiskAssessment,
  LootOpportunityModel = LootOpportunity,
  EnsembleMetaModel = Ensemble,
}

function Catalog.registerAll(registry)
  registry = registry or Registry.new()
  for _, config in ipairs(definitions) do
    local model = models[config[1]]
    registry:declare({ name = config[1], schemaVersion = 1, featureVersion = 1,
      minEvidence = config[3], minConfidence = 0.6, mode = Registry.SHADOW,
      minimumSamples = config[3], confidenceThreshold = 0.6,
      updateIntervalMs = model.updateIntervalMs, cpuBudgetMicros = model.cpuBudgetMicros,
      memoryBudgetBytes = model.memoryBudgetBytes, model = model,
      observe = function(m, ...) return m:observe(...) end,
      predict = function(m, ...) return m:predict(...) end,
      serialize = function(m) return m:serialize() end,
      deserialize = function(m, s) return m:deserialize(s) end })
  end
  return registry
end

function Catalog.names()
  local names = {}
  for index, config in ipairs(definitions) do names[index] = config[1] end
  return names
end

return Catalog
