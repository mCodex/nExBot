describe("TargetBot movement commands", function()
  local env
  local dispatched
  local callbacks

  before_each(function()
    dispatched = {}
    callbacks = 0
    env = {
      nExBot = { Shared = { getClient = function() end } },
      TargetBot = {},
      TargetCore = { PathSafety = { pathCrossesFloorChange = function() return false end } },
      PathUtils = {
        DIR_TO_OFFSET = { [1] = { x = 1, y = 0 } },
        isFloorChangeTile = function() return false end,
      },
      player = {
        isWalking = function() return false end,
        getPosition = function() return { x = 100, y = 100, z = 7 } end,
      },
      getPath = function() return { 1 } end,
      walk = function(direction)
        assert.equals(1, direction)
        table.insert(dispatched, direction)
      end,
      now = 1000,
    }
    assert(loadfile("targetbot/walking.lua", "t", env))()
  end)

  local function issueWalk()
    env.TargetBot.walkTo({ x = 103, y = 100, z = 7 }, 20, { precision = 2 })
  end

  it("respects the Rust goal result at the normal walk entry point", function()
    env.nExBotRuntime = { decide = function(operation, data)
      assert.equals("movement_goal", operation)
      assert.equals(2, data.precision)
      assert.equals(103, data.goal.x)
      callbacks = callbacks + 1
      return "reached"
    end }
    issueWalk()
    assert.equals(1, callbacks)
    assert.same({}, dispatched)
  end)

  it("dispatches the path's first validated direction when movement should continue", function()
    env.nExBotRuntime = { decide = function() return "continue" end }
    issueWalk()
    assert.same({1}, dispatched)
  end)
end)

describe("TargetBot tactical movement votes", function()
  it("uses the native result for the existing movement decision", function()
    local position = { x = 100, y = 100, z = 7 }
    local env = {
      nExBot = {},
      Directions = {},
      player = { getPosition = function() return position end },
      now = 1000,
      nExBotRuntime = { decide = function(operation, data)
        assert.equals("movement_vote", operation)
        assert.same(position, data.player)
        assert.equals(90, data.intents[1].priority)
        return { index = 2, confidence = 0.97 }
      end },
    }
    setmetatable(env, { __index = _G })
    assert(loadfile("targetbot/movement_coordinator.lua", "t", env))()
    local coordinator = env.MovementCoordinator
    local kinds = coordinator.CONSTANTS.INTENT
    coordinator.Intent.register(kinds.WAVE_AVOIDANCE, { x = 99, y = 100, z = 7 }, 0.85, "wave")
    coordinator.Intent.register(kinds.KEEP_DISTANCE, { x = 101, y = 100, z = 7 }, 0.95, "distance")
    local intent, confidence = coordinator.Vote.aggregate()
    assert.equals("distance", intent.source)
    assert.equals(0.97, confidence)
  end)
end)
