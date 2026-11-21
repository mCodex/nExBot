-- tests/unit/navigation/step_validator_spec.lua
-- P0.1 (walkability contract), P0.3 (strict diagonal corners), fail-safe rules.

local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local StepValidator = require("navigation.step_validator")
local D = require("navigation.domain")

describe("StepValidator", function()
  local world, port
  local P = { x = 10, y = 10, z = 7 }

  local function pos(x, y) return { x = x, y = y, z = 7 } end

  -- The domain only ever sees the port, never the raw client.
  local function policy(over)
    local p = { world = port.world }
    for k, v in pairs(over or {}) do p[k] = v end
    return p
  end

  before_each(function()
    world = Fake.newWorld()
    world:freespaceRect(5, 5, 16, 15, 7)
    port = AdapterFake.create(world, Fake.newPlayer(world, P))
  end)

  it("accepts a cardinal step onto a free tile", function()
    local ok, dest, reason = StepValidator.validate(P, D.DIR.EAST, policy())
    assert.is_true(ok)
    assert.equals(11, dest.x)
    assert.is_nil(reason)
  end)

  it("rejects a step into a wall (P0.1: never defaults to true)", function()
    world:setWall(pos(11, 10))
    local ok, _, reason = StepValidator.validate(P, D.DIR.EAST, policy())
    assert.is_false(ok)
    assert.equals(D.OBSTACLE.STATIC_UNWALKABLE, reason)
  end)

  it("rejects a step into a void/unknown tile (fail safe)", function()
    local ok, _, reason = StepValidator.validate({ x = 60, y = 60, z = 7 }, D.DIR.EAST, policy())
    assert.is_false(ok)
    assert.equals(D.OBSTACLE.VOID_OR_MISSING_TILE, reason)
  end)

  it("rejects a creature-occupied tile unless explicitly ignored", function()
    world:setCreature(pos(11, 10))
    local ok, _, reason = StepValidator.validate(P, D.DIR.EAST, policy())
    assert.is_false(ok)
    assert.equals(D.OBSTACLE.TEMPORARY_CREATURE, reason)
    local ok2 = StepValidator.validate(P, D.DIR.EAST, policy({ ignoreCreatures = true }))
    assert.is_true(ok2)
  end)

  it("rejects hazard tiles unless the crossing is authorized", function()
    world:setHazard(pos(11, 10), "FIRE_FIELD")
    local ok, _, reason = StepValidator.validate(P, D.DIR.EAST, policy())
    assert.is_false(ok)
    assert.equals("FIRE_FIELD", reason)
    local ok2 = StepValidator.validate(P, D.DIR.EAST, policy({ allowFields = true }))
    assert.is_true(ok2)
  end)

  it("rejects floor-change tiles unless explicitly allowed", function()
    world:setFloorChange(pos(11, 10))
    local ok, _, reason = StepValidator.validate(P, D.DIR.EAST, policy())
    assert.is_false(ok)
    assert.equals("FLOOR_CHANGE_TILE", reason)
    local ok2 = StepValidator.validate(P, D.DIR.EAST, policy({ allowFloorChange = true }))
    assert.is_true(ok2)
  end)

  it("validates diagonals with strict corner semantics (P0.3)", function()
    local ok = StepValidator.validate(P, D.DIR.NE, policy())
    assert.is_true(ok)
    world:setWall(pos(11, 10))
    local ok2, _, reason2 = StepValidator.validate(P, D.DIR.NE, policy())
    assert.is_false(ok2)
    assert.truthy(reason2:find("DIAGONAL_CORNER"))
  end)

  it("returns INVALID_DIRECTION for a non-direction", function()
    local ok, _, reason = StepValidator.validate(P, 99, policy())
    assert.is_false(ok)
    assert.equals("INVALID_DIRECTION", reason)
  end)

  it("fails closed when the world port is missing", function()
    local ok, _, reason = StepValidator.validate(P, D.DIR.EAST, {})
    assert.is_false(ok)
    assert.equals("NO_MAP", reason)
  end)

  describe("validatePath", function()
    it("reports the first bad step index", function()
      world:setWall(pos(11, 10))
      local ok, _, badIdx, reason = StepValidator.validatePath(P, { D.DIR.EAST }, policy())
      assert.is_false(ok)
      assert.equals(1, badIdx)
      assert.is_not_nil(reason)
    end)

    it("walks a clean sequence end to end", function()
      local ok, endPos = StepValidator.validatePath(P, { D.DIR.EAST, D.DIR.EAST, D.DIR.NORTH }, policy())
      assert.is_true(ok)
      assert.equals(12, endPos.x)
      assert.equals(9, endPos.y)
    end)

    it("rejects a diagonal path when the untraversed corner is blocked", function()
      world:setWall(pos(11, 9))
      local ok, _, badIdx, reason = StepValidator.validatePath(P, { D.DIR.EAST, D.DIR.NE }, policy())
      assert.is_false(ok)
      assert.equals(2, badIdx)
      assert.truthy(reason:find("DIAGONAL_CORNER"))
    end)
  end)

  it("requires both sides of a diagonal merge to be clear", function()
    world:setWall(pos(10, 9))
    local ok, reason = StepValidator.canMergeDiagonal(P, D.DIR.EAST, D.DIR.NORTH, port.world, {})
    assert.is_false(ok)
    assert.truthy(reason:find("CORNER_TILE_BLOCKED"))
  end)

  describe("canWalkDirection (P0.1 contract)", function()
    it("uses player:canWalk when it returns true", function()
      local ctx = {
        player = { canWalk = function(_, _) return true end },
        world = world, getPosition = function() return P end,
      }
      local ok, reason = StepValidator.canWalkDirection(D.DIR.EAST, ctx)
      assert.is_true(ok)
      assert.equals("PLAYER_CONFIRMED", reason)
    end)

    it("rejects when player:canWalk explicitly returns false", function()
      local ctx = {
        player = { canWalk = function(_, _) return false end },
        world = world, getPosition = function() return P end,
      }
      local ok, reason = StepValidator.canWalkDirection(D.DIR.EAST, ctx)
      assert.is_false(ok)
      assert.equals("PLAYER_REJECTED", reason)
    end)

    it("falls back to map validation when canWalk is missing", function()
      local ctx = { player = {}, world = port.world, getPosition = function() return P end }
      local ok, reason = StepValidator.canWalkDirection(D.DIR.EAST, ctx)
      assert.is_true(ok)
      assert.equals("MAP_CONFIRMED", reason)
    end)

    it("never defaults to success when nothing is known", function()
      local ok, reason = StepValidator.canWalkDirection(D.DIR.EAST, {})
      assert.is_false(ok)
      assert.equals("UNKNOWN_WALKABILITY", reason)
    end)
  end)
end)
