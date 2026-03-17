-- recovery_planner_v2.lua
-- 5-tier sequence-aware recovery ladder.
-- Used by NavigationV2 as fallback when WaypointNavigator cannot find a target.
--
-- Tier 1 (A): Forward-in-sequence, same floor, within maxGotoDist
-- Tier 2 (B): Nearest valid same-floor WP (distance-sorted + strict path check)
-- Tier 3 (C): Adjacent-floor (±1) rescue
-- Tier 4 (D): Backtrack window (up to 10 WPs behind, ignores blacklist)
-- Tier 5 (E): Global all-floor rescue sweep (intelligent loop through all WPs)

CaveBot = CaveBot or {}

local RecoveryPlanner = {
  lastTier = nil,
  tierHits = { 0, 0, 0, 0, 0 },
}

-- Chebyshev distance (matches OTClient diagonal-movement semantics).
local function cdist(a, b)
  if not a or not b then return math.huge end
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- Strict path-existence check: no ignoreNonPathable so walls block correctly.
-- Falls back optimistic when PathStrategy is unavailable.
local function hasPath(fromPos, toWp)
  if not fromPos or not toWp then return false end
  if fromPos.z ~= toWp.z then return true end  -- cross-floor: accepted, goto handles it
  local ps = (nExBot and nExBot.PathStrategy) or PathStrategy
  if not (ps and ps.findPath) then return true end
  local path = ps.findPath(fromPos, { x = toWp.x, y = toWp.y, z = toWp.z },
    { ignoreCreatures = true, maxDist = 70 })
  return path ~= nil and #path > 0
end

-- Record a tier hit and return the result triple for callers.
local function hitTier(n, child, idx)
  RecoveryPlanner.lastTier = n
  RecoveryPlanner.tierHits[n] = (RecoveryPlanner.tierHits[n] or 0) + 1
  return child, idx, n
end

-- findTarget(playerPos, isBlacklisted, waypointCache, focusedIdx, actionCount, hardStuck)
-- Returns: child, idx, tier  OR  nil, nil, nil
function RecoveryPlanner.findTarget(playerPos, isBlacklisted, waypointCache, focusedIdx, actionCount, hardStuck)
  if not playerPos or not waypointCache or actionCount == 0 then
    return nil, nil, nil
  end

  local maxDist = (CaveBot.getMaxGotoDistance and CaveBot.getMaxGotoDistance()) or 50
  local curIdx  = focusedIdx or 0

  -- ── TIER A: Forward-in-sequence, same floor ────────────────────────────────
  -- Pass 1: curIdx+1 → end.  Pass 2: wrap 1 → curIdx-1.
  for pass = 1, 2 do
    local iStart = (pass == 1) and (curIdx + 1) or 1
    local iEnd   = (pass == 1) and actionCount  or math.max(1, curIdx - 1)
    for i = iStart, iEnd do
      local wp = waypointCache[i]
      if wp and wp.isGoto and wp.z == playerPos.z then
        if not isBlacklisted(wp.child) and cdist(playerPos, wp) <= maxDist then
          return hitTier(1, wp.child, i)
        end
      end
    end
  end

  -- ── TIER B: Nearest valid same-floor (distance-sorted, path-checked) ────────
  local sameFloor = {}
  for i = 1, actionCount do
    local wp = waypointCache[i]
    if wp and wp.isGoto and wp.z == playerPos.z and (hardStuck or not isBlacklisted(wp.child)) then
      sameFloor[#sameFloor + 1] = { child = wp.child, idx = i, dist = cdist(playerPos, wp), wp = wp }
    end
  end
  table.sort(sameFloor, function(a, b) return a.dist < b.dist end)
  -- Prefer a candidate with a confirmed path.
  for _, c in ipairs(sameFloor) do
    if hasPath(playerPos, c.wp) then
      return hitTier(2, c.child, c.idx)
    end
  end
  -- Accept nearest even without confirmed path (goto callback will handle failure).
  if sameFloor[1] then
    return hitTier(2, sameFloor[1].child, sameFloor[1].idx)
  end

  -- ── TIER C: Adjacent floor ±1 rescue ──────────────────────────────────────
  local cross = {}
  for i = 1, actionCount do
    local wp = waypointCache[i]
    if wp and wp.isGoto and math.abs(wp.z - playerPos.z) == 1 and (hardStuck or not isBlacklisted(wp.child)) then
      cross[#cross + 1] = { child = wp.child, idx = i, dist = cdist(playerPos, wp) }
    end
  end
  table.sort(cross, function(a, b) return a.dist < b.dist end)
  if cross[1] then
    return hitTier(3, cross[1].child, cross[1].idx)
  end

  -- ── TIER D: Backtrack window (last 10 WPs, ignores blacklist for rescue) ────
  local back = {}
  local backStart = math.max(1, curIdx - 10)
  local backEnd   = math.max(1, curIdx - 1)
  for i = backEnd, backStart, -1 do
    local wp = waypointCache[i]
    if wp and wp.isGoto and wp.z == playerPos.z then
      back[#back + 1] = { child = wp.child, idx = i, dist = cdist(playerPos, wp) }
    end
  end
  table.sort(back, function(a, b) return a.dist < b.dist end)
  if back[1] then
    return hitTier(4, back[1].child, back[1].idx)
  end

  -- ── TIER E: Global all-floor rescue sweep ─────────────────────────────────
  -- Intelligent full-loop over every goto waypoint. Scores by floor proximity
  -- then distance, preferring path-confirmed same-floor candidates.
  local global = {}
  for i = 1, actionCount do
    local wp = waypointCache[i]
    if wp and wp.isGoto and (hardStuck or not isBlacklisted(wp.child)) then
      local floorDiff = math.abs((wp.z or playerPos.z) - playerPos.z)
      local dist = cdist(playerPos, wp)
      local score = (floorDiff * 1000) + dist
      global[#global + 1] = { child = wp.child, idx = i, wp = wp, score = score, floorDiff = floorDiff }
    end
  end

  table.sort(global, function(a, b) return a.score < b.score end)

  for _, g in ipairs(global) do
    if g.floorDiff > 0 or hasPath(playerPos, g.wp) then
      return hitTier(5, g.child, g.idx)
    end
  end

  if global[1] then
    return hitTier(5, global[1].child, global[1].idx)
  end

  return nil, nil, nil
end

function RecoveryPlanner.getMetrics()
  return {
    lastTier = RecoveryPlanner.lastTier,
    tierHits = {
      RecoveryPlanner.tierHits[1],
      RecoveryPlanner.tierHits[2],
      RecoveryPlanner.tierHits[3],
      RecoveryPlanner.tierHits[4],
      RecoveryPlanner.tierHits[5],
    },
  }
end

CaveBot.RecoveryPlanner = RecoveryPlanner
return RecoveryPlanner
