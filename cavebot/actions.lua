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
  if CaveBot.isOff() then return end

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

  if not CaveBot.gotoNextWaypointInRange() then
    if getConfigFromName and getConfigFromName() then
      local profile = CaveBot.getCurrentProfile()
      local config = getConfigFromName()
      local newProfile = profile == '#Unibase' and config or '#Unibase'
      
      CaveBot.setCurrentProfile(newProfile)
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
  local c = getCreatureByName(value)
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

CaveBot.registerAction("goto", "green", function(value, retries, prev)
  -- ========== EARLY EXITS (no pathfinding) ==========
  
  -- Skip if walking
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
  
  -- Floor mismatch
  if destPos.z ~= playerPos.z then
    noPath = noPath + 1
    pathfinder()
    return false
  end

  -- Distance calculations
  local distX = math.abs(destPos.x - playerPos.x)
  local distY = math.abs(destPos.y - playerPos.y)
  local maxDist = storage.extras.gotoMaxDistance or 50  -- Realistic pathfinding limit
  
  -- Too far
  if (distX + distY) > maxDist then
    noPath = noPath + 1
    pathfinder()
    return false
  end

  -- Check if destination is floor-change tile (stairs, ladder, rope spot, hole)
  -- When user explicitly adds such a waypoint, they INTEND to use it
  local minimapColor = g_map.getMinimapColor(destPos)
  local isFloorChange = (minimapColor >= 210 and minimapColor <= 213)
  
  -- Also check tile items for floor-change detection (minimap might miss some)
  if not isFloorChange and CaveBot.isFloorChangeTile then
    isFloorChange = CaveBot.isFloorChangeTile(destPos)
  end
  
  -- If destination is floor-change, use precision 0 and allow the floor change
  if isFloorChange then precision = 0 end
  
  -- Already at destination
  if distX <= precision and distY <= precision then
    noPath = 0
    return true
  end

  -- Max retries
  local maxRetries = CaveBot.Config.get("mapClick") and 8 or 40
  if retries >= maxRetries then
    noPath = noPath + 1
    pathfinder()
    return false
  end

  -- ========== WALKING (single attempt per retry) ==========
  
  -- Check for blocking monster first (only on retry > 2)
  if retries > 2 then
    local blocker = getBlockingMonster(playerPos, destPos, maxDist)
    if blocker then
      local currentTarget = g_game.getAttackingCreature()
      if currentTarget ~= blocker then
        attack(blocker)
      end
      g_game.setChaseMode(1)
      CaveBot.delay(200)
      return "retry"
    end
  end
  
  -- Attempt to walk
  local walkParams = {
    ignoreNonPathable = true,
    precision = precision,
    allowFloorChange = isFloorChange  -- Allow if user explicitly added floor-change waypoint
  }
  
  -- Use creature ignoring on higher retries
  if retries > 5 then
    walkParams.ignoreCreatures = true
  end
  
  if CaveBot.walkTo(destPos, maxDist, walkParams) then
    -- Mark that we're walking to this waypoint (reduces unnecessary re-execution)
    if CaveBot.setWalkingToWaypoint then
      CaveBot.setWalkingToWaypoint(destPos)
    end
    noPath = 0
    return "retry"
  end
  
  -- Walk failed - clear walking state
  if CaveBot.clearWalkingState then
    CaveBot.clearWalkingState()
  end
  
  -- Walk failed
  if retries >= maxRetries - 1 then
    noPath = noPath + 1
    pathfinder()
    return false
  end
  
  CaveBot.delay(100)
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