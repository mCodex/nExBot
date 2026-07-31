local Registry = IntelligenceModelRegistry or dofile("core/intelligence/learning/model_registry.lua")

local KillCompletionModule = KillCompletionModel or dofile("targetbot/ml/kill_completion_model.lua")
local TargetSwitchRiskModule = TargetSwitchRiskModel or dofile("targetbot/ml/target_switch_risk_model.lua")
local LureSuccessModule = LureSuccessModel or dofile("targetbot/ml/lure_success_model.lua")
local PullSuccessModule = PullSuccessModel or dofile("targetbot/ml/pull_success_model.lua")
local RepositionTileModule = RepositionTileModel or dofile("targetbot/ml/reposition_tile_model.lua")

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
  { "KillCompletionModel", "kill_completion", 20 },
  { "TargetSwitchRiskModel", "target_switch_risk", 20 },
  { "LureSuccessModel", "lure_success", 20 },
  { "PullSuccessModel", "pull_success", 20 },
  { "RepositionTileModel", "reposition_tile", 20 },
}

local Model = {}
Model.__index = Model

local function copyArray(t)
  if not t then return nil end
  local c = {}
  for i = 1, #t do c[i] = t[i] end
  return c
end

local function copyState(state)
  return { successes = state.successes, failures = state.failures, samples = state.samples,
    evaluations = state.evaluations, correct = state.correct,
    features = copyArray(state.features),
    predictions = copyArray(state.predictions) }
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
  self._pendingTail = self._pendingTail + 1
  self._pendingQueue[self._pendingTail] = { success = success, weight = weight, features = features }
  if self._pendingTail - self._pendingHead + 1 > self.maxPending then
    self._pendingHead = self._pendingHead + 1
  end
  return true
end

function Model:extractFeatures(observation)
  return observation.features or {}
end

function Model:update()
  if self._pendingHead > self._pendingTail then return false end
  self.checkpoint = copyState(self.state)
  for i = self._pendingHead, self._pendingTail do
    local obs = self._pendingQueue[i]
    if obs.success then self.state.successes = self.state.successes + obs.weight
    else self.state.failures = self.state.failures + obs.weight end
    self.state.samples = self.state.samples + 1
    if obs.features and #self.state.features < 100 then
      self.state.features[#self.state.features + 1] = { features = obs.features, success = obs.success }
    end
  end
  self._pendingHead = 1
  self._pendingTail = 0
  return true
end

function Model:predict()
  local alpha = self.state.successes + 1
  local beta = self.state.failures + 1
  local mean = alpha / (alpha + beta)
  local evidence = self.state.samples
  local uncertainty = math.sqrt((alpha * beta) / ((alpha + beta)^2 * (alpha + beta + 1)))
  local confidence = 1 - uncertainty
  local probability = mean
  if #self.state.features > 0 then
    local lastEntry = self.state.features[#self.state.features]
    local lastFeatures = lastEntry.features or lastEntry
    local matches = {}
    for i = 1, #self.state.features - 1 do
      local entry = self.state.features[i]
      local stored = entry.features or entry
      local sim = 0
      for k, v in pairs(lastFeatures) do
        if v ~= 0 and stored[k] == v then sim = sim + 1 end
      end
      if sim > 0 then
        matches[#matches + 1] = { sim = sim, success = entry.success or false }
      end
    end
    table.sort(matches, function(a, b) return a.sim > b.sim end)
    local N = math.min(5, #matches)
    local localSum, localCount = 0, 0
    for i = 1, N do
      if matches[i].success then localSum = localSum + 1 end
      localCount = localCount + 1
    end
    if localCount > 0 then
      local localRate = localSum / localCount
      probability = mean * 0.7 + localRate * 0.3
    end
  end
  local explanation = string.format("%s: %.3f from %d observations (unc=%.3f)",
    self.capability, probability, evidence, uncertainty)
  if #self.state.features > 0 then
    local lastFeatures = self.state.features[#self.state.features]
    local featureNames = {}
    for k, _ in pairs(lastFeatures) do featureNames[#featureNames + 1] = k end
    if #featureNames > 0 then
      explanation = explanation .. " [features: " .. table.concat(featureNames, ", ") .. "]"
    end
  end
  return { probability = probability, confidence = confidence, evidence = evidence,
    uncertainty = uncertainty, explanation = explanation }
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
  self._pendingQueue = {}
  self._pendingHead = 1
  self._pendingTail = 0
  self.checkpoint = nil
  return true
end

function Model:reset()
  self.state = { successes = 1, failures = 1, samples = 0, evaluations = 0, correct = 0, features = {} }
  self._pendingQueue = {}
  self._pendingHead = 1
  self._pendingTail = 0
  self.checkpoint = nil
  return true
end

function Model:rollback()
  if not self.checkpoint then return false end
  self.state, self.checkpoint = self.checkpoint, nil
  self._pendingQueue = {}
  self._pendingHead = 1
  self._pendingTail = 0
  return true
end

function Model:diagnostics()
  return { name = self.name, capability = self.capability, samples = self.state.samples,
    pending = math.max(0, self._pendingTail - self._pendingHead + 1), confidence = self:predict().confidence,
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
  s.predictions = copyArray(self.state.predictions) or {}
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
  self._pendingTail = self._pendingTail + 1
  self._pendingQueue[self._pendingTail] = { success = success, weight = weight, prediction = prediction }
  if self._pendingTail - self._pendingHead + 1 > self.maxPending then
    self._pendingHead = self._pendingHead + 1
  end
  return true
end
function Ensemble:update()
  if self._pendingHead > self._pendingTail then return false end
  self.checkpoint = copyState(self.state)
  for i = self._pendingHead, self._pendingTail do
    local obs = self._pendingQueue[i]
    if obs.success then self.state.successes = self.state.successes + obs.weight
    else self.state.failures = self.state.failures + obs.weight end
    self.state.samples = self.state.samples + 1
    if not self.state.predictions then self.state.predictions = {} end
    self.state.predictions[#self.state.predictions + 1] = obs.prediction
    if #self.state.predictions > 100 then table.remove(self.state.predictions, 1) end
  end
  self._pendingHead = 1
  self._pendingTail = 0
  return true
end
function Ensemble:predict()
  local total = self.state.successes + self.state.failures
  local probability = total > 0 and (self.state.successes / total) or 0.5
  local evidence = self.state.samples
  local alpha = self.state.successes + 1
  local beta = self.state.failures + 1
  local uncertainty = math.sqrt((alpha * beta) / ((alpha + beta)^2 * (alpha + beta + 1)))
  local confidence = 1 - uncertainty
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
    uncertainty = uncertainty,
    explanation = string.format("%s: ensemble_avg=%.3f base=%.3f from %d observations, %d recent predictions (unc=%.3f)",
      self.capability, ensembleAverage, probability, evidence, #recentPredictions, uncertainty) }
end

local MLAdapter = {}
MLAdapter.__index = MLAdapter

local function newMLAdapter(module, name, capability, observeInner)
  local inner = module.new()
  return setmetatable({
    name = name, capability = capability, inner = inner, observeInner = observeInner,
    _samples = 0, _pending = 0, _checkpoint = nil,
    updateIntervalMs = 1000, cpuBudgetMicros = 250, memoryBudgetBytes = 4096,
  }, MLAdapter)
end

function MLAdapter:initialize()
  return self
end

function MLAdapter:observe(observation)
  local success = observation.success
  if success == nil then success = observation.label end
  assert(type(success) == "boolean", "boolean observation label required")
  self.observeInner(self.inner, observation)
  self._samples = self._samples + 1
  self._pending = self._pending + 1
  return true
end

function MLAdapter:update()
  if self._pending == 0 then return false end
  self._checkpoint = self._samples - self._pending
  self._pending = 0
  return true
end

function MLAdapter:predict(features)
  local result = self.inner:predict(features or {})
  local evidence = self.inner:getSampleCount()
  return { probability = result.probability, confidence = result.confidence, evidence = evidence,
    uncertainty = result.uncertainty or (1 - result.confidence),
    explanation = string.format("%s: %.3f from %d observations", self.capability,
      result.probability, evidence) }
end

function MLAdapter:evaluate()
  return true
end

function MLAdapter:serialize()
  return { samples = self._samples }
end

function MLAdapter:deserialize(saved)
  self._samples = saved and saved.samples or 0
  self.inner:reset()
  self._pending = 0
  return true
end

function MLAdapter:rollback()
  if self._checkpoint == nil then return false end
  self._samples = self._checkpoint
  self._checkpoint = nil
  self.inner:reset()
  self._pending = 0
  return true
end

function MLAdapter:reset()
  self.inner:reset()
  self._samples = 0
  self._pending = 0
  self._checkpoint = nil
  return true
end

function MLAdapter:diagnostics()
  return { name = self.name, capability = self.capability, samples = self._samples,
    pending = self._pending, confidence = self:predict().confidence,
    accuracy = nil, memoryBudgetBytes = self.memoryBudgetBytes, cpuBudgetMicros = self.cpuBudgetMicros }
end

local models = {
  TargetValueModel = TargetValue,
  RouteReliabilityModel = RouteReliability,
  ResourceEfficiencyModel = ResourceEfficiency,
  TimingModel = Timing,
  RiskAssessmentModel = RiskAssessment,
  LootOpportunityModel = LootOpportunity,
  EnsembleMetaModel = Ensemble,
  KillCompletionModel = newMLAdapter(KillCompletionModule, "KillCompletionModel", "kill_completion",
    function(m, obs) m:observe(obs.success, obs.features or {}) end),
  TargetSwitchRiskModel = newMLAdapter(TargetSwitchRiskModule, "TargetSwitchRiskModel", "target_switch_risk",
    function(m, obs) m:observe(obs.success, true, obs.features or {}) end),
  LureSuccessModel = newMLAdapter(LureSuccessModule, "LureSuccessModel", "lure_success",
    function(m, obs) m:observe(obs.success, obs.features or {}) end),
  PullSuccessModel = newMLAdapter(PullSuccessModule, "PullSuccessModel", "pull_success",
    function(m, obs) m:observe(obs.success, obs.features or {}) end),
  RepositionTileModel = newMLAdapter(RepositionTileModule, "RepositionTileModel", "reposition_tile",
    function(m, obs) m:observe(obs.success, obs.features or {}) end),
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
