local now = 1000

_G.nExBot = { Shared = { nowMs = function() return now end } }
_G.ReleaseReason = dofile("targetbot/domain/release_reasons.lua")

describe("TargetCommitmentManager", function()
  local TCM

  before_each(function()
    now = 1000
    TCM = dofile("targetbot/domain/target_commitment.lua")
    TCM.reset()
  end)

  it("acquires commitment with correct fields", function()
    local c = TCM.acquire(123, "FINISH_KILL", 75)
    assert.equals(123, c.targetId)
    assert.equals("FINISH_KILL", c.reason)
    assert.equals(1000, c.startedAt)
    assert.equals(75, c.healthAtAcquisition)
    assert.equals(6000, c.minimumHoldUntil)
    assert.equals("DEAD_UNSAFE_MANUAL_OR_CONFIRMED_UNREACHABLE", c.releasePolicy)
    assert.equals(1, c.generation)
  end)

  it("isActive returns true for committed target", function()
    TCM.acquire(123, "FINISH_KILL", 75)
    local active, c = TCM.isActive(123)
    assert.is_true(active)
    assert.equals(123, c.targetId)
  end)

  it("blocksRelease returns false for TARGET_DEAD", function()
    TCM.acquire(123, "FINISH_KILL", 75)
    assert.is_false(TCM.blocksRelease(123, "TARGET_DEAD"))
  end)

  it("blocksRelease returns false for MANUAL_OVERRIDE", function()
    TCM.acquire(123, "FINISH_KILL", 75)
    assert.is_false(TCM.blocksRelease(123, "MANUAL_OVERRIDE"))
  end)

  it("blocksRelease returns false for CONFIRMED_HARD_UNREACHABLE", function()
    TCM.acquire(123, "FINISH_KILL", 75)
    assert.is_false(TCM.blocksRelease(123, "CONFIRMED_HARD_UNREACHABLE"))
  end)

  it("blocksRelease returns false for SAFETY_ABORT", function()
    TCM.acquire(123, "FINISH_KILL", 75)
    assert.is_false(TCM.blocksRelease(123, "SAFETY_ABORT"))
  end)

  it("blocksRelease returns true for non-hard reasons during minimum hold", function()
    TCM.acquire(123, "FINISH_KILL", 75)
    now = 2000
    assert.is_true(TCM.blocksRelease(123, "STRICT_FOLLOW_OVERRIDE"))
  end)

  it("after minimumHoldMs expires, blocksRelease returns false for non-hard reasons", function()
    TCM.acquire(123, "FINISH_KILL", 75)
    now = 7000
    assert.is_false(TCM.blocksRelease(123, "STRICT_FOLLOW_OVERRIDE"))
  end)

  it("generation increments on acquire and release", function()
    assert.equals(0, TCM.getGeneration())
    TCM.acquire(123, "FINISH_KILL", 75)
    assert.equals(1, TCM.getGeneration())
    TCM.release(123, "TARGET_DEAD")
    assert.equals(2, TCM.getGeneration())
  end)

  it("stale generation cannot release newer commitment", function()
    TCM.acquire(100, "FINISH_KILL", 50)
    local gen1 = TCM.getGeneration()
    TCM.release(100, "TARGET_DEAD")
    TCM.acquire(100, "PULL_ANCHOR", 80)
    local ok = TCM.release(100, "TARGET_DEAD", gen1)
    assert.is_false(ok)
  end)

  it("only one commitment active at a time", function()
    TCM.acquire(100, "FINISH_KILL", 50)
    TCM.acquire(200, "PULL_ANCHOR", 80)
    local active1 = TCM.isActive(100)
    assert.is_false(active1)
    local active2, c = TCM.isActive(200)
    assert.is_true(active2)
    assert.equals(200, c.targetId)
    local a = TCM.getActive()
    assert.equals(200, a.targetId)
  end)

  it("reset clears all state", function()
    TCM.acquire(123, "FINISH_KILL", 75)
    TCM.reset()
    assert.is_nil(TCM.getActive())
    assert.is_false(TCM.isActive(123))
  end)
end)
