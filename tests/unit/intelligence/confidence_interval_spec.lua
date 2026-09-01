dofile("core/intelligence/evaluation/confidence_interval.lua")
local CI = nExBot.IntelligenceConfidenceInterval

describe("IntelligenceConfidenceInterval", function()
  local ci

  before_each(function()
    ci = CI.new()
  end)

  describe("new", function()
    it("returns a CI instance", function()
      assert.is_not_nil(ci)
      assert.is_function(ci.compute)
      assert.is_function(ci.isSignificant)
    end)
  end)

  describe("compute", function()
    it("computes confidence interval for a set of values", function()
      local result = ci:compute({10, 12, 11, 13, 9})
      assert.is_not_nil(result)
      assert.is_number(result.mean)
      assert.is_number(result.lower)
      assert.is_number(result.upper)
      assert.is_number(result.std)
      assert.equals(11, result.mean)
      assert.is_true(result.lower <= result.mean)
      assert.is_true(result.upper >= result.mean)
    end)

    it("defaults confidence to 0.95", function()
      local result = ci:compute({10, 12, 11, 13, 9})
      assert.is_not_nil(result)
      assert.is_true(result.lower < result.mean)
      assert.is_true(result.upper > result.mean)
    end)

    it("accepts custom confidence level", function()
      local result90 = ci:compute({10, 12, 11, 13, 9}, 0.90)
      local result99 = ci:compute({10, 12, 11, 13, 9}, 0.99)
      assert.is_true(result90.upper - result90.lower < result99.upper - result99.lower)
    end)

    it("handles single value", function()
      local result = ci:compute({5})
      assert.equals(5, result.mean)
      assert.equals(0, result.std)
      assert.equals(5, result.lower)
      assert.equals(5, result.upper)
    end)

    it("returns nil for empty values", function()
      local result = ci:compute({})
      assert.is_nil(result)
    end)

    it("returns nil for nil input", function()
      local result = ci:compute(nil)
      assert.is_nil(result)
    end)
  end)

  describe("isSignificant", function()
    it("returns true when intervals do not overlap", function()
      local ci1 = { lower = 1, upper = 3 }
      local ci2 = { lower = 5, upper = 7 }
      assert.is_true(ci:isSignificant(ci1, ci2))
    end)

    it("returns false when intervals overlap", function()
      local ci1 = { lower = 1, upper = 5 }
      local ci2 = { lower = 4, upper = 7 }
      assert.is_false(ci:isSignificant(ci1, ci2))
    end)

    it("returns false when intervals touch at boundary", function()
      local ci1 = { lower = 1, upper = 3 }
      local ci2 = { lower = 3, upper = 5 }
      assert.is_false(ci:isSignificant(ci1, ci2))
    end)

    it("is symmetric", function()
      local ci1 = { lower = 1, upper = 3 }
      local ci2 = { lower = 5, upper = 7 }
      assert.equals(ci:isSignificant(ci1, ci2), ci:isSignificant(ci2, ci1))
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceConfidenceInterval", function()
      assert.is_not_nil(nExBot.IntelligenceConfidenceInterval)
    end)
  end)
end)
