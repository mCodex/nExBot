local zChanging = nExBot.zChanging or function() return false end
local cavebotMacro = nil
local config = nil

-- TrimArray is set as a global by utils/ring_buffer.lua (Phase 3)
local TrimArray = TrimArray

-- Lazy PathStrategy resolver (sandbox doesn't have _G, so use nExBot namespace)
local function getPS()
  return (nExBot and nExBot.PathStrategy) or PathStrategy
end

-- Pure candidate-selection logic for findReachableWaypoint, extracted so it's
-- unit-testable without faking the OTClient runtime this file depends on
-- (see cavebot/waypoint_search.lua).
local WaypointSearch = (nExBot and nExBot.Nav and nExBot.Nav["cavebot.waypoint_search"])
  or (type(require) == "function" and require("cavebot.waypoint_search"))

-- Safe wrapper for CaveBot.resetWalking to prevent nil errors
local function safeResetWalking()
  if CaveBot and CaveBot.resetWalking then
    CaveBot.resetWalking()
  end
end

local ui = { list = nExBot.OrderedModel.new() }
CaveBot.Route = ui.list

if CaveBot.Editor then
  CaveBot.Editor.setup()
end
if CaveBot.Config then
  CaveBot.Config.setup()
end
for extension, callbacks in pairs(CaveBot.Extensions) do
  if callbacks.setup then
    callbacks.setup()
  end
end

-- main loop, controlled by config - OPTIMIZED VERSION
local actionRetries = 0
local prevActionResult = true
local lastDispatchedChild = nil  -- Track last WP to preserve PathCursor across retries

-- Cached UI list reference (avoid repeated lookups)
local uiList = nil
local lastPlayerFloor = nil

-- DRY: Single source of truth for gotoMaxDistance with fallback.
-- Used by goto callback, findReachableWaypoint, startup search, Z-change recovery.
CaveBot.getMaxGotoDistance = function()
  local raw = storage and storage.extras and storage.extras.gotoMaxDistance
  local n = tonumber(raw)
  return (n and n > 0) and n or 50
end

--[[
  SMART EXECUTION SYSTEM
  Reduces unnecessary macro executions by tracking walk state and using delays.
  
  Key optimizations:
  1. Skip execution while player is walking (wait for walk to complete)
  2. Skip execution if a delay is active (from previous action)
  3. Track last action to avoid redundant recalculations
  4. Only execute when there's actual work to do
]]
local walkState = {
  isWalkingToWaypoint = false,  -- Currently walking to a waypoint
  targetPos = nil,              -- Target position we're walking to
  lastActionTime = 0,           -- When we last executed an action
  delayUntil = 0,               -- Don't execute until this time
  lastPlayerPos = nil,          -- Last known player position
  stuckCheckTime = 0,           -- When to check if stuck
  STUCK_TIMEOUT = 3000          -- Consider stuck after 3 seconds of no movement
}

-- Forward-declare for hasPlayerMoved (full definition below in WAYPOINT ENGINE section)
local WaypointEngine

-- Check if player has moved since last check
local function hasPlayerMoved()
  local currentPos = pos()
  if not currentPos or not walkState.lastPlayerPos then
    walkState.lastPlayerPos = currentPos
    return true
  end
  
  local moved = (currentPos.x ~= walkState.lastPlayerPos.x or
                 currentPos.y ~= walkState.lastPlayerPos.y or
                 currentPos.z ~= walkState.lastPlayerPos.z)
  
  if moved then
    walkState.lastPlayerPos = currentPos
    walkState.stuckCheckTime = now + walkState.STUCK_TIMEOUT
  end
  
  return moved
end

-- Check if we should skip execution
-- Allows mid-walk verification every ~150ms to detect stuck/blocked states
local function shouldSkipExecution()
  -- Active delay from previous action
  if now < walkState.delayUntil then
    return true
  end
  
  -- Player is actively walking — allow through every 150ms for mid-walk verification
  if player:isWalking() then
    if not walkState.lastVerifyTime then
      walkState.lastVerifyTime = now
    end
    
    -- Allow mid-walk check every 150ms (faster re-dispatch for smoother movement)
    -- Scale verification interval: shorter for close WPs (faster response)
    local verifyInterval = (walkState.walkStartDist or 20) <= 5 and 75
                        or (walkState.walkStartDist or 20) <= 15 and 100
                        or 150
    if (now - walkState.lastVerifyTime) >= verifyInterval then
      walkState.lastVerifyTime = now
      
      -- HARD TIMEOUT: Absolute ceiling regardless of walkExpectedDuration
      -- Prevents infinite walking when duration is nil (race during z-change)
      if walkState.walkStartTime then
        local elapsed = now - walkState.walkStartTime
        local HARD_TIMEOUT = 8000  -- 8 seconds absolute maximum
        local expectedDur = walkState.walkExpectedDuration or 5000  -- Fallback 5s if nil
        local softTimeout = expectedDur * 1.5
        
        if elapsed > HARD_TIMEOUT or elapsed > softTimeout then
          -- Walking too long — stop and let macro recompute
          if player.stopAutoWalk then
            pcall(player.stopAutoWalk, player)
          end
          local ps = getPS()
          if ps and ps.resetCursor then ps.resetCursor() end
          walkState.isWalkingToWaypoint = false
          walkState.targetPos = nil
          return false  -- Don't skip — let macro handle it
        end
      end
      
      -- Check if distance to target is decreasing (Chebyshev + rolling minimum)
      -- Chebyshev matches OTClient diagonal movement better than Manhattan,
      -- reducing false "regression" stops on curved paths around obstacles.
      if walkState.targetPos then
        local currentPos = pos()
        if currentPos then
          local curDist = math.max(
            math.abs(currentPos.x - walkState.targetPos.x),
            math.abs(currentPos.y - walkState.targetPos.y)
          )
          -- Track rolling minimum distance (handles curved/obstacle paths)
          if not walkState.minDist or curDist < walkState.minDist then
            walkState.minDist = curDist
          end
          -- Scale regression tolerance: generous for U-shaped cave corridors
          local tolerance = math.max(3, math.floor((walkState.walkStartDist or 20) * 0.6))
          if walkState.minDist and curDist > walkState.minDist + tolerance then
            -- Getting farther from closest point — stop and recompute
            if player.stopAutoWalk then
              pcall(player.stopAutoWalk, player)
            end
            local ps = getPS()
            if ps and ps.resetCursor then ps.resetCursor() end
            walkState.isWalkingToWaypoint = false
            walkState.targetPos = nil
            return false
          end
          -- Elapsed-progress check: if walking > 3s with zero distance decrease, stuck
          -- Disabled for short walks (≤8 tiles) — the no-progress timer handles those
          if walkState.walkStartTime and walkState.walkStartDist and (walkState.walkStartDist or 99) > 8 then
            local elapsed = now - walkState.walkStartTime
            if elapsed > 3000 and curDist >= walkState.walkStartDist then
              if player.stopAutoWalk then
                pcall(player.stopAutoWalk, player)
              end
              local ps = getPS()
              if ps and ps.resetCursor then ps.resetCursor() end
              walkState.isWalkingToWaypoint = false
              walkState.targetPos = nil
              return false
            end
          end
        end
      end
    end
    
    return true  -- Still walking, skip this tick
  end
  
  -- If player stopped walking, clear the walking state
  if walkState.isWalkingToWaypoint then
    walkState.isWalkingToWaypoint = false
    walkState.targetPos = nil
  end
  walkState.lastVerifyTime = nil
  
  return false
end

-- Mark that we're walking to a waypoint (with mid-walk tracking)
CaveBot.setWalkingToWaypoint = function(targetPos)
  walkState.isWalkingToWaypoint = true
  walkState.targetPos = targetPos
  walkState.stuckCheckTime = now + walkState.STUCK_TIMEOUT
  walkState.lastPlayerPos = pos()
  walkState.walkStartTime = now
  walkState.lastVerifyTime = now
  walkState.minDist = nil  -- Reset rolling minimum for new walk
  -- Calculate expected duration based on distance
  local currentPos = pos()
  if currentPos and targetPos then
    local manhattan = math.abs(currentPos.x - targetPos.x) + math.abs(currentPos.y - targetPos.y)
    local ps = getPS()
    local stepDur = (ps and ps.rawStepDuration and ps.rawStepDuration(false)) or 200
    walkState.walkExpectedDuration = manhattan * stepDur
    -- Record Chebyshev: the elapsed-progress check uses Chebyshev distance,
    -- so walkStartDist must match to avoid false "no decrease" on diagonal moves.
    walkState.walkStartDist = math.max(
      math.abs(currentPos.x - targetPos.x),
      math.abs(currentPos.y - targetPos.y)
    )
  else
    walkState.walkExpectedDuration = nil
    walkState.walkStartDist = nil
  end

end

-- Clear walking state
CaveBot.clearWalkingState = function()
  walkState.isWalkingToWaypoint = false
  walkState.targetPos = nil
  walkState.walkStartTime = nil
  walkState.walkExpectedDuration = nil
  walkState.walkStartDist = nil
  walkState.minDist = nil
  walkState.lastVerifyTime = nil
end

-- FORWARD DECLARATIONS (functions defined later but used early)
local findNearestGlobalWaypoint  -- Defined in WAYPOINT FINDER section
local findReachableWaypoint      -- Unified search (TSP scoring), defined in WAYPOINT FINDER
local checkStartupWaypoint       -- Defined in STARTUP DETECTION section
local invalidateWaypointCache    -- Defined in WAYPOINT CACHE section
local resetStartupCheck          -- Defined in STARTUP DETECTION section
local buildWaypointCache         -- Defined in WAYPOINT CACHE section
local findNearestSameFloorGoto   -- Defined after buildWaypointCache
local focusWaypointForRecovery   -- Defined in RECOVERY STRATEGIES section
local resetWaypointEngine        -- Defined below runWaypointEngine
local chebyshevDist = Directions.chebyshevDistance  -- SSoT: constants/directions.lua
local waypointPositionCache = {} -- Waypoint position cache table
local waypointCacheValid = false
local waypointCacheFloors = {}
local startupWaypointFound = false
local startupCheckTime = nil   -- Set on first check to enforce 500ms delay
local startupFocusTarget = nil -- Fallback child ref when focusChild fails on startup

--[[
  WAYPOINT ENGINE
  
  Simple stuck detection → recovery → blacklist system.
  Recovery picks nearest non-blacklisted WP by distance.
  No path prevalidation — the goto callback is the real validator.
]]

-- WAYPOINT ENGINE STATE

WaypointEngine = {
  -- State machine: NORMAL ↔ RECOVERING
  state = "NORMAL",
  failureCount = 0,
  FAILURE_THRESHOLD = 3,

  -- Waypoint blacklist: skip unreachable WPs during distance scan.
  -- Uses adaptive exponential decay TTL instead of permanent blacklists.
  stuckWaypoints = {},
  stuckFailCounts = {},          -- per-WP failure count for exponential decay
  BLACKLIST_BASE_TTL = 15000,    -- 15s base TTL
  BLACKLIST_MAX_TTL  = 120000,   -- 2 min cap

  -- Recovery coordination
  recoveryJustFocused = false,   -- suppress actionRetries reset after recovery focus
  lastRecoverySearch = 0,        -- throttle recovery searches (1/sec)
  recoveryStartedAt = 0,         -- when current recovery session began
  RECOVERY_IDLE_TIMEOUT = 300000,-- 5 min: clear blacklists if completely stuck

  -- Drift detection: proactive refocus to nearest WP when player drifts too far
  -- NOTE: Corridor enforcement (navigation context) is now the primary drift detector.
  -- These thresholds serve as fallback when the navigator is unavailable.
  DRIFT_THRESHOLD_RATIO = 0.20,  -- refocus when dist > maxDist * ratio (~10 tiles for maxDist=50)
  DRIFT_CHECK_INTERVAL  = 1000,  -- periodic check every 1s
  DRIFT_HYSTERESIS      = 5,     -- nearest must be >=5 tiles closer to justify switch
  REFOCUS_COOLDOWN      = 1500,  -- min 1.5s between refocuses (prevents walk-cancel loops)
  lastDriftCheck    = 0,
  lastRefocusTime   = 0,
  wasTargetBotBlocking = false,
  postCombatUntil      = 0,      -- tighter corridor check for 3s after combat ends

  -- Reachability search bounds (findReachableWaypoint): real A* validation is
  -- expensive, so it's capped by a work budget rather than a fixed rank
  -- cutoff -- candidates past the budget are left unvalidated and skipped,
  -- never blindly trusted by distance (that was the old behavior and picked
  -- unreachable WPs when they happened to rank just past the cutoff).
  PATH_VALIDATION_BUDGET = 12,
  -- Cross-floor fallback: how many floors above/below to consider, ordered
  -- nearest-|Δz|-first. Each candidate floor is still only distance-ranked
  -- (no cross-floor A*, since reaching another floor requires an actual
  -- stair/rope transition this engine doesn't model as a graph) but the
  -- search is no longer limited to exactly one floor up or down.
  MAX_FLOOR_SEARCH_RADIUS = 3,

  -- Performance: avoid redundant UI lookups
  tickCount = 0,
  lastTickTime = 0,
}

-- BLACKLIST UTILITIES

local function isWaypointBlacklisted(child)
  if not child then return false end
  local expiry = WaypointEngine.stuckWaypoints[child]
  if not expiry then return false end
  if expiry <= now then
    WaypointEngine.stuckWaypoints[child] = nil
    return false
  end
  return true
end

local function blacklistWaypoint(child)
  if not child then return end
  -- Exponential decay: base_ttl * 2^(fail_count), capped at max_ttl
  local failCount = (WaypointEngine.stuckFailCounts[child] or 0) + 1
  WaypointEngine.stuckFailCounts[child] = failCount
  local ttl = math.min(
    WaypointEngine.BLACKLIST_BASE_TTL * (2 ^ (failCount - 1)),
    WaypointEngine.BLACKLIST_MAX_TTL
  )
  WaypointEngine.stuckWaypoints[child] = now + ttl
end

local function clearWaypointBlacklist()
  for k in pairs(WaypointEngine.stuckWaypoints) do
    WaypointEngine.stuckWaypoints[k] = nil
  end
  for k in pairs(WaypointEngine.stuckFailCounts) do
    WaypointEngine.stuckFailCounts[k] = nil
  end
end

-- STATE MACHINE (NORMAL ↔ RECOVERING)

local function transitionTo(newState)
  WaypointEngine.state = newState
  if newState == "RECOVERING" then
    -- Adaptive blacklist: exponential decay instead of permanent.
    -- Prevents cascading exclusion of nearby valid WPs.
    local current = ui and ui.list and ui.list:getFocusedChild()
    if current and current.action == "goto" then
      blacklistWaypoint(current)
    end
    if WaypointEngine.recoveryStartedAt == 0 then
      WaypointEngine.recoveryStartedAt = now
    end
  elseif newState == "NORMAL" then
    WaypointEngine.failureCount = 0
    WaypointEngine.recoveryStartedAt = 0
  end
end

local function recordSuccess()
  WaypointEngine.failureCount = 0
  -- Clear blacklists for same-floor WPs only.
  -- Cross-floor WPs stay blacklisted to prevent cycling:
  -- arrive→advance→Z-mismatch→instantFail→recovery→arrive→repeat
  local pz = pos()
  local playerFloor = pz and pz.z
  for child, expiry in pairs(WaypointEngine.stuckWaypoints) do
    -- Clear if: same floor, OR no position info (non-goto), OR no player pos
    local childIdx = ui.list:getChildIndex(child)
    local wp = waypointPositionCache[childIdx]
    if not playerFloor or not wp or wp.z == playerFloor then
      WaypointEngine.stuckWaypoints[child] = nil
      WaypointEngine.stuckFailCounts[child] = nil
    end
  end
  WaypointEngine.recoveryStartedAt = 0
  if WaypointEngine.state ~= "NORMAL" then
    transitionTo("NORMAL")
  end
end

local function recordFailure()
  WaypointEngine.failureCount = WaypointEngine.failureCount + 1
end

-- RECOVERY

-- Focus a waypoint for recovery (cancel walk, reset retries)
focusWaypointForRecovery = function(targetChild, targetIndex)
  if CaveBot.stopAutoWalk then CaveBot.stopAutoWalk() end
  local ok, err = pcall(ui.list.focusChild, ui.list, targetChild)
  if not ok then
    startupFocusTarget = targetChild
  end
  actionRetries = 0
  WaypointEngine.recoveryJustFocused = true
end

-- DRIFT DETECTION: Proactive nearest-WP refocus
-- When the player drifts far from the current WP (e.g. after chasing a monster),
-- find and focus the nearest reachable WP instead of walking all the way back.

local function maybeRefocusNearestWaypoint(playerPos)
  if not playerPos then return false end
  -- Only in NORMAL state (RECOVERING has its own finder)
  if WaypointEngine.state ~= "NORMAL" then return false end
  -- Don't interrupt mid-walk
  if player:isWalking() then return false end
  -- Cooldown
  if (now - WaypointEngine.lastRefocusTime) < WaypointEngine.REFOCUS_COOLDOWN then return false end

  -- PRIMARY: Corridor + segment-aware drift detection
  if nExBot.Navigation and type(CaveBot.ensureNavigatorRoute) == 'function' then
    CaveBot.ensureNavigatorRoute(playerPos.z)
    local isDrifted, driftDist
    if type(nExBot.Navigation.checkDrift) == 'function' then
      isDrifted, driftDist = nExBot.Navigation.checkDrift(playerPos,
        math.floor(CaveBot.getMaxGotoDistance() * WaypointEngine.DRIFT_THRESHOLD_RATIO))
    end

    if isDrifted then
      local wpIdx, wpPos
      if type(nExBot.Navigation.getNextWaypoint) == 'function' then
        wpIdx, wpPos = nExBot.Navigation.getNextWaypoint(playerPos)
      end
      if wpIdx then
        local wp = waypointPositionCache[wpIdx]
        if wp and wp.child and not isWaypointBlacklisted(wp.child) then
          print("[CaveBot] Segment drift: " .. math.floor(driftDist) .. " tiles off-route, focusing WP" .. wpIdx)
          focusWaypointForRecovery(wp.child, wpIdx)
          WaypointEngine.lastRefocusTime = now
          return true
        end
      end
      -- Navigator detected drift but couldn't find a good WP; fall through to legacy
    elseif type(nExBot.Navigation.isRouteBuilt) == 'function' and nExBot.Navigation.isRouteBuilt() then
      return false  -- route is usable and player is not drifted
    end
    -- No usable route (< 2 goto WPs on this floor); fall through to legacy
  end

  -- FALLBACK: Legacy distance-based drift detection
  buildWaypointCache()
  local currentIdx = 0
  if ui and ui.list then
    local focused = ui.list:getFocusedChild()
    if focused then currentIdx = ui.list:getChildIndex(focused) end
  end
  if currentIdx == 0 then return false end

  local currentWp = waypointPositionCache[currentIdx]
  if not currentWp then return false end
  -- Skip if player is on a different floor (floor-change logic handles that)
  if currentWp.z ~= playerPos.z then return false end

  local currentDist = chebyshevDist(playerPos, currentWp)
  local threshold = math.floor(CaveBot.getMaxGotoDistance() * WaypointEngine.DRIFT_THRESHOLD_RATIO)
  if currentDist <= threshold then return false end

  -- Player is far from current WP — find nearest reachable goto WP
  local bestChild, bestIdx = findReachableWaypoint(playerPos, { excludeCurrent = true, forceDistanceBased = true })
  if not bestChild then return false end

  local bestWp = waypointPositionCache[bestIdx]
  if not bestWp then return false end
  local bestDist = chebyshevDist(playerPos, bestWp)

  -- Hysteresis: only switch if the nearest WP is meaningfully closer
  if (currentDist - bestDist) < WaypointEngine.DRIFT_HYSTERESIS then return false end

  -- Refocus to the nearer waypoint
  print("[CaveBot] Drift detected (" .. currentDist .. " tiles from WP" .. currentIdx .. ") — refocusing to WP" .. bestIdx .. " (" .. bestDist .. " tiles)")
  focusWaypointForRecovery(bestChild, bestIdx)
  WaypointEngine.lastRefocusTime = now
  return true
end

local function executeRecovery()
  -- Throttle: search at most once per second while idling
  if (now - WaypointEngine.lastRecoverySearch) < 1000 then
    return true  -- stay in RECOVERING, skip this tick
  end
  WaypointEngine.lastRecoverySearch = now

  local playerPos = player:getPosition()
  if not playerPos then return true end

  -- Safety valve: if stuck too long, clear blacklists and try everything fresh
  if WaypointEngine.recoveryStartedAt > 0 and
     (now - WaypointEngine.recoveryStartedAt) > WaypointEngine.RECOVERY_IDLE_TIMEOUT then
    warn("[CaveBot] Recovery idle timeout (" .. math.floor(WaypointEngine.RECOVERY_IDLE_TIMEOUT/1000) .. "s) — clearing blacklists")
    clearWaypointBlacklist()
    WaypointEngine.recoveryStartedAt = now  -- reset timer for next cycle
  end

  -- PRIMARY: Segment-aware forward-only recovery via the navigation context
  if nExBot.Navigation and type(CaveBot.ensureNavigatorRoute) == 'function' then
    CaveBot.ensureNavigatorRoute(playerPos.z)
    local wpIdx, wpPos
    if type(nExBot.Navigation.getNextWaypoint) == 'function' then
      wpIdx, wpPos = nExBot.Navigation.getNextWaypoint(playerPos)
    end
    if wpIdx then
      local wp = waypointPositionCache[wpIdx]
      -- If navigator's suggestion is blacklisted, walk forward through gotoIndices
      if wp and wp.child and isWaypointBlacklisted(wp.child) then
        local gotoIndices = nExBot.Navigation.getGotoIndices and nExBot.Navigation.getGotoIndices() or {}
        local originalWpIdx = wpIdx
        local startFound = false
        -- Forward search: from the suggested WP onward
        for _, gIdx in ipairs(gotoIndices) do
          if gIdx == originalWpIdx then startFound = true end
          if startFound and gIdx ~= originalWpIdx then
            local fwdWp = waypointPositionCache[gIdx]
            if fwdWp and fwdWp.child and not isWaypointBlacklisted(fwdWp.child) and fwdWp.z == playerPos.z then
              wp = fwdWp
              wpIdx = gIdx
              break
            end
          end
        end
        -- Wrap around: check from beginning of gotoIndices up to original
        if isWaypointBlacklisted(wp.child) then
          for _, gIdx in ipairs(gotoIndices) do
            if gIdx == originalWpIdx then break end
            local fwdWp = waypointPositionCache[gIdx]
            if fwdWp and fwdWp.child and not isWaypointBlacklisted(fwdWp.child) and fwdWp.z == playerPos.z then
              wp = fwdWp
              wpIdx = gIdx
              break
            end
          end
        end
      end
      if wp and wp.child and not isWaypointBlacklisted(wp.child) then
        -- If we're already within arrival distance (3 tiles) of this WP,
        -- skip to the WP after it to avoid the loop:
        -- recovery→WP#N→instant arrive→WP#N+1→walk fail→recovery→WP#N...
        local d = math.max(math.abs(playerPos.x - wp.x), math.abs(playerPos.y - wp.y))
        if d <= 3 then
          -- Focus this WP so the main loop can advance past it immediately
          ui.list:focusChild(wp.child)
          actionRetries = 0
          transitionTo("NORMAL")
          return true
        end
        -- print("[CaveBot] Recovery (segment-aware): focusing forward WP" .. wpIdx)
        focusWaypointForRecovery(wp.child, wpIdx)
        transitionTo("NORMAL")
        return true
      end
    end
  end

  -- FALLBACK: Same-floor nearest non-blacklisted WP by distance
  local child, idx = findReachableWaypoint(playerPos, { maxCandidates = 30 })
  if child then
    print("[CaveBot] Recovery: focusing waypoint " .. idx)
    focusWaypointForRecovery(child, idx)
    transitionTo("NORMAL")
    return true
  end

  -- Floor-change tile recovery: find nearest stair/rope/ladder on current floor
  -- that leads to a floor with waypoints. Scans minimap colors for floor-change tiles.
  local function findNearestFloorChangeTile(pPos, targetFloors)
    local getMinimapColor = g_map and g_map.getMinimapColor
    if not getMinimapColor then return nil end
    local FC_COLORS = { [210]=true, [211]=true, [212]=true, [213]=true }
    local best, bestDist = nil, math.huge
    -- Scan 8-tile radius around player
    for dx = -8, 8 do
      for dy = -8, 8 do
        local tilePos = {x = pPos.x + dx, y = pPos.y + dy, z = pPos.z}
        local ok, color = pcall(getMinimapColor, tilePos)
        if ok and FC_COLORS[color] then
          local d = math.abs(dx) + math.abs(dy)
          if d < bestDist then
            bestDist = d
            best = tilePos
          end
        end
      end
    end
    return best
  end

  -- Determine which floors have WPs
  local floorsWithWPs = {}
  for _, wp in pairs(waypointPositionCache) do
    if wp.isGoto then floorsWithWPs[wp.z] = true end
  end
  local targetFloors = {}
  for floorZ in pairs(floorsWithWPs) do
    if floorZ ~= playerPos.z then targetFloors[#targetFloors + 1] = floorZ end
  end

  if #targetFloors > 0 then
    local fcTile = findNearestFloorChangeTile(playerPos, targetFloors)
    if fcTile then
      -- Walk to the floor-change tile; Z-change handler at top of macro will
      -- transition to NORMAL after the actual floor change fires. Don't
      -- transition here — if the walk stalls we stay in RECOVERING.
      print("[CaveBot] Recovery: walking to floor-change tile at " .. fcTile.x .. "," .. fcTile.y .. "," .. fcTile.z)
      CaveBot.walkTo(fcTile, 20, { allowFloorChange = true, precision = 0 })
      return true  -- stay in RECOVERING until Z-change handler fires
    end
  end

  -- Cross-floor fallback (adjacent floors ±1)
  child, idx = findReachableWaypoint(playerPos, { maxCandidates = 30, searchAllFloors = true })
  if child then
    print("[CaveBot] Recovery: cross-floor waypoint " .. idx)
    focusWaypointForRecovery(child, idx)
    transitionTo("NORMAL")
    return true
  end

  -- No reachable WP found — idle in RECOVERING state.
  -- Don't skip to next index (causes instantFail cascade → all blacklisted → clear → repeat).
  -- The safety valve above will clear blacklists after the idle timeout.
  return true
end

-- MAIN ENGINE TICK (called from macro loop)

local function runWaypointEngine()
  local state = WaypointEngine.state

  if state == "NORMAL" then
    if WaypointEngine.failureCount >= WaypointEngine.FAILURE_THRESHOLD then
      transitionTo("RECOVERING")
      return true
    end
    return false

  elseif state == "RECOVERING" then
    executeRecovery()
    return true
  end

  return false
end

-- Reset engine state
resetWaypointEngine = function()
  WaypointEngine.state = "NORMAL"
  WaypointEngine.failureCount = 0
  WaypointEngine.recoveryJustFocused = false
  WaypointEngine.lastRecoverySearch = 0
  WaypointEngine.recoveryStartedAt = 0
  WaypointEngine.lastDriftCheck = 0
  WaypointEngine.lastRefocusTime = 0
  WaypointEngine.wasTargetBotBlocking = false
  WaypointEngine.postCombatUntil = 0
  lastDispatchedChild = nil
end

-- Cache TargetBot function references (avoid repeated table lookups)
local targetBotIsActive = nil
local targetBotIsCaveBotAllowed = nil

local function initTargetBotCache()
  if TargetBot then
    targetBotIsActive = TargetBot.isActive
    targetBotIsCaveBotAllowed = TargetBot.isCaveBotActionAllowed
  end
end

-- EVENTBUS INTEGRATION: Instant waypoint arrival detection

-- Track current waypoint target for instant arrival detection
local currentWaypointTarget = {
  pos = nil,
  precision = 1,
  arrived = false,
  arrivedTime = 0
}

-- Check if player is at waypoint position
local function isAtWaypoint(playerPos, waypointPos, precision)
  if not playerPos or not waypointPos then return false end
  if playerPos.z ~= waypointPos.z then return false end
  local dx = math.abs(playerPos.x - waypointPos.x)
  local dy = math.abs(playerPos.y - waypointPos.y)
  return dx <= precision and dy <= precision
end

-- Set current waypoint target (called from goto action)
CaveBot.setCurrentWaypointTarget = function(pos, precision)
  currentWaypointTarget.pos = pos
  currentWaypointTarget.precision = precision or 1
  currentWaypointTarget.arrived = false
  currentWaypointTarget.arrivedTime = 0
end

-- Check if we've arrived at current waypoint
CaveBot.hasArrivedAtWaypoint = function()
  return currentWaypointTarget.arrived
end

-- Clear waypoint target
CaveBot.clearWaypointTarget = function()
  currentWaypointTarget.pos = nil
  currentWaypointTarget.arrived = false
end

-- EventBus: Instant waypoint arrival detection
if EventBus then
  EventBus.on("player:move", function(newPos, oldPos)
    if not currentWaypointTarget.pos then return end
    if not newPos then return end
    
    -- Check if we arrived at the waypoint
    if isAtWaypoint(newPos, currentWaypointTarget.pos, currentWaypointTarget.precision) then
      currentWaypointTarget.arrived = true
      currentWaypointTarget.arrivedTime = now
      -- Emit event for other modules
      pcall(function() EventBus.emit("cavebot:waypoint_arrived", currentWaypointTarget.pos) end)
    end
  end, 5)  -- High priority
end

local function pauseIntelligenceRoute(reason)
  local route = nExBot and nExBot.Intelligence and nExBot.Intelligence.route
  if route then route:pause(reason) end
end

cavebotMacro = macro(75, function()  -- 75ms for smooth, responsive walking
  -- Guard: forward-declared functions may not be assigned yet during reload
  if not buildWaypointCache then return end

  -- Z-LEVEL CHANGE: Must run BEFORE shouldSkipExecution so stale delays
  -- from the old floor can't block rescue. All Z changes handled identically
  -- (no intended/accidental distinction).
  local playerPos = player and player:getPosition()
  if playerPos and lastPlayerFloor and playerPos.z ~= lastPlayerFloor then
    -- Clear ALL stale state from old floor
    walkState.delayUntil = 0
    cavebotMacro.delay = nil
    clearWaypointBlacklist()
    safeResetWalking()
    resetWaypointEngine()
    -- Focus nearest same-Z goto WP (pure distance, no path validation)
    local child, idx = findNearestSameFloorGoto(playerPos, playerPos.z, CaveBot.getMaxGotoDistance())
    if child then
      print("[CaveBot] Z-change (" .. lastPlayerFloor .. "→" .. playerPos.z .. "): focusing WP" .. idx)
      focusWaypointForRecovery(child, idx)
    end
    lastPlayerFloor = playerPos.z
    return  -- Consume this tick for the Z transition
  end
  if playerPos then lastPlayerFloor = playerPos.z end

  -- SMART EXECUTION: Skip if we shouldn't execute this tick
  if shouldSkipExecution() then return end

  -- Update player position tracking
  hasPlayerMoved()

  -- Z-change guard: skip heavy processing during floor transitions
  if zChanging() then return end
  
  -- STARTUP DETECTION: Find nearest waypoint on relog/load
  -- Note: checkStartupWaypoint is defined later in file, check if available
  if checkStartupWaypoint then
    checkStartupWaypoint()
  end
  
  -- Guard: skip action processing until startup check completes
  if not startupWaypointFound then return end
  
  -- WAYPOINT ENGINE: High-performance stuck detection and recovery
  if runWaypointEngine() then
    return  -- Engine handled recovery, skip normal processing
  end
  
  -- Lazy-init TargetBot cache
  if not targetBotIsActive and TargetBot then
    initTargetBotCache()
  end
  
  -- Check TargetBot allows CaveBot action (cached function refs)
  local targetBotBlocking = false
  if targetBotIsActive and targetBotIsActive() then
    if targetBotIsCaveBotAllowed and not targetBotIsCaveBotAllowed() then
      safeResetWalking()
      pauseIntelligenceRoute("targetbot")
      WaypointEngine.wasTargetBotBlocking = true
      return
    end
    
    -- PULL SYSTEM PAUSE: If smartPull is active, pause waypoint walking
    if TargetBot.smartPullActive then
      safeResetWalking()
      pauseIntelligenceRoute("pull")
      WaypointEngine.wasTargetBotBlocking = true
      return
    end
    
    -- MONSTER DETECTION: Pause for targetable monsters on screen
    -- Defer to TargetBot's cavebotAllowance: when TargetBot has evaluated all
    -- monsters and explicitly allowed CaveBot (e.g., all targets unreachable),
    -- respect that decision instead of blocking based on passive monster detection.
    if TargetBot.shouldWaitForMonsters and TargetBot.shouldWaitForMonsters() then
      if not (targetBotIsCaveBotAllowed and targetBotIsCaveBotAllowed()) then
        safeResetWalking()
        pauseIntelligenceRoute("monsters")
        WaypointEngine.wasTargetBotBlocking = true
        return
      end
    end

    -- ASM BACKUP: block CaveBot while attack is in progress
    if AttackStateMachine and AttackStateMachine.isActive and AttackStateMachine.isActive() then
      if not (targetBotIsCaveBotAllowed and targetBotIsCaveBotAllowed()) then
        safeResetWalking()
        pauseIntelligenceRoute("attack")
        WaypointEngine.wasTargetBotBlocking = true
        return
      end
    end
    
    -- BACKUP CHECK: If EventTargeting reports combat active, also pause
    if EventTargeting and EventTargeting.isCombatActive and EventTargeting.isCombatActive() then
      if not (targetBotIsCaveBotAllowed and targetBotIsCaveBotAllowed()) then
        safeResetWalking()
        pauseIntelligenceRoute("combat")
        WaypointEngine.wasTargetBotBlocking = true
        return
      end
    end
  end

  local intelligenceRoute = nExBot and nExBot.Intelligence and nExBot.Intelligence.route
  if intelligenceRoute and intelligenceRoute.state == "paused" then intelligenceRoute:resume() end
  
  -- DRIFT DETECTION: Proactive nearest-WP refocus
  -- Trigger 1: Combat just ended (TargetBot was blocking, now allows CaveBot)
  if WaypointEngine.wasTargetBotBlocking then
    WaypointEngine.wasTargetBotBlocking = false
    WaypointEngine.lastRefocusTime = 0  -- Bypass cooldown for post-combat
    WaypointEngine.postCombatUntil = now + 3000  -- 3s aggressive corridor window
    -- Immediate corridor check for fast return-to-track.
    -- Delegated to the navigation session: recovery targets route-graph nodes
    -- only and suppresses repeats without new evidence (WP26 fix) — it never
    -- re-focuses the same unreachable waypoint back-to-back.
    if nExBot.Navigation and type(nExBot.Navigation.recoverCorridor) == 'function'
       and type(CaveBot.ensureNavigatorRoute) == 'function' then
      local pp = pos()
      if pp then
        CaveBot.ensureNavigatorRoute(pp.z)
        if nExBot.Navigation.recoverCorridor(pp) then
          WaypointEngine.lastRefocusTime = now
          return
        end
      end
    end
    -- Fallback to legacy refocus
    local pp = pos()
    if pp and maybeRefocusNearestWaypoint(pp) then
      return
    end
  end

  -- Trigger 2: Corridor enforcement (checked every tick when not walking/in-combat)
  -- During post-combat window (3s): "margin" triggers too (catch 6-15 tile drift from chase).
  -- Otherwise: only hard "outside" (15+ tiles) to avoid interfering with normal A* detours.
  if nExBot.Navigation and playerPos and not player:isWalking() then
    -- Guard: skip if the current goto action was just dispatched recently
    -- (prevents canceling a walk between A* pathfinder steps)
    if (now - WaypointEngine.lastRefocusTime) >= WaypointEngine.REFOCUS_COOLDOWN
       and type(nExBot.Navigation.recoverCorridor) == 'function'
       and type(CaveBot.ensureNavigatorRoute) == 'function' then
      CaveBot.ensureNavigatorRoute(playerPos.z)
      if nExBot.Navigation.recoverCorridor(playerPos) then
        WaypointEngine.lastRefocusTime = now
        return
      end
    end
  end

  -- Trigger 3: Periodic drift check (fallback when corridor is unavailable)
  if (now - WaypointEngine.lastDriftCheck) >= WaypointEngine.DRIFT_CHECK_INTERVAL then
    WaypointEngine.lastDriftCheck = now
    if not player:isWalking() then
      local pp = pos()
      if pp and maybeRefocusNearestWaypoint(pp) then
        return
      end
    end
  end
  
  -- Use cached UI list reference
  uiList = uiList or ui.list
  
  -- Get action count
  local actionCount = uiList:getChildCount()
  if actionCount == 0 then return end
  
  -- Get current action (single call pattern)
  -- If getFocusedChild returns nil (focusChild may have failed on startup),
  -- use startupFocusTarget override. Clear it once focus is restored.
  local currentAction
  local focusedChild = uiList:getFocusedChild()
  if focusedChild then
    currentAction = focusedChild
    startupFocusTarget = nil
  elseif startupFocusTarget then
    currentAction = startupFocusTarget
  else
    currentAction = uiList:getFirstChild()
  end
  if not currentAction then return end
  if intelligenceRoute and intelligenceRoute.state ~= "paused" and intelligenceRoute:currentWaypoint() ~= currentAction then
    intelligenceRoute:start({ currentAction })
    if nExBot.Intelligence.advanceGeneration then
      nExBot.Intelligence.advanceGeneration("route")
    end
  end

  -- Z-MISMATCH GUARD: If focused WP is a goto on a different floor than player,
  -- scan forward to the next same-floor goto (wraps around to WP1).
  -- Prevents rapid cycling: arrive→advance→Z-mismatch→instantFail→recovery→arrive→...
  if playerPos and currentAction.action == "goto" then
    buildWaypointCache()
    local focusedIdx = uiList:getChildIndex(currentAction)
    local cachedWp = waypointPositionCache[focusedIdx]
    if cachedWp and cachedWp.z ~= playerPos.z then
      local found = false
      local scanIdx = focusedIdx
      for _ = 1, actionCount do
        scanIdx = (scanIdx % actionCount) + 1
        local wp = waypointPositionCache[scanIdx]
        if wp and wp.isGoto and wp.z == playerPos.z then
          focusWaypointForRecovery(wp.child, scanIdx)
          found = true
          break
        end
      end
      if found then return end
      -- No same-floor goto exists; fall through to normal failure/recovery
    end
  end

  -- Fast skip: if current waypoint is blacklisted (unreachable), advance past it immediately
  if isWaypointBlacklisted(currentAction) then
    local actionCount2 = uiList:getChildCount()
    local curIdx = uiList:getChildIndex(currentAction)
    local nxtIdx = curIdx
    local skipped = 0
    repeat
      nxtIdx = (nxtIdx % actionCount2) + 1
      local nxtChild = uiList:getChildByIndex(nxtIdx)
      skipped = skipped + 1
      if nxtChild and not isWaypointBlacklisted(nxtChild) then
        uiList:focusChild(nxtChild)
        actionRetries = 0
        return
      end
    until skipped >= actionCount2
    -- All waypoints blacklisted — let recovery handle it.
    -- Don't clear immediately (causes rapid cycle). Trigger recovery instead.
    recordFailure()
    recordFailure()
    recordFailure()
    return
  end
  
  -- Direct table access (O(1))
  local actionType = currentAction.action
  local actionDef = CaveBot.Actions[actionType]
  
  if not actionDef then
    warn("[CaveBot] Invalid action: " .. tostring(actionType))
    return
  end
  
  -- Only reset walking state when the destination waypoint changes.
  -- Preserving the PathCursor across retries of the same WP avoids
  -- redundant A* recomputation every 75ms tick and enables smooth walking.
  if currentAction ~= lastDispatchedChild then
    safeResetWalking()
    lastDispatchedChild = currentAction
  end
  local result, instantFail = actionDef.callback(currentAction.value, actionRetries, prevActionResult)
  
  -- Detect focus change during callback.
  -- If recovery just changed focus (recoveryJustFocused), preserve the reset
  -- but clear the flag. Otherwise reset actionRetries for user/callback focus changes.
  if uiList:getFocusedChild() ~= currentAction then
    if WaypointEngine.recoveryJustFocused then
      WaypointEngine.recoveryJustFocused = false
      -- actionRetries already set to 0 by focusWaypointForRecovery
    else
      actionRetries = 0
    end
  end
  
  -- Handle result
  if result == "walking" or result == "nudge" then
    -- Player is actively walking/nudging toward destination; don't count
    -- this tick as a retry.  Only walkTo invocations should increment actionRetries.
    return
  end

  if result == "retry" then
    actionRetries = actionRetries + 1
    local retryLimit = (actionType == "goto") and 16 or 8
    if actionRetries > retryLimit then
      recordFailure()
      if intelligenceRoute then intelligenceRoute:applyOutcome(intelligenceRoute.generation, "path_failed") end
    end
    return
  end
  
  -- Track success/failure for stuck detection
  if result == true then
    recordSuccess()
    if intelligenceRoute then intelligenceRoute:applyOutcome(intelligenceRoute.generation, "waypoint_reached") end
  else
    recordFailure()
    -- Instant failure (wrong floor, too far): pump extra failures for fast recovery
    if instantFail and actionType == "goto" then
      recordFailure()
      recordFailure()
      if currentAction and currentAction.action == "goto" then
        blacklistWaypoint(currentAction)
      end
    end
    -- Goto false: blacklist this WP so recovery doesn't loop back to it,
    -- then stay on it and let stuck detection trigger recovery.
    -- Non-goto: advance to next action.
    if actionType == "goto" then
      if not instantFail and currentAction then
        blacklistWaypoint(currentAction)
      end
      actionRetries = 0
      return
    end
  end
  
  -- Reset for next action
  actionRetries = 0
  if result == true or result == false then
    prevActionResult = result
  end
  
  -- Check if action changed focus during execution
  local newFocused = startupFocusTarget or uiList:getFocusedChild()
  if currentAction ~= newFocused then
    currentAction = newFocused or uiList:getFirstChild()
    startupFocusTarget = nil
    actionRetries = 0
    prevActionResult = true
  end
  
  -- Move to next action
  local currentIndex = uiList:getChildIndex(currentAction)
  local nextIndex = currentIndex + 1
  if nextIndex > actionCount then
    nextIndex = 1
  end
  
  local nextChild = uiList:getChildByIndex(nextIndex)
  if nextChild then
    -- Skip blacklisted (stuck/unreachable) waypoints
    if isWaypointBlacklisted(nextChild) then
      local skipped = 0
      while isWaypointBlacklisted(nextChild) and skipped < actionCount do
        nextIndex = (nextIndex % actionCount) + 1
        nextChild = uiList:getChildByIndex(nextIndex)
        skipped = skipped + 1
      end
    end
    uiList:focusChild(nextChild)
  end
end)

-- config, its callback is called immediately, data can be nil
local lastConfig = ""
config = nExBot.ProfileStore.open({ key = "cavebot_configs", extension = "cfg", onChange = function(name, enabled, data)
  if enabled and CaveBot.Recorder.isOn() then
    CaveBot.Recorder.disable()
    CaveBot.setOff()
    return    
  end

  -- ALWAYS save character's profile preference when config changes (regardless of enabled state)
  -- This ensures the selected config is persisted even when just switching configs
  if name and name ~= "" then
    if setCharacterProfile then
      setCharacterProfile("cavebotProfile", name)
    end
    -- Persist to UnifiedStorage for character isolation
    if UnifiedStorage and UnifiedStorage.set then
      UnifiedStorage.set("cavebot.selectedConfig", name)
      -- Also save the enabled state
      UnifiedStorage.set("cavebot.enabled", enabled)
    end
    -- Emit event for any listeners
    if EventBus and EventBus.emit then
      pcall(function() EventBus.emit("cavebot:configChanged", name) end)
    end
  end

  local currentActionIndex = ui.list:getChildIndex(ui.list:getFocusedChild())
  ui.list:destroyChildren()
  if not data then return cavebotMacro.setOff() end
  
  local cavebotConfig = nil
  for k,v in ipairs(data) do
    if type(v) == "table" and #v == 2 then
      if v[1] == "config" then
        local status, result = pcall(function()
          return json.decode(v[2])
        end)
        if not status then
          warn("warn while parsing CaveBot extensions from config:\n" .. result)
        else
          cavebotConfig = result
        end
      elseif v[1] == "extensions" then
        local status, result = pcall(function()
          return json.decode(v[2])
        end)
        if not status then
          warn("warn while parsing CaveBot extensions from config:\n" .. result)
        else
          for extension, callbacks in pairs(CaveBot.Extensions) do
            if callbacks.onConfigChange then
              callbacks.onConfigChange(name, enabled, result[extension])
            end
          end
        end
      else
        CaveBot.addAction(v[1], v[2])
      end
    end
  end

  CaveBot.Config.onConfigChange(name, enabled, cavebotConfig)
  
  actionRetries = 0
  -- Use full reset on config change to clear all floor change tracking
  if CaveBot.fullResetWalking then
    CaveBot.fullResetWalking()
  else
    safeResetWalking()
  end
  resetWaypointEngine()  -- Reset waypoint engine state on config change
  if invalidateWaypointCache then invalidateWaypointCache() end  -- Clear waypoint position cache
  if resetStartupCheck then resetStartupCheck() end  -- Reset startup check to find nearest waypoint
  prevActionResult = true
  
  -- Determine final enabled state:
  -- On initial load, use stored value if available; otherwise use config's enabled
  local finalEnabled = enabled
  if not CaveBot._initialized then
    CaveBot._initialized = true
    if storage.cavebotEnabled ~= nil then
      finalEnabled = storage.cavebotEnabled
    end
  else
    -- User is toggling - save their choice
    storage.cavebotEnabled = enabled
  end
  
  -- Use inhibitor instead of setOff/setOn to preserve desired state during profile apply
  if CaveBot._profileApplying then
    -- Profile is being applied programmatically, don't change desired state
    CaveBot._profileApplying = false
  else
    cavebotMacro.setOn(finalEnabled)
  end
  cavebotMacro.delay = nil
  if lastConfig == name then 
    -- restore focused child on the action list
    ui.list:focusChild(ui.list:getChildByIndex(currentActionIndex))
  end
  lastConfig = name
end })
config.reload()
CaveBot.listProfiles = config.list

-- public function, you can use them in your scripts
CaveBot.isOn = function()
  return config and config.isOn and config.isOn() or false
end

CaveBot.isOff = function()
  return not CaveBot.isOn()
end

CaveBot.setOn = function(val)
  if val == false then
    return CaveBot.setOff(true)
  end
  -- Save enabled state to UnifiedStorage
  if UnifiedStorage and UnifiedStorage.set then
    UnifiedStorage.set("cavebot.enabled", true)
  end
  config.setOn()  -- This triggers callback which handles storage and clears _profileApplying
end

CaveBot.setOff = function(val)
  if val == false then
    return CaveBot.setOn(true)
  end
  -- Save enabled state to UnifiedStorage
  if UnifiedStorage and UnifiedStorage.set then
    UnifiedStorage.set("cavebot.enabled", false)
  end
  config.setOff()  -- This triggers callback which handles storage and clears _profileApplying
end

CaveBot.getCurrentProfile = function()
  -- Check UnifiedStorage first for per-character persistence
  if UnifiedStorage and UnifiedStorage.get then
    local stored = UnifiedStorage.get("cavebot.selectedConfig")
    if stored and stored ~= "" then
      return stored
    end
  end
  return storage._configs.cavebot_configs.selected
end

CaveBot.lastReachedLabel = function()
  return nExBot.lastLabel
end

-- Get waypoint engine statistics
CaveBot.getWaypointStats = function()
  return {
    state = WaypointEngine.state,
    failureCount = WaypointEngine.failureCount,
    isRecovering = (WaypointEngine.state == "RECOVERING")
  }
end

CaveBot.resetWaypointEngine = function()
  resetWaypointEngine()
end

CaveBot.isRecovering = function()
  return WaypointEngine.state == "RECOVERING"
end

CaveBot.blacklistWaypoint = function(child, ttl)
  if not child then return end
  -- Delegate to internal blacklistWaypoint to preserve stuckFailCounts + exponential decay
  blacklistWaypoint(child)
  -- Allow caller to override TTL if explicitly provided
  if ttl then
    WaypointEngine.stuckWaypoints[child] = now + ttl
  end
end

-- WAYPOINT FINDER UTILITIES

-- Parse position from any waypoint text that contains coordinates.
-- Supports "goto:x,y,z[,precision]", "stand:x,y,z", "lure:x,y,z", "use:x,y,z", etc.
-- Also handles "usewith:itemid,x,y,z" where the first value is an item ID.
-- @param text string e.g. "goto:1234,5678,7" or "usewith:3003,1234,5678,7"
-- @return table {x, y, z} or nil
local function parseWaypointPosition(text)
  if not text then return nil end
  -- Detect usewith prefix: format is "usewith:itemid,x,y,z" — skip itemid
  local prefix = text:match("^(%w+):")
  if prefix and prefix:lower() == "usewith" then
    local re4 = regexMatch(text, [[(?:\w+:)([^,]+),([^,]+),([^,]+),([^,]+)]])
    if re4 and re4[1] then
      local x = tonumber(re4[1][3])
      local y = tonumber(re4[1][4])
      local z = tonumber(re4[1][5])
      if x and y and z then return { x = x, y = y, z = z } end
    end
    return nil
  end
  -- Standard 3-value format: "prefix:x,y,z" (extra trailing values like precision are ignored)
  local re = regexMatch(text, [[(?:\w+:)([^,]+),([^,]+),([^,]+)]])
  if not re or not re[1] then return nil end
  local x = tonumber(re[1][2])
  local y = tonumber(re[1][3])
  local z = tonumber(re[1][4])
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z }
end

-- Legacy: parseGotoPosition for backward compatibility
-- Distance functions: delegate to SSoT (constants/directions.lua)
-- chebyshevDist is already resolved at forward-declaration above.

-- WAYPOINT CACHE (DRY: Single source of truth for waypoint positions)

-- Note: waypointPositionCache, waypointCacheValid, waypointCacheFloors declared at top

invalidateWaypointCache = function()
  waypointPositionCache = {}
  waypointCacheValid = false
  waypointCacheFloors = {}
  -- Invalidate the navigation route (segment cache is stale)
  if nExBot.Navigation and nExBot.Navigation.invalidate then
    nExBot.Navigation.invalidate()
  end
end

-- Expose for actions.lua (editor changes)
CaveBot.invalidateWaypointCache = invalidateWaypointCache

--- Ensure the navigation route is built for the given floor.
-- Exposed so actions.lua can call it before getLookaheadTarget / hasPassedWaypoint.
CaveBot.ensureNavigatorRoute = function(playerFloor)
  buildWaypointCache()
  if nExBot.Navigation and playerFloor and type(nExBot.Navigation.buildRoute) == 'function' then
    nExBot.Navigation.buildRoute(waypointPositionCache, playerFloor)
  end
end

buildWaypointCache = function()
  if waypointCacheValid then return end
  
  waypointPositionCache = {}
  waypointCacheFloors = {}
  local actions = ui.list:getChildren()
  
  for i, child in ipairs(actions) do
    local text = child:getText()
    local pos = parseWaypointPosition(text)
    if pos then
      waypointPositionCache[i] = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        child = child,
        index = i,
        isGoto = (child.action == "goto"),
      }
      waypointCacheFloors[pos.z] = true
    end
  end
  
  waypointCacheValid = true
end

-- Lightweight distance-only search for the nearest goto WP on a given floor.
-- No path validation — the goto callback's walkTo handles pathfinding.
-- Used for immediate rescue WP focus after accidental floor changes.
findNearestSameFloorGoto = function(pp, floorZ, maxDist)
  buildWaypointCache()
  local bestChild, bestIdx, bestDist = nil, nil, math.huge
  for i, wp in pairs(waypointPositionCache) do
    if wp.isGoto and wp.z == floorZ then
      local d = math.max(math.abs(pp.x - wp.x), math.abs(pp.y - wp.y))
      if d <= maxDist and d < bestDist then
        bestChild, bestIdx, bestDist = wp.child, i, d
      end
    end
  end
  return bestChild, bestIdx
end

-- WAYPOINT FINDER (distance sort + path validation on top candidates)
--
-- Phase 1: Collect candidates by Chebyshev distance.
-- Phase 2: Path-validate the top 5 closest (strict findPath, no ignoreNonPathable).
--          This catches WPs behind walls without validating every single WP.
-- Phase 3: Proximity guarantee — always validate the 3 closest WPs even if
--          they exceed gotoMaxDistance, so very nearby WPs are never skipped.

findReachableWaypoint = function(playerPos, options)
  buildWaypointCache()
  if not playerPos then return nil, nil end

  options = options or {}
  local maxDist         = options.maxDist or CaveBot.getMaxGotoDistance()
  local maxCandidates   = options.maxCandidates or 15
  local excludeCurrent  = (options.excludeCurrent ~= false)
  local searchAllFloors = options.searchAllFloors or false
  local playerZ         = playerPos.z

  -- PRIMARY: Segment-aware forward-only resolution via the navigation context
  -- This ensures the bot always picks the correct NEXT waypoint in sequence,
  -- not just the nearest by distance (which causes sequence skipping).
  if nExBot.Navigation and not options.forceDistanceBased then
    if type(nExBot.Navigation.buildRoute) == 'function' then
      nExBot.Navigation.buildRoute(waypointPositionCache, playerZ)
    end
    local wpIdx, wpPos
    if type(nExBot.Navigation.getNextWaypoint) == 'function' then
      wpIdx, wpPos = nExBot.Navigation.getNextWaypoint(playerPos)
    end
    if wpIdx then
      -- Respect excludeCurrent: skip if navigator returned the currently focused WP
      if excludeCurrent and ui and ui.list then
        local focused = ui.list:getFocusedChild()
        if focused and ui.list:getChildIndex(focused) == wpIdx then
          wpIdx = nil
        end
      end
    end
    if wpIdx then
      local wp = waypointPositionCache[wpIdx]
      if wp and wp.child and not isWaypointBlacklisted(wp.child) then
        local dist = chebyshevDist(playerPos, wp)
        if dist <= maxDist then
          return wp.child, wpIdx
        end
      end
    end
  end

  -- FALLBACK: Distance-based search (original logic for startup, cross-floor, etc.)

  local currentIdx = 0
  if ui and ui.list then
    local focused = ui.list:getFocusedChild()
    if focused then currentIdx = ui.list:getChildIndex(focused) end
  end

  -- Collect same-floor, non-blacklisted candidates (prefer goto WPs for recovery)
  local candidates = {}
  for i, wp in pairs(waypointPositionCache) do
    if isWaypointBlacklisted(wp.child) then goto continue end
    if excludeCurrent and i == currentIdx then goto continue end
    if wp.z ~= playerZ then goto continue end

    local dist = chebyshevDist(playerPos, wp)
    -- Include if within maxDist OR if it's one of the very closest (proximity guarantee)
    if dist > maxDist * 1.5 then goto continue end

    candidates[#candidates + 1] = {
      index = i, dist = dist, score = dist + (nExBot.Intelligence and nExBot.Intelligence.navigationPenalty and nExBot.Intelligence.navigationPenalty(wp, nil, dist) or 0), child = wp.child,
      x = wp.x, y = wp.y, z = wp.z,
      isGoto = wp.isGoto, withinRange = (dist <= maxDist)
    }
    ::continue::
  end

  if #candidates == 0 and not searchAllFloors then
    return nil, nil
  end

  -- Sort by distance
  table.sort(candidates, function(a, b)
    if a.score ~= b.score then return a.score < b.score end
    return a.index < b.index
  end)

  -- Path-validate candidates nearest-first until either a real cap on A*
  -- work is hit or every in-range candidate has been checked. Unlike the
  -- old fixed "validate top 5, trust distance beyond that" cutoff, nothing
  -- past the budget is accepted on distance alone -- an unvalidated
  -- candidate is simply not a candidate, so a farther-but-actually-reachable
  -- WP can still be found once nearer ones fail real path validation.
  local ps = getPS()
  local chosen = WaypointSearch.selectReachable(candidates, {
    proximityGuarantee = 3,
    budget = WaypointEngine.PATH_VALIDATION_BUDGET,
    maxCandidates = maxCandidates,
    validate = (ps and ps.findPath) and function(c)
      -- Strict findPath (no ignoreNonPathable). Generous maxSteps (100)
      -- accounts for obstacle detours that make the real path 2-5x longer
      -- than Chebyshev distance.
      local path = ps.findPath(playerPos, c, {
        maxSteps = math.min(math.floor(c.dist * 3) + 10, 100),
      })
      return path and #path > 0
    end or nil,
  })
  if chosen then return chosen.child, chosen.index end

  -- Cross-floor fallback: scan floors nearest-|Δz|-first, out to
  -- MAX_FLOOR_SEARCH_RADIUS, instead of only ever checking one floor up or
  -- down. There's no cross-floor A* here (reaching another floor needs an
  -- actual stair/rope transition, which executeRecovery's minimap scan
  -- handles separately) -- but widening which floors are even considered,
  -- and scoring candidates the same way as same-floor ones (distance +
  -- Intelligence penalty, goto WPs preferred), means a reachable waypoint
  -- two or three floors away is no longer invisible to this search.
  if searchAllFloors then
    local candidatesByFloor = {}
    for i, wp in pairs(waypointPositionCache) do
      if waypointCacheFloors[wp.z] and wp.z ~= playerZ and not isWaypointBlacklisted(wp.child) then
        local d = chebyshevDist(playerPos, wp)
        local score = d + (nExBot.Intelligence and nExBot.Intelligence.navigationPenalty and nExBot.Intelligence.navigationPenalty(wp, nil, d) or 0)
        candidatesByFloor[wp.z] = candidatesByFloor[wp.z] or {}
        local list = candidatesByFloor[wp.z]
        list[#list + 1] = { index = i, child = wp.child, isGoto = wp.isGoto, score = score }
      end
    end
    local floorOrder = WaypointSearch.floorSearchOrder(playerZ, WaypointEngine.MAX_FLOOR_SEARCH_RADIUS)
    local crossFloor = WaypointSearch.selectCrossFloor(floorOrder, candidatesByFloor)
    if crossFloor then return crossFloor.child, crossFloor.index end
  end

  return nil, nil
end

-- Legacy wrapper (used by floor-change recovery and startup)
findNearestGlobalWaypoint = function(playerPos, maxDist, options)
  options = options or {}
  return findReachableWaypoint(playerPos, {
    maxDist         = maxDist,
    maxCandidates   = options.maxCandidates or 10,
    excludeCurrent  = true,
    searchAllFloors = options.searchAllFloors or false,
  })
end

-- STARTUP WAYPOINT DETECTION
-- Finds nearest waypoint when bot starts (relog scenario)

-- Note: startupWaypointFound and startupCheckTime declared at top

-- Check if we need to find a startup waypoint (called once per session)
checkStartupWaypoint = function()
  if startupWaypointFound then return end
  if not startupCheckTime then
    startupCheckTime = now
    return
  end
  
  -- Small delay to ensure map is loaded
  if now - startupCheckTime < 500 then return end
  
  local playerPos = player:getPosition()
  if not playerPos then return end
  
  buildWaypointCache()
  
  -- Find nearest reachable waypoint globally
  local maxDist = CaveBot.getMaxGotoDistance()
  local nearestChild, nearestIndex = findNearestGlobalWaypoint(playerPos, maxDist, {
    maxCandidates = 10,
    preferCurrentFloor = true,
    searchAllFloors = false
  })
  
  if nearestChild then
    print("[CaveBot] Startup: Found nearest reachable waypoint at index " .. nearestIndex)
    startupWaypointFound = true  -- Set BEFORE focusWaypointForRecovery (focusChild may crash)
    startupFocusTarget = nearestChild
    focusWaypointForRecovery(nearestChild, nearestIndex)
    return
  end
  
  -- Extended search: larger distance, more candidates
  local extendedChild, extendedIndex = findNearestGlobalWaypoint(playerPos, maxDist * 2, {
    maxCandidates = 15,
    preferCurrentFloor = true,
    searchAllFloors = true  -- Try adjacent floors
  })
  
  if extendedChild then
    print("[CaveBot] Startup: Found waypoint at extended range, index " .. extendedIndex)
    startupWaypointFound = true
    startupFocusTarget = extendedChild
    focusWaypointForRecovery(extendedChild, extendedIndex)
  else
    warn("[CaveBot] Startup: No reachable waypoint found. Bot may be stuck.")
    startupWaypointFound = true
  end
end

-- Reset startup check (called on config change)
resetStartupCheck = function()
  startupWaypointFound = false
  startupCheckTime = nil
end

-- Find the best waypoint to go to (thin wrapper around findReachableWaypoint)
CaveBot.findBestWaypoint = function(searchForward)
  local playerPos = player:getPosition()
  if not playerPos then return false end

  local child, idx = findReachableWaypoint(playerPos, {
    maxCandidates  = 5,
    excludeCurrent = true,
  })
  if child then
    ui.list:focusChild(child)
    actionRetries = 0
    return true
  end
  return false
end

CaveBot.gotoNextWaypointInRange = function()
  return CaveBot.findBestWaypoint(true)
end

-- Throttled recovery request for unreachable waypoints
local waypointRecovery = {
  lastRequest = 0,
  cooldown = 1500
}

CaveBot.requestWaypointRecovery = function(reason)
  local nowt = now or (os.time() * 1000)
  if (nowt - waypointRecovery.lastRequest) < waypointRecovery.cooldown then
    return false
  end
  waypointRecovery.lastRequest = nowt

  local playerPos = player and player:getPosition()
  if not playerPos then return false end

  -- Try forward first, then global
  local child, idx = findReachableWaypoint(playerPos, { maxCandidates = 10 })
  if child then
    focusWaypointForRecovery(child, idx)
    return true
  end
  return false
end

-- Legacy backward search (thin wrapper)
CaveBot.gotoFirstPreviousReachableWaypoint = function()
  local playerPos = player:getPosition()
  if not playerPos then return false end

  local child, idx = findReachableWaypoint(playerPos, {
    maxCandidates  = 10,
    excludeCurrent = true,
  })
  if child then
    ui.list:focusChild(child)
    actionRetries = 0
    return true
  end
  return false
end

CaveBot.getFirstWaypointBeforeLabel = function(label)
  label = "label:"..label
  label = label:lower()
  local actions = ui.list:getChildren()
  local index
  local maxDist = CaveBot.getMaxGotoDistance()
  local halfDist = maxDist / 2
  local extendedDist = maxDist * 2
  local playerPos = player:getPosition()

  -- find index of label
  for i, child in pairs(actions) do
    local name = child:getText():lower()
    if name == label then
      index = i
      break
    end
  end

  -- if there's no index then label was not found
  if not index then return false end

  local extendedCandidates = {}

  for i=1,#actions do
    if index - i < 1 then
      break
    end

    local child = ui.list:getChildByIndex(index-i)
    if child then
      local text = child:getText()
      if string.starts(text, "goto:") then
        local re = regexMatch(text, [[(?:goto:)([^,]+),([^,]+),([^,]+)]])
        if re and re[1] then
          local pos = {x = tonumber(re[1][2]), y = tonumber(re[1][3]), z = tonumber(re[1][4])}

          if posz() == pos.z then
            local dist = distanceFromPlayer(pos)
            
            -- First priority: Normal range with path validation
            if dist <= halfDist then
              local path = findPath(playerPos, pos, halfDist, { ignoreNonPathable = true })
              if path then
                return ui.list:focusChild(child)
              end
            -- Second priority: Extended range candidates
            elseif dist <= extendedDist then
              table.insert(extendedCandidates, {child = child, pos = pos, dist = dist})
            end
          end
        end
      end
    end
  end

  -- Try extended range if nothing found
  if #extendedCandidates > 0 then
    table.sort(extendedCandidates, function(a, b) return a.dist < b.dist end)
    for _, candidate in ipairs(extendedCandidates) do
      local path = findPath(playerPos, candidate.pos, extendedDist, { ignoreNonPathable = true })
      if path then
        return ui.list:focusChild(candidate.child)
      end
    end
  end

  return false
end

CaveBot.getPreviousLabel = function()
  local actions = ui.list:getChildren()
  -- check if config is empty
  if #actions == 0 then return false end

  local currentAction = ui.list:getFocusedChild()
  --check we made any progress in waypoints, if no focused or first then no point checking
  if not currentAction or currentAction == ui.list:getFirstChild() then return false end

  local index = ui.list:getChildIndex(currentAction)

  -- if not index then something went wrong and there's no selected child
  if not index then return false end

  for i=1,#actions do
    if index - i < 1 then
      -- did not found any waypoint in range before label 
      return false
    end

    local child = ui.list:getChildByIndex(index-i)
    if child then
      if child.action == "label" then
        return child.value
      end
    end
  end
end

CaveBot.getNextLabel = function()
  local actions = ui.list:getChildren()
  -- check if config is empty
  if #actions == 0 then return false end

  local currentAction = ui.list:getFocusedChild() or ui.list:getFirstChild()
  local index = ui.list:getChildIndex(currentAction)

  -- if not index then something went wrong
  if not index then return false end

  for i=1,#actions do
    if index + i > #actions then
      -- did not found any waypoint in range before label 
      return false
    end

    local child = ui.list:getChildByIndex(index+i)
    if child then
      if child.action == "label" then
        return child.value
      end
    end
  end
end

-- Use shared BotConfigName from configs.lua (DRY)
local botConfigName = BotConfigName or modules.game_bot.contentsPanel.config:getCurrentOption().text
CaveBot.setCurrentProfile = function(name)
  if not g_resources.fileExists("/bot/"..botConfigName.."/cavebot_configs/"..name..".cfg") then
    return warn("there is no cavebot profile with that name!")
  end
  
  -- Atomic profile switch: preserve desired enabled state
  local wasEnabled = CaveBot.isOn()
  CaveBot._profileApplying = true
  
  storage._configs.cavebot_configs.selected = name
  -- Persist to UnifiedStorage for character isolation
  if UnifiedStorage and UnifiedStorage.set then
    UnifiedStorage.set("cavebot.selectedConfig", name)
  end
  -- Save character's profile preference for multi-client support
  if setCharacterProfile then
    setCharacterProfile("cavebotProfile", name)
  end
  -- Emit event for any listeners
  if EventBus and EventBus.emit then
    pcall(function() EventBus.emit("cavebot:configChanged", name) end)
  end
  
  local ok = config.select(name)
  if ok then
    if wasEnabled then CaveBot.setOn() else CaveBot.setOff() end
  end
end

CaveBot.delay = function(value)
  cavebotMacro.delay = math.max(cavebotMacro.delay or 0, now + value)
end

-- Direct walk to position (used by other modules like clear_tile, imbuing)
-- More efficient than goto action as it doesn't have retry logic overhead
CaveBot.GoTo = function(dest, precision)
  if not dest then return false end
  
  precision = precision or 1
  local playerPos = player:getPosition()
  if not playerPos then return false end
  
  -- Already at destination
  local distX = math.abs(dest.x - playerPos.x)
  local distY = math.abs(dest.y - playerPos.y)
  if distX <= precision and distY <= precision and dest.z == playerPos.z then
    return true
  end
  
  -- Different floor
  if dest.z ~= playerPos.z then
    return false
  end
  
  -- Use optimized walkTo
  return CaveBot.walkTo(dest, CaveBot.getMaxGotoDistance(), {
    precision = precision,
    ignoreNonPathable = true
  })
end

CaveBot.gotoLabel = function(label)
  label = label:lower()
  for index, child in ipairs(ui.list:getChildren()) do
    if child.action == "label" and child.value:lower() == label then    
      ui.list:focusChild(child)
      return true
    end
  end
  return false
end

CaveBot.save = function()
  local data = {}
  for index, child in ipairs(ui.list:getChildren()) do
    table.insert(data, {child.action, child.value})
  end
  
  if CaveBot.Config then
    table.insert(data, {"config", json.encode(CaveBot.Config.save())})
  end
  
  local extension_data = {}
  for extension, callbacks in pairs(CaveBot.Extensions) do
    if callbacks.onSave then
      local ext_data = callbacks.onSave()
      if type(ext_data) == "table" then
        extension_data[extension] = ext_data
      end
    end
  end
  table.insert(data, {"extensions", json.encode(extension_data, 2)})
  config.save(data)
end

-- Note: Profile restoration is handled early in configs.lua
-- before Config.setup() is called, so the dropdown loads correctly

-- ─────────────────────────────────────────────────────────────────────────────
-- Container Recovery Coordination
-- Subscribe to recovery:pause/resume events emitted by Discovery.
-- These are issued during reconnect to prevent stale waypoint execution.
-- ─────────────────────────────────────────────────────────────────────────────
if EventBus then
  -- Track whether CaveBot is paused due to container recovery.
  local _recoveryPausedGeneration = nil

  EventBus.on("recovery:pause_cavebot", function(payload)
    local gen = payload and payload.generation
    if _recoveryPausedGeneration == gen then return end  -- already paused this gen
    _recoveryPausedGeneration = gen
    -- Pause waypoint engine if CaveBot is on.
    if CaveBot.isOn() then
      if intelligenceRoute and intelligenceRoute.pause then
        pcall(function() intelligenceRoute:pause("container_recovery") end)
      end
    end
  end, 0)

  EventBus.on("recovery:resume_cavebot", function(payload)
    local gen = payload and payload.generation
    -- Only resume if the pause came from the same generation.
    if _recoveryPausedGeneration ~= gen then return end
    _recoveryPausedGeneration = nil
    if CaveBot.isOn() then
      -- Resume with recalculated route from current position.
      if intelligenceRoute and intelligenceRoute.resume then
        pcall(function() intelligenceRoute:resume() end)
      end
      -- Invalidate stale path so CaveBot recalculates.
      if WaypointEngine then
        pcall(function()
          WaypointEngine.stuckWaypoints = {}
          WaypointEngine.failureCount    = 0
        end)
      end
    end
    if payload and payload.recalculate and CaveBot.resetWaypointEngine then
      pcall(CaveBot.resetWaypointEngine)
    end
  end, 0)
end
