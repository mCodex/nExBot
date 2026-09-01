local SnapshotBuilder = dofile("core/intelligence/foundation/snapshot_builder.lua")
local FeaturePipeline = dofile("core/intelligence/foundation/feature_pipeline.lua")
local DecisionEngine = dofile("core/intelligence/decisions/decision_engine.lua")
local TacticalMemory = dofile("core/intelligence/learning/tactical_memory.lua")
local Metrics = dofile("core/intelligence/foundation/metrics.lua")

local COUNTS = { 1, 10, 50, 100 }
local ITERATIONS = tonumber(os.getenv("Intelligence_BENCH_ITERATIONS")) or 1000

local function creatures(count)
  local result = {}
  for id = count, 1, -1 do
    result[#result + 1] = {
      id = id,
      name = "Creature " .. id,
      healthPercent = id % 100,
      position = { x = 100 + id % 15, y = 100 + id % 11, z = 7 },
    }
  end
  return result
end

local function proposals(count)
  local result = {}
  for id = 1, count do
    result[id] = {
      id = id,
      safety = id % 2,
      priority = id % 7,
      confidence = (id % 10) / 10,
      utility = (id % 13) / 13,
      snapshotGeneration = 1,
    }
  end
  return result
end

local player = {
  id = 0, health = 900, maxHealth = 1000, mana = 400, maxMana = 500,
  position = { x = 100, y = 100, z = 7 },
}

local function benchmark(count)
  local sources = creatures(count)
  local choices = proposals(count)
  local builder = SnapshotBuilder.new({ now = function() return 1 end, getSpectators = function() return sources end })
  local features = FeaturePipeline.new({ maxCreatures = 100 })
  local decisions = DecisionEngine.new({ now = function() return 1 end })
  local started = os.clock()
  local selected
  for _ = 1, ITERATIONS do
    local snapshot = builder:build({ generation = 1, player = player })
    local vector = features:extractCombat(snapshot, { targetId = 1 })
    selected = decisions:select(choices, { snapshot = 1 })
    assert(#snapshot.creatures == count and #vector.values == 17 and selected, "pipeline result changed")
  end
  return (os.clock() - started) * 1000 / ITERATIONS
end

local function checkBoundedStores()
  local memory = TacticalMemory.new({ maxEntries = 100, ttlMs = 100000 })
  local metrics = Metrics.new(100)
  for index = 1, 1000 do
    memory:remember("tile-" .. index, index, index)
    metrics:sample("tick", index)
  end
  assert(memory.size == 100, "tactical memory exceeded maxEntries")
  assert(#metrics:snapshot().samples.tick == 100, "metrics exceeded maxSamples")
end

assert(ITERATIONS >= 1, "Intelligence_BENCH_ITERATIONS must be positive")
checkBoundedStores()
print(string.format("Lua %s | %d iterations per size", _VERSION, ITERATIONS))
print("creatures\tmean_ms")
for _, count in ipairs(COUNTS) do
  print(string.format("%d\t%.6f", count, benchmark(count)))
end
print("bounded stores: PASS (100 retained after 1000 writes)")

