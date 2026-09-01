-- tests/unit/navigation/retry_spec.lua
-- Single retry owner: budgets, escalation, fail-safe, progress reset.

local RetryPolicy = require("navigation.retry")
local D = require("navigation.domain")

describe("RetryPolicy", function()
  it("first failure starts at the failure's phase with backoff", function()
    local r = RetryPolicy.new("r1", "e1")
    local d = RetryPolicy.recordFailure(r, D.FAILURE.NO_POSITION_ACK, 0, {})
    assert.equals("RETRY", d.action)
    assert.equals(D.RETRY_PHASE.RETRY_SAME_VALIDATED_STEP, d.phase)
    assert.equals(250, d.retryAfterMs)
    assert.equals(2, d.attemptId)
  end)

  it("exhausting a phase budget escalates", function()
    local r = RetryPolicy.new("r1", "e1")
    local d
    for i = 1, 4 do
      d = RetryPolicy.recordFailure(r, D.FAILURE.TEMPORARY_CREATURE_BLOCK, 0, {})
      assert.equals(D.RETRY_PHASE.WAIT_TEMPORARY_BLOCKER, d.phase)
    end
    d = RetryPolicy.recordFailure(r, D.FAILURE.TEMPORARY_CREATURE_BLOCK, 0, {})
    assert.equals("ESCALATE", d.action)
    assert.equals(D.RETRY_PHASE.RESOLVE_OBSTACLE, d.phase)
  end)

  it("escalating from REJOIN_CURRENT_EDGE returns RECOVER (backtrack anchor)", function()
    local r = RetryPolicy.new("r1", "e1")
    local d
    for i = 1, 3 do
      d = RetryPolicy.recordFailure(r, D.FAILURE.PARTIAL_AUTOWALK, 0, {})
    end
    assert.equals("RECOVER", d.action)
    assert.equals(D.RETRY_PHASE.BACKTRACK_CONFIRMED_ANCHOR, d.phase)
  end)

  it("escalating from ROUTE_EDGE_RECOVERY fails safe", function()
    local r = RetryPolicy.new("r1", "e1")
    local d
    for i = 1, 3 do
      d = RetryPolicy.recordFailure(r, D.FAILURE.STATIC_TOPOLOGY_BLOCK, 0, {})
    end
    assert.equals("FAILED_SAFE", d.action)
    assert.equals(D.RETRY_PHASE.FAILED_SAFE, d.phase)
  end)

  it("terminal failures never retry", function()
    local r = RetryPolicy.new("r1", "e1")
    local d = RetryPolicy.recordFailure(r, D.FAILURE.MISSING_TOOL, 0, {})
    assert.equals("FAILED_SAFE", d.action)
    assert.equals(0, d.retryAfterMs)
  end)

  it("observed progress resets the phase counter", function()
    local r = RetryPolicy.new("r1", "e1")
    RetryPolicy.recordFailure(r, D.FAILURE.NO_POSITION_ACK, 0, {})
    RetryPolicy.recordFailure(r, D.FAILURE.NO_POSITION_ACK, 0, {})
    local d = RetryPolicy.recordFailure(r, D.FAILURE.NO_POSITION_ACK, 0, { hasProgress = true })
    assert.equals("RETRY", d.action)
    assert.equals(D.RETRY_PHASE.RETRY_SAME_VALIDATED_STEP, d.phase)
  end)

  it("onProgress fully resets the retry context", function()
    local r = RetryPolicy.new("r1", "e1")
    RetryPolicy.recordFailure(r, D.FAILURE.NO_POSITION_ACK, 0, {})
    RetryPolicy.onProgress(r)
    -- The next dispatch is a fresh attempt (#1), not a stale counter.
    assert.equals(1, r.attemptId)
    assert.equals(0, r.totalAttempts)
    assert.is_nil(r.lastPhase)
    local d = RetryPolicy.recordFailure(r, D.FAILURE.NO_POSITION_ACK, 0, {})
    assert.equals(2, d.attemptId)
  end)
end)