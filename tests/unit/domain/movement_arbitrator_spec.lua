local FeatureArbitrator = dofile("targetbot/domain/feature_arbitrator.lua")
local MovementArbitrator = dofile("targetbot/application/movement_arbitrator.lua")

describe("MovementArbitrator", function()
  local arbitrator, featureArbitrator, coordinatorCalls

  before_each(function()
    featureArbitrator = FeatureArbitrator.new()
    coordinatorCalls = {}
  end)

  it("passes intents to FeatureArbitrator", function()
    arbitrator = MovementArbitrator.new({ featureArbitrator = featureArbitrator })
    local intents = {
      { source = "CHASE", type = "movement", priority = 45, confidence = 0.8, position = {x=10,y=10,z=7} }
    }
    local ok, reason = arbitrator:tick(intents, {})
    assert.is_true(ok)
    assert.equals("executed", reason)
  end)

  it("returns false when no intents", function()
    arbitrator = MovementArbitrator.new({ featureArbitrator = featureArbitrator })
    local ok, reason = arbitrator:tick({}, {})
    assert.is_false(ok)
    assert.equals("no_intents", reason)
  end)

  it("rejects intents without position", function()
    arbitrator = MovementArbitrator.new({ featureArbitrator = featureArbitrator })
    local intents = {
      { source = "CHASE", type = "movement", priority = 45, confidence = 0.8 }
    }
    local ok, reason = arbitrator:tick(intents, {})
    assert.is_false(ok)
    assert.equals("no_position", reason)
  end)

  it("at most one movement per tick", function()
    arbitrator = MovementArbitrator.new({ featureArbitrator = featureArbitrator })
    local intents = {
      { source = "CHASE", type = "movement", priority = 45, confidence = 0.8, position = {x=5,y=5,z=7} },
      { source = "LURE", type = "movement", priority = 55, confidence = 0.7, position = {x=15,y=15,z=7} },
    }
    local ok, reason = arbitrator:tick(intents, {})
    assert.is_true(ok)
    local decision = arbitrator:getLastDecision()
    assert.is_not_nil(decision.intent)
    assert.is_nil(decision.secondIntent)
  end)

  it("commitment blocks violating movement", function()
    arbitrator = MovementArbitrator.new({ featureArbitrator = featureArbitrator })
    local intents = {
      { source = "LURE", type = "movement", priority = 55, confidence = 0.8, position = {x=20,y=20,z=7} },
    }
    local context = {
      hasCommitment = true,
      commitmentTargetId = 123,
      commitmentTargetPosition = {x=5,y=5,z=7},
    }
    local ok, reason = arbitrator:tick(intents, context)
    assert.is_false(ok)
    assert.equals("no_selected_intent", reason)
  end)

  it("tracks last decision", function()
    arbitrator = MovementArbitrator.new({ featureArbitrator = featureArbitrator })
    assert.is_nil(arbitrator:getLastDecision())
    local intents = {
      { source = "CHASE", type = "movement", priority = 45, confidence = 0.8, position = {x=10,y=10,z=7} }
    }
    arbitrator:tick(intents, {})
    local decision = arbitrator:getLastDecision()
    assert.is_not_nil(decision)
    assert.is_true(decision.success)
    assert.equals("executed", decision.reason)
  end)

  it("delegates to MovementCoordinator when available", function()
    local executed = false
    local coordinator = function(intent)
      executed = true
      assert.equals("CHASE", intent.source)
      return true
    end
    arbitrator = MovementArbitrator.new({
      featureArbitrator = featureArbitrator,
      movementCoordinator = coordinator,
    })
    local intents = {
      { source = "CHASE", type = "movement", priority = 45, confidence = 0.8, position = {x=10,y=10,z=7} }
    }
    local ok = arbitrator:tick(intents, {})
    assert.is_true(ok)
    assert.is_true(executed)
  end)

  it("reset clears state", function()
    arbitrator = MovementArbitrator.new({ featureArbitrator = featureArbitrator })
    local intents = {
      { source = "CHASE", type = "movement", priority = 45, confidence = 0.8, position = {x=10,y=10,z=7} }
    }
    arbitrator:tick(intents, {})
    assert.is_not_nil(arbitrator:getLastDecision())
    arbitrator:reset()
    assert.is_nil(arbitrator:getLastDecision())
  end)
end)
