--[[
  WaypointSearch — pure candidate-selection logic for CaveBot's reachability
  search (cavebot.lua's findReachableWaypoint). Kept separate from the
  70KB+ cavebot.lua monolith, which builds UI and touches the live OTClient
  runtime at load time, so this can be unit-tested directly.

  Pure Lua; no OTClient globals.
]]

local WaypointSearch = {}

-- Path-validate candidates nearest-first (caller must pass them pre-sorted
-- ascending by `score`) until either the work budget is exhausted or every
-- in-range candidate has been checked. Nothing past the budget is accepted
-- on distance alone: an unvalidated candidate is never treated as reachable,
-- so a farther-but-actually-reachable candidate can still be picked once
-- nearer ones fail real validation, instead of the old "trust distance past
-- a fixed rank" behavior that could return an unreachable WP.
--
-- candidates: array of { index, dist, score, child, isGoto, withinRange, ... }
-- opts.validate(candidate) -> boolean : real reachability check (e.g. A*).
--   Omit when no pathfinder is available; every in-range candidate is then
--   trusted by distance (legacy behavior, used as a graceful degradation).
-- opts.budget: max number of opts.validate() calls to spend (default: unbounded).
-- opts.proximityGuarantee: always consider this many closest candidates even
--   if they're outside maxDist (default 0).
-- opts.maxCandidates: stop looking past this rank entirely (default: unbounded).
-- Returns the chosen candidate (goto-typed preferred among validated), or nil.
function WaypointSearch.selectReachable(candidates, opts)
  opts = opts or {}
  local validate = opts.validate
  local budget = opts.budget or math.huge
  local proximityGuarantee = opts.proximityGuarantee or 0
  local maxCandidates = opts.maxCandidates or math.huge

  local validated = {}
  local calls = 0

  for rank, c in ipairs(candidates) do
    if rank > maxCandidates then break end
    local shouldConsider = (rank <= proximityGuarantee) or c.withinRange
    if shouldConsider then
      if not validate then
        if c.withinRange then validated[#validated + 1] = c end
      elseif calls < budget then
        calls = calls + 1
        if validate(c) then validated[#validated + 1] = c end
      end
    end
  end

  for _, v in ipairs(validated) do
    if v.isGoto then return v end
  end
  return validated[1]
end

-- Builds a floor search order nearest-|Δz|-first, e.g. playerZ=7, radius=3
-- -> {6, 8, 5, 9, 4, 10}.
function WaypointSearch.floorSearchOrder(playerZ, radius)
  local order = {}
  for r = 1, radius do
    order[#order + 1] = playerZ - r
    order[#order + 1] = playerZ + r
  end
  return order
end

-- Cross-floor candidate selection: walks floorOrder (nearest-|Δz|-first) and
-- returns the best candidate on the first floor that has any, preferring a
-- goto-typed one. There's no cross-floor path validation here (reaching
-- another floor needs an actual stair/rope transition, modeled elsewhere) —
-- this only widens which floors get considered instead of a hardcoded ±1.
--
-- candidatesByFloor: { [floorZ] = array of { score, isGoto, ... } }
-- Returns the chosen candidate, or nil.
function WaypointSearch.selectCrossFloor(floorOrder, candidatesByFloor)
  for _, floorZ in ipairs(floorOrder) do
    local floorCandidates = candidatesByFloor[floorZ]
    if floorCandidates and #floorCandidates > 0 then
      local bestAny, bestAnyScore
      local bestGoto, bestGotoScore
      for _, c in ipairs(floorCandidates) do
        if not bestAnyScore or c.score < bestAnyScore then
          bestAny, bestAnyScore = c, c.score
        end
        if c.isGoto and (not bestGotoScore or c.score < bestGotoScore) then
          bestGoto, bestGotoScore = c, c.score
        end
      end
      if bestGoto then return bestGoto end
      if bestAny then return bestAny end
    end
  end
  return nil
end

if nExBot then
  nExBot.Nav = nExBot.Nav or {}
  nExBot.Nav["cavebot.waypoint_search"] = WaypointSearch
end

return WaypointSearch
