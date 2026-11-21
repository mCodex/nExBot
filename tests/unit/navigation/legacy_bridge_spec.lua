-- tests/unit/navigation/legacy_bridge_spec.lua
-- LegacyBridge (S9 wiring): GoTo -> strict session route, tick driving,
-- focusNode reroute, waypoint route ingestion.

local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local Bridge = require("navigation.legacy_bridge")
local Obs = require("navigation.observability")
local D = require("navigation.domain")

describe("LegacyBridge", function()
  local world, player, port, bridge
  local A = { x = 10, y = 10, z = 7 }
  local B = { x = 12, y = 10, z = 7 }

  before_each(function()
    world = Fake.newWorld()
    world:freespaceRect(5, 5, 16, 15, 7)
    player = Fake.newPlayer(world, A)
    port = AdapterFake.create(world, player, {
      onEvent = function() end,
    })
    bridge = Bridge.new({ port = port, owner = "CAVEBOT" })
    Obs.resetMetrics()
  end)

  it("reroutes GoTo to the strict session route (no permissive flags)", function()
    assert.is_true(bridge:goTo(B, { playerPos = A }))
    local snap = bridge:snapshot()
    assert.equals("e1", snap.session.activeEdgeId)
    assert.equals("n2", bridge._focus)

    local res = bridge:tick(A)
    assert.equals("STEP_DISPATCHED", res.reason)
    assert.is_true(res.commandIssued)
  end)

  it("refuses GoTo across floors (matches legacy behavior)", function()
    assert.is_false(bridge:goTo({ x = 12, y = 10, z = 8 }, { playerPos = A }))
  end)

  it("ingests legacy waypoint strings as a route", function()
    assert.is_true(bridge:routeFromWaypoints({ "10,10,7", "12,10,7", "14,10,7" }))
    local snap = bridge:snapshot()
    assert.equals("route-1", snap.session.routeId)
    assert.equals(3, #bridge.session.route.nodes)
  end)

  it("focuses a route node through the session (recovery entry point)", function()
    bridge:routeFromWaypoints({ "10,10,7", "12,10,7", "14,10,7" })
    local focus = bridge:focusNode("n3")
    assert.equals("FOCUSED", focus)
    assert.equals("n3", bridge._focus)
  end)

  it("registers as movement owner", function()
    assert.is_true(bridge:snapshot().ownsMovement)
    assert.equals("CAVEBOT", port.movement.getOwner())
  end)

  describe("legacy facade (WaypointNavigator replacement)", function()
    local cache
    before_each(function()
      -- ui.list-like goto waypoint cache: {x,y,z,isGoto,child,index}
      cache = {
        { x = 10, y = 10, z = 7, isGoto = true, child = "wp1", index = 1 },
        { x = 12, y = 10, z = 7, isGoto = true, child = "wp2", index = 2 },
        { x = 14, y = 10, z = 7, isGoto = true, child = "wp3", index = 3 },
        { x = 9, y = 9, z = 6, isGoto = true, child = "wp4", index = 4 }, -- other floor
      }
    end)

    it("buildRoute ingests the cache for the given floor", function()
      assert.is_true(bridge.buildRoute(cache, 7))
      assert.is_true(bridge.isRouteBuilt())
      -- floor filter: node 4 (z=6) excluded
      assert.equals(3, #bridge.session.route.nodes)
    end)

    it("getNextWaypoint returns the cache index + pos of the nearest route node", function()
      bridge.buildRoute(cache, 7)
      local idx, pos = bridge.getNextWaypoint({ x = 10, y = 10, z = 7 })
      assert.equals(1, idx)
      assert.equals(10, pos.x)
      assert.equals(7, pos.z)
    end)

    it("checkDrift flags a player far off the route polyline", function()
      bridge.buildRoute(cache, 7)
      -- On the route: no drift.
      local drifted, dist = bridge.checkDrift({ x = 12, y = 10, z = 7 }, 5)
      assert.is_false(drifted)
      -- Far off-route: drifted.
      local d2, dist2 = bridge.checkDrift({ x = 12, y = 4, z = 7 }, 5)
      assert.is_true(d2)
      assert.is_true(dist2 > 5)
    end)

    it("checkCorridor returns outside + recovery index when breached", function()
      bridge.buildRoute(cache, 7)
      local status = bridge.checkCorridor({ x = 12, y = 40, z = 7 })
      assert.equals("outside", status)
      local inside = bridge.checkCorridor({ x = 12, y = 10, z = 7 })
      assert.equals("inside", inside)
    end)

    it("hasPassedWaypoint detects when the player is beyond a node", function()
      bridge.buildRoute(cache, 7)
      local idx = bridge.getNextWaypoint({ x = 11, y = 10, z = 7 })
      assert.is_true(bridge.hasPassedWaypoint({ x = 20, y = 10, z = 7 }, idx, { x = 14, y = 10, z = 7 }))
      assert.is_false(bridge.hasPassedWaypoint({ x = 10, y = 10, z = 7 }, idx, { x = 14, y = 10, z = 7 }))
    end)

    it("getGotoIndices returns the cache indices of route nodes", function()
      bridge.buildRoute(cache, 7)
      local indices = bridge.getGotoIndices()
      assert.same({ 1, 2, 3 }, indices)
    end)

    it("recoverCorridor delegates to the strict session recovery (WP26-safe)", function()
      bridge.buildRoute(cache, 7)
      -- First call anchors; a second identical call is suppressed (no repeat).
      local offRoute = { x = 12, y = 14, z = 7 }
      assert.is_true(bridge.recoverCorridor(offRoute))
      assert.is_false(bridge.recoverCorridor(offRoute))
      local m = Obs.snapshot()
      assert.equals(1, m.identicalUnchangedRecoveryLoopCount)
      assert.equals(0, #player.pending, "recovery never dispatches raw movement")
    end)
  end)
end)