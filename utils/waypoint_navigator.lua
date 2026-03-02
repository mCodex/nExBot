--[[
  WaypointNavigator v2.0.0

  Pure geometry module for segment-aware route tracking, corridor enforcement,
  and Pure Pursuit lookahead targeting.

  DESIGN PRINCIPLES:
  - SRP: Only answers geometric questions about "where am I on the route?"
  - KISS: No pathfinding, no tile checks, no UI manipulation
  - DRY: Reuses waypointPositionCache from cavebot.lua
  - SOLID: Open for extension (corridor widths, thresholds), closed for modification

  CORE CONCEPTS:
  - Route = ordered sequence of SEGMENTS between consecutive goto waypoints
  - Segment projection = perpendicular projection of player pos onto nearest segment
  - Corridor = configurable-width band around each segment for deviation detection
  - Forward-only = always advance to the END waypoint of the projected segment
  - Pure Pursuit = lookahead point N tiles ahead on route for smooth, human-like movement

  PURE PURSUIT (from robotics):
  Instead of walking directly to the next waypoint, compute a target point that
  is `lookahead` tiles ahead on the route from the player's projected position.
  This creates smooth arcs through waypoints (corner-cutting) and natural
  forward recovery after combat deviations.

  PERFORMANCE:
  - O(n) segment projection, n = number of segments (typically 10-30)
  - O(k) lookahead walk through subsequent segments (k = 2-4 typically)
  - No pathfinding calls, no tile checks, no A*
  - Total cost: <0.5ms per tick
  - Route rebuilt only on cache invalidation or floor change
]]

-- Module namespace (set as global by _Loader)
WaypointNavigator = WaypointNavigator or {}

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

-- Route: ordered list of segments between consecutive goto waypoints
local route = {
  segments = {},       -- Array of {fromPos, toPos, fromIdx, toIdx, length, dirX, dirY}
  gotoIndices = {},    -- Ordered array of waypoint list indices that are 'goto' type
  built = false,
  floor = nil,
  waypointCount = 0,   -- For invalidation check
}

-- Corridor configuration
local corridor = {
  width = 6,              -- Tiles from segment centerline (normal corridor)
  softWidth = 10,         -- Soft boundary: grace period before correction
  hardWidth = 15,         -- Hard boundary: immediate recovery
  returnCooldown = 300,   -- ms between return-to-track actions
  lastReturnTime = 0,
}

-- Pure Pursuit configuration
-- Lookahead = how far ahead on the route to target.
-- 10 tiles is tuned for OTClient's 8-direction grid movement:
-- short enough to stay responsive on turns, long enough to create smooth arcs.
local pursuit = {
  lookahead = 10,           -- tiles ahead on route (tunable: 8-12 recommended)
  minLookahead = 5,         -- minimum when close to endpoints
  maxLookahead = 18,        -- maximum for long straight segments
}

-- Current tracking state
local tracking = {
  segmentIndex = 0,       -- Which segment (1-based) we're currently on
  progress = 0,           -- 0.0 to 1.0 along the current segment
  lastPlayerPos = nil,
  lastUpdateTime = 0,
  inCorridor = true,      -- Whether player is currently inside the corridor
  corridorExitTime = 0,   -- When player first left the corridor
  consecutiveOutside = 0, -- Ticks outside corridor (prevent false triggers from lag)
}

-- Timing reference (use sandbox global or os.clock fallback)
local function getNow()
  return now or (os.clock() * 1000)
end

-- ============================================================================
-- SEGMENT PROJECTION MATH
-- ============================================================================

--- Project point P onto line segment A->B using dot product.
-- Returns: projectedX, projectedY, t (0-1 parameter), distance from P to projected point
local function projectPointOnSegment(px, py, ax, ay, bx, by)
  local abx, aby = bx - ax, by - ay
  local apx, apy = px - ax, py - ay
  local dotABAB = abx * abx + aby * aby

  -- Degenerate segment (A == B): project to the point itself
  if dotABAB == 0 then
    local dx, dy = px - ax, py - ay
    return ax, ay, 0, math.sqrt(dx * dx + dy * dy)
  end

  -- Clamp t to [0, 1] to stay within segment bounds
  local t = math.max(0, math.min(1, (apx * abx + apy * aby) / dotABAB))
  local projX = ax + t * abx
  local projY = ay + t * aby
  local dx, dy = px - projX, py - projY
  local dist = math.sqrt(dx * dx + dy * dy)

  return projX, projY, t, dist
end

--- Chebyshev distance between two positions (matches CaveBot's distance metric).
local function chebyshevDist(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

--- Euclidean distance between two positions.
local function euclideanDist(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

-- ============================================================================
-- ROUTE BUILDING
-- ============================================================================

--- Build the route from the waypointPositionCache.
-- Filters to goto waypoints on the specified floor, builds segments between
-- consecutive gotos. Skips wrap-around segments that span too far.
-- @param waypointPositionCache table  The cache from cavebot.lua (index -> {x,y,z,child,isGoto})
-- @param playerFloor number  Current player Z level
function WaypointNavigator.buildRoute(waypointPositionCache, playerFloor)
  if not waypointPositionCache then return end

  -- Count current waypoints to detect invalidation
  local count = 0
  for _ in pairs(waypointPositionCache) do count = count + 1 end

  -- Skip rebuild if route is current (same floor, same count)
  if route.built and route.floor == playerFloor and route.waypointCount == count then
    return
  end

  -- Clear previous route
  route.segments = {}
  route.gotoIndices = {}
  route.built = false
  route.floor = playerFloor
  route.waypointCount = count

  -- Collect goto waypoints on this floor, sorted by index
  local gotos = {}
  for idx, wp in pairs(waypointPositionCache) do
    if wp.isGoto and wp.z == playerFloor then
      gotos[#gotos + 1] = { idx = idx, x = wp.x, y = wp.y, z = wp.z }
    end
  end

  -- Sort by waypoint list index (preserves user-defined order)
  table.sort(gotos, function(a, b) return a.idx < b.idx end)

  if #gotos < 2 then
    -- Need at least 2 goto waypoints to form a segment
    if #gotos == 1 then
      route.gotoIndices[1] = gotos[1].idx
    end
    route.built = true
    return
  end

  -- Store ordered goto indices
  for i, g in ipairs(gotos) do
    route.gotoIndices[i] = g.idx
  end

  -- Max segment length (beyond this, skip the segment — likely a wrap-around)
  local maxSegmentLength = 100
  if CaveBot and CaveBot.getMaxGotoDistance then
    maxSegmentLength = CaveBot.getMaxGotoDistance() * 2
  end

  -- Build segments between consecutive gotos
  for i = 1, #gotos - 1 do
    local from = gotos[i]
    local to = gotos[i + 1]
    local dx = to.x - from.x
    local dy = to.y - from.y
    local length = math.sqrt(dx * dx + dy * dy)

    -- Skip excessively long segments (wrap-around or cross-map jumps)
    if length <= maxSegmentLength then
      route.segments[#route.segments + 1] = {
        fromPos = { x = from.x, y = from.y, z = from.z },
        toPos = { x = to.x, y = to.y, z = to.z },
        fromIdx = from.idx,
        toIdx = to.idx,
        length = length,
        dirX = length > 0 and dx / length or 0,
        dirY = length > 0 and dy / length or 0,
      }
    end
  end

  -- Wrap-around segment (last -> first) if close enough
  local last = gotos[#gotos]
  local first = gotos[1]
  local wrapDx = first.x - last.x
  local wrapDy = first.y - last.y
  local wrapLength = math.sqrt(wrapDx * wrapDx + wrapDy * wrapDy)
  if wrapLength <= maxSegmentLength and wrapLength > 0 then
    route.segments[#route.segments + 1] = {
      fromPos = { x = last.x, y = last.y, z = last.z },
      toPos = { x = first.x, y = first.y, z = first.z },
      fromIdx = last.idx,
      toIdx = first.idx,
      length = wrapLength,
      dirX = wrapDx / wrapLength,
      dirY = wrapDy / wrapLength,
    }
  end

  route.built = true
end

-- ============================================================================
-- ROUTE PROJECTION
-- ============================================================================

--- Project player position onto the nearest segment.
-- Finds the segment with the shortest perpendicular distance, with bias toward
-- the current/forward segment to prevent backward jumps.
-- @param playerPos table {x, y, z}
-- @return segmentIndex, projectedPoint {x,y}, distFromRoute, progress (0-1)
function WaypointNavigator.projectOntoRoute(playerPos)
  if not route.built or #route.segments == 0 or not playerPos then
    return 0, nil, math.huge, 0
  end

  local bestSegIdx = 0
  local bestProjX, bestProjY = 0, 0
  local bestDist = math.huge
  local bestRealDist = math.huge
  local bestT = 0

  local px, py = playerPos.x, playerPos.y
  local curSeg = tracking.segmentIndex

  for i, seg in ipairs(route.segments) do
    local projX, projY, t, dist = projectPointOnSegment(
      px, py,
      seg.fromPos.x, seg.fromPos.y,
      seg.toPos.x, seg.toPos.y
    )

    -- Bias toward current segment: give it a small distance bonus (2 tiles)
    -- This prevents oscillation between adjacent segments when near their junction
    local effectiveDist = dist
    if i == curSeg then
      effectiveDist = effectiveDist - 2
    -- Forward bias: slightly prefer the next segment when at a junction
    elseif curSeg > 0 and i == curSeg + 1 then
      effectiveDist = effectiveDist - 1
    -- Backward penalty: discourage jumping to previous segments
    elseif curSeg > 0 and i < curSeg then
      effectiveDist = effectiveDist + 3
    end

    if effectiveDist < bestDist then
      bestDist = effectiveDist
      bestRealDist = dist
      bestSegIdx = i
      bestProjX = projX
      bestProjY = projY
      bestT = t
    end
  end

  if bestSegIdx > 0 then
    return bestSegIdx, { x = bestProjX, y = bestProjY }, bestRealDist, bestT
  end

  return 0, nil, math.huge, 0
end

-- ============================================================================
-- FORWARD-ONLY WAYPOINT RESOLUTION
-- ============================================================================

--- Get the correct next waypoint for the player to walk to.
-- Always returns the END waypoint of the projected segment (forward only).
-- If player is >85% through current segment, advances to next segment.
-- @param playerPos table {x, y, z}
-- @return waypointIndex (or nil), waypointPos (or nil)
function WaypointNavigator.getNextWaypoint(playerPos)
  if not route.built or #route.segments == 0 or not playerPos then
    return nil, nil
  end

  local segIdx, _, distFromRoute, progress = WaypointNavigator.projectOntoRoute(playerPos)
  if segIdx == 0 then return nil, nil end

  -- Update tracking
  tracking.segmentIndex = segIdx
  tracking.progress = progress
  tracking.lastPlayerPos = playerPos
  tracking.lastUpdateTime = getNow()

  local seg = route.segments[segIdx]

  -- If player is near the end of the segment (>85% progress), advance to next
  if progress > 0.85 and segIdx < #route.segments then
    local nextSeg = route.segments[segIdx + 1]
    return nextSeg.toIdx, nextSeg.toPos
  end

  -- Otherwise, target the end of the current segment
  return seg.toIdx, seg.toPos
end

-- ============================================================================
-- PURE PURSUIT LOOKAHEAD
-- ============================================================================

--- Compute a Pure Pursuit lookahead target on the route.
-- Projects the player onto the route, then walks forward `lookahead` tiles
-- along the route from that projection. Returns a tile-rounded position.
--
-- This creates smooth, human-like movement:
-- - Player between WP#5 and WP#6 (4 tiles from WP#6, lookahead=12)
--   → target lands 8 tiles past WP#6 on WP#6→WP#7 segment
--   → A* pathfinds to that point, creating a smooth arc through WP#6
--   → No stop-and-go at each waypoint
--
-- @param playerPos table {x, y, z}
-- @return targetPos {x,y,z} (tile-rounded) or nil, segmentIndex
function WaypointNavigator.getLookaheadTarget(playerPos)
  if not route.built or #route.segments == 0 or not playerPos then
    return nil, 0
  end

  local segIdx, projPoint, distFromRoute, t = WaypointNavigator.projectOntoRoute(playerPos)
  if segIdx == 0 or not projPoint then return nil, 0 end

  local lookahead = pursuit.lookahead
  local baseSeg = route.segments[segIdx]
  local baseFloor = baseSeg.fromPos.z

  -- Remaining distance on current segment from projection point to segment end
  local rx = baseSeg.toPos.x - projPoint.x
  local ry = baseSeg.toPos.y - projPoint.y
  local rem = math.sqrt(rx * rx + ry * ry)

  -- Case 1: Lookahead fits within current segment
  if rem >= lookahead then
    local f = lookahead / math.max(rem, 0.01)
    return {
      x = math.floor(projPoint.x + f * rx + 0.5),
      y = math.floor(projPoint.y + f * ry + 0.5),
      z = baseFloor,
    }, segIdx
  end

  -- Case 2: Walk through subsequent segments until lookahead is exhausted
  local left = lookahead - rem
  for j = segIdx + 1, #route.segments do
    local seg = route.segments[j]
    -- Stop at floor boundaries (floor changes handled by existing floor-change system)
    if seg.fromPos.z ~= baseFloor then break end

    local sx = seg.toPos.x - seg.fromPos.x
    local sy = seg.toPos.y - seg.fromPos.y
    local sLen = math.sqrt(sx * sx + sy * sy)

    if sLen >= left then
      -- Lookahead lands within this segment
      local f = left / math.max(sLen, 0.01)
      return {
        x = math.floor(seg.fromPos.x + f * sx + 0.5),
        y = math.floor(seg.fromPos.y + f * sy + 0.5),
        z = baseFloor,
      }, j
    end
    left = left - sLen
  end

  -- Case 3: Past end of route — target the last waypoint position
  local lastSeg = route.segments[#route.segments]
  if lastSeg then
    return {
      x = lastSeg.toPos.x,
      y = lastSeg.toPos.y,
      z = lastSeg.toPos.z,
    }, #route.segments
  end

  return nil, 0
end

--- Check if the route has been built and has segments.
-- Convenience for callers to guard against calling getLookaheadTarget
-- when no route data is available.
-- @return boolean
function WaypointNavigator.isRouteBuilt()
  return route.built and #route.segments > 0
end

--- Get the ordered list of goto waypoint indices in the current route.
-- Used by recovery logic to walk forward from a blacklisted WP.
-- @return table  Array of waypoint list indices (ordered by route sequence)
function WaypointNavigator.getGotoIndices()
  return route.gotoIndices
end

--- Check if the player has passed a waypoint based on route projection.
-- When Pure Pursuit is active, the player may walk past a waypoint without
-- stepping within `precision` tiles of it (corner-cutting). This function
-- uses two complementary strategies:
-- 1. Segment index matching: if the WP's position matches a segment endpoint,
--    check if the player's projection is past that segment.
-- 2. Position-based: project the WP position onto the route and compare the
--    player's route-distance against the WP's route-distance. This handles
--    cases where the UI list index doesn't match any segment index (e.g.,
--    non-goto actions between gotos).
--
-- @param playerPos table {x, y, z}
-- @param waypointIdx number  The waypoint list index to check against
-- @param waypointPos table (optional) {x, y, z} position of the waypoint
-- @return boolean  true if the player has passed this waypoint on the route
function WaypointNavigator.hasPassedWaypoint(playerPos, waypointIdx, waypointPos)
  if not route.built or #route.segments == 0 or not playerPos then
    return false
  end

  local segIdx, _, _, progress = WaypointNavigator.projectOntoRoute(playerPos)
  if segIdx == 0 then return false end

  -- Strategy 1: Direct segment index matching (fast path)
  if waypointIdx then
    -- Check if this index is the endpoint of any segment
    for i, seg in ipairs(route.segments) do
      if seg.toIdx == waypointIdx then
        -- Player past this segment entirely
        if segIdx > i then return true end
        -- Player on same segment and near the end (lowered threshold for short segments)
        if segIdx == i and progress > 0.75 then return true end
        -- Player on a LATER segment in wrap-around routes
        return false
      end
    end
    -- Check if it's the start of a segment (first waypoint in route)
    for i, seg in ipairs(route.segments) do
      if seg.fromIdx == waypointIdx then
        if segIdx > i then return true end
        if segIdx == i and progress > 0.08 then return true end
        return false
      end
    end
  end

  -- Strategy 2: Position-based comparison (handles non-goto or mismatched indices)
  -- Project the waypoint position onto the route and compare cumulative distances.
  if waypointPos and waypointPos.z == playerPos.z then
    -- Compute cumulative route distance for the player
    local playerCumDist = 0
    for i = 1, segIdx - 1 do
      playerCumDist = playerCumDist + route.segments[i].length
    end
    playerCumDist = playerCumDist + progress * route.segments[segIdx].length

    -- Project waypoint position onto the route
    local wpBestSeg = 0
    local wpBestT = 0
    local wpBestDist = math.huge
    for i, seg in ipairs(route.segments) do
      local _, _, t, dist = projectPointOnSegment(
        waypointPos.x, waypointPos.y,
        seg.fromPos.x, seg.fromPos.y,
        seg.toPos.x, seg.toPos.y
      )
      if dist < wpBestDist then
        wpBestDist = dist
        wpBestSeg = i
        wpBestT = t
      end
    end

    if wpBestSeg > 0 and wpBestDist <= 3 then
      -- WP is close to the route — compute its cumulative distance
      local wpCumDist = 0
      for i = 1, wpBestSeg - 1 do
        wpCumDist = wpCumDist + route.segments[i].length
      end
      wpCumDist = wpCumDist + wpBestT * route.segments[wpBestSeg].length

      -- Player has passed the WP if they are at least 2 tiles ahead on the route
      if playerCumDist > wpCumDist + 2 then
        return true
      end
    end
  end

  return false
end

--- Set the Pure Pursuit lookahead distance.
-- @param tiles number  Lookahead distance in tiles (clamped to min/max)
function WaypointNavigator.setLookahead(tiles)
  if tiles and tiles > 0 then
    pursuit.lookahead = math.max(pursuit.minLookahead,
      math.min(pursuit.maxLookahead, tiles))
  end
end

--- Get current Pure Pursuit configuration (for debug/UI).
function WaypointNavigator.getPursuitConfig()
  return {
    lookahead = pursuit.lookahead,
    minLookahead = pursuit.minLookahead,
    maxLookahead = pursuit.maxLookahead,
  }
end

-- ============================================================================
-- CORRIDOR ENFORCEMENT
-- ============================================================================

--- Check if the player is within the route corridor.
-- Returns a status string, distance from centerline, and recovery info if outside.
-- @param playerPos table {x, y, z}
-- @return status ("inside"|"soft_boundary"|"outside"), distance, recoveryInfo (or nil)
function WaypointNavigator.checkCorridor(playerPos)
  if not route.built or #route.segments == 0 or not playerPos then
    return "inside", 0, nil  -- No route = no corridor enforcement
  end

  local segIdx, projPoint, distFromRoute, progress = WaypointNavigator.projectOntoRoute(playerPos)
  if segIdx == 0 then
    return "inside", 0, nil
  end

  -- Update tracking
  tracking.segmentIndex = segIdx
  tracking.progress = progress

  if distFromRoute <= corridor.width then
    -- Inside corridor: normal operation
    tracking.inCorridor = true
    tracking.consecutiveOutside = 0
    tracking.corridorExitTime = 0
    return "inside", distFromRoute, nil

  elseif distFromRoute <= corridor.softWidth then
    -- Soft boundary: player drifting, grace period before correction
    tracking.consecutiveOutside = tracking.consecutiveOutside + 1

    -- Require 3 consecutive ticks outside to confirm (prevents lag false positives)
    if tracking.consecutiveOutside >= 3 then
      local seg = route.segments[segIdx]
      return "soft_boundary", distFromRoute, {
        segmentIndex = segIdx,
        nextWpIdx = seg.toIdx,
        nextWpPos = seg.toPos,
        projectedPoint = projPoint,
      }
    end
    return "inside", distFromRoute, nil  -- Still in grace period

  else
    -- Outside corridor: immediate recovery needed
    tracking.inCorridor = false
    tracking.consecutiveOutside = tracking.consecutiveOutside + 1
    local currentNow = getNow()
    if tracking.corridorExitTime == 0 then
      tracking.corridorExitTime = currentNow
    end

    local seg = route.segments[segIdx]
    return "outside", distFromRoute, {
      segmentIndex = segIdx,
      nextWpIdx = seg.toIdx,
      nextWpPos = seg.toPos,
      projectedPoint = projPoint,
      distFromRoute = distFromRoute,
      timeOutside = currentNow - tracking.corridorExitTime,
    }
  end
end

--- Get recovery target when player is outside the corridor.
-- For small deviations, returns the next forward waypoint.
-- @param playerPos table {x, y, z}
-- @return waypointIndex (or nil), waypointPos (or nil), distFromRoute
function WaypointNavigator.getRecoveryTarget(playerPos)
  if not route.built or #route.segments == 0 or not playerPos then
    return nil, nil, 0
  end

  local segIdx, projPoint, distFromRoute, progress = WaypointNavigator.projectOntoRoute(playerPos)
  if segIdx == 0 then return nil, nil, 0 end

  local seg = route.segments[segIdx]
  return seg.toIdx, seg.toPos, distFromRoute
end

-- ============================================================================
-- DRIFT CHECK (simplified interface for WaypointEngine)
-- ============================================================================

--- Check if player has drifted off-route beyond the given threshold.
-- @param playerPos table {x, y, z}
-- @param threshold number  Distance threshold in tiles
-- @return isDrifted (bool), driftDistance (number)
function WaypointNavigator.checkDrift(playerPos, threshold)
  if not route.built or #route.segments == 0 or not playerPos then
    return false, 0
  end

  local _, _, distFromRoute, _ = WaypointNavigator.projectOntoRoute(playerPos)
  return distFromRoute > threshold, distFromRoute
end

-- ============================================================================
-- CORRIDOR CONFIGURATION
-- ============================================================================

--- Set the corridor width dynamically.
-- @param width number  Inner corridor width (tiles from centerline)
-- @param softWidth number (optional) Soft boundary width
-- @param hardWidth number (optional) Hard boundary width
function WaypointNavigator.setCorridorWidth(width, softWidth, hardWidth)
  if width and width > 0 then
    corridor.width = width
  end
  if softWidth and softWidth > corridor.width then
    corridor.softWidth = softWidth
  end
  if hardWidth and hardWidth > corridor.softWidth then
    corridor.hardWidth = hardWidth
  end
end

--- Get current corridor configuration (for debug/UI).
function WaypointNavigator.getCorridorConfig()
  return {
    width = corridor.width,
    softWidth = corridor.softWidth,
    hardWidth = corridor.hardWidth,
  }
end

-- ============================================================================
-- CACHE INVALIDATION
-- ============================================================================

--- Invalidate the route (called when waypoint cache changes).
function WaypointNavigator.invalidate()
  route.built = false
  route.segments = {}
  route.gotoIndices = {}
  route.waypointCount = 0

  tracking.segmentIndex = 0
  tracking.progress = 0
  tracking.lastPlayerPos = nil
  tracking.inCorridor = true
  tracking.corridorExitTime = 0
  tracking.consecutiveOutside = 0
end

-- ============================================================================
-- DEBUG / TELEMETRY
-- ============================================================================

--- Get current tracking state (for debug logging).
function WaypointNavigator.getCurrentSegment()
  if not route.built or tracking.segmentIndex == 0 then
    return nil
  end
  local seg = route.segments[tracking.segmentIndex]
  if not seg then return nil end
  return {
    index = tracking.segmentIndex,
    fromIdx = seg.fromIdx,
    toIdx = seg.toIdx,
    progress = tracking.progress,
    inCorridor = tracking.inCorridor,
    totalSegments = #route.segments,
  }
end

--- Get route summary (for debug).
function WaypointNavigator.getRouteSummary()
  return {
    built = route.built,
    floor = route.floor,
    segmentCount = #route.segments,
    gotoCount = #route.gotoIndices,
    waypointCount = route.waypointCount,
  }
end

return WaypointNavigator
