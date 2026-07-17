-- scheduler_spec.lua (updated for v5 Scheduler with priority, ack, backoff)
local Scheduler = dofile("core/containers/scheduler.lua")

describe("Scheduler", function()
  it("enqueues actions", function()
    local s = Scheduler.new()
    s:enqueue({ type = "open", identity = "a" })
    assert.equals(1, s:getQueueSize())
  end)

  it("processes in FIFO order", function()
    local s = Scheduler.new()
    s.cooldownMs = 0
    s:enqueue({ type = "open", identity = "a" })
    s:enqueue({ type = "open", identity = "b" })
    local first = s:processNext()
    assert.not_nil(first)
    assert.equals("a", first.identity)
  end)

  it("respects cooldown", function()
    local s = Scheduler.new()
    s.lastActionTime = os.clock() * 1000
    s.cooldownMs = 200000  -- huge cooldown
    assert.is_false(s:canRun())
  end)

  it("returns nil when empty", function()
    local s = Scheduler.new()
    local result = s:processNext()
    assert.is_nil(result)
  end)

  it("clears queue", function()
    local s = Scheduler.new()
    s:enqueue({ type = "open", identity = "a" })
    s:enqueue({ type = "open", identity = "b" })
    s:clear()
    assert.equals(0, s:getQueueSize())
  end)

  it("sets active action on processNext", function()
    local s = Scheduler.new()
    s.cooldownMs = 0
    s:enqueue({ type = "open", identity = "x", generation = 0 })
    local action = s:processNext()
    assert.not_nil(action)
    assert.not_nil(s.activeAction)
    -- Cannot run again while action is active
    assert.is_false(s:canRun())
  end)

  it("acknowledge clears active action", function()
    local s = Scheduler.new()
    s.cooldownMs = 0
    s:enqueue({ type = "open", identity = "x", generation = 0, correlationId = "x" })
    s:processNext()
    assert.not_nil(s.activeAction)
    assert.is_true(s:acknowledge("x", 100))
    assert.is_nil(s.activeAction)
  end)

  it("rejects stale-generation actions", function()
    local s = Scheduler.new()
    s.cooldownMs = 0
    s.generation = 5
    s:enqueue({ type = "open", identity = "old", generation = 4 })
    local action = s:processNext()
    assert.is_nil(action)
  end)

  it("onExhaustion sets backoff", function()
    local s = Scheduler.new()
    s:onExhaustion(Scheduler.Reason.SERVER_EXHAUSTED)
    assert.is_true(s.backoffUntil > os.clock() * 1000)
    assert.equals(1, s.exhaustionCount)
  end)

  it("setGeneration clears queue and active action", function()
    local s = Scheduler.new()
    s.cooldownMs = 0
    s:enqueue({ type = "open", identity = "a", generation = 0 })
    s:processNext()
    s:setGeneration(2)
    assert.equals(2, s.generation)
    assert.is_nil(s.activeAction)
    assert.equals(0, s:getQueueSize())
  end)

  it("getStatus returns diagnostic snapshot", function()
    local s = Scheduler.new()
    local st = s:getStatus()
    assert.is_number(st.generation)
    assert.is_number(st.queueSize)
    assert.is_number(st.exhaustionCount)
  end)

  it("priority constants are ordered correctly", function()
    assert.is_true(Scheduler.Priority.EMERGENCY_SURVIVAL < Scheduler.Priority.NORMAL_DISCOVERY)
    assert.is_true(Scheduler.Priority.NORMAL_DISCOVERY < Scheduler.Priority.MAINTENANCE)
  end)
end)
