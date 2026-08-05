-- tests/unit/navigation/transitions_spec.lua
-- TransitionCoordinator (P0.6/P0.8): entry -> Z step -> verified landing,
-- wrong-exit classification, timeout, unexpected Z classification.

local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local Transitions = require("navigation.transitions")
local StepExecutor = require("navigation.step_executor")
local Obs = require("navigation.observability")
local D = require("navigation.domain")

describe("TransitionCoordinator", function()
  local world, player, port, tc
  local A = { x = 10, y = 10, z = 7 }
  local entry = { x = 10, y = 10, z = 7 }
  local toPos = { x = 10, y = 10, z = 8 }

  local function makeTC(edge)
    tc = Transitions.new()
    tc.begin(edge, player:getPosition())
    return tc
  end

  before_each(function()
    world = Fake.newWorld()
    world:freespaceRect(5, 5, 16, 15, 7)
    player = Fake.newPlayer(world, A)
    port = AdapterFake.create(world, player)
    StepExecutor.active = nil
    Obs.resetMetrics()
  end)

  local stairsUp = { id = "e1", kind = D.EDGE_KIND.STAIRS_UP, toNode = "n1",
                     toPos = toPos, entryPos = entry, expectedFloorDelta = 1 }

  it("is inactive until a transition begins", function()
    tc = Transitions.new()
    assert.is_false(tc.isActive())
    makeTC(stairsUp)
    assert.is_true(tc.isActive())
    assert.equals("WAITING_Z", tc.snapshot().phase)
  end)

  it("dispatches the Z step and completes only after verified Z delta + landing", function()
    makeTC(stairsUp)

    local res = tc.tick(port, {
      playerPos = player:getPosition(), nowMs = player:getClock(),
      zStepDirection = D.DIR.EAST, routeId = "r1", generation = 1, mapGeneration = 1,
    })
    assert.equals("TRANSITION_STEP_DISPATCHED", res.reason)
    assert.is_true(res.commandIssued)

    -- No Z change yet: still waiting.
    player:advance(Fake.STEP_DELAY_MS)
    assert.is_true(tc.isActive())

    -- Wrong Z delta (0 instead of +1): wrong exit.
    local r = tc.onZChange(player:getPosition(), player:getPosition())
    assert.equals(D.TRANSITION_CLASS.EXPECTED_TRANSITION_WRONG_EXIT, r.class)

    -- Re-begin; correct delta but wrong landing tile -> wrong exit.
    makeTC(stairsUp)
    local delta = 1
    local wrongLand = { x = 10, y = 11, z = 7 + delta }
    local r2 = tc.onZChange(wrongLand, { x = 10, y = 10, z = 7 })
    assert.equals(D.TRANSITION_CLASS.EXPECTED_TRANSITION_WRONG_EXIT, r2.class)
    assert.is_false(tc.isActive())
  end)

  it("completes when Z delta + landing match the edge", function()
    makeTC(stairsUp)
    tc.expectedFloorDelta = 1
    local landing = { x = 10, y = 10, z = 8 }
    local r = tc.onZChange(landing, A)
    assert.equals(D.TRANSITION_CLASS.EXPECTED_TRANSITION_COMPLETED, r.class)
    assert.is_false(tc.isActive())
  end)

  it("classifies unexpected Z changes (not during active transition)", function()
    tc = Transitions.new()
    local c = tc.classify({ x = 10, y = 10, z = 8 }, { x = 10, y = 10, z = 7 }, nil)
    assert.equals(D.TRANSITION_CLASS.UNKNOWN_Z_CHANGE, c)

    -- Active transition edge but no coordinator state: timeout classification.
    local c2 = tc.classify({ x = 10, y = 10, z = 8 }, { x = 10, y = 10, z = 7 }, stairsUp)
    assert.equals(D.TRANSITION_CLASS.EXPECTED_TRANSITION_TIMEOUT, c2)
  end)

  it("times out waiting for the Z ack", function()
    makeTC(stairsUp)
    tc.tick(port, {
      playerPos = player:getPosition(), nowMs = player:getClock(),
      zStepDirection = D.DIR.EAST, routeId = "r1", generation = 1, mapGeneration = 1,
    })
    player:rejectNextStep()
    player:advance(Fake.STEP_DELAY_MS * 4)

    local res = tc.tick(port, { playerPos = player:getPosition(), nowMs = player:getClock() + 100000, zStepDirection = D.DIR.EAST })
    assert.equals(D.NavStatus.FAILED_RETRYABLE, res.status)
    assert.equals("TRANSITION_TIMEOUT", res.reason)
  end)
end)