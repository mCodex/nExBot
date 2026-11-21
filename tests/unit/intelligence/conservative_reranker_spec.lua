dofile("core/intelligence/guardrails/adjustment_bounds.lua")
dofile("core/intelligence/learning/model_interface_v2.lua")
dofile("core/intelligence/learning/conservative_reranker.lua")

local Reranker = nExBot.IntelligenceConservativeReranker

describe("IntelligenceConservativeReranker", function()
  local bounds, model

  before_each(function()
    bounds = nExBot.IntelligenceAdjustmentBounds.new({ bounds = { CANARY = 0.02, ACTIVE = 0.10 } })
    model = nExBot.IntelligenceModelInterfaceV2.new({ mode = "CANARY" })
  end)

  describe("new", function()
    it("requires adjustmentBounds in config", function()
      assert.has_error(function()
        Reranker.new({ modelInterface = model })
      end)
    end)

    it("requires modelInterface in config", function()
      assert.has_error(function()
        Reranker.new({ adjustmentBounds = bounds })
      end)
    end)

    it("returns a Reranker instance", function()
      local r = Reranker.new({ adjustmentBounds = bounds, modelInterface = model })
      assert.is_not_nil(r)
      assert.is_function(r.rerank)
      assert.is_function(r.getAdjustment)
    end)
  end)

  describe("rerank", function()
    local r

    before_each(function()
      r = Reranker.new({ adjustmentBounds = bounds, modelInterface = model })
    end)

    it("returns candidates sorted by adjusted score", function()
      local candidates = {
        { id = "a", score = 0.5, tier = 1 },
        { id = "b", score = 0.3, tier = 1 },
        { id = "c", score = 0.7, tier = 1 },
      }
      local result = r:rerank(candidates, { prediction = { probability = 0.6 } }, "CANARY")
      assert.is_table(result)
      assert.equals(3, #result)
    end)

    it("preserves original candidates when mode is OFF", function()
      local candidates = {
        { id = "a", score = 0.5, tier = 1 },
        { id = "b", score = 0.3, tier = 1 },
      }
      local result = r:rerank(candidates, { prediction = { probability = 0.6 } }, "OFF")
      assert.equals("a", result[1].id)
      assert.equals("b", result[2].id)
    end)

    it("applies bounded adjustment within mode limits", function()
      local candidates = {
        { id = "a", score = 0.5, tier = 1 },
        { id = "b", score = 0.5, tier = 1 },
      }
      local result = r:rerank(candidates, { prediction = { probability = 0.9 } }, "CANARY")
      local adjustment = r:getAdjustment()
      assert.is_true(adjustment <= 0.02)
      assert.is_true(adjustment >= -0.02)
      for _, c in ipairs(result) do
        local delta = math.abs(c.score - c.originalScore)
        assert.is_true(delta <= 0.021)
      end
    end)

    it("never crosses configured priority tiers", function()
      local candidates = {
        { id = "a", score = 0.5, tier = 2 },
        { id = "b", score = 0.9, tier = 1 },
      }
      local result = r:rerank(candidates, { prediction = { probability = 0.99 } }, "CANARY")
      assert.equals(1, result[1].tier)
    end)

    it("returns empty table for empty candidates", function()
      local result = r:rerank({}, { prediction = { probability = 0.5 } }, "CANARY")
      assert.same({}, result)
    end)
  end)

  describe("getAdjustment", function()
    it("returns 0 before any rerank", function()
      local r = Reranker.new({ adjustmentBounds = bounds, modelInterface = model })
      assert.equals(0, r:getAdjustment())
    end)

    it("returns last adjustment after rerank", function()
      local r = Reranker.new({ adjustmentBounds = bounds, modelInterface = model })
      local candidates = {
        { id = "a", score = 0.5, tier = 1 },
      }
      r:rerank(candidates, { prediction = { probability = 0.6 } }, "CANARY")
      local adj = r:getAdjustment()
      assert.is_number(adj)
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceConservativeReranker", function()
      assert.is_not_nil(nExBot.IntelligenceConservativeReranker)
    end)
  end)
end)
