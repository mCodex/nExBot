WaypointNavigator = {}

local function PS()
  return nExBot and nExBot.PathStrategy or PathStrategy
end

-- Configuration constants
local MAX_PATHFIND_CANDIDATES = 5    -- Only pathfind to top 5 closest waypoints
local MAX_PATHFIND_DIST_MULT = 2     -- Consider waypoints within maxDist * 2
local MIN_CHEBYSHEV_FOR_PATHFIND = 3 -- Don't pathfind for very close waypoints (just walk)

function WaypointNavigator.findNearestReachable(playerPos, waypoints, maxDist)
  if not playerPos or not waypoints or #waypoints == 0 then return nil end
  maxDist = maxDist or 50

  local floorCandidates = {}

  -- Collect same-floor goto waypoints with Chebyshev distance
  for i, wp in pairs(waypoints) do
    if wp.isGoto and wp.z == playerPos.z then
      local cheb = math.max(math.abs(playerPos.x - wp.x), math.abs(playerPos.y - wp.y))
      if cheb <= maxDist * MAX_PATHFIND_DIST_MULT then
        floorCandidates[#floorCandidates + 1] = { wp = wp, idx = i, cheb = cheb }
      end
    end
  end

  if #floorCandidates == 0 then return nil end

  -- Sort by Chebyshev distance (closest first) - O(n log n) but n is small
  table.sort(floorCandidates, function(a, b) return a.cheb < b.cheb end)

  -- Only pathfind to top candidates
  local candidates = {}
  local pathfindCount = 0

  for _, fc in ipairs(floorCandidates) do
    if pathfindCount >= MAX_PATHFIND_CANDIDATES then break end
    
    local wp = fc.wp
    local cheb = fc.cheb

    -- For very close waypoints, skip pathfinding - just walk directly
    if cheb <= MIN_CHEBYSHEV_FOR_PATHFIND then
      return { wp = wp, idx = fc.idx, dist = cheb, cheb = cheb, directWalk = true }
    end

    local opts = { 
      maxSteps = math.min(cheb + 10, 50), 
      ignoreCreatures = true, 
      ignoreNonPathable = true 
    }
    local path = PS().findPath(playerPos, { x = wp.x, y = wp.y, z = wp.z }, opts)
    
    pathfindCount = pathfindCount + 1
    
    if path and #path > 0 then
      candidates[#candidates + 1] = { wp = wp, idx = fc.idx, dist = #path, cheb = cheb }
      -- Early exit: if we found a very close reachable waypoint, use it
      if #path <= 5 then
        return candidates[#candidates]
      end
    end
  end

  if #candidates > 0 then
    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    return candidates[1]
  end

  -- Fallback: try with less restrictive options for remaining closest waypoints
  for _, fc in ipairs(floorCandidates) do
    if pathfindCount >= MAX_PATHFIND_CANDIDATES + 3 then break end
    
    local wp = fc.wp
    local cheb = fc.cheb
    if cheb <= MIN_CHEBYSHEV_FOR_PATHFIND then
      return { wp = wp, idx = fc.idx, dist = cheb, cheb = cheb, directWalk = true }
    end

    local opts = { maxSteps = math.min(cheb + 5, 30), ignoreCreatures = true }
    local path = PS().findPath(playerPos, { x = wp.x, y = wp.y, z = wp.z }, opts)
    
    pathfindCount = pathfindCount + 1
    
    if path and #path > 0 then
      candidates[#candidates + 1] = { wp = wp, idx = fc.idx, dist = #path, cheb = cheb }
    end
  end

  if #candidates > 0 then
    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    return candidates[1]
  end

  return nil
end

function WaypointNavigator.findBestOnFloor(playerPos, waypoints, maxDist)
  if not playerPos then return nil end
  maxDist = maxDist or 50
  local best, bestDist = nil, math.huge
  for i, wp in pairs(waypoints) do
    if wp.isGoto and wp.z == playerPos.z then
      local d = math.max(math.abs(playerPos.x - wp.x), math.abs(playerPos.y - wp.y))
      if d <= maxDist and d < bestDist then
        best = { wp = wp, idx = i, dist = d }
        bestDist = d
      end
    end
  end
  return best
end

function WaypointNavigator.stuckDetected(posHistory, threshold)
  if not posHistory or #posHistory < 3 then return false, "insufficient_data" end
  local first = posHistory[1]
  local last = posHistory[#posHistory]
  if first.z ~= last.z then return false, "floor_change" end
  local moved = math.max(math.abs(last.x - first.x), math.abs(last.y - first.y))
  if moved <= threshold then
    return true, "no_progress"
  end

  -- Check for oscillation (back-and-forth movement without progress)
  if #posHistory >= 10 then
    local mid = posHistory[math.floor(#posHistory / 2)]
    if mid then
      local midToEnd = math.max(math.abs(last.x - mid.x), math.abs(last.y - mid.y))
      if midToEnd <= threshold then
        return true, "oscillating"
      end
    end
  end

  return false, "moving"
end


--[[
  Find nearest floor-transition rescue waypoint.
  Auto-detects consecutive goto waypoints with different Z levels.
  Returns the waypoint on player's floor that is closest to a transition.
]]
function WaypointNavigator.findRescueWaypoint(playerPos, waypoints, maxDist)
  if not playerPos or not waypoints or #waypoints < 2 then return nil end
  maxDist = maxDist or 50

  local rescueCandidates = {}
  local playerZ = playerPos.z

  -- Build list of waypoints in insertion order
  local ordered = {}
  for i, wp in ipairs(waypoints) do
    ordered[i] = wp
  end

  -- Detect floor transitions: consecutive goto waypoints with different Z
  for i = 1, #ordered - 1 do
    local a, b = ordered[i], ordered[i + 1]
    if a and b and a.isGoto and b.isGoto and a.z ~= b.z then
      if a.z == playerZ then
        local cheb = math.max(math.abs(playerPos.x - a.x), math.abs(playerPos.y - a.y))
        if cheb <= maxDist * 2 then
          rescueCandidates[#rescueCandidates + 1] = { wp = a, idx = i, cheb = cheb, otherZ = b.z }
        end
      elseif b.z == playerZ then
        local cheb = math.max(math.abs(playerPos.x - b.x), math.abs(playerPos.y - b.y))
        if cheb <= maxDist * 2 then
          rescueCandidates[#rescueCandidates + 1] = { wp = b, idx = i + 1, cheb = cheb, otherZ = a.z }
        end
      end
    end
  end

  if #rescueCandidates == 0 then return nil end

  table.sort(rescueCandidates, function(a, b) return a.cheb < b.cheb end)

  local best = rescueCandidates[1]
  if best.cheb <= 3 then
    return { wp = best.wp, idx = best.idx, dist = best.cheb, directWalk = true }
  end

  -- Try pathfinding for the closest candidate
  local opts = { maxSteps = math.min(best.cheb + 10, 50), ignoreCreatures = true, ignoreNonPathable = true }
  local path = PS().findPath(playerPos, { x = best.wp.x, y = best.wp.y, z = best.wp.z }, opts)
  if path and #path > 0 then
    return { wp = best.wp, idx = best.idx, dist = #path }
  end

  return nil
end

return WaypointNavigator