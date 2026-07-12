local Scheduler = dofile("core/containers/scheduler.lua")

describe("Scheduler", function()
  it("enqueues actions", function()
    local s = Scheduler.new()
    s:enqueue({ type = "open", identity = "a" })
    assert.equals(1, s:getQueueSize())
  end)

  it("processes in FIFO order", function()
    local s = Scheduler.new()
    s:enqueue({ type = "open", identity = "a" })
    s:enqueue({ type = "open", identity = "b" })
    local first = s:processNext()
    assert.equals("a", first.identity)
  end)

  it("respects cooldown", function()
    local s = Scheduler.new()
    s.lastActionTime = os.clock() * 1000
    s.cooldownMs = 200
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
end)
