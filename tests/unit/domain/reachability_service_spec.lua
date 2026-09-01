local clock
local player
local paths
local shots

local function pos(x, y, z) return { x = x, y = y, z = z or 7 } end

local function creature(id, x, y, z)
  local c = { id = id, position = pos(x, y, z), dead = false }
  function c:getId() return self.id end
  function c:getName() return "Monster " .. self.id end
  function c:getPosition() return self.position end
  function c:isDead() return self.dead end
  function c:isRemoved() return false end
  function c:isMonster() return true end
  function c:getHealthPercent() return self.dead and 0 or 100 end
  return c
end

local function key(p) return string.format("%d,%d,%d", p.x, p.y, p.z) end

local function loadModules()
  clock = 1000
  player = { position = pos(100, 100) }
  function player:getPosition() return self.position end
  paths, shots = {}, {}

  _G.now = clock
  _G.player = player
  _G.nExBot = {
    Shared = {
      nowMs = function() return clock end,
      getClient = function() return _G.g_game end,
    },
    zChanging = function() return false end,
  }
  _G.SafeCreature = {
    getId = function(c) return c:getId() end,
    getName = function(c) return c:getName() end,
    getPosition = function(c) return c:getPosition() end,
    getHealthPercent = function(c) return c:getHealthPercent() end,
    isDead = function(c) return c:isDead() end,
    isRemoved = function(c) return c:isRemoved() end,
    isMonster = function(c) return c:isMonster() end,
  }
  _G.g_game = { getLocalPlayer = function() return player end }
  _G.findPath = function(_, destination, _, profile)
    local ring = tostring(profile.marginMin or 0) .. ":" .. tostring(profile.marginMax or 0)
    return paths[key(destination) .. ":" .. ring]
  end
  _G.g_map = {
    isSightClear = function(from, destination)
      return shots[key(from) .. ">" .. key(destination)] ~= false
    end,
  }
  _G.EventBus = nil
  _G.UnifiedTick = nil
  _G.macro = function() end
  _G.MonsterAI = { _helpers = {} }

  _G.TargetReachability = nil
  _G.ReachabilityState = dofile("targetbot/domain/reachability_states.lua")
  dofile("targetbot/monster_reachability.lua")
  return dofile("targetbot/domain/reachability_service.lua")
end

describe("ReachabilityService", function()
  local service

  before_each(function() service = loadModules() end)

  it("returns ATTACKABLE_NOW for reachable creatures", function()
    local target = creature(1, 101, 100)
    local result = service.evaluate(target, { mode = "melee" })
    assert.equals(ReachabilityState.ATTACKABLE_NOW, result.state)
    assert.is_true(result.attackable)
  end)

  it("returns TEMPORARILY_BLOCKED for single path failure", function()
    local target = creature(2, 105, 100)
    local result = service.evaluate(target, { mode = "melee" })
    assert.equals(ReachabilityState.TEMPORARILY_BLOCKED, result.state)
    assert.is_false(result.attackable)
  end)

  it("returns REPOSITION_REQUIRED when path exists but needs movement", function()
    local target = creature(3, 105, 100)
    paths[key(target.position) .. ":2:5"] = { 1, 1, 1 }
    shots[key(player.position) .. ">" .. key(target.position)] = false
    local result = service.evaluate(target, { mode = "ranged", minDistance = 2, maxDistance = 5 })
    assert.equals(ReachabilityState.REPOSITION_REQUIRED, result.state)
    assert.is_false(result.attackable)
  end)

  it("returns DIFFERENT_FLOOR for floor mismatch", function()
    local target = creature(4, 101, 100, 8)
    local result = service.evaluate(target, { mode = "melee" })
    assert.equals(ReachabilityState.DIFFERENT_FLOOR, result.state)
    assert.is_false(result.attackable)
  end)

  it("returns CONFIRMED_HARD_UNREACHABLE only after 3+ failures across different player positions", function()
    local target = creature(5, 105, 100)

    service.evaluate(target, { mode = "melee" })

    player.position = pos(101, 100)
    service.evaluate(target, { mode = "melee" })

    player.position = pos(102, 100)
    local result = service.evaluate(target, { mode = "melee" })

    assert.equals(ReachabilityState.CONFIRMED_HARD_UNREACHABLE, result.state)
  end)

  it("invalidates evidence when player moves", function()
    local target = creature(6, 105, 100)
    service.evaluate(target, { mode = "melee" })
    assert.is_not_nil(service.getEvidence(6))

    service.invalidateOnPlayerMove()
    local evidence = service.getEvidence(6)
    assert.is_nil(evidence)
  end)

  it("invalidates evidence when creature moves", function()
    local target = creature(7, 105, 100)
    service.evaluate(target, { mode = "melee" })
    assert.is_not_nil(service.getEvidence(7))

    service.invalidateOnCreatureMove(7)
    assert.is_nil(service.getEvidence(7))
  end)

  it("single failure does NOT produce CONFIRMED_HARD_UNREACHABLE", function()
    local target = creature(8, 105, 100)
    local result = service.evaluate(target, { mode = "melee" })
    assert.is_not_equals(ReachabilityState.CONFIRMED_HARD_UNREACHABLE, result.state)
  end)

  it("consecutive failures over time produce CONFIRMED_HARD_UNREACHABLE", function()
    local target = creature(9, 105, 100)
    local result
    for i = 1, 5 do
      clock = 1000 + (i - 1) * 1000
      result = service.evaluate(target, { mode = "melee" })
    end
    assert.equals(ReachabilityState.CONFIRMED_HARD_UNREACHABLE, result.state)
  end)

  it("after player moves and creature becomes reachable, evidence resets", function()
    local target = creature(10, 105, 100)

    service.evaluate(target, { mode = "melee" })
    player.position = pos(101, 100)
    service.evaluate(target, { mode = "melee" })
    player.position = pos(102, 100)
    service.evaluate(target, { mode = "melee" })

    service.invalidateOnPlayerMove()

    clock = clock + 500
    player.position = pos(100, 100)
    paths[key(target.position) .. ":1:1"] = { 1, 1, 1, 1 }
    local result = service.evaluate(target, { mode = "melee" })
    assert.equals(ReachabilityState.ATTACKABLE_NOW, result.state)

    clock = clock + 500
    paths[key(target.position) .. ":1:1"] = nil
    result = service.evaluate(target, { mode = "melee", force = true })
    assert.equals(ReachabilityState.TEMPORARILY_BLOCKED, result.state)
  end)
end)
