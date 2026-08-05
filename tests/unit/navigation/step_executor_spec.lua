-- tests/unit/navigation/step_executor_spec.lua
-- MovementCommand lifecycle: ack-only progression (P0.4/P0.5), chunk policy,
-- ownership, timeout, divergence.

local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local StepExecutor = require("navigation.step_executor")
local D = require("navigation.domain")

describe("StepExecutor", function()
  local world, player, port
  local A = { x = 10, y = 10, z = 7 }

  before_each(function()
    world = Fake.newWorld()
    world:freespaceRect(5, 5, 16, 15, 7)
    player = Fake.newPlayer(world, A)
    port = AdapterFake.create(world, player)
    StepExecutor.active = nil
    StepExecutor.releaseOwnership = function(owner) player:releaseOwnership(owner) end
  end)

  local function dispatch(path, chunkSize)
    return StepExecutor.dispatch({
      ports = port, routeId = "r1", edgeId = "e1", attemptId = 1,
      generation = 1, startPosition = A, path = path,
      chunkSize = chunkSize or #path, mapGeneration = world:getMapGeneration(),
    })
  end

  it("dispatches a single keyboard step", function()
    local cmd = dispatch({ D.DIR.EAST }, 1)
    assert.is_not_nil(cmd)
    assert.equals("KEYBOARD", cmd.dispatchType)
    assert.equals(1, #player.pending)
    assert.equals("CAVEBOT", player:getOwner())
    assert.equals(1, cmd.attemptId)
  end)

  it("dispatches an auto-walk chunk", function()
    local cmd = dispatch({ D.DIR.EAST, D.DIR.EAST, D.DIR.EAST }, 3)
    assert.equals("AUTOWALK", cmd.dispatchType)
    assert.equals(3, #player.pending)
    assert.equals(3, #cmd.expectedPositions)
  end)

  it("returns nil when another movement owner is active", function()
    player:acquireOwnership("TARGETBOT")
    local cmd = dispatch({ D.DIR.EAST }, 1)
    assert.is_nil(cmd)
    assert.equals("TARGETBOT", player:getOwner())
  end)

  it("times out without any position ack (P0.5: isWalking is not progress)", function()
    local cmd = dispatch({ D.DIR.EAST }, 1)
    assert.is_not_nil(cmd)
    assert.is_true(player:isWalking())
    player:advance(7000)
    local timeout = StepExecutor.tick(player:getClock())
    assert.is_not_nil(timeout)
    assert.equals("NO_POSITION_ACK", timeout.reason)
    assert.equals("NONE", player:getOwner())
    assert.is_nil(StepExecutor.getActive())
  end)

  it("acks an exact prefix on position change (partial auto-walk)", function()
    local dirs = { D.DIR.EAST, D.DIR.EAST, D.DIR.EAST }
    dispatch(dirs, 3)
    player:advance(Fake.STEP_DELAY_MS)
    local ack = StepExecutor.onPositionChange(player:getPosition(), A, player:getClock())
    assert.is_not_nil(ack)
    assert.is_true(ack.progressed)
    assert.is_true(ack.partial)
    assert.equals(1, ack.ackedSteps)
    assert.is_true(ack.partialAutoWalk)
    assert.equals(2, #player.pending)
  end)

  it("completes when the full chunk is acknowledged", function()
    dispatch({ D.DIR.EAST }, 1)
    player:advance(Fake.STEP_DELAY_MS)
    local ack = StepExecutor.onPositionChange(player:getPosition(), A, player:getClock())
    assert.is_not_nil(ack)
    assert.is_true(ack.completed)
    assert.equals(1, ack.ackedSteps)
    assert.is_nil(StepExecutor.getActive())
    assert.equals("NONE", player:getOwner())
  end)

  it("flags divergence when the player moves off the expected path", function()
    dispatch({ D.DIR.EAST }, 1)
    player:advance(Fake.STEP_DELAY_MS)
    local ack = StepExecutor.onPositionChange({ x = 10, y = 11, z = 7 }, A, player:getClock())
    assert.is_true(ack.diverged)
    assert.equals("PATH_DIVERGENCE", ack.reason)
    assert.is_nil(StepExecutor.getActive())
  end)

  it("treats a bounce back to the start as a server rejection", function()
    dispatch({ D.DIR.EAST }, 1)
    local ack = StepExecutor.onPositionChange(A, { x = 11, y = 10, z = 7 }, 0)
    assert.is_true(ack.diverged)
    assert.equals("SERVER_STEP_REJECTED", ack.reason)
  end)

  it("computeChunk shrinks in corridors, corners and transitions", function()
    assert.equals(1, StepExecutor.computeChunk(1, false, false, false))
    assert.equals(1, StepExecutor.computeChunk(nil, true, false, false))
    assert.equals(1, StepExecutor.computeChunk(5, false, true, false))
    assert.equals(3, StepExecutor.computeChunk(2, false, false, false))
    assert.equals(8, StepExecutor.computeChunk(5, false, false, false))
    assert.equals(3, StepExecutor.computeChunk(nil, false, false, false, true))
  end)

  it("server walk errors fire through the client hook, not the ack path", function()
    local err = nil
    player:onWalkError(function(r) err = r end)
    dispatch({ D.DIR.EAST }, 1)
    player:rejectNextStep()
    player:advance(Fake.STEP_DELAY_MS)
    assert.equals("SERVER_STEP_REJECTED", err)
    assert.is_false(player:isWalking())
    -- Position never changed; no ack happened.
    assert.equals(A.x, player:getPosition().x)
  end)
end)