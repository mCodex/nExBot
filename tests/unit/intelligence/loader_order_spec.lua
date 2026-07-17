describe("intelligence loader foundation", function()
  it("loads UnifiedTick before EventBus so the bus cannot create fallback macros", function()
    local file = assert(io.open("_Loader.lua", "r"))
    local source = file:read("*a")
    file:close()

    local tick = assert(source:find('"unified_tick"', 1, true))
    local eventBus = assert(source:find('"event_bus"', 1, true))
    assert.is_true(tick < eventBus)
  end)

  it("exports shared modules because the OTClient loader discards return values", function()
    local tick = assert(io.open("core/unified_tick.lua", "r")):read("*a")
    local ring = assert(io.open("utils/ring_buffer.lua", "r")):read("*a")
    assert.is_truthy(tick:find("UnifiedTick = {}", 1, true))
    assert.is_truthy(ring:find("nExBot.RingBuffer = RingBuffer", 1, true))
  end)

  it("uses the client-safe clock and the canonical tick registration shape", function()
    for _, path in ipairs({
      "core/intelligence/foundation/event_aggregator.lua",
      "core/intelligence/foundation/tactical_blackboard.lua",
      "core/intelligence/foundation/snapshot_builder.lua",
      "core/intelligence/decisions/decision_engine.lua",
    }) do
      local source = assert(io.open(path, "r")):read("*a")
      assert.is_nil(source:find("g_clock", 1, true), path)
    end
    for _, path in ipairs({
      "targetbot/monster_scenario.lua", "targetbot/monster_ai.lua", "targetbot/monster_reachability.lua",
    }) do
      local source = assert(io.open(path, "r")):read("*a")
      assert.is_nil(source:find("UnifiedTick.register({", 1, true), path)
    end
  end)
end)
