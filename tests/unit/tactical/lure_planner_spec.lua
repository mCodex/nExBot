local now = 1000

_G.nExBot = { Shared = { nowMs = function() return now end } }
_G.ReleaseReason = dofile("targetbot/domain/release_reasons.lua")
_G.ReachabilityState = dofile("targetbot/domain/reachability_states.lua")

describe("LurePlanner", function()
  local LurePlanner

  before_each(function()
    now = 1000
    LurePlanner = dofile("targetbot/tactical/lure_planner.lua")
  end)

  it("produces valid plan with destination and kind=LURE", function()
    local planner = LurePlanner.new()
    local plan = planner:plan({
      creatureCount = 2,
      participantIds = {1, 2},
      targetId = 100,
      targetHp = 80,
      currentPos = {x = 10, y = 20, z = 7},
      hasCommitment = false,
    }, {
      now = 1000,
      config = {lureMin = 3, lureMax = 6, anchorRange = 5},
    })
    assert.is_not_nil(plan)
    assert.equals("LURE", plan.kind)
    assert.equals(100, plan.targetId)
    assert.equals(10, plan.destination.x)
    assert.equals(20, plan.destination.y)
    assert.equals(7, plan.destination.z)
    assert.equals(6, plan.desiredCreatureCount)
  end)

  it("returns nil when creature count >= maxCount", function()
    local planner = LurePlanner.new()
    local plan, reason = planner:plan({
      creatureCount = 6,
      targetId = 100,
      currentPos = {x = 10, y = 20, z = 7},
      hasCommitment = false,
    }, {
      now = 1000,
      config = {lureMin = 3, lureMax = 6},
    })
    assert.is_nil(plan)
    assert.equals("NO_VALID_LURE_PLAN", reason)
  end)

  it("returns nil with LURE_DEFERRED_FINISH_TARGET when hasCommitment", function()
    local planner = LurePlanner.new()
    local plan, reason = planner:plan({
      creatureCount = 2,
      targetId = 100,
      currentPos = {x = 10, y = 20, z = 7},
      hasCommitment = true,
    }, {
      now = 1000,
      config = {lureMin = 3, lureMax = 6},
    })
    assert.is_nil(plan)
    assert.equals("LURE_DEFERRED_FINISH_TARGET", reason)
  end)

  it("checkProgress returns COMPLETED when count reaches desired", function()
    local planner = LurePlanner.new()
    local plan = planner:plan({
      creatureCount = 2,
      targetId = 100,
      currentPos = {x = 10, y = 20, z = 7},
      hasCommitment = false,
    }, {
      now = 1000,
      config = {lureMin = 3, lureMax = 6},
    })
    local status = planner:checkProgress(plan, {creatureCount = 6})
    assert.equals("COMPLETED", status)
  end)

  it("checkProgress returns STALLED after deadline", function()
    local planner = LurePlanner.new()
    local plan = planner:plan({
      creatureCount = 2,
      targetId = 100,
      currentPos = {x = 10, y = 20, z = 7},
      hasCommitment = false,
    }, {
      now = 1000,
      config = {lureMin = 3, lureMax = 6},
    })
    local status = planner:checkProgress(plan, {
      creatureCount = 2,
      now = 10000,
    })
    assert.equals("STALLED", status)
  end)

  it("plan includes attackPolicy KEEP_ATTACKING", function()
    local planner = LurePlanner.new()
    local plan = planner:plan({
      creatureCount = 2,
      targetId = 100,
      currentPos = {x = 10, y = 20, z = 7},
      hasCommitment = false,
    }, {
      now = 1000,
      config = {lureMin = 3, lureMax = 6},
    })
    assert.equals("KEEP_ATTACKING", plan.attackPolicy)
  end)

  it("plan includes abort conditions", function()
    local planner = LurePlanner.new()
    local plan = planner:plan({
      creatureCount = 2,
      targetId = 100,
      currentPos = {x = 10, y = 20, z = 7},
      hasCommitment = false,
    }, {
      now = 1000,
      config = {lureMin = 3, lureMax = 6},
    })
    assert.is_table(plan.abortConditions)
    assert.equals(3, #plan.abortConditions)
    local hasTargetDead = false
    local hasSafetyAbort = false
    for _, cond in ipairs(plan.abortConditions) do
      if cond == "TARGET_DEAD" then hasTargetDead = true end
      if cond == "SAFETY_ABORT" then hasSafetyAbort = true end
    end
    assert.is_true(hasTargetDead)
    assert.is_true(hasSafetyAbort)
  end)

  it("reset clears state", function()
    local planner = LurePlanner.new()
    planner:plan({
      creatureCount = 2,
      targetId = 100,
      currentPos = {x = 10, y = 20, z = 7},
      hasCommitment = false,
    }, {
      now = 1000,
      config = {lureMin = 3, lureMax = 6},
    })
    assert.is_not_nil(planner.currentPlan)
    planner:reset()
    assert.is_nil(planner.currentPlan)
  end)
end)
