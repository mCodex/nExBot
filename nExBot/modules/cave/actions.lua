--[[
  CaveBot Actions
  
  Waypoint action definitions and handlers.
  
  Author: nExBot Team
  Version: 1.0.0
]]

-- Define action handlers for different waypoint types
CaveBot.Actions = {}

-- Walk action
CaveBot.Actions.walk = function(waypoint)
  local pos = waypoint.pos
  if not player:isWalking() then
    return autoWalk(pos, 10, {marginMin = 0, marginMax = 0})
  end
  return false
end

-- Stand action (same as walk but waits)
CaveBot.Actions.stand = function(waypoint)
  return CaveBot.Actions.walk(waypoint)
end

-- Rope action
CaveBot.Actions.rope = function(waypoint)
  local pos = waypoint.pos
  local tile = g_map.getTile(pos)
  if not tile then return false end
  
  -- Find rope hole
  for _, item in ipairs(tile:getItems()) do
    if item:isRopeSpot() then
      useWith(3003, item)
      return true
    end
  end
  
  return false
end

-- Shovel action
CaveBot.Actions.shovel = function(waypoint)
  local pos = waypoint.pos
  local tile = g_map.getTile(pos)
  if not tile then return false end
  
  -- Find shovel spot
  for _, item in ipairs(tile:getItems()) do
    if item:isShovelSpot() then
      useWith(3457, item)
      return true
    end
  end
  
  return false
end

-- Ladder action
CaveBot.Actions.ladder = function(waypoint)
  local pos = waypoint.pos
  local tile = g_map.getTile(pos)
  if not tile then return false end
  
  local topThing = tile:getTopUseThing()
  if topThing then
    g_game.use(topThing)
    return true
  end
  
  return false
end

-- Stairs action (same as ladder)
CaveBot.Actions.stairs = CaveBot.Actions.ladder

-- Sewer grate action
CaveBot.Actions.sewer = function(waypoint)
  local pos = waypoint.pos
  local tile = g_map.getTile(pos)
  if not tile then return false end
  
  for _, item in ipairs(tile:getItems()) do
    local id = item:getId()
    if id == 435 or id == 594 then -- Open sewer grate IDs
      g_game.use(item)
      return true
    end
  end
  
  return false
end

-- Pick action (pickaxe)
CaveBot.Actions.pick = function(waypoint)
  local pos = waypoint.pos
  local tile = g_map.getTile(pos)
  if not tile then return false end
  
  local topThing = tile:getTopUseThing()
  if topThing then
    useWith(3456, topThing) -- Pickaxe ID
    return true
  end
  
  return false
end

-- Machete action
CaveBot.Actions.machete = function(waypoint)
  local pos = waypoint.pos
  local tile = g_map.getTile(pos)
  if not tile then return false end
  
  for _, item in ipairs(tile:getItems()) do
    if item:isJungleCut() then
      useWith(3308, item) -- Machete ID
      return true
    end
  end
  
  return false
end

-- Open door action
CaveBot.Actions.door = function(waypoint)
  local pos = waypoint.pos
  local tile = g_map.getTile(pos)
  if not tile then return false end
  
  for _, item in ipairs(tile:getItems()) do
    if item:isDoor() and not item:isOpen() then
      g_game.use(item)
      return true
    end
  end
  
  return false
end

-- Close door action
CaveBot.Actions.closeDoor = function(waypoint)
  local pos = waypoint.pos
  local tile = g_map.getTile(pos)
  if not tile then return false end
  
  for _, item in ipairs(tile:getItems()) do
    if item:isDoor() and item:isOpen() then
      g_game.use(item)
      return true
    end
  end
  
  return false
end

-- Say action
CaveBot.Actions.say = function(waypoint)
  if waypoint.text then
    say(waypoint.text)
    return true
  end
  return false
end

-- NPC say action
CaveBot.Actions.npcsay = function(waypoint)
  if waypoint.text then
    NPC.say(waypoint.text)
    return true
  end
  return false
end

-- Wait action
CaveBot.Actions.wait = function(waypoint)
  local duration = waypoint.duration or 1000
  CaveBot.delay(duration)
  return true
end

-- Label action (just a marker)
CaveBot.Actions.label = function(waypoint)
  return true
end

-- Goto action
CaveBot.Actions.goto = function(waypoint)
  if waypoint.label then
    return CaveBot.gotoLabel(waypoint.label)
  end
  return false
end

-- Function action
CaveBot.Actions.func = function(waypoint)
  if waypoint.func and type(waypoint.func) == "function" then
    local success, result = pcall(waypoint.func)
    return success and result ~= false
  end
  return true
end

-- Use item action
CaveBot.Actions.useItem = function(waypoint)
  if waypoint.itemId then
    local pos = waypoint.pos
    local tile = g_map.getTile(pos)
    if tile then
      local topThing = tile:getTopUseThing()
      if topThing then
        useWith(waypoint.itemId, topThing)
        return true
      end
    end
  end
  return false
end

-- Lure action
CaveBot.Actions.lure = function(waypoint)
  -- Handled by LuringManager
  if nExBot and nExBot.modules.LuringManager then
    nExBot.modules.LuringManager:setLurePosition(waypoint.pos)
    return true
  end
  return true
end

-- Check floor change
CaveBot.Actions.checkFloor = function(waypoint)
  local myPos = player:getPosition()
  return myPos.z == waypoint.pos.z
end

-- Get action handler
function CaveBot.getActionHandler(actionType)
  return CaveBot.Actions[actionType]
end

-- Register custom action
function CaveBot.registerAction(name, handler)
  if type(handler) == "function" then
    CaveBot.Actions[name] = handler
    return true
  end
  return false
end
