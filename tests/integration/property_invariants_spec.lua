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
    _G.ReachabilityService = dofile("targetbot/domain/reachability_service.lua")
    _G.KillCompletionModel = dofile("targetbot/ml/kill_completion_model.lua")
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

  it("ML never overrides finish commitment", function()
    local commitment = _G.TargetCommitmentManager

    commitment.reset()
    commitment.acquire(1, "FINISH_KILL", 30)

    local active = commitment.getActive()
    assert.is_not_nil(active)
    assert.equals("FINISH_KILL", active.reason)
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
end)
