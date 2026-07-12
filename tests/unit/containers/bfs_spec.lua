local BFS = dofile("core/containers/bfs.lua")
local Registry = dofile("core/containers/registry.lua")
local StateMachine = dofile("core/containers/state_machine.lua")

describe("BFS", function()
  it("starts with empty queue", function()
    local reg = Registry.new()
    local sm = StateMachine.new()
    local bfs = BFS.new(reg, sm)
    assert.equals(0, bfs:getQueueSize())
    assert.is_false(bfs:isActive())
  end)

  it("enqueues roots in priority order", function()
    local reg = Registry.new()
    local sm = StateMachine.new()
    local bfs = BFS.new(reg, sm)
    bfs:start({
      { identity = "root1", rootKind = "mainBackpack", itemType = 3003 },
      { identity = "root2", rootKind = "quiver", itemType = 3031 },
    })
    assert.equals(2, bfs:getQueueSize())
  end)

  it("maintains BFS order", function()
    local reg = Registry.new()
    local sm = StateMachine.new()
    local bfs = BFS.new(reg, sm)
    bfs:start({
      { identity = "a", rootKind = "main", itemType = 3003 },
    })
    local first = bfs:processNext()
    assert.equals("a", first.identity)
  end)

  it("discovers children from opened containers", function()
    local reg = Registry.new()
    local sm = StateMachine.new()
    local bfs = BFS.new(reg, sm)
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
    local reg = Registry.new()
    local sm = StateMachine.new()
    local bfs = BFS.new(reg, sm)
    bfs:start({ { identity = "parent", rootKind = "main", itemType = 3003 } })

    bfs:processNext()
    bfs:onContainerOpened({ identity = "parent" })

    bfs:discoverChildren("parent", {
      { identity = "child1", itemType = 3031, slotIndex = 0 },
    })
    bfs:discoverChildren("parent", {
      { identity = "child1", itemType = 3031, slotIndex = 0 },
    })

    assert.equals(1, bfs:getQueueSize())
  end)

  it("handles empty root", function()
    local reg = Registry.new()
    local sm = StateMachine.new()
    local bfs = BFS.new(reg, sm)
    bfs:start({ { identity = "empty", rootKind = "main", itemType = 3003 } })

    local candidate = bfs:processNext()
    assert.equals("empty", candidate.identity)
    bfs:onContainerOpened({ identity = "empty" })
    assert.is_false(bfs:isActive())
  end)

  it("maintains BFS order for siblings", function()
    local reg = Registry.new()
    local sm = StateMachine.new()
    local bfs = BFS.new(reg, sm)
    bfs:start({
      { identity = "a", rootKind = "main", itemType = 3003 },
      { identity = "b", rootKind = "quiver", itemType = 3031 },
    })

    local first = bfs:processNext()
    assert.equals("a", first.identity)
    local second = bfs:processNext()
    assert.equals("b", second.identity)
  end)

  it("rejects stale generation callbacks", function()
    local reg = Registry.new()
    local sm = StateMachine.new()
    local bfs = BFS.new(reg, sm)
    bfs:start({ { identity = "a", rootKind = "main", itemType = 3003 } })

    sm:transition("cancelled")
    local result = bfs:processNext()
    assert.is_nil(result)
  end)
end)
