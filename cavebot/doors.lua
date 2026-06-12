CaveBot.Extensions.OpenDoors = {}

local getClient = nExBot.Shared.getClient

local function chebyshev(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function getDoorApproachPos(doorPos, playerPos)
  local offsets = {
    {x=0,y=-1},{x=1,y=0},{x=0,y=1},{x=-1,y=0},
    {x=1,y=-1},{x=1,y=1},{x=-1,y=1},{x=-1,y=-1}
  }
  local best, bestDist = nil, math.huge
  for i = 1, #offsets do
    local p = {x = doorPos.x + offsets[i].x, y = doorPos.y + offsets[i].y, z = doorPos.z}
    local d = chebyshev(playerPos, p)
    if d < bestDist then
      best = p
      bestDist = d
    end
  end
  return best
end

CaveBot.Extensions.OpenDoors.setup = function()
  CaveBot.registerAction("OpenDoors", "#6be8e0", function(value, retries)
    local pos = string.split(value, ",")
    local key = nil
    if #pos == 4 then
      key = tonumber(pos[4])
    end
    if not pos[1] then
      warn("CaveBot[OpenDoors]: invalid value. It should be position (x,y,z), is: " .. value)
      return false
    end

    if retries >= 5 then
      print("CaveBot[OpenDoors]: too many tries, can't open doors")
      return false -- tried 5 times, can't open
    end

    pos = {x=tonumber(pos[1]), y=tonumber(pos[2]), z=tonumber(pos[3])}  
    local playerPos = player:getPosition()
    if not playerPos then return false end

    if chebyshev(playerPos, pos) > 1 then
      local maxDist = CaveBot.getMaxGotoDistance and CaveBot.getMaxGotoDistance() or 50
      local approachPos = getDoorApproachPos(pos, playerPos)
      local walkResult = CaveBot.walkTo(approachPos, maxDist, {
        precision = 1,
        allowFloorChange = false,
      })
      if walkResult then
        CaveBot.delay(100)
        return "retry"
      end
      return false
    end

    local Client = getClient()
    local doorTile = (Client and Client.getTile) and Client.getTile(pos) or (g_map and g_map.getTile(pos))

    if not doorTile then
      return false
    end
  
    if not doorTile:isWalkable() then
      -- Use GlobalConfig for door handling if available
      if GlobalConfig and GlobalConfig.openDoor then
        if not throttleDoor(pos) then return "retry" end
        if GlobalConfig.openDoor(doorTile, key) then
          delay(200)
          return "retry"
        end
      end
      
      -- Fallback to direct door handling using DoorItems
      local topThing = doorTile:getTopUseThing()
      if topThing then
        local itemId = topThing:getId()
        
        -- Check if it's a locked door and we have a key
        if key and DoorItems and DoorItems.isLockedDoor(itemId) then
          if not throttleDoor(pos) then return "retry" end
          useWith(key, topThing)
          delay(200)
          return "retry"
        -- Check if it's a closed door (can open without key)
        elseif DoorItems and DoorItems.isClosedDoor(itemId) then
          if not throttleDoor(pos) then return "retry" end
          use(topThing)
          delay(200)
          return "retry"
        -- Original fallback behavior
        elseif not key then
          if not throttleDoor(pos) then return "retry" end
          use(topThing)
          delay(200)
          return "retry"
        else
          if not throttleDoor(pos) then return "retry" end
          useWith(key, topThing)
          delay(200)
          return "retry"
        end
      end
    else
      print("CaveBot[OpenDoors]: possible to cross, proceeding")
      return true
    end
  end)

  CaveBot.Editor.registerAction("opendoors", "open doors", {
    value=function() return posx() .. "," .. posy() .. "," .. posz() end,
    title="Door position",
    description="doors position (x,y,z) and key id (optional)",
    multiline=false,
    validation=[[\d{1,5},\d{1,5},\d{1,2}(?:,\d{1,5}$|$)]]
})
end