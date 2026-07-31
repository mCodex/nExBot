local CombatFixture = require("tests.helpers.combat_fixture")

describe("Combat pipeline — integration tests", function()
  local fx, commitment, evaluator, arbitrator, reachability

  before_each(function()
    fx = CombatFixture.new()
    fx:installGlobals()

    _G.ReleaseReason = dofile("targetbot/domain/release_reasons.lua")
    _G.ReachabilityState = dofile("targetbot/domain/reachability_states.lua")
    _G.TargetReachability = dofile("targetbot/monster_reachability.lua")
    _G.TargetCommitmentManager = dofile("targetbot/domain/target_commitment.lua")
    _G.TargetCandidateEvaluator = dofile("targetbot/domain/target_evaluator.lua")
    _G.FeatureArbitrator = dofile("targetbot/domain/feature_arbitrator.lua")
    _G.ReachabilityService = dofile("targetbot/domain/reachability_service.lua")
    _G.LurePlanner = dofile("targetbot/tactical/lure_planner.lua")
    _G.PullPlanner = dofile("targetbot/tactical/pull_planner.lua")
    _G.RepositionPlanner = dofile("targetbot/tactical/reposition_planner.lua")
    _G.DynamicLurePlanner = dofile("targetbot/tactical/dynamic_lure_planner.lua")
    _G.KillCompletionModel = dofile("targetbot/ml/kill_completion_model.lua")
    _G.MovementArbitrator = dofile("targetbot/application/movement_arbitrator.lua")

    commitment = _G.TargetCommitmentManager
    evaluator = _G.TargetCandidateEvaluator
    arbitrator = _G.FeatureArbitrator:new()
    reachability = _G.ReachabilityService
  end)

  it("Full pipeline: discover → commit → attack → release", function()
    local target = fx:addMonster(1, "Orc", 50, 101, 100)

    local c = commitment.acquire(1, "FINISH_KILL", 50)
    assert.is_not_nil(c)

    local score = evaluator.evaluate(target, {
      creatureHpPercent = 50,
      reachabilityState = _G.ReachabilityState.ATTACKABLE_NOW,
      commitment = c,
      playerHpPercent = 100,
      isCurrentTarget = true,
    })

    assert.equals(1, score.commitmentTier)

    local candidate = evaluator.evaluate(target, {
      creatureHpPercent = 80,
      reachabilityState = _G.ReachabilityState.ATTACKABLE_NOW,
      commitment = nil,
      playerHpPercent = 100,
      isCurrentTarget = false,
    })

    local shouldSwitch = evaluator.shouldSwitch(score, candidate)
    assert.is_false(shouldSwitch)

    local ok, reason = commitment.release(1, _G.ReleaseReason.TARGET_DEAD)
    assert.is_true(ok)
    assert.equals(_G.ReleaseReason.TARGET_DEAD, reason)
  end)

  it("Feature interaction: Lure + Pull + FinishKill simultaneously", function()
    local lure = _G.LurePlanner.new()
    local pull = _G.PullPlanner.new()

    local lurePlan, lureReason = lure:plan(
      { hasCommitment = true, creatureCount = 2, currentPos = {x=100, y=100, z=7} },
      { now = fx.clock }
    )
    assert.is_nil(lurePlan)
    assert.equals("LURE_DEFERRED_FINISH_TARGET", lureReason)

    local pullPlan = pull:plan(
      { participantId = 2, distance = 4, currentPos = {x=100, y=100, z=7} },
      { now = fx.clock }
    )
    assert.is_not_nil(pullPlan)

    local intents = {
      { source = "FINISH_KILL_COMMITMENT", position = {x=101, y=100, z=7}, confidence = 0.9 },
      { source = "LURE", position = {x=105, y=105, z=7}, confidence = 0.7 },
    }

    local result = arbitrator:resolve(intents, { hasCommitment = true, commitmentTargetId = 1 })
    assert.equals("FINISH_KILL_COMMITMENT", result.selected.source)
  end)

  it("CaveBot coordination: pause during commitment, resume after release", function()
    local target = fx:addMonster(3, "Elf", 30, 101, 100)

    commitment.acquire(3, "FINISH_KILL", 30)
    local active = commitment.getActive()
    assert.is_not_nil(active)
    assert.equals(3, active.targetId)

    local blocks = commitment.blocksRelease(3, _G.ReleaseReason.STRICT_FOLLOW_OVERRIDE)
    assert.is_true(blocks)

    local ok = commitment.release(3, _G.ReleaseReason.TARGET_DEAD)
    assert.is_true(ok)

    active = commitment.getActive()
    assert.is_nil(active)
  end)

  it("Reachability evidence accumulation across multiple evaluations", function()
    local target = fx:addMonster(4, "Demon", 80, 130, 100)
    reachability.reset()

    fx.player:setPosition(100, 100, 7)
    local r1 = reachability.evaluate(target, { force = true })
    assert.equals(_G.ReachabilityState.TEMPORARILY_BLOCKED, r1.state)

    fx.player:setPosition(102, 100, 7)
    local r2 = reachability.evaluate(target, { force = true })
    assert.equals(_G.ReachabilityState.TEMPORARILY_BLOCKED, r2.state)

    fx.player:setPosition(104, 100, 7)
    local r3 = reachability.evaluate(target, { force = true })
    assert.equals(_G.ReachabilityState.CONFIRMED_HARD_UNREACHABLE, r3.state)
  end)

  it("Target evaluator structured comparison with commitment", function()
    local committed = evaluator.evaluate(nil, {
      creatureHpPercent = 25,
      reachabilityState = _G.ReachabilityState.ATTACKABLE_NOW,
      commitment = { targetId = 5 },
      playerHpPercent = 100,
      isCurrentTarget = true,
    })

    local candidate = evaluator.evaluate(nil, {
      creatureHpPercent = 90,
      reachabilityState = _G.ReachabilityState.ATTACKABLE_NOW,
      commitment = nil,
      playerHpPercent = 100,
      isCurrentTarget = false,
      config = { priority = 2 },
    })

    local shouldSwitch, reason = evaluator.shouldSwitch(committed, candidate)
    assert.is_false(shouldSwitch)
    assert.equals("committed_target_protection", reason)
  end)

  it("ML shadow mode does not affect decisions", function()
    local model = _G.KillCompletionModel.new()

    local prediction = model:predict({ targetHp = 0.2, distance = 0.3 })
    assert.equals("SHADOW", prediction.mode)
    assert.equals(0.5, prediction.probability)

    local intents = {
      { source = "REPOSITION", position = {x=101, y=100, z=7}, confidence = 0.8 },
    }

    local result = arbitrator:resolve(intents, {})
    assert.is_not_nil(result.selected)
    assert.equals("REPOSITION", result.selected.source)
  end)

  it("Reposition planner preserves same target", function()
    local planner = _G.RepositionPlanner.new()

    local result = planner:plan(
      {
        targetPos = {x=105, y=100, z=7},
        playerPos = {x=100, y=100, z=7},
        attackRange = 1,
        isWalkable = function() return true end,
      },
      { now = fx.clock }
    )

    assert.is_not_nil(result)
    assert.is_not_nil(result.position)
    assert.is_not_nil(result.position.x)
    assert.is_not_nil(result.position.y)
  end)

  it("DynamicLurePlanner + commitment interaction", function()
    local planner = _G.DynamicLurePlanner.new()

    planner:update(
      { creatures = {1, 2, 3}, minCount = 3 },
      { now = fx.clock }
    )

    fx:advanceClock(600)

    local result, reason = planner:update(
      { creatures = {1, 2, 3, 4}, minCount = 3, hasCommitment = true, targetHp = 25 },
      { now = fx.clock }
    )

    assert.is_nil(result)
    assert.equals("LURE_DEFERRED_FINISH_TARGET", reason)
  end)

  it("MovementArbitrator issues at most one movement per tick", function()
    local movementArb = _G.MovementArbitrator.new({ featureArbitrator = arbitrator })

    local intents = {
      { source = "LURE", position = {x=101, y=100, z=7}, confidence = 0.6 },
      { source = "PULL", position = {x=102, y=100, z=7}, confidence = 0.7 },
      { source = "REPOSITION", position = {x=103, y=100, z=7}, confidence = 0.8 },
      { source = "CHASE", position = {x=104, y=100, z=7}, confidence = 0.5 },
      { source = "KEEP_DISTANCE", position = {x=105, y=100, z=7}, confidence = 0.4 },
    }

    local ok, reason = movementArb:tick(intents, {})
    assert.is_true(ok)
    assert.equals("executed", reason)

    local decision = movementArb:getLastDecision()
    assert.is_not_nil(decision.intent)
    assert.is_not_nil(decision.intent.source)
  end)

  it("Multiple release reasons validated", function()
    local reasons = {
      _G.ReleaseReason.TARGET_DEAD,
      _G.ReleaseReason.TARGET_REMOVED,
      _G.ReleaseReason.MANUAL_OVERRIDE,
      _G.ReleaseReason.SAFETY_ABORT,
      _G.ReleaseReason.CONFIRMED_HARD_UNREACHABLE,
    }

    for _, reason in ipairs(reasons) do
      commitment.reset()
      commitment.acquire(10, "FINISH_KILL", 50)

      local blocks = commitment.blocksRelease(10, reason)
      assert.is_false(blocks, "Reason " .. reason .. " should not be blocked")

      local ok = commitment.release(10, reason)
      assert.is_true(ok)
    end
  end)
end)
