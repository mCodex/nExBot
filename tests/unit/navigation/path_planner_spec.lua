-- tests/unit/navigation/path_planner_spec.lua
-- Strict path front-end: classification, cache TTL, invalidation, reachability.

local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local PathPlanner = require("navigation.path_planner")
local D = require("navigation.domain")

describe("PathPlanner", function()
  local world, player, port
  local A = { x = 10, y = 10, z = 7 }
  local B = { x = 13, y = 10, z = 7 }

  before_each(function()
    world = Fake.newWorld()
    player = Fake.newPlayer(world, A)
    port = AdapterFake.create(world, player)
    PathPlanner.cache = nil
    PathPlanner.setNowFn(nil)
  end)

  it("finds a strict path on an open grid", function()
    world:freespaceRect(8, 8, 16, 12, 7)
    local res = PathPlanner.find(port, A, B, {})
    assert.equals("FOUND", res.status)
    assert.is_true(#res.directions > 0)
    assert.equals(B.x, res.endPos.x)
    assert.equals(B.y, res.endPos.y)
  end)

  it("returns NO_PATH when a wall fully separates start and goal", function()
    world:freespaceRect(8, 8, 16, 12, 7)
    for y = 8, 12 do world:setWall({ x = 12, y = y, z = 7 }) end
    local res = PathPlanner.find(port, A, B, { maxSteps = 60 })
    assert.equals("NO_PATH", res.status)
    assert.equals(D.FAILURE.NO_PATH_CURRENT_MAP, res.failure)
  end)

  it("returns FOUND with an empty path when already at the goal", function()
    world:freespaceRect(8, 8, 16, 12, 7)
    local res = PathPlanner.find(port, A, A, {})
    assert.equals("FOUND", res.status)
    assert.equals(0, #res.directions)
    assert.equals(0, res.cost)
  end)

  it("returns MAP_UNKNOWN when the goal tile is void", function()
    local res = PathPlanner.find(port, A, B, {})
    assert.equals("MAP_UNKNOWN", res.status)
  end)

  it("returns DESTINATION_INVALID when the goal is blocked", function()
    world:freespaceRect(8, 8, 16, 12, 7)
    world:setWall(B)
    local res = PathPlanner.find(port, A, B, {})
    assert.equals("DESTINATION_INVALID", res.status)
  end)

  it("classifies a creature-blocked goal as DESTINATION_INVALID", function()
    world:freespaceRect(8, 8, 16, 12, 7)
    world:setCreature(B)
    local res = PathPlanner.find(port, A, B, {})
    assert.equals("DESTINATION_INVALID", res.status)
  end)

  it("defense in depth: re-validates a permissive native path (creature)", function()
    world:freespaceRect(8, 8, 16, 12, 7)
    world:setCreature({ x = 11, y = 10, z = 7 })
    port.path.findPath = function()
      return { directions = { D.DIR.EAST }, positions = { A, { x = 11, y = 10, z = 7 } }, cost = 1 }
    end
    local res = PathPlanner.find(port, A, { x = 12, y = 10, z = 7 }, {})
    assert.equals("NO_PATH", res.status)
    assert.equals(D.FAILURE.TEMPORARY_CREATURE_BLOCK, res.failure)
  end)

  it("serves repeated queries from cache", function()
    world:freespaceRect(8, 8, 16, 12, 7)
    local calls = 0
    local orig = port.path.findPath
    port.path.findPath = function(...)
      calls = calls + 1
      return orig(...)
    end
    PathPlanner.find(port, A, B, { useCache = true })
    PathPlanner.find(port, A, B, { useCache = true })
    assert.equals(1, calls)
  end)

  it("expires cache entries after the TTL", function()
    world:freespaceRect(8, 8, 16, 12, 7)
    local now = 1000
    PathPlanner.setNowFn(function() return now end)
    local calls = 0
    local orig = port.path.findPath
    port.path.findPath = function(...)
      calls = calls + 1
      return orig(...)
    end
    PathPlanner.find(port, A, B, { useCache = true })
    now = now + 4999
    PathPlanner.find(port, A, B, { useCache = true })
    assert.equals(1, calls)
    now = now + 2
    PathPlanner.find(port, A, B, { useCache = true })
    assert.equals(2, calls)
  end)

  it("invalidates on map generation change (world mutation)", function()
    world:freespaceRect(8, 8, 16, 12, 7)
    local calls = 0
    local orig = port.path.findPath
    port.path.findPath = function(...)
      calls = calls + 1
      return orig(...)
    end
    PathPlanner.find(port, A, B, { useCache = true })
    world:setWall({ x = 9, y = 10, z = 7 })
    PathPlanner.find(port, A, B, { useCache = true })
    assert.equals(2, calls)
  end)

  it("isReachable reports reachability", function()
    world:freespaceRect(8, 8, 16, 12, 7)
    local ok, res = PathPlanner.isReachable(port, A, B)
    assert.is_true(ok)
    assert.equals("FOUND", res.status)
    world:setWall(B)
    local ok2 = PathPlanner.isReachable(port, A, B)
    assert.is_false(ok2)
  end)
end)