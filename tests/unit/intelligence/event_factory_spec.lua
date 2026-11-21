local Schema = dofile("core/intelligence/contracts/event_schema.lua")
local Factory = dofile("core/intelligence/contracts/event_factory.lua")

describe("IntelligenceEventFactory", function()
  local factory

  before_each(function()
    factory = Factory.new({ schema = Schema })
  end)

  describe("new", function()
    it("creates a factory with schema", function()
      assert.is_not_nil(factory)
      assert.is_function(factory.create)
      assert.is_function(factory.validate)
      assert.is_function(factory.getErrors)
    end)
  end)

  describe("create", function()
    local validContext = { source = "Test", sessionId = "s1", characterKey = "char1" }

    it("creates a valid event with auto-generated fields", function()
      local event = factory:create("decision_created", {
        decisionId = "d1",
        decisionType = "target",
        candidates = { "a", "b" },
      }, validContext)

      assert.is_not_nil(event)
      assert.matches("^evt:", event.eventId)
      assert.equals("decision_created", event.type)
      assert.is_number(event.timestamp)
      assert.equals(Schema.SCHEMA_VERSION, event.schemaVersion)
      assert.equals("Test", event.source)
      assert.equals("s1", event.sessionId)
      assert.equals("char1", event.characterKey)
      assert.matches("^idem:", event.idempotencyKey)
    end)

    it("returns nil for invalid type", function()
      local event = factory:create("banana", {}, validContext)
      assert.is_nil(event)
      local errors = factory:getErrors()
      assert.is_not_nil(errors)
      assert.is_true(#errors > 0)
    end)

    it("returns nil for missing required fields", function()
      local event = factory:create("decision_created", {}, validContext)
      assert.is_nil(event)
    end)

    it("returns nil for missing context fields", function()
      local event = factory:create("decision_created", {
        decisionId = "d1",
        decisionType = "target",
        candidates = { "a" },
      }, { source = "Test" })
      assert.is_nil(event)
    end)

    it("generates unique event IDs", function()
      local e1 = factory:create("encounter_updated", {}, validContext)
      local e2 = factory:create("encounter_updated", {}, validContext)
      assert.is_not_equal(e1.eventId, e2.eventId)
    end)

    it("merges data fields into event", function()
      local event = factory:create("action_completed", {
        actionId = "a1",
        outcome = { success = true },
      }, validContext)

      assert.equals("a1", event.actionId)
      assert.same({ success = true }, event.outcome)
    end)

    it("rejects NaN in numeric fields", function()
      local event = factory:create("resource_delta", {
        resourceType = "gold",
        delta = 0 / 0,
      }, validContext)
      assert.is_nil(event)
    end)

    it("rejects Infinity in numeric fields", function()
      local event = factory:create("resource_delta", {
        resourceType = "gold",
        delta = math.huge,
      }, validContext)
      assert.is_nil(event)
    end)

    it("rejects negative Infinity in numeric fields", function()
      local event = factory:create("resource_delta", {
        resourceType = "gold",
        delta = -math.huge,
      }, validContext)
      assert.is_nil(event)
    end)
  end)

  describe("validate", function()
    it("returns true for a well-formed event", function()
      local event = {
        eventId = "evt:1:1",
        type = "decision_created",
        timestamp = 1234567890,
      }
      assert.is_true(factory:validate(event))
    end)

    it("returns false for nil event", function()
      assert.is_false(factory:validate(nil))
    end)

    it("returns false for missing eventId", function()
      assert.is_false(factory:validate({ type = "action_started", timestamp = 1 }))
    end)

    it("returns false for missing type", function()
      assert.is_false(factory:validate({ eventId = "e1", timestamp = 1 }))
    end)

    it("returns false for missing timestamp", function()
      assert.is_false(factory:validate({ eventId = "e1", type = "action_started" }))
    end)

    it("returns false for invalid type", function()
      assert.is_false(factory:validate({
        eventId = "e1", type = "banana", timestamp = 1,
      }))
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceEventFactory", function()
      assert.is_not_nil(nExBot.IntelligenceEventFactory)
    end)
  end)
end)
