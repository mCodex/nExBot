-- tests/unit/navigation/session_spec.lua
-- NavigationSession aggregate: ack-only cursor (P0.4/P0.5), edge lifecycle,
-- preemption, retryable failure, focus idempotency, snapshots.

local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local Session = require("navigation.session")
local StepExecutor = require("navigation.step_executor")
local PathPlanner = require("navigation.path_planner")
local Obs = require("navigation.observability")
local D = require("navigation.domain")

describe("NavigationSession", function()
  local world, player, port, events, session
  local A = { x = 10, y = 10, z = 7 }
  local B = { x = 12, y = 10, z = 7 }

  local function makeSession(route)
    session = Session.new(port, {})
    session:setRoute(route)
    session:selectEdge(1)
    return session
  end

  local function tick()
    return session:tick({
      playerPos = player:getPosition(),
      mapGeneration = world:getMapGeneration(),
    })
  end

  before_each(function()
    events = {}
    world = Fake.newWorld()
    world:freespaceRect(5, 5, 16, 15, 7)
    player = Fake.newPlayer(world, A)
    port = AdapterFake.create(world, player, {
      onEvent = function(ev, _) events[#events + 1] = ev end,
    })
    StepExecutor.active = nil
    PathPlanner.cache = nil
    Obs.resetMetrics()
  end)

  local routeWith = function(toPos)
    return { id = "r1", edges = { { id = "e1", kind = D.EDGE_KIND.WALK, toNode = "n1", toPos = toPos } } }
  end

  it("walks a route edge end to end on observed movement only (P0.4)", function()
    makeSession(routeWith(B))

    local r1 = tick()
    assert.equals("STEP_DISPATCHED", r1.reason)
    assert.is_true(r1.commandIssued)
    assert.equals(2, #player.pending)

    player:advance(Fake.STEP_DELAY_MS)
    assert.equals(1, session.cursor)

    player:advance(Fake.STEP_DELAY_MS)
    assert.equals(2, session.cursor)
    assert.equals(B.x, player:getPosition().x)

    local r2 = tick()
    assert.equals("EDGE_COMPLETED", r2.reason)
    assert.is_not_nil(session:getAnchor())
    assert.equals(B.x, session:getAnchor().pos.x)

    local last = events[#events]
    assert.equals("RouteCompleted", last)
  end)

  it("never advances the cursor on isWalking alone (P0.5)", function()
    makeSession(routeWith(B))
    local r1 = tick()
    assert.equals("STEP_DISPATCHED", r1.reason)
    assert.is_true(player:isWalking())

    -- No position change: the session waits for the ack, reports no progress.
    local r2 = tick()
    assert.equals(D.NavStatus.WAITING_ACK, r2.status)
    assert.is_false(r2.commandIssued)
    assert.is_false(r2.observedProgress)
    assert.equals(0, session.cursor)
  end)

  it("fails retryable when no position ack arrives (NO_POSITION_ACK)", function()
    makeSession(routeWith(B))
    tick()
    player:freeze()
    player:advance(7000)
    local r = tick()
    assert.equals(D.NavStatus.FAILED_RETRYABLE, r.status)
    assert.equals(D.FAILURE.NO_POSITION_ACK, r.reason)
    assert.is_number(r.retryAfterMs)
  end)

  it("yields to manual preemption", function()
    makeSession(routeWith(B))
    local r = session:tick({ playerPos = A, preempted = true })
    assert.equals(D.NavStatus.WAITING_BLOCKER, r.status)
    assert.equals(D.FAILURE.MANUAL_PREEMPTED, r.reason)
  end)

  it("waits for the chunk, then replan-state completes from the acked position", function()
    makeSession(routeWith({ x = 14, y = 10, z = 7 }))
    tick()
    assert.equals(4, #player.pending)
    player:advance(Fake.STEP_DELAY_MS)
    assert.equals(1, session.cursor)
    -- The command is still mid-flight; the session waits, it does not replan.
    local r = tick()
    assert.equals(D.NavStatus.WAITING_ACK, r.status)
    player:advance(Fake.STEP_DELAY_MS * 3)
    assert.equals(4, session.cursor)
    local r2 = tick()
    assert.equals("EDGE_COMPLETED", r2.reason)
  end)

  it("focusNode is idempotent (RECOVERY_NO_CHANGE on repeat)", function()
    local s = Session.new(port, {})
    s:setRoute(routeWith(B))
    assert.equals("FOCUSED", s:focusNode("n1"))
    assert.equals(D.REASON.RECOVERY_NO_CHANGE, s:focusNode("n1"))
  end)

  it("snapshot exposes navigation state", function()
    makeSession(routeWith(B))
    tick()
    local snap = session:snapshot()
    assert.equals("e1", snap.activeEdgeId)
    assert.equals(D.EDGE_KIND.WALK, snap.activeEdgeKind)
    assert.is_number(snap.evidenceRevision)
    assert.is_not_nil(snap.state)
  end)

  it("records mandatory zero metrics as zero after a clean walk", function()
    makeSession(routeWith(B))
    tick()
    player:advance(Fake.STEP_DELAY_MS)
    player:advance(Fake.STEP_DELAY_MS)
    tick()
    local m = Obs.snapshot()
    assert.equals(0, m.wallDirectedCommandCount)
    assert.equals(0, m.invalidStepCommandCount)
    assert.equals(0, m.criticalEdgeSkipCount)
    assert.equals(0, m.wrongRouteRecoveryCount)
    assert.equals(0, m.identicalUnchangedRecoveryLoopCount)
    assert.equals(0, m.unexplainedWaypointAdvanceCount)
    assert.equals(0, m.duplicateRecoveryCommandCount)
  end)
end)