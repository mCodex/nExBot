local Registry = IntelligenceModelRegistry or dofile("core/intelligence/learning/model_registry.lua")

IntelligenceModelCatalog = {}
local Catalog = IntelligenceModelCatalog

local definitions = {
  { "MonsterBehaviorModel", "monster_behavior", 24 },
  { "WavePredictionModel", "wave_hit", 30 },
  { "TargetUtilityModel", "target_utility", 30 },
  { "TargetSwitchModel", "target_switch", 30 },
  { "LureSafetyModel", "lure_safety", 40 },
  { "PullContinuationModel", "pull_continuation", 30 },
  { "RouteReliabilityModel", "route_reliability", 20 },
  { "NavigationCostModel", "navigation_cost", 20 },
  { "ResourceEfficiencyModel", "resource_efficiency", 30 },
  { "CombatAreaModel", "combat_area", 30 },
  { "ObservationQualityModel", "observation_quality", 20 },
  { "LatencyModel", "latency", 20 },
}

local Model = {}
Model.__index = Model

local function copyState(state)
  return { successes = state.successes, failures = state.failures, samples = state.samples,
    evaluations = state.evaluations, correct = state.correct }
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
  self.pending[#self.pending + 1] = { success = success,
    weight = math.max(0, math.min(observation.weight or 1, self.maxWeight)) }
  if #self.pending > self.maxPending then table.remove(self.pending, 1) end
  return true
end

function Model:update()
  if #self.pending == 0 then return false end
  self.checkpoint = copyState(self.state)
  for _, observation in ipairs(self.pending) do
    if observation.success then self.state.successes = self.state.successes + observation.weight
    else self.state.failures = self.state.failures + observation.weight end
    self.state.samples = self.state.samples + 1
  end
  self.pending = {}
  return true
end

function Model:predict()
  local total = self.state.successes + self.state.failures
  local probability = total > 0 and (self.state.successes / total) or 0.5
  local evidence = self.state.samples
  local confidence = math.min(1, evidence / self.minSamples)
  return { probability = probability, confidence = confidence, evidence = evidence,
    uncertainty = 1 - confidence,
    explanation = string.format("%s: %.3f from %d observations", self.capability, probability, evidence) }
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
  self.state = { successes = 1, failures = 1, samples = 0, evaluations = 0, correct = 0 }
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

function Catalog.registerAll(registry)
  registry = registry or Registry.new()
  for _, config in ipairs(definitions) do
    local model = create(config[1], config[2], config[3])
    registry:declare({ name = config[1], schemaVersion = 1, featureVersion = 1,
      minEvidence = config[3], minConfidence = 0.6, mode = Registry.SHADOW,
      minimumSamples = config[3], confidenceThreshold = 0.6,
      updateIntervalMs = model.updateIntervalMs, cpuBudgetMicros = model.cpuBudgetMicros,
      memoryBudgetBytes = model.memoryBudgetBytes, model = model,
      observe = Model.observe, predict = Model.predict,
      serialize = Model.serialize, deserialize = Model.deserialize })
  end
  return registry
end

function Catalog.names()
  local names = {}
  for index, config in ipairs(definitions) do names[index] = config[1] end
  return names
end

return Catalog
