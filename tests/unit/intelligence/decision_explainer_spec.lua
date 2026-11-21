local function loadModule()
  _G.nExBot = _G.nExBot or {}
  _G.nExBot.IntelligenceDecisionExplainer = nil
  return dofile("core/intelligence/observability/decision_explainer.lua")
end

describe("Intelligence Decision Explainer", function()
  it("explains a full decision with all fields", function()
    local Explainer = loadModule()
    local explainer = Explainer.new()

    local decision = {
      baseline = { selectedCandidateId = "wolf_a", score = 0.72 },
      selectedCandidateId = "wolf_b",
      prediction = {
        adjustment = 0.15,
        confidence = 0.85,
        evidence = 42,
        modelVersion = 3,
      },
      factors = {
        { name = "distance", weight = 0.4 },
        { name = "health", weight = 0.3 },
      },
      guardrails = { "adjustment_bounds" },
      pricesKnown = true,
    }

    local explanation = explainer:explain(decision)

    assert.equals("wolf_a", explanation.baseline.choice)
    assert.equals(0.72, explanation.baseline.score)
    assert.equals("wolf_b", explanation.selected)
    assert.equals(0.15, explanation.adjustment)
    assert.equals(0.85, explanation.confidence)
    assert.equals(42, explanation.evidence)
    assert.same({ "distance", "health" }, explanation.factors)
    assert.same({ "adjustment_bounds" }, explanation.guardrails)
    assert.is_true(explanation.pricesKnown)
    assert.equals(3, explanation.modelVersion)
  end)

  it("formats explanation as readable string", function()
    local Explainer = loadModule()
    local explainer = Explainer.new()

    local explanation = {
      baseline = { choice = "wolf_a", score = 0.72 },
      selected = "wolf_b",
      adjustment = 0.15,
      confidence = 0.85,
      evidence = 42,
      factors = { "distance", "health" },
      guardrails = { "adjustment_bounds" },
      pricesKnown = true,
      modelVersion = 3,
    }

    local str = explainer:format(explanation)

    assert.is_string(str)
    assert.matches("wolf_a", str)
    assert.matches("wolf_b", str)
    assert.matches("0.85", str)
    assert.matches("adjustment_bounds", str)
  end)

  it("handles missing fields gracefully", function()
    local Explainer = loadModule()
    local explainer = Explainer.new()

    local explanation = explainer:explain({})

    assert.is_table(explanation.baseline)
    assert.equals(nil, explanation.selected)
    assert.equals(0, explanation.adjustment)
    assert.equals(0, explanation.confidence)
    assert.same({}, explanation.factors)
    assert.same({}, explanation.guardrails)
    assert.is_false(explanation.pricesKnown)
  end)

  it("format handles minimal explanation", function()
    local Explainer = loadModule()
    local explainer = Explainer.new()

    local str = explainer:format({
      baseline = { choice = nil, score = 0 },
      selected = nil,
      adjustment = 0,
      confidence = 0,
      evidence = 0,
      factors = {},
      guardrails = {},
      pricesKnown = false,
      modelVersion = 0,
    })

    assert.is_string(str)
    assert.matches("No decision", str)
  end)
end)
