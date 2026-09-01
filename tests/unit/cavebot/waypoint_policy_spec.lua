local WaypointPolicy = require("cavebot.waypoint_policy")

local function position(x, y, z)
  return {x = x, y = y, z = z}
end

describe("WaypointPolicy.classify", function()
  it("classifies representative waypoint topologies", function()
    local cases = {
      {
        name = "normal waypoint",
        waypoint = {position = position(10, 10, 7)},
        topology = {},
        expected = "normal",
      },
      {
        name = "corner in a one-tile corridor",
        waypoint = {position = position(10, 10, 7), corner = true},
        topology = {
          adjacentPositions = {
            position(9, 10, 7), position(11, 10, 7), position(10, 9, 7),
            position(10, 11, 7), position(9, 9, 7), position(11, 11, 7),
          },
          isWalkable = function(tilePosition)
            return tilePosition.x == 9 and tilePosition.y == 10
              or tilePosition.x == 10 and tilePosition.y == 11
          end,
        },
        expected = "corridor",
      },
      {
        name = "adjacent stair",
        waypoint = {position = position(10, 10, 7)},
        topology = {adjacentFloorChange = true},
        expected = "transition",
      },
      {
        name = "cross-floor transition",
        waypoint = {position = position(10, 10, 8), isFloorChange = true},
        topology = {playerPosition = position(10, 9, 7)},
        expected = "transition",
      },
      {
        name = "post-floor-change recovery",
        waypoint = {position = position(10, 10, 8)},
        topology = {floorChanged = true, playerPosition = position(10, 10, 7)},
        expected = "recovery",
      },
    }

    for _, case in ipairs(cases) do
      assert.are_equal(case.expected, WaypointPolicy.classify(case.waypoint, case.topology), case.name)
    end
  end)
end)

describe("WaypointPolicy.forApproach", function()
  it("keeps normal approaches bounded and advanceable", function()
    local approach = WaypointPolicy.forApproach({
      classification = "normal",
      precision = 2,
      maxSteps = 500,
    })

    assert.same({arrivalPrecision = 2, dispatch = "auto", maxSteps = 50, allowAdvance = true}, approach)
  end)

  it("requires exact keyboard stepping and observed floor results for transitions", function()
    local approach = WaypointPolicy.forApproach({
      classification = "transition",
      precision = 3,
      maxSteps = 20,
      distance = 1,
      floorObserved = false,
    })

    assert.same({arrivalPrecision = 0, dispatch = "keyboard", maxSteps = 20, allowAdvance = false}, approach)
  end)

  it("keeps post-floor recovery blocked until the floor result is observed", function()
    local approach = WaypointPolicy.forApproach({
      classification = "recovery",
      maxSteps = 80,
      floorObserved = false,
    })

    assert.same({arrivalPrecision = 0, dispatch = "keyboard", maxSteps = 50, allowAdvance = false}, approach)
  end)
end)
