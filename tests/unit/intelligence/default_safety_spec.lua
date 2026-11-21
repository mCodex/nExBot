local Safety = dofile("core/intelligence/decisions/default_safety.lua")

describe("intelligence default hard safety", function()
  local envelope = Safety.new()

  it("rejects unsafe health, low confidence, invalid targets, and floor changes", function()
    assert.same({ false, "health_below_hard_limit" }, { envelope:validate({ minHealthRatio = 0.3 }, { healthRatio = 0.2 }) })
    assert.same({ false, "confidence_below_threshold" }, { envelope:validate({ confidence = 0.2, minConfidence = 0.5 }, {}) })
    assert.same({ false, "invalid_target" }, { envelope:validate({ action = "attack" }, { targetValid = false }) })
    assert.same({ false, "invalid_movement_floor" }, { envelope:validate({ action = "move", position = { z = 8 } }, { playerPosition = { z = 7 } }) })
  end)

  it("accepts a deterministic valid action", function()
    assert.is_true(envelope:validate({ action = "attack", confidence = 1 }, { healthRatio = 1, targetValid = true }))
  end)
end)
