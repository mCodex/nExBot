-- navigation_v2.lua
-- Floor-change handler and enhanced recovery engine for CaveBot.
-- Called from the macro via CaveBot.NavigationV2.handleFloorChange(navCtx)
-- and CaveBot.NavigationV2.handleRecovery(navCtx).
--
-- Context object (navCtx) fields — see cavebot.lua for builder:
--   playerPos, lastPlayerFloor, focusedChild, focusedIdx
--   waypointCache, actionCount, uiList, engine (WaypointEngine table)
--   setLastFloor(z), setActionRetries(n), clearDelays()
--   safeResetWalking(), focusWaypoint(child,idx)
--   clearBlacklist(), resetEngine(), transitionTo(state)
--   isBlacklisted(child), blacklistWaypoint(child)
--   buildCache(), findNearestSameFloor(pp,z,maxDist), getMaxGotoDist()

CaveBot = CaveBot or {}

local STATE = {
  TRACKING   = "TRACKING",
  RECOVERING = "RECOVERING",
  HARD_STUCK = "HARD_STUCK",
}

local NAV = {
  STATE = STATE,
  -- Internal state
  _hardStuck        = false,
  _lastRecoveryAt   = 0,
  -- Metrics
  _metrics = {
    zIntentional    = 0,
    zStair          = 0,
    zAccidental     = 0,
    recoveryRuns    = 0,
    hardStuckCount  = 0,
    loopGuardBreaks = 0,
  },
}

-- ── FLOOR-CHANGE HANDLER ─────────────────────────────────────────────────────
-- Called every macro tick.  Updates lastPlayerFloor and, when a Z-change is
-- detected, classifies it as intentional / stair-triggered / accidental and
-- takes the appropriate recovery action.
-- Returns true when the tick was consumed (caller should `return` immediately).
function NAV.handleFloorChange(ctx)
  local playerPos = ctx.playerPos

  -- Always keep lastPlayerFloor current (also handles non-Z-change ticks).
  if playerPos then
    ctx.setLastFloor(playerPos.z)
  end

  local lastFloor = ctx.lastPlayerFloor
  if not (playerPos and lastFloor and playerPos.z ~= lastFloor) then
    return false  -- no floor change this tick
  end

  -- Floor changed: clear stale delays and walk state unconditionally.
  ctx.clearDelays()
  ctx.safeResetWalking()

  local focusedChild = ctx.focusedChild
  local focusedIdx   = ctx.focusedIdx
  local wp           = focusedIdx and ctx.waypointCache[focusedIdx]

  -- ── Case 1: Intentional ────────────────────────────────────────────────────
  -- The focused WP is a goto already on the new floor (the goto action chose
  -- this floor; the WP was recorded with the destination floor's z value).
  local intentional = wp and wp.isGoto and (wp.z == playerPos.z)
  if intentional then
    ctx.clearBlacklist()
    ctx.engine.failureCount = 0
    NAV._metrics.zIntentional = NAV._metrics.zIntentional + 1
    print(("[CaveBot] Z-change (%d→%d): intentional, continuing WP%s"):format(
      lastFloor, playerPos.z, tostring(focusedIdx or "?")))
    return true
  end

  -- ── Case 2: Stair-triggered ────────────────────────────────────────────────
  -- The focused WP is a floor-change tile on the OLD floor (goto walked the
  -- player onto a hole/ladder/rope and the server teleported them down/up).
  local stairUsed = false
  if wp and wp.isGoto and (wp.z == lastFloor) then
    local wpPos = { x = wp.x, y = wp.y, z = wp.z }
    if FloorItems and FloorItems.isFloorChangeTile then
      stairUsed = FloorItems.isFloorChangeTile(wpPos)
    end
  end

  if stairUsed then
    ctx.clearBlacklist()
    ctx.engine.failureCount = 0
    NAV._metrics.zStair = NAV._metrics.zStair + 1
    -- Advance to the next WP in sequence to preserve route order.
    if focusedIdx and ctx.actionCount > 0 then
      local nextIdx   = (focusedIdx % ctx.actionCount) + 1
      local nextChild = ctx.uiList:getChildByIndex(nextIdx)
      if nextChild then
        ctx.uiList:focusChild(nextChild)
        ctx.setActionRetries(0)
      end
    end
    print(("[CaveBot] Z-change (%d→%d): stair at WP%s, advancing"):format(
      lastFloor, playerPos.z, tostring(focusedIdx or "?")))
    return true
  end

  -- ── Case 3: Accidental ────────────────────────────────────────────────────
  -- Player ended up on a different floor without intent — reset and refocus.
  NAV._metrics.zAccidental = NAV._metrics.zAccidental + 1
  ctx.clearBlacklist()
  ctx.resetEngine()
  ctx.buildCache()
  local wc = ctx.getWaypointCache and ctx.getWaypointCache() or ctx.waypointCache
  local actionCount = ctx.getActionCount and ctx.getActionCount() or ctx.actionCount

  local maxDist     = ctx.getMaxGotoDist()
  local curIdx      = focusedIdx or 0
  local bestChild, bestIdx, bestDist = nil, nil, math.huge

  -- Forward scan from curIdx+1 → end (first in-sequence match wins).
  for i = curIdx + 1, actionCount do
    local wpi = wc[i]
    if wpi and wpi.isGoto and wpi.z == playerPos.z then
      local d = math.max(math.abs(playerPos.x - wpi.x), math.abs(playerPos.y - wpi.y))
      if d <= maxDist then
        bestChild, bestIdx = wpi.child, i
        break
      end
    end
  end

  -- Wrap scan from 1 → curIdx-1 (rescue WPs at start of route).
  if not bestChild then
    for i = 1, math.max(1, curIdx - 1) do
      local wpi = wc[i]
      if wpi and wpi.isGoto and wpi.z == playerPos.z then
        local d = math.max(math.abs(playerPos.x - wpi.x), math.abs(playerPos.y - wpi.y))
        if d <= maxDist and d < bestDist then
          bestChild, bestIdx, bestDist = wpi.child, i, d
        end
      end
    end
  end

  -- Distance fallback (searches all same-floor WPs by Chebyshev).
  if not bestChild and ctx.findNearestSameFloor then
    bestChild, bestIdx = ctx.findNearestSameFloor(playerPos, playerPos.z, maxDist)
  end

  -- Exhaustive fallback: scan all goto WPs and pick the best rescue candidate
  -- by floor proximity first, then distance. This prevents idle stops when all
  -- nearby same-floor WPs are out of maxDist during accidental Z changes.
  if not bestChild and wc and actionCount > 0 then
    local bestScore = math.huge
    for i = 1, actionCount do
      local wpi = wc[i]
      if wpi and wpi.isGoto and not ctx.isBlacklisted(wpi.child) then
        local floorPenalty = math.abs((wpi.z or playerPos.z) - playerPos.z) * 1000
        local d = math.max(math.abs(playerPos.x - wpi.x), math.abs(playerPos.y - wpi.y))
        local score = floorPenalty + d
        if score < bestScore then
          bestScore = score
          bestChild = wpi.child
          bestIdx = i
        end
      end
    end
  end

  if bestChild then
    print(("[CaveBot] Z-change (%d→%d): accidental, focusing WP%d"):format(
      lastFloor, playerPos.z, bestIdx))
    ctx.focusWaypoint(bestChild, bestIdx)
  else
    print(("[CaveBot] Z-change (%d→%d): accidental, no same-floor WP in range"):format(
      lastFloor, playerPos.z))
  end

  return true  -- tick consumed
end

-- ── INTERNAL: Enhanced recovery execution ────────────────────────────────────
-- WaypointNavigator primary → RecoveryPlanner 4-tier fallback → hard-stuck valve.
local function executeEnhancedRecovery(ctx)
  -- Throttle: at most once per second to avoid hammering PathStrategy.
  if (now - NAV._lastRecoveryAt) < 1000 then return end
  NAV._lastRecoveryAt = now
  NAV._metrics.recoveryRuns = NAV._metrics.recoveryRuns + 1

  local playerPos = ctx.playerPos
  if not playerPos then return end

  -- Always work on fresh cache snapshots after editor/config/runtime updates.
  ctx.buildCache()
  local waypointCache = ctx.getWaypointCache and ctx.getWaypointCache() or ctx.waypointCache
  local actionCount = ctx.getActionCount and ctx.getActionCount() or ctx.actionCount

  local engine = ctx.engine

  -- Hard-stuck safety valve: if recovery has been running for too long,
  -- clear all blacklists and flag hard-stuck for expanded-radius search.
  local idleTimeout = engine.RECOVERY_IDLE_TIMEOUT or 12000
  if engine.recoveryStartedAt > 0 and (now - engine.recoveryStartedAt) > idleTimeout then
    warn(("[CaveBot] Recovery idle %ds — clearing blacklists"):format(
      math.floor(idleTimeout / 1000)))
    ctx.clearBlacklist()
    engine.recoveryStartedAt = now
    NAV._metrics.hardStuckCount = NAV._metrics.hardStuckCount + 1
    NAV._hardStuck = true
  end

  -- Helper: attempt to focus a recovery WP with loop-guard protection.
  -- Returns true if focus was accepted; false if cycling detected (WP blacklisted).
  local function tryFocus(child, idx, label)
    if not child then return false end
    local lg = CaveBot.LoopGuard
    if lg and lg.isCycling(idx) and not lg.isCoolingDown() then
      NAV._metrics.loopGuardBreaks = NAV._metrics.loopGuardBreaks + 1
      lg.markActivation()
      ctx.blacklistWaypoint(child)
      print(("[CaveBot] LoopGuard: WP%d cycling, extending blacklist"):format(idx))
      return false
    end
    if lg then lg.recordFocus(idx) end
    ctx.focusWaypoint(child, idx)
    ctx.transitionTo("NORMAL")
    return true
  end

  -- ── PRIMARY: WaypointNavigator segment-aware forward recovery ─────────────
  if WaypointNavigator and type(CaveBot.ensureNavigatorRoute) == "function" then
    CaveBot.ensureNavigatorRoute(playerPos.z)
    local wpIdx
    if type(WaypointNavigator.getNextWaypoint) == "function" then
      wpIdx = WaypointNavigator.getNextWaypoint(playerPos)
    end
    if wpIdx then
      local wp = waypointCache[wpIdx]
      -- If the suggested WP is blacklisted, walk forward through gotoIndices.
      if wp and wp.child and ctx.isBlacklisted(wp.child) then
        local gotoIndices = (WaypointNavigator.getGotoIndices and WaypointNavigator.getGotoIndices()) or {}
        local originalIdx = wpIdx
        local found = false
        for pass = 1, 2 do
          local pastOriginal = (pass == 2)
          for _, gIdx in ipairs(gotoIndices) do
            if pass == 1 then
              if gIdx == originalIdx then
                pastOriginal = true
              elseif pastOriginal then
                local fwdWp = waypointCache[gIdx]
                if fwdWp and fwdWp.child and not ctx.isBlacklisted(fwdWp.child) and fwdWp.z == playerPos.z then
                  wp = fwdWp; wpIdx = gIdx; found = true; break
                end
              end
            else  -- pass 2: wrap from start to originalIdx
              if gIdx == originalIdx then break end
              local fwdWp = waypointCache[gIdx]
              if fwdWp and fwdWp.child and not ctx.isBlacklisted(fwdWp.child) and fwdWp.z == playerPos.z then
                wp = fwdWp; wpIdx = gIdx; found = true; break
              end
            end
          end
          if found then break end
        end
      end
      if wp and wp.child and not ctx.isBlacklisted(wp.child) then
        local d = math.max(math.abs(playerPos.x - wp.x), math.abs(playerPos.y - wp.y))
        if d <= 3 then
          -- Already within arrival distance: snap focus and return to NORMAL.
          ctx.uiList:focusChild(wp.child)
          ctx.setActionRetries(0)
          ctx.transitionTo("NORMAL")
          return
        end
        if tryFocus(wp.child, wpIdx, "navigator") then return end
        -- Loop-guard blocked this WP; fall through to RecoveryPlanner.
      end
    end
  end

  -- ── FALLBACK: RecoveryPlanner 4-tier ladder ────────────────────────────────
  -- Reload focusedIdx in case earlier tick logic changed focus.
  local fc = ctx.uiList:getFocusedChild()
  local curFocusedIdx = fc and ctx.uiList:getChildIndex(fc) or ctx.focusedIdx

  local rp = CaveBot.RecoveryPlanner
  if rp then
    local child, idx, tier = rp.findTarget(
      playerPos, ctx.isBlacklisted, waypointCache, curFocusedIdx, actionCount, NAV._hardStuck)
    if child then
      if tryFocus(child, idx, "planner_t" .. tostring(tier)) then
        print(("[CaveBot] Recovery (tier %d): WP%d"):format(tier, idx))
        return
      end
      -- Cycling: blacklist extended, retry next tick.
      return
    end
  end

  -- All recovery options exhausted: idle in RECOVERING.
  -- The safety valve above will clear blacklists after idleTimeout.
end

-- ── RECOVERY HANDLER ─────────────────────────────────────────────────────────
-- Called every macro tick (after shouldSkipExecution).
-- Returns true when this tick was consumed by recovery logic.
function NAV.handleRecovery(ctx)
  local engine = ctx.engine
  if not engine then return false end

  local state = engine.state

  if state == "NORMAL" then
    if engine.failureCount >= (engine.FAILURE_THRESHOLD or 3) then
      -- Threshold crossed: transition to RECOVERING (transitionTo sets recoveryStartedAt).
      ctx.transitionTo("RECOVERING")
      return true
    end
    -- Engine healthy: clear hard-stuck flag.
    NAV._hardStuck = false
    return false

  elseif state == "RECOVERING" then
    -- Ensure recoveryStartedAt is set (transitionTo may have been called externally).
    if engine.recoveryStartedAt == 0 then
      engine.recoveryStartedAt = now
    end
    executeEnhancedRecovery(ctx)
    return true
  end

  return false
end

-- ── PUBLIC INTERFACE ──────────────────────────────────────────────────────────

function NAV.getState()
  if NAV._hardStuck then return STATE.HARD_STUCK end
  return STATE.TRACKING
end

function NAV.getMetrics()
  return {
    state     = NAV.getState(),
    hardStuck = NAV._hardStuck,
    metrics   = NAV._metrics,
    recovery  = CaveBot.RecoveryPlanner and CaveBot.RecoveryPlanner.getMetrics() or nil,
    loopGuard = CaveBot.LoopGuard and CaveBot.LoopGuard.getMetrics() or nil,
  }
end

function NAV.reset()
  NAV._hardStuck      = false
  NAV._lastRecoveryAt = 0
  if CaveBot.LoopGuard then CaveBot.LoopGuard.reset() end
end

CaveBot.NavigationV2 = NAV
return NAV
