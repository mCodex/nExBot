local DecisionLog = dofile("core/intelligence/evaluation/decision_log.lua")
local ModelInterfaceV2 = dofile("core/intelligence/learning/model_interface_v2.lua")
local ReplayEvaluator = dofile("core/intelligence/evaluation/replay_evaluator.lua")

local function make_decision(overrides)
  local base = {
    decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
    routeGeneration = 1, decisionType = "target_select",
    candidates = { { id = "a", value = 0.5 }, { id = "b", value = 0.3 } },
    baseline = { selectedCandidateId = "a", value = 0.5 },
    features = { hp = 100 },
  }
  if overrides then
    for k, v in pairs(overrides) do base[k] = v end
  end
  return base
end

describe("IntelligenceReplayEvaluator", function()
  local log, model, evaluator

  before_each(function()
    log = DecisionLog.new({ maxSize = 100 })
    model = ModelInterfaceV2.new({ mode = "ACTIVE" })
    evaluator = ReplayEvaluator.new({ decisionLog = log, modelInterface = model })
  end)

  describe("new", function()
    it("returns an evaluator instance", function()
      assert.is_not_nil(evaluator)
      assert.is_function(evaluator.replay)
      assert.is_function(evaluator.getMetrics)
    end)

    it("sets nExBot.IntelligenceReplayEvaluator", function()
      assert.is_not_nil(nExBot.IntelligenceReplayEvaluator)
    end)
  end)

  describe("replay", function()
    it("replays decisions and returns metrics", function()
      log:log(make_decision())
      local metrics = evaluator:replay()
      assert.is_table(metrics)
      assert.equals(1, metrics.sampleCount)
    end)

    it("computes accuracy matching baseline", function()
      log:log(make_decision({ baseline = { selectedCandidateId = "a", value = 0.5 } }))
      local metrics = evaluator:replay()
      assert.equals(1, metrics.accuracy)
    end)

    it("handles empty logs", function()
      local metrics = evaluator:replay()
      assert.equals(0, metrics.sampleCount)
      assert.equals(0, metrics.accuracy)
      assert.equals(0, metrics.avgAdjustment)
    end)

    it("accepts logs and model override", function()
      local overrideLog = DecisionLog.new({ maxSize = 100 })
      overrideLog:log(make_decision({ decisionId = "d2" }))
      local metrics = evaluator:replay(overrideLog:getLogs({}), model)
      assert.equals(1, metrics.sampleCount)
    end)
  end)

  describe("getMetrics", function()
    it("returns zero metrics when no replay", function()
      local metrics = evaluator:getMetrics()
      assert.equals(0, metrics.sampleCount)
      assert.equals(0, metrics.accuracy)
    end)

    it("returns last replay metrics", function()
      log:log(make_decision())
      evaluator:replay()
      local metrics = evaluator:getMetrics()
      assert.equals(1, metrics.sampleCount)
    end)
  end)
end)
