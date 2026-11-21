local function loadModule()
  _G.IntelligenceEventAggregator = nil
  dofile("core/intelligence/foundation/event_aggregator.lua")
  return IntelligenceEventAggregator.new({ now = function() return 1234 end, maxEvents = 2 })
end

describe("Intelligence Event Aggregator", function()
  it("publishes normalized events in deterministic priority order", function()
    local events = loadModule()
    local received = {}

    events:subscribe("CreatureObserved", function(event)
      received[#received + 1] = "low:" .. event.payload.id
    end, 1)
    events:subscribe("CreatureObserved", function(event)
      received[#received + 1] = "high:" .. event.payload.id
    end, 10)

    local event = events:publish("CreatureObserved", { id = 7 }, {
      source = "TargetBot",
      snapshotGeneration = 3,
    })

    assert.same({ "high:7", "low:7" }, received)
    assert.same({
      type = "CreatureObserved",
      timestamp = 1234,
      source = "TargetBot",
      snapshotGeneration = 3,
      routeGeneration = 0,
      combatGeneration = 0,
      payload = { id = 7 },
    }, event)
  end)

  it("rejects stale generations and bounds retained events", function()
    local events = loadModule()
    events:setGenerations({ snapshot = 2, route = 4, combat = 6 })

    local event, reason = events:publish("PathResolved", {}, {
      source = "CaveBot",
      routeGeneration = 3,
    })
    assert.is_nil(event)
    assert.equals("stale_route_generation", reason)

    events:publish("A", {}, { source = "test" })
    events:publish("B", {}, { source = "test" })
    events:publish("C", {}, { source = "test" })
    assert.equals(2, #events:recent())
    assert.equals("B", events:recent()[1].type)
  end)

  it("requires bounded event metadata", function()
    local events = loadModule()
    assert.has_error(function()
      events:publish("CreatureObserved", {}, {})
    end, "event source is required")
  end)

  it("isolates immutable event values and handler failures", function()
    local events = loadModule()
    local observed
    events:subscribe("A", function(event)
      event.payload.nested.value = 9
      error("broken consumer")
    end, 10)
    events:subscribe("A", function(event) observed = event.payload.nested.value end)

    assert.has_no.errors(function()
      events:publish("A", { nested = { value = 1 } }, { source = "test" })
    end)
    assert.equals(1, observed)
    assert.equals(1, events:recent()[1].payload.nested.value)
  end)

  it("notifies wildcard subscribers for every published event type", function()
    local events = loadModule()
    local seen = {}
    events:subscribeAll(function(event) seen[#seen + 1] = event.type end)

    events:publish("A", {}, { source = "test" })
    events:publish("B", {}, { source = "test" })

    assert.same({ "A", "B" }, seen)
  end)

  it("stops notifying a wildcard subscriber once unsubscribed", function()
    local events = loadModule()
    local seen = {}
    local unsubscribe = events:subscribeAll(function(event) seen[#seen + 1] = event.type end)

    events:publish("A", {}, { source = "test" })
    unsubscribe()
    events:publish("B", {}, { source = "test" })

    assert.same({ "A" }, seen)
  end)

  it("isolates wildcard handler failures from typed listeners", function()
    local events = loadModule()
    local observed
    events:subscribeAll(function() error("broken wildcard consumer") end)
    events:subscribe("A", function(event) observed = event.payload.value end)

    assert.has_no.errors(function()
      events:publish("A", { value = 5 }, { source = "test" })
    end)
    assert.equals(5, observed)
  end)
end)
