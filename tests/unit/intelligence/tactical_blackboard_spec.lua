local function loadModule(options)
  _G.TacticalBlackboard = nil
  dofile("core/intelligence/foundation/tactical_blackboard.lua")
  return TacticalBlackboard.new(options)
end

describe("Tactical Blackboard", function()
  it("accepts only the declared owner and valid values", function()
    local board = loadModule({ keys = {
      targetId = { owner = "TargetBot", validate = function(value) return type(value) == "number" end },
    } })

    assert.is_true(board:write("targetId", 42, { owner = "TargetBot" }))
    assert.equals(42, board:read("targetId"))
    assert.same({ nil, "wrong_owner" }, { board:write("targetId", 7, { owner = "CaveBot" }) })
    assert.same({ nil, "invalid_value" }, { board:write("targetId", "7", { owner = "TargetBot" }) })
    assert.same({ nil, "unknown_key" }, { board:write("other", 7, { owner = "TargetBot" }) })
  end)

  it("expires facts and rejects stale generations", function()
    local now = 100
    local board = loadModule({
      now = function() return now end,
      keys = { route = { owner = "CaveBot" } },
    })
    board:setGenerations({ route = 2 })

    assert.same({ nil, "stale_route_generation" }, {
      board:write("route", "old", { owner = "CaveBot", routeGeneration = 1 }),
    })
    assert.is_true(board:write("route", "north", {
      owner = "CaveBot", routeGeneration = 2, ttl = 20,
    }))
    assert.equals("north", board:read("route"))
    now = 120
    assert.is_nil(board:read("route"))

    board:write("route", "south", { owner = "CaveBot", routeGeneration = 2 })
    board:setGenerations({ route = 3 })
    assert.is_nil(board:read("route"))
  end)
end)
