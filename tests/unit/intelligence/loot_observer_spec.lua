dofile("core/intelligence/contracts/event_schema.lua")
local Factory = dofile("core/intelligence/contracts/event_factory.lua")
local LootObserver = dofile("core/intelligence/observability/loot_observer.lua")

local validContext = { source = "Test", sessionId = "s1", characterKey = "char1" }
local metadata = {
  timestamp = 100,
  latencyClass = 1,
  observationQuality = 0.9,
  confidence = 0.8,
  correlationId = "combat-1",
}

describe("IntelligenceLootObserver", function()
  local factory

  before_each(function()
    factory = Factory.new({ schema = nExBot.IntelligenceEventSchema })
  end)

  describe("new", function()
    it("returns an observer instance", function()
      local observer = LootObserver.new()
      assert.is_not_nil(observer)
      assert.is_function(observer.observe)
      assert.is_function(observer.recent)
      assert.is_function(observer.captureRate)
    end)

    it("registers globally", function()
      assert.is_not_nil(nExBot.IntelligenceLootObserver)
    end)
  end)

  describe("observe (backward compat)", function()
    it("accepts observation without factory", function()
      local observer = LootObserver.new()
      local result = observer:observe({
        monsterId = 1, corpseId = 2, itemsAvailable = 3, itemsCaptured = 2,
        items = { { id = 3031, count = 10 } },
        timestamp = 100, latencyClass = 1, observationQuality = 0.9,
        confidence = 0.8, correlationId = "c1",
      })
      assert.is_not_nil(result)
      assert.equals(1, #observer:recent())
    end)

    it("normalizes items correctly", function()
      local observer = LootObserver.new()
      local result = observer:observe({
        monsterId = 1, corpseId = 2, itemsAvailable = 2, itemsCaptured = 1,
        items = { { id = 3031, count = 10 }, { id = 3032, count = 5 } },
        timestamp = 100, latencyClass = 1, observationQuality = 0.9,
        confidence = 0.8, correlationId = "c1",
      })
      assert.equals(2, #result.items)
      assert.equals(3031, result.items[1].id)
      assert.equals(10, result.items[1].count)
    end)

    it("rejects observation with missing metadata", function()
      local observer = LootObserver.new()
      local result, err = observer:observe({ monsterId = 1 })
      assert.is_nil(result)
      assert.equals("missing_timestamp", err)
    end)
  end)

  describe("observe with event emission", function()
    it("emits loot_item_observed for each item when factory is set", function()
      local observer = LootObserver.new(500, 100, factory, validContext)
      local emitted = {}
      local originalCreate = factory.create
      factory.create = function(self, typeName, data, ctx)
        local event = originalCreate(self, typeName, data, ctx)
        if event then table.insert(emitted, event) end
        return event
      end

      observer:observe({
        monsterId = 1, corpseId = 2, itemsAvailable = 2, itemsCaptured = 1,
        items = { { id = 3031, count = 10 }, { id = 3032, count = 5 } },
        lootEpisodeId = "le1",
        timestamp = 100, latencyClass = 1, observationQuality = 0.9,
        confidence = 0.8, correlationId = "c1",
      })

      assert.equals(2, #emitted)
      assert.equals("loot_item_observed", emitted[1].type)
      assert.equals("le1", emitted[1].lootEpisodeId)
      assert.equals(3031, emitted[1].itemId)
      assert.equals("loot_item_observed", emitted[2].type)
      assert.equals(3032, emitted[2].itemId)
    end)

    it("does not emit when no factory is set", function()
      local observer = LootObserver.new()
      observer:observe({
        monsterId = 1, corpseId = 2, itemsAvailable = 1, itemsCaptured = 1,
        items = { { id = 3031, count = 10 } },
        lootEpisodeId = "le1",
        timestamp = 100, latencyClass = 1, observationQuality = 0.9,
        confidence = 0.8, correlationId = "c1",
      })
      assert.equals(1, #observer:recent())
    end)
  end)

  describe("moveAttempted", function()
    it("emits loot_move_attempted event", function()
      local observer = LootObserver.new(500, 100, factory, validContext)
      local emitted = {}
      local originalCreate = factory.create
      factory.create = function(self, typeName, data, ctx)
        local event = originalCreate(self, typeName, data, ctx)
        if event then table.insert(emitted, event) end
        return event
      end

      local event = observer:moveAttempted("le1", 3031)
      assert.is_not_nil(event)
      assert.equals("loot_move_attempted", event.type)
      assert.equals("le1", event.lootEpisodeId)
      assert.equals(3031, event.itemId)
      assert.equals(1, #emitted)
    end)

    it("returns nil without factory", function()
      local observer = LootObserver.new()
      local event = observer:moveAttempted("le1", 3031)
      assert.is_nil(event)
    end)
  end)

  describe("moveVerified", function()
    it("emits loot_move_verified event", function()
      local observer = LootObserver.new(500, 100, factory, validContext)
      local emitted = {}
      local originalCreate = factory.create
      factory.create = function(self, typeName, data, ctx)
        local event = originalCreate(self, typeName, data, ctx)
        if event then table.insert(emitted, event) end
        return event
      end

      local event = observer:moveVerified("le1", 3031, true)
      assert.is_not_nil(event)
      assert.equals("loot_move_verified", event.type)
      assert.equals("le1", event.lootEpisodeId)
      assert.equals(3031, event.itemId)
      assert.is_true(event.captured)
      assert.equals(1, #emitted)
    end)

    it("returns nil without factory", function()
      local observer = LootObserver.new()
      local event = observer:moveVerified("le1", 3031, false)
      assert.is_nil(event)
    end)
  end)

  describe("event structure", function()
    it("includes canonical event fields", function()
      local observer = LootObserver.new(500, 100, factory, validContext)
      observer:observe({
        monsterId = 1, corpseId = 2, itemsAvailable = 1, itemsCaptured = 1,
        items = { { id = 3031, count = 10 } },
        lootEpisodeId = "le1",
        timestamp = 100, latencyClass = 1, observationQuality = 0.9,
        confidence = 0.8, correlationId = "c1",
      })
      local event = observer:moveAttempted("le1", 3031)
      assert.matches("^evt:", event.eventId)
      assert.is_number(event.timestamp)
      assert.equals("Test", event.source)
      assert.equals("s1", event.sessionId)
      assert.equals("char1", event.characterKey)
      assert.matches("^idem:", event.idempotencyKey)
    end)
  end)

  describe("captureRate", function()
    it("calculates correctly", function()
      local observer = LootObserver.new()
      observer:observe({
        monsterId = 1, corpseId = 2, itemsAvailable = 3, itemsCaptured = 2,
        timestamp = 100, latencyClass = 1, observationQuality = 0.9,
        confidence = 0.8, correlationId = "c1",
      })
      assert.near(2/3, observer:captureRate(), 1e-9)
    end)
  end)
end)
