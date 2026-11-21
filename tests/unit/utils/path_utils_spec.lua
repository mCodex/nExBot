-- tests/unit/utils/path_utils_spec.lua
--
-- Regression for the TargetBot "not attacking" bug: TargetReachability.evaluate()
-- (targetbot/monster_reachability.lua) paths to a creature's OWN occupied tile
-- and relies on profile.ignoreLastCreature=true to make that tile passable.
-- When the runtime has no bare `findPath` global (this OTClientBR build doesn't
-- define one), evaluation falls back to PathUtils.findPath(), which converts
-- params to native flags via paramsToFlags(). Before this fix, paramsToFlags
-- silently dropped ignoreLastCreature, so the destination tile stayed blocked
-- and every non-adjacent creature was reported unreachable.

local function loadPathUtils()
  _G.PathUtils = nil
  dofile("constants/directions.lua")
  return dofile("utils/path_utils.lua")
end

describe("PathUtils.paramsToFlags", function()
  local PathUtils

  before_each(function()
    PathUtils = loadPathUtils()
  end)

  it("maps ignoreLastCreature to the native ALLOW_CREATURES flag", function()
    assert.equals(PathUtils.Flags.ALLOW_CREATURES, PathUtils.paramsToFlags({ ignoreLastCreature = true }))
  end)

  it("still maps allowCreatures to ALLOW_CREATURES (existing behavior)", function()
    assert.equals(PathUtils.Flags.ALLOW_CREATURES, PathUtils.paramsToFlags({ allowCreatures = true }))
  end)

  it("does not double-count when both allowCreatures and ignoreLastCreature are set", function()
    assert.equals(PathUtils.Flags.ALLOW_CREATURES, PathUtils.paramsToFlags({ allowCreatures = true, ignoreLastCreature = true }))
  end)

  it("combines with other flags additively", function()
    local flags = PathUtils.paramsToFlags({ ignoreLastCreature = true, ignoreNonPathable = true })
    assert.equals(PathUtils.Flags.ALLOW_CREATURES + PathUtils.Flags.ALLOW_NON_PATHABLE, flags)
  end)

  it("returns 0 for nil or empty params", function()
    assert.equals(0, PathUtils.paramsToFlags(nil))
    assert.equals(0, PathUtils.paramsToFlags({}))
  end)
end)

-- Regression for the CaveBot "zig-zagging in narrow corridors" bug: the goto
-- action never fed a corridor signal into WaypointPolicy.classify, so tight
-- 1-wide passages were always treated as open ground (chunked autoWalk with
-- multi-tile arrival slack), which overshoots/backtracks in a corridor.
-- walkableNeighborCount() is the tile-topology probe that lets the caller
-- detect a corridor and switch to precise keyboard stepping.
describe("PathUtils.walkableNeighborCount", function()
  local PathUtils
  local blocked

  local function tileAt(pos)
    local key = pos.x .. "," .. pos.y
    return {
      isWalkable = function(_, _ignoreCreatures) return not (blocked and blocked[key]) end,
    }
  end

  before_each(function()
    blocked = nil
    _G.nExBot = nil
    _G.g_map = { getTile = function(pos) return tileAt(pos) end }
    PathUtils = loadPathUtils()
  end)

  it("counts all 8 neighbors walkable on open ground", function()
    assert.equals(8, PathUtils.walkableNeighborCount({ x = 100, y = 100, z = 7 }))
  end)

  it("counts only 2 walkable neighbors inside a straight 1-tile corridor", function()
    -- East-west corridor at y=100: the rows above and below are walls.
    blocked = {}
    for dx = -1, 1 do
      blocked[(100 + dx) .. "," .. 99] = true
      blocked[(100 + dx) .. "," .. 101] = true
    end
    assert.equals(2, PathUtils.walkableNeighborCount({ x = 100, y = 100, z = 7 }))
  end)

  it("returns nil for a nil position", function()
    assert.is_nil(PathUtils.walkableNeighborCount(nil))
  end)
end)
