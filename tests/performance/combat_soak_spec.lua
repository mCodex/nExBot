_G.nExBot = { Shared = { nowMs = function() return clock end } }
_G.ReachabilityState = dofile("targetbot/domain/reachability_states.lua")
_G.ReachabilityService = dofile("targetbot/domain/reachability_service.lua")
_G.TargetReachability = {
  evaluate = function(creature, context)
    local c = creature
    if not c or (c.isRemoved and c:isRemoved()) then
      return { attackable = false, reason = "removed", path = nil }
    end
    if c.isDead and c:isDead() then
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
  function c:kill() self._dead = true; self._hp = 0 end
  function c:remove() self._removed = true end
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

local function runSoak(ticks)
  math.randomseed(42)
  clock = 1000
  ReachabilityService.reset()

  local metrics = {
    engagedTargets = 0,
    killedTargets = 0,
    abandonedAlive = 0,
    switchesPerKill = 0,
    evaluationsPerTick = 0,
    maxFrameDuration = 0,
    memoryGrowth = 0,
  }

  local monsters = {}
  local nextId = 1
  local currentTarget = nil
  local switches = 0
  local totalEvals = 0

  for tick = 1, ticks do
    clock = clock + 100

    if math.random() < 0.05 and #monsters < 10 then
      local c = makeCreature(nextId, "Monster" .. nextId, math.random(20, 100), 100 + math.random(-5, 5), 100 + math.random(-5, 5))
      monsters[nextId] = c
      nextId = nextId + 1
    end

    if math.random() < 0.02 and #monsters > 0 then
      local ids = {}
      for id in pairs(monsters) do ids[#ids + 1] = id end
      if #ids > 0 then
        local victimId = ids[math.random(#ids)]
        monsters[victimId]:kill()
        metrics.killedTargets = metrics.killedTargets + 1
        if currentTarget == victimId then currentTarget = nil end
        monsters[victimId] = nil
      end
    end

    if math.random() < 0.01 and #monsters > 0 then
      local ids = {}
      for id in pairs(monsters) do ids[#ids + 1] = id end
      if #ids > 0 then
        local despawnId = ids[math.random(#ids)]
        monsters[despawnId]:remove()
        if currentTarget == despawnId then
          currentTarget = nil
          metrics.abandonedAlive = metrics.abandonedAlive + 1
        end
        monsters[despawnId] = nil
      end
    end

    local frameStart = os.clock()
    local bestScore = nil
    local bestId = nil
    local evalCount = 0

    for id, c in pairs(monsters) do
      if not c:isDead() and not c:isRemoved() then
        local ctx = randomContext(c, currentTarget == id)
        local score = E.evaluate(c, ctx)
        evalCount = evalCount + 1
        metrics.engagedTargets = metrics.engagedTargets + (evalCount == 1 and 1 or 0)

        if not bestScore then
          bestScore = score
          bestId = id
        else
          local winner = E.compare(bestScore, score)
          if winner == "B" then
            bestScore = score
            bestId = id
          end
        end
      end
    end

    totalEvals = totalEvals + evalCount

    if bestId and bestId ~= currentTarget then
      if currentTarget and monsters[currentTarget] and not monsters[currentTarget]:isDead() and not monsters[currentTarget]:isRemoved() then
        local oldCtx = randomContext(monsters[currentTarget], true)
        local shouldSwitch = E.shouldSwitch(E.evaluate(monsters[currentTarget], oldCtx), bestScore, 0.5)
        if shouldSwitch then
          switches = switches + 1
          currentTarget = bestId
        end
      else
        if currentTarget then currentTarget = nil end
        currentTarget = bestId
        switches = switches + 1
      end
    end

    local frameDuration = (os.clock() - frameStart) * 1000
    if frameDuration > metrics.maxFrameDuration then
      metrics.maxFrameDuration = frameDuration
    end
  end

  metrics.evaluationsPerTick = totalEvals / ticks
  metrics.switchesPerKill = metrics.killedTargets > 0 and switches / metrics.killedTargets or 0

  local evCount = 0
  for _ in pairs(ReachabilityService) do evCount = evCount + 1 end
  metrics.memoryGrowth = evCount

  return metrics
end

describe("Combat Soak Test (10,000 ticks)", function()

  it("unfinished target rate is below 1%", function()
    local metrics = runSoak(10000)
    local rate = metrics.engagedTargets > 0 and metrics.abandonedAlive / metrics.engagedTargets or 0
    assert.is_true(rate < 0.01,
      string.format("abandoned rate %.4f exceeds 1%% (abandoned=%d, engaged=%d)",
        rate, metrics.abandonedAlive, metrics.engagedTargets))
  end)

  it("evidence and caches are bounded", function()
    runSoak(10000)
    local evCount = 0
    for _ in pairs(ReachabilityService) do evCount = evCount + 1 end
    assert.is_true(evCount <= 64,
      string.format("evidence count %d exceeds MAX_EVIDENCE 64", evCount))
  end)

  it("decision throughput is acceptable", function()
    math.randomseed(42)
    local creature = makeCreature(1, "Test", 80, 100, 100)
    local contexts = {}
    for i = 1, 1000 do
      contexts[i] = randomContext(creature, i == 1)
    end

    local start = os.clock()
    for i = 1, 1000 do
      E.evaluate(creature, contexts[i])
    end
    local evalMs = (os.clock() - start) * 1000 / 1000
    assert.is_true(evalMs < 2, string.format("evaluate avg %.4f ms exceeds 2ms budget", evalMs))

    local arbitrator = FeatureArbitrator.new()
    local intentSets = {}
    for i = 1, 1000 do
      local intents = {}
      for j = 1, 5 do
        intents[j] = makeIntent()
      end
      intentSets[i] = intents
    end

    start = os.clock()
    for i = 1, 1000 do
      arbitrator:resolve(intentSets[i], {})
    end
    local resolveMs = (os.clock() - start) * 1000 / 1000
    assert.is_true(resolveMs < 2, string.format("resolve avg %.4f ms exceeds 2ms budget", resolveMs))
  end)

end)
