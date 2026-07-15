local function pos(x, y, z) return { x = x, y = y, z = z or 7 } end

local clock
local player
local paths
local shots
local pathCalls

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

local function loadService()
  clock = 1000
  player = { position = pos(100, 100) }
  function player:getPosition() return self.position end
  paths, shots, pathCalls = {}, {}, 0

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
  _G.MonsterAI = { _helpers = {} }
  _G.EventBus = nil
  _G.UnifiedTick = nil
  _G.macro = function() end
  _G.g_game = { getLocalPlayer = function() return player end }
  _G.findPath = function(_, destination, _, profile)
    pathCalls = pathCalls + 1
    local ring = tostring(profile.marginMin or 0) .. ":" .. tostring(profile.marginMax or 0)
    return paths[key(destination) .. ":" .. ring]
  end
  _G.g_map = {
    isSightClear = function(from, destination)
      return shots[key(from) .. ">" .. key(destination)] ~= false
    end,
  }

  _G.TargetReachability = nil
  return dofile("targetbot/monster_reachability.lua")
end

describe("TargetReachability", function()
  local service

  before_each(function() service = loadService() end)

  it("rejects close creatures when no real melee attack-position path exists", function()
    local result = service.evaluate(creature(1, 102, 100), { mode = "melee", force = true })
    assert.is_false(result.attackable)
    assert.equals("no_attack_position", result.reason)
  end)

  it("rejects targets on another floor without calling pathfinding", function()
    local result = service.evaluate(creature(8, 102, 100, 8), { mode = "melee" })
    assert.is_false(result.attackable)
    assert.equals("different_floor", result.reason)
    assert.equals(0, pathCalls)
  end)

  it("accepts a reachable adjacent melee attack position", function()
    local target = creature(1, 103, 100)
    paths[key(target.position) .. ":1:1"] = { 1, 1 }
    local result = service.evaluate(target, { mode = "melee", force = true })
    assert.is_true(result.attackable)
    assert.same({ 1, 1 }, result.path)
  end)

  it("accepts melee when the player already occupies a valid adjacent tile", function()
    local result = service.evaluate(creature(11, 101, 100), { mode = "melee", force = true })
    assert.is_true(result.attackable)
    assert.same({}, result.path)
    assert.equals(0, pathCalls)
  end)

  it("rejects a ranged route without projectile line of sight", function()
    local target = creature(2, 105, 100)
    paths[key(target.position) .. ":2:5"] = { 1, 1, 1 }
    shots[key(player.position) .. ">" .. key(target.position)] = false
    local result = service.evaluate(target, { mode = "ranged", minDistance = 2, maxDistance = 5, force = true })
    assert.is_false(result.attackable)
    assert.equals("no_line_of_sight", result.reason)
  end)

  it("invalidates cached results when either endpoint moves", function()
    local target = creature(3, 103, 100)
    paths[key(target.position) .. ":1:1"] = { 1, 1 }
    assert.is_true(service.evaluate(target, { mode = "melee" }).attackable)
    assert.equals(1, pathCalls)
    assert.is_true(service.evaluate(target, { mode = "melee" }).cacheHit)
    assert.equals(1, pathCalls)

    player.position = pos(101, 100)
    assert.is_true(service.evaluate(target, { mode = "melee" }).attackable)
    assert.equals(2, pathCalls)

    target.position = pos(104, 100)
    paths[key(target.position) .. ":1:1"] = { 1, 1 }
    assert.is_true(service.evaluate(target, { mode = "melee" }).attackable)
    assert.equals(3, pathCalls)
  end)

  it("quarantines hard failures but retries temporary blockers after a short cooldown", function()
    local target = creature(4, 104, 100)
    local hard = service.evaluate(target, { mode = "melee", force = true })
    service.quarantine(target, hard)
    assert.is_true(service.isQuarantined(target))

    service.invalidate(target:getId(), "target_moved")
    local blocked = { attackable = false, reason = "creature_blocked", classification = "temporarily_blocked" }
    service.quarantine(target, blocked)
    assert.is_true(service.isQuarantined(target))
    clock = clock + 1001
    assert.is_false(service.isQuarantined(target))
  end)

  it("fails conservatively when no path capability exists", function()
    _G.findPath = nil
    _G.g_map.findPath = nil
    local result = service.evaluate(creature(9, 103, 100), { mode = "melee", force = true })
    assert.is_false(result.attackable)
    assert.equals("no_path_api", result.reason)
  end)

  it("rejects malformed path API results", function()
    _G.findPath = function() return "not-a-path" end
    local result = service.evaluate(creature(10, 103, 100), { mode = "melee", force = true })
    assert.is_false(result.attackable)
    assert.equals("no_attack_position", result.reason)
  end)
end)
