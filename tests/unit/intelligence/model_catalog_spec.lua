local Registry = dofile("core/intelligence/learning/model_registry.lua")
local Catalog = dofile("core/intelligence/learning/model_catalog.lua")

describe("intelligence required model catalog", function()
  it("registers all capabilities in SHADOW with a bounded lifecycle", function()
    local registry = Catalog.registerAll()
    assert.equals(12, #Catalog.names())

    for _, name in ipairs(Catalog.names()) do
      local entry, model = registry:get(name), registry:get(name).model
      assert.equals(Registry.SHADOW, entry.mode)
      for _, method in ipairs({ "initialize", "observe", "predict", "update", "evaluate",
          "serialize", "deserialize", "reset", "rollback", "diagnostics" }) do
        assert.is_function(model[method], name .. "." .. method)
      end

      model:observe({ success = true, weight = 1 })
      assert.is_true(model:update())
      local prediction = registry:predict(name)
      assert.is_false(prediction.actionable)
      assert.is_truthy(prediction.explanation)
      assert.equals(1, prediction.evidence)
      assert.is_true(model:rollback())
      assert.equals(0, model:diagnostics().samples)

      local saved = registry:serialize(name)
      model:observe({ success = false })
      model:update()
      assert.is_true(registry:restore(name, saved))
      assert.equals(0, model:diagnostics().samples)
      assert.is_true(model:evaluate(true))
      model:reset()
      assert.equals(0, model:diagnostics().pending)
    end
  end)

  it("bounds queued observations", function()
    local model = Catalog.registerAll():get("TimingModel").model
    for _ = 1, 100 do model:observe({ success = true }) end
    assert.equals(64, model:diagnostics().pending)
    model:update()
    assert.equals(64, model:diagnostics().samples)
  end)

  it("extracts contextual features for each model", function()
    local registry = Catalog.registerAll()
    local targetModel = registry:get("TargetValueModel").model
    targetModel:observe({ success = true, target_xp = 50, target_loot = 100, target_difficulty = 3 })
    targetModel:update()
    local pred = registry:predict("TargetValueModel")
    assert.is_truthy(pred.explanation)
    assert.is_truthy(string.find(pred.explanation, "features"))

    local riskModel = registry:get("RiskAssessmentModel").model
    riskModel:observe({ success = true, hp_ratio = 0.3, enemy_count = 5, distance_to_safety = 10 })
    riskModel:update()
    local riskPred = registry:predict("RiskAssessmentModel")
    assert.is_truthy(riskPred.explanation)
  end)

  it("ensemble meta model tracks recent predictions", function()
    local registry = Catalog.registerAll()
    local ensemble = registry:get("EnsembleMetaModel").model
    for i = 1, 5 do
      ensemble:observe({ success = true, prediction = 0.5 + i * 0.05 })
    end
    ensemble:update()
    local pred = registry:predict("EnsembleMetaModel")
    assert.is_truthy(pred.explanation)
    assert.is_truthy(string.find(pred.explanation, "ensemble_avg"))
    assert.is_truthy(string.find(pred.explanation, "5 recent predictions"))
  end)
end)
