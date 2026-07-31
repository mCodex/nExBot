local now = 1000

_G.nExBot = { Shared = { nowMs = function() return now end } }
_G.ReleaseReason = dofile("targetbot/domain/release_reasons.lua")
_G.ReachabilityState = dofile("targetbot/domain/reachability_states.lua")

describe("PullPlanner", function()
  local PullPlanner

  before_each(function()
    now = 1000
    PullPlanner = dofile("targetbot/tactical/pull_planner.lua")
  end)

  it("produces valid plan with destination and kind=PULL", function()
    local planner = PullPlanner.new()
    local plan = planner:plan({
      participantId = 200,
      distance = 4,
      targetHp = 80,
      currentPos = {x = 15, y = 25, z = 7},
      safe = true,
    }, {
      now = 1000,
      config = {smartPullRange = 5, exitDistance = 2},
    })
    assert.is_not_nil(plan)
    assert.equals("PULL", plan.kind)
    assert.equals(200, plan.pullTargetId)
    assert.equals(15, plan.destination.x)
    assert.equals(25, plan.destination.y)
    assert.equals(7, plan.destination.z)
  end)

  it("returns nil when too close (distance <= exitDistance)", function()
    local planner = PullPlanner.new()
    local plan, reason = planner:plan({
      participantId = 200,
      distance = 2,
      currentPos = {x = 15, y = 25, z = 7},
      safe = true,
    }, {
      now = 1000,
      config = {smartPullRange = 5, exitDistance = 2},
    })
    assert.is_nil(plan)
    assert.equals("PULL_TOO_CLOSE", reason)
  end)

  it("returns nil when too far (distance > enterDistance)", function()
    local planner = PullPlanner.new()
    local plan, reason = planner:plan({
      participantId = 200,
      distance = 6,
      currentPos = {x = 15, y = 25, z = 7},
      safe = true,
    }, {
      now = 1000,
      config = {smartPullRange = 5, exitDistance = 2},
    })
    assert.is_nil(plan)
    assert.equals("PULL_TOO_FAR", reason)
  end)

  it("returns nil when unsafe", function()
    local planner = PullPlanner.new()
    local plan, reason = planner:plan({
      participantId = 200,
      distance = 4,
      currentPos = {x = 15, y = 25, z = 7},
      safe = false,
    }, {
      now = 1000,
      config = {smartPullRange = 5, exitDistance = 2},
    })
    assert.is_nil(plan)
    assert.equals("UNSAFE_PULL", reason)
  end)

  it("checkProgress returns COMPLETED when distance <= exitDistance", function()
    local planner = PullPlanner.new()
    local plan = planner:plan({
      participantId = 200,
      distance = 4,
      currentPos = {x = 15, y = 25, z = 7},
      safe = true,
    }, {
      now = 1000,
      config = {smartPullRange = 5, exitDistance = 2},
    })
    local status = planner:checkProgress(plan, {
      participantId = 200,
      distance = 2,
    })
    assert.equals("COMPLETED", status)
  end)

  it("checkProgress returns STALLED after deadline", function()
    local planner = PullPlanner.new()
    local plan = planner:plan({
      participantId = 200,
      distance = 4,
      currentPos = {x = 15, y = 25, z = 7},
      safe = true,
    }, {
      now = 1000,
      config = {smartPullRange = 5, exitDistance = 2},
    })
    local status = planner:checkProgress(plan, {
      participantId = 200,
      distance = 4,
      now = 7000,
    })
    assert.equals("STALLED", status)
  end)

  it("plan requires destination", function()
    local planner = PullPlanner.new()
    local plan, reason = planner:plan({
      participantId = 200,
      distance = 4,
      safe = true,
    }, {
      now = 1000,
      config = {smartPullRange = 5, exitDistance = 2},
    })
    assert.is_nil(plan)
    assert.equals("NO_DESTINATION", reason)
  end)

  it("reset clears state", function()
    local planner = PullPlanner.new()
    planner:plan({
      participantId = 200,
      distance = 4,
      currentPos = {x = 15, y = 25, z = 7},
      safe = true,
    }, {
      now = 1000,
      config = {smartPullRange = 5, exitDistance = 2},
    })
    assert.is_not_nil(planner.currentPlan)
    planner:reset()
    assert.is_nil(planner.currentPlan)
  end)
end)
