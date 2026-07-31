local clock = 1000

_G.nExBot = { Shared = { nowMs = function() return clock end } }
_G.ReleaseReason = dofile("targetbot/domain/release_reasons.lua")
_G.ReachabilityState = dofile("targetbot/domain/reachability_states.lua")

describe("RepositionPlanner", function()
  local RP

  before_each(function()
    clock = 1000
    _G.RepositionPlanner = nil
    RP = dofile("targetbot/tactical/reposition_planner.lua")
  end)

  local function makeGridWalkable()
    return function(pos) return true end
  end

  local function makeSafe()
    return function(pos) return true end
  end

  local function makeUnoccupied()
    return function(pos) return false end
  end

  it("returns valid tile at ideal attack range", function()
    local p = RP.new()
    local result = p:plan(
      {
        targetPos = { x = 100, y = 100, z = 7 },
        playerPos = { x = 101, y = 100, z = 7 },
        attackRange = 1,
        isWalkable = makeGridWalkable(),
        isTileSafe = makeSafe(),
        isTileOccupied = makeUnoccupied(),
      },
      { now = 1000, mapGeneration = 1 }
    )
    assert.is_not_nil(result)
    assert.equals("reposition", result.reason)
    assert.is_not_nil(result.position)
    assert.is_not_nil(result.score)
    local dx = math.abs(result.position.x - 100)
    local dy = math.abs(result.position.y - 100)
    assert.equals(1, math.max(dx, dy))
  end)

  it("filters out unwalkable tiles", function()
    local p = RP.new()
    local result = p:plan(
      {
        targetPos = { x = 100, y = 100, z = 7 },
        playerPos = { x = 101, y = 100, z = 7 },
        attackRange = 1,
        isWalkable = function() return false end,
        isTileSafe = makeSafe(),
        isTileOccupied = makeUnoccupied(),
      },
      { now = 1000, mapGeneration = 1 }
    )
    assert.is_nil(result)
  end)

  it("filters out unsafe tiles", function()
    local p = RP.new()
    local result = p:plan(
      {
        targetPos = { x = 100, y = 100, z = 7 },
        playerPos = { x = 101, y = 100, z = 7 },
        attackRange = 1,
        isWalkable = makeGridWalkable(),
        isTileSafe = function() return false end,
        isTileOccupied = makeUnoccupied(),
      },
      { now = 1000, mapGeneration = 1 }
    )
    assert.is_nil(result)
  end)

  it("scores ideal distance higher than non-ideal", function()
    local p1 = RP.new()
    local r1 = p1:plan(
      {
        targetPos = { x = 100, y = 100, z = 7 },
        playerPos = { x = 101, y = 100, z = 7 },
        attackRange = 1,
        isWalkable = makeGridWalkable(),
        isTileSafe = makeSafe(),
        isTileOccupied = makeUnoccupied(),
      },
      { now = 1000, mapGeneration = 1 }
    )
    assert.is_not_nil(r1)
    assert.is_true(r1.score >= 150)
  end)

  it("penalizes tiles with many adjacent monsters", function()
    local pClean = RP.new()
    local rClean = pClean:plan(
      {
        targetPos = { x = 100, y = 100, z = 7 },
        playerPos = { x = 105, y = 105, z = 7 },
        attackRange = 1,
        isWalkable = makeGridWalkable(),
        isTileSafe = makeSafe(),
        isTileOccupied = makeUnoccupied(),
      },
      { now = 1000, mapGeneration = 1 }
    )

    local bestTile = rClean.position
    local pDirty = RP.new()
    local occupiedNeighbors = {}
    for dx = -1, 1 do
      for dy = -1, 1 do
        if dx ~= 0 or dy ~= 0 then
          occupiedNeighbors[(bestTile.x+dx)..","..(bestTile.y+dy)..",7"] = true
        end
      end
    end
    local rDirty = pDirty:plan(
      {
        targetPos = { x = 100, y = 100, z = 7 },
        playerPos = { x = 105, y = 105, z = 7 },
        attackRange = 1,
        isWalkable = makeGridWalkable(),
        isTileSafe = makeSafe(),
        isTileOccupied = function(pos) return occupiedNeighbors[pos.x..","..pos.y..","..pos.z] == true end,
      },
      { now = 1000, mapGeneration = 1 }
    )
    assert.is_not_nil(rDirty)
    assert.is_true(rDirty.score < rClean.score)
  end)

  it("returns nil when no valid tiles exist", function()
    local p = RP.new()
    local result, reason = p:plan(
      {
        targetPos = { x = 100, y = 100, z = 7 },
        playerPos = { x = 101, y = 100, z = 7 },
        attackRange = 1,
        isWalkable = function() return false end,
        isTileSafe = makeSafe(),
        isTileOccupied = makeUnoccupied(),
      },
      { now = 1000, mapGeneration = 1 }
    )
    assert.is_nil(result)
    assert.equals("NO_VALID_REPOSITION_TILE", reason)
  end)

  it("caches results by mapGeneration + positions", function()
    local p = RP.new()
    local calls = 0
    local walkFn = function(pos) calls = calls + 1; return true end
    local obs = {
      targetPos = { x = 100, y = 100, z = 7 },
      playerPos = { x = 101, y = 100, z = 7 },
      attackRange = 1,
      isWalkable = walkFn,
      isTileSafe = makeSafe(),
      isTileOccupied = makeUnoccupied(),
    }
    local ctx = { now = 1000, mapGeneration = 1 }
    local r1 = p:plan(obs, ctx)
    local callsAfter1 = calls
    local r2 = p:plan(obs, ctx)
    assert.equals(callsAfter1, calls)
    assert.equals(r1.position.x, r2.position.x)
    assert.equals(r1.position.y, r2.position.y)

    local r3 = p:plan(obs, { now = 1000, mapGeneration = 2 })
    assert.is_true(calls > callsAfter1)
  end)

  it("penalizes oscillation (same as recent position)", function()
    local p = RP.new()
    local obs = {
      targetPos = { x = 100, y = 100, z = 7 },
      playerPos = { x = 101, y = 100, z = 7 },
      attackRange = 1,
      isWalkable = makeGridWalkable(),
      isTileSafe = makeSafe(),
      isTileOccupied = makeUnoccupied(),
    }
    local r1 = p:plan(obs, { now = 1000, mapGeneration = 1 })
    assert.is_not_nil(r1)
    local firstPos = r1.position

    local r2 = p:plan(obs, { now = 1100, mapGeneration = 2 })
    assert.is_not_nil(r2)
    if r2.position.x == firstPos.x and r2.position.y == firstPos.y then
      assert.is_true(r2.score < r1.score)
    end
  end)
end)
