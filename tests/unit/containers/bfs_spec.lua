-- bfs_spec.lua (updated for v5 BFS with deduplication, retry, generation guards)
local BFS      = dofile("core/containers/bfs.lua")
local Registry = dofile("core/containers/registry.lua")
local StateMachine = dofile("core/containers/state_machine.lua")

local function makeReg() return Registry.new() end
local function makeSM()
  local sm = StateMachine.new()
  return sm
end

describe("BFS", function()
  it("starts with empty queue", function()
    local bfs = BFS.new(makeReg(), makeSM())
    assert.equals(0, bfs:getQueueSize())
    assert.is_false(bfs:isActive())
  end)

  it("enqueues roots", function()
    local bfs = BFS.new(makeReg(), makeSM())
    bfs:start({
      { identity = "root1", rootKind = "MAIN_BACKPACK", itemType = 3003 },
      { identity = "root2", rootKind = "QUIVER",        itemType = 3031 },
    })
    assert.equals(2, bfs:getQueueSize())
  end)

  it("processes first candidate", function()
    local bfs = BFS.new(makeReg(), makeSM())
    bfs:start({ { identity = "a", rootKind = "main", itemType = 3003 } })
    local first = bfs:processNext()
    assert.not_nil(first)
    assert.equals("a", first.identity)
  end)

  it("only one in-flight at a time (processNext returns nil when in-flight)", function()
    local bfs = BFS.new(makeReg(), makeSM())
    bfs:start({
      { identity = "a", rootKind = "main",   itemType = 3003 },
      { identity = "b", rootKind = "quiver", itemType = 3031 },
    })
    local first = bfs:processNext()
    assert.not_nil(first)
    -- Cannot dequeue while in-flight
    local second = bfs:processNext()
    assert.is_nil(second)
  end)

  it("processes siblings sequentially after ack", function()
    local sm  = makeSM()
    local bfs = BFS.new(makeReg(), sm)
    bfs:start({
      { identity = "a", rootKind = "main",   itemType = 3003 },
      { identity = "b", rootKind = "quiver", itemType = 3031 },
    })

    local first = bfs:processNext()
    assert.equals("a", first.identity)

    -- Acknowledge first
    bfs:onContainerOpened({ identity = "a" })

    -- Now second is available
    local second = bfs:processNext()
    assert.not_nil(second)
    assert.equals("b", second.identity)
  end)

  it("discovers children from opened containers", function()
    local bfs = BFS.new(makeReg(), makeSM())
    bfs:start({ { identity = "parent", rootKind = "main", itemType = 3003 } })
    bfs:processNext()
    bfs:onContainerOpened({ identity = "parent" })
    bfs:discoverChildren("parent", {
      { identity = "child1", itemType = 3031, slotIndex = 0 },
      { identity = "child2", itemType = 3031, slotIndex = 1 },
    })
    assert.equals(2, bfs:getQueueSize())
  end)

  it("deduplicates children", function()
    local bfs = BFS.new(makeReg(), makeSM())
    bfs:start({ { identity = "parent", rootKind = "main", itemType = 3003 } })
    bfs:processNext()
    bfs:onContainerOpened({ identity = "parent" })
    bfs:discoverChildren("parent", { { identity = "child1", itemType = 3031 } })
    bfs:discoverChildren("parent", { { identity = "child1", itemType = 3031 } })
    assert.equals(1, bfs:getQueueSize())
  end)

  it("deduplicates same identity from start()", function()
    local bfs = BFS.new(makeReg(), makeSM())
    bfs:start({
      { identity = "dup", rootKind = "main", itemType = 3003 },
    })
    -- Starting again clears state, then re-adds
    bfs:start({
      { identity = "dup", rootKind = "main", itemType = 3003 },
    })
    assert.equals(1, bfs:getQueueSize())
  end)

  it("handles empty root (no children)", function()
    local bfs = BFS.new(makeReg(), makeSM())
    bfs:start({ { identity = "empty", rootKind = "main", itemType = 3003 } })
    local candidate = bfs:processNext()
    assert.equals("empty", candidate.identity)
    bfs:onContainerOpened({ identity = "empty" })
    assert.is_false(bfs:isActive())
  end)

  it("rejects stale generation callbacks", function()
    local sm  = makeSM()
    local bfs = BFS.new(makeReg(), sm)
    bfs:start({ { identity = "a", rootKind = "main", itemType = 3003 } })
    sm:transition(StateMachine.States.CANCELLED)  -- bumps generation
    local result = bfs:processNext()
    assert.is_nil(result)
  end)

  it("retry re-enqueues and increments attempt", function()
    local bfs = BFS.new(makeReg(), makeSM())
    bfs:start({ { identity = "x", rootKind = "main", itemType = 3003 } })
    bfs:processNext()
    bfs:onContainerOpened({ identity = "x" })
    -- Force failure state to test retry
    local reg = bfs.registry
    reg:setState("x", "opening")
    bfs.inFlight = reg:get("x")
    local retried = bfs:retry("x")
    assert.is_true(retried)
    assert.equals(1, bfs:getQueueSize())
  end)

  it("markFailed sets state and clears inFlight", function()
    local bfs = BFS.new(makeReg(), makeSM())
    bfs:start({ { identity = "y", rootKind = "main", itemType = 3003 } })
    bfs:processNext()  -- sets inFlight to "y"
    bfs:markFailed("y")
    assert.is_nil(bfs.inFlight)
    local node = bfs.registry:get("y")
    assert.equals("failed", node.state)
  end)

  it("onPageReceived marks node as indexing", function()
    local bfs = BFS.new(makeReg(), makeSM())
    bfs:start({ { identity = "p", rootKind = "main", itemType = 3003 } })
    bfs:processNext()
    bfs:onContainerOpened({ identity = "p" })
    local result = bfs:onPageReceived({ identity = "p", pageIndex = 0, items = {} })
    assert.not_nil(result)
    assert.equals("indexing", bfs.registry:get("p").state)
  end)

  it("onInspectionComplete marks node as inspected", function()
    local bfs = BFS.new(makeReg(), makeSM())
    bfs:start({ { identity = "q", rootKind = "main", itemType = 3003 } })
    bfs:processNext()
    bfs:onContainerOpened({ identity = "q" })
    local ok = bfs:onInspectionComplete("q")
    assert.is_true(ok)
    assert.equals("inspected", bfs.registry:get("q").state)
  end)

  it("MAX_RETRIES: after 3 retries markFailed is set", function()
    local bfs = BFS.new(makeReg(), makeSM())
    bfs:start({ { identity = "z", rootKind = "main", itemType = 3003 } })
    bfs:processNext()
    local node = bfs.registry:get("z")
    node.attempt = 3  -- force max retries
    bfs.inFlight = node
    local retried = bfs:retry("z")
    assert.is_false(retried)
    assert.equals("failed", node.state)
  end)
end)
