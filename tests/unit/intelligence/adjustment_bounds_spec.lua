dofile("core/intelligence/guardrails/adjustment_bounds.lua")
local Bounds = nExBot.IntelligenceAdjustmentBounds

describe("IntelligenceAdjustmentBounds", function()
  describe("new", function()
    it("requires bounds table in config", function()
      assert.has_error(function() Bounds.new({}) end)
    end)

    it("returns a Bounds instance", function()
      local b = Bounds.new({ bounds = { CANARY = 0.02 } })
      assert.is_not_nil(b)
      assert.is_function(b.clamp)
      assert.is_function(b.getBounds)
    end)
  end)

  describe("clamp", function()
    local b

    before_each(function()
      b = Bounds.new({ bounds = { CANARY = 0.02, ACTIVE = 0.10 } })
    end)

    it("clamps positive value to max", function()
      assert.equals(0.02, b:clamp(0.05, "CANARY"))
    end)

    it("clamps negative value to -max", function()
      assert.equals(-0.02, b:clamp(-0.05, "CANARY"))
    end)

    it("passes through value within bounds", function()
      assert.equals(0.01, b:clamp(0.01, "CANARY"))
    end)

    it("passes through negative value within bounds", function()
      assert.equals(-0.01, b:clamp(-0.01, "CANARY"))
    end)

    it("clamps at active mode bounds", function()
      assert.equals(0.10, b:clamp(0.20, "ACTIVE"))
      assert.equals(-0.10, b:clamp(-0.20, "ACTIVE"))
    end)

    it("returns 0 for unknown mode", function()
      assert.equals(0, b:clamp(0.5, "UNKNOWN"))
    end)
  end)

  describe("getBounds", function()
    local b

    before_each(function()
      b = Bounds.new({ bounds = { CANARY = 0.02, ACTIVE = 0.10 } })
    end)

    it("returns correct bounds for known mode", function()
      assert.same({ min = -0.02, max = 0.02 }, b:getBounds("CANARY"))
    end)

    it("returns correct bounds for active mode", function()
      assert.same({ min = -0.10, max = 0.10 }, b:getBounds("ACTIVE"))
    end)

    it("returns zero bounds for unknown mode", function()
      assert.same({ min = 0, max = 0 }, b:getBounds("UNKNOWN"))
    end)
  end)

  describe("defaults", function()
    it("provides spec section 12.2 defaults", function()
      local b = Bounds.new({ bounds = {} })
      assert.same({ min = 0, max = 0 }, b:getBounds("OFF"))
      assert.same({ min = 0, max = 0 }, b:getBounds("OBSERVE"))
      assert.same({ min = 0, max = 0 }, b:getBounds("SHADOW"))
      assert.same({ min = -0.02, max = 0.02 }, b:getBounds("CANARY"))
      assert.same({ min = -0.05, max = 0.05 }, b:getBounds("ACTIVE_LOW"))
      assert.same({ min = -0.10, max = 0.10 }, b:getBounds("ACTIVE"))
    end)

    it("overrides defaults with custom config", function()
      local b = Bounds.new({ bounds = { CANARY = 0.03 } })
      assert.same({ min = -0.03, max = 0.03 }, b:getBounds("CANARY"))
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceAdjustmentBounds", function()
      assert.is_not_nil(nExBot.IntelligenceAdjustmentBounds)
    end)
  end)
end)
