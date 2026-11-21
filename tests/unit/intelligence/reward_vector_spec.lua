-- tests/unit/intelligence/reward_vector_spec.lua
-- Tests for IntelligenceRewardVector

local mock = require("tests.helpers.mock_otclient")

describe("IntelligenceRewardVector", function()
  local RewardVector
  local defaultComponents = {
    "xpEfficiency", "lootCaptureRate", "lootValueEfficiency", "resourceEfficiency",
    "survivalSafety", "routeReliability", "timeEfficiency",
    "manualInterventionPenalty", "targetThrashPenalty", "stuckPenalty",
    "corpseAbandonmentPenalty", "downtimePenalty", "uncertaintyPenalty",
  }

  before_each(function()
    mock.install()
    RewardVector = dofile("core/intelligence/learning/reward_vector.lua")
  end)

  describe("new()", function()
    it("creates a reward vector with default version", function()
      local rv = RewardVector.new({ componentNames = defaultComponents })
      assert.is_table(rv)
      assert.equals(1, rv.version)
    end)

    it("creates a reward vector with custom version", function()
      local rv = RewardVector.new({ version = 3, componentNames = defaultComponents })
      assert.equals(3, rv.version)
    end)

    it("stores componentNames", function()
      local rv = RewardVector.new({ componentNames = defaultComponents })
      assert.same(defaultComponents, rv.componentNames)
    end)

    it("errors when componentNames is missing", function()
      assert.has_error(function()
        RewardVector.new({})
      end)
    end)
  end)

  describe("create()", function()
    local rv

    before_each(function()
      rv = RewardVector.new({ componentNames = defaultComponents })
    end)

    it("creates a reward vector from components table", function()
      local v = rv:create({
        xpEfficiency = 0.8,
        lootCaptureRate = 0.5,
        lootValueEfficiency = 0.6,
        resourceEfficiency = 0.7,
        survivalSafety = 0.9,
        routeReliability = 0.3,
        timeEfficiency = 0.4,
        manualInterventionPenalty = 0.1,
        targetThrashPenalty = 0.0,
        stuckPenalty = 0.0,
        corpseAbandonmentPenalty = 0.0,
        downtimePenalty = 0.0,
        uncertaintyPenalty = 0.0,
      })
      assert.is_table(v)
      assert.equals(1, v.version)
      assert.is_number(v.timestamp)
      assert.equals(0.8, v.components.xpEfficiency)
      assert.equals(0.5, v.components.lootCaptureRate)
    end)

    it("defaults missing components to 0", function()
      local v = rv:create({ xpEfficiency = 1.0 })
      assert.equals(1.0, v.components.xpEfficiency)
      assert.equals(0, v.components.lootCaptureRate)
      assert.equals(0, v.components.survivalSafety)
    end)

    it("includes version from config", function()
      local rv2 = RewardVector.new({ version = 5, componentNames = defaultComponents })
      local v = rv2:create({ xpEfficiency = 0.5 })
      assert.equals(5, v.version)
    end)
  end)

  describe("add()", function()
    local rv

    before_each(function()
      rv = RewardVector.new({ componentNames = defaultComponents })
    end)

    it("adds two vectors component-wise", function()
      local v1 = rv:create({
        xpEfficiency = 0.3, lootCaptureRate = 0.4, lootValueEfficiency = 0.5,
        resourceEfficiency = 0.1, survivalSafety = 0.2, routeReliability = 0.3,
        timeEfficiency = 0.1, manualInterventionPenalty = 0.1,
        targetThrashPenalty = 0.0, stuckPenalty = 0.0,
        corpseAbandonmentPenalty = 0.0, downtimePenalty = 0.0,
        uncertaintyPenalty = 0.0,
      })
      local v2 = rv:create({
        xpEfficiency = 0.2, lootCaptureRate = 0.1, lootValueEfficiency = 0.3,
        resourceEfficiency = 0.4, survivalSafety = 0.1, routeReliability = 0.2,
        timeEfficiency = 0.1, manualInterventionPenalty = 0.05,
        targetThrashPenalty = 0.0, stuckPenalty = 0.0,
        corpseAbandonmentPenalty = 0.0, downtimePenalty = 0.0,
        uncertaintyPenalty = 0.0,
      })
      local sum = rv:add(v1, v2)
      assert.equals(0.5, sum.components.xpEfficiency)
      assert.equals(0.5, sum.components.lootCaptureRate)
      assert.equals(0.8, sum.components.lootValueEfficiency)
      assert.is_near(0.15, sum.components.manualInterventionPenalty, 1e-10)
    end)

    it("returns a new vector, does not mutate inputs", function()
      local v1 = rv:create({ xpEfficiency = 0.5 })
      local v2 = rv:create({ xpEfficiency = 0.5 })
      rv:add(v1, v2)
      assert.equals(0.5, v1.components.xpEfficiency)
      assert.equals(0.5, v2.components.xpEfficiency)
    end)

    it("carries version from first vector", function()
      local rv2 = RewardVector.new({ version = 2, componentNames = defaultComponents })
      local v1 = rv2:create({ xpEfficiency = 0.1 })
      local v2 = rv2:create({ xpEfficiency = 0.2 })
      local sum = rv:add(v1, v2)
      assert.equals(2, sum.version)
    end)
  end)

  describe("scale()", function()
    local rv

    before_each(function()
      rv = RewardVector.new({ componentNames = defaultComponents })
    end)

    it("scales all components by factor", function()
      local v = rv:create({
        xpEfficiency = 0.5, lootCaptureRate = 0.3, lootValueEfficiency = 0.7,
        resourceEfficiency = 0.2, survivalSafety = 0.4, routeReliability = 0.1,
        timeEfficiency = 0.6, manualInterventionPenalty = 0.1,
        targetThrashPenalty = 0.0, stuckPenalty = 0.0,
        corpseAbandonmentPenalty = 0.0, downtimePenalty = 0.0,
        uncertaintyPenalty = 0.0,
      })
      local scaled = rv:scale(v, 2.0)
      assert.equals(1.0, scaled.components.xpEfficiency)
      assert.equals(0.6, scaled.components.lootCaptureRate)
      assert.equals(1.4, scaled.components.lootValueEfficiency)
    end)

    it("returns a new vector, does not mutate input", function()
      local v = rv:create({ xpEfficiency = 0.5 })
      rv:scale(v, 3.0)
      assert.equals(0.5, v.components.xpEfficiency)
    end)

    it("handles zero factor", function()
      local v = rv:create({ xpEfficiency = 0.9 })
      local scaled = rv:scale(v, 0)
      assert.equals(0, scaled.components.xpEfficiency)
    end)
  end)

  describe("dot()", function()
    local rv

    before_each(function()
      rv = RewardVector.new({ componentNames = defaultComponents })
    end)

    it("computes dot product of two vectors", function()
      local v1 = rv:create({
        xpEfficiency = 1.0, lootCaptureRate = 2.0, lootValueEfficiency = 3.0,
        resourceEfficiency = 0, survivalSafety = 0, routeReliability = 0,
        timeEfficiency = 0, manualInterventionPenalty = 0,
        targetThrashPenalty = 0, stuckPenalty = 0,
        corpseAbandonmentPenalty = 0, downtimePenalty = 0,
        uncertaintyPenalty = 0,
      })
      local v2 = rv:create({
        xpEfficiency = 4.0, lootCaptureRate = 5.0, lootValueEfficiency = 6.0,
        resourceEfficiency = 0, survivalSafety = 0, routeReliability = 0,
        timeEfficiency = 0, manualInterventionPenalty = 0,
        targetThrashPenalty = 0, stuckPenalty = 0,
        corpseAbandonmentPenalty = 0, downtimePenalty = 0,
        uncertaintyPenalty = 0,
      })
      -- 1*4 + 2*5 + 3*6 = 4+10+18 = 32
      assert.equals(32, rv:dot(v1, v2))
    end)

    it("returns 0 for orthogonal vectors", function()
      local v1 = rv:create({ xpEfficiency = 1.0 })
      local v2 = rv:create({ lootCaptureRate = 1.0 })
      assert.equals(0, rv:dot(v1, v2))
    end)

    it("returns 0 for zero vectors", function()
      local v1 = rv:create({})
      local v2 = rv:create({})
      assert.equals(0, rv:dot(v1, v2))
    end)
  end)

  describe("validate()", function()
    local rv

    before_each(function()
      rv = RewardVector.new({ componentNames = defaultComponents })
    end)

    it("returns true for well-formed reward vector", function()
      local v = rv:create({ xpEfficiency = 0.5, survivalSafety = 0.8 })
      assert.is_true(rv:validate(v))
    end)

    it("returns true when all components are 0", function()
      local v = rv:create({})
      assert.is_true(rv:validate(v))
    end)

    it("returns false for nil", function()
      assert.is_false(rv:validate(nil))
    end)

    it("returns false for non-table", function()
      assert.is_false(rv:validate("not a table"))
    end)

    it("returns false when missing version", function()
      local v = { components = { xpEfficiency = 0.5 }, timestamp = os.time() }
      assert.is_false(rv:validate(v))
    end)

    it("returns false when missing components", function()
      local v = { version = 1, timestamp = os.time() }
      assert.is_false(rv:validate(v))
    end)

    it("returns false when component has non-number value", function()
      local v = { version = 1, timestamp = os.time(), components = { xpEfficiency = "bad" } }
      assert.is_false(rv:validate(v))
    end)
  end)
end)
