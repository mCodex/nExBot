local Monitor = dofile("core/intelligence/guardrails/rollback_monitor.lua")

describe("intelligence rollback monitor", function()
  it("constructs with default thresholds", function()
    local m = Monitor.new()
    assert.equals(0.1, m.thresholds.safetyEventRate)
    assert.equals(0.05, m.thresholds.nearDeathRate)
    assert.equals(0.01, m.thresholds.deathRate)
    assert.equals(0.3, m.thresholds.targetSwitchRate)
    assert.equals(0.2, m.thresholds.pathFailureRate)
    assert.equals(30, m.thresholds.stuckDuration)
    assert.equals(0.5, m.thresholds.lootCaptureRate)
    assert.equals(2.0, m.thresholds.resourceConsumption)
    assert.equals(0.1, m.thresholds.manualInterventionRate)
    assert.equals(0.01, m.thresholds.modelExceptionRate)
    assert.equals(500, m.thresholds.latencyMs)
  end)

  it("constructs with custom thresholds", function()
    local m = Monitor.new({ deathRate = 0.05, latencyMs = 1000 })
    assert.equals(0.05, m.thresholds.deathRate)
    assert.equals(1000, m.thresholds.latencyMs)
    assert.equals(0.1, m.thresholds.safetyEventRate)
  end)

  it("check returns false when no thresholds breached", function()
    local m = Monitor.new()
    assert.is_false(m:check({
      safetyEventRate = 0.05,
      nearDeathRate = 0.02,
      deathRate = 0.005,
      targetSwitchRate = 0.1,
      pathFailureRate = 0.1,
      stuckDuration = 10,
      lootCaptureRate = 0.8,
      resourceConsumption = 1.0,
      manualInterventionRate = 0.05,
      modelExceptionRate = 0.005,
      latencyMs = 200,
    }))
  end)

  it("check returns true when safetyEventRate breached", function()
    local m = Monitor.new()
    assert.is_true(m:check({ safetyEventRate = 0.15 }))
  end)

  it("check returns true when nearDeathRate breached", function()
    local m = Monitor.new()
    assert.is_true(m:check({ nearDeathRate = 0.1 }))
  end)

  it("check returns true when deathRate breached", function()
    local m = Monitor.new()
    assert.is_true(m:check({ deathRate = 0.02 }))
  end)

  it("check returns true when targetSwitchRate breached", function()
    local m = Monitor.new()
    assert.is_true(m:check({ targetSwitchRate = 0.4 }))
  end)

  it("check returns true when pathFailureRate breached", function()
    local m = Monitor.new()
    assert.is_true(m:check({ pathFailureRate = 0.3 }))
  end)

  it("check returns true when stuckDuration breached", function()
    local m = Monitor.new()
    assert.is_true(m:check({ stuckDuration = 60 }))
  end)

  it("check returns true when lootCaptureRate below threshold", function()
    local m = Monitor.new()
    assert.is_true(m:check({ lootCaptureRate = 0.3 }))
  end)

  it("check returns true when resourceConsumption breached", function()
    local m = Monitor.new()
    assert.is_true(m:check({ resourceConsumption = 3.0 }))
  end)

  it("check returns true when manualInterventionRate breached", function()
    local m = Monitor.new()
    assert.is_true(m:check({ manualInterventionRate = 0.2 }))
  end)

  it("check returns true when modelExceptionRate breached", function()
    local m = Monitor.new()
    assert.is_true(m:check({ modelExceptionRate = 0.02 }))
  end)

  it("check returns true when latencyMs breached", function()
    local m = Monitor.new()
    assert.is_true(m:check({ latencyMs = 600 }))
  end)

  it("shouldRollback returns false when check returns false", function()
    local m = Monitor.new()
    m:check({ safetyEventRate = 0.05 })
    assert.is_false(m:shouldRollback())
  end)

  it("shouldRollback returns true when check returns true", function()
    local m = Monitor.new()
    m:check({ deathRate = 0.02 })
    assert.is_true(m:shouldRollback())
  end)

  it("getReason returns nil when no breach", function()
    local m = Monitor.new()
    m:check({ safetyEventRate = 0.05 })
    assert.is_nil(m:getReason())
  end)

  it("getReason returns reason string for deathRate breach", function()
    local m = Monitor.new()
    m:check({ deathRate = 0.02 })
    assert.is_truthy(m:getReason())
    assert.is_truthy(string.find(m:getReason(), "death"))
  end)

  it("getReason returns reason string for safetyEventRate breach", function()
    local m = Monitor.new()
    m:check({ safetyEventRate = 0.15 })
    assert.is_truthy(string.find(m:getReason(), "safety"))
  end)

  it("getReason returns reason string for latencyMs breach", function()
    local m = Monitor.new()
    m:check({ latencyMs = 800 })
    assert.is_truthy(string.find(m:getReason(), "latency"))
  end)

  it("only reports first breached threshold", function()
    local m = Monitor.new()
    m:check({ deathRate = 0.02, safetyEventRate = 0.15, latencyMs = 800 })
    local reason = m:getReason()
    assert.is_truthy(reason)
  end)
end)
