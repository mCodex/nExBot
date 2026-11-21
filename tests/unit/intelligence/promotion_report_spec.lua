local Report = dofile("core/intelligence/evaluation/promotion_report.lua")

describe("intelligence promotion report", function()
  it("constructs with default config", function()
    local r = Report.new()
    assert.equals(100, r.config.minEpisodes)
    assert.equals(10, r.config.minHunts)
  end)

  it("constructs with custom config", function()
    local r = Report.new({ minEpisodes = 50, minHunts = 5 })
    assert.equals(50, r.config.minEpisodes)
    assert.equals(5, r.config.minHunts)
  end)

  it("generates a report with all gates", function()
    local r = Report.new()
    local model = { name = "TestModel", mode = "SHADOW" }
    local metrics = {
      episodes = 150, hunts = 20, observationDays = 14,
      featureCoverage = 0.95, calibrationError = 0.03, predictionError = 0.1,
      replayStable = true, safetyRegression = false, deathRegression = false,
      pathFailureRegression = false, targetThrashRegression = false,
      lootCaptureRegression = false, resourceEfficiencyRegression = false,
      manualInterventionRegression = false, performanceBudgetOk = true,
      persistenceValid = true, confidenceIntervalOk = true
    }
    local report = r:generate(model, metrics)
    assert.is_truthy(report)
    assert.is_truthy(report.gates)
    assert.equals(17, #report.gates)
    assert.is_truthy(report.passed)
  end)

  it("returns canPromote true when all gates pass", function()
    local r = Report.new()
    local model = { name = "TestModel", mode = "SHADOW" }
    local metrics = {
      episodes = 150, hunts = 20, observationDays = 14,
      featureCoverage = 0.95, calibrationError = 0.03, predictionError = 0.1,
      replayStable = true, safetyRegression = false, deathRegression = false,
      pathFailureRegression = false, targetThrashRegression = false,
      lootCaptureRegression = false, resourceEfficiencyRegression = false,
      manualInterventionRegression = false, performanceBudgetOk = true,
      persistenceValid = true, confidenceIntervalOk = true
    }
    local report = r:generate(model, metrics)
    assert.is_true(r:canPromote(report))
  end)

  it("returns canPromote false when a gate fails", function()
    local r = Report.new()
    local model = { name = "TestModel", mode = "SHADOW" }
    local metrics = {
      episodes = 10, hunts = 20, observationDays = 14,
      featureCoverage = 0.95, calibrationError = 0.03, predictionError = 0.1,
      replayStable = true, safetyRegression = false, deathRegression = false,
      pathFailureRegression = false, targetThrashRegression = false,
      lootCaptureRegression = false, resourceEfficiencyRegression = false,
      manualInterventionRegression = false, performanceBudgetOk = true,
      persistenceValid = true, confidenceIntervalOk = true
    }
    local report = r:generate(model, metrics)
    assert.is_false(r:canPromote(report))
  end)

  it("handles insufficient data", function()
    local r = Report.new()
    local model = { name = "TestModel", mode = "SHADOW" }
    local metrics = {}
    local report = r:generate(model, metrics)
    assert.is_false(r:canPromote(report))
    assert.is_truthy(report.gates)
    local failedCount = 0
    for _, gate in ipairs(report.gates) do
      if not gate.passed then failedCount = failedCount + 1 end
    end
    assert.is_true(failedCount > 0)
  end)
end)
