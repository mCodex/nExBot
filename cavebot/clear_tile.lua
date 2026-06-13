CaveBot.Extensions.ClearTile = {}

local getClient = nExBot.Shared.getClient

local function actionLimiter()
  return BotCore and BotCore.ActionRateLimiter
end

local function posKey(pos)
  if not pos then return "unknown" end
  return tostring(pos.x) .. ":" .. tostring(pos.y) .. ":" .. tostring(pos.z)
end

local function throttleRetry(action, pos, interval, actionType)
  local limiter = actionLimiter()
  if not limiter or not limiter.allow then return true end
  local ok, remaining = limiter.allow("cleartile:" .. action .. ":" .. posKey(pos), interval, actionType)
  if not ok then
    delay(math.max(remaining or 50, 50))
    return "throttle_wait"
  end
  return true
end

CaveBot.Extensions.ClearTile.setup = function()
  CaveBot.registerAction("ClearTile", "#6be8e0", function(value, retries)
    local data = string.split(value, ",")
    local pos = {x=tonumber(data[1]), y=tonumber(data[2]), z=tonumber(data[3])}
    local doors = false
    local stand = false
    local pPos = player:getPosition()


    for i, value in ipairs(data) do
      value = value:lower():trim()
      if value == "stand" then
        stand = true
      elseif value == "doors" then
        doors = true
      end
    end


    if #data < 3 or not pos.x or not pos.y or not pos.z then
      warn("CaveBot[ClearTile]: invalid value. It should be position (x,y,z), is: " .. value)
      return false
    end

    if retries >= 20 then
      print("CaveBot[ClearTile]: too many tries, can't clear it")
      return false -- tried 20 times, can't clear it
    end

    if getDistanceBetween(player:getPosition(), pos) == 0 then
      print("CaveBot[ClearTile]: tile reached, proceeding")
      return true
    end
    local Client = getClient()
    local tile = (Client and Client.getTile) and Client.getTile(pos) or (g_map and g_map.getTile(pos))
    if not tile then
      print("CaveBot[ClearTile]: can't find tile or tile is unreachable, skipping")
      return false
    end
    local tPos = tile:getPosition()

    -- no items on tile and walkability means we are done
    local hasCreature = tile.hasCreature and tile:hasCreature()
    if tile:isWalkable() and tile:getTopUseThing():isNotMoveable() and not hasCreature and not doors then
    if stand then
      if not CaveBot.MatchPosition(tPos, 0) then
        local tr = throttleRetry("goto-stand", tPos, 200, "path")
        if tr == "throttle_wait" then return "throttle_wait" end
        if not tr then return "retry" end
        CaveBot.GoTo(tPos, 0)
        delay(100)
        return "retry"
      end
    end
      print("CaveBot[ClearTile]: tile clear, proceeding")
      return true
    end

    if not CaveBot.MatchPosition(tPos, 3) then
      local tr = throttleRetry("goto", tPos, 200, "path")
      if tr == "throttle_wait" then return "throttle_wait" end
      if not tr then return "retry" end
      CaveBot.GoTo(tPos, 3)
      delay(100)
      return "retry"
    end

    if retries > 0 then
      delay(1100)
    end

    -- monster
    local hasCreature2 = tile.hasCreature and tile:hasCreature()
    if hasCreature2 then
      local c = tile:getCreatures()[1]
      if c:isMonster() then
        local tr = throttleRetry("attack", tPos, 350, "attack")
        if tr == "throttle_wait" then return "throttle_wait" end
        if not tr then return "retry" end
        attack(c)
        delay(150)
        return "retry"
      end
    end

    -- moveable item
    local item = tile:getTopMoveThing()
    if item:isItem() then
      if item and not item:isNotMoveable() then
        print("CaveBot[ClearTile]: moving item... " .. item:getId().. " from tile")
        local tr = throttleRetry("move-item", tPos, 250, "move")
        if tr == "throttle_wait" then return "throttle_wait" end
        if not tr then return "retry" end
        if Client and Client.move then Client.move(item, pPos, item:getCount()) elseif g_game then g_game.move(item, pPos, item:getCount()) end
        delay(200)
        return "retry"
      end   
    end

    -- player

      -- push creature
      local hasCreature3 = tile.hasCreature and tile:hasCreature()
      if hasCreature3 then
        local c = tile:getCreatures()[1]
        if c and c:isPlayer() then

          local candidates = {}
          local adjacentTiles = getNearTiles(c:getPosition())
          for _, tile in ipairs(adjacentTiles) do
            local tPos = tile:getPosition()
            if tPos.x ~= pPos.x or tPos.y ~= pPos.y or tPos.z ~= pPos.z then
              if tile:isWalkable() then
                table.insert(candidates, tPos)
              end
            end
          end

            if #candidates == 0 then
              print("CaveBot[ClearTile]: can't find tile to push, cannot clear way, skipping")
              return false
            else
              print("CaveBot[ClearTile]: pushing player... " .. c:getName() .. " out of the way")
              local pos = candidates[math.random(1,#candidates)]
              local tileToPush = (Client and Client.getTile) and Client.getTile(pos) or (g_map and g_map.getTile(pos))
              tileToPush:setText("here")
              schedule(500, function() tileToPush:setText("") end)
              local tr = throttleRetry("push-player", tPos, 350, "move")
              if tr == "throttle_wait" then return "throttle_wait" end
              if not tr then return "retry" end
              if Client and Client.move then Client.move(c, pos, 1) elseif g_game then g_game.move(c, pos, 1) end
              delay(250)
              return "retry"
            end
        end
      end

    -- doors
    if doors then
      local tr = throttleRetry("use-door", tPos, 250, "use")
      if tr == "throttle_wait" then return "throttle_wait" end
      if not tr then return "retry" end
      use(tile:getTopUseThing())
      delay(200)
      return "retry"
    end

    delay(100)
    return "retry"
  end)

  CaveBot.Editor.registerAction("cleartile", "clear tile", {
    value=function() return posx() .. "," .. posy() .. "," .. posz() end,
    title="position of tile to clear",
    description="tile position (x,y,z), doors/stand - optional",
    multiline=false
})
end