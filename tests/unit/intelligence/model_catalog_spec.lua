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
    local model = Catalog.registerAll():get("LatencyModel").model
    for _ = 1, 100 do model:observe({ success = true }) end
    assert.equals(64, model:diagnostics().pending)
    model:update()
    assert.equals(64, model:diagnostics().samples)
  end)
end)
