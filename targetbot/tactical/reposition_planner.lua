RepositionPlanner = {}
RepositionPlanner.__index = RepositionPlanner

local CACHE_TTL_MS = 300
local MAX_RECENT = 5

function RepositionPlanner.new(options)
  options = options or {}
  return setmetatable({
    recentPositions = {},
    cache = {},
    cacheTime = 0,
    cacheKey = nil,
  }, RepositionPlanner)
end

function RepositionPlanner:reset()
  self.recentPositions = {}
  self.cache = {}
  self.cacheKey = nil
  self.cacheTime = 0
end

local function posKey(pos)
  return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function cacheKeyOf(mapGen, playerPos, targetPos)
  return mapGen .. "|" .. posKey(playerPos) .. "|" .. posKey(targetPos)
end

local function addRecent(self, pos)
  table.insert(self.recentPositions, 1, { x = pos.x, y = pos.y, z = pos.z })
  if #self.recentPositions > MAX_RECENT then
    table.remove(self.recentPositions)
  end
end

local function isRecent(self, pos)
  for _, rp in ipairs(self.recentPositions) do
    if rp.x == pos.x and rp.y == pos.y and rp.z == pos.z then return true end
  end
  return false
end

local function generateCandidates(targetPos, attackRange)
  local candidates = {}
  local lo = attackRange - 1
  local hi = attackRange + 1
  if lo < 1 then lo = 1 end
  for dx = -hi, hi do
    for dy = -hi, hi do
      local dist = math.max(math.abs(dx), math.abs(dy))
      if dist >= lo and dist <= hi and not (dx == 0 and dy == 0) then
        candidates[#candidates + 1] = {
          x = targetPos.x + dx,
          y = targetPos.y + dy,
          z = targetPos.z,
          dist = dist,
        }
      end
    end
  end
  return candidates
end

local function countWalkableAdjacent(tile, isWalkable)
  local count = 0
  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        if isWalkable({ x = tile.x + dx, y = tile.y + dy, z = tile.z }) then
          count = count + 1
        end
      end
    end
  end
  return count
end

local function countAdjacentMonsters(tile, isTileOccupied)
  local count = 0
  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        if isTileOccupied({ x = tile.x + dx, y = tile.y + dy, z = tile.z }) then
          count = count + 1
        end
      end
    end
  end
  return count
end

function RepositionPlanner:plan(observation, context)
  observation = observation or {}
  context = context or {}

  local targetPos = observation.targetPos
  local playerPos = observation.playerPos
  if not targetPos or not playerPos then return nil, "NO_TARGET" end

  local attackRange = observation.attackRange or 1
  local now = context.now or 0
  local mapGeneration = context.mapGeneration or 0
  local isWalkable = observation.isWalkable or function() return false end
  local isTileSafe = observation.isTileSafe or function() return true end
  local isTileOccupied = observation.isTileOccupied or function() return false end

  local key = cacheKeyOf(mapGeneration, playerPos, targetPos)
  if self.cacheKey == key and now - self.cacheTime < CACHE_TTL_MS then
    return self.cache.result, self.cache.reason
  end

  local candidates = generateCandidates(targetPos, attackRange)
  local best = nil
  local bestScore = -math.huge

  for _, tile in ipairs(candidates) do
    if tile.z == playerPos.z
      and isWalkable(tile)
      and isTileSafe(tile)
      and not isTileOccupied(tile) then

      local score = 100
      if tile.dist == attackRange then
        score = score + 50
      elseif tile.dist >= attackRange - 1 and tile.dist <= attackRange + 1 then
        score = score + 30
      end

      score = score + countWalkableAdjacent(tile, isWalkable) * 10
      score = score - countAdjacentMonsters(tile, isTileOccupied) * 15

      if isRecent(self, tile) then
        score = score - 20
      end

      if score > bestScore then
        bestScore = score
        best = tile
      end
    end
  end

  if best then
    addRecent(self, best)
    local result = { position = { x = best.x, y = best.y, z = best.z }, score = bestScore, reason = "reposition" }
    self.cache = { result = result }
    self.cacheKey = key
    self.cacheTime = now
    return result
  end

  self.cache = { result = nil, reason = "NO_VALID_REPOSITION_TILE" }
  self.cacheKey = key
  self.cacheTime = now
  return nil, "NO_VALID_REPOSITION_TILE"
end

return RepositionPlanner
