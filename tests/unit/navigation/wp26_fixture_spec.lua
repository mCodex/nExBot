-- tests/unit/navigation/wp26_fixture_spec.lua
-- WP26 fixture: the repeated "[CaveBot] ... refocusing WP<n>" log must be
-- structurally unproducible under the new navigation domain.
--
-- WP26 reproduced a 3-line log storm: post-combat corridor recovery kept
-- refocusing the SAME geometric waypoint with NO new evidence (the corridor
-- projection stayed constant and the waypoint never became reachable).
--
-- New invariants under test:
--   (a) recovery targets come ONLY from the route graph (nodes), never a
--       geometric corridor index — so there is no `recovery.nextWpIdx`
--       projection to loop over;
--   (b) invariant 5: repeating the same route node without NEW evidence is
--       suppressed (RECOVERY_TARGET_DUPLICATE_SUPPRESSED) — the identical
--       "refocusing WP" directive can never be re-emitted back-to-back;
--   (c) every movement command is pre-validated, so the wall-directed step
--       behind the log never dispatches (wallDirectedCommandCount stays 0).

local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local Session = require("navigation.session")
local Recovery = require("navigation.recovery")
local Obs = require("navigation.observability")
local D = require("navigation.domain")

describe("WP26 fixture (repeated refocus log)", function()
  local world, player, port, session, directives
  local A = { x = 10, y = 10, z = 7 }
  local B = { x = 12, y = 10, z = 7 }
  local C = { x = 14, y = 10, z = 7 }

  -- The old WP26 loop would re-emit a "refocusing WP" directive on EVERY
  -- tick while off-route. We capture every recovery directive the session
  -- would hand to a UI/log emitter.
  local function captureDirective(res)
    if res and res.reason == D.REASON.RECOVERY_ANCHOR_SELECTED then
      directives[#directives + 1] = res.targetNode
    end
  end

  before_each(function()
    world = Fake.newWorld()
    world:freespaceRect(5, 5, 16, 15, 7)
    player = Fake.newPlayer(world, A)
    port = AdapterFake.create(world, player, { onEvent = function() end })
    session = Session.new(port, { recovery = Recovery.new() })
    session:setRoute({
      id = "r1",
      nodes = { { id = "n1", pos = B }, { id = "n2", pos = C } },
      edges = {
        { id = "e1", kind = D.EDGE_KIND.WALK, toNode = "n1", toPos = B },
        { id = "e2", kind = D.EDGE_KIND.WALK, toNode = "n2", toPos = C },
      },
    })
    directives = {}
    Obs.resetMetrics()
  end)

  it("the identical recovery directive is never re-emitted without new evidence", function()
    -- Simulate the WP26 post-combat corridor loop: tick after tick, the
    -- recovery tries to refocus. Only the FIRST selection may emit.
    for _ = 1, 20 do
      session.state = D.SESSION_STATE.RECOVERING
      local res = session.deps.recovery:tick(session, {
        playerPos = player:getPosition(), nowMs = player:getClock(),
      })
      captureDirective(res)
      if res.reason == D.REASON.RECOVERY_TARGET_DUPLICATE_SUPPRESSED then break end
      -- new evidence arrives ONLY if the player actually moves
    end

    assert.equals(1, #directives, "identical refocus directive emitted more than once")
    assert.equals("n1", directives[1])
    -- The loop terminates (no infinite re-emission).
    assert.equals(1, Obs.snapshot().identicalUnchangedRecoveryLoopCount)
  end)

  it("recovery targets are route nodes, never a geometric corridor index", function()
    local rec = session.deps.recovery
    session.state = D.SESSION_STATE.RECOVERING
    local res = rec:tick(session, { playerPos = A, nowMs = 0 })
    assert.equals(D.REASON.RECOVERY_ANCHOR_SELECTED, res.reason)
    -- The target exists in the route graph (n1/n2), not a fabricated index.
    local found = false
    for _, node in ipairs(session.route.nodes) do
      if node.id == res.targetNode then found = true break end
    end
    assert.is_true(found, "recovery targeted a node outside the route graph")
  end)

  it("zero wall-directed commands and zero unexplained advances under the loop", function()
    for _ = 1, 20 do
      session.state = D.SESSION_STATE.RECOVERING
      local res = session.deps.recovery:tick(session, {
        playerPos = player:getPosition(), nowMs = player:getClock(),
      })
      if res.reason == D.REASON.RECOVERY_TARGET_DUPLICATE_SUPPRESSED then break end
    end
    local m = Obs.snapshot()
    assert.equals(0, m.wallDirectedCommandCount)
    assert.equals(0, m.unexplainedWaypointAdvanceCount)
    assert.equals(0, #player.pending, "recovery dispatched raw movement commands")
  end)

  it("new evidence (player movement) breaks the suppression and re-targets", function()
    session.state = D.SESSION_STATE.RECOVERING
    local r1 = session.deps.recovery:tick(session, { playerPos = A, nowMs = 0 })
    assert.equals(D.REASON.RECOVERY_ANCHOR_SELECTED, r1.reason)

    -- Player actually moves toward the anchor: real evidence arrives.
    session.evidenceRevision = session.evidenceRevision + 1
    session.state = D.SESSION_STATE.RECOVERING
    local r2 = session.deps.recovery:tick(session, { playerPos = { x = 11, y = 10, z = 7 }, nowMs = 100 })
    assert.equals(D.REASON.RECOVERY_ANCHOR_SELECTED, r2.reason)
  end)
end)