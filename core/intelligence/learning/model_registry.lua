IntelligenceModelRegistry = {}
local Registry = IntelligenceModelRegistry

Registry.OFF, Registry.OBSERVE, Registry.SHADOW, Registry.ACTIVE =
  "OFF", "OBSERVE", "SHADOW", "ACTIVE"

local modes = { OFF = true, OBSERVE = true, SHADOW = true, ACTIVE = true }
local required = { "name", "schemaVersion", "featureVersion", "model", "predict",
  "serialize", "deserialize" }

function Registry.new()
  return setmetatable({ entries = {} }, { __index = Registry })
end

function Registry:declare(definition)
  assert(type(definition) == "table", "model declaration required")
  for _, key in ipairs(required) do assert(definition[key] ~= nil, "missing model declaration field: " .. key) end
  assert(not self.entries[definition.name], "model already declared: " .. definition.name)
  assert(type(definition.schemaVersion) == "number" and type(definition.featureVersion) == "number",
    "model versions must be numbers")
  local entry = {
    definition = definition, model = definition.model,
    mode = definition.mode or Registry.SHADOW, lastRollbackReason = nil,
  }
  assert(modes[entry.mode], "invalid model mode")
  self.entries[definition.name] = entry
  return entry
end

function Registry:get(name)
  return assert(self.entries[name], "unknown model: " .. tostring(name))
end

function Registry:setMode(name, mode)
  assert(modes[mode], "invalid model mode")
  self:get(name).mode = mode
end

function Registry:observe(name, ...)
  local entry = self:get(name)
  if entry.mode == Registry.OFF then return false end
  local observe = entry.definition.observe or entry.model.observe or entry.model.update
  if observe then observe(entry.model, ...) end
  return true
end

function Registry:predict(name, ...)
  local entry = self:get(name)
  if entry.mode == Registry.OFF or entry.mode == Registry.OBSERVE then return nil end
  local result = entry.definition.predict(entry.model, ...)
  if result == nil then return nil end
  assert(type(result.probability) == "number" and result.probability >= 0 and result.probability <= 1,
    "model probability must be in [0, 1]")
  assert(type(result.confidence) == "number" and result.confidence >= 0 and result.confidence <= 1,
    "model confidence must be in [0, 1]")
  assert(type(result.evidence) == "number" and result.evidence >= 0, "model evidence must be non-negative")
  result.uncertainty = result.uncertainty or 1 - result.confidence
  result.actionable = entry.mode == Registry.ACTIVE
  result.model = name
  return result
end

function Registry:promote(name, metrics)
  local entry, definition = self:get(name), self:get(name).definition
  metrics = metrics or {}
  local safe = (metrics.evidence or 0) >= (definition.minEvidence or 0)
    and (metrics.confidence or 0) >= (definition.minConfidence or 0)
    and (metrics.calibrationError or math.huge) <= (definition.maxCalibrationError or math.huge)
    and (metrics.falsePositiveRate or math.huge) <= (definition.maxFalsePositiveRate or math.huge)
    and metrics.budgetOk == true
    and (metrics.safetyRegressions or 0) <= 0
    and (metrics.xpRegression or 0) <= 0
    and (metrics.pathFailureRegression or 0) <= 0
    and (metrics.targetThrashingRegression or 0) <= 0
  if safe then entry.mode = Registry.ACTIVE end
  return safe
end

function Registry:rollback(name, reason)
  local entry = self:get(name)
  entry.mode, entry.lastRollbackReason = Registry.SHADOW, reason
  return true
end

function Registry:serialize(name)
  local entry, definition = self:get(name), self:get(name).definition
  return { schemaVersion = definition.schemaVersion, featureVersion = definition.featureVersion,
    state = definition.serialize(entry.model) }
end

function Registry:restore(name, saved)
  local entry, definition = self:get(name), self:get(name).definition
  if type(saved) ~= "table" or saved.schemaVersion ~= definition.schemaVersion
      or saved.featureVersion ~= definition.featureVersion or type(saved.state) ~= "table" then return false end
  definition.deserialize(entry.model, saved.state)
  return true
end

return Registry
