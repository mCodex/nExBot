_G.nExBot = { Shared = { nowMs = function() return clock end } }
_G.ReachabilityState = dofile("targetbot/domain/reachability_states.lua")
_G.ReachabilityService = dofile("targetbot/domain/reachability_service.lua")
_G.TargetReachability = {
  evaluate = function(creature, context)
    if not creature or (creature.isRemoved and creature:isRemoved()) then
      return { attackable = false, reason = "removed", path = nil }
    end
    if creature.isDead and creature:isDead() then
      return { attackable = false, reason = "removed", path = nil }
    end
    return { attackable = true, reason = "in_range", path = { 1 } }
  end
}
_G.SafeCreature = {
  getId = function(c) return c and c.getId and c:getId() or nil end,
  getPosition = function(c) return c and c.getPosition and c:getPosition() or nil end,
}
_G.player = { getId = function() return 99999 end, getPosition = function() return { x = 100, y = 100, z = 7 } end }

local E = dofile("targetbot/domain/target_evaluator.lua")
local FeatureArbitrator = dofile("targetbot/domain/feature_arbitrator.lua")
local KillCompletionModel = dofile("targetbot/ml/kill_completion_model.lua")

local clock = 1000

local function pos(x, y, z) return { x = x, y = y, z = z or 7 } end

local function makeCreature(id, name, hp, x, y)
  local c = {
    _id = id, _name = name, _hp = hp or 100,
    _position = pos(x or 100 + (id % 10), y or 100 + (id % 10)),
    _dead = false, _removed = false,
  }
  function c:getId() return self._id end
  function c:getName() return self._name end
  function c:getPosition() return self._position end
  function c:getHealthPercent() return self._dead and 0 or self._hp end
  function c:isDead() return self._dead or self._hp <= 0 end
  function c:isRemoved() return self._removed end
  function c:isMonster() return true end
  return c
end

local states = {
  ReachabilityState.ATTACKABLE_NOW,
  ReachabilityState.REPOSITION_REQUIRED,
  ReachabilityState.TEMPORARILY_BLOCKED,
}

local function randomContext(creature, isCurrent)
  local state = states[math.random(#states)]
  return {
    config = { priority = math.random(1, 10) },
    isCurrentTarget = isCurrent,
    commitment = math.random() < 0.3 and { targetId = creature:getId(), reason = "ENGAGEMENT" } or nil,
    reachabilityState = state,
    reachabilityPath = { 1, 2, math.random(1, 5) },
    playerHpPercent = math.random(20, 100),
    creatureHpPercent = creature:getHealthPercent(),
  }
end

local function makeIntent()
  local sources = { "CHASE", "LURE", "KEEP_DISTANCE", "REPOSITION", "PULL", "FINISH_KILL_COMMITMENT", "WAVE_AVOIDANCE", "ROUTE_ADVANCEMENT" }
  return {
    source = sources[math.random(#sources)],
    type = "movement",
    confidence = math.random() * 0.8 + 0.2,
    position = { x = 100 + math.random(-5, 5), y = 100 + math.random(-5, 5), z = 7 },
  }
end

local function percentile(sorted, p)
  local idx = math.ceil(#sorted * p / 100)
  return sorted[math.max(1, math.min(idx, #sorted))]
end

print(string.format("Lua %s | Hot Path Benchmarks", _VERSION))
print(string.rep("=", 60))

print("\n1. TargetCandidateEvaluator.evaluate benchmark")
print(string.rep("-", 60))
math.randomseed(42)
local creature = makeCreature(1, "Test", 80, 100, 100)
local contexts = {}
for i = 1, 100 do
  contexts[i] = randomContext(creature, i == 1)
end

local timings = {}
for i = 1, 100 do
  local start = os.clock()
  E.evaluate(creature, contexts[i])
  timings[i] = (os.clock() - start) * 1000
end

table.sort(timings)
local min, max, sum = timings[1], timings[#timings], 0
for _, t in ipairs(timings) do sum = sum + t end
print(string.format("  Iterations: 100"))
print(string.format("  Min:  %.4f ms", min))
print(string.format("  Max:  %.4f ms", max))
print(string.format("  Avg:  %.4f ms", sum / #timings))
print(string.format("  P95:  %.4f ms", percentile(timings, 95)))
print(string.format("  P99:  %.4f ms", percentile(timings, 99)))

print("\n2. FeatureArbitrator.resolve benchmark")
print(string.rep("-", 60))
math.randomseed(42)
local arbitrator = FeatureArbitrator.new()
local sizes = { 1, 3, 5, 10 }
local iterations = 1000

print(string.format("  %-10s %-15s", "Intents", "Avg (ms)"))
for _, size in ipairs(sizes) do
  local intentSets = {}
  for i = 1, iterations do
    local intents = {}
    for j = 1, size do
      intents[j] = makeIntent()
    end
    intentSets[i] = intents
  end

  local start = os.clock()
  for i = 1, iterations do
    arbitrator:resolve(intentSets[i], {})
  end
  local avgMs = (os.clock() - start) * 1000 / iterations
  print(string.format("  %-10d %-15.4f", size, avgMs))
end

print("\n3. ReachabilityService evidence accumulation benchmark")
print(string.rep("-", 60))
math.randomseed(42)
ReachabilityService.reset()
clock = 1000

local creatures = {}
for i = 1, 100 do
  creatures[i] = makeCreature(i, "Creature" .. i, math.random(20, 100), 100 + i % 10, 100 + i % 10)
end

local start = os.clock()
for _, c in ipairs(creatures) do
  for _ = 1, 5 do
    clock = clock + 100
    ReachabilityService.evaluate(c, {})
  end
end
local totalMs = (os.clock() - start) * 1000
local evalCount = 100 * 5
print(string.format("  Creatures: 100"))
print(string.format("  Evaluations per creature: 5"))
print(string.format("  Total evaluations: %d", evalCount))
print(string.format("  Total time: %.4f ms", totalMs))
print(string.format("  Per-evaluation: %.4f ms", totalMs / evalCount))

print("\n4. ML prediction benchmark")
print(string.rep("-", 60))
math.randomseed(42)
local model = KillCompletionModel.new()

for i = 1, 100 do
  local features = {
    targetHp = math.random() * 0.5,
    distance = math.random() * 0.3,
    hasLOS = math.random(0, 1),
    isCurrentTarget = math.random(0, 1),
  }
  model:observe(math.random() < 0.5, features)
end

local featureSets = {}
for i = 1, 1000 do
  featureSets[i] = {
    targetHp = math.random() * 0.5,
    distance = math.random() * 0.3,
    hasLOS = math.random(0, 1),
    isCurrentTarget = math.random(0, 1),
  }
end

start = os.clock()
for i = 1, 1000 do
  model:predict(featureSets[i])
end
local predMs = (os.clock() - start) * 1000 / 1000
print(string.format("  Samples observed: 100"))
print(string.format("  Predictions: 1000"))
print(string.format("  Per-prediction: %.4f ms", predMs))

print("\n" .. string.rep("=", 60))
print("Benchmark complete")
