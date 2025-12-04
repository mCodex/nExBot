--[[
  nExBot Luring Manager
  Orchestrates smart luring behavior with patterns and tracking
  
  Features:
  - Multiple simultaneous lures
  - Pattern-based movement
  - Automatic respawn prevention
  - Integration with pathfinding
  
  Author: nExBot Team
  Version: 1.0.0
]]

local LuringPatterns = dofile("/nExBot/modules/luring/luring_patterns.lua")
local CreatureTracker = dofile("/nExBot/modules/luring/creature_tracker.lua")

local LuringManager = {
  patterns = nil,
  tracker = nil,
  activeLures = {},
  maxActiveLures = 3,
  enabled = false,
  updateInterval = 100,
  lastUpdate = 0
}

-- Create new LuringManager instance
function LuringManager:new(options)
  options = options or {}
  
  local instance = {
    patterns = LuringPatterns,
    tracker = CreatureTracker:new(options.trackerOptions),
    activeLures = {},
    maxActiveLures = options.maxLures or 3,
    enabled = false,
    updateInterval = options.updateInterval or 100,
    lastUpdate = 0,
    onLureComplete = options.onComplete,
    onLureStart = options.onStart,
    onLureFailed = options.onFailed
  }
  
  setmetatable(instance, { __index = self })
  return instance
end

-- Get current time
local function getCurrentTime()
  return g_clock and g_clock.millis() or (now or 0)
end

-- Start luring a creature
-- @param creature - Creature to lure
-- @param patternType string - Pattern type (circular, spiral, etc.)
-- @param options table - Pattern options
-- @return boolean - Whether luring started successfully
function LuringManager:startLuring(creature, patternType, options)
  if not creature or not self.enabled then
    return false
  end
  
  local id = creature:getId()
  
  -- Check if already luring this creature
  if self.activeLures[id] then
    return false
  end
  
  -- Check max lures
  local activeCount = 0
  for _ in pairs(self.activeLures) do
    activeCount = activeCount + 1
  end
  
  if activeCount >= self.maxActiveLures then
    if self.onLureFailed then
      self.onLureFailed(creature, "max_lures_reached")
    end
    return false
  end
  
  -- Generate waypoints
  options = options or {}
  local centerPos = creature:getPosition()
  local waypoints = self.patterns:generate(patternType, centerPos, {
    radius = options.radius or 6,
    density = options.density or 12,
    validate = true
  })
  
  if #waypoints == 0 then
    if self.onLureFailed then
      self.onLureFailed(creature, "no_valid_waypoints")
    end
    return false
  end
  
  -- Create lure entry
  local currentTime = getCurrentTime()
  self.activeLures[id] = {
    creatureId = id,
    creatureName = creature:getName(),
    waypoints = waypoints,
    currentWaypoint = 1,
    nextMoveTime = currentTime + 500,
    patternType = patternType,
    startTime = currentTime,
    centerPos = centerPos,
    options = options,
    state = "active"
  }
  
  -- Start tracking
  self.tracker:track(creature)
  
  if self.onLureStart then
    self.onLureStart(creature, patternType)
  end
  
  return true
end

-- Stop luring a creature
function LuringManager:stopLuring(creatureOrId)
  local id = type(creatureOrId) == "number" and creatureOrId or creatureOrId:getId()
  
  local lure = self.activeLures[id]
  if lure then
    lure.state = "stopped"
    self.activeLures[id] = nil
    self.tracker:remove(id)
    
    if self.onLureComplete then
      self.onLureComplete(id, "stopped")
    end
    
    return true
  end
  
  return false
end

-- Stop all lures
function LuringManager:stopAllLures()
  for id, _ in pairs(self.activeLures) do
    self:stopLuring(id)
  end
  self.activeLures = {}
  self.tracker:reset()
end

-- Update all active lures
function LuringManager:update()
  if not self.enabled then return end
  
  local currentTime = getCurrentTime()
  
  -- Throttle updates
  if (currentTime - self.lastUpdate) < self.updateInterval then
    return
  end
  self.lastUpdate = currentTime
  
  -- Update tracker
  self.tracker:update()
  
  -- Process each active lure
  for id, lure in pairs(self.activeLures) do
    self:updateLure(id, lure, currentTime)
  end
end

-- Update a single lure
function LuringManager:updateLure(id, lure, currentTime)
  -- Get creature
  local creature = g_game and g_game.getCreatureById(id)
  
  if not creature or creature:isDead() then
    self:stopLuring(id)
    if self.onLureComplete then
      self.onLureComplete(id, creature and "dead" or "lost")
    end
    return
  end
  
  -- Update tracker
  self.tracker:track(creature)
  
  -- Check for respawn
  if self.tracker:hasRespawned(creature) then
    self:stopLuring(id)
    if self.onLureComplete then
      self.onLureComplete(id, "respawned")
    end
    return
  end
  
  -- Check if time to move
  if currentTime < lure.nextMoveTime then
    return
  end
  
  -- Get next waypoint
  local waypoint = lure.waypoints[lure.currentWaypoint]
  if not waypoint then
    -- Pattern complete, loop back
    lure.currentWaypoint = 1
    waypoint = lure.waypoints[1]
  end
  
  -- Get player
  local localPlayer = player or (g_game and g_game.getLocalPlayer())
  if not localPlayer then return end
  
  local playerPos = localPlayer:getPosition()
  
  -- Calculate distance to waypoint
  local distToWaypoint = math.sqrt(
    math.pow(playerPos.x - waypoint.x, 2) +
    math.pow(playerPos.y - waypoint.y, 2)
  )
  
  -- If close to waypoint, move to next
  if distToWaypoint <= 1 then
    lure.currentWaypoint = lure.currentWaypoint + 1
    if lure.currentWaypoint > #lure.waypoints then
      lure.currentWaypoint = 1
    end
    waypoint = lure.waypoints[lure.currentWaypoint]
    lure.nextMoveTime = currentTime + (lure.options.moveDelay or 300)
  end
  
  -- Walk to waypoint
  if autoWalk then
    autoWalk(waypoint, 20, {
      ignoreNonPathable = true,
      precision = 1
    })
    lure.nextMoveTime = currentTime + (lure.options.moveDelay or 500)
  end
end

-- Check if creature is being lured
function LuringManager:isLuring(creatureOrId)
  local id = type(creatureOrId) == "number" and creatureOrId or creatureOrId:getId()
  return self.activeLures[id] ~= nil
end

-- Get lure status
function LuringManager:getLureStatus(creatureOrId)
  local id = type(creatureOrId) == "number" and creatureOrId or creatureOrId:getId()
  return self.activeLures[id]
end

-- Get all active lures
function LuringManager:getActiveLures()
  local lures = {}
  for id, lure in pairs(self.activeLures) do
    table.insert(lures, {
      id = id,
      name = lure.creatureName,
      pattern = lure.patternType,
      waypoint = lure.currentWaypoint,
      totalWaypoints = #lure.waypoints,
      startTime = lure.startTime
    })
  end
  return lures
end

-- Enable luring
function LuringManager:enable()
  self.enabled = true
  return self
end

-- Disable luring
function LuringManager:disable()
  self.enabled = false
  self:stopAllLures()
  return self
end

-- Toggle luring
function LuringManager:toggle()
  if self.enabled then
    return self:disable()
  else
    return self:enable()
  end
end

-- Check if enabled
function LuringManager:isEnabled()
  return self.enabled
end

-- Set max lures
function LuringManager:setMaxLures(count)
  self.maxActiveLures = count
  return self
end

-- Get statistics
function LuringManager:getStats()
  local activeCount = 0
  for _ in pairs(self.activeLures) do
    activeCount = activeCount + 1
  end
  
  return {
    enabled = self.enabled,
    activeLures = activeCount,
    maxLures = self.maxActiveLures,
    trackerStats = self.tracker:getStats()
  }
end

-- Create the main update macro
function LuringManager:createMacro(interval)
  interval = interval or 100
  
  local self_ref = self
  macro(interval, function()
    self_ref:update()
  end)
end

return LuringManager
