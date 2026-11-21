-- tests/unit/navigation/obstacles_spec.lua
-- ObstacleResolver (T6): inline door/tool resolution on action edges,
-- strict replan invalidation, missing-item and unknown-capability fail-closed.

local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local Session = require("navigation.session")
local Obstacles = require("navigation.obstacles")
local Obs = require("navigation.observability")
local D = require("navigation.domain")

describe("ObstacleResolver", function()
  local world, player, port, session, obstacles
  local A = { x = 10, y = 10, z = 7 }
  local doorPos = { x = 12, y = 10, z = 7 }

  local function makeSession(edge)
    obstacles = Obstacles.new(port)
    session = Session.new(port, { obstacles = obstacles })
    session:setRoute({ id = "r1", edges = { edge } })
    session:selectEdge(1)
    return session
  end

  before_each(function()
    world = Fake.newWorld()
    world:freespaceRect(5, 5, 16, 15, 7)
    player = Fake.newPlayer(world, A)
    port = AdapterFake.create(world, player)
    Obs.resetMetrics()
  end)

  local function doorEdge()
    return { id = "e1", kind = D.EDGE_KIND.DOOR, toNode = "n1",
             toPos = doorPos, actionPos = doorPos }
  end

  it("resolves a closed door with the required item and invalidates for replan", function()
    makeSession(doorEdge())
    world:setDoor(doorPos, { closed = true })
    player:addItem("door_key", 1)

    local handled = obstacles.handleFailure(session, D.FAILURE.STATIC_TOPOLOGY_BLOCK, A)
    assert.is_true(handled)
    assert.equals("OPEN_DOOR", obstacles.snapshot().lastResolved.effect)
    -- Session must strictly replan, never pass permissively.
    assert.equals(nil, session.edgePath)
  end)

  it("does NOT resolve when the item is missing (fail-closed to retry)", function()
    makeSession(doorEdge())
    world:setDoor(doorPos, { closed = true })

    local handled = obstacles.handleFailure(session, D.FAILURE.STATIC_TOPOLOGY_BLOCK, A)
    assert.is_false(handled)
    assert.equals(1, Obs.snapshot().missingToolCount)
  end)

  it("does NOT resolve non-action edges or transient failures", function()
    makeSession({ id = "e1", kind = D.EDGE_KIND.WALK, toNode = "n1", toPos = doorPos })
    local handled = obstacles.handleFailure(session, D.FAILURE.NO_POSITION_ACK, A)
    assert.is_false(handled)
    assert.is_nil(obstacles.snapshot().lastResolved)
  end)

  it("does NOT resolve when the action port is missing (unknown capability)", function()
    obstacles = Obstacles.new({})   -- no action port
    session = Session.new({}, { obstacles = obstacles })
    session:setRoute({ id = "r1", edges = { doorEdge() } })
    session:selectEdge(1)
    world:setDoor(doorPos, { closed = true })

    local handled = obstacles.handleFailure(session, D.FAILURE.DOOR_REQUIRED, A)
    assert.is_false(handled)
  end)

  it("does NOT resolve an already-clear action tile", function()
    makeSession(doorEdge())   -- door NOT closed
    player:addItem("door_key", 1)
    local handled = obstacles.handleFailure(session, D.FAILURE.DOOR_REQUIRED, A)
    assert.is_false(handled)
  end)

  it("uses useWith for tool edges (machete)", function()
    makeSession({ id = "e1", kind = D.EDGE_KIND.MACHETE, toNode = "n1",
                  toPos = doorPos, actionPos = doorPos })
    world:setWall(doorPos)  -- a static jungle wall
    player:addItem("machete", 1)
    local handled = obstacles.handleFailure(session, D.FAILURE.TOOL_REQUIRED, A)
    assert.is_true(handled)
    assert.equals("CUT_JUNGLE", obstacles.snapshot().lastResolved.effect)
  end)
end)