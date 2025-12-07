--[[
  Smart Hunting Analytics Module
  
  Features:
  1. Smart Supply Prediction - Tracks consumption and predicts needed supplies
  2. Adaptive Route Optimizer - Identifies cold spots and optimizes hunting paths
  3. Dynamic Lure Threshold - Auto-adjusts based on damage taken
  4. Smart Refill Decision - Calculates if one more round is possible
  5. Auto-Learning Monster Database - Tracks damage per monster type
  
  All data is stored in storage.smartHunt and persists across sessions.
]]

-- Initialize storage namespace
if not storage.smartHunt then
  storage.smartHunt = {
    -- Supply tracking
    supplies = {
      sessions = {},           -- Historical session data
      currentSession = nil,    -- Current session tracking
      consumptionRates = {},   -- Item ID -> per-minute consumption
    },
    
    -- Route optimization
    routes = {
      waypointStats = {},      -- Label -> {kills, xp, time, visits}
      coldSpots = {},          -- Labels with low activity
    },
    
    -- Lure management
    lure = {
      damageHistory = {},      -- Recent damage taken samples
      avgDamagePerCreature = 0,
      maxSafeCreatures = 8,
      lastAdjustment = 0,
    },
    
    -- Monster database
    monsters = {},             -- Name -> {damage, kills, xpEach, dangerScore}
    
    -- Session timing
    roundTimes = {},           -- Array of round durations
    avgRoundTime = 0,
  }
end

local SmartHunt = {}
nExBot.SmartHunt = SmartHunt

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function getSessionTime()
  if not storage.smartHunt.supplies.currentSession then
    return 0
  end
  return (now - storage.smartHunt.supplies.currentSession.startTime) / 1000 / 60  -- in minutes
end

local function calculateAverage(tbl)
  if not tbl or #tbl == 0 then return 0 end
  local sum = 0
  for _, v in ipairs(tbl) do
    sum = sum + v
  end
  return sum / #tbl
end

-- ============================================================================
-- 1. SMART SUPPLY PREDICTION SYSTEM
-- ============================================================================

SmartHunt.Supplies = {}

-- Start tracking a new session
function SmartHunt.Supplies.startSession()
  local session = {
    startTime = now,
    startSupplies = {},
    endSupplies = {},
    consumptionPerMinute = {},
  }
  
  -- Record starting supplies
  local supplyData = Supplies and Supplies.getItemsData and Supplies.getItemsData() or {}
  for id, data in pairs(supplyData) do
    local count = player:getItemsCount(tonumber(id))
    session.startSupplies[id] = count
  end
  
  storage.smartHunt.supplies.currentSession = session
  print("[SmartHunt] Session started - tracking supply consumption")
end

-- Update consumption rates (called periodically)
function SmartHunt.Supplies.updateConsumption()
  local session = storage.smartHunt.supplies.currentSession
  if not session then return end
  
  local elapsed = getSessionTime()
  if elapsed < 1 then return end  -- Need at least 1 minute of data
  
  local supplyData = Supplies and Supplies.getItemsData and Supplies.getItemsData() or {}
  for id, data in pairs(supplyData) do
    local startCount = session.startSupplies[id] or 0
    local currentCount = player:getItemsCount(tonumber(id))
    local consumed = startCount - currentCount
    
    if consumed > 0 then
      local perMinute = consumed / elapsed
      storage.smartHunt.supplies.consumptionRates[id] = perMinute
      session.consumptionPerMinute[id] = perMinute
    end
  end
end

-- Predict supplies needed for X minutes of hunting
function SmartHunt.Supplies.predictNeeded(minutes)
  minutes = minutes or 60  -- Default 1 hour
  local predictions = {}
  
  for id, rate in pairs(storage.smartHunt.supplies.consumptionRates) do
    local needed = math.ceil(rate * minutes * 1.1)  -- 10% safety margin
    predictions[tonumber(id)] = needed
  end
  
  return predictions
end

-- Get optimal supply amounts based on history
function SmartHunt.Supplies.getOptimalAmounts()
  local avgRoundTime = storage.smartHunt.avgRoundTime or 30  -- Default 30 min
  local targetRounds = storage.extras and storage.extras.huntRoutes or 50
  local huntDuration = avgRoundTime * targetRounds
  
  return SmartHunt.Supplies.predictNeeded(huntDuration)
end

-- Check if we have enough supplies for one more round
function SmartHunt.Supplies.canDoOneMoreRound()
  local avgRoundTime = storage.smartHunt.avgRoundTime or 30
  local rates = storage.smartHunt.supplies.consumptionRates
  
  for id, rate in pairs(rates) do
    local needed = math.ceil(rate * avgRoundTime)
    local current = player:getItemsCount(tonumber(id))
    
    if current < needed then
      return false, tonumber(id), current, needed
    end
  end
  
  return true
end

-- ============================================================================
-- 2. ADAPTIVE HUNTING ROUTE OPTIMIZER
-- ============================================================================

SmartHunt.Routes = {}

local currentWaypointLabel = nil
local waypointEnterTime = 0
local waypointKills = 0
local waypointXP = 0

-- Called when entering a new waypoint/label
function SmartHunt.Routes.enterWaypoint(label)
  -- Save stats from previous waypoint
  if currentWaypointLabel and waypointEnterTime > 0 then
    SmartHunt.Routes.exitWaypoint()
  end
  
  currentWaypointLabel = label
  waypointEnterTime = now
  waypointKills = 0
  waypointXP = exp()
end

-- Called when leaving a waypoint
function SmartHunt.Routes.exitWaypoint()
  if not currentWaypointLabel then return end
  
  local timeSpent = (now - waypointEnterTime) / 1000  -- seconds
  local xpGained = exp() - waypointXP
  
  local stats = storage.smartHunt.routes.waypointStats[currentWaypointLabel] or {
    totalKills = 0,
    totalXP = 0,
    totalTime = 0,
    visits = 0,
    avgKillsPerVisit = 0,
    avgXPPerMinute = 0,
  }
  
  stats.totalKills = stats.totalKills + waypointKills
  stats.totalXP = stats.totalXP + xpGained
  stats.totalTime = stats.totalTime + timeSpent
  stats.visits = stats.visits + 1
  stats.avgKillsPerVisit = stats.totalKills / stats.visits
  stats.avgXPPerMinute = stats.totalTime > 0 and (stats.totalXP / (stats.totalTime / 60)) or 0
  
  storage.smartHunt.routes.waypointStats[currentWaypointLabel] = stats
  
  -- Check if this is a cold spot (low XP/min compared to average)
  SmartHunt.Routes.updateColdSpots()
  
  currentWaypointLabel = nil
end

-- Record a kill at current waypoint
function SmartHunt.Routes.recordKill()
  waypointKills = waypointKills + 1
end

-- Identify waypoints with low activity
function SmartHunt.Routes.updateColdSpots()
  local allStats = storage.smartHunt.routes.waypointStats
  local xpRates = {}
  
  for label, stats in pairs(allStats) do
    if stats.visits >= 3 then  -- Need enough data
      table.insert(xpRates, stats.avgXPPerMinute)
    end
  end
  
  if #xpRates < 3 then return end  -- Need enough waypoints to compare
  
  local avgXPRate = calculateAverage(xpRates)
  local coldThreshold = avgXPRate * 0.5  -- 50% below average = cold spot
  
  storage.smartHunt.routes.coldSpots = {}
  for label, stats in pairs(allStats) do
    if stats.visits >= 3 and stats.avgXPPerMinute < coldThreshold then
      storage.smartHunt.routes.coldSpots[label] = {
        xpPerMin = stats.avgXPPerMinute,
        avgXP = avgXPRate,
        efficiency = (stats.avgXPPerMinute / avgXPRate) * 100
      }
    end
  end
end

-- Check if current waypoint is a cold spot
function SmartHunt.Routes.isColdSpot(label)
  return storage.smartHunt.routes.coldSpots[label] ~= nil
end

-- Get list of cold spots
function SmartHunt.Routes.getColdSpots()
  return storage.smartHunt.routes.coldSpots
end

-- ============================================================================
-- 3. DYNAMIC LURE THRESHOLD
-- ============================================================================

SmartHunt.Lure = {}

local lastHP = 0
local damageWindow = {}  -- Recent damage samples
local DAMAGE_WINDOW_SIZE = 20

-- Track damage taken
function SmartHunt.Lure.trackDamage()
  local currentHP = player:getHealth()
  
  if lastHP > 0 and currentHP < lastHP then
    local damage = lastHP - currentHP
    
    table.insert(damageWindow, {
      damage = damage,
      time = now,
      creatures = SmartHunt.Lure.getCreatureCount()
    })
    
    -- Keep window size limited
    while #damageWindow > DAMAGE_WINDOW_SIZE do
      table.remove(damageWindow, 1)
    end
  end
  
  lastHP = currentHP
end

-- Get creature count around player
function SmartHunt.Lure.getCreatureCount()
  local pos = player:getPosition()
  local creatures = g_map.getSpectatorsInRange(pos, false, 5, 5)
  local count = 0
  
  for _, c in ipairs(creatures) do
    if c:isMonster() and not c:isDead() then
      count = count + 1
    end
  end
  
  return count
end

-- Calculate average damage per creature
function SmartHunt.Lure.calculateDamagePerCreature()
  if #damageWindow < 5 then return 0 end
  
  local totalDamage = 0
  local totalCreatures = 0
  
  for _, sample in ipairs(damageWindow) do
    totalDamage = totalDamage + sample.damage
    totalCreatures = totalCreatures + sample.creatures
  end
  
  if totalCreatures == 0 then return 0 end
  
  return totalDamage / totalCreatures
end

-- Get recommended max creatures to lure
function SmartHunt.Lure.getRecommendedMax()
  local maxHP = player:getMaxHealth()
  local avgDamagePerCreature = SmartHunt.Lure.calculateDamagePerCreature()
  
  if avgDamagePerCreature <= 0 then
    return storage.smartHunt.lure.maxSafeCreatures
  end
  
  -- Calculate how many creatures we can handle
  -- Target: take no more than 40% HP per "hit wave"
  local safeHPLoss = maxHP * 0.4
  local recommended = math.floor(safeHPLoss / avgDamagePerCreature)
  
  -- Clamp between 1 and 15
  recommended = math.max(1, math.min(15, recommended))
  
  -- Only adjust if significantly different
  local current = storage.smartHunt.lure.maxSafeCreatures
  if math.abs(recommended - current) >= 2 then
    storage.smartHunt.lure.maxSafeCreatures = recommended
    storage.smartHunt.lure.lastAdjustment = now
    print("[SmartHunt] Lure threshold adjusted: " .. current .. " -> " .. recommended)
  end
  
  return storage.smartHunt.lure.maxSafeCreatures
end

-- Check if we're taking too much damage
function SmartHunt.Lure.isDangerousLure()
  local creatureCount = SmartHunt.Lure.getCreatureCount()
  local maxSafe = storage.smartHunt.lure.maxSafeCreatures
  
  return creatureCount > maxSafe
end

-- ============================================================================
-- 4. SMART REFILL DECISION ENGINE
-- ============================================================================

SmartHunt.Refill = {}

-- Record round time
function SmartHunt.Refill.recordRound(seconds)
  table.insert(storage.smartHunt.roundTimes, seconds)
  
  -- Keep last 20 rounds
  while #storage.smartHunt.roundTimes > 20 do
    table.remove(storage.smartHunt.roundTimes, 1)
  end
  
  -- Update average
  storage.smartHunt.avgRoundTime = calculateAverage(storage.smartHunt.roundTimes) / 60  -- in minutes
end

-- Check if we can complete one more round
function SmartHunt.Refill.canCompleteRound()
  local canDo, itemId, current, needed = SmartHunt.Supplies.canDoOneMoreRound()
  
  if not canDo then
    return false, string.format(
      "Not enough supplies: Item %d has %d, needs %d for one round",
      itemId, current, needed
    )
  end
  
  -- Check stamina if enabled
  local supplyInfo = Supplies and Supplies.getAdditionalData and Supplies.getAdditionalData() or {}
  if supplyInfo.stamina and supplyInfo.stamina.enabled then
    local avgRoundTime = storage.smartHunt.avgRoundTime or 30
    local staminaNeeded = avgRoundTime  -- 1 min hunting = 1 min stamina
    local currentStamina = stamina()
    local minStamina = tonumber(supplyInfo.stamina.value) or 840
    
    if currentStamina - staminaNeeded < minStamina then
      return false, "Stamina would drop below threshold"
    end
  end
  
  return true, "Can complete one more round"
end

-- Get recommendation
function SmartHunt.Refill.getRecommendation()
  local canDo, reason = SmartHunt.Refill.canCompleteRound()
  
  return {
    canContinue = canDo,
    reason = reason,
    avgRoundTime = storage.smartHunt.avgRoundTime or 0,
    roundsCompleted = #storage.smartHunt.roundTimes
  }
end

-- ============================================================================
-- 5. AUTO-LEARNING MONSTER DATABASE
-- ============================================================================

SmartHunt.Monsters = {}

-- Record damage dealt to monster
function SmartHunt.Monsters.recordDamage(monsterName, damage)
  local data = storage.smartHunt.monsters[monsterName] or {
    totalDamageDealt = 0,
    totalDamageTaken = 0,
    kills = 0,
    xpTotal = 0,
    encounters = 0,
    avgDamageToKill = 0,
    dangerScore = 50,  -- Default medium danger
  }
  
  data.totalDamageDealt = data.totalDamageDealt + damage
  data.encounters = data.encounters + 1
  
  storage.smartHunt.monsters[monsterName] = data
end

-- Record damage taken from monster
function SmartHunt.Monsters.recordDamageTaken(monsterName, damage)
  local data = storage.smartHunt.monsters[monsterName] or {
    totalDamageDealt = 0,
    totalDamageTaken = 0,
    kills = 0,
    xpTotal = 0,
    encounters = 0,
    avgDamageToKill = 0,
    dangerScore = 50,
  }
  
  data.totalDamageTaken = data.totalDamageTaken + damage
  
  -- Update danger score based on damage taken
  SmartHunt.Monsters.updateDangerScore(monsterName)
  
  storage.smartHunt.monsters[monsterName] = data
end

-- Record a kill
function SmartHunt.Monsters.recordKill(monsterName, xpGained)
  local data = storage.smartHunt.monsters[monsterName] or {
    totalDamageDealt = 0,
    totalDamageTaken = 0,
    kills = 0,
    xpTotal = 0,
    encounters = 0,
    avgDamageToKill = 0,
    dangerScore = 50,
  }
  
  data.kills = data.kills + 1
  data.xpTotal = data.xpTotal + (xpGained or 0)
  
  if data.kills > 0 then
    data.avgDamageToKill = data.totalDamageDealt / data.kills
    data.avgXP = data.xpTotal / data.kills
  end
  
  -- Record kill for route optimization
  SmartHunt.Routes.recordKill()
  
  storage.smartHunt.monsters[monsterName] = data
end

-- Calculate danger score (0-100)
function SmartHunt.Monsters.updateDangerScore(monsterName)
  local data = storage.smartHunt.monsters[monsterName]
  if not data or data.encounters < 3 then return end
  
  local avgDamageTaken = data.totalDamageTaken / data.encounters
  local maxHP = player:getMaxHealth()
  
  -- Danger based on % of max HP per encounter
  local dangerPercent = (avgDamageTaken / maxHP) * 100
  
  -- Scale to 0-100 (clamp)
  local score = math.min(100, math.max(0, dangerPercent * 2))
  
  data.dangerScore = math.floor(score)
end

-- Get monster stats
function SmartHunt.Monsters.getStats(monsterName)
  return storage.smartHunt.monsters[monsterName]
end

-- Get all monsters sorted by danger
function SmartHunt.Monsters.getDangerousMonsters()
  local sorted = {}
  
  for name, data in pairs(storage.smartHunt.monsters) do
    if data.encounters >= 3 then
      table.insert(sorted, {name = name, data = data})
    end
  end
  
  table.sort(sorted, function(a, b)
    return a.data.dangerScore > b.data.dangerScore
  end)
  
  return sorted
end

-- Suggest priority for TargetBot
function SmartHunt.Monsters.suggestPriority(monsterName)
  local data = storage.smartHunt.monsters[monsterName]
  if not data or data.kills < 5 then return 0 end
  
  -- Priority based on:
  -- - Lower HP = higher priority (easier to kill)
  -- - Higher danger = higher priority (kill fast)
  -- - Lower XP = lower priority
  
  local killEfficiency = data.avgXP and (data.avgXP / math.max(1, data.avgDamageToKill)) or 0
  local dangerFactor = data.dangerScore / 100
  
  -- Combine factors
  local priority = (killEfficiency * 0.5) + (dangerFactor * 50)
  
  return math.floor(priority)
end

-- ============================================================================
-- EVENT HOOKS
-- ============================================================================

-- Track monster deaths
onCreatureHealthPercentChange(function(creature, healthPercent)
  if creature:isMonster() and healthPercent == 0 then
    local name = creature:getName()
    -- We don't know exact XP, so just record the kill
    SmartHunt.Monsters.recordKill(name, 0)
  end
end)

-- Track damage taken
onPlayerHealthChange(function(healthPercent)
  SmartHunt.Lure.trackDamage()
end)

-- Periodic supply tracking
macro(5000, "SmartHunt Supply Tracker", function()
  if CaveBot and CaveBot.isOn() then
    -- Auto-start session if not already started
    if not SmartHunt.Supplies.sessionStart then
      SmartHunt.Supplies.startSession()
    end
    SmartHunt.Supplies.updateConsumption()
  end
end)

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Print summary to console
function SmartHunt.printSummary()
  print("=== SmartHunt Summary ===")
  
  -- Supply predictions
  local optimal = SmartHunt.Supplies.getOptimalAmounts()
  print("Optimal Supplies for next hunt:")
  for id, amount in pairs(optimal) do
    print("  Item " .. id .. ": " .. amount)
  end
  
  -- Cold spots
  local coldSpots = SmartHunt.Routes.getColdSpots()
  if next(coldSpots) then
    print("Cold Spots (consider skipping):")
    for label, data in pairs(coldSpots) do
      print("  " .. label .. ": " .. math.floor(data.efficiency) .. "% efficiency")
    end
  end
  
  -- Lure recommendation
  local maxLure = storage.smartHunt.lure.maxSafeCreatures
  print("Recommended max lure: " .. maxLure .. " creatures")
  
  -- Round info
  local rec = SmartHunt.Refill.getRecommendation()
  print("Avg round time: " .. math.floor(rec.avgRoundTime) .. " min")
  print("Can continue: " .. (rec.canContinue and "Yes" or "No") .. " - " .. rec.reason)
  
  -- Dangerous monsters
  local dangerous = SmartHunt.Monsters.getDangerousMonsters()
  if #dangerous > 0 then
    print("Most dangerous monsters:")
    for i = 1, math.min(5, #dangerous) do
      local m = dangerous[i]
      print("  " .. m.name .. ": Danger " .. m.data.dangerScore .. "/100")
    end
  end
end

print("[SmartHunt] Smart Hunting Analytics loaded")
