-- tests/unit/navigation/recovery_spec.lua
-- RecoveryPlanner (P0.7/WP26): route-graph targets only, invariant-5
-- suppression, combat episodes, fail-safe on unreachable, no raw GoTo.

local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local Session = require("navigation.session")
local Recovery = require("navigation.recovery")
local Obs = require("navigation.observability")
local D = require("navigation.domain")

describe("RecoveryPlanner", function()
  local world, player, port, session
  local A = { x = 10, y = 10, z = 7 }
  local B = { x = 12, y = 10, z = 7 }
  local C = { x = 14, y = 10, z = 7 }

  local function makeSession(route)
    session = Session.new(port, { recovery = Recovery.new() })
    session:setRoute(route)
    return session
  end

  local function recover()
    return session.deps.recovery:tick(session, {
      playerPos = player:getPosition(),
      nowMs = player:getClock(),
    })
  end

  before_each(function()
    world = Fake.newWorld()
    world:freespaceRect(5, 5, 16, 15, 7)
    player = Fake.newPlayer(world, A)
    port = AdapterFake.create(world, player)
    Obs.resetMetrics()
  end)

  local function routeWithNodes(edges, nodes)
    return { id = "r1", edges = edges, nodes = nodes }
  end

  it("selects the nearest reachable route node as recovery anchor", function()
    makeSession(routeWithNodes(
      { { id = "e1", kind = D.EDGE_KIND.WALK, toNode = "n1", toPos = B },
        { id = "e2", kind = D.EDGE_KIND.WALK, toNode = "n2", toPos = C } },
      { { id = "n1", pos = B }, { id = "n2", pos = C } }))

    session.state = D.SESSION_STATE.RECOVERING
    local res = session:_recoveryTick({ playerPos = player:getPosition(), nowMs = 0 })
    assert.equals("RECOVERY_ANCHOR_SELECTED", res.reason)
    -- Session flips back to the strict, ack-driven edge flow.
    assert.equals(D.SESSION_STATE.EDGE_ACTIVE, session.state)
    -- Recovery dispatches zero movement commands.
    assert.is_not_true(res.commandIssued)
    assert.equals(0, #player.pending)
  end)

  it("never repeats the same anchor without new evidence (invariant 5)", function()
    makeSession(routeWithNodes(
      { { id = "e1", kind = D.EDGE_KIND.WALK, toNode = "n1", toPos = B } },
      { { id = "n1", pos = B } }))

    local r1 = recover()
    assert.equals("RECOVERY_ANCHOR_SELECTED", r1.reason)

    -- Same evidence: suppressed -> fail safe, no duplicate dispatch.
    session.state = D.SESSION_STATE.RECOVERING
    local r2 = recover()
    assert.equals("RECOVERY_TARGET_DUPLICATE_SUPPRESSED", r2.reason)
    assert.equals(D.NavStatus.FAILED_TERMINAL, r2.status)
    local m = Obs.snapshot()
    assert.equals(1, m.identicalUnchangedRecoveryLoopCount)
    assert.equals(0, #player.pending)
  end)

  it("allows re-targeting after new evidence (map change / re-selection)", function()
    makeSession(routeWithNodes(
      { { id = "e1", kind = D.EDGE_KIND.WALK, toNode = "n1", toPos = B } },
      { { id = "n1", pos = B } }))

    local r1 = recover()
    assert.equals("RECOVERY_ANCHOR_SELECTED", r1.reason)

    session.evidenceRevision = session.evidenceRevision + 1
    session.state = D.SESSION_STATE.RECOVERING
    local r2 = recover()
    assert.equals("RECOVERY_ANCHOR_SELECTED", r2.reason)
  end)

  it("fail-safes with RECOVERY_TARGET_UNREACHABLE when no node is reachable", function()
    makeSession(routeWithNodes(
      { { id = "e1", kind = D.EDGE_KIND.WALK, toNode = "n1", toPos = { x = 40, y = 40, z = 7 } } },
      { { id = "n1", pos = { x = 40, y = 40, z = 7 } } }))

    world:setWall({ x = 14, y = 10, z = 7 })

    local res = recover()
    assert.equals("RECOVERY_TARGET_UNREACHABLE", res.reason)
    assert.equals(D.NavStatus.FAILED_TERMINAL, res.status)
    local m = Obs.snapshot()
    assert.equals(1, m.wrongRouteRecoveryCount)
  end)

  it("fail-safes when the route graph is empty", function()
    makeSession(routeWithNodes({}, {}))
    local res = recover()
    assert.equals("RECOVERY_TARGET_UNREACHABLE", res.reason)
  end)

  it("tracks combat episodes and records unexpected Z changes", function()
    makeSession(routeWithNodes(
      { { id = "e1", kind = D.EDGE_KIND.WALK, toNode = "n1", toPos = B } },
      { { id = "n1", pos = B } }))

    local rec = session.deps.recovery
    rec:onCombatState(false, true)
    rec:onCombatState(true, true)
    assert.equals(0, rec:snapshot().episodes)
    rec:onCombatState(true, false)
    assert.equals(1, rec:snapshot().episodes)
    assert.equals("COMBAT_END_RESOLVE", rec:snapshot().phase)

    rec:onUnexpectedZChange({ x = 10, y = 10, z = 8 }, D.TRANSITION_CLASS.UNKNOWN_Z_CHANGE)
    local m = Obs.snapshot()
    assert.equals(1, m.wrongFloorRecoveryCount)
    assert.equals("RECOVERING", rec:snapshot().phase)
  end)

  it("defers (WAITING_BLOCKER) until a player position is observed", function()
    makeSession(routeWithNodes(
      { { id = "e1", kind = D.EDGE_KIND.WALK, toNode = "n1", toPos = B } },
      { { id = "n1", pos = B } }))

    local res = session.deps.recovery:tick(session, { nowMs = 0 })
    assert.equals("RECOVERY_DEFERRED", res.reason)
    assert.equals(D.NavStatus.WAITING_BLOCKER, res.status)
  end)
end)