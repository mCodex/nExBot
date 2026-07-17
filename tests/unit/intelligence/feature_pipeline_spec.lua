local function loadModule()
  _G.IntelligenceFeaturePipeline = nil
  return dofile("core/intelligence/foundation/feature_pipeline.lua")
end

describe("Intelligence Feature Pipeline", function()
  it("returns deterministic versioned combat features bounded to zero and one", function()
    local pipeline = loadModule().new({ maxDistance = 10, maxCreatures = 10,
      maxDps = 200, maxBurst = 500, maxPathLength = 50, maxPotions = 10,
      maxXpRate = 1000000 })
    local snapshot = {
      player = { healthRatio = 0.8, manaRatio = 0.5 },
      creatures = { {}, {}, {} },
      creaturesById = { [7] = { healthPercent = 25, distance = 15 } },
    }
    local context = { targetId = 7, meleeCount = 2, rangedCount = 1,
      waveCount = 99, estimatedIncomingDps = 100, estimatedBurst = -2,
      lureSize = 4, routeCongestion = 0.3, pathLength = 25,
      recentPotionUsage = 5, xpRate = 500000, latencyClass = 2,
      observationQuality = 1.2 }

    local first = pipeline:extractCombat(snapshot, context)
    local second = pipeline:extractCombat(snapshot, context)

    assert.equals(1, first.version)
    assert.same(first, second)
    assert.same({
      0.8, 0.5, 0.25, 1, 0.3, 0.2, 0.1, 1, 0.5, 0, 0.4, 0.3,
      0.5, 0.5, 0.5, 2 / 3, 1,
    }, first.values)
    assert.equals(#first.names, #first.values)
  end)

  it("uses safe zero defaults when observations are missing", function()
    local features = loadModule().new():extractCombat({}, {})
    assert.equals(17, #features.values)
    for _, value in ipairs(features.values) do
      assert.is_true(value >= 0 and value <= 1)
    end
  end)
end)
