local clock = 1000

_G.nExBot = { Shared = { nowMs = function() return clock end } }
_G.ReleaseReason = dofile("targetbot/domain/release_reasons.lua")
_G.ReachabilityState = dofile("targetbot/domain/reachability_states.lua")

describe("DynamicLurePlanner", function()
  local DLP

  before_each(function()
    clock = 1000
    _G.DynamicLurePlanner = nil
    DLP = dofile("targetbot/tactical/dynamic_lure_planner.lua")
  end)

  it("starts in INACTIVE state", function()
    local p = DLP.new()
    assert.equals("INACTIVE", p:getState())
  end)

  it("transitions to GATHERING when creature count < minCount", function()
    local p = DLP.new({ minCount = 3, maxCount = 6, enterDwellMs = 0 })
    clock = 1000
    p:update({ snapshotGeneration = 1, creatures = {10, 20}, minCount = 3, maxCount = 6, safe = true }, { now = 1000 })
    assert.equals("GATHERING", p:getState())
  end)

  it("produces lure proposal during GATHERING", function()
    local p = DLP.new({ minCount = 3, maxCount = 6, enterDwellMs = 0 })
    clock = 1000
    local proposal = p:update(
      { snapshotGeneration = 1, creatures = {10, 20}, minCount = 3, maxCount = 6, safe = true },
      { now = 1000 }
    )
    assert.is_not_nil(proposal)
    assert.equals("movement", proposal.domain)
    assert.equals("lure", proposal.action)
    assert.equals("DynamicLure", proposal.source)
    assert.equals(60, proposal.priority)
    assert.equals(2, proposal.evidence.count)
  end)

  it("transitions to COMPLETED when count >= maxCount for dwell time", function()
    local p = DLP.new({ minCount = 3, maxCount = 4, enterDwellMs = 0, exitDwellMs = 1000 })
    clock = 1000
    p:update({ snapshotGeneration = 1, creatures = {10, 20}, minCount = 3, maxCount = 4, safe = true }, { now = 1000 })
    assert.equals("GATHERING", p:getState())

    clock = 1500
    p:update({ snapshotGeneration = 2, creatures = {10, 20, 30, 40}, minCount = 3, maxCount = 4, safe = true }, { now = 1500 })
    assert.equals("GATHERING", p:getState())

    clock = 2500
    p:update({ snapshotGeneration = 3, creatures = {10, 20, 30, 40}, minCount = 3, maxCount = 4, safe = true }, { now = 2500 })
    assert.equals("COMPLETED", p:getState())
  end)

  it("transitions to ABORTED when unsafe", function()
    local p = DLP.new({ minCount = 3, maxCount = 6, enterDwellMs = 0 })
    clock = 1000
    p:update({ snapshotGeneration = 1, creatures = {10, 20}, minCount = 3, maxCount = 6, safe = true }, { now = 1000 })
    assert.equals("GATHERING", p:getState())

    local result, reason = p:update(
      { snapshotGeneration = 2, creatures = {10, 20}, minCount = 3, maxCount = 6, safe = false },
      { now = 1100 }
    )
    assert.equals("ABORTED", p:getState())
    assert.is_nil(result)
    assert.equals("LURE_ABORTED_UNSAFE", reason)
  end)

  it("returns nil with LURE_DEFERRED_FINISH_TARGET when hasCommitment and targetHp < 30", function()
    local p = DLP.new({ minCount = 3, maxCount = 6, enterDwellMs = 0 })
    clock = 1000
    p:update({ snapshotGeneration = 1, creatures = {10, 20, 30}, minCount = 3, maxCount = 6, safe = true }, { now = 1000 })
    assert.equals("PLANNING", p:getState())

    local result, reason = p:update(
      { snapshotGeneration = 2, creatures = {10, 20}, minCount = 3, maxCount = 6, safe = true, hasCommitment = true, targetHp = 20 },
      { now = 1100 }
    )
    assert.is_nil(result)
    assert.equals("LURE_DEFERRED_FINISH_TARGET", reason)
  end)

  it("tracks participants by ID", function()
    local p = DLP.new({ minCount = 3, maxCount = 6, enterDwellMs = 0 })
    clock = 1000
    p:update({ snapshotGeneration = 1, creatures = {101, 202}, minCount = 3, maxCount = 6, safe = true }, { now = 1000 })
    local ids = p:getParticipants()
    local found = {}
    for _, id in ipairs(ids) do found[id] = true end
    assert.is_true(found[101])
    assert.is_true(found[202])
  end)

  it("detects lost participants (count drops to REPLANNING)", function()
    local p = DLP.new({ minCount = 3, maxCount = 6, enterDwellMs = 500, exitDwellMs = 1000 })
    clock = 1000
    p:update({ snapshotGeneration = 1, creatures = {10, 20}, minCount = 3, maxCount = 6, safe = true }, { now = 1000 })
    assert.equals("GATHERING", p:getState())

    clock = 1100
    p:update({ snapshotGeneration = 2, creatures = {10}, minCount = 3, maxCount = 6, safe = true }, { now = 1100 })
    assert.equals("GATHERING", p:getState())

    clock = 1700
    p:update({ snapshotGeneration = 3, creatures = {10}, minCount = 3, maxCount = 6, safe = true }, { now = 1700 })
    assert.equals("REPLANNING", p:getState())
  end)

  it("entry hysteresis: requires minCount for 500ms before entering GATHERING", function()
    local p = DLP.new({ minCount = 3, maxCount = 6, enterDwellMs = 500 })

    clock = 1000
    p:update({ snapshotGeneration = 1, creatures = {10, 20, 30}, minCount = 3, maxCount = 6, safe = true }, { now = 1000 })
    assert.equals("INACTIVE", p:getState())

    clock = 1200
    p:update({ snapshotGeneration = 2, creatures = {10, 20, 30}, minCount = 3, maxCount = 6, safe = true }, { now = 1200 })
    assert.equals("INACTIVE", p:getState())

    clock = 1500
    p:update({ snapshotGeneration = 3, creatures = {10, 20, 30}, minCount = 3, maxCount = 6, safe = true }, { now = 1500 })
    assert.equals("PLANNING", p:getState())
  end)

  it("reset returns to INACTIVE", function()
    local p = DLP.new({ minCount = 3, maxCount = 6, enterDwellMs = 0 })
    clock = 1000
    p:update({ snapshotGeneration = 1, creatures = {10, 20}, minCount = 3, maxCount = 6, safe = true }, { now = 1000 })
    assert.equals("GATHERING", p:getState())
    p:reset()
    assert.equals("INACTIVE", p:getState())
    assert.equals(0, #p:getParticipants())
  end)
end)
