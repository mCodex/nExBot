CaveBot.Extensions.OpenDoors = {}

CaveBot.Extensions.OpenDoors.setup = function()
  CaveBot.registerAction("OpenDoors", "#00FFFF", function(value, retries)
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

    local doorTile
    if not doorTile then
      for i, tile in ipairs(g_map.getTiles(posz())) do
        if tile:getPosition().x == pos.x and tile:getPosition().y == pos.y and tile:getPosition().z == pos.z then
          doorTile = tile
        end
      end
    end

    if not doorTile then
      return false
    end
  
    if not doorTile:isWalkable() then
      -- Use GlobalConfig for door handling if available
      if GlobalConfig and GlobalConfig.openDoor then
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
          useWith(key, topThing)
          delay(200)
          return "retry"
        -- Check if it's a closed door (can open without key)
        elseif DoorItems and DoorItems.isClosedDoor(itemId) then
          use(topThing)
          delay(200)
          return "retry"
        -- Original fallback behavior
        elseif not key then
          use(topThing)
          delay(200)
          return "retry"
        else
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