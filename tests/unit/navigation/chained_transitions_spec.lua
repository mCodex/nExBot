-- tests/unit/navigation/chained_transitions_spec.lua
-- Regression fixture: back-to-back floor transitions (staircases/ladders
-- with no WALK edge between them) deadlocked the session.
--
-- Frost_Dragon_Okolnir.cfg (auto-recorded) is dense with exactly this shape:
-- consecutive `goto` waypoints where each one only changes Z, e.g.
--   goto:32256,31399,7
--   goto:32256,31400,8   <- STAIRS_UP, lands exactly on the next entry tile
--   goto:32256,31399,7   <- STAIRS_DOWN, entry tile == previous landing tile
--
-- Two bugs combined to make this hang forever:
--   1. transitions.begin() was only ever called from _dispatchNext(), gated
--      on there being a walk step left to send. When the player is already
--      standing on a transition edge's entry tile (guaranteed once you land
--      exactly on it from the prior transition), the approach path is
--      zero-length, _dispatchNext returns nil before reaching begin(), and
--      the coordinator never activates -> WAITING_BLOCKER forever.
--   2. Session:onPositionChange routed every Z-changing update straight to
--      handleZChange() and returned, never calling StepExecutor's own
--      Z-branch -- so the command that dispatched the climb was never
--      marked COMPLETED. It sat as StepExecutor.active until its 6s
--      timeout, blocking the *next* transition and raising a spurious
--      failure on every single floor change even when bug 1 didn't apply.

local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local Session = require("navigation.session")
local StepExecutor = require("navigation.step_executor")
local PathPlanner = require("navigation.path_planner")
local RouteGraph = require("navigation.route_graph")
local Recovery = require("navigation.recovery")
local Transitions = require("navigation.transitions")
local Obstacles = require("navigation.obstacles")
local MLShadow = require("navigation.ml_shadow")
local Obs = require("navigation.observability")
local D = require("navigation.domain")

describe("chained floor transitions (WP-Frost fixture)", function()
  local world, player, port, session

  -- Route: N1 -> N2 is STAIRS_UP, N2 -> N3 is STAIRS_DOWN, chained with no
  -- WALK edge between them (N2 is simultaneously edge 1's landing tile AND
  -- edge 2's entry tile) -- exactly the shape Frost_Dragon_Okolnir.cfg
  -- produces for its staircases.
  local N1 = { x = 10, y = 10, z = 7 }
  local N2 = { x = 11, y = 10, z = 8 }
  local N3 = { x = 11, y = 11, z = 7 }

  before_each(function()
    world = Fake.newWorld()
    world:freespaceRect(5, 5, 20, 20, 7)
    world:freespaceRect(5, 5, 20, 20, 8)
    -- Stepping east from N1 climbs onto N2; stepping south from N2 descends
    -- onto N3. The player never has to walk *toward* the entry tile in this
    -- fixture -- they start standing exactly on it, which is what a chained
    -- transition edge looks like after landing from the previous one.
    world:setFloorChange({ x = N1.x + 1, y = N1.y, z = N1.z }, N2.z - N1.z)
    world:setFloorChange({ x = N2.x, y = N2.y + 1, z = N2.z }, N3.z - N2.z)

    player = Fake.newPlayer(world, N1)
    port = AdapterFake.create(world, player, { onEvent = function() end })

    StepExecutor.active = nil
    PathPlanner.cache = nil
    Obs.resetMetrics()

    session = Session.new(port, {
      recovery = Recovery.new(),
      transitions = Transitions.new(),
      obstacles = Obstacles.new(port),
    })
    session.deps.ml = MLShadow.new(session)

    local route = RouteGraph.fromWaypoints({ N1, N2, N3 })
    assert.is_not_nil(route)
    assert.equals(D.EDGE_KIND.STAIRS_UP, route.edges[1].kind)
    assert.equals(D.EDGE_KIND.STAIRS_DOWN, route.edges[2].kind)
    session:setRoute(route)
    session:selectEdge(1)
  end)

  local function tick()
    return session:tick({
      playerPos = player:getPosition(),
      mapGeneration = world:getMapGeneration(),
    })
  end

  -- Standing exactly on a transition edge's entry tile takes two ticks to
  -- actually move: tick 1 hits the zero-length-approach branch and only
  -- calls transitions.begin() (WAITING_Z); tick 2 sees the transition is
  -- active and calls transitions.tick(), which is what actually dispatches
  -- the Z step through StepExecutor. Drive ticks/advances until `predicate`
  -- is satisfied so the test doesn't hard-code that step count.
  local function driveUntil(predicate, maxTicks)
    for _ = 1, (maxTicks or 20) do
      tick()
      player:advance(Fake.STEP_DELAY_MS)
      if predicate() then return true end
    end
    return false
  end

  it("does not deadlock in WAITING_BLOCKER when already standing on a transition's entry tile", function()
    local climbed = driveUntil(function() return player:getPosition().z == 8 end)
    assert.is_true(climbed, "player did not climb the first staircase")

    -- The session must now progress the SECOND (chained) transition edge --
    -- not sit in WAITING_BLOCKER forever.
    local landed = driveUntil(function()
      local pos = player:getPosition()
      return pos.z == 7 and pos.y == 11
    end)

    assert.is_true(landed, "session never completed the second, chained transition")
  end)

  it("clears the in-flight command on Z change instead of leaving it to time out", function()
    local climbed = driveUntil(function() return player:getPosition().z == 8 end)
    assert.is_true(climbed, "player did not climb the first staircase")

    -- Before the fix this stayed populated (state=DISPATCHED) until its
    -- 6-second deadline, blocking every tick with WAITING_ACK in between.
    assert.is_nil(StepExecutor.getActive(),
      "StepExecutor left a stale command after the floor change completed")
  end)
end)
