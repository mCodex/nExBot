-- tests/unit/cavebot/waypoint_search_spec.lua
-- WaypointSearch: pure candidate-selection logic extracted from CaveBot's
-- findReachableWaypoint (cavebot/cavebot.lua). Covers the two scenarios the
-- old distance-only/±1-floor logic got wrong: a closer-but-unreachable
-- candidate beating a farther-but-reachable one, and waypoints more than one
-- floor away being invisible to the cross-floor fallback.

local WaypointSearch = require("cavebot.waypoint_search")

local function candidate(index, score, opts)
  opts = opts or {}
  return {
    index = index,
    score = score,
    dist = score,
    child = { id = index },
    isGoto = opts.isGoto ~= false,
    withinRange = opts.withinRange ~= false,
  }
end

describe("WaypointSearch.selectReachable", function()
  it("picks the nearest reachable candidate when everything is reachable", function()
    local candidates = { candidate(1, 5), candidate(2, 10), candidate(3, 15) }
    local chosen = WaypointSearch.selectReachable(candidates, {
      budget = 10,
      validate = function() return true end,
    })
    assert.are_equal(1, chosen.index)
  end)

  it("skips closer unreachable candidates in favor of a farther reachable one", function()
    -- Regression: the old logic only real-validated the top 5 by rank and
    -- blindly trusted distance beyond that, so an unreachable candidate
    -- ranked 6th+ could still win. Here ranks 1-3 are unreachable (behind a
    -- wall) and rank 4 is the first one that's actually reachable.
    local candidates = {
      candidate(1, 5), candidate(2, 6), candidate(3, 7), candidate(4, 8),
    }
    local unreachable = { [1] = true, [2] = true, [3] = true }
    local chosen = WaypointSearch.selectReachable(candidates, {
      budget = 10,
      validate = function(c) return not unreachable[c.index] end,
    })
    assert.is_not_nil(chosen)
    assert.are_equal(4, chosen.index)
  end)

  it("never accepts a candidate past the validation budget on distance alone", function()
    -- All 5 candidates are within range, but only 2 fit the work budget and
    -- neither of those is reachable. The old code would have fallen back to
    -- blindly trusting distance for candidates 3-5 (all unvalidated); the
    -- new code must return nil instead of silently picking one of them.
    local candidates = {
      candidate(1, 5), candidate(2, 6), candidate(3, 7), candidate(4, 8), candidate(5, 9),
    }
    local chosen = WaypointSearch.selectReachable(candidates, {
      budget = 2,
      validate = function() return false end,
    })
    assert.is_nil(chosen)
  end)

  it("prefers a goto-typed candidate over a closer non-goto one", function()
    local candidates = {
      candidate(1, 5, { isGoto = false }),
      candidate(2, 8, { isGoto = true }),
    }
    local chosen = WaypointSearch.selectReachable(candidates, {
      budget = 10,
      validate = function() return true end,
    })
    assert.are_equal(2, chosen.index)
  end)

  it("always considers the proximity guarantee even when outside range", function()
    local candidates = { candidate(1, 100, { withinRange = false }) }
    local chosen = WaypointSearch.selectReachable(candidates, {
      budget = 10,
      proximityGuarantee = 1,
      validate = function() return true end,
    })
    assert.is_not_nil(chosen)
  end)

  it("trusts distance when no validator is available (no pathfinder)", function()
    local candidates = { candidate(1, 5), candidate(2, 10) }
    local chosen = WaypointSearch.selectReachable(candidates, {})
    assert.are_equal(1, chosen.index)
  end)

  it("stops considering candidates past maxCandidates", function()
    local candidates = { candidate(1, 5), candidate(2, 6) }
    local chosen = WaypointSearch.selectReachable(candidates, {
      budget = 10,
      maxCandidates = 1,
      validate = function(c) return c.index == 2 end,
    })
    assert.is_nil(chosen)
  end)
end)

describe("WaypointSearch.floorSearchOrder", function()
  it("orders floors nearest-|Δz|-first, alternating up/down", function()
    assert.same({ 6, 8, 5, 9, 4, 10 }, WaypointSearch.floorSearchOrder(7, 3))
  end)
end)

describe("WaypointSearch.selectCrossFloor", function()
  it("finds a waypoint two floors away when one floor away has none", function()
    -- Regression: the old cross-floor fallback only ever checked playerZ-1
    -- and playerZ+1, so a waypoint two floors away was never found even
    -- though nothing about it was actually unreachable.
    local floorOrder = WaypointSearch.floorSearchOrder(7, 3) -- {6,8,5,9,4,10}
    local candidatesByFloor = {
      [5] = { candidate(1, 12) }, -- two floors down
    }
    local chosen = WaypointSearch.selectCrossFloor(floorOrder, candidatesByFloor)
    assert.is_not_nil(chosen)
    assert.are_equal(1, chosen.index)
  end)

  it("prefers the nearer floor over a farther one that also has candidates", function()
    local floorOrder = WaypointSearch.floorSearchOrder(7, 3)
    local candidatesByFloor = {
      [6] = { candidate(1, 20) },
      [9] = { candidate(2, 3) }, -- much closer by score, but a farther floor
    }
    local chosen = WaypointSearch.selectCrossFloor(floorOrder, candidatesByFloor)
    assert.are_equal(1, chosen.index)
  end)

  it("prefers a goto-typed candidate within the chosen floor", function()
    local floorOrder = WaypointSearch.floorSearchOrder(7, 1)
    local candidatesByFloor = {
      [6] = {
        candidate(1, 5, { isGoto = false }),
        candidate(2, 9, { isGoto = true }),
      },
    }
    local chosen = WaypointSearch.selectCrossFloor(floorOrder, candidatesByFloor)
    assert.are_equal(2, chosen.index)
  end)

  it("returns nil when no floor in range has any candidates", function()
    local floorOrder = WaypointSearch.floorSearchOrder(7, 2)
    local chosen = WaypointSearch.selectCrossFloor(floorOrder, {})
    assert.is_nil(chosen)
  end)
end)
