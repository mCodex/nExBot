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
local cachedActions = nil
local cachedCurrentAction = nil
local lastActionCheck = 0
local ACTION_CACHE_TTL = 50  -- Refresh cache every 50ms

cavebotMacro = macro(50, function()
  -- Early return checks first (most common case)
  if TargetBot and TargetBot.isActive() and not TargetBot.isCaveBotActionAllowed() then
    CaveBot.resetWalking()
    return
  end
  
  if CaveBot.doWalking() then
    return
  end
  
  -- Get action count (cached access pattern)
  local actionCount = ui.list:getChildCount()
  if actionCount == 0 then return end
  
  -- Get current action
  local currentAction = ui.list:getFocusedChild()
  if not currentAction then
    currentAction = ui.list:getFirstChild()
    if not currentAction then return end
  end
  
  -- Cache action lookup
  local actionType = currentAction.action
  local action = CaveBot.Actions[actionType]
  
  if not action then
    warn("Invalid cavebot action: " .. tostring(actionType))
    return
  end
  
  local value = currentAction.value
  local retry = false
  
  -- Execute action with error handling
  local status, result = pcall(function()
    CaveBot.resetWalking()
    return action.callback(value, actionRetries, prevActionResult)
  end)
  
  if status then
    if result == "retry" then
      actionRetries = actionRetries + 1
      retry = true
    elseif result == true or result == false then
      actionRetries = 0
      prevActionResult = result
    else
      warn("Invalid return from cavebot action (" .. actionType .. "), should be \"retry\", false or true, is: " .. tostring(result))
    end
  else
    warn("Error while executing cavebot action (" .. actionType .. "):\n" .. result)
  end
  
  if retry then
    return
  end
  
  -- Check if focused child changed during action
  local newFocused = ui.list:getFocusedChild()
  if currentAction ~= newFocused then
    currentAction = newFocused or ui.list:getFirstChild()
    actionRetries = 0
    prevActionResult = true
  end
  
  -- Move to next action
  local currentIndex = ui.list:getChildIndex(currentAction)
  local nextIndex = currentIndex + 1
  if nextIndex > actionCount then
    nextIndex = 1
  end
  
  local nextChild = ui.list:getChildByIndex(nextIndex)
  if nextChild then
    ui.list:focusChild(nextChild)
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

local botConfigName = modules.game_bot.contentsPanel.config:getCurrentOption().text
CaveBot.setCurrentProfile = function(name)
  if not g_resources.fileExists("/bot/"..botConfigName.."/cavebot_configs/"..name..".cfg") then
    return warn("there is no cavebot profile with that name!")
  end
  CaveBot.setOff()
  storage._configs.cavebot_configs.selected = name
  CaveBot.setOn()
end

CaveBot.delay = function(value)
  cavebotMacro.delay = math.max(cavebotMacro.delay or 0, now + value)
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