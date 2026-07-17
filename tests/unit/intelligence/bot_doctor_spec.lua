local Doctor = dofile("core/intelligence/observability/bot_doctor.lua")

describe("intelligence Bot Doctor", function()
  it("reports actionable ownership, lifecycle, schema, and performance issues", function()
    local issues = Doctor.inspect({
      owners = { movement = { "MovementCoordinator", "CaveBot" }, attack = {} },
      lifecycle = { active = true, subscriptions = 0 },
      schemas = { config = { current = 5, expected = 6 } },
      performance = { tickMs = 9, budgetMs = 5 },
    })

    assert.equals("OWNERSHIP_MULTIPLE", issues[1].code)
    assert.equals("OWNERSHIP_MISSING", issues[2].code)
    assert.equals("LIFECYCLE_DISCONNECTED", issues[3].code)
    assert.equals("SCHEMA_MISMATCH", issues[4].code)
    assert.equals("PERFORMANCE_BUDGET", issues[5].code)
    assert.matches("MovementCoordinator", issues[1].action)
  end)

  it("returns no issues for healthy explicit inspection data", function()
    assert.same({}, Doctor.inspect({
      owners = { movement = { "MovementCoordinator" }, attack = { "AttackStateMachine" } },
      lifecycle = { active = true, subscriptions = 2 },
      schemas = { config = { current = 6, expected = 6 } },
      performance = { tickMs = 4, budgetMs = 5 },
    }))
  end)

  it("captures live owners, listener count, schemas, and measured tick data", function()
    local captured = Doctor.capture({ lifecycle = { active = true }, budgets = { maxMilliseconds = 5 } },
      { movementOwner = {}, attackOwner = {}, subscriptions = 4, tick = { avgTickTime = 2 },
        storageVersion = 5, replayVersion = 1 })
    assert.same({ "MovementCoordinator" }, captured.owners.movement)
    assert.same({ "AttackStateMachine" }, captured.owners.attack)
    assert.equals(4, captured.lifecycle.subscriptions)
    assert.equals(2, captured.performance.tickMs)
    assert.equals(5, captured.performance.budgetMs)
  end)
end)
