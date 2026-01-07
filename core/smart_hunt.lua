--[[
  Hunt Analyzer Module v2.0
  
  Features:
  - Statistical analysis (standard deviation, trends, confidence)
  - Trend tracking with rolling window analysis
  - Weighted scoring with time-decay
  - Confidence-based insights prioritization
  - Advanced metrics: efficiency index, survivability index, combat uptime
  - Detailed consumption tracking: spells, potions, runes from HealBot/TargetBot
  - Consumption-based insights and recommendations
  - Enhanced multi-variable score calculation
  
  Consumption Tracking API (HuntAnalytics):
  - trackHealSpell(name, mana) - Track heal spell usage
  - trackAttackSpell(name, mana) - Track attack spell usage
  - trackSupportSpell(name, mana) - Track support spell usage
  - trackPotion(name, type) - Track potion usage ("heal"/"mana"/"other")
  - trackRune(name, type) - Track rune usage ("attack"/"heal")
  - getConsumption() - Get all consumption data
  
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
  timeHasted = 0, greenStaminaTime = 0, orangeStaminaTime = 0, timeInCombat = 0,
  lootValue = 0, lootGold = 0, lootDrops = 0,
  -- Detailed consumption tracking
  healSpellsCast = 0, attackSpellsCast = 0, supportSpellsCast = 0,
  healPotionsUsed = 0, manaPotionsUsed = 0,
  attackRunesUsed = 0, healRunesUsed = 0,
  manaSpent = 0  -- Total mana spent on spells
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
  a.lootItems = a.lootItems or {}
  -- Detailed consumption tracking tables
  a.spellsUsed = a.spellsUsed or {}      -- { ["exura vita"] = { count = 5, mana = 80 }, ... }
  a.potionsUsed = a.potionsUsed or {}    -- { ["great mana potion"] = 10, ... }
  a.runesUsed = a.runesUsed or {}        -- { ["sudden death rune"] = 15, ... }
  return a
end

local analytics = initStorage()

local function getElapsed()
  return analytics.session.active and (now - analytics.session.startTime) or 0
end

local function isSessionActive()
  return analytics.session.active == true
end

-- Captures player skills at session start for potential future skill gain tracking
-- @return table Skills table with string keys: "skill_0" through "skill_6" (Fist, Club, Sword, Axe, Distance, Shielding, Fishing)
--               and "mlevel" for Magic Level
-- Note: Uses string keys (e.g., skills["skill_0"]) instead of numeric indices to avoid Lua sparse array issues
--       Access pattern: skills["skill_" .. skillId] where skillId is 0-6, or skills["mlevel"]
-- Currently stored but not used - reserved for future skill gain analytics feature
local function captureSkills()
  local skills = {}
  for id = 0, 6 do skills["skill_" .. id] = Player.skill(id).current end
  skills["mlevel"] = Player.mlevel()
  return skills
end

local function startSession()
  local stamInfo = Player.staminaInfo()
  local levelInfo = Player.levelProgress()
  
  -- Session data structure:
  -- startSkills: table with string keys "skill_0" to "skill_6" and "mlevel" (reserved for future use)
  analytics.session = {
    startTime = now, startXp = Player.exp(), startSkills = captureSkills(),
    startCap = Player.cap(), startStamina = stamInfo.minutes,
    startLevelPercent = levelInfo.percent, startSpeed = Player.speed(),
    active = true
  }
  
  for k, v in pairs(DEFAULT_METRICS) do analytics.metrics[k] = v end
  for k, v in pairs(DEFAULT_PEAKS) do analytics.peakStats[k] = v end
  analytics.monsters = {}
  analytics.lootItems = {}
  -- Reset detailed consumption tracking
  analytics.spellsUsed = {}
  analytics.potionsUsed = {}
  analytics.runesUsed = {}
  analytics.peakStats.maxSpeed = Player.speed()
  
  if HealBot and HealBot.resetAnalytics then HealBot.resetAnalytics() end
  if AttackBot and AttackBot.resetAnalytics then AttackBot.resetAnalytics() end
  if EventBus then EventBus.emit("analytics:session:start") end
end

-- ============================================================================
-- LOOT PARSING (Server message listener)
-- ============================================================================

local COIN_VALUES = {
  ["gold coin"] = 1,
  ["platinum coin"] = 100,
  ["crystal coin"] = 10000
}

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Parse values like "1.2k" -> 1200, "2.5m" -> 2500000
local function parseValue(str)
  if not str then return 0 end
  str = trim(str:lower())
  local num, suffix = str:match("^([%d%.]+)([km]?)$")
  if not num then
    -- Try plain number
    return tonumber(str) or 0
  end
  local value = tonumber(num) or 0
  if suffix == "k" then
    value = value * 1000
  elseif suffix == "m" then
    value = value * 1000000
  end
  return math.floor(value)
end

local function normalizeItemName(name)
  if not name then return nil end
  local lowered = trim(name:lower())
  -- Collapse multiple spaces to single space
  lowered = lowered:gsub("%s+", " ")
  -- Remove article prefixes
  lowered = lowered:gsub("^a ", ""):gsub("^an ", ""):gsub("^the ", "")
  -- Normalize coins plural (match any coin type)
  lowered = lowered:gsub("coins$", "coin")
  -- Ensure proper spacing around "coin"
  lowered = lowered:gsub("%s+coin$", " coin")
  -- Try singular if plural not found in LootItems
  if LootItems and not LootItems[lowered] and lowered:sub(-1) == "s" then
    local singular = lowered:sub(1, -2)
    if LootItems[singular] then
      lowered = singular
    end
  end
  return lowered
end

local function parseLootMessage(text)
  if not text then return nil end
  
  -- Clean up the text: remove newlines, collapse spaces
  local cleanText = text:gsub("[\r\n]+", " "):gsub("%s+", " ")
  
  -- Must contain "Loot of" (case insensitive check)
  if not cleanText:lower():find("loot of") then return nil end
  
  -- Strip timestamp if present (e.g., "18:41 ")
  cleanText = cleanText:gsub("^%d%d:%d%d%s*", "")
  
  -- Format: "Loot of a cyclops drone: 27 gold coins" or "Loot of a cyclops: nothing"
  -- May optionally have " - (Ngp)" suffix from loot channel
  
  -- First strip optional value suffix if present
  cleanText = cleanText:gsub("%s*%-%s*%([%d%.]+[km]?gp%)%s*$", "")
  
  -- Find the colon that separates creature from items
  local colonPos = cleanText:find(":")
  if not colonPos then return nil end
  
  local creaturePart = cleanText:sub(1, colonPos - 1)
  local itemsPart = trim(cleanText:sub(colonPos + 1))
  
  -- Extract creature name: remove "Loot of " prefix and article
  local creature = creaturePart:lower():gsub("^loot of%s*", "")
  creature = creature:gsub("^a%s+", ""):gsub("^an%s+", ""):gsub("^the%s+", "")
  creature = trim(creature)
  
  if not creature or creature == "" or not itemsPart or itemsPart == "" then 
    return nil 
  end
  
  local items = {}
  local totalValue = 0
  
  -- Check for "nothing" loot
  if itemsPart:lower():find("nothing") then
    return { creature = trim(creature), totalValue = 0, items = items }
  end
  
  -- Parse each item separated by comma
  for part in itemsPart:gmatch("[^,]+") do
    local entry = trim(part)
    if entry ~= "" then
      -- Try to match "N item" pattern (e.g., "20 gold coins", "a short sword")
      local count, itemName = entry:match("^(%d+)%s+(.+)$")
      if count then
        count = tonumber(count) or 1
      else
        -- Check for "a/an item" pattern
        itemName = entry:match("^an?%s+(.+)$")
        if itemName then
          count = 1
        else
          -- Just the item name
          itemName = entry
          count = 1
        end
      end
      
      local normalized = normalizeItemName(itemName)
      local price = 0
      if normalized and LootItems then
        price = LootItems[normalized] or 0
      end
      
      -- Calculate value from coins directly
      if normalized then
        local coinVal = COIN_VALUES[normalized]
        if coinVal then
          totalValue = totalValue + (coinVal * count)
        else
          totalValue = totalValue + (price * count)
        end
      end
      
      items[#items + 1] = { 
        name = normalized or itemName:lower(), 
        display = itemName, 
        count = count, 
        price = price 
      }
    end
  end
  
  return { creature = trim(creature), totalValue = totalValue, items = items }
end

local function recordLoot(entry)
  if not entry or not isSessionActive() then return end
  local m = analytics.metrics
  m.lootDrops = (m.lootDrops or 0) + 1
  m.lootValue = (m.lootValue or 0) + (entry.totalValue or 0)

  analytics.lootItems = analytics.lootItems or {}

  for _, itm in ipairs(entry.items or {}) do
    local nameKey = itm.name or itm.display
    if nameKey then
      local bucket = analytics.lootItems[nameKey] or {count = 0, value = 0}
      bucket.count = bucket.count + (itm.count or 0)
      local itemValue = (itm.price or 0) * (itm.count or 0)
      bucket.value = bucket.value + itemValue
      analytics.lootItems[nameKey] = bucket
      -- Track gold from coins
      if COIN_VALUES[nameKey] then
        m.lootGold = (m.lootGold or 0) + COIN_VALUES[nameKey] * (itm.count or 0)
      end
    end
  end
end

-- Listen to server text messages (loot appears here, not in onTalk)
onTextMessage(function(mode, text)
  if not text then return end
  local entry = parseLootMessage(text)
  if entry then
    recordLoot(entry)
  end
end)

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
-- CONSUMPTION TRACKING API
-- Provides functions for HealBot and TargetBot to report spell/potion/rune usage
-- ============================================================================

local Analytics = {}

-- Track a healing spell cast (called by HealBot/HealEngine)
-- @param spellName string - The spell name (e.g., "exura vita")
-- @param manaCost number - Mana cost of the spell
function Analytics.trackHealSpell(spellName, manaCost)
  if not isSessionActive() then return end
  spellName = spellName or "unknown"
  manaCost = manaCost or 0
  
  analytics.metrics.healSpellsCast = (analytics.metrics.healSpellsCast or 0) + 1
  analytics.metrics.manaSpent = (analytics.metrics.manaSpent or 0) + manaCost
  
  analytics.spellsUsed = analytics.spellsUsed or {}
  if not analytics.spellsUsed[spellName] then
    analytics.spellsUsed[spellName] = { count = 0, mana = 0, type = "heal" }
  end
  analytics.spellsUsed[spellName].count = analytics.spellsUsed[spellName].count + 1
  analytics.spellsUsed[spellName].mana = analytics.spellsUsed[spellName].mana + manaCost
end

-- Track an attack spell cast (called by TargetBot)
-- @param spellName string - The spell name (e.g., "exori gran")
-- @param manaCost number - Mana cost of the spell
function Analytics.trackAttackSpell(spellName, manaCost)
  if not isSessionActive() then return end
  spellName = spellName or "unknown"
  manaCost = manaCost or 0
  
  analytics.metrics.attackSpellsCast = (analytics.metrics.attackSpellsCast or 0) + 1
  analytics.metrics.manaSpent = (analytics.metrics.manaSpent or 0) + manaCost
  
  analytics.spellsUsed = analytics.spellsUsed or {}
  if not analytics.spellsUsed[spellName] then
    analytics.spellsUsed[spellName] = { count = 0, mana = 0, type = "attack" }
  end
  analytics.spellsUsed[spellName].count = analytics.spellsUsed[spellName].count + 1
  analytics.spellsUsed[spellName].mana = analytics.spellsUsed[spellName].mana + manaCost
end

-- Track a support spell cast (haste, mana shield, etc.)
-- @param spellName string - The spell name (e.g., "utani hur")
-- @param manaCost number - Mana cost of the spell
function Analytics.trackSupportSpell(spellName, manaCost)
  if not isSessionActive() then return end
  spellName = spellName or "unknown"
  manaCost = manaCost or 0
  
  analytics.metrics.supportSpellsCast = (analytics.metrics.supportSpellsCast or 0) + 1
  analytics.metrics.manaSpent = (analytics.metrics.manaSpent or 0) + manaCost
  
  analytics.spellsUsed = analytics.spellsUsed or {}
  if not analytics.spellsUsed[spellName] then
    analytics.spellsUsed[spellName] = { count = 0, mana = 0, type = "support" }
  end
  analytics.spellsUsed[spellName].count = analytics.spellsUsed[spellName].count + 1
  analytics.spellsUsed[spellName].mana = analytics.spellsUsed[spellName].mana + manaCost
end

-- Track a potion used (called by HealBot)
-- @param potionName string - The potion name (e.g., "great mana potion")
-- @param potionType string - Type: "heal", "mana", or "other"
function Analytics.trackPotion(potionName, potionType)
  if not isSessionActive() then return end
  potionName = potionName or "unknown potion"
  potionType = potionType or "other"
  
  analytics.metrics.potionsUsed = (analytics.metrics.potionsUsed or 0) + 1
  
  if potionType == "heal" then
    analytics.metrics.healPotionsUsed = (analytics.metrics.healPotionsUsed or 0) + 1
  elseif potionType == "mana" then
    analytics.metrics.manaPotionsUsed = (analytics.metrics.manaPotionsUsed or 0) + 1
  end
  
  analytics.potionsUsed = analytics.potionsUsed or {}
  analytics.potionsUsed[potionName] = (analytics.potionsUsed[potionName] or 0) + 1
end

-- Track a rune used (called by TargetBot - kept for backwards compatibility)
-- Note: Runes are now also tracked via onUseWith hook
-- @param runeName string - The rune name (e.g., "sudden death rune")
-- @param runeType string - Type: "attack" or "heal"
function Analytics.trackRune(runeName, runeType)
  -- This function is now mostly handled by the onUseWith hook
  -- But we keep it for any direct API calls
  if not isSessionActive() then return end
  runeName = runeName or "unknown rune"
  runeType = runeType or "attack"
  
  analytics.metrics.runesUsed = (analytics.metrics.runesUsed or 0) + 1
  
  if runeType == "attack" then
    analytics.metrics.attackRunesUsed = (analytics.metrics.attackRunesUsed or 0) + 1
  elseif runeType == "heal" then
    analytics.metrics.healRunesUsed = (analytics.metrics.healRunesUsed or 0) + 1
  end
  
  analytics.runesUsed = analytics.runesUsed or {}
  analytics.runesUsed[runeName] = (analytics.runesUsed[runeName] or 0) + 1
  
  -- Additional debug: verify it was stored
  if DEBUG_HUNT_ANALYZER then
    print("[HuntAnalytics] Runes used table: " .. tostring(analytics.runesUsed[runeName]) .. "x " .. runeName)
  end
end

-- Get all consumption data for external use
function Analytics.getConsumption()
  return {
    spells = analytics.spellsUsed or {},
    potions = analytics.potionsUsed or {},
    runes = analytics.runesUsed or {},
    totals = {
      spellsCast = analytics.metrics.spellsCast or 0,
      healSpells = analytics.metrics.healSpellsCast or 0,
      attackSpells = analytics.metrics.attackSpellsCast or 0,
      supportSpells = analytics.metrics.supportSpellsCast or 0,
      potions = analytics.metrics.potionsUsed or 0,
      healPotions = analytics.metrics.healPotionsUsed or 0,
      manaPotions = analytics.metrics.manaPotionsUsed or 0,
      runes = analytics.metrics.runesUsed or 0,
      attackRunes = analytics.metrics.attackRunesUsed or 0,
      healRunes = analytics.metrics.healRunesUsed or 0,
      manaSpent = analytics.metrics.manaSpent or 0
    }
  }
end

-- Expose Analytics API globally for HealBot/TargetBot integration
HuntAnalytics = Analytics

-- ============================================================================
-- GLOBAL RUNE TRACKING HOOK
-- ============================================================================
-- This hooks into ALL useWith calls to track rune usage automatically,
-- regardless of whether runes are used via TargetBot, combo, hotkey, etc.

-- List of known rune item IDs (expand as needed)
local RUNE_ITEM_IDS = {
  -- Attack Runes
  [3155] = "sudden death rune",
  [3200] = "thunderstorm rune",
  [3161] = "destroy field rune",
  [3180] = "fire bomb rune", 
  [3178] = "paralyze rune",
  [3188] = "avalanche rune",
  [3189] = "ultimate healing rune",
  [3152] = "energy bomb rune",
  [3149] = "wild growth rune",
  [3191] = "great fireball rune",
  [3179] = "heavy magic missile rune",
  [3198] = "explosion rune",
  [3203] = "fire wall rune",
  [3174] = "soulfire rune",
  [3197] = "energy wall rune",
  [3175] = "stalagmite rune",
  [3202] = "poison wall rune",
  [3173] = "icicle rune",
  [3164] = "stone shower rune",
  [3153] = "magic wall rune",
  -- Healing Runes
  [3160] = "intense healing rune",
  -- Add more rune IDs as needed
}

-- Check if an item is a rune based on ID or name pattern
local function isRune(itemId)
  if RUNE_ITEM_IDS[itemId] then
    return true, RUNE_ITEM_IDS[itemId], "attack"
  end
  
  -- Try to get item info from g_things
  if g_things and g_things.getThingType then
    local ok, thing = pcall(function() return g_things.getThingType(itemId, ThingCategoryItem) end)
    if ok and thing then
      -- Try getName
      if thing.getName and type(thing.getName) == "function" then
        local nameOk, name = pcall(function() return thing:getName() end)
        if nameOk and name and name:lower():find("rune") then
          local runeType = name:lower():find("healing") and "heal" or "attack"
          return true, name:lower(), runeType
        end
      end
      -- Try getMarketData
      if thing.getMarketData and type(thing.getMarketData) == "function" then
        local mdOk, marketData = pcall(function() return thing:getMarketData() end)
        if mdOk and marketData and marketData.name and marketData.name:lower():find("rune") then
          local runeType = marketData.name:lower():find("healing") and "heal" or "attack"
          return true, marketData.name:lower(), runeType
        end
      end
    end
  end
  
  return false, nil, nil
end

-- Hook into ALL useWith calls to track rune usage
onUseWith(function(pos, itemId, target, subType)
  if not isSessionActive() then return end
  
  local isRuneItem, runeName, runeType = isRune(itemId)
  if isRuneItem then
    -- Track the rune
    runeName = runeName or ("rune #" .. tostring(itemId))
    runeType = runeType or "attack"
    
    analytics.metrics.runesUsed = (analytics.metrics.runesUsed or 0) + 1
    
    if runeType == "attack" then
      analytics.metrics.attackRunesUsed = (analytics.metrics.attackRunesUsed or 0) + 1
    elseif runeType == "heal" then
      analytics.metrics.healRunesUsed = (analytics.metrics.healRunesUsed or 0) + 1
    end
    
    analytics.runesUsed = analytics.runesUsed or {}
    analytics.runesUsed[runeName] = (analytics.runesUsed[runeName] or 0) + 1
  end
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
-- INSIGHTS ENGINE (Analysis)
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

  -- Loot economy metrics
  metrics.lootValue = m.lootValue or 0
  metrics.lootGold = m.lootGold or 0
  metrics.lootDrops = m.lootDrops or 0
  metrics.lootValuePerHour = perHour(metrics.lootValue, elapsed)
  metrics.lootGoldPerHour = perHour(metrics.lootGold, elapsed)
  metrics.lootPerKill = m.kills > 0 and (metrics.lootValue / m.kills) or 0
  
  -- Stamina efficiency (XP per minute of stamina)
  local staminaUsed = (analytics.session.startStamina or 0) - (Player.stamina() or 0)
  metrics.xpPerStaminaMin = staminaUsed > 0 and (xpGained / staminaUsed) or 0
  
  -- Consumption metrics
  metrics.potionsPerHour = perHour(m.potionsUsed or 0, elapsed)
  metrics.runesPerHour = perHour(m.runesUsed or 0, elapsed)
  metrics.runesPerKill = m.kills > 0 and ((m.runesUsed or 0) / m.kills) or 0
  metrics.healSpellsPerHour = perHour(m.healSpellsCast or 0, elapsed)
  metrics.attackSpellsPerHour = perHour(m.attackSpellsCast or 0, elapsed)
  metrics.manaSpentPerHour = perHour(m.manaSpent or 0, elapsed)
  metrics.manaPerKill = m.kills > 0 and ((m.manaSpent or 0) / m.kills) or 0
  
  -- Healing efficiency (HP healed per heal spell)
  local healActions = (m.healSpellsCast or 0) + (m.healPotionsUsed or 0)
  metrics.healingPerAction = healActions > 0 and (m.healingDone / healActions) or 0
  
  -- Damage efficiency (damage per attack spell/rune)
  local attackActions = (m.attackSpellsCast or 0) + (m.attackRunesUsed or 0)
  metrics.attackActionsPerKill = m.kills > 0 and (attackActions / m.kills) or 0
  
  return metrics
end

-- ============================================================================
-- INSIGHTS ANALYSIS
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
  
  -- Mana potion analysis
  if (m.manaPotionsUsed or 0) >= 10 then
    local manaPotsPerHour = metrics.potionsPerHour or 0
    if manaPotsPerHour > 200 then
      addInsight(results, SEVERITY.WARNING, "Resources", string.format("Very high mana potion use: %.0f/h. Consider lower MP threshold.", manaPotsPerHour), sessionConfidence)
    elseif manaPotsPerHour > 100 then
      addInsight(results, SEVERITY.TIP, "Resources", string.format("High mana consumption: %.0f potions/h.", manaPotsPerHour), sessionConfidence)
    end
  end
  
  -- Health potion analysis
  if (m.healPotionsUsed or 0) >= 10 then
    local healPotsPerHour = perHour(m.healPotionsUsed or 0, elapsed)
    if healPotsPerHour > 60 then
      addInsight(results, SEVERITY.WARNING, "Resources", string.format("Heavy HP potion use: %.0f/h. Consider adding heal spells.", healPotsPerHour), sessionConfidence)
    end
  end
  
  -- Rune consumption analysis
  if (m.runesUsed or 0) >= 10 then
    local runesPerKill = metrics.runesPerKill or 0
    local runesPerHour = metrics.runesPerHour or 0
    if runesPerKill > 2 then
      addInsight(results, SEVERITY.WARNING, "Resources", string.format("High rune use: %.1f/kill. Consider spell attacks.", runesPerKill), sessionConfidence)
    elseif runesPerKill < 0.5 and m.kills > 30 then
      addInsight(results, SEVERITY.INFO, "Resources", string.format("Efficient rune usage: %.1f/kill", runesPerKill), sessionConfidence)
    end
  end
  
  -- Mana efficiency analysis
  if (m.manaSpent or 0) > 5000 and m.kills >= 20 then
    local manaPerKill = metrics.manaPerKill or 0
    if manaPerKill > 500 then
      addInsight(results, SEVERITY.TIP, "Efficiency", string.format("High mana/kill: %.0f. Optimize spell selection.", manaPerKill), sessionConfidence)
    elseif manaPerKill < 100 and manaPerKill > 0 then
      addInsight(results, SEVERITY.INFO, "Efficiency", string.format("Excellent mana efficiency: %.0f mana/kill", manaPerKill), sessionConfidence)
    end
  end
  
  -- Healing spell efficiency
  if (m.healSpellsCast or 0) >= 10 and m.healingDone > 1000 then
    local healPerSpell = metrics.healingPerAction or 0
    if healPerSpell < 100 then
      addInsight(results, SEVERITY.TIP, "Healing", "Low heal per cast. Consider stronger healing spells.", sessionConfidence)
    elseif healPerSpell > 400 then
      addInsight(results, SEVERITY.INFO, "Healing", string.format("Great healing efficiency: %.0f HP/action", healPerSpell), sessionConfidence)
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
  
  -- ========== RESOURCE EFFICIENCY (15 pts) ==========
  local resScore = 0
  
  -- Potion efficiency (5 pts)
  if m.kills > 10 then
    local ppk = metrics.potionsPerKill
    if ppk < 0.3 then resScore = resScore + 5
    elseif ppk < 0.7 then resScore = resScore + 4
    elseif ppk < 1.2 then resScore = resScore + 3
    elseif ppk < 2.0 then resScore = resScore + 2
    elseif ppk < 3.0 then resScore = resScore + 1
    elseif ppk > 4.0 then resScore = resScore - 1
    end
  else
    resScore = resScore + 2  -- Neutral if not enough data
  end
  
  -- Rune efficiency (5 pts)
  if m.kills > 10 and (m.runesUsed or 0) > 0 then
    local rpk = metrics.runesPerKill or 0
    if rpk < 0.5 then resScore = resScore + 5
    elseif rpk < 1.0 then resScore = resScore + 4
    elseif rpk < 1.5 then resScore = resScore + 3
    elseif rpk < 2.5 then resScore = resScore + 2
    elseif rpk > 3.0 then resScore = resScore - 1
    end
  else
    resScore = resScore + 2  -- No runes = spell-based (efficient)
  end
  
  -- Mana efficiency (5 pts)
  if m.kills > 10 and (m.manaSpent or 0) > 0 then
    local mpk = metrics.manaPerKill or 0
    if mpk < 100 then resScore = resScore + 5
    elseif mpk < 200 then resScore = resScore + 4
    elseif mpk < 350 then resScore = resScore + 3
    elseif mpk < 500 then resScore = resScore + 2
    elseif mpk > 700 then resScore = resScore - 1
    end
  else
    resScore = resScore + 2
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
    elseif metrics.lootValuePerHour and metrics.lootValuePerHour > 0 then
      -- Fallback: use parsed loot value if bottingStats unavailable
      local profitPerHour = metrics.lootValuePerHour
      if profitPerHour > 100000 then score = score + 5
      elseif profitPerHour > 50000 then score = score + 4
      elseif profitPerHour > 20000 then score = score + 3
      elseif profitPerHour > 0 then score = score + 1
      elseif profitPerHour < -30000 then score = score - 2
      end
    end
  elseif metrics.lootValuePerHour and metrics.lootValuePerHour > 0 then
    local profitPerHour = metrics.lootValuePerHour
    if profitPerHour > 100000 then score = score + 5
    elseif profitPerHour > 50000 then score = score + 4
    elseif profitPerHour > 20000 then score = score + 3
    elseif profitPerHour > 0 then score = score + 1
    elseif profitPerHour < -30000 then score = score - 2
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
  table.insert(lines, "          HUNT ANALYZER v1.0")
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
  
  -- Monsters Killed
  local monsterLines = {}
  local monsterList = {}
  for name, count in pairs(analytics.monsters or {}) do
    table.insert(monsterList, {name = name, count = count})
  end
  -- Sort by count descending
  table.sort(monsterList, function(a, b) return a.count > b.count end)
  -- Show up to 10 monsters
  local monsterLimit = math.min(10, #monsterList)
  for i = 1, monsterLimit do
    local mon = monsterList[i]
    table.insert(monsterLines, string.format("%dx %s", mon.count, mon.name))
  end
  if #monsterList > monsterLimit then
    table.insert(monsterLines, string.format("... and %d more types", #monsterList - monsterLimit))
  end
  if #monsterLines == 0 then
    table.insert(monsterLines, "No monsters killed yet")
  end
  addSection(lines, "MONSTERS KILLED", monsterLines)
  
  -- Spells Used
  local spellLines = {}
  local spellList = {}
  for name, data in pairs(analytics.spellsUsed or {}) do
    table.insert(spellList, {name = name, count = data.count or 0, mana = data.mana or 0, type = data.type or "other"})
  end
  table.sort(spellList, function(a, b) return a.count > b.count end)
  local spellLimit = math.min(8, #spellList)
  for i = 1, spellLimit do
    local sp = spellList[i]
    local typeIcon = sp.type == "heal" and "[H]" or sp.type == "attack" and "[A]" or "[S]"
    table.insert(spellLines, string.format("%s %dx %s", typeIcon, sp.count, sp.name))
  end
  if #spellList > spellLimit then
    table.insert(spellLines, string.format("... and %d more spells", #spellList - spellLimit))
  end
  -- Add summary line
  local totalSpells = (m.healSpellsCast or 0) + (m.attackSpellsCast or 0) + (m.supportSpellsCast or 0)
  if totalSpells > 0 then
    table.insert(spellLines, 1, string.format("Total: %d (%.0f/h) | Mana: %s", 
      totalSpells, perHour(totalSpells, elapsed), formatNum(m.manaSpent or 0)))
  end
  if #spellLines == 0 then
    table.insert(spellLines, "No spells tracked yet")
  end
  addSection(lines, "SPELLS USED", spellLines)
  
  -- Potions Used
  local potionLines = {}
  local potionList = {}
  for name, count in pairs(analytics.potionsUsed or {}) do
    table.insert(potionList, {name = name, count = count})
  end
  table.sort(potionList, function(a, b) return a.count > b.count end)
  local potionLimit = math.min(6, #potionList)
  for i = 1, potionLimit do
    local pot = potionList[i]
    table.insert(potionLines, string.format("%dx %s", pot.count, pot.name))
  end
  -- Add summary line
  local totalPotions = m.potionsUsed or 0
  if totalPotions > 0 then
    local healPots = m.healPotionsUsed or 0
    local manaPots = m.manaPotionsUsed or 0
    table.insert(potionLines, 1, string.format("Total: %d (%.0f/h) | HP: %d | MP: %d", 
      totalPotions, metrics.potionsPerHour or 0, healPots, manaPots))
  end
  if #potionLines == 0 then
    table.insert(potionLines, "No potions tracked yet")
  end
  addSection(lines, "POTIONS USED", potionLines)
  
  -- Runes Used
  local runeLines = {}
  local runeList = {}
  
  -- Debug: Show raw table state
  local runeTableSize = 0
  if analytics.runesUsed then
    for _ in pairs(analytics.runesUsed) do runeTableSize = runeTableSize + 1 end
  end
  
  -- Collect rune data from analytics table
  if analytics.runesUsed then
    for name, count in pairs(analytics.runesUsed) do
      if count and count > 0 then
        table.insert(runeList, {name = name, count = count})
      end
    end
  end
  
  -- Sort by count (highest first)
  if #runeList > 0 then
    table.sort(runeList, function(a, b) return a.count > b.count end)
    local runeLimit = math.min(6, #runeList)
    for i = 1, runeLimit do
      local rn = runeList[i]
      table.insert(runeLines, string.format("%dx %s", rn.count, rn.name))
    end
    if #runeList > runeLimit then
      table.insert(runeLines, string.format("... and %d more runes", #runeList - runeLimit))
    end
  end
  
  -- Add summary line
  local totalRunes = m.runesUsed or 0
  if totalRunes > 0 then
    local attackRunes = m.attackRunesUsed or 0
    local healRunes = m.healRunesUsed or 0
    table.insert(runeLines, 1, string.format("Total: %d (%.0f/h) | Attack: %d | Heal: %d", 
      totalRunes, metrics.runesPerHour or 0, attackRunes, healRunes))
  end
  
  if #runeLines == 0 then
    table.insert(runeLines, string.format("No runes tracked (table:%d, metric:%d)", runeTableSize, totalRunes))
  end
  addSection(lines, "RUNES USED", runeLines)
  
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
    "Speed: " .. Player.speed()
  })
  
  -- Loot
  local lootLines = {
    "Total Value: " .. formatNum(m.lootValue) .. " gp (" .. formatNum(math.floor(metrics.lootValuePerHour)) .. "/h)",
    "Gold Coins: " .. formatNum(m.lootGold) .. " (" .. formatNum(math.floor(metrics.lootGoldPerHour)) .. "/h)",
    "Drops Parsed: " .. formatNum(m.lootDrops),
    "Avg/Kill: " .. formatNum(math.floor(metrics.lootPerKill)) .. " gp"
  }

  local topItems = {}
  for name, data in pairs(analytics.lootItems or {}) do
    topItems[#topItems + 1] = {name = name, count = data.count or 0, value = data.value or 0}
  end
  table.sort(topItems, function(a, b) return a.value > b.value end)
  local limit = math.min(5, #topItems)
  for i = 1, limit do
    local itm = topItems[i]
    lootLines[#lootLines + 1] = string.format("%d) %s x%d (%s gp)", i, itm.name, itm.count, formatNum(math.floor(itm.value)))
  end
  addSection(lines, "LOOT", lootLines)

  -- Score
  local score = Insights.calculateScore()
  addSection(lines, "HUNT SCORE", { Insights.scoreBar(score) })
  
  -- Insights
  local insightsList = Insights.analyze()
  table.insert(lines, "[INSIGHTS]")
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

-- Live update flag for analytics window (must be defined before showAnalytics)
local liveUpdatesActive = false
local lastSummaryText = ""

local function stopLiveUpdates()
  liveUpdatesActive = false
end

local function doLiveUpdate()
  if not liveUpdatesActive then return end
  
  if analyticsWindow and analyticsWindow.content and analyticsWindow.content.textContent then
    pcall(function()
      local newText = buildSummary()
      if newText ~= lastSummaryText then
        analyticsWindow.content.textContent:setText(newText)
        lastSummaryText = newText
      end
    end)
    -- Schedule next update
    schedule(1000, doLiveUpdate)
  else
    -- Window closed, stop live updates
    liveUpdatesActive = false
  end
end

local function startLiveUpdates()
  if liveUpdatesActive then return end  -- Already running
  liveUpdatesActive = true
  -- Start the update loop
  schedule(1000, doLiveUpdate)
end

local function showAnalytics()
  if analyticsWindow then 
    stopLiveUpdates()  -- Stop any existing live updates
    pcall(function() analyticsWindow:destroy() end)
    analyticsWindow = nil 
  end
  
  -- Auto-start session if not active
  if not isSessionActive() then
    startSession()
  end
  
  -- Try to create window, fall back to console output
  local ok, win = pcall(function() return UI.createWindow('HuntAnalyzerWindow') end)
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
      -- Keep refresh button for manual refresh, but it's less needed now
      analyticsWindow.buttons.refreshButton.onClick = function() 
        if analyticsWindow and analyticsWindow.content and analyticsWindow.content.textContent then
          analyticsWindow.content.textContent:setText(buildSummary()) 
        end
      end
    end
    if analyticsWindow.buttons.closeButton then
      analyticsWindow.buttons.closeButton.onClick = function() 
        stopLiveUpdates()  -- Stop live updates when closing
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
  
  -- Start live updates
  startLiveUpdates()
end

-- ============================================================================
-- MACROS (Hidden - runs automatically in background)
-- ============================================================================

-- Background tracking (no visible button)
macro(5000, function()
  if CaveBot and type(CaveBot.isOn) == "function" and CaveBot.isOn() and not isSessionActive() then
    startSession()
  end
  updateTracking()
end)

macro(1000, function() updateTracking() end)

-- ============================================================================
-- UI BUTTON
-- ============================================================================

UI.Separator();

UI.Label("Statistics:")

local btn = UI.Button("Hunt Analyzer", function()
  local ok, err = pcall(showAnalytics)
  if not ok then warn("[HuntAnalyzer] " .. tostring(err)) print(buildSummary()) end
end)
if btn then btn:setTooltip("View hunting analytics") end

-- Monster Insights button below Hunt Analyzer
local monsterBtn = UI.Button("Monster Insights", function()
  -- Ensure monster inspector is loaded and window exists
  if not MonsterInspectorWindow then
    if nExBot and nExBot.MonsterInspector and nExBot.MonsterInspector.showWindow then
      nExBot.MonsterInspector.showWindow()
    else
      -- Try to load it manually
      pcall(function() dofile("/targetbot/monster_inspector.lua") end)
      if nExBot and nExBot.MonsterInspector and nExBot.MonsterInspector.showWindow then
        nExBot.MonsterInspector.showWindow()
      end
    end
  else
    MonsterInspectorWindow:setVisible(not MonsterInspectorWindow:isVisible())
    if MonsterInspectorWindow:isVisible() then
      if nExBot and nExBot.MonsterInspector and nExBot.MonsterInspector.refreshPatterns then
        nExBot.MonsterInspector.refreshPatterns()
      elseif refreshPatterns then
        refreshPatterns()
      end
    end
  end
end)
if monsterBtn then monsterBtn:setTooltip("View learned monster patterns and samples") end

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
  getTrends = function() return trendData end,
  
  -- Access session start skills data
  -- @param skillId number 0-6 for combat skills (Fist, Club, Sword, Axe, Distance, Shielding, Fishing), or 7 for Magic Level
  -- @return number The skill level at session start, or nil if no active session
  getStartSkill = function(skillId)
    if not analytics.session or not analytics.session.startSkills then return nil end
    if skillId == 7 then
      return analytics.session.startSkills["mlevel"]
    elseif skillId >= 0 and skillId <= 6 then
      return analytics.session.startSkills["skill_" .. skillId]
    end
    return nil
  end
}

print("[HuntAnalyzer] v1.0 loaded")
