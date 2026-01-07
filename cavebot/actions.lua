CaveBot.Actions = {}
nExBot.lastLabel = ""
local oldTibia = g_game.getClientVersion() < 960
local nextTile = nil

local noPath = 0

-- Pre-computed direction lookup table for optimal performance
local DIR_MOD_LOOKUP = {
    [0] = { x = 0, y = -1 },   -- North
    [1] = { x = 1, y = 0 },    -- East
    [2] = { x = 0, y = 1 },    -- South
    [3] = { x = -1, y = 0 },   -- West
    [4] = { x = 1, y = -1 },   -- NorthEast
    [5] = { x = 1, y = 1 },    -- SouthEast
    [6] = { x = -1, y = 1 },   -- SouthWest
    [7] = { x = -1, y = -1 }   -- NorthWest
}

-- antistuck f() - optimized with lookup table
local nextPos = nil -- creature
local nextPosF = nil -- furniture
local function modPos(dir)
    local mod = DIR_MOD_LOOKUP[dir]
    if mod then
        return { mod.x, mod.y }
    end
    return { 0, 0 }
end

-- stack-covered antystuck, in & out pz - optimized with early returns
local lastMoved = now - 200
onTextMessage(function(mode, text)
  if text ~= 'There is not enough room.' then return end
  if not CaveBot or not CaveBot.isOff or CaveBot.isOff() then return end

  local playerPos = pos()
  local tiles = getNearTiles(playerPos)
  local inPz = isInPz()

  for i, tile in ipairs(tiles) do
    local itemCount = #tile:getItems()
    if not tile:hasCreature() and tile:isWalkable() and itemCount > 9 then
      local topThing = tile:getTopThing()
      if not inPz then
        return useWith(3197, topThing) -- disintegrate
      else
        if now < lastMoved + 200 then return end -- delay to prevent clogging
        local nearTiles = getNearTiles(tile:getPosition())
        for j, nearTile in ipairs(nearTiles) do
          local tpos = nearTile:getPosition()
          if playerPos.x ~= tpos.x or playerPos.y ~= tpos.y or playerPos.z ~= tpos.z then
            if nearTile:isWalkable() then
              lastMoved = now
              return g_game.move(topThing, tpos) -- move item
            end
          end
        end
      end
    end
  end
end)

-- Pre-built lookup set for O(1) furniture ignore check
local furnitureIgnoreSet = { [2986] = true }
local function breakFurniture(destPos)
  if isInPz() then return false end
  
  local candidate = { thing = nil, dist = 100 }
  local playerPos = player:getPosition()
  local playerZ = playerPos.z
  local tiles = g_map.getTiles(playerZ)
  
  for i, tile in ipairs(tiles) do
    local topThing = tile:getTopThing()
    if topThing then
      local thingId = topThing:getId()
      local isWg = thingId == 2130
      local isItem = topThing:isItem()
      
      if isWg or (not furnitureIgnoreSet[thingId] and isItem) then
        local walkable = tile:isWalkable()
        local moveable = not topThing:isNotMoveable()
        
        if isWg or (not walkable and moveable) then
          local tpos = tile:getPosition()
          local path = findPath(playerPos, tpos, 7, { ignoreNonPathable = true, precision = 1 })
          
          if path then
            local distance = getDistanceBetween(destPos, tpos)
            if distance < candidate.dist then
              candidate.thing = topThing
              candidate.dist = distance
            end
          end
        end
      end
    end
  end

  if candidate.thing then
    useWith(3197, candidate.thing)
    return true
  end
  
  return false
end

local function pushPlayer(creature)
  local cpos = creature:getPosition()
  local tiles = getNearTiles(cpos)

  for i, tile in ipairs(tiles) do
    local pos = tile:getPosition()
    local minimapColor = g_map.getMinimapColor(pos)
    local stairs = (minimapColor >= 210 and minimapColor <= 213)

    if not stairs and tile:isWalkable() then
      g_game.move(creature, pos)
    end
  end

end

local function pathfinder()
  if not storage.extras.pathfinding then return end
  if noPath < 10 then return end

  if not CaveBot or not CaveBot.gotoNextWaypointInRange or not CaveBot.gotoNextWaypointInRange() then
    if getConfigFromName and getConfigFromName() then
      local profile = CaveBot and CaveBot.getCurrentProfile and CaveBot.getCurrentProfile() or nil
      local config = getConfigFromName()
      local newProfile = profile == '#Unibase' and config or '#Unibase'
      
      if CaveBot and CaveBot.setCurrentProfile then
        CaveBot.setCurrentProfile(newProfile)
      end
    end
  end
  noPath = 0
  return true
end

-- it adds an action widget to list
CaveBot.addAction = function(action, value, focus)
  action = action:lower()
  local raction = CaveBot.Actions[action]
  if not raction then
    return warn("Invalid cavebot action: " .. action)
  end
  if type(value) == 'number' then
    value = tostring(value)
  end
  local widget = UI.createWidget("CaveBotAction", CaveBot.actionList)
  if not widget then return end
  widget:setText(action .. ":" .. value:split("\n")[1])
  widget.action = action
  widget.value = value
  if raction.color then
    widget:setColor(raction.color)
  end
  widget.onDoubleClick = function(cwidget) -- edit on double click
    if CaveBot.Editor then
      schedule(20, function() -- schedule to have correct focus
        CaveBot.Editor.edit(cwidget.action, cwidget.value, function(action, value)
          CaveBot.editAction(cwidget, action, value)
          CaveBot.save()
        end)
      end)
    end
  end
  if focus then
    widget:focus()
    CaveBot.actionList:ensureChildVisible(widget)
  end
  return widget
end

-- it updates existing widget, you should call CaveBot.save() later
CaveBot.editAction = function(widget, action, value)
  action = action:lower()
  local raction = CaveBot.Actions[action]
  if not raction then
    return warn("Invalid cavebot action: " .. action)
  end
  
  if not widget.action or not widget.value then
    return warn("Invalid cavebot action widget, has missing action or value")  
  end
  
  widget:setText(action .. ":" .. value:split("\n")[1])
  widget.action = action
  widget.value = value
  if raction.color then
    widget:setColor(raction.color)
  end
  return widget
end

--[[
registerAction:
action - string, color - string, callback = function(value, retries, prev)
value is a string value of action, retries is number which will grow by 1 if return is "retry"
prev is a true when previuos action was executed succesfully, false otherwise
it must return true if executed correctly, false otherwise
it can also return string "retry", then the function will be called again in 20 ms
]]--
CaveBot.registerAction = function(action, color, callback) 
  action = action:lower()
  if CaveBot.Actions[action] then
    return warn("Duplicated acction: " .. action)
  end
  CaveBot.Actions[action] = {
    color=color,
    callback=callback
  }
end

CaveBot.registerAction("label", "yellow", function(value, retries, prev)
  nExBot.lastLabel = value
  
  -- SmartHunt: Track waypoint entry for route optimization
  if nExBot.SmartHunt and nExBot.SmartHunt.Routes then
    nExBot.SmartHunt.Routes.enterWaypoint(value)
  end
  
  return true
end)

CaveBot.registerAction("gotolabel", "#FFFF55", function(value, retries, prev)
  return CaveBot.gotoLabel(value) 
end)

CaveBot.registerAction("delay", "#AAAAAA", function(value, retries, prev)
  if retries == 0 then
    local data = string.split(value, ",")
    local val = tonumber(data[1]:trim())
    local random
    local final


    if #data == 2 then
      random = tonumber(data[2]:trim())
    end

    if random then
      local diff = (val/100) * random
      local min = val - diff
      local max = val + diff
      final = math.random(min, max)
    end
    final = final or val

    CaveBot.delay(final) 
    return "retry"
  end
  return true
end)

CaveBot.registerAction("follow", "#FF8400", function(value, retries, prev)
  local c = SafeCall.getCreatureByName(value)
  if not c then
    print("CaveBot[follow]: can't find creature to follow")
    return false
  end
  local cpos = c:getPosition()
  local pos = pos()
  if getDistanceBetween(cpos, pos) < 2 then
    g_game.cancelFollow()
    return true
  else
    SafeCall.global("follow", c)
    delay(200)
    return "retry"
  end
end)

CaveBot.registerAction("function", "red", function(value, retries, prev)
  local prefix = "local retries = " .. retries .. "\nlocal prev = " .. tostring(prev) .. "\nlocal delay = CaveBot.delay\nlocal gotoLabel = CaveBot.gotoLabel\n"
  prefix = prefix .. "local macro = function() warn('Macros inside cavebot functions are not allowed') end\n"
  for extension, callbacks in pairs(CaveBot.Extensions) do
    prefix = prefix .. "local " .. extension .. " = CaveBot.Extensions." .. extension .. "\n"
  end
  local status, result = pcall(function() 
    return assert(load(prefix .. value, "cavebot_function"))()
  end)
  if not status then
    warn("warn in cavebot function:\n" .. result)
    return false
  end  
  return result
end)

--[[
  ============================================
  OPTIMIZED GOTO ACTION - Minimal Pathfinding
  ============================================
  
  Key optimizations:
  1. Early exits before ANY pathfinding
  2. Single pathfinding call when possible
  3. Let walkTo handle the complexity
  4. Reduced retry overhead
  
  The walkTo function now handles path caching internally.
]]

-- Walk strategy enum
local WALK_STRATEGY = {
  DIRECT = 1,
  ATTACK_BLOCKER = 2,
  FAILED = 3
}

-- Direction offset lookup
local DIR_OFFSET = {
  [0] = { x = 0, y = -1 },   -- North
  [1] = { x = 1, y = 0 },    -- East
  [2] = { x = 0, y = 1 },    -- South
  [3] = { x = -1, y = 0 },   -- West
  [4] = { x = 1, y = -1 },   -- NorthEast
  [5] = { x = 1, y = 1 },    -- SouthEast
  [6] = { x = -1, y = 1 },   -- SouthWest
  [7] = { x = -1, y = -1 }   -- NorthWest
}

-- Check for monsters within radius around a position (optimized)
-- Uses early exits and avoids redundant tile lookups
local function hasMonstersInRadius(centerPos, radius)
  if not centerPos or not radius then return false end
  local z = centerPos.z
  local cx, cy = centerPos.x, centerPos.y
  
  -- Spiral search from center for faster discovery
  for r = 0, radius do
    for dx = -r, r do
      for dy = -r, r do
        -- Only check tiles on the ring (spiral pattern)
        if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
          local tile = g_map.getTile({x = cx + dx, y = cy + dy, z = z})
          if tile and tile:hasCreature() then
            local creatures = tile:getCreatures()
            for i = 1, #creatures do
              local c = creatures[i]
              if c and c:isMonster() then
                local hp = c:getHealthPercent()
                if not hp or hp > 0 then
                  return true
                end
              end
            end
          end
        end
      end
    end
  end
  return false
end

-- Check if path is blocked by attackable monster
local function getBlockingMonster(playerPos, destPos, maxDist)
  -- Only check if we're close to destination
  local dist = math.abs(destPos.x - playerPos.x) + math.abs(destPos.y - playerPos.y)
  if dist > 5 then return nil end
  
  -- Try to find path ignoring creatures
  local path = findPath(playerPos, destPos, maxDist, {
    ignoreNonPathable = true,
    ignoreCreatures = true,
    precision = 1
  })
  
  if not path or #path == 0 then return nil end
  
  -- Check first step for blocking monster
  local dir = path[1]
  local offset = DIR_OFFSET[dir]
  if not offset then return nil end
  
  local checkPos = {
    x = playerPos.x + offset.x,
    y = playerPos.y + offset.y,
    z = playerPos.z
  }
  
  local tile = g_map.getTile(checkPos)
  if not tile or not tile:hasCreature() then return nil end
  
  local creatures = tile:getCreatures()
  for _, creature in ipairs(creatures) do
    if creature:isMonster() then
      local hp = creature:getHealthPercent()
      if hp and hp > 0 and (oldTibia or creature:getType() < 3) then
        return creature
      end
    end
  end
  
  return nil
end

-- ============================================================================
-- EVENT-DRIVEN MONSTER TRACKING (Fast screen monster detection via EventBus)
-- ============================================================================
-- Tracks monsters on screen in real-time via events instead of polling tiles.
-- Provides O(1) check for "are there monsters on screen?" and emits events
-- when the screen is cleared, allowing instant waypoint progression.

local screenMonsters = {}  -- Set of monster IDs currently on screen
local screenMonsterCount = 0
local lastScreenClearTime = 0
local lastMonsterValidation = 0  -- Last time we validated monster list
local VALIDATION_INTERVAL = 2000  -- Validate every 2 seconds to prevent desync

-- Fast O(1) check: are there any alive monsters on screen?
local function hasScreenMonsters()
  return screenMonsterCount > 0
end

-- Get count of monsters on screen
local function getScreenMonsterCount()
  return screenMonsterCount
end

-- Check if a creature is a valid alive monster
local function isAliveMonster(creature)
  if not creature then return false end
  if not creature:isMonster() then return false end
  local hp = creature:getHealthPercent()
  return not hp or hp > 0
end

-- Add monster to tracking
local function trackMonster(creature)
  if not creature then return end
  local id = creature:getId()
  if id and not screenMonsters[id] then
    screenMonsters[id] = true
    screenMonsterCount = screenMonsterCount + 1
  end
end

-- Remove monster from tracking (died or left screen)
local function untrackMonster(creature)
  if not creature then return end
  local id = creature:getId()
  if id and screenMonsters[id] then
    screenMonsters[id] = nil
    screenMonsterCount = screenMonsterCount - 1
    
    -- Emit event when screen is cleared of monsters
    if screenMonsterCount <= 0 then
      screenMonsterCount = 0  -- Safety clamp
      lastScreenClearTime = now or os.clock() * 1000
      if EventBus then
        pcall(function() EventBus.emit("cavebot/screen_cleared") end)
      end
    end
  end
end

-- Rebuild monster list (called on floor change or login)
local function rebuildMonsterTracking()
  screenMonsters = {}
  screenMonsterCount = 0
  
  local playerPos = player and player:getPosition()
  if not playerPos then return end
  
  -- Scan visible tiles for monsters
  local specs = g_map.getSpectators(playerPos, false)
  if specs then
    for _, creature in ipairs(specs) do
      if isAliveMonster(creature) then
        trackMonster(creature)
      end
    end
  end
  lastMonsterValidation = now or (os.clock() * 1000)
end

-- Validate monster tracking against actual state (fixes desync issues)
local function validateMonsterTracking()
  local currentTime = now or (os.clock() * 1000)
  if (currentTime - lastMonsterValidation) < VALIDATION_INTERVAL then
    return  -- Not time to validate yet
  end
  lastMonsterValidation = currentTime
  
  local playerPos = player and player:getPosition()
  if not playerPos then return end
  
  -- Get actual monsters on screen
  local actualMonsters = {}
  local actualCount = 0
  local specs = g_map.getSpectators(playerPos, false)
  if specs then
    for _, creature in ipairs(specs) do
      if isAliveMonster(creature) then
        local id = creature:getId()
        if id then
          actualMonsters[id] = true
          actualCount = actualCount + 1
        end
      end
    end
  end
  
  -- Check for desync: if our count differs significantly, rebuild
  if math.abs(screenMonsterCount - actualCount) > 0 then
    screenMonsters = actualMonsters
    screenMonsterCount = actualCount
    
    -- Emit clear event if we just discovered there are no monsters
    if actualCount == 0 and storage.cavebotScreenCleared ~= true then
      if EventBus then
        pcall(function() EventBus.emit("cavebot/screen_cleared") end)
      end
    end
  end
end

-- Quick ground-truth check: actually scan for monsters (used as fallback)
local function hasActualMonstersOnScreen()
  local playerPos = player and player:getPosition()
  if not playerPos then return false end
  
  local specs = g_map.getSpectators(playerPos, false)
  if specs then
    for _, creature in ipairs(specs) do
      if isAliveMonster(creature) then
        return true
      end
    end
  end
  return false
end

-- Register EventBus handlers for monster tracking
if EventBus then
  -- Monster appeared on screen
  EventBus.on("monster:appear", function(creature)
    if isAliveMonster(creature) then
      trackMonster(creature)
    end
  end, 15)  -- Priority 15 (run before other handlers)
  
  -- Monster left screen or died
  EventBus.on("monster:disappear", function(creature)
    untrackMonster(creature)
  end, 15)
  
  -- Monster health changed (check if died)
  EventBus.on("monster:health", function(creature, percent)
    if percent and percent <= 0 then
      untrackMonster(creature)
    end
  end, 15)
  
  -- Player moved to new floor - rebuild tracking
  EventBus.on("player:move", function(newPos, oldPos)
    if oldPos and newPos and oldPos.z ~= newPos.z then
      -- Floor changed, rebuild monster list
      schedule(100, rebuildMonsterTracking)
    end
  end, 15)
  
  -- Combat state tracking (existing)
  EventBus.on("targetbot/combat_start", function(creature, payload)
    storage.targetbotCombatActive = true
  end, 20)

  EventBus.on("targetbot/combat_end", function()
    storage.targetbotCombatActive = false
  end, 20)

  EventBus.on("targetbot/emergency", function(hpPercent)
    storage.targetbotEmergency = true
  end, 20)

  EventBus.on("targetbot/emergency_cleared", function(hpPercent)
    storage.targetbotEmergency = false
  end, 20)
  
  -- Screen cleared - can be used by other modules
  EventBus.on("cavebot/screen_cleared", function()
    -- Signal that CaveBot can proceed to next waypoint immediately
    storage.cavebotScreenCleared = true
  end, 20)
end

-- Initialize monster tracking on load
schedule(500, rebuildMonsterTracking)

-- ============================================================================
-- EVENT-DRIVEN WAYPOINT ARRIVAL DETECTION
-- ============================================================================
-- Tracks the current target waypoint and instantly detects arrival via player:move event.
-- This eliminates polling delay and makes waypoint progression instant.

local waypointTarget = {
  pos = nil,        -- Target position {x, y, z}
  precision = 1,    -- Precision for arrival check
  value = nil,      -- Waypoint value string (for matching)
  arrived = false   -- Flag: have we arrived?
}

-- Set the current waypoint target (called when processing a goto action)
local function setWaypointTarget(pos, precision, value)
  waypointTarget.pos = pos
  waypointTarget.precision = precision or 1
  waypointTarget.value = value
  waypointTarget.arrived = false
end

-- Check if player is at the target waypoint
local function checkWaypointArrival(playerPos)
  if not waypointTarget.pos or not playerPos then return false end
  if playerPos.z ~= waypointTarget.pos.z then return false end
  
  local distX = math.abs(playerPos.x - waypointTarget.pos.x)
  local distY = math.abs(playerPos.y - waypointTarget.pos.y)
  local precision = waypointTarget.precision or 1
  
  return distX <= precision and distY <= precision
end

-- Clear waypoint target (called when waypoint is completed)
local function clearWaypointTarget()
  waypointTarget.pos = nil
  waypointTarget.value = nil
  waypointTarget.arrived = false
end

-- Register player move event for instant waypoint arrival detection
if EventBus then
  EventBus.on("player:move", function(newPos, oldPos)
    -- Check if we arrived at target waypoint
    if waypointTarget.pos and checkWaypointArrival(newPos) then
      waypointTarget.arrived = true
      -- Emit event for other modules
      pcall(function() EventBus.emit("cavebot/waypoint_arrived", waypointTarget.pos, waypointTarget.value) end)
    end
  end, 10)  -- High priority (10) to run before other handlers
end

-- State tracking for non-blocking waits
local gotoWaitState = {
  monsterWaitStart = 0,
  blockerWaitStart = 0,
  lastWaypointValue = nil
}

-- Maximum wait times (minimal for fast progression)
local MONSTER_WAIT_MAX = 2  -- 2 seconds max waiting for monsters
local BLOCKER_WAIT_MAX = 3  -- 3 seconds max waiting for blocker

CaveBot.registerAction("goto", "green", function(value, retries, prev)
  -- ========== EARLY EXITS ==========
  
  -- Reset wait states when waypoint changes
  if gotoWaitState.lastWaypointValue ~= value then
    gotoWaitState.monsterWaitStart = 0
    gotoWaitState.blockerWaitStart = 0
    gotoWaitState.lastWaypointValue = value
    waypointTarget.arrived = false
  end
  
  -- Skip if walking (let walk complete)
  if player and player:isWalking() then
    return "retry"
  end

  -- Parse position
  local posMatch = regexMatch(value, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+),?\\s*([0-9]?)")
  if not posMatch[1] then
    warn("Invalid cavebot goto value: " .. value)
    return false
  end

  local destPos = {
    x = tonumber(posMatch[1][2]),
    y = tonumber(posMatch[1][3]),
    z = tonumber(posMatch[1][4])
  }
  local precision = tonumber(posMatch[1][5]) or 1
  local playerPos = player:getPosition()
  
  -- EARLY CHECK: Was this exact floor-change waypoint just completed?
  -- This is the most reliable way to prevent re-executing a waypoint we just used
  if CaveBot.wasFloorChangeWaypointCompleted and CaveBot.wasFloorChangeWaypointCompleted(destPos) then
    -- This waypoint was already completed - skip it immediately
    noPath = 0
    return true
  end
  
  -- MULTI-FLOOR WAYPOINT HANDLING
  -- If the waypoint is on a different Z level, determine how to handle it
  if destPos.z ~= playerPos.z then
    local dist2D = math.abs(destPos.x - playerPos.x) + math.abs(destPos.y - playerPos.y)
    local floorDiff = math.abs(destPos.z - playerPos.z)
    
    -- CASE 1: Check if we just completed a floor change TO our current floor
    local recentChange = CaveBot.getRecentFloorChange and CaveBot.getRecentFloorChange()
    if recentChange and recentChange.toZ == playerPos.z then
      -- We recently changed TO this floor
      -- Skip any waypoint that is for a DIFFERENT floor (the one we left)
      if dist2D <= 15 then  -- Increased range - be aggressive about skipping
        noPath = 0
        return true
      end
    end
    
    -- CASE 2: Check if we recently came FROM this floor
    -- If the waypoint is on a floor we just LEFT, skip it
    if recentChange and recentChange.fromZ == destPos.z then
      -- This waypoint is for the floor we just left - definitely skip
      if dist2D <= 15 then
        noPath = 0
        return true
      end
    end
    
    -- CASE 3: We're close horizontally but on different floor
    -- This often happens after using a ladder - waypoint was for the OLD floor
    if dist2D <= 8 and floorDiff <= 2 then
      -- Close in X/Y, small floor difference - likely we just changed floors
      -- Skip this waypoint meant for the other floor
      noPath = 0
      return true
    end
    
    -- CASE 4: Standard floor mismatch - we need to find a path to this floor
    noPath = noPath + 1
    pathfinder()
    return false
  end

  -- Distance check
  local maxDist = storage.extras.gotoMaxDistance or 50
  if (distX + distY) > maxDist then
    noPath = noPath + 1
    pathfinder()
    return false
  end
  
  -- TargetBot emergency check
  if storage.targetbotEmergency then
    return "retry"
  end

  -- Check if destination is floor-change tile
  local minimapColor = g_map.getMinimapColor(destPos)
  local isFloorChange = (minimapColor >= 210 and minimapColor <= 213)
  if not isFloorChange and CaveBot.isFloorChangeTile then
    isFloorChange = CaveBot.isFloorChangeTile(destPos)
  end
  
  -- If destination is floor-change, use precision 0 and allow the floor change
  -- Also mark the intended floor change so we don't reset after using the ladder/stairs
  local expectedFloorAfterChange = nil
  if isFloorChange then 
    precision = 0
    -- Determine expected floor after using this tile
    -- Going up: z decreases, Going down: z increases
    -- Minimap colors: 210=ladder up, 211=rope up, 212=stairs down, 213=hole down
    if minimapColor == 210 or minimapColor == 211 then
      expectedFloorAfterChange = destPos.z - 1  -- Ladder/rope up
    elseif minimapColor == 212 or minimapColor == 213 then
      expectedFloorAfterChange = destPos.z + 1  -- Stairs/hole down
    else
      -- Fallback: check tile for clues, default to up
      expectedFloorAfterChange = destPos.z - 1
    end
    
    -- LOOP PREVENTION: Check if this floor change would create a loop
    if CaveBot.wouldFloorChangeLoop and CaveBot.wouldFloorChangeLoop(expectedFloorAfterChange) then
      -- We would be going back to a floor we just left - likely a loop
      -- Check cooldown before allowing
      if CaveBot.canChangeFloor and not CaveBot.canChangeFloor() then
        -- Still in cooldown - skip this floor change waypoint
        noPath = 0
        return true  -- Move to next waypoint
      end
    end
    
    -- Get current waypoint index to track which waypoint initiated this
    local currentAction = ui and ui.list and ui.list:getFocusedChild()
    local waypointIdx = currentAction and ui.list:getChildIndex(currentAction) or nil
    
    -- CRITICAL: Set intended floor change BEFORE we start walking
    -- This ensures the floor change is marked as intentional before it happens
    if CaveBot.setIntendedFloorChange then
      CaveBot.setIntendedFloorChange(expectedFloorAfterChange, waypointIdx)
    end
  end
  
  -- Already at destination
  if distX <= precision and distY <= precision then
    noPath = 0
    -- If this was a floor-change tile and we're standing on it, wait for floor change
    if isFloorChange then
      -- Ensure intended floor change is set
      if expectedFloorAfterChange and CaveBot.setIntendedFloorChange then
        local currentAction = ui and ui.list and ui.list:getFocusedChild()
        local waypointIdx = currentAction and ui.list:getChildIndex(currentAction) or nil
        CaveBot.setIntendedFloorChange(expectedFloorAfterChange, waypointIdx)
      end
      
      -- Check if we've already changed floors (floor change completed)
      if playerPos.z == expectedFloorAfterChange then
        -- Floor change completed successfully!
        -- Mark this waypoint as completed so we don't re-execute it
        if CaveBot.markFloorChangeWaypointCompleted then
          CaveBot.markFloorChangeWaypointCompleted(destPos)
        end
        noPath = 0
        return true
      end
      
      -- Still on the same floor - wait for floor change to occur
      CaveBot.delay(300)
      return "retry"
    end
    return true
  end

  -- Max retries
  local maxRetries = CaveBot.Config.get("mapClick") and 8 or 40
  if retries >= maxRetries then
    noPath = noPath + 1
    pathfinder()
    return false
  end

  -- ========== WALKING ==========
  
  -- Handle blocking monster (only after a few retries)
  if retries > 3 then
    local blocker = getBlockingMonster(playerPos, destPos, maxDist)
    if blocker then
      local currentTarget = g_game.getAttackingCreature()
      if currentTarget ~= blocker then
        attack(blocker)
      end
      g_game.setChaseMode(1)
      
      -- Quick timeout for blocker
      local clockNow = os.clock()
      if gotoWaitState.blockerWaitStart == 0 then
        gotoWaitState.blockerWaitStart = clockNow
      end
      
      if (clockNow - gotoWaitState.blockerWaitStart) >= BLOCKER_WAIT_MAX then
        gotoWaitState.blockerWaitStart = 0
        -- Fall through to walk with ignoreCreatures
      else
        return "retry"
      end
    else
      gotoWaitState.blockerWaitStart = 0
    end
  end
  
  -- Walk parameters
  local walkParams = {
    ignoreNonPathable = true,
    precision = precision,
    allowFloorChange = isFloorChange
  }
  
  -- Ignore creatures on high retries
  if retries > 5 then
    walkParams.ignoreCreatures = true
  end
  
  -- Attempt to walk
  if CaveBot.walkTo(destPos, maxDist, walkParams) then
    if CaveBot.setWalkingToWaypoint then
      CaveBot.setWalkingToWaypoint(destPos, precision, value)
    end
    noPath = 0
    return "retry"
  end
  
  -- Walk failed
  if retries >= maxRetries - 1 then
    noPath = noPath + 1
    pathfinder()
    return false
  end
  
  return "retry"
end)

CaveBot.registerAction("use", "#FFB272", function(value, retries, prev)
  local pos = regexMatch(value, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)")
  if not pos[1] then
    local itemid = tonumber(value)
    if not itemid then
      warn("Invalid cavebot use action value. It should be (x,y,z) or item id, is: " .. value)
      return false
    end
    use(itemid)
    return true
  end

  pos = {x=tonumber(pos[1][2]), y=tonumber(pos[1][3]), z=tonumber(pos[1][4])}  
  local playerPos = player:getPosition()
  if pos.z ~= playerPos.z then 
    return false -- different floor
  end

  if math.max(math.abs(pos.x-playerPos.x), math.abs(pos.y-playerPos.y)) > 7 then
    return false -- too far way
  end

  local tile = g_map.getTile(pos)
  if not tile then
    return false
  end

  local topThing = tile:getTopUseThing()
  if not topThing then
    return false
  end

  use(topThing)
  CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
  return true
end)

CaveBot.registerAction("usewith", "#EEB292", function(value, retries, prev)
  local pos = regexMatch(value, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)")
  if not pos[1] then
    if not itemid then
      warn("Invalid cavebot usewith action value. It should be (itemid,x,y,z) or item id, is: " .. value)
      return false
    end
    use(itemid)
    return true
  end

  local itemid = tonumber(pos[1][2])
  pos = {x=tonumber(pos[1][3]), y=tonumber(pos[1][4]), z=tonumber(pos[1][5])}  
  local playerPos = player:getPosition()
  if pos.z ~= playerPos.z then 
    return false -- different floor
  end

  if math.max(math.abs(pos.x-playerPos.x), math.abs(pos.y-playerPos.y)) > 7 then
    return false -- too far way
  end

  local tile = g_map.getTile(pos)
  if not tile then
    return false
  end

  local topThing = tile:getTopUseThing()
  if not topThing then
    return false
  end

  usewith(itemid, topThing)
  CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
  return true
end)

CaveBot.registerAction("say", "#FF55FF", function(value, retries, prev)
  say(value)
  return true
end)
CaveBot.registerAction("npcsay", "#FF55FF", function(value, retries, prev)
  NPC.say(value)
  return true
end)