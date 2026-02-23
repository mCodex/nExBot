CaveBot.Actions = {}
nExBot.lastLabel = ""

local getClient = nExBot.Shared.getClient
local getClientVersion = nExBot.Shared.getClientVersion

local oldTibia = getClientVersion() < 960
local nextTile = nil

-- Use canonical direction table from Directions module (DRY: SSoT is constants/directions.lua)
local DIR_MOD_LOOKUP = Directions.DIR_TO_OFFSET

-- Direction-offset helper using Directions module
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
    local hasCreature = tile.hasCreature and tile:hasCreature()
    if not hasCreature and tile:isWalkable() and itemCount > 9 then
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
              local Client = getClient()
              if Client and Client.move then
                return Client.move(topThing, tpos)
              else
                return g_game.move(topThing, tpos) -- move item
              end
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
  local Client = getClient()
  
  -- Scan only tiles in a radius around player and destination instead of entire floor
  local scannedSet = {}
  local tilesToCheck = {}
  
  local function addTilesAround(centerPos, radius)
    for dx = -radius, radius do
      for dy = -radius, radius do
        local checkPos = {x = centerPos.x + dx, y = centerPos.y + dy, z = playerZ}
        local key = checkPos.x .. "," .. checkPos.y
        if not scannedSet[key] then
          scannedSet[key] = true
          local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile(checkPos))
          if tile then tilesToCheck[#tilesToCheck+1] = tile end
        end
      end
    end
  end
  
  -- Check around player (walking range) and around destination
  addTilesAround(playerPos, 7)
  if destPos then addTilesAround(destPos, 3) end
  
  for i, tile in ipairs(tilesToCheck) do
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
  local Client = getClient()

  for i, tile in ipairs(tiles) do
    local pos = tile:getPosition()
    local minimapColor = (Client and Client.getMinimapColor) and Client.getMinimapColor(pos) or (g_map and g_map.getMinimapColor(pos)) or 0
    local stairs = (minimapColor >= 210 and minimapColor <= 213)

    if not stairs and tile:isWalkable() then
      if Client and Client.move then
        Client.move(creature, pos)
      else
        g_game.move(creature, pos)
      end
    end
  end

end

-- Recovery is handled exclusively by WaypointEngine (SRP: single authority).
-- The old pathfinder() function was removed because it competed with
-- WaypointEngine by changing focus before stuck detection could trigger,
-- resetting actionRetries and preventing smart recovery strategies.

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
  widget:setText(action .. ":" .. value:split("\n")[1])
  widget.action = action
  widget.value = value
  if raction.color then
    widget:setColor(raction.color)
  end
  -- Invalidate waypoint cache when editor adds a new action
  if CaveBot.invalidateWaypointCache then
    CaveBot.invalidateWaypointCache()
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
  local c = getCreatureByName(value)
  if not c then
    print("CaveBot[follow]: can't find creature to follow")
    return false
  end
  local cpos = c:getPosition()
  local pos = pos()
  if getDistanceBetween(cpos, pos) < 2 then
    local Client = getClient()
    if Client and Client.cancelFollow then
      Client.cancelFollow()
    else
      g_game.cancelFollow()
    end
    return true
  else
    follow(c)
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

-- Direction offset lookup (reuse canonical table)
local DIR_OFFSET = DIR_MOD_LOOKUP

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
  
  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile(checkPos))
  if not tile then return nil end
  if not tile.hasCreature or not tile:hasCreature() then return nil end
  
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

CaveBot.registerAction("goto", "green", function(value, retries, prev)
  -- ========== EARLY EXITS (no pathfinding) ==========
  
  -- Skip if actively walking — return "walking" so the main loop does NOT
  -- increment actionRetries.  Only actual walkTo calls should count as retries;
  -- inflating retries while walking caused the safety valve / maxRetries to
  -- abort perfectly valid walks (any destination >7-8 tiles away).
  if player and player:isWalking() then
    -- Check if we've already arrived via EventBus
    if CaveBot.hasArrivedAtWaypoint and CaveBot.hasArrivedAtWaypoint() then
      CaveBot.clearWaypointTarget()
      return true
    end
    return "walking"  -- Don't count walking ticks as retries
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
  local maxDist = CaveBot.getMaxGotoDistance()
  
  -- MULTI-FLOOR WAYPOINT HANDLING
  -- If the waypoint is on a different Z level, signal failure immediately
  -- so WaypointEngine's stuck detection sees it and triggers recovery.
  if destPos.z ~= playerPos.z then
    return false, true  -- instantFail: pumps extra recordFailure
  end

  -- Distance calculations (chebyshev matches findReachableWaypoint + OTClient diagonal movement)
  local distX = math.abs(destPos.x - playerPos.x)
  local distY = math.abs(destPos.y - playerPos.y)
  local dist  = math.max(distX, distY)
  
  -- Too far — signal failure for stuck detection
  if dist > maxDist then
    return false, true  -- instantFail: pumps extra recordFailure
  end

  -- Check if destination is floor-change tile (stairs, ladder, rope spot, hole)
  -- When user explicitly adds such a waypoint, they INTEND to use it
  -- Uses FloorItems module (SSoT: constants/floor_items.lua) for detection,
  -- with minimap color for determining floor-change direction.
  local Client = getClient()
  local minimapColor = (Client and Client.getMinimapColor) and Client.getMinimapColor(destPos) or (g_map and g_map.getMinimapColor(destPos)) or 0
  local isFloorChange = (FloorItems and FloorItems.isFloorChangeTile) and FloorItems.isFloorChangeTile(destPos) or false
  
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
      -- Unknown minimap color: don't assume direction
      expectedFloorAfterChange = nil
    end
    
    -- LOOP PREVENTION: Check if this floor change would create a loop
    if CaveBot.wouldFloorChangeLoop and CaveBot.wouldFloorChangeLoop(expectedFloorAfterChange) then
      -- We would be going back to a floor we just left - likely a loop
      -- Check cooldown before allowing
      if CaveBot.canChangeFloor and not CaveBot.canChangeFloor() then
        -- Still in cooldown - skip this floor change waypoint
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
    CaveBot.clearWaypointTarget()  -- Clear target on arrival
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
        return true
      end
      
      -- Still on the same floor - wait for floor change to occur
      CaveBot.delay(50)  -- Minimal delay for fast floor-change response
      return "retry"
    end
    return true
  end

  -- Max retries — lower thresholds for faster handoff to WaypointEngine recovery.
  -- Progressive: ignoreCreatures retries>1, blocker attack retries>2, ignoreFields retries>2.
  local maxRetries = CaveBot.Config.get("mapClick") and 4 or 8
  if retries >= maxRetries then
    return false
  end

  -- ========== WALKING (single attempt per retry) ==========
  
  -- Check for blocking monster first (only on retry > 2)
  if retries > 2 then
    local blocker = getBlockingMonster(playerPos, destPos, maxDist)
    if blocker then
      local Client = getClient()
      local currentTarget = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
      if currentTarget ~= blocker then
        attack(blocker)
      end
      if Client and Client.setChaseMode then
        Client.setChaseMode(1)
      else
        g_game.setChaseMode(1)
      end
      CaveBot.delay(100)  -- Reduced delay for faster recovery
      return "retry"
    end
  end
  
  -- Attempt to walk
  local walkParams = {
    ignoreNonPathable = true,
    precision = precision,
    allowFloorChange = isFloorChange  -- Allow if user explicitly added floor-change waypoint
  }
  
  -- Progressive escalation: ignoreCreatures early so mapClick (maxRetries=4)
  -- actually benefits; ignoreFields slightly later to match findPathRelaxed.
  if retries > 1 then
    walkParams.ignoreCreatures = true
  end
  if retries > 2 then
    walkParams.ignoreFields = true
  end
  
  if CaveBot.walkTo(destPos, maxDist, walkParams) then
    -- Set waypoint target for EventBus instant arrival detection
    if CaveBot.setCurrentWaypointTarget then
      CaveBot.setCurrentWaypointTarget(destPos, precision)
    end
    -- Mark that we're walking to this waypoint (reduces unnecessary re-execution)
    if CaveBot.setWalkingToWaypoint then
      CaveBot.setWalkingToWaypoint(destPos)
    end
    return "retry"  -- Continue checking for arrival
  end
  
  -- Walk failed — clear walking state and retry with progressive strategies.
  -- retries > 1 ignoreCreatures; retries > 2 blocker attack + ignoreFields.
  -- retries >= maxRetries returns false, feeding WaypointEngine's recordFailure().
  if CaveBot.clearWalkingState then
    CaveBot.clearWalkingState()
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

  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(pos) or (g_map and g_map.getTile(pos))
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

  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(pos) or (g_map and g_map.getTile(pos))
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