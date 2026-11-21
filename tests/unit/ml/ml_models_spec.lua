_G.nExBot = { Shared = { nowMs = function() return 1000 end } }

local ContextualFeatures = dofile("targetbot/ml/contextual_features.lua")
local KillCompletionModel = dofile("targetbot/ml/kill_completion_model.lua")
local TargetSwitchRiskModel = dofile("targetbot/ml/target_switch_risk_model.lua")
local LureSuccessModel = dofile("targetbot/ml/lure_success_model.lua")
local PullSuccessModel = dofile("targetbot/ml/pull_success_model.lua")
local RepositionTileModel = dofile("targetbot/ml/reposition_tile_model.lua")

describe("ML contextual models", function()
  it("ContextualFeatures extracts correct feature vector", function()
    local extractor = ContextualFeatures.new()
    local ctx = {
      targetHp = 0.8, targetId = 123, isCurrentTarget = true,
      distance = 3, hasLOS = true, reachabilityState = 0.7,
      pathCost = 5, monsterCount = 2, playerHpPercent = 0.9,
      activeFeature = 1, recentSwitches = 2, hasCommitment = false,
    }
    local f = extractor:extractCombat(ctx)
    assert.equals(0.8, f.targetHp)
    assert.equals(0.3, f.distance)
    assert.equals(1, f.hasLOS)
    assert.equals(1, f.isCurrentTarget)
    assert.equals(0.7, f.reachabilityConfidence)
    assert.equals(0, f.hasCommitment)
    assert.equals(1, f.activeFeatureId)
    assert.equals(2, f.recentSwitchCount)
  end)

  it("ContextualFeatures hash is deterministic", function()
    local extractor = ContextualFeatures.new()
    local ctx = { targetHp = 0.5, distance = 2, hasLOS = true, isCurrentTarget = false }
    local f1 = extractor:extractCombat(ctx)
    local f2 = extractor:extractCombat(ctx)
    assert.equals(f1.hash, f2.hash)
    assert.is_string(f1.hash)
  end)

  it("KillCompletionModel returns 0.5 with no samples", function()
    local model = KillCompletionModel.new()
    local result = model:predict({ targetHp = 0.5, distance = 0.3 })
    assert.equals(0.5, result.probability)
    assert.equals(0, result.confidence)
    assert.equals(0, result.sampleCount)
  end)

  it("KillCompletionModel prediction changes after observe", function()
    local model = KillCompletionModel.new({ minSamples = 1 })
    local features = { targetHp = 0.5, distance = 0.3 }
    for _ = 1, 10 do model:observe(true, features) end
    local result = model:predict(features)
    assert.is_not.equals(0.5, result.probability)
  end)

  it("KillCompletionModel requires minSamples for reliable prediction", function()
    local model = KillCompletionModel.new({ minSamples = 5 })
    for _ = 1, 3 do model:observe(true, { targetHp = 0.5 }) end
    local result = model:predict({ targetHp = 0.5 })
    assert.equals(0.5, result.probability)
    assert.equals(0, result.confidence)
  end)

  it("TargetSwitchRiskModel returns 1.0 risk when hasCommitment", function()
    local model = TargetSwitchRiskModel.new()
    local result = model:predict({ hasCommitment = 1, currentTargetHp = 0.5 })
    assert.equals(1.0, result.probability)
    assert.equals(1, result.confidence)
  end)

  it("TargetSwitchRiskModel prediction changes with features", function()
    local model = TargetSwitchRiskModel.new({ minSamples = 1 })
    local features = { hasCommitment = 0, currentTargetHp = 0.5, distance = 0.3 }
    for _ = 1, 10 do model:observe(true, true, features) end
    local result = model:predict(features)
    assert.is_not.equals(0.5, result.probability)
  end)

  it("LureSuccessModel returns default with no samples", function()
    local model = LureSuccessModel.new()
    local result = model:predict({ creatureCount = 3, distanceVariance = 0.5 })
    assert.equals(0.5, result.probability)
    assert.equals(0, result.confidence)
  end)

  it("LureSuccessModel learns from observations", function()
    local model = LureSuccessModel.new({ minSamples = 1 })
    local features = { creatureCount = 3, distanceVariance = 0.2, escapeTileCount = 5 }
    for _ = 1, 10 do model:observe(true, features) end
    local result = model:predict(features)
    assert.is_not.equals(0.5, result.probability)
  end)

  it("PullSuccessModel returns default with no samples", function()
    local model = PullSuccessModel.new()
    local result = model:predict({ distance = 5, speedRatio = 1.0 })
    assert.equals(0.5, result.probability)
    assert.equals(0, result.confidence)
  end)

  it("PullSuccessModel prediction changes with distance feature", function()
    local model = PullSuccessModel.new({ minSamples = 1 })
    local features = { distance = 5, speedRatio = 1.0, pathLength = 10 }
    for _ = 1, 10 do model:observe(true, features) end
    local result = model:predict(features)
    assert.is_not.equals(0.5, result.probability)
  end)

  it("RepositionTileModel ranks tiles", function()
    local model = RepositionTileModel.new({ minSamples = 1 })
    local tile1 = { distanceToTarget = 2, losQuality = 0.8, escapeNeighborCount = 3 }
    local tile2 = { distanceToTarget = 5, losQuality = 0.3, escapeNeighborCount = 1 }
    for _ = 1, 10 do model:observe(true, tile1) end
    for _ = 1, 10 do model:observe(false, tile2) end
    local p1 = model:predict(tile1)
    local p2 = model:predict(tile2)
    assert.is_true(p1.probability > p2.probability)
  end)

  it("All models have SHADOW mode by default", function()
    local models = {
      KillCompletionModel.new(),
      TargetSwitchRiskModel.new(),
      LureSuccessModel.new(),
      PullSuccessModel.new(),
      RepositionTileModel.new(),
    }
    for _, m in ipairs(models) do
      assert.equals("SHADOW", m._mode)
    end
  end)

  it("All models support reset", function()
    local models = {
      KillCompletionModel.new({ minSamples = 1 }),
      TargetSwitchRiskModel.new({ minSamples = 1 }),
      LureSuccessModel.new({ minSamples = 1 }),
      PullSuccessModel.new({ minSamples = 1 }),
      RepositionTileModel.new({ minSamples = 1 }),
    }
    for _, m in ipairs(models) do
      if m.observe == TargetSwitchRiskModel.observe then
        m:observe(true, true, { x = 1 })
      else
        m:observe(true, { x = 1 })
      end
      assert.equals(1, m:getSampleCount())
      m:reset()
      assert.equals(0, m:getSampleCount())
    end
  end)

  it("All models bound weights (no extreme values)", function()
    local models = {
      KillCompletionModel.new({ minSamples = 1, learningRate = 1.0 }),
      LureSuccessModel.new({ minSamples = 1, learningRate = 1.0 }),
      PullSuccessModel.new({ minSamples = 1, learningRate = 1.0 }),
      RepositionTileModel.new({ minSamples = 1, learningRate = 1.0 }),
    }
    local extreme = { x = 100 }
    for _, m in ipairs(models) do
      for _ = 1, 100 do m:observe(true, extreme) end
      for _, w in pairs(m._weights) do
        assert.is_true(w <= 10)
        assert.is_true(w >= -10)
      end
    end
  end)
end)
