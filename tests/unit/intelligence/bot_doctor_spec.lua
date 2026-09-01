local Doctor = dofile("core/intelligence/observability/bot_doctor.lua")

describe("intelligence Bot Doctor", function()
  it("reports actionable ownership, lifecycle, schema, and performance issues", function()
    local issues = Doctor.inspect({
      owners = {
        movement = { "MovementCoordinator", "CaveBot" },
        attack = {},
      },
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

  it("flags an active long session with no intelligence samples", function()
    local issues = Doctor.inspect({
      owners = {
        movement = { "MovementCoordinator" },
        attack = { "AttackStateMachine" },
      },
      lifecycle = { active = true, subscriptions = 2, elapsedMs = 11 * 60 * 1000 },
      pipeline = { eventCount = 0 },
      models = { summary = { samples = 0 } },
      monsters = { liveMonsters = 1, summary = { persistedProfiles = 0 } },
      session = { elapsedMs = 11 * 60 * 1000 },
      schemas = { storage = { current = 5, expected = 5 }, replay = { current = 1, expected = 1 } },
      performance = { tickMs = 4, budgetMs = 5 },
    })

    local codes = {}
    for _, issue in ipairs(issues) do
      codes[issue.code] = true
    end

    assert.is_true(codes.DATA_PIPELINE_NO_EVENTS)
    assert.is_true(codes.MODEL_ZERO_SAMPLES)
    assert.is_true(codes.MONSTER_INSIGHTS_EMPTY)
    assert.is_true(codes.UI_PROJECTION_EMPTY)
  end)

  it("captures live owners, listener count, pipeline, and tick data", function()
    local captured = Doctor.capture({
      lifecycle = { active = true },
      budgets = { maxMilliseconds = 5 },
    }, {
      movementOwner = "MovementCoordinator",
      attackOwner = "AttackStateMachine",
      subscriptions = 4,
      tick = { avgTickTime = 2 },
      storageVersion = 5,
      replayVersion = 1,
      elapsedMs = 1234,
      pipeline = { eventCount = 3 },
      models = { summary = { samples = 9 } },
      monsters = { liveMonsters = 2, summary = { persistedProfiles = 1 } },
      session = { elapsedMs = 1234 },
    })

    assert.same({ "MovementCoordinator" }, captured.owners.movement)
    assert.same({ "AttackStateMachine" }, captured.owners.attack)
    assert.equals(4, captured.lifecycle.subscriptions)
    assert.equals(2, captured.performance.tickMs)
    assert.equals(5, captured.performance.budgetMs)
    assert.equals(3, captured.pipeline.eventCount)
    assert.equals(9, captured.models.summary.samples)
  end)
end)
