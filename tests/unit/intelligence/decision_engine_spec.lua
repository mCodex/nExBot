local function loadModule()
  _G.IntelligenceDecisionEngine = nil
  return dofile("core/intelligence/decisions/decision_engine.lua")
end

describe("Intelligence Decision Engine", function()
  it("selects deterministically and explains stale or expired rejections", function()
    local engine = loadModule().new({ now = function() return 100 end })
    local proposals = {
      { id = "first", safety = 1, priority = 10, confidence = 0.8, utility = 0.7, expiresAt = 101 },
      { id = "expired", safety = 9, priority = 99, confidence = 1, utility = 1, expiresAt = 100 },
      { id = "stale", safety = 9, priority = 99, confidence = 1, utility = 1, routeGeneration = 2 },
      { id = "second", safety = 1, priority = 10, confidence = 0.8, utility = 0.7 },
    }

    local selected, rejected = engine:select(proposals, { route = 3 })

    assert.equals("first", selected.id)
    assert.same({
      { proposal = proposals[2], reason = "expired" },
      { proposal = proposals[3], reason = "stale_route_generation" },
    }, rejected)
  end)

  it("orders valid proposals by safety, priority, confidence, then utility", function()
    local engine = loadModule().new()
    local selected = engine:select({
      { id = "utility", safety = 1, priority = 2, confidence = 0.8, utility = 1 },
      { id = "confidence", safety = 1, priority = 2, confidence = 0.9, utility = 0 },
      { id = "priority", safety = 1, priority = 3, confidence = 0, utility = 0 },
      { id = "safety", safety = 2, priority = 0, confidence = 0, utility = 0 },
    })
    assert.equals("safety", selected.id)
  end)

  it("keeps configured user priority above learned score changes", function()
    local engine = loadModule().new()
    local selected = engine:select({
      { id = "user-high", configuredPriority = 5, priority = 4500, confidence = 0.7 },
      { id = "learned-high", configuredPriority = 4, priority = 9999, confidence = 1 },
    })
    assert.equals("user-high", selected.id)
  end)
end)
