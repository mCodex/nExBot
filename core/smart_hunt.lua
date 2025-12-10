--[[
  SmartHunt Analytics Module v4.0 (Advanced AI)
  
  Features:
  - Statistical analysis (standard deviation, trends, confidence)
  - Trend tracking with rolling window analysis
  - Weighted scoring with time-decay
  - Confidence-based insights prioritization
  - Advanced metrics: efficiency index, survivability index, combat uptime
  
  OTClient Functions: getLevel, getLevelPercent, getStamina, getSoul,
  getBlessings, getSpeed, getSkillLevel/Percent, getMagicLevel
]]

setDefaultTab("Main")

-- ============================================================================
-- CONSTANTS & CONFIGURATION
-- ============================================================================

local SEVERITY = { INFO = "INFO", TIP = "TIP", WARNING = "WARN", CRITICAL = "CRIT" }

local SKILL_NAMES = {
  [0] = "Fist", [1] = "Club", [2] = "Sword", [3] = "Axe",
  [4] = "Distance", [5] = "Shielding", [6] = "Fishing", [7] = "Magic Level"
}

local CONDITION_MAP = {
  { check = "isPoisioned", key = "timePoisoned", name = "poisoned" },
  { check = "isBurning", key = "timeBurning", name = "burning" },
  { check = "isParalyzed", key = "timeParalyzed", name = "paralyzed" },
  { check = "hasManaShield", key = "timeManaShield", name = "manaShield" },
  { check = "hasHaste", key = "timeHasted", name = "hasted" },
  { check = "isInFight", key = "timeInCombat", name = "inCombat" }
}

-- ============================================================================
-- PURE UTILITY FUNCTIONS
-- ============================================================================

-- Safe get with default value
local function safeGet(fn, default)
  if type(fn) == "function" then
    local ok, result = pcall(fn)
    return ok and result or default
  end
  return default
end

-- Safe player method call (supports optional arguments)
local function playerGet(method, default, ...)
  if player and player[method] then
    local ok, result = pcall(player[method], player, ...)
    if ok then return result or default end
  end
  return default
end

-- Format number with thousands separator (pure function)
local function formatNum(n)
  if not n or n == 0 then return "0" end
  return tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- Format duration in ms to readable string (pure function)
local function formatDuration(ms)
  if not ms or ms <= 0 then return "0m" end
  local mins = math.floor(ms / 60000)
  local hrs = math.floor(mins / 60)
  return hrs > 0 and string.format("%dh %dm", hrs, mins % 60) or string.format("%dm", mins)
end

-- Calculate per-hour rate (pure function)
local function perHour(value, elapsedMs)
  return (elapsedMs and elapsedMs > 0) and (value / (elapsedMs / 3600000)) or 0
end

-- XP formula for level (pure function) 
local function expForLevel(lvl)
  return math.floor((50 * lvl^3) / 3 - 100 * lvl^2 + (850 * lvl) / 3 - 200)
end

-- Check if table has data (pure function)
local function hasData(tbl)
  if not tbl then return false end
  return next(tbl) ~= nil
end

-- Clamp value between min and max (pure function)
local function clamp(value, min, max)
  return math.max(min, math.min(max, value))
end

-- ============================================================================
-- PLAYER DATA ACCESSORS (Single Responsibility)
-- ============================================================================

local Player = {}

function Player.level() return safeGet(lvl, 0) or safeGet(level, 1) end
function Player.exp() return safeGet(exp, 0) end
function Player.hp() return safeGet(hp, 0), safeGet(maxhp, 1) end
function Player.mana() return safeGet(mana, 0), safeGet(maxmana, 1) end
function Player.cap() return safeGet(freecap, 0) or playerGet("getFreeCapacity", 0) end
function Player.stamina() return playerGet("getStamina", 0) or safeGet(stamina, 0) end
function Player.soul() return safeGet(soul, 0) or playerGet("getSoul", 0) end
function Player.speed() return safeGet(speed, 0) or playerGet("getSpeed", 0) end
function Player.blessings() return safeGet(bless, 0) or playerGet("getBlessings", 0) end
function Player.mlevel() return safeGet(mlevel, 0) or playerGet("getMagicLevel", 0) end
function Player.isPremium() return playerGet("isPremium", false) end

function Player.staminaInfo()
  local mins = Player.stamina()
  local hrs = mins / 60
  local status, bonus, warning = "Normal", 0, 0
  
  if hrs >= 39 then status, bonus = "Green Bonus", 50
  elseif hrs < 14 then status, bonus, warning = hrs >= 1 and "Orange Penalty" or "DEPLETED", hrs >= 1 and -50 or -100, hrs >= 1 and 1 or 2
  end
  
  return { minutes = mins, hours = hrs, status = status, bonusPercent = bonus, warningLevel = warning,
           greenRemaining = math.max(0, hrs - 39), untilOrange = math.max(0, hrs - 14) }
end

function Player.skill(id)
  return {
    current = playerGet("getSkillLevel", 0, id),
    base = playerGet("getSkillBaseLevel", 0, id),
    percent = playerGet("getSkillLevelPercent", 0, id),
    name = SKILL_NAMES[id] or ("Skill " .. id)
  }
end

function Player.magicLevel()
  return {
    current = Player.mlevel(),
    base = playerGet("getBaseMagicLevel", 0) or Player.mlevel(),
    percent = playerGet("getMagicLevelPercent", 0)
  }
end

function Player.conditions()
  local result = {}
  -- Direct function references instead of _G lookup (OTClient sandbox may not have _G)
  local conditionChecks = {
    { fn = isPoisioned, name = "poisoned" },
    { fn = isBurning, name = "burning" },
    { fn = isParalyzed, name = "paralyzed" },
    { fn = hasManaShield, name = "manaShield" },
    { fn = hasHaste, name = "hasted" },
    { fn = isInFight, name = "inCombat" }
  }
  
  for _, c in ipairs(conditionChecks) do
    if c.fn and type(c.fn) == "function" then
      local ok, val = pcall(c.fn)
      if ok and val then result[c.name] = true end
    end
  end
  return result
end

function Player.levelProgress()
  local lvl = Player.level()
  local currentXp = Player.exp()
  local xpCurrent = expForLevel(lvl)
  local xpNext = expForLevel(lvl + 1)
  local xpNeeded = xpNext - xpCurrent
  local pct = playerGet("getLevelPercent", 0) or ((xpNeeded > 0) and ((currentXp - xpCurrent) / xpNeeded * 100) or 0)
  return { level = lvl, percent = pct, xpNeeded = xpNeeded, xpRemaining = xpNext - currentXp }
end

-- ============================================================================
-- STORAGE & SESSION (Single Responsibility)
-- ============================================================================

local DEFAULT_METRICS = {
  tilesWalked = 0, kills = 0, spellsCast = 0, potionsUsed = 0, runesUsed = 0,
  damageTaken = 0, healingDone = 0, deathCount = 0, nearDeathCount = 0,
  timePoisoned = 0, timeBurning = 0, timeParalyzed = 0, timeManaShield = 0,
  timeHasted = 0, greenStaminaTime = 0, orangeStaminaTime = 0, timeInCombat = 0
}

local DEFAULT_PEAKS = { maxXpPerHour = 0, maxKillsPerHour = 0, lowestHpPercent = 100, highestDamageHit = 0, maxSpeed = 0 }

local function ensureDefaults(tbl, defaults)
  for k, v in pairs(defaults) do tbl[k] = tbl[k] or v end
  return tbl
end

local function initStorage()
  storage.analytics = storage.analytics or { session = {}, metrics = {}, monsters = {}, peakStats = {} }
  local a = storage.analytics
  ensureDefaults(a.metrics, DEFAULT_METRICS)
  ensureDefaults(a.peakStats, DEFAULT_PEAKS)
  return a
end

local analytics = initStorage()

local function getElapsed()
  return analytics.session.active and (now - analytics.session.startTime) or 0
end

local function isSessionActive()
  return analytics.session.active == true
end

local function captureSkills()
  local skills = {}
  for id = 0, 6 do skills[id] = Player.skill(id).current end
  skills[7] = Player.mlevel()
  return skills
end

local function startSession()
  local stamInfo = Player.staminaInfo()
  local levelInfo = Player.levelProgress()
  
  analytics.session = {
    startTime = now, startXp = Player.exp(), startSkills = captureSkills(),
    startCap = Player.cap(), startStamina = stamInfo.minutes,
    startLevelPercent = levelInfo.percent, startSpeed = Player.speed(),
    active = true
  }
  
  for k, v in pairs(DEFAULT_METRICS) do analytics.metrics[k] = v end
  for k, v in pairs(DEFAULT_PEAKS) do analytics.peakStats[k] = v end
  analytics.monsters = {}
  analytics.peakStats.maxSpeed = Player.speed()
  
  if HealBot and HealBot.resetAnalytics then HealBot.resetAnalytics() end
  if AttackBot and AttackBot.resetAnalytics then AttackBot.resetAnalytics() end
  if EventBus then EventBus.emit("analytics:session:start") end
end

local function endSession()
  analytics.session.active = false
  if EventBus then EventBus.emit("analytics:session:end") end
end

-- ============================================================================
-- EVENT HANDLERS (Metrics Collection)
-- ============================================================================

onWalk(function(creature)
  if creature == player and isSessionActive() then
    analytics.metrics.tilesWalked = analytics.metrics.tilesWalked + 1
  end
end)

onCreatureHealthPercentChange(function(creature, healthPercent)
  if isSessionActive() and creature:isMonster() and healthPercent == 0 then
    analytics.metrics.kills = analytics.metrics.kills + 1
    local name = creature:getName()
    analytics.monsters[name] = (analytics.monsters[name] or 0) + 1
  end
end)

onSpellCooldown(function(_, duration)
  if isSessionActive() and duration > 0 then
    analytics.metrics.spellsCast = analytics.metrics.spellsCast + 1
  end
end)

local lastHP, lastHpPercent = 0, 100
onPlayerHealthChange(function(healthPercent)
  if not isSessionActive() then return end
  local currentHP = safeGet(hp, 0)
  
  if lastHP > 0 then
    local diff = currentHP - lastHP
    if diff < 0 then
      analytics.metrics.damageTaken = analytics.metrics.damageTaken + math.abs(diff)
      if math.abs(diff) > analytics.peakStats.highestDamageHit then
        analytics.peakStats.highestDamageHit = math.abs(diff)
      end
    elseif diff > 0 then
      analytics.metrics.healingDone = analytics.metrics.healingDone + diff
    end
  end
  
  if healthPercent < analytics.peakStats.lowestHpPercent then
    analytics.peakStats.lowestHpPercent = healthPercent
  end
  if lastHpPercent >= 20 and healthPercent < 20 then
    analytics.metrics.nearDeathCount = analytics.metrics.nearDeathCount + 1
  end
  if lastHpPercent > 5 and healthPercent <= 0 then
    analytics.metrics.deathCount = analytics.metrics.deathCount + 1
  end
  
  lastHP, lastHpPercent = currentHP, healthPercent
end)

-- ============================================================================
-- PERIODIC UPDATES
-- ============================================================================

local lastConditionCheck = 0

local function updateTracking()
  if not isSessionActive() then return end
  
  local deltaMs = now - lastConditionCheck
  if deltaMs < 1000 then return end
  lastConditionCheck = now
  
  -- Condition tracking using map
  local conditions = Player.conditions()
  for _, c in ipairs(CONDITION_MAP) do
    if conditions[c.name] then
      analytics.metrics[c.key] = (analytics.metrics[c.key] or 0) + deltaMs
    end
  end
  
  -- Stamina bonus tracking
  local stamInfo = Player.staminaInfo()
  if stamInfo.status == "Green Bonus" then
    analytics.metrics.greenStaminaTime = analytics.metrics.greenStaminaTime + deltaMs
  elseif stamInfo.warningLevel > 0 then
    analytics.metrics.orangeStaminaTime = analytics.metrics.orangeStaminaTime + deltaMs
  end
  
  -- Peak stats
  local spd = Player.speed()
  if spd > (analytics.peakStats.maxSpeed or 0) then analytics.peakStats.maxSpeed = spd end
  
  local elapsed = getElapsed()
  if elapsed >= 60000 then
    local elapsedHour = elapsed / 3600000
    local xpGained = Player.exp() - (analytics.session.startXp or 0)
    local xpPerHour = xpGained / math.max(0.1, elapsedHour)
    local killsPerHour = analytics.metrics.kills / math.max(0.1, elapsedHour)
    
    if xpPerHour > analytics.peakStats.maxXpPerHour then analytics.peakStats.maxXpPerHour = xpPerHour end
    if killsPerHour > analytics.peakStats.maxKillsPerHour then analytics.peakStats.maxKillsPerHour = killsPerHour end
  end
end

-- ============================================================================
-- INSIGHTS ENGINE (Advanced AI Analysis)
-- Uses: Weighted scoring, trend analysis, statistical methods, correlation
-- ============================================================================

local Insights = {}

-- Insight builder (DRY - single function for all insights)
local function addInsight(results, severity, category, message, confidence)
  table.insert(results, { 
    severity = severity, 
    category = category, 
    message = message,
    confidence = confidence or 1.0  -- 0.0 to 1.0 confidence score
  })
end

-- ============================================================================
-- STATISTICAL HELPERS (Pure Functions)
-- ============================================================================

-- Calculate weighted average with time decay (recent data matters more)
local function weightedAverage(values, decayFactor)
  if not values or #values == 0 then return 0 end
  decayFactor = decayFactor or 0.9
  local sum, weightSum = 0, 0
  for i, v in ipairs(values) do
    local weight = decayFactor ^ (#values - i)  -- More recent = higher weight
    sum = sum + (v * weight)
    weightSum = weightSum + weight
  end
  return weightSum > 0 and (sum / weightSum) or 0
end

-- Calculate standard deviation (consistency measure)
local function standardDeviation(values, mean)
  if not values or #values < 2 then return 0 end
  mean = mean or 0
  local sum = 0
  for _, v in ipairs(values) do
    sum = sum + (v - mean) ^ 2
  end
  return math.sqrt(sum / (#values - 1))
end

-- Normalize value to 0-1 range
local function normalize(value, min, max)
  if max <= min then return 0.5 end
  return clamp((value - min) / (max - min), 0, 1)
end

-- Calculate percentile rank
local function percentileRank(value, thresholds)
  for i, threshold in ipairs(thresholds) do
    if value <= threshold then return (i - 1) / #thresholds end
  end
  return 1.0
end

-- Sigmoid function for smooth scoring transitions
local function sigmoid(x, midpoint, steepness)
  midpoint = midpoint or 0
  steepness = steepness or 1
  return 1 / (1 + math.exp(-steepness * (x - midpoint)))
end

-- ============================================================================
-- TREND TRACKING (Rolling Window Analysis)
-- ============================================================================

local trendData = {
  xpPerHour = {},
  killsPerHour = {},
  damageRatio = {},
  maxSamples = 12  -- Track last 12 samples (1 per 5 min = 1 hour of data)
}

local lastTrendUpdate = 0
local TREND_UPDATE_INTERVAL = 300000  -- 5 minutes

local function updateTrends(metrics)
  if now - lastTrendUpdate < TREND_UPDATE_INTERVAL then return end
  lastTrendUpdate = now
  
  -- Add new samples
  table.insert(trendData.xpPerHour, metrics.xpPerHour)
  table.insert(trendData.killsPerHour, metrics.killsPerHour)
  table.insert(trendData.damageRatio, metrics.damageRatio)
  
  -- Trim to max samples
  while #trendData.xpPerHour > trendData.maxSamples do table.remove(trendData.xpPerHour, 1) end
  while #trendData.killsPerHour > trendData.maxSamples do table.remove(trendData.killsPerHour, 1) end
  while #trendData.damageRatio > trendData.maxSamples do table.remove(trendData.damageRatio, 1) end
end

-- Calculate trend direction: -1 (declining), 0 (stable), 1 (improving)
local function calculateTrend(values)
  if #values < 3 then return 0, 0 end  -- Need at least 3 samples
  
  -- Compare recent average vs older average
  local mid = math.floor(#values / 2)
  local oldSum, newSum = 0, 0
  
  for i = 1, mid do oldSum = oldSum + values[i] end
  for i = mid + 1, #values do newSum = newSum + values[i] end
  
  local oldAvg = oldSum / mid
  local newAvg = newSum / (#values - mid)
  
  if oldAvg == 0 then return 0, 0 end
  
  local changePercent = ((newAvg - oldAvg) / oldAvg) * 100
  local direction = changePercent > 5 and 1 or changePercent < -5 and -1 or 0
  
  return direction, changePercent
end

-- ============================================================================
-- ADVANCED METRICS CALCULATION
-- ============================================================================

local function calculateMetrics()
  local m = analytics.metrics
  local elapsed = getElapsed()
  local elapsedHour = elapsed / 3600000
  local xpGained = Player.exp() - (analytics.session.startXp or 0)
  local levelInfo = Player.levelProgress()
  
  -- Base metrics
  local metrics = {
    elapsed = elapsed,
    elapsedHour = elapsedHour,
    elapsedMin = elapsed / 60000,
    xpGained = xpGained,
    xpPerHour = perHour(xpGained, elapsed),
    killsPerHour = perHour(m.kills, elapsed),
    levelPercentPerHour = (levelInfo.xpNeeded > 0) and (perHour(xpGained, elapsed) / levelInfo.xpNeeded * 100) or 0,
    damageRatio = m.healingDone > 0 and (m.damageTaken / m.healingDone) or 0,
    potionsPerKill = m.kills > 0 and (m.potionsUsed / m.kills) or 0,
    tilesPerKill = m.kills > 0 and (m.tilesWalked / m.kills) or 0,
    spellsPerKill = m.kills > 0 and (m.spellsCast / m.kills) or 0
  }
  
  -- Advanced derived metrics
  metrics.efficiency = 0
  if metrics.killsPerHour > 0 and metrics.tilesPerKill > 0 then
    -- Efficiency = kills per tile walked (higher = better spawn density)
    metrics.efficiency = 1 / metrics.tilesPerKill * 100
  end
  
  -- Survivability index (0-100, higher = safer)
  metrics.survivabilityIndex = 100
  if m.healingDone > 0 then
    metrics.survivabilityIndex = clamp(100 - (metrics.damageRatio * 50), 0, 100)
  end
  if m.deathCount > 0 then
    metrics.survivabilityIndex = metrics.survivabilityIndex * (0.5 ^ m.deathCount)
  end
  
  -- Combat uptime (time in combat vs total time)
  metrics.combatUptime = elapsed > 0 and ((m.timeInCombat or 0) / elapsed * 100) or 0
  
  -- Haste uptime
  metrics.hasteUptime = elapsed > 0 and ((m.timeHasted or 0) / elapsed * 100) or 0
  
  -- Near death frequency (per hour)
  metrics.nearDeathPerHour = perHour(m.nearDeathCount, elapsed)
  
  -- Stamina efficiency (XP per minute of stamina)
  local staminaUsed = (analytics.session.startStamina or 0) - (Player.stamina() or 0)
  metrics.xpPerStaminaMin = staminaUsed > 0 and (xpGained / staminaUsed) or 0
  
  return metrics
end

-- ============================================================================
-- AI INSIGHTS ANALYSIS
-- ============================================================================

function Insights.analyze()
  local results = {}
  local elapsed = getElapsed()
  local m = analytics.metrics
  
  -- Minimum session time check with progressive confidence
  local sessionConfidence = clamp(elapsed / 600000, 0.3, 1.0)  -- 0.3 at start, 1.0 at 10+ min
  
  if elapsed < 120000 then  -- Less than 2 minutes
    addInsight(results, SEVERITY.INFO, "Session", "Gathering data... (2+ min for initial insights)", 0.5)
    return results
  end
  
  local metrics = calculateMetrics()
  local stamInfo = Player.staminaInfo()
  
  -- Update trend tracking
  updateTrends(metrics)
  
  -- ========== EFFICIENCY ANALYSIS ==========
  
  -- XP Rate Analysis with contextual thresholds
  local lvlPct = metrics.levelPercentPerHour
  local xpConfidence = clamp(elapsed / 900000, 0.5, 1.0)  -- Higher confidence after 15 min
  
  if lvlPct >= 5 then 
    addInsight(results, SEVERITY.INFO, "XP Rate", string.format("Excellent! %.1f%% level/hour", lvlPct), xpConfidence)
  elseif lvlPct >= 2 then
    addInsight(results, SEVERITY.INFO, "XP Rate", string.format("Good: %.2f%%/h (~%.0fh to level)", lvlPct, 100/lvlPct), xpConfidence)
  elseif lvlPct >= 0.5 then
    addInsight(results, SEVERITY.TIP, "XP Rate", string.format("Moderate: %.2f%%/h. Consider stronger spawns.", lvlPct), xpConfidence)
  elseif lvlPct > 0 and metrics.elapsedHour >= 0.25 then
    addInsight(results, SEVERITY.WARNING, "XP Rate", string.format("Slow: %.2f%%/h. Spawn may be too weak.", lvlPct), xpConfidence)
  end
  
  -- Trend analysis for XP
  if #trendData.xpPerHour >= 3 then
    local trend, changePercent = calculateTrend(trendData.xpPerHour)
    if trend == 1 and changePercent > 10 then
      addInsight(results, SEVERITY.INFO, "Trend", string.format("XP rate improving! +%.0f%% trend", changePercent), 0.8)
    elseif trend == -1 and changePercent < -15 then
      addInsight(results, SEVERITY.WARNING, "Trend", string.format("XP rate declining: %.0f%%. Check respawn.", changePercent), 0.8)
    end
  end
  
  -- Kill Rate Analysis
  if m.kills >= 10 then
    if metrics.killsPerHour < 30 then
      addInsight(results, SEVERITY.WARNING, "Kill Rate", string.format("Low: %.0f/h. Improve targeting or find denser spawn.", metrics.killsPerHour), sessionConfidence)
    elseif metrics.killsPerHour >= 250 then
      addInsight(results, SEVERITY.INFO, "Kill Rate", string.format("Excellent! %.0f kills/hour", metrics.killsPerHour), sessionConfidence)
    elseif metrics.killsPerHour >= 150 then
      addInsight(results, SEVERITY.INFO, "Kill Rate", string.format("Good: %.0f/h", metrics.killsPerHour), sessionConfidence)
    end
  end
  
  -- Spawn Density Analysis
  if m.kills >= 20 and m.tilesWalked >= 100 then
    local density = metrics.efficiency
    if density < 2 then
      addInsight(results, SEVERITY.TIP, "Spawn", string.format("Sparse (%.0f tiles/kill). Consider tighter routes.", metrics.tilesPerKill), sessionConfidence)
    elseif density >= 10 then
      addInsight(results, SEVERITY.INFO, "Spawn", "Dense spawn! Efficient pathing.", sessionConfidence)
    end
  end
  
  -- ========== SURVIVABILITY ANALYSIS ==========
  
  -- Damage/Healing Ratio with nuanced thresholds
  if m.healingDone > 1000 then  -- Enough data to analyze
    local dr = metrics.damageRatio
    local survConfidence = clamp(m.healingDone / 10000, 0.5, 1.0)
    
    if dr > 1.3 then 
      addInsight(results, SEVERITY.CRITICAL, "Survival", "DANGER! Taking 30%+ more damage than healing. Risk of death!", survConfidence)
    elseif dr > 1.0 then
      addInsight(results, SEVERITY.WARNING, "Survival", string.format("Risky: %.0f%% damage vs healing. Lower HP threshold.", dr * 100), survConfidence)
    elseif dr > 0.8 then
      addInsight(results, SEVERITY.TIP, "Survival", "Damage close to healing. Consider safer play.", survConfidence)
    elseif dr < 0.3 and dr > 0 then
      addInsight(results, SEVERITY.TIP, "Survival", string.format("Very safe (%.0f%% ratio). Could handle harder content.", dr * 100), survConfidence)
    end
  end
  
  -- Near-death analysis with frequency consideration
  if m.nearDeathCount > 0 then
    local ndRate = metrics.nearDeathPerHour
    if ndRate > 3 then
      addInsight(results, SEVERITY.CRITICAL, "Survival", string.format("High risk! %.1f near-deaths/hour. Increase heal threshold!", ndRate), 0.95)
    elseif ndRate > 1 then
      addInsight(results, SEVERITY.WARNING, "Survival", string.format("%.1f near-deaths/hour. Consider adjusting healer.", ndRate), 0.85)
    end
  end
  
  -- Death penalty tracking
  if m.deathCount > 0 then
    addInsight(results, SEVERITY.CRITICAL, "Survival", string.format("%d death(s)! Check equipment, supplies, and heal settings.", m.deathCount), 1.0)
  end
  
  -- ========== STAMINA ANALYSIS ==========
  
  if stamInfo.warningLevel == 2 then 
    addInsight(results, SEVERITY.CRITICAL, "Stamina", "DEPLETED! 0% XP from kills. Stop hunting!", 1.0)
  elseif stamInfo.warningLevel == 1 then
    addInsight(results, SEVERITY.WARNING, "Stamina", string.format("Orange (%.1fh). 50%% XP penalty active!", stamInfo.hours), 1.0)
  elseif stamInfo.greenRemaining > 0 and stamInfo.greenRemaining < 1 then
    addInsight(results, SEVERITY.WARNING, "Stamina", string.format("Green ending soon! %.0fm left.", stamInfo.greenRemaining * 60), 1.0)
  elseif stamInfo.greenRemaining >= 1 then
    addInsight(results, SEVERITY.INFO, "Stamina", string.format("Green bonus active. %.1fh remaining.", stamInfo.greenRemaining), 0.9)
  end
  
  -- Stamina efficiency
  if metrics.xpPerStaminaMin > 0 and metrics.elapsedHour >= 0.5 then
    addInsight(results, SEVERITY.INFO, "Stamina", string.format("%.0f XP per stamina minute used.", metrics.xpPerStaminaMin), sessionConfidence)
  end
  
  -- ========== RESOURCE ANALYSIS ==========
  
  if m.potionsUsed >= 20 then
    local ppk = metrics.potionsPerKill
    if ppk > 3 then
      addInsight(results, SEVERITY.WARNING, "Resources", string.format("High potion use: %.1f/kill. Check mana efficiency.", ppk), sessionConfidence)
    elseif ppk < 0.5 and m.kills > 30 then
      addInsight(results, SEVERITY.INFO, "Resources", "Efficient potion usage!", sessionConfidence)
    end
  end
  
  -- ========== COMBAT UPTIME ANALYSIS ==========
  
  if elapsed >= 600000 then  -- At least 10 min
    if metrics.combatUptime < 30 then
      addInsight(results, SEVERITY.TIP, "Uptime", string.format("Low combat time (%.0f%%). More aggressive luring?", metrics.combatUptime), sessionConfidence)
    elseif metrics.combatUptime >= 70 then
      addInsight(results, SEVERITY.INFO, "Uptime", string.format("High combat uptime: %.0f%%", metrics.combatUptime), sessionConfidence)
    end
  end
  
  -- ========== CONDITION ANALYSIS ==========
  
  -- Paralysis impact
  if m.timeParalyzed > 60000 then
    local paraPct = (m.timeParalyzed / elapsed) * 100
    addInsight(results, SEVERITY.WARNING, "Conditions", string.format("Paralyzed %.0f%% of time. Use anti-paralyze.", paraPct), 0.9)
  end
  
  -- Haste efficiency
  if elapsed >= 600000 and m.tilesWalked > 500 then
    if metrics.hasteUptime < 40 then
      addInsight(results, SEVERITY.TIP, "Conditions", string.format("Haste only %.0f%%. Enable auto-haste.", metrics.hasteUptime), sessionConfidence)
    end
  end
  
  -- ========== PROTECTION ANALYSIS ==========
  
  local blessCount = Player.blessings()
  if blessCount < 5 then
    if m.nearDeathCount >= 2 or m.deathCount > 0 then
      addInsight(results, SEVERITY.WARNING, "Protection", string.format("Only %d blessings with %d close calls. Get full bless!", blessCount, m.nearDeathCount), 0.95)
    elseif metrics.damageRatio > 0.7 then
      addInsight(results, SEVERITY.TIP, "Protection", string.format("%d/5 blessings. Recommend full protection.", blessCount), 0.7)
    end
  end
  
  -- ========== CONSISTENCY ANALYSIS ==========
  
  if #trendData.killsPerHour >= 4 then
    local avg = 0
    for _, v in ipairs(trendData.killsPerHour) do avg = avg + v end
    avg = avg / #trendData.killsPerHour
    
    local stdDev = standardDeviation(trendData.killsPerHour, avg)
    local cv = avg > 0 and (stdDev / avg * 100) or 0  -- Coefficient of variation
    
    if cv > 40 then
      addInsight(results, SEVERITY.TIP, "Consistency", string.format("Kill rate varies %.0f%%. Inconsistent spawn or path.", cv), 0.75)
    elseif cv < 15 and avg > 100 then
      addInsight(results, SEVERITY.INFO, "Consistency", "Very consistent performance!", 0.8)
    end
  end
  
  return results
end

function Insights.format(list)
  local lines = {}
  local icons = { 
    [SEVERITY.CRITICAL] = "[!]", 
    [SEVERITY.WARNING] = "[*]", 
    [SEVERITY.TIP] = "[>]", 
    [SEVERITY.INFO] = "[i]" 
  }
  local byPriority = { {}, {}, {}, {} }
  local order = { [SEVERITY.CRITICAL] = 1, [SEVERITY.WARNING] = 2, [SEVERITY.TIP] = 3, [SEVERITY.INFO] = 4 }
  
  -- Sort by priority, then by confidence (higher confidence first)
  for _, i in ipairs(list) do 
    table.insert(byPriority[order[i.severity] or 4], i) 
  end
  
  for _, group in ipairs(byPriority) do
    -- Sort each group by confidence descending
    table.sort(group, function(a, b) return (a.confidence or 0) > (b.confidence or 0) end)
    for _, i in ipairs(group) do 
      table.insert(lines, string.format("  %s %s", icons[i.severity] or "[?]", i.message))
    end
  end
  return lines
end

function Insights.calculateScore()
  local elapsed = getElapsed()
  if elapsed < 180000 then return 0 end  -- Need 3 min minimum
  
  local m = analytics.metrics
  local metrics = calculateMetrics()
  
  -- Confidence multiplier based on session length (more data = more accurate score)
  local confidence = clamp(elapsed / 1800000, 0.5, 1.0)  -- 50% at start, 100% at 30 min
  
  local score = 0
  local maxScore = 100
  
  -- ========== XP EFFICIENCY (25 pts) ==========
  local lvlPct = metrics.levelPercentPerHour
  local xpScore = 0
  if lvlPct >= 10 then xpScore = 25
  elseif lvlPct >= 5 then xpScore = 22
  elseif lvlPct >= 2 then xpScore = 18
  elseif lvlPct >= 1 then xpScore = 14
  elseif lvlPct >= 0.5 then xpScore = 10
  elseif lvlPct >= 0.2 then xpScore = 6
  elseif lvlPct > 0 then xpScore = 3
  end
  score = score + xpScore
  
  -- ========== KILL EFFICIENCY (20 pts) ==========
  local killScore = 0
  if metrics.killsPerHour > 300 then killScore = 20
  elseif metrics.killsPerHour > 200 then killScore = 16
  elseif metrics.killsPerHour > 150 then killScore = 13
  elseif metrics.killsPerHour > 100 then killScore = 10
  elseif metrics.killsPerHour > 50 then killScore = 6
  elseif metrics.killsPerHour > 20 then killScore = 3
  end
  score = score + killScore
  
  -- ========== SPAWN DENSITY (10 pts) ==========
  local densityScore = 0
  if m.kills > 10 and m.tilesWalked > 0 then
    local tpk = metrics.tilesPerKill
    if tpk < 5 then densityScore = 10
    elseif tpk < 10 then densityScore = 8
    elseif tpk < 20 then densityScore = 6
    elseif tpk < 35 then densityScore = 4
    elseif tpk < 50 then densityScore = 2
    end
  end
  score = score + densityScore
  
  -- ========== SURVIVABILITY (25 pts) ==========
  local survScore = 0
  
  -- Damage ratio component (15 pts)
  if m.healingDone > 0 then
    local dr = metrics.damageRatio
    if dr < 0.3 then survScore = survScore + 15
    elseif dr < 0.5 then survScore = survScore + 13
    elseif dr < 0.7 then survScore = survScore + 10
    elseif dr < 0.9 then survScore = survScore + 6
    elseif dr < 1.0 then survScore = survScore + 3
    elseif dr > 1.2 then survScore = survScore - 5  -- Penalty for dangerous
    end
  else
    survScore = survScore + 12  -- No damage taken = safe
  end
  
  -- Death penalty (up to -15 pts)
  if m.deathCount > 0 then
    survScore = survScore - math.min(15, m.deathCount * 8)
  else
    survScore = survScore + 5  -- Bonus for no deaths
  end
  
  -- Near-death frequency (5 pts)
  local ndRate = metrics.nearDeathPerHour
  if ndRate == 0 then survScore = survScore + 5
  elseif ndRate < 1 then survScore = survScore + 3
  elseif ndRate < 2 then survScore = survScore + 1
  elseif ndRate > 4 then survScore = survScore - 3
  end
  
  score = score + math.max(0, survScore)
  
  -- ========== RESOURCE EFFICIENCY (10 pts) ==========
  local resScore = 0
  if m.kills > 10 then
    local ppk = metrics.potionsPerKill
    if ppk < 0.3 then resScore = 10
    elseif ppk < 0.7 then resScore = 8
    elseif ppk < 1.2 then resScore = 6
    elseif ppk < 2.0 then resScore = 4
    elseif ppk < 3.0 then resScore = 2
    elseif ppk > 4.0 then resScore = -2  -- Penalty for excessive use
    end
  else
    resScore = 5  -- Neutral if not enough data
  end
  score = score + math.max(0, resScore)
  
  -- ========== COMBAT UPTIME (5 pts) ==========
  local uptimeScore = 0
  if elapsed >= 300000 then
    local uptime = metrics.combatUptime
    if uptime >= 70 then uptimeScore = 5
    elseif uptime >= 50 then uptimeScore = 4
    elseif uptime >= 35 then uptimeScore = 3
    elseif uptime >= 20 then uptimeScore = 2
    end
  end
  score = score + uptimeScore
  
  -- ========== ECONOMY BONUS (5 pts) ==========
  if bottingStats then
    local ok, waste, loot, balance = pcall(bottingStats)
    if ok and balance then
      local profitPerHour = balance / math.max(0.1, metrics.elapsedHour)
      if profitPerHour > 100000 then score = score + 5
      elseif profitPerHour > 50000 then score = score + 4
      elseif profitPerHour > 20000 then score = score + 3
      elseif profitPerHour > 0 then score = score + 1
      elseif profitPerHour < -30000 then score = score - 2
      end
    end
  end
  
  -- Apply confidence multiplier for short sessions
  local finalScore = score * confidence
  
  return clamp(math.floor(finalScore), 0, 100)
end

function Insights.scoreBar(score)
  local filled = math.floor(score / 10)
  local rating
  if score >= 85 then rating = "Excellent"
  elseif score >= 70 then rating = "Great"
  elseif score >= 55 then rating = "Good"
  elseif score >= 40 then rating = "Average"
  elseif score >= 25 then rating = "Below Avg"
  else rating = "Poor"
  end
  return string.format("[%s%s] %d/100 (%s)", string.rep("#", filled), string.rep("-", 10 - filled), score, rating)
end

-- ============================================================================
-- SUMMARY BUILDER (Template Pattern)
-- ============================================================================

local function addSection(lines, title, content)
  table.insert(lines, "[" .. title .. "]")
  table.insert(lines, "--------------------------------------------")
  for _, line in ipairs(content) do table.insert(lines, "  " .. line) end
  table.insert(lines, "")
end

local function buildSummary()
  local lines = {}
  local m = analytics.metrics
  local elapsed = getElapsed()
  local metrics = calculateMetrics()
  local levelInfo = Player.levelProgress()
  local stamInfo = Player.staminaInfo()
  
  -- Header
  table.insert(lines, "============================================")
  table.insert(lines, "        SMARTHUNT ANALYTICS v4.0")
  table.insert(lines, "============================================")
  table.insert(lines, "")
  
  -- Session
  addSection(lines, "SESSION", {
    "Duration: " .. formatDuration(elapsed),
    "Status: " .. (isSessionActive() and "ACTIVE" or "STOPPED"),
    "Level: " .. levelInfo.level .. " (" .. string.format("%.1f%%", levelInfo.percent) .. ")"
  })
  
  -- Experience
  local xpLines = {
    "XP Gained: " .. formatNum(metrics.xpGained),
    "XP/Hour: " .. formatNum(math.floor(metrics.xpPerHour)),
    "Progress/Hour: " .. string.format("%.2f%%", metrics.levelPercentPerHour)
  }
  local hoursToLevel = metrics.xpPerHour > 0 and levelInfo.xpRemaining / metrics.xpPerHour or 0
  if hoursToLevel > 0 and hoursToLevel < 10000 then
    table.insert(xpLines, "Time to Level: " .. string.format("%.1fh", hoursToLevel))
  end
  addSection(lines, "EXPERIENCE", xpLines)
  
  -- Combat
  addSection(lines, "COMBAT", {
    "Kills: " .. formatNum(m.kills) .. " (" .. formatNum(math.floor(metrics.killsPerHour)) .. "/h)",
    "Damage Taken: " .. formatNum(m.damageTaken),
    "Healing Done: " .. formatNum(m.healingDone),
    "Deaths: " .. m.deathCount .. " | Near-Death: " .. m.nearDeathCount
  })
  
  -- Stamina
  local startStaminaMins = analytics.session.startStamina or 0
  local staminaUsedMins = startStaminaMins - stamInfo.minutes
  if staminaUsedMins < 0 then staminaUsedMins = 0 end -- In case stamina was refilled
  
  -- Format stamina used as hours:minutes
  local staminaUsedStr
  if staminaUsedMins > 0 then
    local usedHrs = math.floor(staminaUsedMins / 60)
    local usedMins = staminaUsedMins % 60
    if usedHrs > 0 then
      staminaUsedStr = string.format("%dh %dm", usedHrs, usedMins)
    else
      staminaUsedStr = string.format("%dm", usedMins)
    end
  end
  
  local stamLines = {
    "Current: " .. string.format("%.2fh (%s)", stamInfo.hours, stamInfo.status),
    "Session Start: " .. string.format("%.2fh", startStaminaMins / 60),
    staminaUsedStr and ("Spent: " .. staminaUsedStr) or nil,
    stamInfo.greenRemaining > 0 and ("Green Left: " .. string.format("%.1fh", stamInfo.greenRemaining)) or nil
  }
  local filteredStam = {}
  for _, l in ipairs(stamLines) do if l then table.insert(filteredStam, l) end end
  addSection(lines, "STAMINA", filteredStam)
  
  -- Player
  addSection(lines, "PLAYER", {
    "Magic Level: " .. Player.mlevel(),
    "Blessings: " .. Player.blessings(),
    "Speed: " .. Player.speed()
  })
  
  -- Score
  local score = Insights.calculateScore()
  addSection(lines, "HUNT SCORE", { Insights.scoreBar(score) })
  
  -- Insights
  local insightsList = Insights.analyze()
  table.insert(lines, "[AI INSIGHTS]")
  table.insert(lines, "--------------------------------------------")
  local insightLines = Insights.format(insightsList)
  for _, line in ipairs(insightLines) do table.insert(lines, line) end
  table.insert(lines, "")
  table.insert(lines, "  [!]=Critical [*]=Warning [>]=Tip [i]=Info")
  table.insert(lines, "============================================")
  
  return table.concat(lines, "\n")
end

-- ============================================================================
-- UI
-- ============================================================================

local analyticsWindow = nil

local function showAnalytics()
  if analyticsWindow then 
    pcall(function() analyticsWindow:destroy() end)
    analyticsWindow = nil 
  end
  
  -- Try to create window, fall back to console output
  local ok, win = pcall(function() return UI.createWindow('SmartHuntAnalyticsWindow') end)
  if not ok or not win then 
    print(buildSummary()) 
    return 
  end
  
  analyticsWindow = win
  
  -- Safely access window elements
  if analyticsWindow.content and analyticsWindow.content.textContent then
    analyticsWindow.content.textContent:setText(buildSummary())
  end
  
  if analyticsWindow.buttons then
    if analyticsWindow.buttons.refreshButton then
      analyticsWindow.buttons.refreshButton.onClick = function() 
        if analyticsWindow and analyticsWindow.content and analyticsWindow.content.textContent then
          analyticsWindow.content.textContent:setText(buildSummary()) 
        end
      end
    end
    if analyticsWindow.buttons.closeButton then
      analyticsWindow.buttons.closeButton.onClick = function() 
        if analyticsWindow then pcall(function() analyticsWindow:destroy() end) end
        analyticsWindow = nil 
      end
    end
    if analyticsWindow.buttons.resetButton then
      analyticsWindow.buttons.resetButton.onClick = function() 
        startSession() 
        if analyticsWindow and analyticsWindow.content and analyticsWindow.content.textContent then
          analyticsWindow.content.textContent:setText(buildSummary()) 
        end
      end
    end
  end
  
  -- Safely show window
  pcall(function() analyticsWindow:show():raise():focus() end)
end

-- ============================================================================
-- MACROS (Hidden)
-- ============================================================================

UI.Separator()

macro(5000, "SmartHunt Tracker", function()
  if CaveBot and CaveBot.isOn() and not isSessionActive() then
    startSession()
    -- Session started silently
  end
  updateTracking()
end)

macro(1000, function() updateTracking() end)

-- ============================================================================
-- UI BUTTON
-- ============================================================================

local btn = UI.Button("SmartHunt Analytics", function()
  local ok, err = pcall(showAnalytics)
  if not ok then warn("[SmartHunt] " .. tostring(err)) print(buildSummary()) end
end)
if btn then btn:setTooltip("View hunting analytics") end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

nExBot.Analytics = {
  start = startSession,
  stop = endSession,
  isActive = isSessionActive,
  getSummary = buildSummary,
  getMetrics = function() return analytics.metrics end,
  getElapsed = getElapsed,
  getTrends = function() return trendData end
}

print("[SmartHunt] v4.0 loaded (Advanced AI)")
