dofile("core/intelligence/contracts/outcome_reasons.lua")
local OutcomeRecord = dofile("core/intelligence/records/outcome_record.lua")

describe("IntelligenceOutcomeRecord", function()
  local record

  before_each(function()
    record = OutcomeRecord.new({})
  end)

  describe("new", function()
    it("returns a record instance", function()
      assert.is_not_nil(record)
      assert.is_function(record.create)
      assert.is_function(record.validate)
      assert.is_function(record.measure)
    end)
  end)

  describe("create", function()
    it("creates outcome with required fields", function()
      local outcome = record:create({
        decisionId = "d1",
        actionId = "a1",
        closureReason = "completed",
      })
      assert.equals("d1", outcome.decisionId)
      assert.equals("a1", outcome.actionId)
      assert.equals("completed", outcome.closureReason)
      assert.is_number(outcome.closedAt)
    end)

    it("returns nil for missing decisionId", function()
      local outcome = record:create({
        actionId = "a1",
        closureReason = "completed",
      })
      assert.is_nil(outcome)
    end)

    it("returns nil for missing actionId", function()
      local outcome = record:create({
        decisionId = "d1",
        closureReason = "completed",
      })
      assert.is_nil(outcome)
    end)

    it("returns nil for missing closureReason", function()
      local outcome = record:create({
        decisionId = "d1",
        actionId = "a1",
      })
      assert.is_nil(outcome)
    end)

    it("returns nil for invalid closureReason", function()
      local outcome = record:create({
        decisionId = "d1",
        actionId = "a1",
        closureReason = "invalid_reason",
      })
      assert.is_nil(outcome)
    end)

    it("includes optional success field", function()
      local outcome = record:create({
        decisionId = "d1",
        actionId = "a1",
        closureReason = "target_killed",
        success = true,
      })
      assert.is_true(outcome.success)
    end)

    it("allows nil success (tri-state)", function()
      local outcome = record:create({
        decisionId = "d1",
        actionId = "a1",
        closureReason = "timeout",
      })
      assert.is_nil(outcome.success)
    end)

    it("sets default measurements table", function()
      local outcome = record:create({
        decisionId = "d1",
        actionId = "a1",
        closureReason = "completed",
      })
      assert.is_table(outcome.measurements)
      assert.equals(0, outcome.measurements.elapsedMs)
      assert.equals(0, outcome.measurements.progressTiles)
      assert.equals(0, outcome.measurements.targetHpDelta)
      assert.equals(0, outcome.measurements.damageTaken)
      assert.equals(0, outcome.measurements.resourceCost)
      assert.equals(0, outcome.measurements.xpDelta)
      assert.equals(0, outcome.measurements.lootValueConfidence)
      assert.is_false(outcome.measurements.manualIntervention)
    end)

    it("accepts provided measurements", function()
      local outcome = record:create({
        decisionId = "d1",
        actionId = "a1",
        closureReason = "completed",
        measurements = { elapsedMs = 500 },
      })
      assert.equals(500, outcome.measurements.elapsedMs)
      assert.equals(0, outcome.measurements.progressTiles)
    end)
  end)

  describe("validate", function()
    it("returns true for well-formed outcome", function()
      local outcome = record:create({
        decisionId = "d1",
        actionId = "a1",
        closureReason = "completed",
      })
      assert.is_true(record:validate(outcome))
    end)

    it("rejects non-table", function()
      assert.is_false(record:validate(nil))
      assert.is_false(record:validate("bad"))
    end)

    it("rejects missing decisionId", function()
      assert.is_false(record:validate({
        actionId = "a1",
        closureReason = "completed",
        closedAt = os.time(),
        measurements = {},
      }))
    end)

    it("rejects missing actionId", function()
      assert.is_false(record:validate({
        decisionId = "d1",
        closureReason = "completed",
        closedAt = os.time(),
        measurements = {},
      }))
    end)

    it("rejects invalid closureReason", function()
      assert.is_false(record:validate({
        decisionId = "d1",
        actionId = "a1",
        closureReason = "bananas",
        closedAt = os.time(),
        measurements = {},
      }))
    end)

    it("rejects missing closedAt", function()
      assert.is_false(record:validate({
        decisionId = "d1",
        actionId = "a1",
        closureReason = "completed",
        measurements = {},
      }))
    end)
  end)

  describe("measure", function()
    it("adds measurement to outcome", function()
      local outcome = record:create({
        decisionId = "d1",
        actionId = "a1",
        closureReason = "completed",
      })
      local updated = record:measure(outcome, "elapsedMs", 1234)
      assert.equals(1234, updated.measurements.elapsedMs)
    end)

    it("rejects unknown measurement key", function()
      local outcome = record:create({
        decisionId = "d1",
        actionId = "a1",
        closureReason = "completed",
      })
      local updated = record:measure(outcome, "fakeField", 42)
      assert.is_nil(updated)
      assert.equals(0, outcome.measurements.elapsedMs)
    end)

    it("returns the updated outcome", function()
      local outcome = record:create({
        decisionId = "d1",
        actionId = "a1",
        closureReason = "completed",
      })
      local updated = record:measure(outcome, "damageTaken", 50)
      assert.equals(50, updated.measurements.damageTaken)
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceOutcomeRecord", function()
      assert.is_not_nil(nExBot.IntelligenceOutcomeRecord)
    end)
  end)
end)
