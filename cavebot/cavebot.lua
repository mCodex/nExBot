local cavebotMacro = nil
local config = nil

-- Safe local fallback for TrimArray (some sandboxes / test clients don't expose the global)
local TrimArray = TrimArray or (RingBuffer and RingBuffer.trimArray) or function(arr, maxSize)
  if type(arr) ~= "table" or not maxSize or maxSize < 1 then return 0 end
  local excess = #arr - maxSize
  if excess <= 0 then return 0 end
  for i = 1, maxSize do arr[i] = arr[i + excess] end
  for i = maxSize + 1, #arr do arr[i] = nil end
  return excess
end

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
  completedFloorChange = nil,  -- Track that a floor change was just completed {time, toZ, fromZ}
  lastCompletedWaypointPos = nil,  -- Position of last completed floor-change waypoint
  lastCompletedWaypointTime = 0    -- When the floor-change waypoint was completed
}

-- Check if a floor change would create a loop (going back to a floor we just left)
local function wouldCreateFloorLoop(targetZ)
  if #floorChangeHistory.changes < 2 then return false end
  
  local recentTime = now - 8000  -- Look at last 8 seconds
  local visitCount = {}
  
  -- Count how many times we visited each floor recently
  for i = #floorChangeHistory.changes, 1, -1 do
    local change = floorChangeHistory.changes[i]
    if change.time < recentTime then break end
    
    visitCount[change.toZ] = (visitCount[change.toZ] or 0) + 1
    visitCount[change.fromZ] = (visitCount[change.fromZ] or 0) + 1
  end
  
  -- If we've visited the target floor 2+ times recently, it's likely a loop
  if visitCount[targetZ] and visitCount[targetZ] >= 2 then
    return true
  end
  
  return false
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

-- Mark a floor-change waypoint as completed (prevents re-execution)
local function markFloorChangeWaypointCompleted(waypointPos)
  floorChangeHistory.lastCompletedWaypointPos = waypointPos
  floorChangeHistory.lastCompletedWaypointTime = now
end

-- Check if a waypoint was just completed (within timeout)
local function wasWaypointJustCompleted(waypointPos, timeout)
  timeout = timeout or 10000  -- 10 second default
  if not floorChangeHistory.lastCompletedWaypointPos then return false end
  if now - floorChangeHistory.lastCompletedWaypointTime > timeout then return false end
  
  local lastPos = floorChangeHistory.lastCompletedWaypointPos
  return lastPos.x == waypointPos.x and lastPos.y == waypointPos.y and lastPos.z == waypointPos.z
end

-- Check if enough time has passed since last floor change
local function canChangeFloorNow()
  return (now - floorChangeHistory.lastChangeTime) >= floorChangeHistory.cooldownTime
end

-- Get recent floor change info (for skipping logic)
CaveBot.getRecentFloorChange = function()
  if floorChangeHistory.completedFloorChange then
    local elapsed = now - floorChangeHistory.completedFloorChange.time
    if elapsed < 8000 then  -- Within 8 seconds (increased from 2s)
      return floorChangeHistory.completedFloorChange
    end
  end
  return nil
end

-- Check if a floor-change waypoint was just completed
CaveBot.wasFloorChangeWaypointCompleted = function(waypointPos)
  return wasWaypointJustCompleted(waypointPos, 10000)  -- 10 second window
end

-- Mark a floor-change waypoint as completed
CaveBot.markFloorChangeWaypointCompleted = function(waypointPos)
  markFloorChangeWaypointCompleted(waypointPos)
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
  floorChangeHistory.lastCompletedWaypointPos = nil
  floorChangeHistory.lastCompletedWaypointTime = 0
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

    local maxDist = storage.extras.gotoMaxDistance or 50
    if tryCurrentWaypointReachable(pp, maxDist) then return end

    if findNearestGlobalWaypoint then
      local child, idx = findNearestGlobalWaypoint(pp, maxDist, {
        maxCandidates = 6,
        preferCurrentFloor = true,
        searchAllFloors = false,
        excludeCompletedFloorChange = true
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
    if WaypointEngine then
      WaypointEngine.lastMoveTime = now
    end
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
    
    -- Allow mid-walk check every 300ms
    if (now - walkState.lastVerifyTime) >= 300 then
      walkState.lastVerifyTime = now
      
      -- Check if walk is taking too long (expected duration exceeded by 50%)
      if walkState.walkStartTime and walkState.walkExpectedDuration then
        local elapsed = now - walkState.walkStartTime
        if elapsed > walkState.walkExpectedDuration * 1.5 then
          -- Walking too long — stop and let macro recompute
          if player.stopAutoWalk then
            pcall(player.stopAutoWalk, player)
          end
          walkState.isWalkingToWaypoint = false
          walkState.targetPos = nil
          return false  -- Don't skip — let macro handle it
        end
      end
      
      -- Check if distance to target is decreasing (rolling minimum + tolerance)
      if walkState.targetPos then
        local currentPos = pos()
        if currentPos then
          local curDist = math.abs(currentPos.x - walkState.targetPos.x)
                        + math.abs(currentPos.y - walkState.targetPos.y)
          -- Track rolling minimum distance (handles curved/obstacle paths)
          if not walkState.minDist or curDist < walkState.minDist then
            walkState.minDist = curDist
          end
          -- Only stop if we've regressed significantly beyond the best distance seen
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
    local dist = math.abs(currentPos.x - targetPos.x) + math.abs(currentPos.y - targetPos.y)
    local stepDur = (PathStrategy and PathStrategy.rawStepDuration(false)) or 200
    walkState.walkExpectedDuration = dist * stepDur
    walkState.walkStartDist = dist
  else
    walkState.walkExpectedDuration = nil
    walkState.walkStartDist = nil
  end
  -- Track walkTo success for instant-stuck detection
  if WaypointEngine then
    WaypointEngine.walkToFailCount = 0
    WaypointEngine.lastMoveTime = now
  end
end

-- Clear walking state
CaveBot.clearWalkingState = function()
  walkState.isWalkingToWaypoint = false
  walkState.targetPos = nil
end

-- ============================================================================
-- FORWARD DECLARATIONS (functions defined later but used early)
-- ============================================================================
local findNearestGlobalWaypoint  -- Defined in WAYPOINT FINDER section
local checkStartupWaypoint       -- Defined in STARTUP DETECTION section
local invalidateWaypointCache    -- Defined in WAYPOINT CACHE section
local resetStartupCheck          -- Defined in STARTUP DETECTION section
local buildWaypointCache         -- Defined in WAYPOINT CACHE section
local chebyshevDist = Directions.chebyshevDistance  -- SSoT: constants/directions.lua
local waypointPositionCache = {} -- Waypoint position cache table
local waypointCacheValid = false
local waypointCacheFloors = {}
local startupWaypointFound = false
local startupCheckTime = nil   -- Set on first check to enforce 500ms delay

--[[
  HIGH-PERFORMANCE WAYPOINT ENGINE
  
  A production-grade waypoint system with:
  - O(1) state lookups using hash maps
  - Sliding window for progress tracking (no array shifting)
  - Exponential backoff for recovery
  - Zero-allocation hot path
  - Predictive waypoint prefetching
]]

-- ============================================================================
-- WAYPOINT ENGINE STATE (pre-allocated, zero GC pressure)
-- ============================================================================

WaypointEngine = {
  -- Progress tracking (circular buffer - O(1) operations)
  progressBuffer = {},           -- Pre-allocated circular buffer
  progressHead = 1,              -- Current write position
  progressSize = 0,              -- Current buffer size
  PROGRESS_CAPACITY = 16,        -- Fixed capacity (power of 2 for fast modulo)
  
  -- Position delta tracking (inline, no allocations)
  lastPos = nil,                 -- Last sampled position {x, y, z}
  totalMovement = 0,             -- Accumulated movement since last reset
  lastMovementTime = 0,          -- Last time movement was detected
  lastSampleTime = 0,            -- Last position sample time
  SAMPLE_INTERVAL = 1000,        -- Sample every 1 second
  
  -- Failure state machine
  state = "NORMAL",              -- NORMAL, STUCK, RECOVERING, STOPPED
  failureCount = 0,              -- Current consecutive failures
  stuckStartTime = 0,            -- When stuck state began
  recoveryStartTime = 0,         -- When recovery began
  
  -- Thresholds (tuned for fast recovery)
  STUCK_THRESHOLD = 4,           -- Failures before stuck (was 8)
  STUCK_TIMEOUT = 4000,          -- Max time in stuck before recovery (was 10000)
  MOVEMENT_THRESHOLD = 3,        -- Min tiles to consider "progress"
  PROGRESS_WINDOW = 8000,        -- Time window for progress check (was 15000)
  RECOVERY_TIMEOUT = 10000,      -- Max recovery time before stop (was 25000)
  
  -- Instant-stuck tracking
  walkToFailCount = 0,           -- Consecutive walkTo false returns
  lastMoveTime = 0,              -- Last time player actually moved
  
  -- Backoff for recovery attempts
  recoveryAttempt = 0,
  MAX_RECOVERY_ATTEMPTS = 6,     -- Increased: 6 strategies now available
  
  -- Performance counters (optional, for debugging)
  tickCount = 0,
  lastTickTime = 0,
  
  -- Waypoint blacklist: temporarily skip unreachable waypoints.
  -- When stuck on waypoint N, blacklist it so advancement skips past it.
  -- Without this, recovery finds N-1 (closest reachable), N-1 completes
  -- instantly (player already there), advances back to N → infinite loop.
  stuckWaypoints = {},           -- child widget → expiry timestamp
  BLACKLIST_TTL = 45000          -- 45 seconds (survives one route circuit)
}

-- Pre-allocate progress buffer
for i = 1, WaypointEngine.PROGRESS_CAPACITY do
  WaypointEngine.progressBuffer[i] = {time = 0, x = 0, y = 0, z = 0, waypointId = 0}
end

-- ============================================================================
-- INLINE UTILITY FUNCTIONS (no function call overhead)
-- ============================================================================

-- Fast waypoint ID lookup (cached)
local cachedWaypointId = 0
local cachedWaypointTime = 0
local function getCurrentWaypointId()
  -- Cache for 100ms to avoid repeated UI lookups
  if now - cachedWaypointTime < 100 then
    return cachedWaypointId
  end
  cachedWaypointTime = now
  
  if not ui or not ui.list then 
    cachedWaypointId = 0
    return 0 
  end
  
  local focused = ui.list:getFocusedChild()
  if not focused then 
    cachedWaypointId = 0
    return 0 
  end
  
  cachedWaypointId = ui.list:getChildIndex(focused)
  return cachedWaypointId
end

-- Check if a waypoint widget is temporarily blacklisted (stuck/unreachable)
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

-- Clear the entire blacklist (e.g. on floor change or route reset)
local function clearWaypointBlacklist()
  for k in pairs(WaypointEngine.stuckWaypoints) do
    WaypointEngine.stuckWaypoints[k] = nil
  end
end

-- ============================================================================
-- PROGRESS TRACKING (circular buffer, O(1) all operations)
-- ============================================================================

local function recordProgress()
  local playerPos = pos()
  if not playerPos then return end
  
  -- Rate limit sampling
  if now - WaypointEngine.lastSampleTime < WaypointEngine.SAMPLE_INTERVAL then
    return
  end
  WaypointEngine.lastSampleTime = now
  
  -- Track movement delta
  if WaypointEngine.lastPos then
    local dx = math.abs(playerPos.x - WaypointEngine.lastPos.x)
    local dy = math.abs(playerPos.y - WaypointEngine.lastPos.y)
    local moved = dx + dy
    
    if moved > 0 then
      WaypointEngine.totalMovement = WaypointEngine.totalMovement + moved
      WaypointEngine.lastMovementTime = now
    end
  end
  
  -- Update last position (inline copy, no allocation)
  if not WaypointEngine.lastPos then
    WaypointEngine.lastPos = {x = 0, y = 0, z = 0}
  end
  WaypointEngine.lastPos.x = playerPos.x
  WaypointEngine.lastPos.y = playerPos.y
  WaypointEngine.lastPos.z = playerPos.z
  
  -- Write to circular buffer (reuse existing entry)
  local entry = WaypointEngine.progressBuffer[WaypointEngine.progressHead]
  entry.time = now
  entry.x = playerPos.x
  entry.y = playerPos.y
  entry.z = playerPos.z
  entry.waypointId = getCurrentWaypointId()
  
  -- Advance head (fast modulo for power of 2)
  WaypointEngine.progressHead = (WaypointEngine.progressHead % WaypointEngine.PROGRESS_CAPACITY) + 1
  if WaypointEngine.progressSize < WaypointEngine.PROGRESS_CAPACITY then
    WaypointEngine.progressSize = WaypointEngine.progressSize + 1
  end
end

-- Check if player has made meaningful progress recently
local function hasRecentProgress()
  -- Quick check: any movement in progress window?
  if now - WaypointEngine.lastMovementTime < WaypointEngine.PROGRESS_WINDOW then
    if WaypointEngine.totalMovement >= WaypointEngine.MOVEMENT_THRESHOLD then
      return true
    end
  end
  
  -- Check circular buffer for position delta
  if WaypointEngine.progressSize < 3 then
    return true  -- Not enough data, assume OK
  end
  
  local cutoff = now - WaypointEngine.PROGRESS_WINDOW
  local oldest = nil
  local newest = nil
  
  -- Find oldest and newest entries within window
  for i = 1, WaypointEngine.progressSize do
    local entry = WaypointEngine.progressBuffer[i]
    if entry.time >= cutoff then
      if not oldest or entry.time < oldest.time then
        oldest = entry
      end
      if not newest or entry.time > newest.time then
        newest = entry
      end
    end
  end
  
  if not oldest or not newest then
    return true  -- Not enough data
  end
  
  -- Calculate total movement
  local dx = math.abs(newest.x - oldest.x)
  local dy = math.abs(newest.y - oldest.y)
  
  return (dx + dy) >= WaypointEngine.MOVEMENT_THRESHOLD
end

-- ============================================================================
-- STATE MACHINE (NORMAL -> STUCK -> RECOVERING -> STOPPED)
-- ============================================================================

local function transitionTo(newState)
  local oldState = WaypointEngine.state
  WaypointEngine.state = newState
  
  if newState == "STUCK" then
    WaypointEngine.stuckStartTime = now
    -- Blacklist the current waypoint so advancement skips past it
    local current = ui and ui.list and ui.list:getFocusedChild()
    if current and current.action == "goto" then
      WaypointEngine.stuckWaypoints[current] = now + WaypointEngine.BLACKLIST_TTL
    end
  elseif newState == "RECOVERING" then
    WaypointEngine.recoveryStartTime = now
    WaypointEngine.recoveryAttempt = WaypointEngine.recoveryAttempt + 1
  elseif newState == "NORMAL" then
    WaypointEngine.failureCount = 0
    WaypointEngine.totalMovement = 0
    WaypointEngine.recoveryAttempt = 0
  end
end

local function recordSuccess()
  WaypointEngine.failureCount = 0
  WaypointEngine.walkToFailCount = 0
  if WaypointEngine.state ~= "NORMAL" then
    transitionTo("NORMAL")
  end
end

local function recordFailure()
  WaypointEngine.failureCount = WaypointEngine.failureCount + 1
  WaypointEngine.walkToFailCount = WaypointEngine.walkToFailCount + 1
end

-- ============================================================================
-- RECOVERY STRATEGIES (ordered by likelihood of success)
-- Uses a tiered approach: fast local search → global search → skip strategies
-- ============================================================================

-- Helper function to focus a waypoint for recovery
-- Focuses the target waypoint directly and resets retries so it executes fresh.
-- The old approach of focusing N-1 caused ping-pong loops: recovery finds N,
-- focuses N-1, N-1 succeeds → advances to N → N unreachable → recovery → loop.
-- @param targetChild widget The waypoint widget to focus
-- @param targetIndex number The index of the waypoint (unused, kept for API compat)
local function focusWaypointForRecovery(targetChild, targetIndex)
  ui.list:focusChild(targetChild)
  actionRetries = 0
end

local function executeRecovery()
  local attempt = WaypointEngine.recoveryAttempt
  local playerPos = player:getPosition()
  local maxDist = storage.extras.gotoMaxDistance or 50
  
  -- Strategy 1: Try current waypoint with ignoreCreatures (maybe just blocked by monster)
  if attempt <= 1 then
    local current = ui and ui.list and ui.list:getFocusedChild()
    if current and current.action == "goto" then
      local posMatch = regexMatch(current.value, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)")
      if posMatch and posMatch[1] then
        local destPos = {
          x = tonumber(posMatch[1][2]),
          y = tonumber(posMatch[1][3]),
          z = tonumber(posMatch[1][4])
        }
        if destPos.z == playerPos.z then
          local path = findPath(playerPos, destPos, maxDist, {
            ignoreNonPathable = true,
            ignoreCreatures = true
          })
          if path then
            print("[CaveBot] Recovery: Current waypoint reachable (ignoring creatures)")
            transitionTo("NORMAL")
            return true
          end
        end
      end
    end
    WaypointEngine.recoveryAttempt = 2
    return false
  end
  
  -- Strategy 2: Find nearest reachable waypoint (forward search)
  if attempt <= 2 then
    if CaveBot.findBestWaypoint and CaveBot.findBestWaypoint(true) then
      print("[CaveBot] Recovery: Found waypoint via forward search")
      transitionTo("NORMAL")
      return true
    end
    WaypointEngine.recoveryAttempt = 3
    return false
  end
  
  -- Strategy 3: ROUTE-AWARE GLOBAL SEARCH (uses orderDistance scoring)
  if attempt <= 3 and playerPos and findNearestGlobalWaypoint then
    local nearestChild, nearestIndex = findNearestGlobalWaypoint(playerPos, maxDist, {
      maxCandidates = 15,
      preferCurrentFloor = true,
      searchAllFloors = false,
      excludeCompletedFloorChange = true
    })
    
    if nearestChild then
      print("[CaveBot] Recovery: Found waypoint via route-aware global search at index " .. nearestIndex)
      focusWaypointForRecovery(nearestChild, nearestIndex)
      transitionTo("NORMAL")
      return true
    end
    WaypointEngine.recoveryAttempt = 4
    return false
  end
  
  -- Strategy 4: Search backwards for reachable waypoint
  if attempt <= 4 then
    if CaveBot.gotoFirstPreviousReachableWaypoint and CaveBot.gotoFirstPreviousReachableWaypoint() then
      print("[CaveBot] Recovery: Found waypoint via backward search")
      transitionTo("NORMAL")
      return true
    end
    WaypointEngine.recoveryAttempt = 5
    return false
  end
  
  -- Strategy 5: EXTENDED GLOBAL SEARCH with cross-floor support
  if attempt <= 5 and playerPos and findNearestGlobalWaypoint then
    local nearestChild, nearestIndex = findNearestGlobalWaypoint(playerPos, maxDist * 2, {
      maxCandidates = 25,
      preferCurrentFloor = true,
      searchAllFloors = true,
      excludeCompletedFloorChange = true
    })
    
    if nearestChild then
      print("[CaveBot] Recovery: Found waypoint via extended global search at index " .. nearestIndex)
      focusWaypointForRecovery(nearestChild, nearestIndex)
      transitionTo("NORMAL")
      return true
    end
    WaypointEngine.recoveryAttempt = 6
    return false
  end
  
  -- Strategy 6: Skip current waypoint (last resort)
  if attempt <= 6 then
    if ui and ui.list then
      local actionCount = ui.list:getChildCount()
      if actionCount > 1 then
        local current = ui.list:getFocusedChild()
        if current then
          local currentIndex = ui.list:getChildIndex(current)
          local nextIndex = (currentIndex % actionCount) + 1
          local nextChild = ui.list:getChildByIndex(nextIndex)
          if nextChild then
            print("[CaveBot] Recovery: Skipping waypoint " .. currentIndex .. " -> " .. nextIndex)
            ui.list:focusChild(nextChild)
            transitionTo("NORMAL")
            return true
          end
        end
      end
    end
  end
  
  return false
end

-- ============================================================================
-- MAIN ENGINE TICK (called from macro loop)
-- ============================================================================

local function runWaypointEngine()
  -- Record progress (rate-limited internally)
  recordProgress()
  
  -- State machine processing
  local state = WaypointEngine.state
  
  if state == "NORMAL" then
    -- Check for stuck condition
    local isStuck = false
    
    -- Condition 1: Too many consecutive failures
    if WaypointEngine.failureCount >= WaypointEngine.STUCK_THRESHOLD then
      isStuck = true
    end
    
    -- Condition 2: No progress despite activity
    if WaypointEngine.failureCount >= 3 and not hasRecentProgress() then
      isStuck = true
    end
    
    -- Condition 3: Instant-stuck — walkTo returned false 3+ times AND no movement for 2s
    if WaypointEngine.walkToFailCount >= 3 and (now - WaypointEngine.lastMoveTime) > 2000 then
      isStuck = true
    end
    
    if isStuck then
      transitionTo("STUCK")
    end
    
    return false  -- No intervention needed
    
  elseif state == "STUCK" then
    -- Check if we should transition to recovery
    local stuckDuration = now - WaypointEngine.stuckStartTime
    
    -- Quick check: if player started moving, return to normal
    if hasRecentProgress() and WaypointEngine.failureCount < 3 then
      transitionTo("NORMAL")
      return false
    end
    
    -- Transition to RECOVERING after 1s (was 3s grace + 10s timeout)
    if stuckDuration >= 1000 then
      transitionTo("RECOVERING")
    end
    
    return false
    
  elseif state == "RECOVERING" then
    -- Check recovery timeout
    local recoveryDuration = now - WaypointEngine.recoveryStartTime
    
    if recoveryDuration >= WaypointEngine.RECOVERY_TIMEOUT then
      -- Recovery taking too long, try next strategy
      if WaypointEngine.recoveryAttempt >= WaypointEngine.MAX_RECOVERY_ATTEMPTS then
        transitionTo("STOPPED")
        return true
      end
    end
    
    -- Execute recovery strategy
    if executeRecovery() then
      return true  -- Recovery succeeded, skip this tick
    end
    
    -- If all strategies exhausted
    if WaypointEngine.recoveryAttempt >= WaypointEngine.MAX_RECOVERY_ATTEMPTS then
      transitionTo("STOPPED")
    end
    
    return true  -- Recovery in progress
    
  elseif state == "STOPPED" then
    -- SIMPLIFIED: Instead of stopping, reset and try again
    -- This prevents permanent stops during hunts
    warn("[CaveBot] Recovery exhausted - resetting to try again")
    resetWaypointEngine()
    return false  -- Allow normal processing to continue
  end
  
  return false
end

-- Reset engine state
local function resetWaypointEngine()
  WaypointEngine.state = "NORMAL"
  WaypointEngine.failureCount = 0
  WaypointEngine.totalMovement = 0
  WaypointEngine.lastMovementTime = now
  WaypointEngine.lastSampleTime = 0
  WaypointEngine.lastPos = nil
  WaypointEngine.recoveryAttempt = 0
  WaypointEngine.progressSize = 0
  WaypointEngine.progressHead = 1
  WaypointEngine.walkToFailCount = 0
  WaypointEngine.lastMoveTime = now
  
  -- Clear caches
  cachedWaypointId = 0
  cachedWaypointTime = 0
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
      -- Floor changed — clear waypoint blacklist (entries were for the old floor)
      clearWaypointBlacklist()
      
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
        -- The cavebot will naturally advance to the next waypoint in the list
        safeResetWalking()
        -- Do NOT call resetWaypointEngine or findNearestGlobalWaypoint!
      else
        -- Unintended floor change - defer recovery to avoid blocking the macro tick
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
    -- All waypoints blacklisted — clear blacklist to allow recovery
    warn("[CaveBot] All waypoints blacklisted — clearing blacklist")
    clearWaypointBlacklist()
    uiList:focusChild(uiList:getChildByIndex(1))
    actionRetries = 0
    return
  end
  
  -- Direct table access (O(1))
  local actionType = currentAction.action
  local actionDef = CaveBot.Actions[actionType]
  
  if not actionDef then
    warn("[CaveBot] Invalid action: " .. tostring(actionType))
    return
  end
  
  -- Execute action (inline for performance)
  safeResetWalking()
  local result = actionDef.callback(currentAction.value, actionRetries, prevActionResult)
  
  -- Handle result
  if result == "retry" then
    actionRetries = actionRetries + 1
    if actionRetries > 20 then
      recordFailure()  -- Many retries = likely stuck
    end
    return
  end
  
  -- Track success/failure for stuck detection
  if result == true then
    recordSuccess()
  else
    recordFailure()
    -- CRITICAL FIX: goto actions that return false should NOT advance to next waypoint.
    -- This was the primary cause of the "loop standing still" bug — the bot would rapidly
    -- cycle through all unreachable waypoints (1→2→…→N→1) at ~13/s doing nothing.
    -- Instead, stay on the current waypoint and let WaypointEngine's stuck detection
    -- handle recovery (recordFailure() → STUCK → RECOVERING → find nearest reachable).
    -- Non-goto actions (depositor, buy, sell, etc.) still advance on false because
    -- retrying failed NPC interactions immediately won't help.
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
    recoveryAttempt = WaypointEngine.recoveryAttempt,
    totalMovement = WaypointEngine.totalMovement,
    progressSize = WaypointEngine.progressSize,
    isRecovering = (WaypointEngine.state == "RECOVERING" or WaypointEngine.state == "STUCK")
  }
end

-- Manually reset waypoint engine (useful for scripts that handle their own recovery)
CaveBot.resetWaypointEngine = function()
  resetWaypointEngine()
end

-- Check if CaveBot is currently in recovery mode
CaveBot.isRecovering = function()
  return WaypointEngine.state == "RECOVERING" or WaypointEngine.state == "STUCK"
end

-- Blacklist a waypoint widget so it is skipped during advancement and finder searches.
-- Used by WaypointGuard (actions.lua) to mark unreachable waypoints BEFORE triggering
-- recovery, eliminating the WP_N→WP_{N-1}→WP_N oscillation.
CaveBot.blacklistWaypoint = function(child, ttl)
  if not child then return end
  WaypointEngine.stuckWaypoints[child] = now + (ttl or WaypointEngine.BLACKLIST_TTL)
end

--[[
  OPTIMIZED WAYPOINT FINDER (v2.0)
  
  Intelligent waypoint selection with:
  1. Distance-based filtering (Chebyshev/Manhattan hybrid)
  2. Path availability validation
  3. Global search capability (for startup/recovery)
  4. Multi-floor awareness
  5. Smart startup: Find nearest waypoint on relog/load
  
  Architecture follows DRY, KISS, SRP principles:
  - Pure functions for calculations (testable, no side effects)
  - O(n) scan, O(n log n) sort (full list before truncation)
  - Minimal allocations via table reuse
  - Tiered pathfinding: distance filter → path check
]]

-- ============================================================================
-- PURE UTILITY FUNCTIONS (SRP: Single responsibility, no side effects)
-- ============================================================================

-- Parse position from goto waypoint text
-- @param text string "goto:1234,5678,7"
-- @return table {x, y, z} or nil
local function parseGotoPosition(text)
  if not text or not string.starts(text, "goto:") then return nil end
  local re = regexMatch(text, [[(?:goto:)([^,]+),([^,]+),([^,]+)]])
  if not re or not re[1] then return nil end
  return {
    x = tonumber(re[1][2]),
    y = tonumber(re[1][3]),
    z = tonumber(re[1][4])
  }
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

buildWaypointCache = function()
  if waypointCacheValid then return end
  
  waypointPositionCache = {}
  waypointCacheFloors = {}
  local actions = ui.list:getChildren()
  
  for i, child in ipairs(actions) do
    local text = child:getText()
    local pos = parseGotoPosition(text)
    if pos then
      waypointPositionCache[i] = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        child = child,
        index = i
      }
      -- Track which floors have waypoints (for cross-floor recovery)
      waypointCacheFloors[pos.z] = true
    end
  end
  
  waypointCacheValid = true
end

-- ============================================================================
-- GLOBAL WAYPOINT FINDER (Pure function, SRP)
-- Used for startup detection and stuck recovery
-- ============================================================================

--[[
  Find the nearest reachable waypoint from ANY position globally.
  
  Algorithm (optimized for both accuracy and performance):
  1. Build waypoint cache if needed (O(n))
  2. Filter by floor and collect candidates (O(n))
  3. Sort by distance (O(n log n) but typically small n after filtering)
  4. Check pathfinding for top k candidates (O(k))
  
  @param playerPos table {x, y, z} - player's current position
  @param maxDist number - maximum pathfinding distance
  @param options table (optional):
    - maxCandidates: max candidates to check pathfinding for (default 20)
    - preferCurrentFloor: prioritize current floor (default true)
    - searchAllFloors: also search adjacent floors if nothing found (default false)
    - collectRangeMultiplier: multiplier for candidate collection distance (default 1)
  @return child, index or nil, nil if not found
]]
findNearestGlobalWaypoint = function(playerPos, maxDist, options)
  buildWaypointCache()
  
  options = options or {}
  local maxCandidates = options.maxCandidates or 8
  local preferCurrentFloor = options.preferCurrentFloor ~= false
  local searchAllFloors = options.searchAllFloors or false
  local collectRangeMultiplier = options.collectRangeMultiplier or 1
  local excludeCompletedFloorChange = options.excludeCompletedFloorChange or false
  local playerZ = playerPos.z
  
  -- Phase 1: Collect candidates on same floor with distance
  local candidates = {}
  local collectionLimit = maxDist * collectRangeMultiplier

  for i, wp in pairs(waypointPositionCache) do
    -- Skip blacklisted (stuck/unreachable) waypoints
    if isWaypointBlacklisted(wp.child) then
      goto continue
    end
    
    -- Skip recently completed floor-change waypoints to prevent loops
    if excludeCompletedFloorChange and CaveBot.wasFloorChangeWaypointCompleted then
      if CaveBot.wasFloorChangeWaypointCompleted({x = wp.x, y = wp.y, z = wp.z}) then
        -- This waypoint was just completed - skip it
        goto continue
      end
    end
    
    -- Also skip waypoints that are on the floor we just came FROM
    if excludeCompletedFloorChange and CaveBot.getRecentFloorChange then
      local recent = CaveBot.getRecentFloorChange()
      if recent and wp.z == recent.fromZ then
        -- This waypoint is on the floor we just left - skip it
        goto continue
      end
    end
    
    local isSameFloor = (wp.z == playerZ)
    if isSameFloor then
      local dist = chebyshevDist(playerPos, wp)
      if dist <= collectionLimit then
        candidates[#candidates + 1] = {
          index = i,
          waypoint = wp,
          distance = dist,
          child = wp.child
        }
      end
    elseif searchAllFloors and not preferCurrentFloor then
      -- When not prioritizing current floor, allow collecting cross-floor
      local dist = manhattanDist(playerPos, wp)
      candidates[#candidates + 1] = {
        index = i,
        waypoint = wp,
        distance = dist,
        child = wp.child
      }
    end
    
    ::continue::
  end
  
  -- Phase 2: Route-aware scoring — prefer waypoints that are both close AND near current route position
  if #candidates > 0 then
    -- Get current waypoint index for order-distance calculation
    local currentIdx = 0
    local actionCount = ui and ui.list and ui.list:getChildCount() or 0
    if actionCount > 0 then
      local focused = ui.list:getFocusedChild()
      if focused then
        currentIdx = ui.list:getChildIndex(focused)
      end
    end

    -- Score each candidate: distance + orderDistance * 0.3
    for _, candidate in ipairs(candidates) do
      local orderDist = 0
      if currentIdx > 0 and actionCount > 0 then
        local fwd = (candidate.index - currentIdx) % actionCount
        local bwd = (currentIdx - candidate.index) % actionCount
        orderDist = math.min(fwd, bwd)
      end
      candidate.score = candidate.distance + orderDist * 0.3
    end

    table.sort(candidates, function(a, b)
      return a.score < b.score
    end)
    
    -- Phase 3: Check pathfinding for top candidates (tiered approach)
    local checkCount = math.min(maxCandidates, #candidates)
    for i = 1, checkCount do
      local candidate = candidates[i]
      local destPos = {x = candidate.waypoint.x, y = candidate.waypoint.y, z = candidate.waypoint.z}
      
      -- Tier 1: Normal pathfinding
      local path = findPath(playerPos, destPos, maxDist, { ignoreNonPathable = true })
      
      -- Tier 2: Ignore creatures (maybe blocked by monsters)
      if not path then
        path = findPath(playerPos, destPos, maxDist, { ignoreNonPathable = true, ignoreCreatures = true })
      end
      
      if path then
        return candidate.child, candidate.index
      end
    end
  end
  
  -- No candidates found on current floor (or none collected when preferCurrentFloor=false)
  if searchAllFloors then
    -- Try adjacent floors (±1) - useful for stairs/holes
    for _, floorZ in ipairs({playerZ - 1, playerZ + 1}) do
      if waypointCacheFloors[floorZ] then
        -- Collect candidates on this floor
        local floorCandidates = {}
        for i, wp in pairs(waypointPositionCache) do
          if wp.z == floorZ then
            local dist = manhattanDist(playerPos, wp)
            floorCandidates[#floorCandidates + 1] = {
              index = i,
              waypoint = wp,
              distance = dist,
              child = wp.child
            }
          end
        end
        
        -- Sort and return first (can't pathfind cross-floor, just return closest)
        if #floorCandidates > 0 then
          table.sort(floorCandidates, function(a, b)
            return a.distance < b.distance
          end)
          return floorCandidates[1].child, floorCandidates[1].index
        end
      end
    end
  end
  
  return nil, nil
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
      local maxDist = storage.extras.gotoMaxDistance or 50
      
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
  local maxDist = storage.extras.gotoMaxDistance or 50
  local nearestChild, nearestIndex = findNearestGlobalWaypoint(playerPos, maxDist, {
    maxCandidates = 10,
    preferCurrentFloor = true,
    searchAllFloors = false,
    excludeCompletedFloorChange = true  -- Don't select recently completed floor-change waypoints
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
    searchAllFloors = true,  -- Try adjacent floors
    excludeCompletedFloorChange = true
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

-- Find the best waypoint to go to (optimized for long distances)
CaveBot.findBestWaypoint = function(searchForward)
  buildWaypointCache()
  
  local currentAction = ui.list:getFocusedChild()
  local currentIndex = ui.list:getChildIndex(currentAction)
  local actions = ui.list:getChildren()
  local actionCount = #actions
  
  local playerPos = player:getPosition()
  local maxDist = storage.extras.gotoMaxDistance or 50  -- Realistic pathfinding limit
  local playerZ = playerPos.z
  
  -- Collect candidates: waypoints within distance on same floor
  local candidates = {}
  
  -- Build search order based on direction
  local searchOrder = {}
  if searchForward then
    -- Search forward first, then from start
    for i = currentIndex + 1, actionCount do
      table.insert(searchOrder, i)
    end
    for i = 1, currentIndex do
      table.insert(searchOrder, i)
    end
  else
    -- Search backward first
    for i = currentIndex - 1, 1, -1 do
      table.insert(searchOrder, i)
    end
  end
  
  -- Phase 1: Fast distance check (no pathfinding) - uses pure chebyshevDist function
  for _, i in ipairs(searchOrder) do
    local waypoint = waypointPositionCache[i]
    if waypoint and waypoint.z == playerZ and not isWaypointBlacklisted(waypoint.child) then
      local dist = chebyshevDist(playerPos, waypoint)
      
      if dist <= maxDist then
        table.insert(candidates, {
          index = i,
          waypoint = waypoint,
          distance = dist
        })
      end
    end
  end
  
  -- Sort by distance (closest first)
  table.sort(candidates, function(a, b)
    return a.distance < b.distance
  end)
  
  -- Phase 2: Check pathfinding for candidates (capped at 5 to limit CPU per tick)
  local maxCandidates = math.min(5, #candidates)
  for i = 1, maxCandidates do
    local candidate = candidates[i]
    local wp = candidate.waypoint
    local destPos = {x = wp.x, y = wp.y, z = wp.z}
    
    -- Check if path exists (try with and without creature ignore)
    local path = findPath(playerPos, destPos, maxDist, { ignoreNonPathable = true })
    if not path then
      -- Second attempt: ignore creatures
      path = findPath(playerPos, destPos, maxDist, { ignoreNonPathable = true, ignoreCreatures = true })
    end
    
    if path then
      -- Found a reachable waypoint — focus it directly
      ui.list:focusChild(candidate.waypoint.child)
      actionRetries = 0
      return true
    end
  end
  
  return false
end

CaveBot.gotoNextWaypointInRange = function()
  -- Use optimized waypoint finder
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

  if CaveBot.findBestWaypoint and CaveBot.findBestWaypoint(true) then
    return true
  end

  local playerPos = player and player:getPosition()
  if not playerPos then return false end

  local maxDist = storage.extras.gotoMaxDistance or 50
  local nearestChild, nearestIndex = findNearestGlobalWaypoint(playerPos, maxDist, {
    maxCandidates = 10,
    preferCurrentFloor = true,
    searchAllFloors = false,
    excludeCompletedFloorChange = true
  })

  if nearestChild then
    focusWaypointForRecovery(nearestChild, nearestIndex)
    return true
  end

  return false
end

-- Original legacy function removed (dead code, never called).
-- findBestWaypoint() handles all forward/backward waypoint search.

CaveBot.gotoFirstPreviousReachableWaypoint = function()
  local currentAction = ui.list:getFocusedChild()
  local currentIndex = ui.list:getChildIndex(currentAction)
  local maxDist = storage.extras.gotoMaxDistance
  local halfDist = maxDist / 2
  local extendedDist = maxDist * 2 -- Extended range for finding waypoints
  local playerPos = player:getPosition()
  
  -- Cache of candidates for extended range (in case we don't find anything in normal range)
  local extendedCandidates = {}

  -- check up to 100 waypoints backwards
  for i = 1, 100 do
    local index = currentIndex - i
    if index <= 0 then
      break
    end

    local child = ui.list:getChildByIndex(index)

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
                print("CaveBot: Found previous waypoint at distance " .. dist .. ", going back " .. i .. " waypoints.")
                return ui.list:focusChild(child)
              end
            -- Second priority: Extended range candidates
            elseif dist <= extendedDist then
              table.insert(extendedCandidates, {child = child, pos = pos, dist = dist, steps = i})
            end
          end
        end
      end
    end
  end

  -- If we didn't find anything in normal range, try extended range
  if #extendedCandidates > 0 then
    -- Sort by distance (closest first)
    table.sort(extendedCandidates, function(a, b) return a.dist < b.dist end)
    
    for _, candidate in ipairs(extendedCandidates) do
      local path = findPath(playerPos, candidate.pos, extendedDist, { ignoreNonPathable = true })
      if path then
        print("CaveBot: Found previous waypoint at extended range (distance " .. candidate.dist .. "), going back " .. candidate.steps .. " waypoints.")
        return ui.list:focusChild(candidate.child)
      end
    end
  end

  -- not found
  print("CaveBot: Previous waypoint not found, proceeding")
  return false
end

CaveBot.getFirstWaypointBeforeLabel = function(label)
  label = "label:"..label
  label = label:lower()
  local actions = ui.list:getChildren()
  local index
  local maxDist = storage.extras.gotoMaxDistance
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
  return CaveBot.walkTo(dest, storage.extras.gotoMaxDistance or 50, {
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