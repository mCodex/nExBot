local cavebotMacro = nil
local config = nil
local slow_ops = nil
pcall(function() slow_ops = dofile('/utils/slow_ops.lua') end)
if not slow_ops then
  slow_ops = {start = function() end, finish = function() end, with = function(f) return f() end, isEnabled = function() return false end}
end
local lastMacroTime = 0

local function getCfg(key, def)
  if CaveBot and CaveBot.Config and CaveBot.Config.get then
    local ok, v = pcall(function() return CaveBot.Config.get(key) end)
    if ok and v ~= nil then return v end
  end
  return def
end

-- ui
local configWidget = UI.Config()  -- Create config widget first
local ui = UI.createWidget("CaveBotPanel")

-- Hide the global "Money Rune" icon while CaveBot UI is loaded (non-destructive)
local function hideMoneyRuneIcon()
  local ok, root = pcall(function() return g_ui.getRootWidget() end)
  if not ok or not root then return false end

  local function matchAndHide(widget)
    if not widget then return false end
    -- Check common text/tooltip properties
    local ok1, txt = pcall(function() if type(widget.getText) == 'function' then return widget:getText() end end)
    if ok1 and txt == 'Money Rune' then pcall(function() widget:setVisible(false) end); return true end
    local ok2, tip = pcall(function() if type(widget.getTooltip) == 'function' then return widget:getTooltip() end end)
    if ok2 and tip == 'Money Rune' then pcall(function() widget:setVisible(false) end); return true end

    -- Recurse children
    local ok3, children = pcall(function() return widget:getChildren() end)
    if ok3 and children then
      for _, ch in ipairs(children) do
        if matchAndHide(ch) then return true end
      end
    end
    return false
  end

  return matchAndHide(root)
end

-- Try once immediately, then retry after a short delay to handle load-order
local function ensureHideMoneyRune()
  if hideMoneyRuneIcon() then
    print('[CaveBot] Hidden "Money Rune" icon from UI')
  else
    schedule(200, function()
      if hideMoneyRuneIcon() then print('[CaveBot] Hidden "Money Rune" icon on retry') end
    end)
  end
end

ensureHideMoneyRune()

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

--[[
  SIMPLIFIED WAYPOINT STATE MACHINE (Event-Driven)
  
  States:
  - IDLE: Not walking, ready for next action
  - WALKING: Walk command issued, waiting for arrival
  - ARRIVED: Reached destination, ready to advance
  
  Events:
  - player:move -> Check arrival, emit cavebot/arrived
  - cavebot/arrived -> Advance waypoint immediately
  - cavebot/walk_timeout -> Handle stuck detection
]]

-- ============================================================================
-- CORE STATE (Minimal, single source of truth)
-- ============================================================================
local WaypointState = {
  -- Current state
  state = "IDLE",           -- IDLE, WALKING, ARRIVED
  
  -- Target tracking
  targetPos = nil,          -- {x, y, z}
  targetPrecision = 1,      -- Arrival precision
  targetValue = nil,        -- Waypoint value string
  
  -- Timing
  walkStartTime = 0,        -- When walk was issued
  lastAdvanceTime = 0,      -- When last waypoint was advanced
  delayUntil = 0,           -- Delay before next action
  
  -- Stuck detection
  lastMoveTime = 0,         -- Last time player moved
  lastPos = nil,            -- Last known position
  
  -- Configuration
  WALK_TIMEOUT = 4000,      -- 4s max walk time before stuck
  ADVANCE_COOLDOWN = 50,    -- 50ms between advances (prevents double-fire)
  MAX_DELAY = 300,          -- Cap action delays to 300ms
}

-- ============================================================================
-- PURE FUNCTIONS (No side effects, testable)
-- ============================================================================

-- Check if player is at target position
local function isAtTarget(playerPos, targetPos, precision)
  if not playerPos or not targetPos then return false end
  if playerPos.z ~= targetPos.z then return false end
  local dx = math.abs(playerPos.x - targetPos.x)
  local dy = math.abs(playerPos.y - targetPos.y)
  return dx <= precision and dy <= precision
end

-- Parse goto value to position
local function parseGotoValue(value)
  if not value then return nil, 1 end
  local match = regexMatch(value, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+),?\\s*([0-9]?)")
  if not match or not match[1] then return nil, 1 end
  local pos = {
    x = tonumber(match[1][2]),
    y = tonumber(match[1][3]),
    z = tonumber(match[1][4])
  }
  local precision = tonumber(match[1][5]) or 1
  return pos, precision
end

-- ============================================================================
-- STATE TRANSITIONS (Clean state machine)
-- ============================================================================

local function transitionTo(newState, data)
  local oldState = WaypointState.state
  WaypointState.state = newState
  
  if newState == "WALKING" then
    WaypointState.walkStartTime = now
    WaypointState.targetPos = data and data.pos
    WaypointState.targetPrecision = data and data.precision or 1
    WaypointState.targetValue = data and data.value
  elseif newState == "ARRIVED" then
    WaypointState.walkStartTime = 0
  elseif newState == "IDLE" then
    WaypointState.targetPos = nil
    WaypointState.targetValue = nil
    WaypointState.walkStartTime = 0
  end
end

-- ============================================================================
-- EVENT HANDLERS (Core event-driven logic)
-- ============================================================================

-- Handle player movement - check for arrival
local function onPlayerMove(newPos, oldPos)
  if not CaveBot or CaveBot.isOff() then return end
  if not newPos then return end
  
  -- Update last move time for stuck detection
  WaypointState.lastMoveTime = now
  WaypointState.lastPos = newPos
  
  -- Check if we've arrived at target
  if WaypointState.state == "WALKING" and WaypointState.targetPos then
    if isAtTarget(newPos, WaypointState.targetPos, WaypointState.targetPrecision) then
      transitionTo("ARRIVED")
      -- Emit arrival event for immediate waypoint advancement
      if EventBus then
        EventBus.emit("cavebot/arrived", WaypointState.targetPos, WaypointState.targetValue)
      end
    end
  end
  
  -- Also check current focused waypoint for direct arrival detection
  if WaypointState.state ~= "ARRIVED" and ui and ui.list then
    local currentAction = ui.list:getFocusedChild()
    if currentAction and currentAction.action == "goto" then
      local targetPos, precision = parseGotoValue(currentAction.value)
      if targetPos and isAtTarget(newPos, targetPos, precision) then
        transitionTo("ARRIVED", {pos = targetPos, precision = precision, value = currentAction.value})
        if EventBus then
          EventBus.emit("cavebot/arrived", targetPos, currentAction.value)
        end
      end
    end
  end
end

-- Handle arrival - advance waypoint immediately
local function onWaypointArrived(targetPos, waypointValue)
  if not CaveBot or CaveBot.isOff() then return end
  if not ui or not ui.list then return end
  
  -- Cooldown check to prevent double-fire
  if now - WaypointState.lastAdvanceTime < WaypointState.ADVANCE_COOLDOWN then
    return
  end
  
  local currentAction = ui.list:getFocusedChild()
  if not currentAction then return end
  
  -- Advance to next waypoint
  local currentIndex = ui.list:getChildIndex(currentAction)
  local actionCount = ui.list:getChildCount()
  if actionCount == 0 then return end
  
  local nextIndex = currentIndex + 1
  if nextIndex > actionCount then nextIndex = 1 end
  
  local nextChild = ui.list:getChildByIndex(nextIndex)
  if nextChild then
    ui.list:focusChild(nextChild)
    WaypointState.lastAdvanceTime = now
    transitionTo("IDLE")
    
    -- Reset action state
    actionRetries = 0
    prevActionResult = true
  end
end

-- ============================================================================
-- REGISTER EVENT HANDLERS
-- ============================================================================
if EventBus then
  -- Player movement - highest priority for fast arrival detection
  EventBus.on("player:move", onPlayerMove, 15)
  
  -- Waypoint arrival - immediate advancement
  EventBus.on("cavebot/arrived", onWaypointArrived, 15)
end

-- ============================================================================
-- SIMPLIFIED EXECUTION CHECK
-- ============================================================================
local function shouldSkipExecution()
  -- Cap delays to prevent stuck states
  if WaypointState.delayUntil > 0 and now < WaypointState.delayUntil then
    if WaypointState.delayUntil - now > WaypointState.MAX_DELAY then
      WaypointState.delayUntil = now + WaypointState.MAX_DELAY
    end
    return true
  end
  
  -- Skip if player is mid-step
  if player:isWalking() then
    return true
  end
  
  -- Check for stuck while walking
  if WaypointState.state == "WALKING" then
    local walkDuration = now - WaypointState.walkStartTime
    if walkDuration > WaypointState.WALK_TIMEOUT then
      -- Stuck - transition to IDLE and let macro retry
      transitionTo("IDLE")
      return false  -- Don't skip, try again
    end
  end
  
  return false
end

-- Mark that we're walking to a waypoint
CaveBot.setWalkingToWaypoint = function(targetPos, precision, value)
  transitionTo("WALKING", {pos = targetPos, precision = precision or 1, value = value})
end

-- Clear walking state
CaveBot.clearWalkingState = function()
  transitionTo("IDLE")
end

-- Set delay
CaveBot.delay = function(ms)
  WaypointState.delayUntil = now + math.min(ms, WaypointState.MAX_DELAY)
end

-- Legacy compatibility
local walkState = {
  isWalkingToWaypoint = false,
  targetPos = nil,
  lastActionTime = 0,
  delayUntil = 0,
  lastPlayerPos = nil,
  stuckCheckTime = 0,
  STUCK_TIMEOUT = 3000
}

-- Sync legacy state for backward compatibility
local function syncLegacyState()
  walkState.isWalkingToWaypoint = (WaypointState.state == "WALKING")
  walkState.targetPos = WaypointState.targetPos
  walkState.delayUntil = WaypointState.delayUntil
  walkState.lastPlayerPos = WaypointState.lastPos
end

-- Check if player has moved (legacy function)
local function hasPlayerMoved()
  local currentPos = pos()
  if not currentPos or not WaypointState.lastPos then
    WaypointState.lastPos = currentPos
    return true
  end
  local moved = (currentPos.x ~= WaypointState.lastPos.x or
                 currentPos.y ~= WaypointState.lastPos.y or
                 currentPos.z ~= WaypointState.lastPos.z)
  if moved then
    WaypointState.lastPos = currentPos
    WaypointState.lastMoveTime = now
  end
  return moved
end

-- ============================================================================
-- FORWARD DECLARATIONS (functions defined later but used early)
-- ============================================================================
local findNearestGlobalWaypoint  -- Defined in WAYPOINT FINDER section
local checkStartupWaypoint       -- Defined in STARTUP DETECTION section
local invalidateWaypointCache    -- Defined in WAYPOINT CACHE section
local resetStartupCheck          -- Defined in STARTUP DETECTION section
local buildWaypointCache         -- Defined in WAYPOINT CACHE section
local chebyshevDist              -- Defined in PURE UTILITY FUNCTIONS section
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

local WaypointEngine = {
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
  
  -- Thresholds (tuned for accuracy)
  STUCK_THRESHOLD = 8,           -- Failures before stuck
  STUCK_TIMEOUT = 5000,         -- Reduced from 10000 for faster stuck detection
  MOVEMENT_THRESHOLD = 3,        -- Min tiles to consider "progress"
  PROGRESS_WINDOW = 15000,       -- Time window for progress check (15s)
  RECOVERY_TIMEOUT = 25000,      -- Max recovery time before stop (increased for more strategies)
  
  -- Backoff for recovery attempts
  recoveryAttempt = 0,
  MAX_RECOVERY_ATTEMPTS = 6,     -- Increased: 6 strategies now available
  
  -- Performance counters (optional, for debugging)
  tickCount = 0,
  lastTickTime = 0
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
  if WaypointEngine.state ~= "NORMAL" then
    transitionTo("NORMAL")
  end
end

local function recordFailure()
  WaypointEngine.failureCount = WaypointEngine.failureCount + 1
end

-- ============================================================================
-- RECOVERY STRATEGIES (ordered by likelihood of success)
-- Uses a tiered approach: fast local search → global search → skip strategies
-- ============================================================================

-- Oscillation protection (prevent rapid floor flip-flops between waypoints)
local FLOOR_OSCILLATION_WINDOW = getCfg("floorOscillationWindow", 5000) -- ms
local lastFloorChangeRecord = nil

-- Called by walking layer when player's floor changes unexpectedly.
-- Detects quick flip back between two floors and advances waypoint focus to escape loops.
CaveBot.onFloorChanged = function(fromFloor, toFloor)
  if not ui or not ui.list then return end
  local nowTs = now or os.time() * 1000
  if lastFloorChangeRecord and lastFloorChangeRecord.from == toFloor and lastFloorChangeRecord.to == fromFloor and (nowTs - lastFloorChangeRecord.ts) <= FLOOR_OSCILLATION_WINDOW then
    -- Detected flip-flop between floors within window -> advance focused waypoint to escape loop
    local current = ui.list:getFocusedChild() or ui.list:getFirstChild()
    if current then
      local idx = ui.list:getChildIndex(current) or 1
      local actionCount = ui.list:getChildCount()
      local nextIdx = idx + 1
      if nextIdx > actionCount then nextIdx = 1 end
      local nextChild = ui.list:getChildByIndex(nextIdx)
      if nextChild then
        -- mark the problematic waypoint (the one we just left) as snoozed to avoid immediate re-visit
        local snoozeDur = getCfg("floorOscillationSnooze", 8000)
        current.snoozedUntil = nowTs + snoozeDur
        -- visually mark (best effort): set color to gray if widget supports setColor
        pcall(function() current:setColor("#888888") end)

        ui.list:focusChild(nextChild)
        print(string.format('[CaveBot] Floor oscillation detected (%d <-> %d). Advancing waypoint index from %d to %d and snoozing waypoint for %dms.', fromFloor, toFloor, idx, nextIdx, snoozeDur))
        -- reset walking and waypoint engine state to avoid immediate re-trigger
        CaveBot.resetWalking()
        resetWaypointEngine()
      end
    end
    lastFloorChangeRecord = nil
  else
    lastFloorChangeRecord = { from = fromFloor, to = toFloor, ts = nowTs }
  end
end

-- Helper function to focus a waypoint (DRY: used in recovery and startup)
-- Focuses the waypoint BEFORE the target so next tick executes it
-- @param targetChild widget The waypoint widget to focus
-- @param targetIndex number The index of the waypoint
local function focusWaypointBefore(targetChild, targetIndex)
  local prevChild = ui.list:getChildByIndex(targetIndex - 1)
  if prevChild then
    ui.list:focusChild(prevChild)
  else
    ui.list:focusChild(targetChild)
  end
end

-- Find closest waypoint by distance only (no pathfinding - very fast)
local function findClosestWaypointByDistance(playerPos, maxDist)
  if not playerPos then return nil, nil end
  buildWaypointCache()
  
  local bestChild, bestIndex, bestDist = nil, nil, maxDist + 1
  local px, py, pz = playerPos.x, playerPos.y, playerPos.z
  
  for i, wp in pairs(waypointPositionCache) do
    -- Same floor only for simplicity
    if wp.z == pz then
      local dx = math.abs(wp.x - px)
      local dy = math.abs(wp.y - py)
      local dist = math.max(dx, dy)  -- Chebyshev distance
      
      if dist < bestDist and dist <= maxDist then
        bestDist = dist
        bestChild = wp.child
        bestIndex = i
      end
    end
  end
  
  return bestChild, bestIndex
end

local function executeRecovery()
  local attempt = WaypointEngine.recoveryAttempt
  local playerPos = player:getPosition()
  local maxDist = storage.extras.gotoMaxDistance or 50
  
  -- Emergency break for combat/emergency
  if storage.targetbotCombatActive or storage.targetbotEmergency then
    return false
  end
  
  -- Strategy 1: Find nearest reachable waypoint (forward search - fastest)
  if attempt <= 1 then
    if CaveBot.findBestWaypoint and CaveBot.findBestWaypoint(true) then
      print("[CaveBot] Recovery: Found waypoint via forward search")
      transitionTo("NORMAL")
      return true
    end
    WaypointEngine.recoveryAttempt = 2
    return false
  end
  
  -- Strategy 2: Search backwards for reachable waypoint
  if attempt <= 2 then
    if CaveBot.gotoFirstPreviousReachableWaypoint and CaveBot.gotoFirstPreviousReachableWaypoint() then
      print("[CaveBot] Recovery: Found waypoint via backward search")
      transitionTo("NORMAL")
      return true
    end
    WaypointEngine.recoveryAttempt = 3
    return false
  end
  
  -- Strategy 3: SIMPLE DISTANCE-BASED SEARCH (no pathfinding - very fast)
  if attempt <= 3 and playerPos then
    local nearestChild, nearestIndex = findClosestWaypointByDistance(playerPos, maxDist)
    if nearestChild and nearestIndex then
      print("[CaveBot] Recovery: Found closest waypoint by distance at index " .. nearestIndex)
      focusWaypointBefore(nearestChild, nearestIndex)
      transitionTo("NORMAL")
      return true
    end
    WaypointEngine.recoveryAttempt = 4
    return false
  end
  
  -- Strategy 4: Skip current waypoint (no pathfinding needed)
  if attempt <= 4 then
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
          WaypointEngine.recoveryAttempt = 5
          return false
        end
      end
    end
  end
  
  -- Strategy 5: Skip multiple waypoints (exponential skip - emergency)
  if attempt <= 5 then
    if ui and ui.list then
      local actionCount = ui.list:getChildCount()
      local skipCount = math.min(5, math.floor(actionCount / 4))
      if actionCount > skipCount then
        local current = ui.list:getFocusedChild()
        if current then
          local currentIndex = ui.list:getChildIndex(current)
          local nextIndex = ((currentIndex + skipCount - 1) % actionCount) + 1
          local nextChild = ui.list:getChildByIndex(nextIndex)
          if nextChild then
            print("[CaveBot] Recovery: Skipping " .. skipCount .. " waypoints")
            ui.list:focusChild(nextChild)
            transitionTo("NORMAL")
            return true
          end
        end
        WaypointEngine.recoveryAttempt = 5
        return false
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
    
    if isStuck then
      transitionTo("STUCK")
    end
    
    return false  -- No intervention needed
    
  elseif state == "STUCK" then
    -- Check if we should transition to recovery
    local stuckDuration = now - WaypointEngine.stuckStartTime
    
    -- Give some time for natural resolution
    if stuckDuration < 3000 then
      return false
    end
    
    -- Check if player started moving (natural recovery)
    if hasRecentProgress() and WaypointEngine.failureCount < 3 then
      transitionTo("NORMAL")
      return false
    end
    
    -- Timeout: start recovery
    if stuckDuration >= WaypointEngine.STUCK_TIMEOUT then
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
    -- CaveBot should stop
    if config and config.setOff then
      warn("[CaveBot] Unable to recover. Stopping.")
      config.setOff()
    end
    return true
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
-- SIMPLE WAYPOINT FINDER (Lightweight, no heavy pathfinding)
-- ============================================================================

-- Simple candidate collection (no pre-allocation needed for small lists)
local function collectWaypointCandidates(playerPos, maxDist, options)
  options = options or {}
  local candidates = {}
  candidatePoolSize = 0
  
  local collectionLimit = maxDist * (options.collectRangeMultiplier or 1)
  local px, py, pz = playerPos.x, playerPos.y, playerPos.z
  local preferCurrentFloor = options.preferCurrentFloor ~= false
  local searchAllFloors = options.searchAllFloors or false
  local collectionLimitSq = collectionLimit * collectionLimit  -- Avoid sqrt
  
  -- Early exit if cache is empty
  local cacheEmpty = true
  for _ in pairs(waypointPositionCache) do cacheEmpty = false; break end
  if cacheEmpty then return {} end
  
  -- Single pass with early exits
  for i, wp in pairs(waypointPositionCache) do
    -- Quick Z check first (cheapest)
    local isSameFloor = (wp.z == pz)
    if not isSameFloor and (preferCurrentFloor or not searchAllFloors) then
      -- Skip if different floor and we're preferring current floor
      goto continue
    end
    
    -- Inline distance calculation with early X exit
    local dx = wp.x - px
    if dx < 0 then dx = -dx end
    if dx > collectionLimit then goto continue end
    
    local dy = wp.y - py
    if dy < 0 then dy = -dy end  
    if dy > collectionLimit then goto continue end
    
    -- Compute final distance (Chebyshev for same floor, Manhattan for cross-floor)
    local dist = isSameFloor and (dx > dy and dx or dy) or (dx + dy)
    if dist > collectionLimit then goto continue end
    
    -- Add to pool (reuse pre-allocated entry)
    candidatePoolSize = candidatePoolSize + 1
    if candidatePoolSize > MAX_CANDIDATE_POOL then
      candidatePoolSize = MAX_CANDIDATE_POOL
      break  -- Pool full, stop collecting
    end
    
    local entry = candidatePool[candidatePoolSize]
    entry.index = i
    entry.waypoint = wp
    entry.distance = dist
    entry.child = wp.child
    
    ::continue::
  end
  
  return candidates
end

-- Stub functions for compatibility (no-op, lightweight)
local function cancelIncrementalSearch() end
local function startIncrementalWaypointSearch() return false end

local _lastCavebotSlowWarn = 0
local _macroHardTimeout = 0.12  -- 120ms hard timeout

-- ============================================================================
-- MAIN MACRO (Simplified - event handlers do most work)
-- ============================================================================

cavebotMacro = macro(150, function()
  local _msStart = os.clock()
  
  -- Prevent overlapping executions
  if _msStart - (lastMacroTime or 0) < 0.12 then return end
  lastMacroTime = _msStart
  
  -- Time budget to prevent freezing
  local totalBudget = 0.12
  local budgetStart = _msStart
  
  -- Prevent execution before login
  if not g_game.isOnline() then return end
  
  -- Skip if we shouldn't execute this tick
  if shouldSkipExecution() then 
    syncLegacyState()
    return 
  end
  
  -- Update player position tracking
  hasPlayerMoved()

  -- Get player position
  local playerPos = player:getPosition()
  if not playerPos then return end
  
  -- Floor change detection
  if lastPlayerFloor and playerPos.z ~= lastPlayerFloor then
    CaveBot.clearWalkingState()
    resetWaypointEngine()
    if resetStartupCheck then resetStartupCheck() end
    
    -- Find closest waypoint on new floor
    local maxDist = storage.extras.gotoMaxDistance or 50
    local closestChild, closestIndex = findClosestWaypointByDistance(playerPos, maxDist)
    if closestChild and closestIndex then
      focusWaypointBefore(closestChild, closestIndex)
    end
  end
  lastPlayerFloor = playerPos.z
  
  -- Budget check
  if (os.clock() - budgetStart) > totalBudget then return end
  
  -- Startup detection (find nearest waypoint on relog)
  if checkStartupWaypoint then
    checkStartupWaypoint()
  end
  
  -- Budget check
  if (os.clock() - budgetStart) > totalBudget then return end
  
  -- Waypoint engine stuck detection
  if runWaypointEngine() then
    return
  end
  
  -- Budget check
  if (os.clock() - budgetStart) > totalBudget then return end
  
  -- TargetBot integration
  if not targetBotIsActive and TargetBot then
    initTargetBotCache()
  end
  
  if targetBotIsActive and targetBotIsActive() then
    if targetBotIsCaveBotAllowed and not targetBotIsCaveBotAllowed() then
      return
    end
    if TargetBot.smartPullActive then
      return
    end
  end
  
  -- Get UI list
  uiList = uiList or ui.list
  local actionCount = uiList:getChildCount()
  if actionCount == 0 then return end
  
  -- Get current action
  local currentAction = uiList:getFocusedChild() or uiList:getFirstChild()
  if not currentAction then return end

  -- Skip snoozed waypoints
  if currentAction.snoozedUntil and currentAction.snoozedUntil > now then
    local currentIndex = uiList:getChildIndex(currentAction)
    local nextIndex = (currentIndex % actionCount) + 1
    local nextChild = uiList:getChildByIndex(nextIndex)
    if nextChild then uiList:focusChild(nextChild) end
    return
  end
  
  -- Get action definition
  local actionType = currentAction.action
  local actionDef = CaveBot.Actions[actionType]
  
  if not actionDef then
    warn("[CaveBot] Invalid action: " .. tostring(actionType))
    return
  end
  
  -- Execute action
  -- Final budget check before action
  if os.clock() - budgetStart > totalBudget * 0.8 then return end
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

  -- Save character's profile preference when profile changes (multi-client support)
  if enabled and name and name ~= "" and setCharacterProfile then
    setCharacterProfile("cavebotProfile", name)
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
  CaveBot.resetWalking()
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
  config.setOn()  -- This triggers callback which handles storage
end

CaveBot.setOff = function(val)
  if val == false then  
    return CaveBot.setOn(true)
  end
  config.setOff()  -- This triggers callback which handles storage
end

CaveBot.getCurrentProfile = function()
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

-- NOTE: parseGotoPosition is defined earlier in the file (event-driven waypoint section)

-- Calculate Chebyshev distance (max of dx, dy) - used for "within range" checks
-- @param p1 table Table with x, y fields (first position)
-- @param p2 table Table with x, y fields (second position)
-- @return number
chebyshevDist = function(p1, p2)
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

-- Calculate Manhattan distance (dx + dy) - used for path length estimation
-- @param p1 table Table with x, y fields (first position)
-- @param p2 table Table with x, y fields (second position)
-- @return number
local function manhattanDist(p1, p2)
  return math.abs(p1.x - p2.x) + math.abs(p1.y - p2.y)
end

-- Pure: Check if position is valid (KISS)
local function isValidPosition(pos)
  return pos and type(pos.x) == 'number' and type(pos.y) == 'number' and type(pos.z) == 'number'
end

-- Pure: Sort candidates by distance (KISS)
local function sortCandidatesByDistance(candidates)
  table.sort(candidates, function(a, b) return a.distance < b.distance end)
  return candidates
end

-- Pure: Check if we should break pathfinding check (SRP)
local function shouldBreakPathfindingCheck(startTime, timeBudgetSec)
  return os.clock() - startTime > timeBudgetSec or storage.targetbotCombatActive or storage.targetbotEmergency
end

-- ============================================================================
-- WAYPOINT CACHE (DRY: Single source of truth for waypoint positions)
-- ============================================================================

-- Note: waypointPositionCache, waypointCacheValid, waypointCacheFloors declared at top

-- Parse position from goto waypoint text
-- @param text string "goto:1234,5678,7" or "1234,5678,7"
-- @return table {x, y, z} or nil
local function parseGotoPosition(text)
  if not text then return nil end
  -- Try "goto:x,y,z" format first
  if string.starts and string.starts(text, "goto:") then
    local re = regexMatch(text, [[(?:goto:)([^,]+),([^,]+),([^,]+)]])
    if re and re[1] then
      return {
        x = tonumber(re[1][2]),
        y = tonumber(re[1][3]),
        z = tonumber(re[1][4])
      }
    end
  end
  -- Try plain "x,y,z" format
  local match = regexMatch(text, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)")
  if match and match[1] then
    return {
      x = tonumber(match[1][2]),
      y = tonumber(match[1][3]),
      z = tonumber(match[1][4])
    }
  end
  return nil
end

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
  -- SIMPLIFIED: Use distance-only search (no pathfinding) to prevent freezes
  -- This is much faster and sufficient for most cases
  return findClosestWaypointByDistance(playerPos, maxDist)
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
  if now - startupCheckTime < 200 then return end
  
  local playerPos = player:getPosition()
  if not playerPos then return end
  
  buildWaypointCache()
  
  -- Check if current focused waypoint is already close enough (no pathfinding - fast)
  local currentAction = ui.list:getFocusedChild()
  if currentAction then
    local currentIndex = ui.list:getChildIndex(currentAction)
    local currentWp = waypointPositionCache[currentIndex]
    
    if currentWp and currentWp.z == playerPos.z then
      local dist = chebyshevDist(playerPos, currentWp)
      local maxDist = storage.extras.gotoMaxDistance or 50
      
      if dist <= maxDist then
        -- Close enough on same floor - assume reachable (no pathfinding)
        startupWaypointFound = true
        return
      end
    end
  end
  
  -- Current waypoint not reachable - find nearest globally (lightweight distance-based search)
  local maxDist = storage.extras.gotoMaxDistance or 50
  local nearestChild, nearestIndex = findNearestGlobalWaypoint(playerPos, maxDist * 2)
  
  if nearestChild then
    print("[CaveBot] Startup: Found nearest waypoint at index " .. nearestIndex)
    focusWaypointBefore(nearestChild, nearestIndex)
    startupWaypointFound = true
    return
  end
  
  -- Extended search: larger distance
  local extendedChild, extendedIndex = findNearestGlobalWaypoint(playerPos, maxDist * 3)
  
  if extendedChild then
    print("[CaveBot] Startup: Found waypoint at extended range, index " .. extendedIndex)
    focusWaypointBefore(extendedChild, extendedIndex)
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
    if waypoint and waypoint.z == playerZ then
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
  
  -- Phase 2: Use closest candidate by distance (no pathfinding - fast)
  if #candidates > 0 then
    local candidate = candidates[1]  -- Already sorted by distance
    local prevChild = ui.list:getChildByIndex(candidate.index - 1)
    if prevChild then
      ui.list:focusChild(prevChild)
    else
      ui.list:focusChild(candidate.waypoint.child)
    end
    return true
  end
  
  return false
end

CaveBot.gotoNextWaypointInRange = function()
  -- Use optimized waypoint finder
  return CaveBot.findBestWaypoint(true)
end

-- Original function for backward compatibility (redirects to optimized version)
CaveBot.gotoNextWaypointInRangeLegacy = function()
  local currentAction = ui.list:getFocusedChild()
  local index = ui.list:getChildIndex(currentAction)
  local actions = ui.list:getChildren()

  -- start searching from current index (distance only - no pathfinding)
  for i, child in ipairs(actions) do
    if i > index then
      local text = child:getText()
      if string.starts(text, "goto:") then
        local re = regexMatch(text, [[(?:goto:)([^,]+),([^,]+),([^,]+)]])
        local pos = {x = tonumber(re[1][2]), y = tonumber(re[1][3]), z = tonumber(re[1][4])}
        
        if posz() == pos.z then
          local maxDist = storage.extras.gotoMaxDistance
          if distanceFromPlayer(pos) <= maxDist then
            -- Close enough on same floor - use it (no pathfinding)
            ui.list:focusChild(ui.list:getChildByIndex(i-1))
            return true
          end
        end
      end
    end
  end

  -- if not found then damn go from start (distance only - no pathfinding)
  for i, child in ipairs(actions) do
    if i <= index then
      local text = child:getText()
      if string.starts(text, "goto:") then
        local re = regexMatch(text, [[(?:goto:)([^,]+),([^,]+),([^,]+)]])
        local pos = {x = tonumber(re[1][2]), y = tonumber(re[1][3]), z = tonumber(re[1][4])}

        if posz() == pos.z then
          local maxDist = storage.extras.gotoMaxDistance
          if distanceFromPlayer(pos) <= maxDist then
            -- Close enough on same floor - use it (no pathfinding)
            ui.list:focusChild(ui.list:getChildByIndex(i-1))
            return true
          end
        end
      end
    end
  end

  -- not found
  return false
end

local function reverseTable(t, max)
  local reversedTable = {}
  local itemCount = max or #t
  for i, v in ipairs(t) do
      reversedTable[itemCount + 1 - i] = v
  end
  return reversedTable
end

function rpairs(t)
  test()
	return function(t, i)
		i = i - 1
		if i ~= 0 then
			return i, t[i]
		end
	end, t, #t + 1
end

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
            
            -- Use distance only - no pathfinding (fast)
            if dist <= halfDist then
              print("CaveBot: Found previous waypoint at distance " .. dist .. ", going back " .. i .. " waypoints.")
              return ui.list:focusChild(child)
            elseif dist <= extendedDist then
              table.insert(extendedCandidates, {child = child, pos = pos, dist = dist, steps = i})
            end
          end
        end
      end
    end
  end

  -- If we didn't find anything in normal range, use closest extended range (no pathfinding)
  if #extendedCandidates > 0 then
    table.sort(extendedCandidates, function(a, b) return a.dist < b.dist end)
    local candidate = extendedCandidates[1]
    print("CaveBot: Found previous waypoint at extended range (distance " .. candidate.dist .. "), going back " .. candidate.steps .. " waypoints.")
    return ui.list:focusChild(candidate.child)
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
            
            -- Use distance only - no pathfinding (fast)
            if dist <= halfDist then
              return ui.list:focusChild(child)
            elseif dist <= extendedDist then
              table.insert(extendedCandidates, {child = child, pos = pos, dist = dist})
            end
          end
        end
      end
    end
  end

  -- Use closest extended range if nothing found (no pathfinding)
  if #extendedCandidates > 0 then
    table.sort(extendedCandidates, function(a, b) return a.dist < b.dist end)
    return ui.list:focusChild(extendedCandidates[1].child)
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
  -- Save character's profile preference for multi-client support
  if setCharacterProfile then
    setCharacterProfile("cavebotProfile", name)
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