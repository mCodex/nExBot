-- imbuing window should be handled separatly
-- reequiping should be handled separatly (ie. equipment manager)

CaveBot.Extensions.Imbuing = {}

local getClient = nExBot.Shared.getClient

local SHRINES = {25060, 25061, 25182, 25183}
local currentIndex = 1
local shrine = nil
local item = nil
local currentId = 0
local triedToTakeOff = false
local destination = nil

local function reset()
  EquipManager.setOn()
  shrine = nil
  currentIndex = 1
  item = nil
  currentId = 0
  triedToTakeOff = false
  destination = nil
end

CaveBot.Extensions.Imbuing.setup = function()
  CaveBot.registerAction("imbuing", "#ff4b81", function(value, retries)
    local data = string.split(value, ",")
    local ids = {}

    if #data == 0 and value ~= 'name' then
      warn("CaveBot[Imbuing] no items added, proceeding")
      reset()
      return false
    end

    -- setting of equipment manager so it wont disturb imbuing process
    EquipManager.setOff()

    if value == 'name' then
      local imbuData = AutoImbueTable[player:getName()]      
      for id, imbues in pairs(imbuData) do
        table.insert(ids, id)
      end
    else
      -- convert to number
      for i, id in ipairs(data) do
        id = tonumber(id)
        if not table.find(ids, id) then
          table.insert(ids, id)
        end
      end
    end
 
    -- all items imbued, can proceed
    if currentIndex > #ids then
      warn("CaveBot[Imbuing] used shrine on all items, proceeding")
      reset()
      return true
    end

    -- Search nearby tiles for shrine instead of full floor scan
    local Client = getClient()
    local playerPos = player:getPosition()
    local nearTiles = getNearTiles(playerPos)
    -- Also check tiles in a wider radius (up to 7 sqm) around player
    local searchTiles = {}
    -- Start with the player's own tile
    local playerTile = (Client and Client.getTile) and Client.getTile(playerPos) or (g_map and g_map.getTile(playerPos))
    if playerTile then searchTiles[#searchTiles+1] = playerTile end
    for _, t in ipairs(nearTiles) do searchTiles[#searchTiles+1] = t end
    -- Expand search to 7-tile radius if not found nearby
    for _, tile in ipairs(searchTiles) do
      for _, itm in ipairs(tile:getItems()) do
          local id = itm:getId()
          if table.find(SHRINES, id) then
            shrine = itm
            break
          end
      end
      if shrine then break end
    end
    -- Fallback: scan spectator range tiles if shrine not found nearby
    if not shrine then
      for dx = -7, 7 do
        for dy = -7, 7 do
          local checkPos = {x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z}
          local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile(checkPos))
          if tile then
            for _, itm in ipairs(tile:getItems()) do
              if table.find(SHRINES, itm:getId()) then
                shrine = itm
                break
              end
            end
            if shrine then break end
          end
        end
        if shrine then break end
      end
    end

    -- if not shrine
    if not shrine then
      warn("CaveBot[Imbuing] shrine not found! proceeding")
      reset()
      return false
    end

    destination = shrine:getPosition()

    currentId = ids[currentIndex]
    item = findItem(currentId)
    
    -- maybe equipped? try to take off
    if not item then
      -- did try before, still not found so item is unavailable
      if triedToTakeOff then
        warn("CaveBot[Imbuing] item not found! skipping: "..currentId)
        triedToTakeOff = false
        currentIndex = currentIndex + 1
        return "retry"
      end
      triedToTakeOff = true
      if Client and Client.equipItemId then Client.equipItemId(currentId) elseif g_game then g_game.equipItemId(currentId) end
      delay(1000)
      return "retry"
    end

    -- we are past unequiping so just in case we were forced before, reset var
    triedToTakeOff = false

    -- reaching shrine
    if not CaveBot.MatchPosition(destination, 1) then
      CaveBot.GoTo(destination, 1)
      delay(200)
      return "retry"
    end

    useWith(shrine, item)
    currentIndex = currentIndex + 1
    warn("CaveBot[Imbuing] Using shrine on item: "..currentId)
    delay(4000)
    return "retry"
  end)

 CaveBot.Editor.registerAction("imbuing", "imbuing", {
  value="name",
  title="Auto Imbuing",
  description="insert below item ids to be imbued, separated by comma\nor 'name' to load from file",
 })
end