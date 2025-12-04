--[[
  nExBot Creature Tracker
  Tracks creature positions and detects respawns
  
  Features:
  - Spawn position tracking
  - Distance from spawn monitoring
  - Respawn detection
  - Weak reference tracking for GC efficiency
  
  Author: nExBot Team
  Version: 1.0.0
]]

local CreatureTracker = {
  trackedCreatures = {},
  safeDistance = 5,
  respawnThreshold = 3000,  -- 3 seconds
  cleanupInterval = 10000,  -- 10 seconds
  lastCleanup = 0
}

-- Create new tracker instance
function CreatureTracker:new(options)
  options = options or {}
  
  local instance = {
    trackedCreatures = {},
    safeDistance = options.safeDistance or 5,
    respawnThreshold = options.respawnThreshold or 3000,
    cleanupInterval = options.cleanupInterval or 10000,
    lastCleanup = 0
  }
  
  setmetatable(instance, { __index = self })
  return instance
end

-- Get current time helper
local function getCurrentTime()
  return g_clock and g_clock.millis() or (now or 0)
end

-- Calculate distance between positions
local function calculateDistance(pos1, pos2)
  return math.sqrt(
    math.pow(pos1.x - pos2.x, 2) +
    math.pow(pos1.y - pos2.y, 2)
  )
end

-- Track a creature
function CreatureTracker:track(creature)
  if not creature then return nil end
  
  local id = creature:getId()
  if not id then return nil end
  
  local currentTime = getCurrentTime()
  local currentPos = creature:getPosition()
  
  if not self.trackedCreatures[id] then
    -- New creature, start tracking
    self.trackedCreatures[id] = {
      id = id,
      name = creature:getName(),
      spawnPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z},
      lastSeenPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z},
      lastSeen = currentTime,
      firstSeen = currentTime,
      distanceFromSpawn = 0,
      maxDistanceFromSpawn = 0,
      totalMoves = 0,
      isDead = false
    }
  else
    -- Update existing tracking
    local tracking = self.trackedCreatures[id]
    local prevPos = tracking.lastSeenPos
    
    -- Check if moved
    if prevPos.x ~= currentPos.x or prevPos.y ~= currentPos.y then
      tracking.totalMoves = tracking.totalMoves + 1
    end
    
    tracking.lastSeenPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
    tracking.lastSeen = currentTime
    tracking.distanceFromSpawn = calculateDistance(currentPos, tracking.spawnPos)
    tracking.maxDistanceFromSpawn = math.max(tracking.maxDistanceFromSpawn, tracking.distanceFromSpawn)
  end
  
  return self.trackedCreatures[id]
end

-- Get tracking data for a creature
function CreatureTracker:get(creatureOrId)
  local id = type(creatureOrId) == "number" and creatureOrId or creatureOrId:getId()
  return self.trackedCreatures[id]
end

-- Check if creature is lured (far from spawn)
function CreatureTracker:isLured(creature)
  local tracking = self:get(creature)
  if not tracking then return false end
  
  return tracking.distanceFromSpawn >= self.safeDistance
end

-- Check if creature has likely respawned
function CreatureTracker:hasRespawned(creature)
  local tracking = self:get(creature)
  if not tracking then return false end
  
  local currentTime = getCurrentTime()
  local timeSinceLastSeen = currentTime - tracking.lastSeen
  
  return timeSinceLastSeen >= self.respawnThreshold
end

-- Check if creature returned to spawn
function CreatureTracker:returnedToSpawn(creature)
  local tracking = self:get(creature)
  if not tracking then return false end
  
  local currentPos = creature:getPosition()
  local distFromSpawn = calculateDistance(currentPos, tracking.spawnPos)
  
  -- Consider returned if within 2 tiles of spawn
  return distFromSpawn <= 2
end

-- Mark creature as dead
function CreatureTracker:markDead(creatureOrId)
  local id = type(creatureOrId) == "number" and creatureOrId or creatureOrId:getId()
  
  if self.trackedCreatures[id] then
    self.trackedCreatures[id].isDead = true
    self.trackedCreatures[id].deathTime = getCurrentTime()
  end
end

-- Remove tracking for a creature
function CreatureTracker:remove(creatureOrId)
  local id = type(creatureOrId) == "number" and creatureOrId or creatureOrId:getId()
  self.trackedCreatures[id] = nil
end

-- Get all creatures lured far from spawn
function CreatureTracker:getLuredCreatures()
  local lured = {}
  
  for id, tracking in pairs(self.trackedCreatures) do
    if not tracking.isDead and tracking.distanceFromSpawn >= self.safeDistance then
      table.insert(lured, tracking)
    end
  end
  
  return lured
end

-- Get creatures near their spawn
function CreatureTracker:getCreaturesNearSpawn(maxDistance)
  maxDistance = maxDistance or 3
  local nearSpawn = {}
  
  for id, tracking in pairs(self.trackedCreatures) do
    if not tracking.isDead and tracking.distanceFromSpawn <= maxDistance then
      table.insert(nearSpawn, tracking)
    end
  end
  
  return nearSpawn
end

-- Cleanup old/dead creature tracking
function CreatureTracker:cleanup()
  local currentTime = getCurrentTime()
  local removed = 0
  
  for id, tracking in pairs(self.trackedCreatures) do
    local shouldRemove = false
    
    -- Remove if dead for more than 30 seconds
    if tracking.isDead and (currentTime - (tracking.deathTime or 0)) > 30000 then
      shouldRemove = true
    end
    
    -- Remove if not seen for more than 60 seconds
    if (currentTime - tracking.lastSeen) > 60000 then
      shouldRemove = true
    end
    
    if shouldRemove then
      self.trackedCreatures[id] = nil
      removed = removed + 1
    end
  end
  
  self.lastCleanup = currentTime
  return removed
end

-- Periodic cleanup check
function CreatureTracker:update()
  local currentTime = getCurrentTime()
  
  if (currentTime - self.lastCleanup) >= self.cleanupInterval then
    return self:cleanup()
  end
  
  return 0
end

-- Get statistics
function CreatureTracker:getStats()
  local total = 0
  local alive = 0
  local dead = 0
  local lured = 0
  
  for id, tracking in pairs(self.trackedCreatures) do
    total = total + 1
    if tracking.isDead then
      dead = dead + 1
    else
      alive = alive + 1
      if tracking.distanceFromSpawn >= self.safeDistance then
        lured = lured + 1
      end
    end
  end
  
  return {
    total = total,
    alive = alive,
    dead = dead,
    lured = lured,
    safeDistance = self.safeDistance
  }
end

-- Reset all tracking
function CreatureTracker:reset()
  self.trackedCreatures = {}
  self.lastCleanup = getCurrentTime()
end

-- Set safe distance
function CreatureTracker:setSafeDistance(distance)
  self.safeDistance = distance
end

-- Export tracking data (for debugging)
function CreatureTracker:export()
  local data = {}
  for id, tracking in pairs(self.trackedCreatures) do
    table.insert(data, {
      id = tracking.id,
      name = tracking.name,
      spawnPos = tracking.spawnPos,
      distanceFromSpawn = tracking.distanceFromSpawn,
      isDead = tracking.isDead,
      lastSeen = tracking.lastSeen
    })
  end
  return data
end

return CreatureTracker
