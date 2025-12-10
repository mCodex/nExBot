--[[
  SmartHunt Analytics Module v3.1 (Refactored)
  
  Comprehensive hunting analytics using OTClient native functions.
  Refactored using: SRP, DRY, KISS, SOLID, Pure Functions
  
  OTClient Functions: getLevel, getLevelPercent, getStamina, getSoul,
  getBlessings, getVocation, getSpeed, getSkillLevel/Percent, getMagicLevel
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

local VOCATION_NAMES = {
  [0] = "None", [1] = "Sorcerer", [2] = "Druid", [3] = "Paladin", [4] = "Knight",
  [5] = "Master Sorcerer", [6] = "Elder Druid", [7] = "Royal Paladin", [8] = "Elite Knight"
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

function Player.vocation()
  local id = safeGet(voc, 0) or playerGet("getVocation", 0)
  return {
    id = id,
    name = VOCATION_NAMES[id] or "Unknown",
    isKnight = id == 4 or id == 8,
    isPaladin = id == 3 or id == 7,
    isMage = id <= 2 or (id >= 5 and id <= 6),
    isSorcerer = id == 1 or id == 5,
    isDruid = id == 2 or id == 6
  }
end

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
    vocation = Player.vocation().id, active = true
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
-- INSIGHTS ENGINE (Pure Functions + Builder Pattern)
-- ============================================================================

local Insights = {}

-- Insight builder (DRY - single function for all insights)
local function addInsight(results, severity, category, message)
  table.insert(results, { severity = severity, category = category, message = message })
end

-- Calculate hunt metrics (pure function)
local function calculateMetrics()
  local m = analytics.metrics
  local elapsed = getElapsed()
  local elapsedHour = elapsed / 3600000
  local xpGained = Player.exp() - (analytics.session.startXp or 0)
  local levelInfo = Player.levelProgress()
  
  return {
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
end

function Insights.analyze()
  local results = {}
  local elapsed = getElapsed()
  local m = analytics.metrics
  
  if elapsed < 300000 then
    addInsight(results, SEVERITY.INFO, "Session", "Need 5+ minutes for accurate insights")
    return results
  end
  
  local metrics = calculateMetrics()
  local voc = Player.vocation()
  local stamInfo = Player.staminaInfo()
  
  -- Level Progress Insights
  local lvlPct = metrics.levelPercentPerHour
  if lvlPct >= 5 then addInsight(results, SEVERITY.INFO, "Efficiency", string.format("Excellent! %.1f%% level/hour", lvlPct))
  elseif lvlPct >= 1 then addInsight(results, SEVERITY.INFO, "Efficiency", string.format("Good progress: %.2f%%/h (~%.0fh to level)", lvlPct, 100/lvlPct))
  elseif lvlPct >= 0.1 then addInsight(results, SEVERITY.TIP, "Efficiency", string.format("Slow (%.2f%%/h). Consider stronger spawns.", lvlPct))
  elseif metrics.elapsedHour >= 0.5 then addInsight(results, SEVERITY.WARNING, "Efficiency", string.format("Very slow (%.2f%%/h). Inefficient spawn.", lvlPct))
  end
  
  -- Kill Rate
  if m.kills > 0 and metrics.killsPerHour < 50 then
    addInsight(results, SEVERITY.WARNING, "Efficiency", string.format("Low kills (%.0f/h). Improve targeting/luring.", metrics.killsPerHour))
  elseif metrics.killsPerHour > 200 then
    addInsight(results, SEVERITY.INFO, "Efficiency", string.format("Great kill rate! %.0f/h", metrics.killsPerHour))
  end
  
  -- Survivability
  if metrics.damageRatio > 1.2 then addInsight(results, SEVERITY.CRITICAL, "Survivability", "Taking more damage than healing! Death risk!")
  elseif metrics.damageRatio > 0.9 then addInsight(results, SEVERITY.WARNING, "Survivability", "Damage nearly equals healing. Lower HP threshold.")
  elseif metrics.damageRatio < 0.3 and metrics.damageRatio > 0 then addInsight(results, SEVERITY.TIP, "Survivability", "Very safe. Could handle stronger monsters.")
  end
  
  -- Stamina
  if stamInfo.warningLevel == 2 then addInsight(results, SEVERITY.CRITICAL, "Stamina", "DEPLETED! No XP from kills!")
  elseif stamInfo.warningLevel == 1 then addInsight(results, SEVERITY.WARNING, "Stamina", string.format("Orange stamina (%.1fh). 50%% XP penalty!", stamInfo.hours))
  elseif stamInfo.greenRemaining > 0 then addInsight(results, SEVERITY.INFO, "Stamina", string.format("Green bonus! +50%% XP. %.1fh remaining.", stamInfo.greenRemaining))
  end
  
  -- Resources
  if m.potionsUsed > 10 and metrics.potionsPerKill > 2 then
    addInsight(results, SEVERITY.WARNING, "Resources", string.format("High potion use (%.1f/kill). Consider mana shield.", metrics.potionsPerKill))
  end
  
  -- Movement
  if m.tilesWalked > 100 and m.kills > 10 and metrics.tilesPerKill > 50 then
    addInsight(results, SEVERITY.TIP, "Movement", string.format("Walking %.0f tiles/kill. Sparse spawn.", metrics.tilesPerKill))
  end
  
  -- Conditions
  if m.timeParalyzed > 30000 then
    addInsight(results, SEVERITY.WARNING, "Conditions", string.format("Paralyzed %.0fs. Anti-paralyze recommended.", m.timeParalyzed/1000))
  end
  if m.timeHasted > 0 and elapsed > 300000 then
    local hastePct = (m.timeHasted / elapsed) * 100
    if hastePct < 30 and m.tilesWalked > 500 then
      addInsight(results, SEVERITY.TIP, "Conditions", string.format("Haste only %.0f%%. Use utani hur.", hastePct))
    end
  end
  
  -- Vocation-specific
  if voc.isKnight and m.spellsCast < m.kills * 0.5 and m.kills > 30 then
    addInsight(results, SEVERITY.TIP, "Vocation", "Knight: Use exori spells for faster kills.")
  end
  if voc.isMage and m.timeManaShield > 0 then
    local msPct = (m.timeManaShield / elapsed) * 100
    if msPct > 50 then addInsight(results, SEVERITY.INFO, "Vocation", string.format("Mana shield %.0f%%. Good defense.", msPct)) end
  end
  
  -- Blessings
  if Player.blessings() < 5 and m.nearDeathCount > 2 then
    addInsight(results, SEVERITY.WARNING, "Protection", string.format("Only %d blessings with near-death events.", Player.blessings()))
  end
  
  return results
end

function Insights.format(list)
  local lines, icons = {}, { [SEVERITY.CRITICAL] = "[!]", [SEVERITY.WARNING] = "[*]", [SEVERITY.TIP] = "[>]", [SEVERITY.INFO] = "[i]" }
  local byPriority = { {}, {}, {}, {} }
  local order = { [SEVERITY.CRITICAL] = 1, [SEVERITY.WARNING] = 2, [SEVERITY.TIP] = 3, [SEVERITY.INFO] = 4 }
  
  for _, i in ipairs(list) do table.insert(byPriority[order[i.severity] or 4], i) end
  for _, group in ipairs(byPriority) do
    for _, i in ipairs(group) do table.insert(lines, string.format("  %s %s", icons[i.severity] or "[?]", i.message)) end
  end
  return lines
end

function Insights.calculateScore()
  local elapsed = getElapsed()
  if elapsed < 300000 then return 0 end
  
  local m = analytics.metrics
  local metrics = calculateMetrics()
  local score = 0
  
  -- Level Progress (20 pts)
  local lvlPct = metrics.levelPercentPerHour
  score = score + (lvlPct >= 10 and 20 or lvlPct >= 5 and 18 or lvlPct >= 2 and 15 or lvlPct >= 1 and 12 or lvlPct >= 0.5 and 8 or lvlPct >= 0.2 and 5 or lvlPct > 0 and 3 or 0)
  
  -- Kill Rate (15 pts)
  score = score + (metrics.killsPerHour > 300 and 15 or metrics.killsPerHour > 200 and 12 or metrics.killsPerHour > 100 and 9 or metrics.killsPerHour > 50 and 5 or 0)
  
  -- Movement (5 pts)
  if m.kills > 10 and m.tilesWalked > 0 then
    score = score + (metrics.tilesPerKill < 10 and 5 or metrics.tilesPerKill < 20 and 3 or metrics.tilesPerKill < 40 and 1 or 0)
  end
  
  -- Survivability (30 pts)
  if m.healingDone > 0 then
    local dr = metrics.damageRatio
    score = score + (dr < 0.4 and 15 or dr < 0.6 and 12 or dr < 0.8 and 8 or dr < 1.0 and 4 or dr > 1.2 and -5 or 0)
  else score = score + 10 end
  score = score + (m.deathCount > 0 and (-m.deathCount * 10) or 10)
  local nearDeathRate = m.nearDeathCount / math.max(1, metrics.elapsedHour)
  score = score + (nearDeathRate > 5 and -5 or nearDeathRate > 2 and -2 or nearDeathRate == 0 and 5 or 0)
  
  -- Resources (20 pts)
  if m.kills > 10 then
    local ppk = metrics.potionsPerKill
    score = score + (ppk < 0.3 and 10 or ppk < 0.7 and 7 or ppk < 1.5 and 4 or ppk > 3 and -3 or 0)
  end
  score = score + 6 -- Base resource score
  
  -- Economy (10 pts)
  if bottingStats then
    local _, _, balance = bottingStats()
    local profitPerHour = balance / math.max(0.1, metrics.elapsedHour)
    score = score + (profitPerHour > 100000 and 10 or profitPerHour > 50000 and 7 or profitPerHour > 20000 and 4 or profitPerHour > 0 and 2 or profitPerHour < -20000 and -3 or 0)
  end
  
  return clamp(score, 0, 100)
end

function Insights.scoreBar(score)
  local filled = math.floor(score / 10)
  local rating = score >= 80 and "Excellent" or score >= 60 and "Good" or score >= 40 and "Average" or score >= 20 and "Below Avg" or "Poor"
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
  local vocInfo = Player.vocation()
  
  -- Header
  table.insert(lines, "============================================")
  table.insert(lines, "        SMARTHUNT ANALYTICS v3.1")
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
  local staminaUsed = (analytics.session.startStamina or 0) - stamInfo.minutes
  local stamLines = {
    "Current: " .. string.format("%.1fh (%s)", stamInfo.hours, stamInfo.status),
    staminaUsed > 0 and ("Used: " .. staminaUsed .. " min") or nil,
    stamInfo.greenRemaining > 0 and ("Green Left: " .. string.format("%.1fh", stamInfo.greenRemaining)) or nil
  }
  local filteredStam = {}
  for _, l in ipairs(stamLines) do if l then table.insert(filteredStam, l) end end
  addSection(lines, "STAMINA", filteredStam)
  
  -- Player
  addSection(lines, "PLAYER", {
    "Vocation: " .. vocInfo.name,
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
  if analyticsWindow then analyticsWindow:destroy() analyticsWindow = nil end
  
  analyticsWindow = UI.createWindow('SmartHuntAnalyticsWindow')
  if not analyticsWindow then print(buildSummary()) return end
  
  analyticsWindow.content.textContent:setText(buildSummary())
  analyticsWindow.buttons.refreshButton.onClick = function() analyticsWindow.content.textContent:setText(buildSummary()) end
  analyticsWindow.buttons.closeButton.onClick = function() analyticsWindow:destroy() analyticsWindow = nil end
  analyticsWindow.buttons.resetButton.onClick = function() startSession() analyticsWindow.content.textContent:setText(buildSummary()) end
  analyticsWindow:show():raise():focus()
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
  getElapsed = getElapsed
}

print("[SmartHunt] v3.1 loaded (refactored)")
