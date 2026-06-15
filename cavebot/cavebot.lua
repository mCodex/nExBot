local cavebotMacro = nil
local config = nil

local function safeResetWalking()
  if CaveBot and CaveBot.resetWalking then CaveBot.resetWalking() end
end

local configWidget = UI.Config()
local ui = UI.createWidget("CaveBotPanel")

if ui.configWidgetPlaceholder and configWidget then
  local placeholder = ui.configWidgetPlaceholder
  if configWidget.setParent then configWidget:setParent(placeholder) end
  if placeholder.addChild then
    local ok, parent = pcall(function() return configWidget:getParent() end)
    if not ok or parent ~= placeholder then placeholder:addChild(configWidget) end
  end
  if placeholder.moveChildToIndex then placeholder:moveChildToIndex(configWidget, 1) end
end

do
  local parent = ui:getParent()
  if parent then
    if parent.moveChildToIndex then parent:moveChildToIndex(ui, 1)
    elseif parent.insertChild then parent:removeChild(ui); parent:insertChild(1, ui) end
  end
end

ui.list = ui.listPanel.list
CaveBot.actionList = ui.list

if CaveBot.Editor then CaveBot.Editor.setup() end
if CaveBot.Config then CaveBot.Config.setup() end
for extension, callbacks in pairs(CaveBot.Extensions) do
  if callbacks.setup then callbacks.setup() end
end

-- ============================================================================
-- STATE — simplified: no WaypointEngine, no blacklist, no drift detection
-- ============================================================================

local actionRetries = 0
local prevActionResult = true
local uiList = nil

CaveBot.getMaxGotoDistance = function()
  local raw = storage and storage.extras and storage.extras.gotoMaxDistance
  local n = tonumber(raw)
  return (n and n > 0) and n or 50
end

-- Simple walk state: only track "wait until walking finishes"
local delayUntil = 0

CaveBot.delay = function(value)
  delayUntil = math.max(delayUntil, now + value)
end

-- ============================================================================
-- EVENTBUS INTEGRATION — Instant waypoint arrival detection
-- ============================================================================

local currentWaypointTarget = {
  pos = nil, precision = 1, arrived = false, arrivedTime = 0
}

local function isAtWaypoint(playerPos, waypointPos, precision)
  if not playerPos or not waypointPos then return false end
  if playerPos.z ~= waypointPos.z then return false end
  local dx = math.abs(playerPos.x - waypointPos.x)
  local dy = math.abs(playerPos.y - waypointPos.y)
  return dx <= precision and dy <= precision
end

CaveBot.setCurrentWaypointTarget = function(pos, precision)
  currentWaypointTarget.pos = pos
  currentWaypointTarget.precision = precision or 1
  currentWaypointTarget.arrived = false
  currentWaypointTarget.arrivedTime = 0
end

CaveBot.hasArrivedAtWaypoint = function()
  return currentWaypointTarget.arrived
end

CaveBot.clearWaypointTarget = function()
  currentWaypointTarget.pos = nil
  currentWaypointTarget.arrived = false
end

if EventBus then
  EventBus.on("player:move", function(newPos, oldPos)
    if not currentWaypointTarget.pos then return end
    if not newPos then return end
    if isAtWaypoint(newPos, currentWaypointTarget.pos, currentWaypointTarget.precision) then
      currentWaypointTarget.arrived = true
      currentWaypointTarget.arrivedTime = now
      pcall(function() EventBus.emit("cavebot:waypoint_arrived", currentWaypointTarget.pos) end)
    end
  end, 5)
end

-- ============================================================================
-- WAYPOINT CACHE
-- ============================================================================

local waypointPositionCache = {}
local waypointCacheValid = false
local startupWaypointFound = false
local startupCheckTime = nil

local function parseWaypointPosition(text)
  if not text then return nil end
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
  local re = regexMatch(text, [[(?:\w+:)([^,]+),([^,]+),([^,]+)]])
  if not re or not re[1] then return nil end
  local x = tonumber(re[1][2])
  local y = tonumber(re[1][3])
  local z = tonumber(re[1][4])
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z }
end

local invalidateWaypointCache
local buildWaypointCache

invalidateWaypointCache = function()
  waypointPositionCache = {}
  waypointCacheValid = false
end

CaveBot.invalidateWaypointCache = invalidateWaypointCache

buildWaypointCache = function()
  if waypointCacheValid then return end
  waypointPositionCache = {}
  local actions = ui.list:getChildren()
  for i, child in ipairs(actions) do
    local pos = parseWaypointPosition(child:getText())
    if pos then
      waypointPositionCache[i] = {
        x = pos.x, y = pos.y, z = pos.z,
        child = child, index = i, isGoto = (child.action == "goto"),
      }
    end
  end
  waypointCacheValid = true
end

CaveBot.getRouteGraph = function()
  buildWaypointCache()
  return nil
end

CaveBot.getRouteValidationReport = function()
  buildWaypointCache()
  return nil
end

-- ============================================================================
-- STARTUP + RECOVERY — pathfinding-based nearest waypoint
-- ============================================================================

local function checkStartupWaypoint()
  if startupWaypointFound then return end
  if not startupCheckTime then startupCheckTime = now; return end
  -- Reduced from 500ms to 100ms for faster startup
  if now - startupCheckTime < 100 then return end
  local playerPos = player:getPosition()
  if not playerPos then return end
  buildWaypointCache()
  
  -- Try pathfinding-based nearest reachable first
  local best = WaypointNavigator.findNearestReachable(playerPos, waypointPositionCache, CaveBot.getMaxGotoDistance())
  
  -- Fallback: if pathfinding fails, use Chebyshev distance only (no pathfinding)
  if not best then
    best = WaypointNavigator.findBestOnFloor(playerPos, waypointPositionCache, CaveBot.getMaxGotoDistance())
    if best then
      print("[CaveBot] Startup: Using fallback waypoint selection (no pathfinding)")
    end
  end
  
  if best then
    ui.list:focusChild(best.wp.child)
    actionRetries = 0
    print("[CaveBot] Startup: Focused waypoint " .. best.idx .. " at " .. best.wp.x .. "," .. best.wp.y .. "," .. best.wp.z)
  else
    print("[CaveBot] Startup: No reachable waypoint found on current floor")
  end
  startupWaypointFound = true
end

local function resetStartupCheck()
  startupWaypointFound = false
  startupCheckTime = nil
end

-- Real recovery state (replaces stub)
local recovering = false
local positionHistory = {}

-- Adaptive tick rate state
local currentMacroInterval = 100
local MIN_MACRO_INTERVAL = 50    -- Walking: responsive
local MAX_MACRO_INTERVAL = 300   -- Idle: lower CPU
local IDLE_MACRO_INTERVAL = 200  -- Waiting/delayed


-- TargetBot integration (uses EventBus events instead of polling)

-- Adjust macro interval based on current state
local function adjustMacroInterval(isWalking, isDelayed, isRecovering)
  local newInterval
  if isWalking then
    newInterval = MIN_MACRO_INTERVAL
  elseif isDelayed or isRecovering then
    newInterval = IDLE_MACRO_INTERVAL
  else
    newInterval = MAX_MACRO_INTERVAL
  end
  
  if newInterval ~= currentMacroInterval then
    currentMacroInterval = newInterval
    if cavebotMacro and cavebotMacro.setInterval then
      cavebotMacro.setInterval(newInterval)
    end
  end
end

-- ============================================================================
-- MACRO LOOP — simplified: linear execution, stuck counter, no state machine
-- ============================================================================

cavebotMacro = macro(100, function()
  local playerPos = player and player:getPosition()

  -- Track position history for stuck detection
  if playerPos then
    positionHistory[#positionHistory + 1] = { x = playerPos.x, y = playerPos.y, z = playerPos.z }
    if #positionHistory > 20 then table.remove(positionHistory, 1) end
  end

  -- Skip if delay active
  local isDelayed = now < delayUntil
  if isDelayed then
    adjustMacroInterval(false, true, recovering)
    return
  end

  -- Skip if player walking (let walk finish)
  local isWalking = player and player:isWalking()
  if isWalking then
    adjustMacroInterval(true, false, recovering)
    if currentWaypointTarget.arrived then
      currentWaypointTarget.arrived = false
      if recovering then recovering = false end
    end
    return
  end

  -- If recovering, check if we arrived
  if recovering then
    adjustMacroInterval(false, false, true)
    if currentWaypointTarget.arrived then
      currentWaypointTarget.arrived = false
      recovering = false
      actionRetries = 0
    end
    return
  end

  adjustMacroInterval(false, false, false)

  -- Check TargetBot allows CaveBot action (using EventBus-driven state)
  if TargetBot and TargetBot.isActive and TargetBot.isActive() then
    if TargetBot.isCaveBotActionAllowed and not TargetBot.isCaveBotActionAllowed() then
      safeResetWalking(); return
    end
    if TargetBot.smartPullActive then safeResetWalking(); return end
  end

  -- Startup detection
  checkStartupWaypoint()

  uiList = uiList or ui.list
  local actionCount = uiList:getChildCount()
  if actionCount == 0 then return end

  local currentAction = uiList:getFocusedChild() or uiList:getFirstChild()
  if not currentAction then return end

  local actionType = currentAction.action
  local actionDef = CaveBot.Actions[actionType]
  if not actionDef then
    warn("[CaveBot] Invalid action: " .. tostring(actionType))
    return
  end

  local result, instantFail = actionDef.callback(currentAction.value, actionRetries, prevActionResult)

  if result == "walking" then
    currentWaypointTarget.arrived = false
    return
  end

  if result == "retry" then
    actionRetries = actionRetries + 1
    local retryLimit = (actionType == "goto") and 30 or 8
    if actionRetries > retryLimit then
      -- Try recovery before force-advancing
      local stuck, reason = WaypointNavigator.stuckDetected(positionHistory, 1)
      if stuck then
        CaveBot.requestWaypointRecovery(reason)
        if recovering then positionHistory = {}; return end
      end
      actionRetries = 0
      local curIdx = uiList:getChildIndex(currentAction)
      local nxtIdx = (curIdx % actionCount) + 1
      local nextChild = uiList:getChildByIndex(nxtIdx)
      if nextChild then uiList:focusChild(nextChild) end
    end
    return
  end

  if result == true then
    prevActionResult = true
  elseif result == false then
    prevActionResult = false
    if instantFail and actionType == "goto" then
      actionRetries = 0
      local curIdx = uiList:getChildIndex(currentAction)
      if curIdx then
        local nxtIdx = (curIdx % actionCount) + 1
        local nextChild = uiList:getChildByIndex(nxtIdx)
        if nextChild then uiList:focusChild(nextChild) end
      end
      return
    end
    if actionType ~= "goto" then
      actionRetries = 0
      local curIdx = uiList:getChildIndex(currentAction)
      local nxtIdx = (curIdx % actionCount) + 1
      local nextChild = uiList:getChildByIndex(nxtIdx)
      if nextChild then uiList:focusChild(nextChild) end
      return
    end
    actionRetries = 0
    return
  end

  -- Advance to next action
  actionRetries = 0
  if result == true or result == false then
    prevActionResult = result
  end

  local curIdx = uiList:getChildIndex(currentAction)
  local nxtIdx = (curIdx % actionCount) + 1
  local nextChild = uiList:getChildByIndex(nxtIdx)
  if nextChild then uiList:focusChild(nextChild) end
end)

-- ============================================================================
-- CONFIG
-- ============================================================================

local lastConfig = ""
config = Config.setup("cavebot_configs", configWidget, "cfg", function(name, enabled, data)
  if enabled and CaveBot.Recorder.isOn() then
    CaveBot.Recorder.disable()
    CaveBot.setOff()
    return
  end

  if name and name ~= "" then
    if setCharacterProfile then setCharacterProfile("cavebotProfile", name) end
    if UnifiedStorage and UnifiedStorage.set then
      UnifiedStorage.set("cavebot.selectedConfig", name)
      UnifiedStorage.set("cavebot.enabled", enabled)
    end
    if EventBus and EventBus.emit then
      pcall(function() EventBus.emit("cavebot:configChanged", name) end)
    end
  end

  local currentActionIndex = ui.list:getChildIndex(ui.list:getFocusedChild())
  ui.list:destroyChildren()
  if not data then return cavebotMacro.setOff() end

  local cavebotConfig = nil
  for k, v in ipairs(data) do
    if type(v) == "table" and #v == 2 then
      if v[1] == "config" then
        local status, result = pcall(function() return json.decode(v[2]) end)
        if not status then warn("warn while parsing CaveBot extensions from config:\n" .. result)
        else cavebotConfig = result end
      elseif v[1] == "extensions" then
        local status, result = pcall(function() return json.decode(v[2]) end)
        if not status then warn("warn while parsing CaveBot extensions from config:\n" .. result)
        else
          for extension, callbacks in pairs(CaveBot.Extensions) do
            if callbacks.onConfigChange then callbacks.onConfigChange(name, enabled, result[extension]) end
          end
        end
      else
        CaveBot.addAction(v[1], v[2])
      end
    end
  end

  CaveBot.Config.onConfigChange(name, enabled, cavebotConfig)

  actionRetries = 0
  if CaveBot.fullResetWalking then CaveBot.fullResetWalking() else safeResetWalking() end
  invalidateWaypointCache()
  resetStartupCheck()
  prevActionResult = true

  local finalEnabled = enabled
  if not CaveBot._initialized then
    CaveBot._initialized = true
    if storage.cavebotEnabled ~= nil then finalEnabled = storage.cavebotEnabled end
  else
    storage.cavebotEnabled = enabled
  end

  cavebotMacro.setOn(finalEnabled)
  delayUntil = 0
  if lastConfig == name then
    ui.list:focusChild(ui.list:getChildByIndex(currentActionIndex))
  end
  lastConfig = name
end)

-- UI callbacks
ui.showEditor.onClick = function()
  if not CaveBot.Editor then return end
  if ui.showEditor:isOn() then CaveBot.Editor.hide(); ui.showEditor:setOn(false)
  else CaveBot.Editor.show(); ui.showEditor:setOn(true) end
end

ui.showConfig.onClick = function()
  if not CaveBot.Config then return end
  if ui.showConfig:isOn() then CaveBot.Config.hide(); ui.showConfig:setOn(false)
  else CaveBot.Config.show(); ui.showConfig:setOn(true) end
end

-- Public API
CaveBot.isOn = function() return config and config.isOn and config.isOn() or false end
CaveBot.isOff = function() return not CaveBot.isOn() end

CaveBot.setOn = function(val)
  if val == false then return CaveBot.setOff(true) end
  if UnifiedStorage and UnifiedStorage.set then UnifiedStorage.set("cavebot.enabled", true) end
  config.setOn()
end

CaveBot.setOff = function(val)
  if val == false then return CaveBot.setOn(true) end
  if UnifiedStorage and UnifiedStorage.set then UnifiedStorage.set("cavebot.enabled", false) end
  config.setOff()
end

CaveBot.getCurrentProfile = function()
  if UnifiedStorage and UnifiedStorage.get then
    local stored = UnifiedStorage.get("cavebot.selectedConfig")
    if stored and stored ~= "" then return stored end
  end
  return storage._configs.cavebot_configs.selected
end

CaveBot.lastReachedLabel = function() return nExBot.lastLabel end

CaveBot.getWaypointStats = function()
  return { state = recovering and "RECOVERING" or "NORMAL", failureCount = 0, isRecovering = recovering, navV2State = nil }
end

CaveBot.isRecovering = function() return recovering end

CaveBot.findBestWaypoint = function()
  local playerPos = player:getPosition()
  if not playerPos then return false end
  buildWaypointCache()
  local best = WaypointNavigator.findNearestReachable(playerPos, waypointPositionCache, CaveBot.getMaxGotoDistance())
  if best then
    ui.list:focusChild(best.wp.child)
    actionRetries = 0
    return true
  end
  local fallback = WaypointNavigator.findBestOnFloor(playerPos, waypointPositionCache, CaveBot.getMaxGotoDistance())
  if fallback then
    ui.list:focusChild(fallback.wp.child)
    actionRetries = 0
    return true
  end
  return false
end

CaveBot.gotoNextWaypointInRange = CaveBot.findBestWaypoint

local waypointRecovery = { lastRequest = 0, cooldown = 1000, attempts = 0 }

CaveBot.requestWaypointRecovery = function(reason)
  local nowt = now or (os.time() * 1000)
  if (nowt - waypointRecovery.lastRequest) < waypointRecovery.cooldown then return false end

  -- Increase cooldown on repeated failures
  waypointRecovery.attempts = waypointRecovery.attempts + 1
  waypointRecovery.cooldown = math.min(1000 * waypointRecovery.attempts, 5000)
  waypointRecovery.lastRequest = nowt

  if reason ~= "no_progress" then
    print("[CaveBot] Recovery: " .. tostring(reason) .. " (attempt " .. waypointRecovery.attempts .. ")")
  end

  local ok = CaveBot.findBestWaypoint()
  if ok then
    local focusedChild = ui.list:getFocusedChild()
    if focusedChild and focusedChild.action == "goto" then
      local actionDef = CaveBot.Actions["goto"]
      if actionDef and actionDef.callback then
        actionDef.callback(focusedChild.value, 0, true)
      end
    end
    recovering = true
    waypointRecovery.attempts = 0
    waypointRecovery.cooldown = 1000
  end
  return ok
end

CaveBot.gotoFirstPreviousReachableWaypoint = function()
  return CaveBot.findBestWaypoint()
end

CaveBot.getFirstWaypointBeforeLabel = function(label)
  label = "label:"..label; label = label:lower()
  local actions = ui.list:getChildren()
  local index
  local maxDist = CaveBot.getMaxGotoDistance()
  local halfDist = maxDist / 2
  local extendedDist = maxDist * 2
  local playerPos = player:getPosition()
  for i, child in pairs(actions) do
    local name = child:getText():lower()
    if name == label then index = i; break end
  end
  if not index then return false end
  local extendedCandidates = {}
  for i = 1, #actions do
    if index - i < 1 then break end
    local child = ui.list:getChildByIndex(index - i)
    if child then
      local text = child:getText()
      if string.starts(text, "goto:") then
        local re = regexMatch(text, [[(?:goto:)([^,]+),([^,]+),([^,]+)]])
        if re and re[1] then
          local pos = {x = tonumber(re[1][2]), y = tonumber(re[1][3]), z = tonumber(re[1][4])}
          if posz() == pos.z then
            local dist = distanceFromPlayer(pos)
            if dist <= halfDist then
              local path = findPath(playerPos, pos, halfDist, { ignoreNonPathable = true })
              if path then return ui.list:focusChild(child) end
            elseif dist <= extendedDist then
              table.insert(extendedCandidates, {child = child, pos = pos, dist = dist})
            end
          end
        end
      end
    end
  end
  if #extendedCandidates > 0 then
    table.sort(extendedCandidates, function(a, b) return a.dist < b.dist end)
    for _, candidate in ipairs(extendedCandidates) do
      local path = findPath(playerPos, candidate.pos, extendedDist, { ignoreNonPathable = true })
      if path then return ui.list:focusChild(candidate.child) end
    end
  end
  return false
end

CaveBot.getPreviousLabel = function()
  local actions = ui.list:getChildren()
  if #actions == 0 then return false end
  local currentAction = ui.list:getFocusedChild()
  if not currentAction or currentAction == ui.list:getFirstChild() then return false end
  local index = ui.list:getChildIndex(currentAction)
  if not index then return false end
  for i = 1, #actions do
    if index - i < 1 then return false end
    local child = ui.list:getChildByIndex(index - i)
    if child and child.action == "label" then return child.value end
  end
end

CaveBot.getNextLabel = function()
  local actions = ui.list:getChildren()
  if #actions == 0 then return false end
  local currentAction = ui.list:getFocusedChild() or ui.list:getFirstChild()
  local index = ui.list:getChildIndex(currentAction)
  if not index then return false end
  for i = 1, #actions do
    if index + i > #actions then return false end
    local child = ui.list:getChildByIndex(index + i)
    if child and child.action == "label" then return child.value end
  end
end

local botConfigName = BotConfigName or modules.game_bot.contentsPanel.config:getCurrentOption().text

CaveBot.setCurrentProfile = function(name)
  if not g_resources.fileExists("/bot/"..botConfigName.."/cavebot_configs/"..name..".cfg") then
    return warn("there is no cavebot profile with that name!")
  end
  CaveBot.setOff()
  storage._configs.cavebot_configs.selected = name
  if UnifiedStorage and UnifiedStorage.set then UnifiedStorage.set("cavebot.selectedConfig", name) end
  if setCharacterProfile then setCharacterProfile("cavebotProfile", name) end
  if EventBus and EventBus.emit then pcall(function() EventBus.emit("cavebot:configChanged", name) end) end
  CaveBot.setOn()
end

CaveBot.GoTo = function(dest, precision)
  if not dest then return false end
  precision = precision or 1
  local playerPos = player:getPosition()
  if not playerPos then return false end
  local distX = math.abs(dest.x - playerPos.x)
  local distY = math.abs(dest.y - playerPos.y)
  if distX <= precision and distY <= precision and dest.z == playerPos.z then return true end
  if dest.z ~= playerPos.z then return false end
  return CaveBot.walkTo(dest, CaveBot.getMaxGotoDistance(), { precision = precision, ignoreNonPathable = true })
end

CaveBot.gotoLabel = function(label)
  label = label:lower()
  for index, child in ipairs(ui.list:getChildren()) do
    if child.action == "label" and child.value:lower() == label then
      ui.list:focusChild(child); return true
    end
  end
  return false
end

CaveBot.save = function()
  local data = {}
  for index, child in ipairs(ui.list:getChildren()) do
    table.insert(data, {child.action, child.value})
  end
  if CaveBot.Config then table.insert(data, {"config", json.encode(CaveBot.Config.save())}) end
  local extension_data = {}
  for extension, callbacks in pairs(CaveBot.Extensions) do
    if callbacks.onSave then
      local ext_data = callbacks.onSave()
      if type(ext_data) == "table" then extension_data[extension] = ext_data end
    end
  end
  table.insert(data, {"extensions", json.encode(extension_data, 2)})
  config.save(data)
end

CaveBotList = function()
  return ui.list
end

-- ============================================================================
-- EVENTBUS INTEGRATION — Respond to targetbot events without polling
-- ============================================================================

if EventBus and EventBus.on then
  -- When targetbot allows cavebot to act, reduce delay to act quickly
  EventBus.on("targetbot:cavebot_allowed", function()
    delayUntil = now  -- Clear any delay so cavebot acts immediately
  end, 1)

  -- When player moves, check if we need to re-evaluate waypoints
  EventBus.on("player:move", function(newPos, oldPos)
    if not CaveBot or CaveBot.isOff() then return end
    oldPos = oldPos or {}
    if newPos and oldPos.x then
      local dx = math.abs(newPos.x - oldPos.x)
      local dy = math.abs(newPos.y - oldPos.y)
      local dz = oldPos.z and newPos.z ~= oldPos.z
      -- Clear pending FC state on Z change or teleport
      if dz then
        CaveBot._pendingFC = nil
      end
      -- Only invalidate cache on significant movement (>10 tiles)
      if dx > 10 or dy > 10 then
        invalidateWaypointCache()
      end
    end
  end, 50)

  -- When combat ends, reset recovery state
  EventBus.on("targetbot/combat_end", function()
    if recovering then
      recovering = false
      actionRetries = 0
    end
  end, 50)
end
