WaypointNavigator = {}

local function PS()
  return nExBot and nExBot.PathStrategy or PathStrategy
end

function WaypointNavigator.findNearestReachable(playerPos, waypoints, maxDist)
  if not playerPos or not waypoints or #waypoints == 0 then return nil end
  maxDist = maxDist or 50

  local candidates = {}
  local floorCandidates = {}

  for i, wp in pairs(waypoints) do
    if wp.isGoto then
      if wp.z == playerPos.z then
        floorCandidates[#floorCandidates + 1] = { wp = wp, idx = i }
      end
    end
  end

  for _, fc in ipairs(floorCandidates) do
    local wp = fc.wp
    local cheb = math.max(math.abs(playerPos.x - wp.x), math.abs(playerPos.y - wp.y))
    if cheb <= maxDist * 2 then
      local opts = { maxSteps = math.min(cheb + 10, 50), ignoreCreatures = true, ignoreNonPathable = true }
      local path = PS().findPath(playerPos, { x = wp.x, y = wp.y, z = wp.z }, opts)
      if path and #path > 0 then
        candidates[#candidates + 1] = { wp = wp, idx = fc.idx, dist = #path, cheb = cheb }
      end
    end
  end

  if #candidates > 0 then
    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    return candidates[1]
  end

  for _, fc in ipairs(floorCandidates) do
    local wp = fc.wp
    local cheb = math.max(math.abs(playerPos.x - wp.x), math.abs(playerPos.y - wp.y))
    local opts = { maxSteps = math.min(cheb + 5, 30), ignoreCreatures = true }
    local path = PS().findPath(playerPos, { x = wp.x, y = wp.y, z = wp.z }, opts)
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
  return false, "moving"
end


return WaypointNavigator
