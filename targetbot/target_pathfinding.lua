-- TargetBot Pathfinding Module
-- Path calculation, distance management, walkability checks

local getClient = nExBot.Shared.getClient

local PATH_PARAMS = {
  ignoreLastCreature = true,
  ignoreNonPathable = true,
  ignoreCost = true,
  ignoreCreatures = true,
  allowOnlyVisibleTiles = true,
  precision = 1
}

local RELAXED_PATH_PARAMS = {
  ignoreLastCreature = true,
  ignoreNonPathable = true,
  ignoreCost = true,
  ignoreCreatures = true,
  allowOnlyVisibleTiles = false,
  precision = 1
}

local PathCache = {
  entries = {},
  TTL = 400
}

local function cleanupPathCache()
  local currentTime = now or (os.time() * 1000)
  local cutoff = currentTime - PathCache.TTL * 2
  for id, entry in pairs(PathCache.entries) do
    if entry.time < cutoff then
      PathCache.entries[id] = nil
    end
  end
end

local function getCachedPath(creatureId, playerPos, creaturePos)
  local entry = PathCache.entries[creatureId]
  local currentTime = now or (os.time() * 1000)
  if entry and (currentTime - entry.time) < PathCache.TTL then
    if entry.playerZ == playerPos.z and entry.creatureZ == creaturePos.z then
      return entry.path
    end
  end
  return nil
end

local function setCachedPath(creatureId, path, playerPos, creaturePos)
  PathCache.entries[creatureId] = {
    path = path,
    time = now or (os.time() * 1000),
    playerZ = playerPos.z,
    creatureZ = creaturePos.z
  }
end

local function findPathInternal(pos, cpos, maxDist, params)
  return findPath(pos, cpos, maxDist, params)
end

local function isInRange(pos1, pos2, range)
  if not pos1 or not pos2 then return false end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y)) <= range
end

local function getWalkDirection(path)
  if not path or #path == 0 then return nil end
  return path[1]
end

local function isSameFloor(pos1, pos2)
  return pos1 and pos2 and pos1.z == pos2.z
end

local function chebyshevDistance(p1, p2)
  if not p1 or not p2 then return 999 end
  if p1.z ~= p2.z then return 999 end
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

local chebyshev = chebyshevDistance

local function getDistanceBetween(pos1, pos2)
  if not pos1 or not pos2 then return nil end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

local function isTargetableCreature(creature)
  if not creature then return false end
  local SC = SafeCreature or {}
  local isDead = SC.isDead(creature)
  if isDead then return false end
  local isMonster = SC.isMonster(creature)
  if not isMonster then return false end
  local hp = SC.getHealthPercent(creature)
  if hp and hp <= 0 then return false end
  local Client = getClient()
  local oldTibia = (Client and Client.getClientVersion) and Client.getClientVersion() < 960
  if oldTibia then return true end
  local okType, creatureType = pcall(function() return creature:getType() end)
  if okType and creatureType then
    return creatureType < 3
  end
  return true
end

local function isTargetableMonster(creature)
  if not creature then return false end
  local SC = SafeCreature or {}
  if SC.isDead and SC.isDead(creature) then return false end
  if SC.isMonster and not SC.isMonster(creature) then return false end
  if SC.getHealthPercent and SC.getHealthPercent(creature) <= 0 then return false end
  local Client = getClient()
  local oldTibia = (Client and Client.getClientVersion) and Client.getClientVersion() < 960
  if oldTibia then return true end
  local okType, creatureType = pcall(function() return creature:getType() end)
  if creatureType and creatureType >= 3 then return false end
  return true
end

local function isTileSafe(checkPos)
  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile and g_map.getTile(checkPos))
  local hasCreature = tile and tile.hasCreature and tile:hasCreature()
  return tile and tile:isWalkable() and not hasCreature
end

nExBot.target_pathfinding = {
  getCachedPath = getCachedPath,
  setCachedPath = setCachedPath,
  cleanupPathCache = cleanupPathCache,
  PathCache = PathCache,
  PATH_PARAMS = PATH_PARAMS,
  RELAXED_PATH_PARAMS = RELAXED_PATH_PARAMS,
  findPath = findPathInternal,
  isInRange = isInRange,
  getWalkDirection = getWalkDirection,
  isSameFloor = isSameFloor,
  chebyshevDistance = chebyshevDistance,
  chebyshev = chebyshev,
  getDistanceBetween = getDistanceBetween,
  isTargetableCreature = isTargetableCreature,
  isTargetableMonster = isTargetableMonster,
  isTileSafe = isTileSafe
}
