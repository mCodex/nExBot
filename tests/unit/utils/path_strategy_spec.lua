-- tests/unit/utils/path_strategy_spec.lua
--
-- Regression for the TargetBot "stops attacking every monster on screen /
-- bot gets stuck" bug introduced by db50999 ("Unify targetbot movement onto
-- strict PathStrategy"). targetbot/walking.lua's TargetBot.walk() calls
-- PathStrategy.findPath(playerPos, dest, { precision = ... }) expecting
-- "stop within N tiles of goal" leniency (dest is usually the target
-- creature's own occupied tile, so an exact-tile path is expected to fail
-- and the caller relies on precision to accept a nearby tile instead).
--
-- PathStrategy.findPath documented `opts.precision` but never read it -
-- every backend (ACL adapter, bare `findPath` global, raw g_map.findPath)
-- was asked to path onto the EXACT goal tile with zero tolerance. Since
-- that tile is normally occupied by the creature itself, the pathfind
-- fails for virtually every chase that requires movement, so TargetBot
-- never gets in range and looks permanently stuck.

local function loadPathStrategy()
  _G.PathStrategy = nil
  _G.Directions = nil
  _G.nExBot = nil
  _G.findPath = nil
  -- OTClient provides these as real globals; directions.lua falls back to
  -- 0-3/4-7 when absent, so pin them explicitly for a stable test mock.
  _G.North, _G.East, _G.South, _G.West = 0, 1, 2, 3
  dofile("constants/directions.lua")
  return dofile("utils/path_strategy.lua")
end

describe("PathStrategy.findPath precision/margin handling", function()
  local PathStrategy
  local CREATURE_POS = { x = 103, y = 100, z = 7 }
  local START_POS = { x = 100, y = 100, z = 7 }

  local function straightPathTo(startPos, goalPos)
    local dx = goalPos.x - startPos.x
    if dx == 0 then return {} end
    local dir = dx > 0 and East or West
    local path = {}
    for i = 1, math.abs(dx) do path[i] = dir end
    return path
  end

  before_each(function()
    -- No ACL adapter registered -> resolveBackend() falls through to raw g_map.findPath.
    _G.g_map = {
      findPath = function(startPos, goalPos, maxSteps, flags)
        -- The creature's own tile is occupied and never a valid path goal.
        if goalPos.x == CREATURE_POS.x and goalPos.y == CREATURE_POS.y then
          return nil
        end
        return straightPathTo(startPos, goalPos)
      end,
    }
    _G.PathUtils = {
      isTileWalkable = function(pos, ignoreCreatures)
        if pos.x == CREATURE_POS.x and pos.y == CREATURE_POS.y and not ignoreCreatures then
          return false
        end
        return true
      end,
      isFloorChangeTile = function() return false end,
    }
    PathStrategy = loadPathStrategy()
  end)

  it("returns nil when asked to path exactly onto a creature-occupied tile (precision=0)", function()
    local path = PathStrategy.findPath(START_POS, CREATURE_POS, { maxSteps = 10 })
    assert.is_nil(path)
  end)

  it("finds a path to a tile within `precision` of the goal when the exact tile is blocked", function()
    local path = PathStrategy.findPath(START_POS, CREATURE_POS, { maxSteps = 10, precision = 1 })
    assert.is_not_nil(path)
    assert.is_true(#path > 0)

    -- Walk the returned directions from START_POS and verify we land within
    -- `precision` tiles of the creature, not on top of it.
    local pos = { x = START_POS.x, y = START_POS.y, z = START_POS.z }
    for _, dir in ipairs(path) do
      local off = Directions.DIR_TO_OFFSET[dir]
      pos = { x = pos.x + off.x, y = pos.y + off.y, z = pos.z }
    end
    local finalDistance = math.max(math.abs(pos.x - CREATURE_POS.x), math.abs(pos.y - CREATURE_POS.y))
    assert.is_true(finalDistance <= 1)
    assert.is_false(pos.x == CREATURE_POS.x and pos.y == CREATURE_POS.y)
  end)

  it("respects marginMin/marginMax as an explicit ring instead of precision", function()
    local path = PathStrategy.findPath(START_POS, CREATURE_POS, { maxSteps = 10, marginMin = 1, marginMax = 1 })
    assert.is_not_nil(path)

    local pos = { x = START_POS.x, y = START_POS.y, z = START_POS.z }
    for _, dir in ipairs(path) do
      local off = Directions.DIR_TO_OFFSET[dir]
      pos = { x = pos.x + off.x, y = pos.y + off.y, z = pos.z }
    end
    local finalDistance = math.max(math.abs(pos.x - CREATURE_POS.x), math.abs(pos.y - CREATURE_POS.y))
    assert.equals(1, finalDistance)
  end)
end)
