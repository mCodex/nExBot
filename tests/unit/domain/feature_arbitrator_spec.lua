local FeatureArbitrator = dofile("targetbot/domain/feature_arbitrator.lua")
local PRECEDENCE = FeatureArbitrator.PRECEDENCE

describe("FeatureArbitrator", function()
  local arbitrator

  before_each(function()
    arbitrator = FeatureArbitrator.new()
  end)

  it("single intent passes through", function()
    local intents = {
      { source = "CHASE", type = "movement", priority = 45, confidence = 0.8, position = {x=10,y=10,z=7} }
    }
    local result = arbitrator:resolve(intents, {})
    assert.is_not_nil(result.selected)
    assert.equals("CHASE", result.selected.source)
    assert.equals(0, #result.rejected)
  end)

  it("FINISH_KILL overrides LURE (HARD_OVERRIDE)", function()
    local intents = {
      { source = "FINISH_KILL_COMMITMENT", type = "movement", priority = 90, confidence = 0.9, position = {x=5,y=5,z=7} },
      { source = "LURE", type = "movement", priority = 55, confidence = 0.8, position = {x=15,y=15,z=7} },
    }
    local result = arbitrator:resolve(intents, {})
    assert.is_not_nil(result.selected)
    assert.equals("FINISH_KILL_COMMITMENT", result.selected.source)
    assert.is_true(#result.rejected >= 1)
  end)

  it("FINISH_KILL overrides PULL", function()
    local intents = {
      { source = "FINISH_KILL_COMMITMENT", type = "movement", priority = 90, confidence = 0.9, position = {x=5,y=5,z=7} },
      { source = "PULL", type = "movement", priority = 65, confidence = 0.8, position = {x=15,y=15,z=7} },
    }
    local result = arbitrator:resolve(intents, {})
    assert.equals("FINISH_KILL_COMMITMENT", result.selected.source)
  end)

  it("FINISH_KILL overrides ROUTE_ADVANCEMENT", function()
    local intents = {
      { source = "FINISH_KILL_COMMITMENT", type = "movement", priority = 90, confidence = 0.9, position = {x=5,y=5,z=7} },
      { source = "ROUTE_ADVANCEMENT", type = "movement", priority = 30, confidence = 0.8, position = {x=15,y=15,z=7} },
    }
    local result = arbitrator:resolve(intents, {})
    assert.equals("FINISH_KILL_COMMITMENT", result.selected.source)
  end)

  it("commitment blocks lure intent that moves away from target", function()
    local intents = {
      { source = "LURE", type = "movement", priority = 55, confidence = 0.8, position = {x=20,y=20,z=7} },
    }
    local context = {
      hasCommitment = true,
      commitmentTargetId = 123,
      commitmentTargetPosition = {x=5,y=5,z=7},
    }
    local result = arbitrator:resolve(intents, context)
    assert.is_nil(result.selected)
    assert.equals("commitment_violation", result.rejected[1].reason)
  end)

  it("WAVE_AVOIDANCE preempts lower-priority intents", function()
    local intents = {
      { source = "WAVE_AVOIDANCE", type = "movement", priority = 80, confidence = 0.9, position = {x=5,y=5,z=7} },
      { source = "LURE", type = "movement", priority = 55, confidence = 0.8, position = {x=15,y=15,z=7} },
    }
    local result = arbitrator:resolve(intents, {})
    assert.equals("WAVE_AVOIDANCE", result.selected.source)
    local found = false
    for _, r in ipairs(result.rejected) do
      if r.intent.source == "LURE" and r.reason == "preempted" then found = true end
    end
    assert.is_true(found)
  end)

  it("LURE and DYNAMIC_LURE are MUTUALLY_EXCLUSIVE", function()
    local intents = {
      { source = "LURE", type = "movement", priority = 55, confidence = 0.8, position = {x=5,y=5,z=7} },
      { source = "DYNAMIC_LURE", type = "movement", priority = 60, confidence = 0.7, position = {x=15,y=15,z=7} },
    }
    local result = arbitrator:resolve(intents, {})
    assert.equals("DYNAMIC_LURE", result.selected.source)
    local found = false
    for _, r in ipairs(result.rejected) do
      if r.intent.source == "LURE" and r.reason == "mutually_exclusive" then found = true end
    end
    assert.is_true(found)
  end)

  it("CHASE and KEEP_DISTANCE are MUTUALLY_EXCLUSIVE", function()
    local intents = {
      { source = "CHASE", type = "movement", priority = 45, confidence = 0.8, position = {x=5,y=5,z=7} },
      { source = "KEEP_DISTANCE", type = "movement", priority = 50, confidence = 0.7, position = {x=15,y=15,z=7} },
    }
    local result = arbitrator:resolve(intents, {})
    assert.equals("KEEP_DISTANCE", result.selected.source)
    local found = false
    for _, r in ipairs(result.rejected) do
      if r.intent.source == "CHASE" and r.reason == "mutually_exclusive" then found = true end
    end
    assert.is_true(found)
  end)

  it("manual override beats everything", function()
    local intents = {
      { source = "MANUAL_OVERRIDE", type = "movement", priority = 95, confidence = 1.0, position = {x=5,y=5,z=7} },
      { source = "FINISH_KILL_COMMITMENT", type = "movement", priority = 90, confidence = 0.9, position = {x=10,y=10,z=7} },
      { source = "WAVE_AVOIDANCE", type = "movement", priority = 80, confidence = 0.8, position = {x=15,y=15,z=7} },
    }
    local context = { isManualOverride = true }
    local result = arbitrator:resolve(intents, context)
    assert.equals("MANUAL_OVERRIDE", result.selected.source)
    assert.equals(2, #result.rejected)
  end)

  it("low player HP adds safety filter", function()
    local intents = {
      { source = "HARD_SAFETY", type = "movement", priority = 100, confidence = 0.9, position = {x=5,y=5,z=7} },
      { source = "LURE", type = "movement", priority = 55, confidence = 0.8, position = {x=15,y=15,z=7} },
    }
    local context = { playerHpPercent = 10 }
    local result = arbitrator:resolve(intents, context)
    assert.equals("HARD_SAFETY", result.selected.source)
    local found = false
    for _, r in ipairs(result.rejected) do
      if r.intent.source == "LURE" and r.reason == "safety_filter" then found = true end
    end
    assert.is_true(found)
  end)

  it("ML_TIE_BREAKER only decides between equal intents", function()
    local intents = {
      { source = "CHASE", type = "movement", priority = 45, confidence = 0.7, position = {x=5,y=5,z=7} },
      { source = "CHASE", type = "movement", priority = 45, confidence = 0.7, position = {x=10,y=10,z=7} },
      { source = "ML_TIE_BREAKER", type = "movement", priority = 10, confidence = 0.5, position = {x=5,y=5,z=7} },
    }
    local result = arbitrator:resolve(intents, {})
    assert.is_not_nil(result.selected)
    assert.equals("CHASE", result.selected.source)
  end)

  it("returns rejected intents with reasons", function()
    local intents = {
      { source = "FINISH_KILL_COMMITMENT", type = "movement", priority = 90, confidence = 0.9, position = {x=5,y=5,z=7} },
      { source = "LURE", type = "movement", priority = 55, confidence = 0.8, position = {x=15,y=15,z=7} },
      { source = "PULL", type = "movement", priority = 65, confidence = 0.7, position = {x=20,y=20,z=7} },
    }
    local result = arbitrator:resolve(intents, {})
    assert.equals("FINISH_KILL_COMMITMENT", result.selected.source)
    assert.is_true(#result.rejected >= 2)
    for _, r in ipairs(result.rejected) do
      assert.is_not_nil(r.intent)
      assert.is_not_nil(r.reason)
    end
  end)
end)
