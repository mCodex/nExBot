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
local shrineSearch = { key = nil, at = 0, result = nil, failed = false }

local function nowMs()
  if nExBot and nExBot.Shared and nExBot.Shared.nowMs then
    return nExBot.Shared.nowMs()
  end
  if now then return now end
  return os.time() * 1000
end

local function posKey(pos)
  if not pos then return "unknown" end
  return tostring(pos.x) .. ":" .. tostring(pos.y) .. ":" .. tostring(pos.z)
end

local function actionLimiter()
  return BotCore and BotCore.ActionRateLimiter
end

local function throttleRetry(key, interval, actionType)
  local limiter = actionLimiter()
  if not limiter or not limiter.allow then return true end
  local ok, remaining = limiter.allow("imbuing:" .. key, interval, actionType)
  if not ok then
    delay(math.max(remaining or 50, 50))
    return false
  end
  return true
end

local function findShrine(Client, playerPos)
  local key = posKey(playerPos)
  local t = nowMs()
  if shrineSearch.key == key and (t - shrineSearch.at) < 2000 then
    return shrineSearch.result
  end

  local found = nil
  local nearTiles = getNearTiles(playerPos)
  local searchTiles = {}
  local playerTile = (Client and Client.getTile) and Client.getTile(playerPos) or (g_map and g_map.getTile(playerPos))
  if playerTile then searchTiles[#searchTiles+1] = playerTile end
  for _, tile in ipairs(nearTiles) do searchTiles[#searchTiles+1] = tile end

  for _, tile in ipairs(searchTiles) do
    for _, itm in ipairs(tile:getItems()) do
      local id = itm:getId()
      if table.find(SHRINES, id) then
        found = itm
        break
      end
    end
    if found then break end
  end

  if not found then
    for dx = -7, 7 do
      for dy = -7, 7 do
        local checkPos = {x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z}
        local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile(checkPos))
        if tile then
          for _, itm in ipairs(tile:getItems()) do
            if table.find(SHRINES, itm:getId()) then
              found = itm
              break
            end
          end
          if found then break end
        end
      end
      if found then break end
    end
  end

  shrineSearch.key = key
  shrineSearch.at = t
  shrineSearch.result = found
  shrineSearch.failed = not found
  return found
end

local function reset()
  EquipManager.setOn()
  shrine = nil
  currentIndex = 1
  item = nil
  currentId = 0
  triedToTakeOff = false
  destination = nil
  shrineSearch.key = nil
  shrineSearch.at = 0
  shrineSearch.result = nil
  shrineSearch.failed = false
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

    local Client = getClient()
    local playerPos = player:getPosition()
    shrine = shrine or findShrine(Client, playerPos)

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
      if not throttleRetry("equip-off:" .. tostring(currentId), 500, "move") then return "retry" end
      if Client and Client.equipItemId then Client.equipItemId(currentId) elseif g_game then g_game.equipItemId(currentId) end
      delay(1000)
      return "retry"
    end

    -- we are past unequiping so just in case we were forced before, reset var
    triedToTakeOff = false

    -- reaching shrine
    if not CaveBot.MatchPosition(destination, 1) then
      if not throttleRetry("goto-shrine", 250, "path") then return "retry" end
      CaveBot.GoTo(destination, 1)
      delay(200)
      return "retry"
    end

    if not throttleRetry("use-shrine", 500, "useWith") then return "retry" end
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