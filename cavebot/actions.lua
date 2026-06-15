CaveBot.Actions = {}
nExBot.lastLabel = ""

local getClient = nExBot.Shared.getClient

local FloorItems = (function()
  local ok, fi = pcall(dofile, "/constants/floor_items.lua")
  if ok and fi then return fi end
  ok, fi = pcall(dofile, "/core/constants/floor_items.lua")
  return ok and fi or {}
end)()

local CARDINAL_OFFSETS = {{x=0,y=-1},{x=1,y=0},{x=0,y=1},{x=-1,y=0}}

local function getAdjacentPos(targetPos)
  for _, off in ipairs(CARDINAL_OFFSETS) do
    local alt = {x = targetPos.x + off.x, y = targetPos.y + off.y, z = targetPos.z}
    if not (FloorItems.isFloorChangeTile and FloorItems.isFloorChangeTile(alt)) then
      return alt
    end
  end
  return nil
end

local function actionLimiter()
  return BotCore and BotCore.ActionRateLimiter
end

local function throttleCavebotAction(key, interval, actionType)
  local limiter = actionLimiter()
  if not limiter or not limiter.allow then return true end
  local ok, remaining = limiter.allow("cavebot:" .. key, interval, actionType)
  if not ok then
    delay(math.max(remaining or 50, 50))
    return false
  end
  return true
end

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
        if not throttleCavebotAction("antistuck-disintegrate", 500, "useWith") then return end
        return useWith(3197, topThing)
      else
        if now < lastMoved + 200 then return end
        local nearTiles = getNearTiles(tile:getPosition())
        for j, nearTile in ipairs(nearTiles) do
          local tpos = nearTile:getPosition()
          if playerPos.x ~= tpos.x or playerPos.y ~= tpos.y or playerPos.z ~= tpos.z then
            if nearTile:isWalkable() then
              if not throttleCavebotAction("antistuck-move", 250, "move") then return end
              lastMoved = now
              local Client = getClient()
              if Client and Client.move then
                return Client.move(topThing, tpos)
              else
                return g_game.move(topThing, tpos)
              end
            end
          end
        end
      end
    end
  end
end)

CaveBot.addAction = function(action, value, focus)
  action = action:lower()
  local raction = CaveBot.Actions[action]
  if not raction then return warn("Invalid cavebot action: " .. action) end
  if type(value) == 'number' then value = tostring(value) end
  local widget = UI.createWidget("CaveBotAction", CaveBot.actionList)
  widget:setText(action .. ":" .. value:split("\n")[1])
  widget.action = action
  widget.value = value
  if raction.color then widget:setColor(raction.color) end
  if CaveBot.invalidateWaypointCache then CaveBot.invalidateWaypointCache() end
  widget.onDoubleClick = function(cwidget)
    if CaveBot.Editor then
      schedule(20, function()
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

CaveBot.editAction = function(widget, action, value)
  action = action:lower()
  local raction = CaveBot.Actions[action]
  if not raction then return warn("Invalid cavebot action: " .. action) end
  if not widget.action or not widget.value then return warn("Invalid cavebot action widget, has missing action or value") end
  widget:setText(action .. ":" .. value:split("\n")[1])
  widget.action = action
  widget.value = value
  if raction.color then widget:setColor(raction.color) end
  return widget
end

CaveBot.registerAction = function(action, color, callback)
  action = action:lower()
  if CaveBot.Actions[action] then return warn("Duplicated acction: " .. action) end
  CaveBot.Actions[action] = { color=color, callback=callback }
end

CaveBot.registerAction("label", "#ffc857", function(value, retries, prev)
  nExBot.lastLabel = value
  if nExBot.SmartHunt and nExBot.SmartHunt.Routes then
    nExBot.SmartHunt.Routes.enterWaypoint(value)
  end
  return true
end)

CaveBot.registerAction("gotolabel", "#ffc857", function(value, retries, prev)
  return CaveBot.gotoLabel(value)
end)

CaveBot.registerAction("delay", "#8893b3", function(value, retries, prev)
  if retries == 0 then
    local data = string.split(value, ",")
    local val = tonumber(data[1]:trim())
    local random
    local final
    if #data == 2 then random = tonumber(data[2]:trim()) end
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

CaveBot.registerAction("follow", "#46e6a6", function(value, retries, prev)
  local c = getCreatureByName(value)
  if not c then
    print("CaveBot[follow]: can't find creature to follow")
    return false
  end
  local cpos = c:getPosition()
  local pos = pos()
  if getDistanceBetween(cpos, pos) < 2 then
    local Client = getClient()
    if Client and Client.cancelFollow then Client.cancelFollow()
    else g_game.cancelFollow() end
    return true
  else
    follow(c)
    delay(200)
    return "retry"
  end
end)

CaveBot.registerAction("function", "#ff4b81", function(value, retries, prev)
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

local ALL_OFFSETS = {
  {x=0,y=-1},{x=1,y=0},{x=0,y=1},{x=-1,y=0},
  {x=1,y=-1},{x=1,y=1},{x=-1,y=1},{x=-1,y=-1}
}

local function getAdjacentApproachPos(playerPos, targetPos)
  if not playerPos or not targetPos then return targetPos end
  local bestPos, bestDist = nil, math.huge
  for _, off in ipairs(ALL_OFFSETS) do
    local alt = {x = targetPos.x + off.x, y = targetPos.y + off.y, z = targetPos.z}
    if not (FloorItems.isFloorChangeTile and FloorItems.isFloorChangeTile(alt)) then
      local d = math.max(math.abs(playerPos.x - alt.x), math.abs(playerPos.y - alt.y))
      if d < bestDist then bestPos = alt; bestDist = d end
    end
  end
  return bestPos or targetPos
end

-- ============================================================================
-- SIMPLIFIED GOTO ACTION — vBot-style: no floor transition handling
-- Floor changes handled by explicit "use" waypoints (ladder, rope, hole).
-- Returns false when crossing floors; waypoint system handles the rest.
-- ============================================================================

CaveBot.registerAction("goto", "#46e6a6", function(value, retries, prev)
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

  -- Different floor: return false (use explicit "use" waypoints for stairs/ladders/ropes)
  if destPos.z ~= playerPos.z then
    return false
  end

  local distX = math.abs(destPos.x - playerPos.x)
  local distY = math.abs(destPos.y - playerPos.y)
  local dist = math.max(distX, distY)

  -- Arrival check
  if dist <= precision then
    CaveBot.clearWaypointTarget()
    return true
  end

  -- Currently walking
  if player and player:isWalking() then
    if CaveBot.hasArrivedAtWaypoint and CaveBot.hasArrivedAtWaypoint() then
      CaveBot.clearWaypointTarget()
      return true
    end
    return "walking"
  end

  -- Too far
  if dist > maxDist then return false, true end

  -- Max retries
  if retries >= 30 then return false end

  -- Walk parameters with progressive escalation
  local walkParams = {
    ignoreNonPathable = true,
    precision = math.max(0, precision - 1),
    allowFloorChange = false
  }
  if retries > 1 then walkParams.ignoreCreatures = true end
  if retries > 2 then walkParams.ignoreFields = true end

  local walkResult = CaveBot.walkTo(destPos, maxDist, walkParams)
  if walkResult then
    if CaveBot.setCurrentWaypointTarget then
      CaveBot.setCurrentWaypointTarget(destPos, precision)
    end
    local walkDelay = dist <= 3 and 0 or dist <= 8 and 25 or dist <= 15 and 50 or 75
    if walkDelay > 0 then CaveBot.delay(walkDelay) end
    return "walking"
  end

  return "retry"
end)

CaveBot.registerAction("use", "#3be4d0", function(value, retries, prev)
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
  local isFC = FloorItems.isFloorChangeTile and FloorItems.isFloorChangeTile(pos) or false
  if pos.z ~= playerPos.z then
    if isFC then
      local Client = getClient()
      local minimapColor = (Client and Client.getMinimapColor) and Client.getMinimapColor(pos) or (g_map and g_map.getMinimapColor(pos)) or 0
      local expectedFloor = FloorItems.getExpectedFloor and FloorItems.getExpectedFloor(minimapColor, pos.z) or pos.z
      if playerPos.z == expectedFloor then return true end
    end
    return false
  end
  local dist = math.max(math.abs(pos.x-playerPos.x), math.abs(pos.y-playerPos.y))
  if dist > 1 then
    local maxDist = CaveBot.getMaxGotoDistance and CaveBot.getMaxGotoDistance() or 50
    local approachPos = getAdjacentApproachPos(playerPos, pos)
    local walkResult = CaveBot.walkTo(approachPos, maxDist, { precision = 1, allowFloorChange = false })
    if walkResult then CaveBot.delay(100); return "retry" end
    return false
  end
  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(pos) or (g_map and g_map.getTile(pos))
  if not tile then return false end
  local topThing = tile:getTopUseThing()
  if not topThing then return false end
  use(topThing)
  CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
  if isFC then return "retry" end
  return true
end)

CaveBot.registerAction("usewith", "#3be4d0", function(value, retries, prev)
  local pos = regexMatch(value, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)")
  local itemid = nil
  if not pos[1] then
    itemid = tonumber(value)
    if not itemid then
      warn("Invalid cavebot usewith action value. It should be (itemid,x,y,z) or item id, is: " .. value)
      return false
    end
    use(itemid)
    return true
  end
  itemid = tonumber(pos[1][2])
  pos = {x=tonumber(pos[1][3]), y=tonumber(pos[1][4]), z=tonumber(pos[1][5])}
  local playerPos = player:getPosition()
  local isFC = FloorItems.isFloorChangeTile and FloorItems.isFloorChangeTile(pos) or false
  if pos.z ~= playerPos.z then
    if isFC then
      local Client = getClient()
      local minimapColor = (Client and Client.getMinimapColor) and Client.getMinimapColor(pos) or (g_map and g_map.getMinimapColor(pos)) or 0
      local expectedFloor = FloorItems.getExpectedFloor and FloorItems.getExpectedFloor(minimapColor, pos.z) or pos.z
      if playerPos.z == expectedFloor then return true end
    end
    return false
  end
  local dist = math.max(math.abs(pos.x-playerPos.x), math.abs(pos.y-playerPos.y))
  if dist > 1 then
    local maxDist = CaveBot.getMaxGotoDistance and CaveBot.getMaxGotoDistance() or 50
    local approachPos = getAdjacentApproachPos(playerPos, pos)
    local walkResult = CaveBot.walkTo(approachPos, maxDist, { precision = 1, allowFloorChange = false })
    if walkResult then CaveBot.delay(100); return "retry" end
    return false
  end
  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(pos) or (g_map and g_map.getTile(pos))
  if not tile then return false end
  local topThing = tile:getTopUseThing()
  if not topThing then return false end
  usewith(itemid, topThing)
  CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
  if isFC then return "retry" end
  return true
end)

CaveBot.registerAction("say", "#c49bff", function(value, retries, prev)
  say(value)
  return true
end)
CaveBot.registerAction("npcsay", "#c49bff", function(value, retries, prev)
  NPC.say(value)
  return true
end)
