local DecisionRecord = dofile("core/intelligence/records/decision_record.lua")

describe("IntelligenceDecisionRecord", function()
  local record

  before_each(function()
    record = DecisionRecord.new({ eventFactory = {} })
  end)

  describe("new", function()
    it("returns a record instance", function()
      assert.is_not_nil(record)
      assert.is_function(record.create)
      assert.is_function(record.close)
      assert.is_function(record.validate)
    end)
  end)

  describe("create", function()
    it("creates decision with required fields", function()
      local decision = record:create({
        decisionId = "d1",
        sessionId = "s1",
        huntId = "h1",
        encounterId = "e1",
        routeGeneration = 1,
        decisionType = "target_select",
        candidates = { { candidateId = "c1", action = "attack", configuredPriority = 1, deterministicScore = 0.5, eligible = true } },
        baseline = { selectedCandidateId = "c1", score = 0.5, reason = "highest score" },
      })
      assert.equals("d1", decision.decisionId)
      assert.equals("s1", decision.sessionId)
      assert.equals("h1", decision.huntId)
      assert.equals("e1", decision.encounterId)
      assert.equals(1, decision.routeGeneration)
      assert.equals("target_select", decision.decisionType)
      assert.is_number(decision.createdAt)
      assert.equals("baseline", decision.selectionSource)
      assert.equals(1.0, decision.propensity)
      assert.equals(1, decision.featureSchemaVersion)
      assert.is_table(decision.features)
      assert.is_table(decision.missingMask)
    end)

    it("returns nil for missing decisionId", function()
      local decision = record:create({
        sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      assert.is_nil(decision)
    end)

    it("returns nil for missing sessionId", function()
      local decision = record:create({
        decisionId = "d1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      assert.is_nil(decision)
    end)

    it("returns nil for missing huntId", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      assert.is_nil(decision)
    end)

    it("returns nil for missing encounterId", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      assert.is_nil(decision)
    end)

    it("returns nil for missing routeGeneration", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      assert.is_nil(decision)
    end)

    it("returns nil for missing decisionType", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1,
        candidates = {}, baseline = {},
      })
      assert.is_nil(decision)
    end)

    it("returns nil for invalid decisionType", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "invalid_type",
        candidates = {}, baseline = {},
      })
      assert.is_nil(decision)
    end)

    it("returns nil for missing candidates", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        baseline = {},
      })
      assert.is_nil(decision)
    end)

    it("returns nil for missing baseline", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {},
      })
      assert.is_nil(decision)
    end)

    it("sets default prediction table", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      assert.is_table(decision.prediction)
      assert.equals("", decision.prediction.modelName)
      assert.equals(0, decision.prediction.modelVersion)
      assert.equals(0, decision.prediction.value)
      assert.equals(0, decision.prediction.confidence)
      assert.equals(0, decision.prediction.evidence)
      assert.is_false(decision.prediction.calibrated)
      assert.is_false(decision.prediction.abstained)
      assert.equals(0, decision.prediction.adjustment)
    end)

    it("accepts provided prediction", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
        prediction = { modelName = "m1", modelVersion = 2, value = 0.8, confidence = 0.9 },
      })
      assert.equals("m1", decision.prediction.modelName)
      assert.equals(2, decision.prediction.modelVersion)
      assert.equals(0.8, decision.prediction.value)
      assert.equals(0.9, decision.prediction.confidence)
    end)

    it("sets selectedCandidateId from baseline", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = { selectedCandidateId = "c1", score = 0.5, reason = "test" },
      })
      assert.equals("c1", decision.selectedCandidateId)
    end)

    it("accepts all valid decisionType values", function()
      local types = { "target_select", "target_switch", "movement", "loot", "path_mode" }
      for _, dtype in ipairs(types) do
        local decision = record:create({
          decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
          routeGeneration = 1, decisionType = dtype,
          candidates = {}, baseline = {},
        })
        assert.is_not_nil(decision, "should accept decisionType: " .. dtype)
      end
    end)
  end)

  describe("close", function()
    it("attaches outcome to decision", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      local closed = record:close(decision, { success = true })
      assert.is_true(closed.outcome.success)
      assert.is_number(closed.outcome.closedAt)
    end)

    it("returns nil for nil decision", function()
      local closed = record:close(nil, { success = true })
      assert.is_nil(closed)
    end)

    it("returns nil for nil outcome", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      local closed = record:close(decision, nil)
      assert.is_nil(closed)
    end)
  end)

  describe("validate", function()
    it("returns true for well-formed decision", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      assert.is_true(record:validate(decision))
    end)

    it("rejects non-table", function()
      assert.is_false(record:validate(nil))
      assert.is_false(record:validate("bad"))
    end)

    it("rejects missing decisionId", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      decision.decisionId = nil
      assert.is_false(record:validate(decision))
    end)

    it("rejects missing sessionId", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      decision.sessionId = nil
      assert.is_false(record:validate(decision))
    end)

    it("rejects missing huntId", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      decision.huntId = nil
      assert.is_false(record:validate(decision))
    end)

    it("rejects missing encounterId", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      decision.encounterId = nil
      assert.is_false(record:validate(decision))
    end)

    it("rejects missing createdAt", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      decision.createdAt = nil
      assert.is_false(record:validate(decision))
    end)

    it("rejects invalid decisionType", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      decision.decisionType = "bogus"
      assert.is_false(record:validate(decision))
    end)

    it("rejects missing candidates", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      decision.candidates = nil
      assert.is_false(record:validate(decision))
    end)

    it("rejects missing baseline", function()
      local decision = record:create({
        decisionId = "d1", sessionId = "s1", huntId = "h1", encounterId = "e1",
        routeGeneration = 1, decisionType = "target_select",
        candidates = {}, baseline = {},
      })
      decision.baseline = nil
      assert.is_false(record:validate(decision))
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceDecisionRecord", function()
      assert.is_not_nil(nExBot.IntelligenceDecisionRecord)
    end)
  end)
end)
