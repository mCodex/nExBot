dofile("core/intelligence/learning/model_interface_v2.lua")
local ItemValueProvider = dofile("core/intelligence/learning/item_value_provider.lua")
dofile("core/intelligence/learning/loot_priority.lua")

local Priority = nExBot.IntelligenceLootPriority

describe("IntelligenceLootPriority", function()
  local model, valueProvider

  before_each(function()
    model = nExBot.IntelligenceModelInterfaceV2.new({ mode = "ACTIVE" })
    valueProvider = ItemValueProvider.new({
      valueTable = { ["gold_coin"] = 100, ["magic_sword"] = 500, ["rusty_dagger"] = 5 },
    })
  end)

  describe("new", function()
    it("requires modelInterface in config", function()
      assert.has_error(function()
        Priority.new({ itemValueProvider = valueProvider })
      end)
    end)

    it("requires itemValueProvider in config", function()
      assert.has_error(function()
        Priority.new({ modelInterface = model })
      end)
    end)

    it("returns a LootPriority instance", function()
      local p = Priority.new({ modelInterface = model, itemValueProvider = valueProvider })
      assert.is_not_nil(p)
      assert.is_function(p.prioritize)
      assert.is_function(p.getMetrics)
    end)
  end)

  describe("prioritize", function()
    local p

    before_each(function()
      p = Priority.new({ modelInterface = model, itemValueProvider = valueProvider })
    end)

    it("returns empty table for empty actions", function()
      local result = p:prioritize({}, {})
      assert.same({}, result)
    end)

    it("returns actions reordered by expected value", function()
      local actions = {
        { itemId = "rusty_dagger", containerReady = true, distance = 1 },
        { itemId = "magic_sword", containerReady = true, distance = 1 },
        { itemId = "gold_coin", containerReady = true, distance = 1 },
      }
      local result = p:prioritize(actions, {})
      assert.equals("magic_sword", result[1].itemId)
      assert.equals("gold_coin", result[2].itemId)
      assert.equals("rusty_dagger", result[3].itemId)
    end)

    it("penalizes actions with higher move cost", function()
      local actions = {
        { itemId = "gold_coin", containerReady = true, distance = 1, moveCost = 1 },
        { itemId = "rusty_dagger", containerReady = true, distance = 1, moveCost = 10 },
      }
      local result = p:prioritize(actions, {})
      assert.equals("gold_coin", result[1].itemId)
    end)

    it("penalizes actions with greater distance", function()
      local actions = {
        { itemId = "magic_sword", containerReady = true, distance = 1, moveCost = 1 },
        { itemId = "magic_sword", containerReady = true, distance = 20, moveCost = 1 },
      }
      local result = p:prioritize(actions, {})
      assert.equals(1, result[1].distance)
      assert.equals(20, result[2].distance)
    end)

    it("boosts actions with expiry urgency", function()
      local actions = {
        { itemId = "rusty_dagger", containerReady = true, distance = 1, expiryTurns = 2 },
        { itemId = "rusty_dagger", containerReady = true, distance = 1, expiryTurns = 100 },
      }
      local result = p:prioritize(actions, {})
      assert.equals(2, result[1].expiryTurns)
    end)

    it("filters out actions in unsafe containers", function()
      local actions = {
        { itemId = "magic_sword", containerReady = true, distance = 1, safe = true },
        { itemId = "gold_coin", containerReady = true, distance = 1, safe = false },
      }
      local result = p:prioritize(actions, {})
      assert.equals(1, #result)
      assert.equals("magic_sword", result[1].itemId)
    end)

    it("filters out actions with container not ready", function()
      local actions = {
        { itemId = "magic_sword", containerReady = true, distance = 1 },
        { itemId = "gold_coin", containerReady = false, distance = 1 },
      }
      local result = p:prioritize(actions, {})
      assert.equals(1, #result)
      assert.equals("magic_sword", result[1].itemId)
    end)

    it("returns reordered actions preserving original fields", function()
      local actions = {
        { itemId = "rusty_dagger", containerReady = true, distance = 1, extra = "kept" },
        { itemId = "magic_sword", containerReady = true, distance = 1 },
      }
      local result = p:prioritize(actions, {})
      assert.equals("magic_sword", result[1].itemId)
      assert.is_nil(result[1].extra)
      assert.equals("kept", result[2].extra)
    end)
  end)

  describe("getMetrics", function()
    it("returns zero metrics before any prioritize call", function()
      local p = Priority.new({ modelInterface = model, itemValueProvider = valueProvider })
      local m = p:getMetrics()
      assert.equals(0, m.total)
      assert.equals(0, m.avgValue)
      assert.equals(0, m.avgCost)
    end)

    it("returns correct metrics after prioritize", function()
      local p = Priority.new({ modelInterface = model, itemValueProvider = valueProvider })
      local actions = {
        { itemId = "gold_coin", containerReady = true, distance = 1, moveCost = 5 },
        { itemId = "magic_sword", containerReady = true, distance = 1, moveCost = 10 },
      }
      p:prioritize(actions, {})
      local m = p:getMetrics()
      assert.equals(2, m.total)
      assert.equals(300, m.avgValue)
      assert.equals(7.5, m.avgCost)
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceLootPriority", function()
      assert.is_not_nil(nExBot.IntelligenceLootPriority)
    end)
  end)
end)
