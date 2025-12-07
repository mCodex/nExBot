CaveBot.Tools = {}

local Tools = CaveBot.Tools
local USE_COOLDOWN = 600
local lastUseTime = 0

local function hasClassifier()
  return ItemClassifier and ItemClassifier.isDoor
end

local function applyUseDelay()
  local baseDelay = CaveBot.Config and CaveBot.Config.get("useDelay") or 400
  local ping = CaveBot.Config and CaveBot.Config.get("ping") or 0
  CaveBot.delay(baseDelay + ping)
end

local function asLookup(list)
  local lookup = {}
  for _, id in ipairs(list) do
    lookup[id] = true
  end
  return lookup
end

local TOOL_TARGETS = {
  rope = asLookup({ 17238, 12202, 12935, 386, 421, 21966, 14238 }),
  shovel = asLookup({ 606, 593, 867, 608 }),
  machete = asLookup({ 2130, 3696 }),
  scythe = asLookup({ 3653 })
}

local NEAR_OFFSETS = {
  { x = 0, y = 0 },
  { x = 1, y = 0 },
  { x = -1, y = 0 },
  { x = 0, y = 1 },
  { x = 0, y = -1 },
  { x = 1, y = 1 },
  { x = 1, y = -1 },
  { x = -1, y = 1 },
  { x = -1, y = -1 }
}

local function getToolId(toolKey)
  if not CaveBot.Config then
    return nil
  end
  local configKey = toolKey .. "ToolId"
  local value = CaveBot.Config.get(configKey)
  if type(value) ~= "number" or value <= 0 then
    return nil
  end
  return value
end

local function canUseTools()
  if not CaveBot.Config or not CaveBot.Config.get("autoUseTools") then
    return false
  end
  return now - lastUseTime > USE_COOLDOWN
end

local function canUseDoor(tile)
  if not hasClassifier() or not tile or tile:isWalkable() then
    return false
  end

  local thing = tile:getTopUseThing()
  if not thing then
    return false
  end

  return ItemClassifier.isDoor(thing:getId())
end

local function shouldRopeTile(tilePos, dest)
  if not dest then
    return false
  end
  return tilePos.x == dest.x and tilePos.y == dest.y and tilePos.z == dest.z
end

local function matchThing(thing)
  if not thing or not thing:isItem() then
    return nil
  end
  local id = thing:getId()
  for toolType, lookup in pairs(TOOL_TARGETS) do
    if lookup[id] then
      return toolType
    end
  end
  return nil
end

local function detectObstacle(tile, dest)
  if not tile then
    return nil
  end

  local tilePos = tile:getPosition()
  local function isValid(toolType)
    if toolType == "rope" then
      return shouldRopeTile(tilePos, dest)
    end
    return true
  end

  local topThing = tile:getTopUseThing()
  if topThing then
    local toolType = matchThing(topThing)
    if toolType and isValid(toolType) then
      return toolType, topThing
    end
  end

  local items = tile:getItems()
  if items then
    for _, item in ipairs(items) do
      local toolType = matchThing(item)
      if toolType and isValid(toolType) then
        return toolType, item
      end
    end
  end

  local ground = tile:getGround()
  if ground then
    local toolType = matchThing(ground)
    if toolType and isValid(toolType) then
      return toolType, ground
    end
  end

  return nil
end

local function gatherTiles(playerPos, dest)
  local tiles = {}
  local visited = {}

  local function addTile(pos)
    local key = string.format("%d,%d,%d", pos.x, pos.y, pos.z)
    if visited[key] then
      return
    end
    visited[key] = true
    local tile = g_map.getTile(pos)
    if tile then
      tiles[#tiles + 1] = tile
    end
  end

  if dest and dest.z == playerPos.z and getDistanceBetween(playerPos, dest) <= 1 then
    addTile(dest)
  end

  for _, offset in ipairs(NEAR_OFFSETS) do
    local pos = { x = playerPos.x + offset.x, y = playerPos.y + offset.y, z = playerPos.z }
    addTile(pos)
  end

  return tiles
end

local function useTool(toolType, thing)
  local itemId = getToolId(toolType)
  if not itemId then
    return false
  end

  useWith(itemId, thing)
  lastUseTime = now
  applyUseDelay()
  return true
end

local function openDoor(tile)
  if not tile then
    return false
  end

  local thing = tile:getTopUseThing()
  if not thing then
    return false
  end

  use(thing)
  lastUseTime = now
  applyUseDelay()
  return true
end

local function resolveDoors(tiles)
  if not hasClassifier() then
    return false
  end

  for _, tile in ipairs(tiles) do
    if canUseDoor(tile) and openDoor(tile) then
      return true
    end
  end

  return false
end

local function resolveToolTargets(tiles, dest)
  for _, tile in ipairs(tiles) do
    local toolType, thing = detectObstacle(tile, dest)
    if toolType and thing and useTool(toolType, thing) then
      return true
    end
  end

  return false
end

function Tools.handleObstacle(dest)
  if not canUseTools() then
    return false
  end

  local playerPos = player:getPosition()
  if not playerPos then
    return false
  end

  local tiles = gatherTiles(playerPos, dest)
  if resolveDoors(tiles) then
    return true
  end

  return resolveToolTargets(tiles, dest)
end
