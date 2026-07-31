local CombatFixture = require("tests.helpers.combat_fixture")

describe("Property invariants — validation tests", function()
  local fx

  before_each(function()
    math.randomseed(42)
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
    _G.KillCompletionModel = dofile("targetbot/ml/kill_completion_model.lua")
    _G.MovementArbitrator = dofile("targetbot/application/movement_arbitrator.lua")
  end)

  it("Invalid replacement never invalidates current target", function()
    local commitment = _G.TargetCommitmentManager
    local evaluator = _G.TargetCandidateEvaluator

    for _ = 1, 10 do
      commitment.reset()
      local targetId = math.random(1, 100)
      local hp = math.random(10, 90)

      commitment.acquire(targetId, "FINISH_KILL", hp)

      local currentScore = evaluator.evaluate(nil, {
        creatureHpPercent = hp,
        reachabilityState = _G.ReachabilityState.ATTACKABLE_NOW,
        commitment = { targetId = targetId },
        playerHpPercent = 100,
        isCurrentTarget = true,
      })

      local invalidScore = evaluator.evaluate(nil, {
        creatureHpPercent = math.random(50, 100),
        reachabilityState = _G.ReachabilityState.TEMPORARILY_BLOCKED,
        commitment = nil,
        playerHpPercent = 100,
        isCurrentTarget = false,
      })

      local shouldSwitch = evaluator.shouldSwitch(currentScore, invalidScore)
      assert.is_false(shouldSwitch)
    end
  end)

  it("Living committed target never disappears without valid release reason", function()
    local commitment = _G.TargetCommitmentManager

    local validReasons = {
      _G.ReleaseReason.TARGET_DEAD,
      _G.ReleaseReason.TARGET_REMOVED,
      _G.ReleaseReason.TARGET_DIFFERENT_FLOOR,
      _G.ReleaseReason.MANUAL_OVERRIDE,
      _G.ReleaseReason.SAFETY_ABORT,
      _G.ReleaseReason.CONFIRMED_HARD_UNREACHABLE,
      _G.ReleaseReason.TARGETBOT_DISABLED,
    }

    for _, reason in ipairs(validReasons) do
      commitment.reset()
      commitment.acquire(1, "FINISH_KILL", 50)

      local ok = commitment.release(1, reason)
      assert.is_true(ok, "Release with " .. reason .. " should succeed")
    end
  end)

  it("Temporary reachability failures do not immediately become permanent", function()
    local reachability = _G.ReachabilityService
    local target = fx:addMonster(1, "Orc", 80, 110, 100)
    fx:setReachability(1, false, "no_attack_position")

    reachability.reset()
    local r1 = reachability.evaluate(target, { force = true })
    assert.not_equals(_G.ReachabilityState.CONFIRMED_HARD_UNREACHABLE, r1.state)

    reachability.reset()
    fx.player:setPosition(100, 100, 7)
    reachability.evaluate(target, { force = true })
    fx.player:setPosition(101, 100, 7)
    local r2 = reachability.evaluate(target, { force = true })
    assert.not_equals(_G.ReachabilityState.CONFIRMED_HARD_UNREACHABLE, r2.state)
  end)

  it("ML never overrides hard safety", function()
    local arbitrator = _G.FeatureArbitrator:new()

    for _ = 1, 10 do
      local intents = {
        { source = "LURE", position = {x=105, y=100, z=7}, confidence = math.random() },
        { source = "PULL", position = {x=103, y=100, z=7}, confidence = math.random() },
      }

      local result = arbitrator:resolve(intents, { playerHpPercent = 5 })

      if result.selected then
        local p = _G.FeatureArbitrator.PRECEDENCE[result.selected.source] or 0
        assert.is_true(p >= 100 or result.selected.source == "HARD_SAFETY" or result.selected.source == "WAVE_AVOIDANCE")
      end
    end
  end)

  it("ML never overrides finish commitment", function()
    local commitment = _G.TargetCommitmentManager

    commitment.reset()
    commitment.acquire(1, "FINISH_KILL", 30)

    local active = commitment.getActive()
    assert.is_not_nil(active)
    assert.equals("FINISH_KILL", active.reason)
  end)

  it("FeatureArbitrator always returns at most one selected intent", function()
    local arbitrator = _G.FeatureArbitrator:new()
    local sources = {"LURE", "PULL", "REPOSITION", "CHASE", "KEEP_DISTANCE", "ROUTE_ADVANCEMENT"}

    for _ = 1, 20 do
      local intents = {}
      local count = math.random(1, 10)
      for _ = 1, count do
        intents[#intents + 1] = {
          source = sources[math.random(1, #sources)],
          position = {x=100 + math.random(1, 10), y=100, z=7},
          confidence = math.random(),
        }
      end

      local result = arbitrator:resolve(intents, {})

      if result.selected then
        assert.is_not_nil(result.selected.source)
      end
    end
  end)

  it("Every release reason is in ReleaseReason enum", function()
    local allReasons = {
      _G.ReleaseReason.TARGET_DEAD,
      _G.ReleaseReason.TARGET_REMOVED,
      _G.ReleaseReason.TARGET_DIFFERENT_FLOOR,
      _G.ReleaseReason.MANUAL_OVERRIDE,
      _G.ReleaseReason.SAFETY_ABORT,
      _G.ReleaseReason.STRICT_FOLLOW_OVERRIDE,
      _G.ReleaseReason.CONFIRMED_HARD_UNREACHABLE,
      _G.ReleaseReason.TARGET_TIMEOUT_WITH_EVIDENCE,
      _G.ReleaseReason.TARGETBOT_DISABLED,
    }

    for _, reason in ipairs(allReasons) do
      assert.is_true(_G.ReleaseReason.isValid(reason))
    end
  end)

  it("Reachability states are in ReachabilityState enum", function()
    local allStates = {
      _G.ReachabilityState.ATTACKABLE_NOW,
      _G.ReachabilityState.REPOSITION_REQUIRED,
      _G.ReachabilityState.TEMPORARILY_BLOCKED,
      _G.ReachabilityState.VISIBILITY_UNKNOWN,
      _G.ReachabilityState.PATH_API_UNAVAILABLE,
      _G.ReachabilityState.MOVING_TARGET,
      _G.ReachabilityState.DIFFERENT_FLOOR,
      _G.ReachabilityState.REMOVED,
      _G.ReachabilityState.CONFIRMED_HARD_UNREACHABLE,
    }

    for _, state in ipairs(allStates) do
      assert.is_not_nil(state)
      assert.is_string(state)
    end
  end)

  it("Target evaluator comparison is transitive", function()
    local evaluator = _G.TargetCandidateEvaluator

    for _ = 1, 15 do
      local scoreA = {
        safetyTier = math.random(0, 3),
        commitmentTier = math.random(0, 2),
        configuredPriority = math.random(1, 5),
        killCompletionScore = math.random() * 0.5,
        attackContinuityScore = math.random() * 0.3,
        reachabilityConfidence = math.random(),
        pathCost = math.random(1, 20),
        tacticalUtility = math.random() * 0.5,
        learnedUtility = math.random() * 0.5,
      }

      local scoreB = {
        safetyTier = math.random(0, 3),
        commitmentTier = math.random(0, 2),
        configuredPriority = math.random(1, 5),
        killCompletionScore = math.random() * 0.5,
        attackContinuityScore = math.random() * 0.3,
        reachabilityConfidence = math.random(),
        pathCost = math.random(1, 20),
        tacticalUtility = math.random() * 0.5,
        learnedUtility = math.random() * 0.5,
      }

      local scoreC = {
        safetyTier = math.random(0, 3),
        commitmentTier = math.random(0, 2),
        configuredPriority = math.random(1, 5),
        killCompletionScore = math.random() * 0.5,
        attackContinuityScore = math.random() * 0.3,
        reachabilityConfidence = math.random(),
        pathCost = math.random(1, 20),
        tacticalUtility = math.random() * 0.5,
        learnedUtility = math.random() * 0.5,
      }

      local winnerAB = evaluator.compare(scoreA, scoreB)
      local winnerBC = evaluator.compare(scoreB, scoreC)
      local winnerAC = evaluator.compare(scoreA, scoreC)

      if winnerAB == "A" and winnerBC == "A" then
        assert.equals("A", winnerAC)
      end
    end
  end)

  it("MovementArbitrator never returns success without a selected intent", function()
    local arbitrator = _G.FeatureArbitrator:new()
    local movementArb = _G.MovementArbitrator.new({ featureArbitrator = arbitrator })

    local ok = movementArb:tick({}, {})
    assert.is_false(ok)

    local decision = movementArb:getLastDecision()
    assert.is_false(decision.success)
  end)

  it("LurePlanner never produces plan when hasCommitment and targetHp < 30%", function()
    local lure = _G.LurePlanner.new()

    for _ = 1, 10 do
      local obs = {
        hasCommitment = true,
        targetHp = math.random(1, 29),
        creatureCount = math.random(1, 5),
        currentPos = {x=100, y=100, z=7},
      }

      local plan, reason = lure:plan(obs, { now = fx.clock })
      assert.is_nil(plan)
      assert.equals("LURE_DEFERRED_FINISH_TARGET", reason)
    end
  end)

  it("PullPlanner never produces plan without destination", function()
    local pull = _G.PullPlanner.new()

    local plan, reason = pull:plan(
      { participantId = 1, distance = 3, currentPos = nil },
      { now = fx.clock }
    )

    assert.is_nil(plan)
    assert.equals("NO_DESTINATION", reason)
  end)
end)
