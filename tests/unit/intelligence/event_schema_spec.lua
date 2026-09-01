local Schema = dofile("core/intelligence/contracts/event_schema.lua")

describe("IntelligenceEventSchema", function()
  describe("schema version", function()
    it("has SCHEMA_VERSION >= 1", function()
      assert.is_number(Schema.SCHEMA_VERSION)
      assert.is_true(Schema.SCHEMA_VERSION >= 1)
    end)
  end)

  describe("TYPES enum", function()
    it("has exactly 25 event types", function()
      local count = 0
      for _ in pairs(Schema.TYPES) do count = count + 1 end
      assert.equals(25, count)
    end)

    it("includes all expected types", function()
      local expected = {
        "decision_created", "decision_selected", "decision_rejected",
        "action_started", "action_progress", "action_completed", "action_failed",
        "encounter_started", "encounter_updated", "encounter_closed",
        "loot_episode_started", "loot_item_observed", "loot_move_attempted",
        "loot_move_verified", "loot_episode_closed",
        "route_segment_started", "route_segment_progress", "route_segment_closed",
        "hunt_started", "hunt_closed",
        "resource_delta", "player_intervention",
        "model_prediction", "model_observation", "guardrail_triggered",
      }
      for _, name in ipairs(expected) do
        assert.is_not_nil(Schema.TYPES[name], "missing type: " .. name)
      end
    end)
  end)

  describe("isValidType", function()
    it("returns true for all known types", function()
      for name in pairs(Schema.TYPES) do
        assert.is_true(Schema.isValidType(name), "expected valid: " .. name)
      end
    end)

    it("rejects unknown type", function()
      assert.is_false(Schema.isValidType("banana"))
    end)

    it("rejects nil", function()
      assert.is_false(Schema.isValidType(nil))
    end)

    it("rejects empty string", function()
      assert.is_false(Schema.isValidType(""))
    end)

    it("rejects non-string", function()
      assert.is_false(Schema.isValidType(123))
    end)
  end)

  describe("requiredFieldsFor", function()
    local COMMON_FIELDS = {
      eventId = true, timestamp = true, schemaVersion = true,
      source = true, sessionId = true, characterKey = true,
    }

    it("includes common fields for every type", function()
      for name in pairs(Schema.TYPES) do
        local fields = Schema.requiredFieldsFor(name)
        assert.is_table(fields, "expected table for " .. name)
        local as_set = {}
        for _, f in ipairs(fields) do as_set[f] = true end
        for _, f in ipairs({"eventId", "timestamp", "schemaVersion", "source", "sessionId", "characterKey"}) do
          assert.is_true(as_set[f] ~= nil,
            "common field '" .. f .. "' missing from " .. name)
        end
      end
    end)

    it("returns 6 common fields for types with no extra fields", function()
      local fields = Schema.requiredFieldsFor("encounter_updated")
      assert.equals(6, #fields)
    end)

    it("includes type-specific fields", function()
      local fields = Schema.requiredFieldsFor("decision_created")
      local as_set = {}
      for _, f in ipairs(fields) do as_set[f] = true end
      assert.is_true(as_set["decisionId"] ~= nil)
      assert.is_true(as_set["decisionType"] ~= nil)
      assert.is_true(as_set["candidates"] ~= nil)
    end)

    it("returns nil for unknown type", function()
      assert.is_nil(Schema.requiredFieldsFor("banana"))
    end)
  end)

  describe("hasField", function()
    it("returns true for common fields", function()
      assert.is_true(Schema.hasField("action_started", "eventId"))
      assert.is_true(Schema.hasField("action_started", "timestamp"))
    end)

    it("returns true for type-specific fields", function()
      assert.is_true(Schema.hasField("action_started", "actionId"))
      assert.is_true(Schema.hasField("action_started", "decisionId"))
      assert.is_true(Schema.hasField("action_started", "actionType"))
    end)

    it("returns false for fields not required by the type", function()
      assert.is_false(Schema.hasField("action_started", "outcome"))
      assert.is_false(Schema.hasField("encounter_started", "actionId"))
    end)

    it("returns false for unknown types", function()
      assert.is_false(Schema.hasField("banana", "eventId"))
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceEventSchema", function()
      assert.is_not_nil(nExBot.IntelligenceEventSchema)
      assert.is_function(nExBot.IntelligenceEventSchema.isValidType)
    end)
  end)
end)
