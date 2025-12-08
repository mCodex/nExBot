CaveBot.Actions = {}
nExBot.lastLabel = ""
local oldTibia = g_game.getClientVersion() < 960
local nextTile = nil

local noPath = 0

-- Lightweight cache for goto pathfinding
local gotoPathCache = {
  key = nil,
  from = nil,
  path = nil,
  at = 0
}
local PATH_CACHE_TTL = 800 -- ms - extended for better cache hits

-- Path cache helper functions (defined once, reused)
local function gotoPathKey(pos, variant)
  return variant .. ":" .. pos.x .. "," .. pos.y .. "," .. pos.z
end

local function getGotoCachedPath(key, playerPos)
  if gotoPathCache.key ~= key then return nil end
  if (now - gotoPathCache.at) > PATH_CACHE_TTL then return nil end
  if gotoPathCache.from then
    local dx = math.abs(playerPos.x - gotoPathCache.from.x)
    local dy = math.abs(playerPos.y - gotoPathCache.from.y)
    local dz = math.abs(playerPos.z - gotoPathCache.from.z)
    if math.max(dx, dy) > 2 or dz ~= 0 then
      return nil
    end
  end
  return gotoPathCache.path
end

local function saveGotoCachedPath(key, playerPos, path)
  gotoPathCache.key = key
  gotoPathCache.at = now
  gotoPathCache.from = { x = playerPos.x, y = playerPos.y, z = playerPos.z }
  gotoPathCache.path = path
end

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

CaveBot.registerAction("goto", "green", function(value, retries, prev)
  -- Skip if player is currently walking (wait for step to complete)
  if player and player:isWalking() then
    return "retry"
  end

  local pos = regexMatch(value, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+),?\\s*([0-9]?)")
  if not pos[1] then
    warn("Invalid cavebot goto action value. It should be position (x,y,z), is: " .. value)
    return false
  end

  -- reset pathfinder state
  nextPosF = nil
  nextPos = nil
  
  -- Adaptive retry limits based on walking mode
  local maxRetries = CaveBot.Config.get("mapClick") and 8 or 50
  if retries >= maxRetries then
    print("[CaveBot] goto: max retries reached (" .. maxRetries .. ")")
    noPath = noPath + 1
    pathfinder()
    return false
  end

  local precision = tonumber(pos[1][5])
  pos = {x=tonumber(pos[1][2]), y=tonumber(pos[1][3]), z=tonumber(pos[1][4])}  
  local playerPos = player:getPosition()
  
  -- Different floor check
  if pos.z ~= playerPos.z then 
    print("[CaveBot] goto: floor mismatch - target z=" .. pos.z .. ", player z=" .. playerPos.z)
    noPath = noPath + 1
    pathfinder()
    return false
  end

  local maxDist = storage.extras.gotoMaxDistance or 40
  
  -- Calculate actual distance (Manhattan)
  local distX = math.abs(pos.x - playerPos.x)
  local distY = math.abs(pos.y - playerPos.y)
  local totalDist = distX + distY
  
  if totalDist > maxDist then
    print("[CaveBot] goto: too far - distance=" .. totalDist .. ", max=" .. maxDist)
    noPath = noPath + 1
    pathfinder()
    return false
  end

  -- Detect stairs/special tiles
  local minimapColor = g_map.getMinimapColor(pos)
  local stairs = (minimapColor >= 210 and minimapColor <= 213)
  
  -- Check if already at position
  local targetPrecision = precision or (stairs and 0 or 1)
  if distX <= targetPrecision and distY <= targetPrecision then
    noPath = 0
    return true
  end
  
  -- ============================================
  -- OPTIMIZED PATHFINDING - Let walkTo handle it
  -- ============================================

  -- Try direct walk first (autoWalk does pathfinding internally)
  if CaveBot.walkTo(pos, maxDist, { ignoreNonPathable = true }) then
    noPath = 0
    return "retry"
  end

  -- Direct walk failed, check for blocking creatures
  -- Use cached path to check for monsters
  local ignoreKey = gotoPathKey(pos, "ignore")
  local path = getGotoCachedPath(ignoreKey, playerPos)

  if path == false then
    -- Recently failed, try creature-ignoring walk
    if CaveBot.walkTo(pos, maxDist, { ignoreNonPathable = true, ignoreCreatures = true }) then
      return "retry"
    end
    return "retry"
  end

  if not path then
    path = findPath(playerPos, pos, maxDist, {
      ignoreNonPathable = true,
      precision = 1,
      ignoreCreatures = true,
      allowUnseen = true,
      allowOnlyVisibleTiles = false
    })

    saveGotoCachedPath(ignoreKey, playerPos, path or false)
  end

  if path and #path > 0 then
    -- Check if there's a blocking monster we should attack first (only first 2 tiles)
    local tempPos = { x = playerPos.x, y = playerPos.y, z = playerPos.z }
    local foundMonster = false

    for i, dir in ipairs(path) do
      if i > 2 then break end  -- Only check first 2 steps for speed

      local dirMod = DIR_MOD_LOOKUP[dir]
      if dirMod then
        tempPos.x = tempPos.x + dirMod.x
        tempPos.y = tempPos.y + dirMod.y

        local tile = g_map.getTile(tempPos)
        if tile and tile:hasCreature() then
          local creatures = tile:getCreatures()
          for _, creature in ipairs(creatures) do
            local hppc = creature:getHealthPercent()
            if creature:isMonster() and hppc and hppc > 0 and (oldTibia or creature:getType() < 3) then
              local currentTarget = g_game.getAttackingCreature()
              if currentTarget ~= creature then
                attack(creature)
              end
              g_game.setChaseMode(1)
              CaveBot.delay(150)
              return "retry"
            end
          end
        end
      end
    end

    -- No blocking monster found, try walking with creature ignoring
    if CaveBot.walkTo(pos, maxDist, { ignoreNonPathable = true, ignoreCreatures = true }) then
      return "retry"
    end
  end

  -- Last resort: try without ignoring fields
  if not CaveBot.Config.get("ignoreFields") then
    if CaveBot.walkTo(pos, maxDist) then
      return "retry"
    end
  end

  -- All strategies failed
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