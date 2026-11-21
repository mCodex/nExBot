_G.nExBot = { Shared = { nowMs = function() return 1000 end } }
_G.ReleaseReason = dofile("targetbot/domain/release_reasons.lua")
_G.ReachabilityState = dofile("targetbot/domain/reachability_states.lua")

local E = dofile("targetbot/domain/target_evaluator.lua")

describe("TargetCandidateEvaluator", function()

  describe("evaluate", function()

    it("evaluates reachable melee target with correct structured score", function()
      local score = E.evaluate(nil, {
        config = { priority = 5 },
        isCurrentTarget = true,
        commitment = nil,
        reachabilityState = ReachabilityState.ATTACKABLE_NOW,
        reachabilityPath = {1, 2, 3},
        playerHpPercent = 80,
        creatureHpPercent = 45,
      })
      assert.equals(3, score.safetyTier)
      assert.equals(0, score.commitmentTier)
      assert.equals(5, score.configuredPriority)
      assert.equals(0.4, score.killCompletionScore)
      assert.equals(1.0, score.reachabilityConfidence)
      assert.equals(1.0, score.attackContinuityScore)
      assert.equals(3, score.pathCost)
      assert.equals(0.5, score.tacticalUtility)
      assert.equals(0.5, score.learnedUtility)
    end)

    it("commitmentTier = 2 for finish-kill committed target with HP < 30%", function()
      local score = E.evaluate(nil, {
        config = { priority = 3 },
        isCurrentTarget = false,
        commitment = { targetId = 1, reason = "FINISH_KILL" },
        reachabilityState = ReachabilityState.ATTACKABLE_NOW,
        reachabilityPath = {1},
        playerHpPercent = 80,
        creatureHpPercent = 20,
      })
      assert.equals(2, score.commitmentTier)
    end)

    it("commitmentTier = 1 for engaged committed target with HP >= 30%", function()
      local score = E.evaluate(nil, {
        config = { priority = 3 },
        isCurrentTarget = false,
        commitment = { targetId = 1, reason = "ENGAGEMENT" },
        reachabilityState = ReachabilityState.ATTACKABLE_NOW,
        reachabilityPath = {1},
        playerHpPercent = 80,
        creatureHpPercent = 50,
      })
      assert.equals(1, score.commitmentTier)
    end)

    it("commitmentTier = 0 for uncommitted target", function()
      local score = E.evaluate(nil, {
        config = { priority = 3 },
        isCurrentTarget = false,
        commitment = nil,
        reachabilityState = ReachabilityState.ATTACKABLE_NOW,
        reachabilityPath = {1},
        playerHpPercent = 80,
        creatureHpPercent = 20,
      })
      assert.equals(0, score.commitmentTier)
    end)

    it("killCompletionScore is 1.0 at HP 5%, 0.1 at HP 100%", function()
      local low = E.evaluate(nil, {
        config = { priority = 1 },
        isCurrentTarget = false,
        commitment = nil,
        reachabilityState = ReachabilityState.ATTACKABLE_NOW,
        reachabilityPath = {1},
        playerHpPercent = 80,
        creatureHpPercent = 5,
      })
      assert.equals(1.0, low.killCompletionScore)

      local high = E.evaluate(nil, {
        config = { priority = 1 },
        isCurrentTarget = false,
        commitment = nil,
        reachabilityState = ReachabilityState.ATTACKABLE_NOW,
        reachabilityPath = {1},
        playerHpPercent = 80,
        creatureHpPercent = 100,
      })
      assert.equals(0.1, high.killCompletionScore)
    end)

    it("unreachable candidate gets reachabilityConfidence 0 and safetyTier 0", function()
      local score = E.evaluate(nil, {
        config = { priority = 5 },
        isCurrentTarget = false,
        commitment = nil,
        reachabilityState = ReachabilityState.CONFIRMED_HARD_UNREACHABLE,
        reachabilityPath = nil,
        playerHpPercent = 80,
        creatureHpPercent = 50,
      })
      assert.equals(0, score.reachabilityConfidence)
      assert.equals(0, score.safetyTier)
    end)

  end)

  describe("compare", function()

    it("commitmentTier 2 beats commitmentTier 0 regardless of configuredPriority", function()
      local A = {
        safetyTier = 3, commitmentTier = 2, configuredPriority = 1,
        killCompletionScore = 0.5, attackContinuityScore = 0, reachabilityConfidence = 1.0,
        pathCost = 5, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local B = {
        safetyTier = 3, commitmentTier = 0, configuredPriority = 10,
        killCompletionScore = 0.5, attackContinuityScore = 0, reachabilityConfidence = 1.0,
        pathCost = 5, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local winner, reason = E.compare(A, B)
      assert.equals("A", winner)
      assert.equals("commitmentTier", reason)
    end)

    it("higher configuredPriority wins when tiers are equal", function()
      local A = {
        safetyTier = 3, commitmentTier = 0, configuredPriority = 10,
        killCompletionScore = 0.5, attackContinuityScore = 0, reachabilityConfidence = 1.0,
        pathCost = 5, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local B = {
        safetyTier = 3, commitmentTier = 0, configuredPriority = 3,
        killCompletionScore = 0.5, attackContinuityScore = 0, reachabilityConfidence = 1.0,
        pathCost = 5, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local winner, reason = E.compare(A, B)
      assert.equals("A", winner)
      assert.equals("configuredPriority", reason)
    end)

    it("lower pathCost wins when all else equal", function()
      local A = {
        safetyTier = 3, commitmentTier = 0, configuredPriority = 5,
        killCompletionScore = 0.5, attackContinuityScore = 0, reachabilityConfidence = 1.0,
        pathCost = 3, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local B = {
        safetyTier = 3, commitmentTier = 0, configuredPriority = 5,
        killCompletionScore = 0.5, attackContinuityScore = 0, reachabilityConfidence = 1.0,
        pathCost = 8, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local winner, reason = E.compare(A, B)
      assert.equals("A", winner)
      assert.equals("pathCost", reason)
    end)

  end)

  describe("shouldSwitch", function()

    it("returns false when current has commitmentTier 2 and candidate has commitmentTier 0", function()
      local current = {
        safetyTier = 2, commitmentTier = 2, configuredPriority = 5,
        killCompletionScore = 0.6, attackContinuityScore = 1.0, reachabilityConfidence = 1.0,
        pathCost = 3, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local candidate = {
        safetyTier = 3, commitmentTier = 0, configuredPriority = 10,
        killCompletionScore = 0.5, attackContinuityScore = 0.0, reachabilityConfidence = 1.0,
        pathCost = 2, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local result, reason = E.shouldSwitch(current, candidate)
      assert.is_false(result)
      assert.equals("committed_target_protection", reason)
    end)

    it("returns true when candidate has higher commitmentTier", function()
      local current = {
        safetyTier = 3, commitmentTier = 0, configuredPriority = 5,
        killCompletionScore = 0.5, attackContinuityScore = 1.0, reachabilityConfidence = 1.0,
        pathCost = 3, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local candidate = {
        safetyTier = 3, commitmentTier = 2, configuredPriority = 5,
        killCompletionScore = 0.5, attackContinuityScore = 0.0, reachabilityConfidence = 1.0,
        pathCost = 3, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local result, reason = E.shouldSwitch(current, candidate)
      assert.is_true(result)
      assert.equals("commitmentTier", reason)
    end)

    it("respects hysteresis margin - blocks when below margin", function()
      local current = {
        safetyTier = 3, commitmentTier = 0, configuredPriority = 5,
        killCompletionScore = 0.1, attackContinuityScore = 0.0, reachabilityConfidence = 1.0,
        pathCost = 3, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local candidate = {
        safetyTier = 3, commitmentTier = 0, configuredPriority = 5,
        killCompletionScore = 0.4, attackContinuityScore = 0.0, reachabilityConfidence = 1.0,
        pathCost = 3, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local result, reason = E.shouldSwitch(current, candidate, 0.5)
      assert.is_false(result)
      assert.equals("hysteresis", reason)
    end)

    it("respects hysteresis margin - allows when above margin", function()
      local current = {
        safetyTier = 3, commitmentTier = 0, configuredPriority = 5,
        killCompletionScore = 0.1, attackContinuityScore = 0.0, reachabilityConfidence = 1.0,
        pathCost = 3, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local candidate = {
        safetyTier = 3, commitmentTier = 0, configuredPriority = 5,
        killCompletionScore = 0.9, attackContinuityScore = 0.0, reachabilityConfidence = 1.0,
        pathCost = 3, tacticalUtility = 0.5, learnedUtility = 0.5,
      }
      local result, reason = E.shouldSwitch(current, candidate, 0.5)
      assert.is_true(result)
      assert.equals("killCompletionScore", reason)
    end)

  end)

end)
