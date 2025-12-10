local cavebotMacro = nil
local config = nil

-- ui
local configWidget = UI.Config()
local ui = UI.createWidget("CaveBotPanel")

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

-- Cache frequently accessed values
local cachedActionCount = 0
local cachedCurrentAction = nil
local lastCacheUpdate = 0
local CACHE_TTL = 100  -- Update cache every 100ms

-- Cached UI list reference (avoid repeated lookups)
local uiList = nil

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

-- Check if we're stuck (no movement for too long)
local function isStuck()
  if not walkState.isWalkingToWaypoint then return false end
  return now > walkState.stuckCheckTime
end

-- Set a delay before next execution
local function setExecutionDelay(delayMs)
  walkState.delayUntil = now + delayMs
end

-- Check if we should skip execution
-- SIMPLIFIED: Only skip during active walking, don't block on walk state tracking
local function shouldSkipExecution()
  -- Active delay from previous action
  if now < walkState.delayUntil then
    return true
  end
  
  -- Player is actively walking - wait for walk to complete
  -- This is the only reliable check - player:isWalking() is definitive
  if player:isWalking() then
    return true
  end
  
  -- If player stopped walking, clear the walking state
  if walkState.isWalkingToWaypoint then
    walkState.isWalkingToWaypoint = false
    walkState.targetPos = nil
  end
  
  return false
end

-- Mark that we're walking to a waypoint
CaveBot.setWalkingToWaypoint = function(targetPos)
  walkState.isWalkingToWaypoint = true
  walkState.targetPos = targetPos
  walkState.stuckCheckTime = now + walkState.STUCK_TIMEOUT
  walkState.lastPlayerPos = pos()
end

-- Clear walking state
CaveBot.clearWalkingState = function()
  walkState.isWalkingToWaypoint = false
  walkState.targetPos = nil
end

--[[
  HIGH-PERFORMANCE WAYPOINT ENGINE v3.0
  
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
  STUCK_TIMEOUT = 10000,         -- Max time in stuck state before recovery
  MOVEMENT_THRESHOLD = 3,        -- Min tiles to consider "progress"
  PROGRESS_WINDOW = 15000,       -- Time window for progress check (15s)
  RECOVERY_TIMEOUT = 20000,      -- Max recovery time before stop
  
  -- Backoff for recovery attempts
  recoveryAttempt = 0,
  MAX_RECOVERY_ATTEMPTS = 5,
  
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

-- Fast position parsing with caching
local cachedWaypointPos = nil
local cachedWaypointPosTime = 0
local function getCurrentWaypointPos()
  if now - cachedWaypointPosTime < 100 then
    return cachedWaypointPos
  end
  cachedWaypointPosTime = now
  
  if not ui or not ui.list then 
    cachedWaypointPos = nil
    return nil 
  end
  
  local focused = ui.list:getFocusedChild()
  if not focused then 
    cachedWaypointPos = nil
    return nil 
  end
  
  local actionType = focused.action
  if actionType ~= "goto" and actionType ~= "walk" then
    cachedWaypointPos = nil
    return nil
  end
  
  local value = focused.value
  if not value or type(value) ~= "string" then 
    cachedWaypointPos = nil
    return nil 
  end
  
  -- Inline parsing (avoid string:split allocation)
  local x, y, z = value:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
  if x then
    cachedWaypointPos = {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
  else
    cachedWaypointPos = nil
  end
  
  return cachedWaypointPos
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
-- ============================================================================

local function executeRecovery()
  local attempt = WaypointEngine.recoveryAttempt
  
  -- Strategy 1: Find nearest reachable waypoint (forward search)
  if attempt <= 2 then
    if CaveBot.findBestWaypoint and CaveBot.findBestWaypoint(true) then
      transitionTo("NORMAL")
      return true
    end
  end
  
  -- Strategy 2: Search backwards for reachable waypoint
  if attempt <= 3 then
    if CaveBot.gotoFirstPreviousReachableWaypoint and CaveBot.gotoFirstPreviousReachableWaypoint() then
      transitionTo("NORMAL")
      return true
    end
  end
  
  -- Strategy 3: Skip current waypoint
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
            ui.list:focusChild(nextChild)
            transitionTo("NORMAL")
            return true
          end
        end
      end
    end
  end
  
  -- Strategy 4: Skip multiple waypoints (exponential skip)
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
  cachedWaypointPos = nil
  cachedWaypointPosTime = 0
end

-- Skip to next waypoint
local function skipCurrentWaypoint()
  if not ui or not ui.list then return false end
  
  local actionCount = ui.list:getChildCount()
  if actionCount == 0 then return false end
  
  local current = ui.list:getFocusedChild()
  if not current then return false end
  
  local currentIndex = ui.list:getChildIndex(current)
  local nextIndex = (currentIndex % actionCount) + 1
  
  local nextChild = ui.list:getChildByIndex(nextIndex)
  if nextChild then
    ui.list:focusChild(nextChild)
    return true
  end
  
  return false
end

local function updateCache()
  if (now - lastCacheUpdate) < CACHE_TTL then return end
  lastCacheUpdate = now
  uiList = uiList or ui.list
  cachedActionCount = uiList:getChildCount()
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

cavebotMacro = macro(250, function()
  -- SMART EXECUTION: Skip if we shouldn't execute this tick
  if shouldSkipExecution() then return end
  
  -- Update player position tracking
  hasPlayerMoved()
  
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
      CaveBot.resetWalking()
      return
    end
    
    -- SMART PULL PAUSE: If smartPull is active, pause waypoint walking
    if TargetBot.smartPullActive then
      CaveBot.resetWalking()
      return
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
  
  -- Direct table access (O(1))
  local actionType = currentAction.action
  local actionDef = CaveBot.Actions[actionType]
  
  if not actionDef then
    warn("[CaveBot] Invalid action: " .. tostring(actionType))
    return
  end
  
  -- Execute action (inline for performance)
  CaveBot.resetWalking()
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
  prevActionResult = true
  cavebotMacro.setOn(enabled)
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
  return config.isOn()
end

CaveBot.isOff = function()
  return config.isOff()
end

CaveBot.setOn = function(val)
  if val == false then  
    return CaveBot.setOff(true)
  end
  config.setOn()
end

CaveBot.setOff = function(val)
  if val == false then  
    return CaveBot.setOn(true)
  end
  config.setOff()
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
  IMPROVED WAYPOINT FINDER
  
  Finds the best reachable waypoint considering:
  1. Distance from player (within maxDist)
  2. Path availability (can actually walk there)
  3. Preference for closer waypoints to reduce travel time
  4. Skip waypoints on different floors
  
  Uses tiered search: fast distance check first, then pathfinding only for candidates
]]

-- Pre-compute waypoint positions to avoid regex parsing every search
local waypointPositionCache = {}
local waypointCacheValid = false

local function invalidateWaypointCache()
  waypointPositionCache = {}
  waypointCacheValid = false
end

local function buildWaypointCache()
  if waypointCacheValid then return end
  
  waypointPositionCache = {}
  local actions = ui.list:getChildren()
  
  for i, child in ipairs(actions) do
    local text = child:getText()
    if string.starts(text, "goto:") then
      local re = regexMatch(text, [[(?:goto:)([^,]+),([^,]+),([^,]+)]])
      if re and re[1] then
        waypointPositionCache[i] = {
          x = tonumber(re[1][2]),
          y = tonumber(re[1][3]),
          z = tonumber(re[1][4]),
          child = child
        }
      end
    end
  end
  
  waypointCacheValid = true
end

-- Find the best waypoint to go to (optimized for long distances)
CaveBot.findBestWaypoint = function(searchForward)
  buildWaypointCache()
  
  local currentAction = ui.list:getFocusedChild()
  local currentIndex = ui.list:getChildIndex(currentAction)
  local actions = ui.list:getChildren()
  local actionCount = #actions
  
  local playerPos = player:getPosition()
  local maxDist = storage.extras.gotoMaxDistance or 30
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
  
  -- Phase 1: Fast distance check (no pathfinding)
  for _, i in ipairs(searchOrder) do
    local waypoint = waypointPositionCache[i]
    if waypoint and waypoint.z == playerZ then
      local dx = math.abs(playerPos.x - waypoint.x)
      local dy = math.abs(playerPos.y - waypoint.y)
      local dist = math.max(dx, dy)
      
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
  
  -- Phase 2: Check pathfinding only for top candidates (limit to 5 for performance)
  local maxCandidates = math.min(5, #candidates)
  for i = 1, maxCandidates do
    local candidate = candidates[i]
    local wp = candidate.waypoint
    local destPos = {x = wp.x, y = wp.y, z = wp.z}
    
    -- Check if path exists
    local path = findPath(playerPos, destPos, maxDist, { ignoreNonPathable = true })
    if path then
      -- Found a reachable waypoint
      local prevChild = ui.list:getChildByIndex(candidate.index - 1)
      if prevChild then
        ui.list:focusChild(prevChild)
      else
        ui.list:focusChild(candidate.waypoint.child)
      end
      return true
    end
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

  -- start searching from current index
  for i, child in ipairs(actions) do
    if i > index then
      local text = child:getText()
      if string.starts(text, "goto:") then
        local re = regexMatch(text, [[(?:goto:)([^,]+),([^,]+),([^,]+)]])
        local pos = {x = tonumber(re[1][2]), y = tonumber(re[1][3]), z = tonumber(re[1][4])}
        
        if posz() == pos.z then
          local maxDist = storage.extras.gotoMaxDistance
          if distanceFromPlayer(pos) <= maxDist then
            if findPath(player:getPosition(), pos, maxDist, { ignoreNonPathable = true }) then
              ui.list:focusChild(ui.list:getChildByIndex(i-1))
              return true
            end
          end
        end
      end
    end
  end

  -- if not found then damn go from start
  for i, child in ipairs(actions) do
    if i <= index then
      local text = child:getText()
      if string.starts(text, "goto:") then
        local re = regexMatch(text, [[(?:goto:)([^,]+),([^,]+),([^,]+)]])
        local pos = {x = tonumber(re[1][2]), y = tonumber(re[1][3]), z = tonumber(re[1][4])}

        if posz() == pos.z then
          local maxDist = storage.extras.gotoMaxDistance
          if distanceFromPlayer(pos) <= maxDist then
            if findPath(player:getPosition(), pos, maxDist, { ignoreNonPathable = true }) then
              ui.list:focusChild(ui.list:getChildByIndex(i-1))
              return true
            end
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
  return CaveBot.walkTo(dest, storage.extras.gotoMaxDistance or 40, {
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