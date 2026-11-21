local ResourceObserver = dofile("core/intelligence/observability/resource_observer.lua")
local LootObserver = dofile("core/intelligence/observability/loot_observer.lua")
local RewardModel = dofile("core/intelligence/learning/reward_model.lua")

local metadata = {
  timestamp = 100,
  latencyClass = 1,
  observationQuality = 0.9,
  confidence = 0.8,
  correlationId = "combat-1",
}

describe("intelligence resource, loot, and reward", function()
  it("keeps bounded resource observations and totals consumption", function()
    local observer = ResourceObserver.new(2)
    assert.is_truthy(observer:observe({ hpPotions = 1, runes = 2 }, metadata))
    observer:observe({ manaPotions = 3 }, metadata)
    observer:observe({ ammunition = 4, hpPotions = -10 }, metadata)

    assert.equals(2, #observer:recent())
    assert.same({ manaPotions = 3, ammunition = 4 }, observer:totals())
  end)

  it("normalizes optional loot sources without assigning economic value", function()
    local observer = LootObserver.new(2)
    local observation = LootObserver.adapt(function(raw)
      return { monsterId = raw.creature, corpseId = raw.container,
        itemsAvailable = raw.available, itemsCaptured = raw.moved,
        items = { { id = 3031, count = raw.coins } } }
    end, { creature = 7, container = 8, available = 4, moved = 3, coins = 20 }, metadata)

    assert.is_truthy(observer:observe(observation))
    observer:observe(LootObserver.adapt(function() return { itemsAvailable = 1, itemsCaptured = 1 } end, {}, metadata))
    observer:observe(LootObserver.adapt(function() return { itemsAvailable = 2, itemsCaptured = 1 } end, {}, metadata))

    assert.equals(2, #observer:recent())
    assert.equals(2 / 3, observer:captureRate())
    assert.is_nil(observation.gpValue)
  end)

  it("rejects incomplete learning metadata", function()
    local observer = ResourceObserver.new()
    local result, err = observer:observe({ hpPotions = 1 }, { timestamp = 1 })
    assert.is_nil(result)
    assert.equals("missing_latencyClass", err)
  end)

  it("calculates a bounded weighted XP/resource/safety reward", function()
    local model = RewardModel.new({ xpWeight = 0.5, resourceWeight = 0.3,
      safetyWeight = 0.2, routeReliabilityWeight = 0 })
    assert.near(0.45, model:calculate({ xp = 0.9, resourceCost = 0.5, safety = 0.75 }), 1e-9)
    assert.equals(0.5, model:calculate({ xp = 2, resourceCost = -1, safety = 0 }))
  end)
end)
