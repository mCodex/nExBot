local cavebotMacro = nil
local config = nil

-- TrimArray is set as a global by utils/ring_buffer.lua (Phase 3)
local TrimArray = TrimArray

-- Safe wrapper for CaveBot.resetWalking to prevent nil errors
local function safeResetWalking()
  if CaveBot and CaveBot.resetWalking then
    CaveBot.resetWalking()
  end
end

-- ui
local configWidget = UI.Config()  -- Create config widget first
local ui = UI.createWidget("CaveBotPanel")

-- Move the config widget into the placeholder panel at the top
if ui.configWidgetPlaceholder and configWidget then
  -- Try multiple methods to reparent the widget
  local placeholder = ui.configWidgetPlaceholder
  if configWidget.setParent then
    configWidget:setParent(placeholder)
  end
  if placeholder.addChild then
    -- Only add if not already a child to avoid duplicate-add warnings
    local ok, parent = pcall(function() return configWidget:getParent() end)
    if not ok or parent ~= placeholder then
      placeholder:addChild(configWidget)
    end
  end
  -- Move to first child position if possible
  if placeholder.moveChildToIndex then
    placeholder:moveChildToIndex(configWidget, 1)
  end
end

-- Move the main CaveBot panel to the first position in the tab
-- This ensures the waypoint list appears before Editor/Config panels
do
  local parent = ui:getParent()
  if parent then
    -- Try different OTClient methods for reordering children
    if parent.moveChildToIndex then
      parent:moveChildToIndex(ui, 1)
    elseif parent.insertChild then
      -- Alternative: remove and re-insert at front
      parent:removeChild(ui)
      parent:insertChild(1, ui)
    end
  end
end

ui.list = ui.listPanel.list -- shortcut
CaveBot.actionList = ui.list

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

-- FLOOR CHANGE TRACKING: Prevent looping when waypoints span multiple Z levels
-- When a floor-change waypoint is being executed, we set this to the expected floor
-- so that when the floor actually changes, we know it was intentional
local intendedFloorChange = {
  active = false,          -- True when executing a floor-change waypoint
  expectedFloor = nil,     -- The Z level we expect to end up on after the floor change
  sourceFloor = nil,       -- The Z level we started from
  waypointIndex = nil,     -- The waypoint index that triggered the floor change
  timestamp = 0,           -- When the floor change was initiated
  TIMEOUT = 5000           -- Max time to wait for floor change to complete
}

-- FLOOR CHANGE LOOP PREVENTION: Track recent floor changes to prevent up/down loops
local floorChangeHistory = {
  changes = {},            -- Circular buffer of recent floor changes: {time, fromZ, toZ, waypointIdx}
  maxSize = 6,             -- Track last 6 floor changes
  cooldownTime = 3000,     -- Minimum time (ms) before allowing another floor change to same floor
  loopThreshold = 4,       -- Number of changes to detect a loop pattern
  lastChangeTime = 0,      -- Last floor change timestamp
  lastFloorFrom = nil,     -- Last floor we changed FROM
  lastFloorTo = nil,       -- Last floor we changed TO
  completedFloorChange = nil  -- Track that a floor change was just completed {time, toZ, fromZ}
}

-- Check if a floor change would create a loop (going back to a floor we just left)
-- Only counts arrivals (toZ), not departures — a single round-trip is expected
-- for rescue waypoints. Threshold 3 and 5s window avoid false positives.
local function wouldCreateFloorLoop(targetZ)
  if #floorChangeHistory.changes < 3 then return false end

  local recentTime = now - 5000  -- Look at last 5 seconds
  local arrivals = 0

  for i = #floorChangeHistory.changes, 1, -1 do
    local change = floorChangeHistory.changes[i]
    if change.time < recentTime then break end
    if change.toZ == targetZ then
      arrivals = arrivals + 1
    end
  end

  return arrivals >= 3
end

-- Record a floor change
local function recordFloorChange(fromZ, toZ, waypointIdx)
  local change = {time = now, fromZ = fromZ, toZ = toZ, waypointIdx = waypointIdx}
  floorChangeHistory.changes[#floorChangeHistory.changes + 1] = change
  
  -- Trim to max size (using TrimArray for O(1) amortized)
  TrimArray(floorChangeHistory.changes, floorChangeHistory.maxSize)
  
  floorChangeHistory.lastChangeTime = now
  floorChangeHistory.lastFloorFrom = fromZ
  floorChangeHistory.lastFloorTo = toZ
  floorChangeHistory.completedFloorChange = {time = now, toZ = toZ, fromZ = fromZ}
end

-- Check if enough time has passed since last floor change
local function canChangeFloorNow()
  return (now - floorChangeHistory.lastChangeTime) >= floorChangeHistory.cooldownTime
end

-- Get recent floor change info (for step-back avoidance in walking.lua)
CaveBot.getRecentFloorChange = function()
  if floorChangeHistory.completedFloorChange then
    local elapsed = now - floorChangeHistory.completedFloorChange.time
    if elapsed < 3000 then  -- 3 seconds: short enough to not block rescue WPs
      return floorChangeHistory.completedFloorChange
    end
  end
  return nil
end

-- Check if we would loop by going to target floor
CaveBot.wouldFloorChangeLoop = function(targetZ)
  return wouldCreateFloorLoop(targetZ)
end

-- Record a completed floor change (called from walking.lua)
CaveBot.recordFloorChange = function(fromZ, toZ, waypointIdx)
  recordFloorChange(fromZ, toZ, waypointIdx)
end

-- Check if floor change is allowed (cooldown check)
CaveBot.canChangeFloor = function()
  return canChangeFloorNow()
end

-- Clear floor change history (on config change)
local function clearFloorChangeHistory()
  floorChangeHistory.changes = {}
  floorChangeHistory.lastChangeTime = 0
  floorChangeHistory.lastFloorFrom = nil
  floorChangeHistory.lastFloorTo = nil
  floorChangeHistory.completedFloorChange = nil
end

-- DRY: Single source of truth for gotoMaxDistance with fallback.
-- Used by goto callback, findReachableWaypoint, startup search, floor-change recovery.
CaveBot.getMaxGotoDistance = function()
  return storage.extras.gotoMaxDistance or 50
end

-- Mark that we're intentionally changing floors (called from goto action)
CaveBot.setIntendedFloorChange = function(expectedZ, waypointIndex)
  intendedFloorChange.active = true
  intendedFloorChange.expectedFloor = expectedZ
  intendedFloorChange.sourceFloor = posz()
  intendedFloorChange.waypointIndex = waypointIndex
  intendedFloorChange.timestamp = now
end

-- Clear the intended floor change tracking
CaveBot.clearIntendedFloorChange = function()
  intendedFloorChange.active = false
  intendedFloorChange.expectedFloor = nil
  intendedFloorChange.sourceFloor = nil
  intendedFloorChange.waypointIndex = nil
  intendedFloorChange.timestamp = 0
end

-- Full clear including history (for config changes)
CaveBot.clearAllFloorChangeTracking = function()
  CaveBot.clearIntendedFloorChange()
  clearFloorChangeHistory()
end

-- Check if a floor change was intended (used by walking.lua to prevent step-back)
-- This is the AUTHORITATIVE check for whether a floor change should be allowed
CaveBot.isFloorChangeIntended = function(newFloor)
  if not intendedFloorChange.active then 
    return false 
  end
  
  -- Check timeout
  if now - intendedFloorChange.timestamp > intendedFloorChange.TIMEOUT then
    CaveBot.clearIntendedFloorChange()
    return false
  end
  
  local expectedZ = intendedFloorChange.expectedFloor
  local sourceZ = intendedFloorChange.sourceFloor
  if not expectedZ or not sourceZ then 
    return false 
  end
  
  -- EXACT MATCH: If we ended up exactly where expected, it's definitely intentional
  if newFloor == expectedZ then
    return true
  end
  
  -- DIRECTION CHECK: If we moved in the right direction, allow it
  -- This handles cases where floor change might go to adjacent floor
  local movingUp = newFloor < sourceZ
  local expectedUp = expectedZ < sourceZ
  local movedInRightDirection = (movingUp == expectedUp)
  
  -- Only allow if we moved AND we're within 1 floor of expected
  if movedInRightDirection and math.abs(newFloor - expectedZ) <= 1 then
    return true
  end
  
  return false
end

-- Get the current intended floor change state (for debugging/checks)
CaveBot.getIntendedFloorChange = function()
  if not intendedFloorChange.active then return nil end
  return {
    expectedFloor = intendedFloorChange.expectedFloor,
    sourceFloor = intendedFloorChange.sourceFloor,
    waypointIndex = intendedFloorChange.waypointIndex,
    timestamp = intendedFloorChange.timestamp,
    age = now - intendedFloorChange.timestamp
  }
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

-- Floor-change recovery throttle (reduce heavy scans on manual z-changes)
local FLOOR_CHANGE_RECOVERY_DEFAULT = 200  -- ms, internal safe default
local floorChangeRecovery = {
  scheduled = false,
  pendingZ = nil,
  pendingFrom = nil,
  lastRun = 0
}

local function getFloorChangeRecoveryDelay()
  local delay = FLOOR_CHANGE_RECOVERY_DEFAULT
  if storage and storage.cavebot and storage.cavebot.walking then
    local v = tonumber(storage.cavebot.walking.floorChangeDelay)
    if v and v >= 0 then
      delay = v
    end
  end
  return delay
end

local function tryCurrentWaypointReachable(playerPos, maxDist)
  if not ui or not ui.list or not playerPos then return false end
  local current = ui.list:getFocusedChild() or ui.list:getFirstChild()
  if not current or current.action ~= "goto" then return false end

  local posMatch = regexMatch(current.value, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)")
  if not posMatch or not posMatch[1] or not posMatch[1][2] or not posMatch[1][3] or not posMatch[1][4] then return false end

  local destPos = {
    x = tonumber(posMatch[1][2]),
    y = tonumber(posMatch[1][3]),
    z = tonumber(posMatch[1][4])
  }
  if destPos.z ~= playerPos.z then return false end

  local dist2d = math.abs(destPos.x - playerPos.x) + math.abs(destPos.y - playerPos.y)
  if dist2d > maxDist then return false end

  local path = findPath(playerPos, destPos, maxDist, { ignoreNonPathable = true })
  return path ~= nil
end

local function scheduleFloorChangeRecovery()
  local delay = getFloorChangeRecoveryDelay()
  if floorChangeRecovery.scheduled then return end

  floorChangeRecovery.scheduled = true
  schedule(delay, function()
    floorChangeRecovery.scheduled = false
    if now - floorChangeRecovery.lastRun < delay then return end
    floorChangeRecovery.lastRun = now

    local pp = player and player:getPosition()
    if not pp then return end
    if floorChangeRecovery.pendingZ and pp.z ~= floorChangeRecovery.pendingZ then return end

    local maxDist = CaveBot.getMaxGotoDistance()
    if tryCurrentWaypointReachable(pp, maxDist) then return end

    if findNearestGlobalWaypoint then
      local child, idx = findNearestGlobalWaypoint(pp, maxDist, {
        maxCandidates = 6,
        preferCurrentFloor = true,
        searchAllFloors = false
      })
      if child then
        focusWaypointForRecovery(child, idx)
      end
    end
  end)
end

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
-- Allows mid-walk verification every ~300ms to detect stuck/blocked states
local function shouldSkipExecution()
  -- Active delay from previous action
  if now < walkState.delayUntil then
    return true
  end
  
  -- Player is actively walking — allow through every 300ms for mid-walk verification
  if player:isWalking() then
    if not walkState.lastVerifyTime then
      walkState.lastVerifyTime = now
    end
    
    -- Allow mid-walk check every 150ms (faster re-dispatch for smoother movement)
    if (now - walkState.lastVerifyTime) >= 150 then
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
          -- Only stop if we've regressed well beyond the best distance seen
          local tolerance = 3
          if walkState.minDist and curDist > walkState.minDist + tolerance then
            -- Getting farther from closest point — stop and recompute
            if player.stopAutoWalk then
              pcall(player.stopAutoWalk, player)
            end
            walkState.isWalkingToWaypoint = false
            walkState.targetPos = nil
            return false
          end
          -- Elapsed-progress check: if walking > 3s with zero distance decrease, stuck
          if walkState.walkStartTime and walkState.walkStartDist then
            local elapsed = now - walkState.walkStartTime
            if elapsed > 3000 and curDist >= walkState.walkStartDist then
              if player.stopAutoWalk then
                pcall(player.stopAutoWalk, player)
              end
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
    local stepDur = (PathStrategy and PathStrategy.rawStepDuration(false)) or 200
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

-- ============================================================================
-- FORWARD DECLARATIONS (functions defined later but used early)
-- ============================================================================
local findNearestGlobalWaypoint  -- Defined in WAYPOINT FINDER section
local findReachableWaypoint      -- Unified search (TSP scoring), defined in WAYPOINT FINDER
local checkStartupWaypoint       -- Defined in STARTUP DETECTION section
local invalidateWaypointCache    -- Defined in WAYPOINT CACHE section
local resetStartupCheck          -- Defined in STARTUP DETECTION section
local buildWaypointCache         -- Defined in WAYPOINT CACHE section
local focusWaypointForRecovery   -- Defined in RECOVERY STRATEGIES section
local resetWaypointEngine        -- Defined below runWaypointEngine
local chebyshevDist = Directions.chebyshevDistance  -- SSoT: constants/directions.lua
local waypointPositionCache = {} -- Waypoint position cache table
local waypointCacheValid = false
local waypointCacheFloors = {}
local startupWaypointFound = false
local startupCheckTime = nil   -- Set on first check to enforce 500ms delay

--[[
  WAYPOINT ENGINE
  
  Simple stuck detection → recovery → blacklist system.
  Recovery picks nearest non-blacklisted WP by distance.
  No path prevalidation — the goto callback is the real validator.
]]

-- ============================================================================
-- WAYPOINT ENGINE STATE
-- ============================================================================

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

  -- Performance: avoid redundant UI lookups
  tickCount = 0,
  lastTickTime = 0,
}

-- ============================================================================
-- BLACKLIST UTILITIES
-- ============================================================================

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
    WaypointEngine.BLACKLIST_BASE_TTL * math.pow(2, failCount - 1),
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

-- ============================================================================
-- STATE MACHINE (NORMAL ↔ RECOVERING)
-- ============================================================================

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
  -- Player made progress — clear all blacklists.
  -- From the new position, previously-unreachable WPs may now be reachable.
  clearWaypointBlacklist()
  WaypointEngine.recoveryStartedAt = 0
  if WaypointEngine.state ~= "NORMAL" then
    transitionTo("NORMAL")
  end
end

local function recordFailure()
  WaypointEngine.failureCount = WaypointEngine.failureCount + 1
end

-- ============================================================================
-- RECOVERY
-- ============================================================================

-- Focus a waypoint for recovery (cancel walk, reset retries)
focusWaypointForRecovery = function(targetChild, targetIndex)
  if CaveBot.stopAutoWalk then CaveBot.stopAutoWalk() end
  ui.list:focusChild(targetChild)
  actionRetries = 0
  WaypointEngine.recoveryJustFocused = true
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

  -- Same-floor: nearest non-blacklisted WP by distance (no path validation)
  local child, idx = findReachableWaypoint(playerPos, { maxCandidates = 30 })
  if child then
    print("[CaveBot] Recovery: focusing waypoint " .. idx)
    focusWaypointForRecovery(child, idx)
    transitionTo("NORMAL")
    return true
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

-- ============================================================================
-- MAIN ENGINE TICK (called from macro loop)
-- ============================================================================

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

-- ============================================================================
-- EVENTBUS INTEGRATION: Instant waypoint arrival detection
-- ============================================================================

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

cavebotMacro = macro(75, function()  -- 75ms for smooth, responsive walking
  -- SMART EXECUTION: Skip if we shouldn't execute this tick
  if shouldSkipExecution() then return end
  
  -- Update player position tracking
  hasPlayerMoved()

  -- Z-change guard: skip heavy processing during manual floor transitions
  if zChanging() then
    local pp = player and player:getPosition()
    local intended = CaveBot.isFloorChangeIntended and pp and CaveBot.isFloorChangeIntended(pp.z)
    if not intended then
      if pp then lastPlayerFloor = pp.z end
      return
    end
  end

  -- Guard against unintended floor changes: realign to nearest waypoint on current floor
  -- BUT: If the floor change was intended (from a floor-change waypoint), don't reset!
  local playerPos = player:getPosition()
  if playerPos then
    if lastPlayerFloor and playerPos.z ~= lastPlayerFloor then
      -- Check if this floor change was intended using multiple methods:
      -- 1. intendedFloorChange is still active (rare - usually cleared by walking.lua)
      -- 2. recentFloorChange matches this transition (most reliable)
      local wasIntended = false
      
      -- Method 1: Check intendedFloorChange (might still be active)
      if CaveBot.isFloorChangeIntended and CaveBot.isFloorChangeIntended(playerPos.z) then
        wasIntended = true
        CaveBot.clearIntendedFloorChange()
      end
      
      -- Method 2: Check recentFloorChange (more reliable - persists for 8 seconds)
      if not wasIntended and CaveBot.getRecentFloorChange then
        local recent = CaveBot.getRecentFloorChange()
        if recent and recent.toZ == playerPos.z and recent.fromZ == lastPlayerFloor then
          -- This matches our floor transition - it was intended
          wasIntended = true
        end
      end
      
      if wasIntended then
        -- Intended floor change - just reset walking, don't search for waypoints
        -- DON'T clear blacklist here — blacklisted waypoints should survive intended transitions
        safeResetWalking()
        -- Do NOT call resetWaypointEngine or findNearestGlobalWaypoint!
      else
        -- Unintended floor change - clear blacklist (stale for old floor) and recover
        clearWaypointBlacklist()
        safeResetWalking()
        resetWaypointEngine()
        floorChangeRecovery.pendingZ = playerPos.z
        floorChangeRecovery.pendingFrom = lastPlayerFloor

        -- Manual z-change: skip heavy recovery scans when not walking to a waypoint
        if walkState and walkState.isWalkingToWaypoint and player and player:isWalking() then
          scheduleFloorChangeRecovery()
        else
          if walkState then
            walkState.isWalkingToWaypoint = false
            walkState.targetPos = nil
          end
        end
      end
    end
    lastPlayerFloor = playerPos.z
  end
  
  -- STARTUP DETECTION: Find nearest waypoint on relog/load
  -- Note: checkStartupWaypoint is defined later in file, check if available
  if checkStartupWaypoint then
    checkStartupWaypoint()
  end
  
  -- WAYPOINT ENGINE: High-performance stuck detection and recovery
  if runWaypointEngine() then
    return  -- Engine handled recovery, skip normal processing
  end
  
  -- Lazy-init TargetBot cache
  if not targetBotIsActive and TargetBot then
    initTargetBotCache()
  end
  
  -- Check TargetBot allows CaveBot action (cached function refs)
  if targetBotIsActive and targetBotIsActive() then
    if targetBotIsCaveBotAllowed and not targetBotIsCaveBotAllowed() then
      safeResetWalking()
      return
    end
    
    -- PULL SYSTEM PAUSE: If smartPull is active, pause waypoint walking
    if TargetBot.smartPullActive then
      safeResetWalking()
      return
    end
    
    -- ═══════════════════════════════════════════════════════════════════════════
    -- IMPROVED MONSTER DETECTION (v3.0)
    -- Check for targetable monsters on screen BEFORE proceeding to next waypoint
    -- This prevents the bot from leaving monsters behind
    -- ═══════════════════════════════════════════════════════════════════════════
    if TargetBot.shouldWaitForMonsters and TargetBot.shouldWaitForMonsters() then
      -- There are monsters that need to be killed - pause cavebot
      safeResetWalking()
      return
    end
    
    -- BACKUP CHECK: If EventTargeting reports combat active, also pause
    if EventTargeting and EventTargeting.isCombatActive and EventTargeting.isCombatActive() then
      -- Only pause if we're NOT allowed by TargetBot
      if not (targetBotIsCaveBotAllowed and targetBotIsCaveBotAllowed()) then
        safeResetWalking()
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
  local currentAction = uiList:getFocusedChild() or uiList:getFirstChild()
  if not currentAction then return end
  
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
  if result == "walking" then
    -- Player is actively walking toward destination; don't count this tick
    -- as a retry.  Only walkTo invocations should increment actionRetries.
    return
  end

  if result == "retry" then
    actionRetries = actionRetries + 1
    local retryLimit = (actionType == "goto") and 16 or 8
    if actionRetries > retryLimit then
      recordFailure()
    end
    return
  end
  
  -- Track success/failure for stuck detection
  if result == true then
    recordSuccess()
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
    -- Goto false: stay on current WP, let stuck detection trigger recovery.
    -- Non-goto: advance to next action.
    if actionType == "goto" then
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
  local newFocused = uiList:getFocusedChild()
  if currentAction ~= newFocused then
    currentAction = newFocused or uiList:getFirstChild()
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
config = Config.setup("cavebot_configs", configWidget, "cfg", function(name, enabled, data)
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
  -- Clear all floor change tracking including history
  if CaveBot.clearAllFloorChangeTracking then
    CaveBot.clearAllFloorChangeTracking()
  else
    CaveBot.clearIntendedFloorChange()  -- Fallback to just clearing intended
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
  
  cavebotMacro.setOn(finalEnabled)
  cavebotMacro.delay = nil
  if lastConfig == name then 
    -- restore focused child on the action list
    ui.list:focusChild(ui.list:getChildByIndex(currentActionIndex))
  end
  lastConfig = name
end)

-- ui callbacks
ui.showEditor.onClick = function()
  if not CaveBot.Editor then return end
  if ui.showEditor:isOn() then
    CaveBot.Editor.hide()
    ui.showEditor:setOn(false)
  else
    CaveBot.Editor.show()
    ui.showEditor:setOn(true)
  end
end

ui.showConfig.onClick = function()
  if not CaveBot.Config then return end
  if ui.showConfig:isOn() then
    CaveBot.Config.hide()
    ui.showConfig:setOn(false)
  else
    CaveBot.Config.show()
    ui.showConfig:setOn(true)
  end
end

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
  config.setOn()  -- This triggers callback which handles storage
end

CaveBot.setOff = function(val)
  if val == false then  
    return CaveBot.setOn(true)
  end
  -- Save enabled state to UnifiedStorage
  if UnifiedStorage and UnifiedStorage.set then
    UnifiedStorage.set("cavebot.enabled", false)
  end
  config.setOff()  -- This triggers callback which handles storage
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
  WaypointEngine.stuckWaypoints[child] = now + (ttl or WaypointEngine.BLACKLIST_TTL)
end

-- ============================================================================
-- WAYPOINT FINDER UTILITIES
-- ============================================================================

-- Parse position from any waypoint text that contains coordinates.
-- Supports "goto:x,y,z", "stand:x,y,z", "lure:x,y,z", "use:x,y,z,..." etc.
-- @param text string e.g. "goto:1234,5678,7" or "stand:1234,5678,7"
-- @return table {x, y, z} or nil
local function parseWaypointPosition(text)
  if not text then return nil end
  local re = regexMatch(text, [[(?:\w+:)([^,]+),([^,]+),([^,]+)]])
  if not re or not re[1] then return nil end
  local x = tonumber(re[1][2])
  local y = tonumber(re[1][3])
  local z = tonumber(re[1][4])
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z }
end

-- Legacy: parseGotoPosition for backward compatibility
local function parseGotoPosition(text)
  if not text or not string.starts(text, "goto:") then return nil end
  return parseWaypointPosition(text)
end

-- Distance functions: delegate to SSoT (constants/directions.lua)
-- chebyshevDist is already resolved at forward-declaration above.
-- manhattanDist is only used locally in this section.
local manhattanDist = Directions.manhattanDistance

-- ============================================================================
-- WAYPOINT CACHE (DRY: Single source of truth for waypoint positions)
-- ============================================================================

-- Note: waypointPositionCache, waypointCacheValid, waypointCacheFloors declared at top

invalidateWaypointCache = function()
  waypointPositionCache = {}
  waypointCacheValid = false
  waypointCacheFloors = {}
end

-- Expose for actions.lua (editor changes)
CaveBot.invalidateWaypointCache = invalidateWaypointCache

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

-- ============================================================================
-- WAYPOINT FINDER (distance sort + path validation on top candidates)
--
-- Phase 1: Collect candidates by Chebyshev distance.
-- Phase 2: Path-validate the top 5 closest (strict findPath, no ignoreNonPathable).
--          This catches WPs behind walls without validating every single WP.
-- Phase 3: Proximity guarantee — always validate the 3 closest WPs even if
--          they exceed gotoMaxDistance, so very nearby WPs are never skipped.
-- ============================================================================

findReachableWaypoint = function(playerPos, options)
  buildWaypointCache()
  if not playerPos then return nil, nil end

  options = options or {}
  local maxDist         = options.maxDist or CaveBot.getMaxGotoDistance()
  local maxCandidates   = options.maxCandidates or 15
  local excludeCurrent  = (options.excludeCurrent ~= false)
  local searchAllFloors = options.searchAllFloors or false
  local playerZ         = playerPos.z

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
      index = i, dist = dist, child = wp.child,
      isGoto = wp.isGoto, withinRange = (dist <= maxDist)
    }
    ::continue::
  end

  if #candidates == 0 and not searchAllFloors then
    return nil, nil
  end

  -- Sort by distance
  table.sort(candidates, function(a, b) return a.dist < b.dist end)

  -- Path-validate top candidates (max 5 strict A* calls, bounded cost)
  -- This prevents selecting WPs behind walls during recovery.
  local PATH_VALIDATE_COUNT = 5
  local PROXIMITY_GUARANTEE = 3
  local validated = {}

  for rank, c in ipairs(candidates) do
    if rank > maxCandidates then break end

    -- Proximity guarantee: always validate the 3 closest regardless of maxDist
    local shouldValidate = (rank <= PROXIMITY_GUARANTEE) or c.withinRange
    if not shouldValidate then goto skip_candidate end

    -- Path validation: use strict findPath (no ignoreNonPathable) for top candidates
    if rank <= PATH_VALIDATE_COUNT and PathStrategy then
      local path = PathStrategy.findPath(playerPos, c, {
        maxSteps = math.min(math.floor(c.dist * 1.5) + 5, 50),
      })
      if path and #path > 0 then
        validated[#validated + 1] = c
      end
      -- If strict fails, try with ignoreNonPathable as fallback
      if not path or #path == 0 then
        path = PathStrategy.findPath(playerPos, c, {
          maxSteps = math.min(math.floor(c.dist * 1.5) + 5, 50),
          ignoreNonPathable = true,
        })
        if path and #path > 0 then
          validated[#validated + 1] = c
        end
      end
    else
      -- Beyond validation budget: accept by distance (legacy behavior)
      if c.withinRange then
        validated[#validated + 1] = c
      end
    end
    ::skip_candidate::
  end

  -- Return the nearest validated candidate (prefer goto WPs)
  if #validated > 0 then
    -- Prefer goto WPs over other types for recovery (goto WPs are actionable)
    for _, v in ipairs(validated) do
      if v.isGoto then return v.child, v.index end
    end
    return validated[1].child, validated[1].index
  end

  -- Cross-floor fallback
  if searchAllFloors then
    for _, floorZ in ipairs({playerZ - 1, playerZ + 1}) do
      if waypointCacheFloors[floorZ] then
        local best, bestDist, bestIdx = nil, math.huge, 0
        for i, wp in pairs(waypointPositionCache) do
          if wp.z == floorZ and not isWaypointBlacklisted(wp.child) then
            local d = manhattanDist(playerPos, wp)
            if d < bestDist then
              best, bestDist, bestIdx = wp.child, d, i
            end
          end
        end
        if best then return best, bestIdx end
      end
    end
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

-- ============================================================================
-- STARTUP WAYPOINT DETECTION
-- Finds nearest waypoint when bot starts (relog scenario)
-- ============================================================================

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
  
  -- Check if current focused waypoint is already reachable
  local currentAction = ui.list:getFocusedChild()
  if currentAction then
    local currentIndex = ui.list:getChildIndex(currentAction)
    local currentWp = waypointPositionCache[currentIndex]
    
    if currentWp and currentWp.z == playerPos.z then
      local dist = chebyshevDist(playerPos, currentWp)
      local maxDist = CaveBot.getMaxGotoDistance()
      
      if dist <= maxDist then
        local path = findPath(playerPos, currentWp, maxDist, { ignoreNonPathable = true })
        if path then
          -- Current waypoint is reachable, no need to search
          startupWaypointFound = true
          return
        end
      end
    end
  end
  
  -- Current waypoint not reachable - find nearest globally
  local maxDist = CaveBot.getMaxGotoDistance()
  local nearestChild, nearestIndex = findNearestGlobalWaypoint(playerPos, maxDist, {
    maxCandidates = 10,
    preferCurrentFloor = true,
    searchAllFloors = false
  })
  
  if nearestChild then
    print("[CaveBot] Startup: Found nearest reachable waypoint at index " .. nearestIndex)
    focusWaypointForRecovery(nearestChild, nearestIndex)
    startupWaypointFound = true
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
    focusWaypointForRecovery(extendedChild, extendedIndex)
  else
    warn("[CaveBot] Startup: No reachable waypoint found. Bot may be stuck.")
  end
  
  startupWaypointFound = true
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
  CaveBot.setOff()
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
  CaveBot.setOn()
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

CaveBotList = function()
  return ui.list
end

-- Note: Profile restoration is handled early in configs.lua
-- before Config.setup() is called, so the dropdown loads correctly