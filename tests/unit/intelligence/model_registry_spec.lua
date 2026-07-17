local Registry = dofile("core/intelligence/learning/model_registry.lua")
local Models = dofile("core/intelligence/learning/online_models.lua")

describe("intelligence model registry", function()
  local function declaration(overrides)
    local model = Models.beta()
    local value = {
      name = "hit", schemaVersion = 1, featureVersion = 2, model = model,
      minEvidence = 2, minConfidence = 0.6, maxCalibrationError = 0.2,
      maxFalsePositiveRate = 0.1,
      predict = function(current)
        return { probability = current:mean(), confidence = 0.8,
          evidence = current.samples, uncertainty = 0.2, updatedAt = 10 }
      end,
      serialize = function(current)
        return { alpha = current.alpha, beta = current.beta, samples = current.samples }
      end,
      deserialize = function(current, state)
        current.alpha, current.beta, current.samples = state.alpha, state.beta, state.samples
      end,
    }
    for key, item in pairs(overrides or {}) do value[key] = item end
    return value
  end

  it("enforces modes and recommendation evidence", function()
    local registry = Registry.new()
    local entry = registry:declare(declaration())
    assert.equals(Registry.SHADOW, entry.mode)

    entry.model:update(true)
    local shadow = registry:predict("hit")
    assert.is_false(shadow.actionable)
    assert.equals(1, shadow.evidence)

    registry:setMode("hit", Registry.OBSERVE)
    assert.is_nil(registry:predict("hit"))
    registry:setMode("hit", Registry.OFF)
    assert.is_false(registry:observe("hit", true))
  end)

  it("promotes only through bounded gates and rolls back", function()
    local registry = Registry.new()
    registry:declare(declaration())
    local metrics = { evidence = 10, confidence = 0.8, calibrationError = 0.1,
      falsePositiveRate = 0.05, budgetOk = true, safetyRegressions = 0,
      xpRegression = 0, pathFailureRegression = 0, targetThrashingRegression = 0 }

    assert.is_true(registry:promote("hit", metrics))
    assert.equals(Registry.ACTIVE, registry:get("hit").mode)
    assert.is_true(registry:predict("hit").actionable)
    assert.is_true(registry:rollback("hit", "regression"))
    assert.equals(Registry.SHADOW, registry:get("hit").mode)

    metrics.safetyRegressions = 1
    assert.is_false(registry:promote("hit", metrics))
  end)

  it("restores only matching persistence versions", function()
    local registry = Registry.new()
    local entry = registry:declare(declaration())
    entry.model:update(true)
    local saved = registry:serialize("hit")

    entry.model:update(false)
    assert.is_true(registry:restore("hit", saved))
    assert.equals(1, entry.model.samples)
    saved.featureVersion = 3
    assert.is_false(registry:restore("hit", saved))
    assert.equals(1, entry.model.samples)
  end)
end)
