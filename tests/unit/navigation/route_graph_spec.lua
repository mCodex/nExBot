-- tests/unit/navigation/route_graph_spec.lua
-- RouteGraph (T3): legacy waypoint normalization, transition edges from Z
-- deltas, rebuild detection. Recorder: acked-trace -> route graph.

local RouteGraph = require("navigation.route_graph")
local Recorder = require("navigation.recorder")
local D = require("navigation.domain")

describe("RouteGraph", function()
  it("normalizes legacy waypoint strings into nodes + WALK edges", function()
    local route = RouteGraph.fromWaypoints({
      "10,10,7", "12,10,7", "14,10,7",
    })
    assert.is_not_nil(route)
    assert.equals(3, #route.nodes)
    assert.equals(2, #route.edges)
    assert.equals("n2", route.edges[1].toNode)
    assert.equals(D.EDGE_KIND.WALK, route.edges[1].kind)
    assert.equals(7, route.edges[1].entryPos.z)
    assert.equals(7, route.edges[1].toPos.z)
  end)

  it("creates transition edges with expectedFloorDelta on Z changes", function()
    local route = RouteGraph.fromWaypoints({
      "10,10,7", "10,10,8", "12,10,8",
    })
    assert.equals(D.EDGE_KIND.STAIRS_UP, route.edges[1].kind)
    assert.equals(1, route.edges[1].expectedFloorDelta)
    assert.equals(D.EDGE_KIND.WALK, route.edges[2].kind)
    -- downward:
    local down = RouteGraph.fromWaypoints({ "12,10,8", "12,10,7" })
    assert.equals(D.EDGE_KIND.STAIRS_DOWN, down.edges[1].kind)
    assert.equals(-1, down.edges[1].expectedFloorDelta)
  end)

  it("respects a marker suffix (stairs)", function()
    local route = RouteGraph.fromWaypoints({ "10,10,7", "10,10,7,stairs" })
    assert.equals(D.EDGE_KIND.STAIRS_UP, route.edges[1].kind)
  end)

  it("rejects unusable waypoint lists", function()
    assert.is_nil(RouteGraph.fromWaypoints({}))
    assert.is_nil(RouteGraph.fromWaypoints({ "10,10,7" }))
    assert.is_nil(RouteGraph.fromWaypoints({ "nonsense", "10,10,7" }))
  end)

  it("rebuild returns nil when structurally unchanged", function()
    local a = RouteGraph.fromWaypoints({ "10,10,7", "12,10,7" })
    local same = RouteGraph.rebuild(a, { "10,10,7", "12,10,7" })
    assert.is_nil(same)
    local changed = RouteGraph.rebuild(a, { "10,10,7", "13,10,7" })
    assert.is_not_nil(changed)
  end)
end)

describe("Recorder", function()
  local function walkLine(rec, from, dx, dy, steps, z)
    z = z or 7
    local p = { x = from.x, y = from.y, z = z }
    rec:record(p)
    for i = 1, steps do
      p = { x = p.x + dx, y = p.y + dy, z = z }
      rec:record(p)
    end
  end

  it("records anchors on confirmed turns", function()
    local rec = Recorder.new()
    walkLine(rec, { x = 10, y = 10 }, 1, 0, 4)   -- east
    rec:record({ x = 15, y = 11, z = 7 })        -- turn south-east
    rec:record({ x = 16, y = 12, z = 7 })        -- confirm the turn
    local route = rec:route()
    assert.is_not_nil(route)
    assert.is_true(#route.nodes >= 2)
  end)

  it("records an anchor on floor change and flags the transition", function()
    local rec = Recorder.new()
    rec:record({ x = 10, y = 10, z = 7 })
    rec:record({ x = 10, y = 11, z = 7 })
    local route = rec:record({ x = 10, y = 11, z = 8 }, { floorChange = true })
    assert.is_not_nil(route)
    assert.equals(D.EDGE_KIND.STAIRS_UP, route.edges[#route.edges].kind)
  end)

  it("keeps straight-line spacing under maxStraightDist", function()
    local rec = Recorder.new()
    walkLine(rec, { x = 10, y = 10 }, 1, 0, 5)
    assert.is_true(rec:snapshot().waypointCount <= 7)
  end)

  it("resets state", function()
    local rec = Recorder.new()
    walkLine(rec, { x = 10, y = 10 }, 1, 0, 3)
    rec:reset()
    assert.equals(0, rec:snapshot().waypointCount)
    assert.is_nil(rec:route())
  end)
end)