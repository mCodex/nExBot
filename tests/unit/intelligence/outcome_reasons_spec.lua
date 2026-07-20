local Reasons = dofile("core/intelligence/contracts/outcome_reasons.lua")

describe("IntelligenceOutcomeReasons", function()
  describe("ClosureReason enum", function()
    local all_reasons = Reasons.all()

    it("has exactly 20 closure reasons", function()
      assert.equals(20, #all_reasons)
    end)

    it("includes all expected closure reasons", function()
      local expected = {
        "completed", "target_killed", "target_lost", "target_unreachable",
        "player_override", "bot_disabled", "route_changed", "profile_changed",
        "reconnect", "game_end", "timeout", "safety_abort",
        "insufficient_capacity", "container_unavailable", "corpse_expired",
        "loot_completed", "loot_skipped_by_policy", "teleport_or_floor_change",
        "generation_mismatch", "invalidated",
      }
      for _, reason in ipairs(expected) do
        assert.is_true(Reasons.isValid(reason), "expected valid: " .. reason)
      end
    end)

    it("returns a sorted list from all()", function()
      local sorted = {}
      for _, r in ipairs(all_reasons) do table.insert(sorted, r) end
      table.sort(sorted)
      assert.same(sorted, all_reasons)
    end)
  end)

  describe("isValid", function()
    it("returns true for all known reasons", function()
      for _, reason in ipairs(Reasons.all()) do
        assert.is_true(Reasons.isValid(reason))
      end
    end)

    it("rejects unknown reason", function()
      assert.is_false(Reasons.isValid("banana"))
    end)

    it("rejects nil", function()
      assert.is_false(Reasons.isValid(nil))
    end)

    it("rejects empty string", function()
      assert.is_false(Reasons.isValid(""))
    end)

    it("rejects non-string", function()
      assert.is_false(Reasons.isValid(123))
    end)
  end)

  describe("isAmbiguous", function()
    local ambiguous = {
      reconnect = true, player_override = true, game_end = true,
      teleport_or_floor_change = true, invalidated = true,
    }

    it("identifies all ambiguous reasons", function()
      for reason, _ in pairs(ambiguous) do
        assert.is_true(Reasons.isAmbiguous(reason), "expected ambiguous: " .. reason)
      end
    end)

    it("returns false for non-ambiguous valid reasons", function()
      for _, reason in ipairs(Reasons.all()) do
        if not ambiguous[reason] then
          assert.is_false(Reasons.isAmbiguous(reason), "expected not ambiguous: " .. reason)
        end
      end
    end)

    it("returns false for unknown reasons", function()
      assert.is_false(Reasons.isAmbiguous("banana"))
      assert.is_false(Reasons.isAmbiguous(nil))
      assert.is_false(Reasons.isAmbiguous(""))
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceOutcomeReasons", function()
      assert.is_not_nil(nExBot.IntelligenceOutcomeReasons)
      assert.is_function(nExBot.IntelligenceOutcomeReasons.isValid)
    end)
  end)
end)
