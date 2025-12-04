--[[
  NexBot Priority Target Manager
  Intelligent target selection based on multiple factors
  
  Features:
  - Health-based priority
  - Distance-based priority
  - Threat level assessment
  - Kill potential calculation
  - Dynamic target switching
  
  Author: NexBot Team
  Version: 1.0.0
]]

local PriorityTargetManager = {
  targetScores = {},
  currentTarget = nil,
  targetSwitchThreshold = 0.3,  -- 30% score difference to switch
  enabled = false,
  lastEvaluation = 0
}

-- Priority factor weights
local PRIORITY_FACTORS = {
  health = 0.4,         -- Weight of target health percentage
  distance = 0.2,       -- Weight of proximity
  threat = 0.25,        -- Weight of damage potential
  killPotential = 0.15  -- Weight of kill probability
}

-- Create new instance
function PriorityTargetManager:new(options)
  options = options or {}
  
  local instance = {
    targetScores = {},
    currentTarget = nil,
    targetSwitchThreshold = options.switchThreshold or 0.3,
    enabled = false,
    lastEvaluation = 0,
    playerStats = options.playerStats or {},
    priorityFactors = options.factors or PRIORITY_FACTORS
  }
  
  setmetatable(instance, { __index = self })
  return instance
end

-- Get current time
local function getCurrentTime()
  return g_clock and g_clock.millis() or (now or 0)
end

-- Calculate distance between positions
local function calculateDistance(pos1, pos2)
  if not pos1 or not pos2 then return 20 end
  return math.sqrt(
    math.pow(pos1.x - pos2.x, 2) +
    math.pow(pos1.y - pos2.y, 2)
  )
end

-- Get player position
local function getPlayerPos()
  local localPlayer = player or (g_game and g_game.getLocalPlayer())
  if localPlayer then
    return localPlayer:getPosition()
  end
  return nil
end

-- Estimate creature damage per turn
function PriorityTargetManager:estimateDamage(creature)
  if not creature then return 0 end
  
  -- Try to get creature level
  local creatureLevel = 10
  if creature.getLevel then
    creatureLevel = creature:getLevel() or 10
  end
  
  -- Base damage estimation
  local baseDamage = creatureLevel * 2.5
  
  -- Adjust for creature type if available
  local name = creature:getName():lower()
  
  -- Known dangerous creatures get bonus
  local dangerousCreatures = {
    "demon", "dragon", "hydra", "behemoth", "wyrm", "serpent spawn"
  }
  
  for _, dangerous in ipairs(dangerousCreatures) do
    if name:find(dangerous) then
      baseDamage = baseDamage * 1.5
      break
    end
  end
  
  return baseDamage
end

-- Estimate time to kill a creature
function PriorityTargetManager:estimateTimeToKill(creature, playerStats)
  if not creature then return math.huge end
  
  local playerDamage = (playerStats and playerStats.avgDamage) or 50
  local creatureHealth = creature:getHealth and creature:getHealth() or 100
  
  return creatureHealth / math.max(playerDamage, 1)
end

-- Calculate priority score for a creature
function PriorityTargetManager:calculatePriority(creature, playerStats)
  if not creature then return 0 end
  
  local score = 0
  local factors = self.priorityFactors
  
  -- Health factor (lower health = higher priority)
  local health = creature:getHealth and creature:getHealth() or 100
  local maxHealth = creature:getMaxHealth and creature:getMaxHealth() or 100
  local healthPercentage = health / math.max(maxHealth, 1)
  score = score + (1 - healthPercentage) * factors.health
  
  -- Distance factor (closer = higher priority)
  local playerPos = getPlayerPos()
  local creaturePos = creature:getPosition()
  local distance = calculateDistance(playerPos, creaturePos)
  local maxDistance = 20
  score = score + (1 - math.min(distance / maxDistance, 1)) * factors.distance
  
  -- Threat factor (higher threat = higher priority)
  local damagePerTurn = self:estimateDamage(creature)
  score = score + math.min(damagePerTurn / 100, 1) * factors.threat
  
  -- Kill potential (faster kill = higher priority)
  local timeToKill = self:estimateTimeToKill(creature, playerStats)
  score = score + math.max(1 - (timeToKill / 10), 0) * factors.killPotential
  
  return score
end

-- Select optimal target from list
function PriorityTargetManager:selectOptimalTarget(creatures, playerStats)
  if not creatures or #creatures == 0 then
    return nil
  end
  
  playerStats = playerStats or self.playerStats
  
  local bestTarget = nil
  local bestScore = -1
  
  -- Evaluate all creatures
  for _, creature in ipairs(creatures) do
    local isDead = creature.isDead and creature:isDead()
    local canBeSeen = creature.canBeSeen and creature:canBeSeen()
    local isMonster = creature.isMonster and creature:isMonster()
    
    if not isDead and (canBeSeen == nil or canBeSeen) and (isMonster == nil or isMonster) then
      local score = self:calculatePriority(creature, playerStats)
      
      self.targetScores[creature:getId()] = {
        score = score,
        time = getCurrentTime()
      }
      
      if score > bestScore then
        bestScore = score
        bestTarget = creature
      end
    end
  end
  
  -- Check if should switch targets
  if self.currentTarget and bestTarget then
    local currentId = self.currentTarget:getId()
    local currentScore = 0
    
    if self.targetScores[currentId] then
      currentScore = self.targetScores[currentId].score
    else
      currentScore = self:calculatePriority(self.currentTarget, playerStats)
    end
    
    -- Only switch if score difference exceeds threshold
    if (bestScore - currentScore) > self.targetSwitchThreshold then
      self.currentTarget = bestTarget
    end
  else
    self.currentTarget = bestTarget
  end
  
  self.lastEvaluation = getCurrentTime()
  return self.currentTarget
end

-- Force set current target
function PriorityTargetManager:setTarget(creature)
  self.currentTarget = creature
end

-- Get current target
function PriorityTargetManager:getTarget()
  return self.currentTarget
end

-- Get score for a creature
function PriorityTargetManager:getScore(creatureOrId)
  local id = type(creatureOrId) == "number" and creatureOrId or creatureOrId:getId()
  local data = self.targetScores[id]
  return data and data.score or 0
end

-- Get all scores (for debugging)
function PriorityTargetManager:getAllScores()
  return self.targetScores
end

-- Clear target
function PriorityTargetManager:clearTarget()
  self.currentTarget = nil
end

-- Set priority factors
function PriorityTargetManager:setFactors(factors)
  for key, value in pairs(factors) do
    if self.priorityFactors[key] then
      self.priorityFactors[key] = value
    end
  end
  return self
end

-- Get priority factors
function PriorityTargetManager:getFactors()
  return self.priorityFactors
end

-- Set switch threshold
function PriorityTargetManager:setSwitchThreshold(threshold)
  self.targetSwitchThreshold = threshold
  return self
end

-- Set player stats
function PriorityTargetManager:setPlayerStats(stats)
  self.playerStats = stats
  return self
end

-- Update player stats from current player
function PriorityTargetManager:updatePlayerStats()
  local localPlayer = player or (g_game and g_game.getLocalPlayer())
  if not localPlayer then return end
  
  -- Calculate average damage based on equipment, skills, etc.
  local avgDamage = 50  -- Base damage
  
  -- Try to get skill level for better estimation
  local voc = localPlayer.getVocation and localPlayer:getVocation() or 0
  
  if voc == 1 or voc == 11 then  -- Knight
    avgDamage = 80
  elseif voc == 2 or voc == 12 then  -- Paladin
    avgDamage = 120
  elseif voc == 3 or voc == 13 then  -- Sorcerer
    avgDamage = 150
  elseif voc == 4 or voc == 14 then  -- Druid
    avgDamage = 100
  end
  
  -- Adjust for level
  local lvl = localPlayer.getLevel and localPlayer:getLevel() or 100
  avgDamage = avgDamage * (lvl / 100)
  
  self.playerStats = {
    avgDamage = avgDamage,
    level = lvl,
    vocation = voc
  }
  
  return self.playerStats
end

-- Enable manager
function PriorityTargetManager:enable()
  self.enabled = true
  self:updatePlayerStats()
  return self
end

-- Disable manager
function PriorityTargetManager:disable()
  self.enabled = false
  self:clearTarget()
  return self
end

-- Toggle manager
function PriorityTargetManager:toggle()
  if self.enabled then
    return self:disable()
  else
    return self:enable()
  end
end

-- Check if enabled
function PriorityTargetManager:isEnabled()
  return self.enabled
end

-- Get status
function PriorityTargetManager:getStatus()
  return {
    enabled = self.enabled,
    hasTarget = self.currentTarget ~= nil,
    targetName = self.currentTarget and self.currentTarget:getName() or "none",
    targetScore = self.currentTarget and self:getScore(self.currentTarget) or 0,
    lastEvaluation = self.lastEvaluation,
    trackedCreatures = #self.targetScores
  }
end

-- Cleanup old scores
function PriorityTargetManager:cleanup()
  local currentTime = getCurrentTime()
  local maxAge = 10000  -- 10 seconds
  
  for id, data in pairs(self.targetScores) do
    if (currentTime - data.time) > maxAge then
      self.targetScores[id] = nil
    end
  end
end

return PriorityTargetManager
