--[[
  SmartHunt Analytics Module v2.0
  
  Event-driven hunting analytics using EventBus pattern.
  
  Principles Applied:
  - SRP: Each function has a single responsibility
  - DRY: Shared utilities, no code duplication
  - KISS: Simple, readable implementation
  - Pure Functions: Calculations don't modify state
  
  Events Used (from OTClient):
  - onWalk: Track movement
  - onCreatureHealthPercentChange: Track kills
  - onManaChange: Detect mana usage
  - onSpellCooldown: Track spell casts
  - onUse: Track item usage
  - onTextMessage: Detect "You are full" etc.
]]

setDefaultTab("Main")

-- ============================================================================
-- STORAGE INITIALIZATION
-- ============================================================================

local function initStorage()
  if not storage.analytics then
    storage.analytics = {
      session = {
        startTime = 0,
        startXp = 0,
        startSkills = {},
        startCap = 0,
        startStamina = 0,
        startBalance = 0,
        active = false
      },
      metrics = {
        tilesWalked = 0,
        kills = 0,
        spellsCast = 0,
        potionsUsed = 0,
        runesUsed = 0,
        damageTaken = 0,
        healingDone = 0,
        deathCount = 0,
        nearDeathCount = 0,  -- HP dropped below 20%
        idleTime = 0,        -- Time spent not moving/fighting
        combatTime = 0       -- Time in combat
      },
      skills = {},
      supplies = {},
      monsters = {},
      peakStats = {
        maxXpPerHour = 0,
        maxKillsPerHour = 0,
        lowestHpPercent = 100,
        highestDamageHit = 0
      }
    }
  end
  -- Ensure new fields exist for existing storage
  analytics = storage.analytics
  analytics.session.startCap = analytics.session.startCap or 0
  analytics.session.startStamina = analytics.session.startStamina or 0
  analytics.session.startBalance = analytics.session.startBalance or 0
  analytics.metrics.deathCount = analytics.metrics.deathCount or 0
  analytics.metrics.nearDeathCount = analytics.metrics.nearDeathCount or 0
  analytics.metrics.idleTime = analytics.metrics.idleTime or 0
  analytics.metrics.combatTime = analytics.metrics.combatTime or 0
  analytics.peakStats = analytics.peakStats or {
    maxXpPerHour = 0,
    maxKillsPerHour = 0,
    lowestHpPercent = 100,
    highestDamageHit = 0
  }
  return storage.analytics
end

local analytics = initStorage()

-- ============================================================================
-- PURE UTILITY FUNCTIONS
-- ============================================================================

-- Format number with thousands separator
local function formatNum(n)
  if not n or n == 0 then return "0" end
  local s = tostring(math.floor(n))
  local result = ""
  local len = #s
  for i = 1, len do
    if i > 1 and (len - i + 1) % 3 == 0 then
      result = result .. ","
    end
    result = result .. s:sub(i, i)
  end
  return result
end

-- Format duration in minutes to readable string
local function formatDuration(ms)
  if not ms or ms <= 0 then return "0m" end
  local seconds = math.floor(ms / 1000)
  local minutes = math.floor(seconds / 60)
  local hours = math.floor(minutes / 60)
  minutes = minutes % 60
  if hours > 0 then
    return string.format("%dh %dm", hours, minutes)
  end
  return string.format("%dm", minutes)
end

-- Calculate per-hour rate
local function perHour(value, elapsedMs)
  if not elapsedMs or elapsedMs <= 0 then return 0 end
  return value / (elapsedMs / 1000 / 3600)
end

-- Get current session elapsed time in ms
local function getElapsed()
  if not analytics.session.active then return 0 end
  return now - analytics.session.startTime
end

-- Get analytics from HealBot if available
local function getHealBotData()
  if HealBot and HealBot.getAnalytics then
    return HealBot.getAnalytics()
  end
  return nil
end

-- Get analytics from AttackBot if available
local function getAttackBotData()
  if AttackBot and AttackBot.getAnalytics then
    return AttackBot.getAnalytics()
  end
  return nil
end

-- Check if table has any items
local function hasData(tbl)
  if not tbl then return false end
  for _ in pairs(tbl) do return true end
  return false
end

-- ============================================================================
-- SKILL TRACKING
-- ============================================================================

local SKILL_NAMES = {
  [0] = "Fist",
  [1] = "Club", 
  [2] = "Sword",
  [3] = "Axe",
  [4] = "Distance",
  [5] = "Shielding",
  [6] = "Fishing",
  [7] = "Magic Level"
}

local function captureSkills()
  local skills = {}
  if player then
    for id = 0, 6 do
      skills[id] = player:getSkillLevel(id) or 0
    end
    skills[7] = mlevel() or 0
  end
  return skills
end

local function calculateSkillGains(startSkills, currentSkills)
  local gains = {}
  for id, startLevel in pairs(startSkills or {}) do
    local current = currentSkills[id] or 0
    local gain = current - startLevel
    if gain > 0 then
      gains[id] = { start = startLevel, current = current, gain = gain }
    end
  end
  return gains
end

-- ============================================================================
-- SESSION MANAGEMENT
-- ============================================================================

-- Get current balance from Analyzer if available
local function getCurrentBalance()
  if bottingStats then
    local loot, waste, balance = bottingStats()
    return balance or 0
  end
  return 0
end

-- Get stamina in minutes
local function getStaminaMinutes()
  if player and player.getStamina then
    return player:getStamina() or 0
  end
  if stamina then
    return stamina() or 0
  end
  return 0
end

-- Get free capacity
local function getFreeCap()
  if freecap then
    return freecap() or 0
  end
  if player and player.getFreeCapacity then
    return player:getFreeCapacity() or 0
  end
  return 0
end

local function startSession()
  -- Capture starting values
  local startBalance = getCurrentBalance()
  local startStamina = getStaminaMinutes()
  local startCap = getFreeCap()
  
  analytics.session = {
    startTime = now,
    startXp = exp() or 0,
    startSkills = captureSkills(),
    startCap = startCap,
    startStamina = startStamina,
    startBalance = startBalance,
    active = true
  }
  analytics.metrics = {
    tilesWalked = 0,
    kills = 0,
    spellsCast = 0,
    potionsUsed = 0,
    runesUsed = 0,
    damageTaken = 0,
    healingDone = 0,
    deathCount = 0,
    nearDeathCount = 0,
    idleTime = 0,
    combatTime = 0
  }
  analytics.supplies = {}
  analytics.monsters = {}
  analytics.peakStats = {
    maxXpPerHour = 0,
    maxKillsPerHour = 0,
    lowestHpPercent = 100,
    highestDamageHit = 0
  }
  
  -- Reset HealBot analytics if available
  if HealBot and HealBot.resetAnalytics then
    HealBot.resetAnalytics()
  end
  
  -- Reset AttackBot analytics if available
  if AttackBot and AttackBot.resetAnalytics then
    AttackBot.resetAnalytics()
  end
  
  EventBus.emit("analytics:session:start")
end

local function endSession()
  analytics.session.active = false
  EventBus.emit("analytics:session:end")
end

local function isSessionActive()
  return analytics.session.active == true
end

-- ============================================================================
-- METRICS COLLECTION (Event Handlers)
-- ============================================================================

-- Track player movement
onWalk(function(creature, oldPos, newPos)
  if creature == player and isSessionActive() then
    analytics.metrics.tilesWalked = analytics.metrics.tilesWalked + 1
  end
end)

-- Track monster kills
onCreatureHealthPercentChange(function(creature, healthPercent)
  if not isSessionActive() then return end
  if creature:isMonster() and healthPercent == 0 then
    analytics.metrics.kills = analytics.metrics.kills + 1
    
    local name = creature:getName()
    analytics.monsters[name] = (analytics.monsters[name] or 0) + 1
  end
end)

-- Track spell casts via cooldown
onSpellCooldown(function(iconId, duration)
  if isSessionActive() and duration > 0 then
    analytics.metrics.spellsCast = analytics.metrics.spellsCast + 1
  end
end)

-- Track item usage (potions, runes)
onUse(function(pos, itemId, stackPos, subType)
  if not isSessionActive() then return end
  
  -- Potion IDs (health, mana, spirit)
  local potionIds = {
    266, 236, 239, 7643, 23373, 23375, 35302,  -- Health
    268, 237, 238, 7642, 23374, 23376,         -- Mana
    7642                                        -- Spirit
  }
  
  -- Rune IDs (attack runes)
  local runeIds = {
    3155, 3161, 3164, 3174, 3180, 3191, 3198, 3200, 3202
  }
  
  for _, id in ipairs(potionIds) do
    if itemId == id then
      analytics.metrics.potionsUsed = analytics.metrics.potionsUsed + 1
      analytics.supplies[itemId] = (analytics.supplies[itemId] or 0) + 1
      return
    end
  end
  
  for _, id in ipairs(runeIds) do
    if itemId == id then
      analytics.metrics.runesUsed = analytics.metrics.runesUsed + 1
      analytics.supplies[itemId] = (analytics.supplies[itemId] or 0) + 1
      return
    end
  end
end)

-- Track health changes for damage/healing and peak stats
local lastHP = 0
local lastHpPercent = 100
onPlayerHealthChange(function(healthPercent)
  if not isSessionActive() then return end
  
  local currentHP = hp() or 0
  local currentPercent = hppercent() or 100
  
  -- Track damage/healing
  if lastHP > 0 then
    local diff = currentHP - lastHP
    if diff < 0 then
      local damageAmount = math.abs(diff)
      analytics.metrics.damageTaken = analytics.metrics.damageTaken + damageAmount
      
      -- Track highest damage hit
      if damageAmount > analytics.peakStats.highestDamageHit then
        analytics.peakStats.highestDamageHit = damageAmount
      end
    elseif diff > 0 then
      analytics.metrics.healingDone = analytics.metrics.healingDone + diff
    end
  end
  
  -- Track lowest HP percent (near death tracking)
  if currentPercent < analytics.peakStats.lowestHpPercent then
    analytics.peakStats.lowestHpPercent = currentPercent
  end
  
  -- Track near-death events (HP drops below 20%)
  if lastHpPercent >= 20 and currentPercent < 20 then
    analytics.metrics.nearDeathCount = analytics.metrics.nearDeathCount + 1
  end
  
  -- Track deaths (HP drops to 0 or very low from a higher value)
  if lastHpPercent > 5 and currentPercent <= 0 then
    analytics.metrics.deathCount = analytics.metrics.deathCount + 1
  end
  
  lastHP = currentHP
  lastHpPercent = currentPercent
end)

-- Peak stats tracking (XP/hour, kills/hour) - updated periodically
local lastPeakCheck = 0
local PEAK_CHECK_INTERVAL = 60000 -- Check every minute

local function updatePeakStats()
  if not isSessionActive() then return end
  if now - lastPeakCheck < PEAK_CHECK_INTERVAL then return end
  lastPeakCheck = now
  
  local elapsed = getElapsed()
  if elapsed < 60000 then return end -- Need at least 1 minute
  
  local elapsedHour = elapsed / 3600000
  local xpGained = (exp() or 0) - (analytics.session.startXp or 0)
  local xpPerHour = xpGained / math.max(0.1, elapsedHour)
  local killsPerHour = analytics.metrics.kills / math.max(0.1, elapsedHour)
  
  if xpPerHour > analytics.peakStats.maxXpPerHour then
    analytics.peakStats.maxXpPerHour = xpPerHour
  end
  if killsPerHour > analytics.peakStats.maxKillsPerHour then
    analytics.peakStats.maxKillsPerHour = killsPerHour
  end
end

-- ============================================================================
-- INSIGHTS ENGINE - Intelligent Analysis & Recommendations
-- ============================================================================

--[[
  The Insights Engine analyzes hunting metrics to provide actionable suggestions.
  
  Analysis Categories:
  1. Efficiency Analysis - XP/hour, kills/hour optimization
  2. Survivability Analysis - Damage taken vs healing patterns
  3. Resource Efficiency - Potion/rune usage optimization
  4. Combat Analysis - Spell usage patterns
  5. Movement Analysis - Walking efficiency
  6. Economic Analysis - Loot/waste/profit tracking
  7. Peak Performance - Best rates achieved
]]

local Insights = {}

-- Severity levels for insights
local SEVERITY = {
  INFO = "INFO",
  TIP = "TIP", 
  WARNING = "WARN",
  CRITICAL = "CRIT"
}

-- Generate all insights based on current data
function Insights.analyze()
  local results = {}
  local elapsed = getElapsed()
  local m = analytics.metrics
  
  -- Need at least 5 minutes of data for meaningful analysis
  if elapsed < 300000 then
    table.insert(results, {
      severity = SEVERITY.INFO,
      category = "Session",
      message = "Need 5+ minutes of data for accurate insights"
    })
    return results
  end
  
  local elapsedMin = elapsed / 60000
  local elapsedHour = elapsed / 3600000
  
  -- ==================== EFFICIENCY ANALYSIS ====================
  
  local xpGained = (exp() or 0) - (analytics.session.startXp or 0)
  local xpPerHour = xpGained / math.max(0.1, elapsedHour)
  local killsPerHour = m.kills / math.max(0.1, elapsedHour)
  
  -- XP per kill ratio
  if m.kills > 10 then
    local xpPerKill = xpGained / m.kills
    if xpPerKill < 100 then
      table.insert(results, {
        severity = SEVERITY.TIP,
        category = "Efficiency",
        message = string.format("Low XP/kill (%.0f). Consider hunting stronger monsters for better XP.", xpPerKill)
      })
    elseif xpPerKill > 1000 then
      table.insert(results, {
        severity = SEVERITY.INFO,
        category = "Efficiency", 
        message = string.format("Excellent XP/kill ratio (%.0f). Good monster selection!", xpPerKill)
      })
    end
  end
  
  -- Kill rate analysis
  if m.kills > 0 and killsPerHour < 50 then
    table.insert(results, {
      severity = SEVERITY.WARNING,
      category = "Efficiency",
      message = string.format("Low kill rate (%.0f/h). Consider: faster targeting, better luring, or easier spawn.", killsPerHour)
    })
  elseif killsPerHour > 200 then
    table.insert(results, {
      severity = SEVERITY.INFO,
      category = "Efficiency",
      message = string.format("High kill rate (%.0f/h). Excellent hunting speed!", killsPerHour)
    })
  end
  
  -- ==================== SURVIVABILITY ANALYSIS ====================
  
  local damageRatio = 0
  if m.healingDone > 0 then
    damageRatio = m.damageTaken / m.healingDone
  end
  
  -- Damage vs Healing balance
  if m.damageTaken > 0 and m.healingDone > 0 then
    if damageRatio > 1.2 then
      table.insert(results, {
        severity = SEVERITY.CRITICAL,
        category = "Survivability",
        message = string.format("Taking more damage than healing (%.1fx). Risk of death! Check HealBot thresholds.", damageRatio)
      })
    elseif damageRatio > 0.9 then
      table.insert(results, {
        severity = SEVERITY.WARNING,
        category = "Survivability",
        message = "Damage nearly equals healing. Consider lowering HP trigger in HealBot."
      })
    elseif damageRatio < 0.3 then
      table.insert(results, {
        severity = SEVERITY.TIP,
        category = "Survivability",
        message = "Very safe hunting (low damage ratio). You could handle stronger monsters or larger pulls."
      })
    end
  end
  
  -- Damage per minute analysis
  local dmgPerMin = m.damageTaken / math.max(1, elapsedMin)
  if dmgPerMin > 500 then
    table.insert(results, {
      severity = SEVERITY.WARNING,
      category = "Survivability",
      message = string.format("High damage intake (%.0f/min). Consider better equipment or smaller pulls.", dmgPerMin)
    })
  end
  
  -- ==================== RESOURCE EFFICIENCY ====================
  
  local potionsPerHour = m.potionsUsed / math.max(0.1, elapsedHour)
  local potionsPerKill = m.kills > 0 and (m.potionsUsed / m.kills) or 0
  
  -- Potion efficiency
  if m.potionsUsed > 10 then
    if potionsPerKill > 2 then
      table.insert(results, {
        severity = SEVERITY.WARNING,
        category = "Resources",
        message = string.format("High potion usage (%.1f per kill). Consider: mana shield, better healing spells, or weaker monsters.", potionsPerKill)
      })
    elseif potionsPerKill < 0.3 and m.kills > 20 then
      table.insert(results, {
        severity = SEVERITY.INFO,
        category = "Resources",
        message = "Excellent potion efficiency! Your sustain is very good."
      })
    end
  end
  
  -- Rune efficiency for mages
  if m.runesUsed > 10 then
    local runesPerKill = m.runesUsed / math.max(1, m.kills)
    if runesPerKill > 1.5 then
      table.insert(results, {
        severity = SEVERITY.TIP,
        category = "Resources",
        message = string.format("Using %.1f runes per kill. Consider AOE runes for multi-target or spell attacks.", runesPerKill)
      })
    end
  end
  
  -- ==================== COMBAT ANALYSIS ====================
  
  local spellsPerKill = m.kills > 0 and (m.spellsCast / m.kills) or 0
  
  -- Spell usage patterns
  if m.spellsCast > 0 and m.kills > 10 then
    if spellsPerKill < 1 then
      table.insert(results, {
        severity = SEVERITY.TIP,
        category = "Combat",
        message = "Low spell usage. Consider adding attack spells to AttackBot for faster kills."
      })
    elseif spellsPerKill > 10 then
      table.insert(results, {
        severity = SEVERITY.TIP,
        category = "Combat",
        message = string.format("High spell usage (%.1f/kill). Check for spell spam or consider stronger single spells.", spellsPerKill)
      })
    end
  end
  
  -- ==================== MOVEMENT ANALYSIS ====================
  
  local tilesPerKill = m.kills > 0 and (m.tilesWalked / m.kills) or 0
  
  -- Walking efficiency
  if m.tilesWalked > 100 and m.kills > 10 then
    if tilesPerKill > 50 then
      table.insert(results, {
        severity = SEVERITY.TIP,
        category = "Movement",
        message = string.format("Walking %.0f tiles per kill. Spawn may be sparse - consider denser hunting ground.", tilesPerKill)
      })
    elseif tilesPerKill < 5 then
      table.insert(results, {
        severity = SEVERITY.INFO,
        category = "Movement",
        message = "Excellent spawn density! Minimal walking between kills."
      })
    end
  end
  
  -- ==================== MONSTER ANALYSIS ====================
  
  if hasData(analytics.monsters) then
    local monsterCount = 0
    local topMonster = nil
    local topCount = 0
    
    for name, count in pairs(analytics.monsters) do
      monsterCount = monsterCount + 1
      if count > topCount then
        topCount = count
        topMonster = name
      end
    end
    
    -- Diversity analysis
    if monsterCount == 1 and m.kills > 50 then
      table.insert(results, {
        severity = SEVERITY.INFO,
        category = "Hunting",
        message = string.format("Single target focus on %s. Good for specific loot/bestiary.", topMonster)
      })
    elseif monsterCount > 5 then
      local topPercent = (topCount / m.kills) * 100
      if topPercent < 30 then
        table.insert(results, {
          severity = SEVERITY.TIP,
          category = "Hunting",
          message = string.format("Diverse monster kills (%d types). Consider focusing TargetBot priority on best XP monsters.", monsterCount)
        })
      end
    end
  end
  
  -- ==================== GENERAL RECOMMENDATIONS ====================
  
  -- Session length check
  if elapsedHour > 2 then
    table.insert(results, {
      severity = SEVERITY.INFO,
      category = "Session",
      message = string.format("Long session (%.1fh). Remember to check supplies and take breaks!", elapsedHour)
    })
  end
  
  -- No kills warning
  if m.kills == 0 and elapsedMin > 5 then
    table.insert(results, {
      severity = SEVERITY.WARNING,
      category = "Hunting",
      message = "No kills recorded. Check if TargetBot is enabled and configured."
    })
  end
  
  -- No spells warning
  if m.spellsCast == 0 and elapsedMin > 5 then
    table.insert(results, {
      severity = SEVERITY.TIP,
      category = "Combat",
      message = "No spells detected. Consider adding attack spells to HealBot/AttackBot."
    })
  end
  
  -- ==================== HEALBOT DEEP ANALYSIS ====================
  
  local healData = nil
  if HealBot and HealBot.getAnalytics then
    healData = HealBot.getAnalytics()
  end
  
  if healData then
    -- Mana waste analysis
    if healData.manaWaste and healData.manaWaste > 1000 then
      local wastePercent = 0
      if healData.spellCasts and healData.spellCasts > 0 then
        -- Rough estimate: assume avg 50 mana per spell
        local estimatedManaUsed = healData.spellCasts * 50
        wastePercent = (healData.manaWaste / math.max(1, estimatedManaUsed)) * 100
      end
      if wastePercent > 20 then
        table.insert(results, {
          severity = SEVERITY.WARNING,
          category = "HealBot",
          message = string.format("High mana waste (%.0f%%). Lower HP trigger threshold to avoid overhealing.", wastePercent)
        })
      end
    end
    
    -- Potion waste analysis
    if healData.potionWaste and healData.potionUses and healData.potionUses > 10 then
      local wastePercent = (healData.potionWaste / healData.potionUses) * 100
      if wastePercent > 15 then
        table.insert(results, {
          severity = SEVERITY.TIP,
          category = "HealBot",
          message = string.format("%.0f%% of potions wasted (used when healthy). Lower HP trigger threshold.", wastePercent)
        })
      end
    end
    
    -- Healing spell diversity
    if hasData(healData.spells) then
      local spellCount = 0
      for _ in pairs(healData.spells) do spellCount = spellCount + 1 end
      
      if spellCount == 1 and healData.spellCasts and healData.spellCasts > 50 then
        table.insert(results, {
          severity = SEVERITY.TIP,
          category = "HealBot",
          message = "Using only 1 healing spell. Consider adding weaker spell for minor damage (mana efficient)."
        })
      end
    end
  end
  
  -- ==================== ATTACKBOT DEEP ANALYSIS ====================
  
  local attackData = nil
  if AttackBot and AttackBot.getAnalytics then
    attackData = AttackBot.getAnalytics()
  end
  
  -- Get damage data from analyzer
  local totalDmgDealt = 0
  if getHuntingData then
    totalDmgDealt = select(1, getHuntingData()) or 0
  end
  
  if attackData and m.kills > 10 then
    -- Attack spell usage analysis
    local totalAttacks = attackData.totalAttacks or 0
    local attacksPerKill = totalAttacks / m.kills
    
    if attacksPerKill > 5 then
      table.insert(results, {
        severity = SEVERITY.TIP,
        category = "AttackBot",
        message = string.format("High attacks/kill (%.1f). Consider stronger spells or single-target focus.", attacksPerKill)
      })
    elseif attacksPerKill < 0.5 and totalAttacks > 0 then
      table.insert(results, {
        severity = SEVERITY.INFO,
        category = "AttackBot",
        message = "Efficient attack usage! Good spell power for this spawn."
      })
    end
    
    -- Rune vs Spell preference
    local spellUses = 0
    local runeUses = 0
    if hasData(attackData.spells) then
      for _, count in pairs(attackData.spells) do
        spellUses = spellUses + count
      end
    end
    if hasData(attackData.runes) then
      for _, count in pairs(attackData.runes) do
        runeUses = runeUses + count
      end
    end
    
    if spellUses > 0 and runeUses > 0 then
      local spellRatio = spellUses / (spellUses + runeUses)
      if spellRatio < 0.2 then
        table.insert(results, {
          severity = SEVERITY.TIP,
          category = "AttackBot",
          message = "Mostly using runes. Attack spells are often cheaper long-term if mana is available."
        })
      elseif spellRatio > 0.9 and runeUses > 10 then
        table.insert(results, {
          severity = SEVERITY.INFO,
          category = "AttackBot",
          message = "Good spell-based attack rotation. Mana efficient!"
        })
      end
    end
    
    -- Empowerment usage
    if attackData.empowerments and attackData.empowerments > 0 then
      local empPerHour = attackData.empowerments / math.max(0.1, elapsedHour)
      if empPerHour < 10 and totalAttacks > 100 then
        table.insert(results, {
          severity = SEVERITY.TIP,
          category = "AttackBot",
          message = "Low empowerment usage. Keep utito/utamo active for faster kills."
        })
      end
    elseif totalAttacks > 50 and attackData.empowerments == 0 then
      table.insert(results, {
        severity = SEVERITY.TIP,
        category = "AttackBot",
        message = "No empowerment buffs detected. Consider adding utito tempo or utamo vita for faster/safer hunts."
      })
    end
    
    -- ===== DAMAGE EFFICIENCY ANALYSIS =====
    if totalDmgDealt > 0 and totalAttacks > 0 then
      local avgDmgPerAttack = totalDmgDealt / totalAttacks
      
      -- Compare damage per attack to expected values
      if avgDmgPerAttack < 50 then
        table.insert(results, {
          severity = SEVERITY.WARNING,
          category = "AttackBot",
          message = string.format("Low avg damage/attack (%.0f). Consider stronger spells or higher magic level.", avgDmgPerAttack)
        })
      elseif avgDmgPerAttack > 300 then
        table.insert(results, {
          severity = SEVERITY.INFO,
          category = "AttackBot",
          message = string.format("Excellent damage output (%.0f avg/attack)! Great spell power.", avgDmgPerAttack)
        })
      end
      
      -- Damage per kill analysis
      local dmgPerKill = totalDmgDealt / m.kills
      local attacksNeeded = dmgPerKill / math.max(1, avgDmgPerAttack)
      
      if attacksNeeded > 8 then
        table.insert(results, {
          severity = SEVERITY.TIP,
          category = "AttackBot",
          message = string.format("Taking ~%.0f attacks per kill. Consider AOE attacks for multi-target or stronger single-target spells.", attacksNeeded)
        })
      elseif attacksNeeded < 2 and m.kills > 20 then
        table.insert(results, {
          severity = SEVERITY.INFO,
          category = "AttackBot",
          message = "One-shotting most monsters. Efficient damage setup!"
        })
      end
    end
    
    -- ===== ATTACK DIVERSITY ANALYSIS =====
    local totalSpellTypes = 0
    local totalRuneTypes = 0
    if hasData(attackData.spells) then
      for _ in pairs(attackData.spells) do totalSpellTypes = totalSpellTypes + 1 end
    end
    if hasData(attackData.runes) then
      for _ in pairs(attackData.runes) do totalRuneTypes = totalRuneTypes + 1 end
    end
    
    if totalSpellTypes == 1 and spellUses > 100 then
      table.insert(results, {
        severity = SEVERITY.TIP,
        category = "AttackBot",
        message = "Using only 1 attack spell. Consider adding AOE for groups or single-target for bosses."
      })
    end
    
    -- ===== RUNE EFFICIENCY (cost analysis) =====
    if runeUses > 50 then
      -- Check if using expensive runes
      local usingExpensiveRunes = false
      for runeId, count in pairs(attackData.runes or {}) do
        -- Sudden Death (3155), Thunderstorm (3202), Avalanche (3161), Great Fireball (3191)
        if runeId == 3155 and count > 20 then
          usingExpensiveRunes = true
          local sdPerKill = count / math.max(1, m.kills)
          if sdPerKill > 1.5 then
            table.insert(results, {
              severity = SEVERITY.WARNING,
              category = "AttackBot",
              message = string.format("Using %.1f Sudden Death runes per kill. SDs are expensive - consider AOE runes or attack spells for regular monsters.", sdPerKill)
            })
          end
        end
      end
    end
  end
  
  -- Check if AttackBot is not being used at all
  if not attackData or (attackData.totalAttacks or 0) == 0 then
    if m.kills > 20 and elapsedMin > 10 then
      table.insert(results, {
        severity = SEVERITY.TIP,
        category = "AttackBot",
        message = "No AttackBot activity detected. Enable attack spells/runes for faster kills."
      })
    end
  end
  
  return results
end

-- Format insights for display
function Insights.format(insightsList)
  local lines = {}
  
  if #insightsList == 0 then
    table.insert(lines, "  No insights available yet.")
    return lines
  end
  
  -- Group by severity
  local critical = {}
  local warnings = {}
  local tips = {}
  local info = {}
  
  for _, insight in ipairs(insightsList) do
    if insight.severity == SEVERITY.CRITICAL then
      table.insert(critical, insight)
    elseif insight.severity == SEVERITY.WARNING then
      table.insert(warnings, insight)
    elseif insight.severity == SEVERITY.TIP then
      table.insert(tips, insight)
    else
      table.insert(info, insight)
    end
  end
  
  -- Display critical first
  for _, i in ipairs(critical) do
    table.insert(lines, string.format("  [!] %s", i.message))
  end
  for _, i in ipairs(warnings) do
    table.insert(lines, string.format("  [*] %s", i.message))
  end
  for _, i in ipairs(tips) do
    table.insert(lines, string.format("  [>] %s", i.message))
  end
  for _, i in ipairs(info) do
    table.insert(lines, string.format("  [i] %s", i.message))
  end
  
  return lines
end

-- Calculate efficiency score (0-100) using weighted multi-factor analysis
function Insights.calculateScore()
  local elapsed = getElapsed()
  if elapsed < 300000 then return 0 end
  
  local m = analytics.metrics
  local score = 0
  local maxScore = 100
  
  local elapsedHour = elapsed / 3600000
  local xpGained = (exp() or 0) - (analytics.session.startXp or 0)
  
  -- ===== EFFICIENCY FACTORS (40 points max) =====
  
  -- XP/hour efficiency (max 20 points)
  local xpPerHour = xpGained / math.max(0.1, elapsedHour)
  if xpPerHour > 1000000 then score = score + 20
  elseif xpPerHour > 500000 then score = score + 17
  elseif xpPerHour > 200000 then score = score + 14
  elseif xpPerHour > 100000 then score = score + 10
  elseif xpPerHour > 50000 then score = score + 6
  elseif xpPerHour > 20000 then score = score + 3
  end
  
  -- Kill rate efficiency (max 15 points)
  local killsPerHour = m.kills / math.max(0.1, elapsedHour)
  if killsPerHour > 300 then score = score + 15
  elseif killsPerHour > 200 then score = score + 12
  elseif killsPerHour > 100 then score = score + 9
  elseif killsPerHour > 50 then score = score + 5
  elseif killsPerHour > 20 then score = score + 2
  end
  
  -- Movement efficiency (max 5 points)
  if m.kills > 10 and m.tilesWalked > 0 then
    local tilesPerKill = m.tilesWalked / m.kills
    if tilesPerKill < 10 then score = score + 5
    elseif tilesPerKill < 20 then score = score + 3
    elseif tilesPerKill < 40 then score = score + 1
    end
  end
  
  -- ===== SURVIVABILITY FACTORS (30 points max) =====
  
  -- Damage/Healing ratio (max 15 points)
  if m.healingDone > 0 then
    local damageRatio = m.damageTaken / m.healingDone
    if damageRatio < 0.4 then score = score + 15
    elseif damageRatio < 0.6 then score = score + 12
    elseif damageRatio < 0.8 then score = score + 8
    elseif damageRatio < 1.0 then score = score + 4
    elseif damageRatio > 1.2 then score = score - 5
    end
  else
    score = score + 10 -- No damage taken is good
  end
  
  -- Death penalty (max -20 points)
  if m.deathCount > 0 then
    score = score - (m.deathCount * 10)
  else
    score = score + 10 -- No deaths bonus
  end
  
  -- Near-death events penalty (max -5 points)
  local nearDeathRate = m.nearDeathCount / math.max(1, elapsedHour)
  if nearDeathRate > 5 then score = score - 5
  elseif nearDeathRate > 2 then score = score - 2
  elseif nearDeathRate == 0 then score = score + 5
  end
  
  -- ===== RESOURCE EFFICIENCY (20 points max) =====
  
  -- Get HealBot data for waste analysis
  local healData = getHealBotData()
  
  -- Potion efficiency (max 10 points)
  if m.kills > 10 then
    local potionsPerKill = 0
    if healData and healData.potionUses then
      potionsPerKill = healData.potionUses / m.kills
    else
      potionsPerKill = m.potionsUsed / m.kills
    end
    
    if potionsPerKill < 0.3 then score = score + 10
    elseif potionsPerKill < 0.7 then score = score + 7
    elseif potionsPerKill < 1.5 then score = score + 4
    elseif potionsPerKill > 3 then score = score - 3
    end
  end
  
  -- Mana waste penalty (max 5 points)
  if healData and healData.manaWaste and healData.spellCasts and healData.spellCasts > 10 then
    local avgManaCost = 50 -- Assume avg 50 mana per spell
    local estimatedMana = healData.spellCasts * avgManaCost
    local wastePercent = healData.manaWaste / math.max(1, estimatedMana) * 100
    if wastePercent < 5 then score = score + 5
    elseif wastePercent < 15 then score = score + 3
    elseif wastePercent > 30 then score = score - 2
    end
  else
    score = score + 3 -- Neutral if no data
  end
  
  -- Potion waste penalty (max 5 points)
  if healData and healData.potionWaste and healData.potionUses and healData.potionUses > 10 then
    local wastePercent = (healData.potionWaste / healData.potionUses) * 100
    if wastePercent < 5 then score = score + 5
    elseif wastePercent < 15 then score = score + 2
    elseif wastePercent > 25 then score = score - 2
    end
  else
    score = score + 3 -- Neutral if no data
  end
  
  -- ===== ECONOMIC FACTORS (10 points max) =====
  
  if bottingStats then
    local loot, waste, balance = bottingStats()
    local profitPerHour = balance / math.max(0.1, elapsedHour)
    
    if profitPerHour > 100000 then score = score + 10
    elseif profitPerHour > 50000 then score = score + 7
    elseif profitPerHour > 20000 then score = score + 4
    elseif profitPerHour > 0 then score = score + 2
    elseif profitPerHour < -20000 then score = score - 3
    end
  end
  
  return math.max(0, math.min(100, score))
end

-- Generate score bar visualization
function Insights.scoreBar(score)
  local filled = math.floor(score / 10)
  local empty = 10 - filled
  local bar = string.rep("#", filled) .. string.rep("-", empty)
  
  local rating = "Poor"
  if score >= 80 then rating = "Excellent"
  elseif score >= 60 then rating = "Good"
  elseif score >= 40 then rating = "Average"
  elseif score >= 20 then rating = "Below Avg"
  end
  
  return string.format("[%s] %d/100 (%s)", bar, score, rating)
end

-- ============================================================================
-- ANALYTICS SUMMARY BUILDER
-- ============================================================================

-- Helper to get item name by ID
local function getItemName(itemId)
  local item = Item.create(itemId)
  if item then return item:getName() end
  return "Item #" .. tostring(itemId)
end

local function buildSummary()
  local lines = {}
  local elapsed = getElapsed()
  local m = analytics.metrics
  local currentXp = exp() or 0
  local xpGained = currentXp - (analytics.session.startXp or 0)
  local xpPerHour = perHour(xpGained, elapsed)
  
  -- Get bot analytics
  local healData = getHealBotData()
  local attackData = getAttackBotData()
  
  -- Header
  table.insert(lines, "============================================")
  table.insert(lines, "        SMARTHUNT ANALYTICS v3.0")
  table.insert(lines, "============================================")
  table.insert(lines, "")
  
  -- Session Info
  table.insert(lines, "[SESSION]")
  table.insert(lines, "--------------------------------------------")
  table.insert(lines, "  Duration: " .. formatDuration(elapsed))
  table.insert(lines, "  Status: " .. (isSessionActive() and "ACTIVE" or "STOPPED"))
  table.insert(lines, "")
  
  -- Experience
  table.insert(lines, "[EXPERIENCE]")
  table.insert(lines, "--------------------------------------------")
  table.insert(lines, "  XP Gained: " .. formatNum(xpGained))
  table.insert(lines, "  XP/Hour: " .. formatNum(math.floor(xpPerHour)))
  table.insert(lines, "")
  
  -- Skills
  local currentSkills = captureSkills()
  local skillGains = calculateSkillGains(analytics.session.startSkills, currentSkills)
  if hasData(skillGains) then
    table.insert(lines, "[SKILL GAINS]")
    table.insert(lines, "--------------------------------------------")
    for id, data in pairs(skillGains) do
      local name = SKILL_NAMES[id] or ("Skill " .. id)
      table.insert(lines, string.format("  %s: %d -> %d (+%d)", name, data.start, data.current, data.gain))
    end
    table.insert(lines, "")
  end
  
  -- Combat Stats
  table.insert(lines, "[COMBAT]")
  table.insert(lines, "--------------------------------------------")
  table.insert(lines, "  Total Kills: " .. formatNum(m.kills))
  table.insert(lines, "  Kills/Hour: " .. formatNum(math.floor(perHour(m.kills, elapsed))))
  table.insert(lines, "  Damage Taken: " .. formatNum(m.damageTaken))
  table.insert(lines, "  Healing Done: " .. formatNum(m.healingDone))
  table.insert(lines, "")
  
  -- Movement
  table.insert(lines, "[MOVEMENT]")
  table.insert(lines, "--------------------------------------------")
  table.insert(lines, "  Tiles Walked: " .. formatNum(m.tilesWalked))
  table.insert(lines, "  Tiles/Min: " .. string.format("%.1f", m.tilesWalked / math.max(1, elapsed / 60000)))
  table.insert(lines, "")
  
  -- ==================== HEALBOT ANALYTICS ====================
  if healData then
    table.insert(lines, "[HEALBOT - HEALING SPELLS]")
    table.insert(lines, "--------------------------------------------")
    if hasData(healData.spells) then
      local sortedSpells = {}
      for spell, count in pairs(healData.spells) do
        table.insert(sortedSpells, {name = spell, count = count})
      end
      table.sort(sortedSpells, function(a, b) return a.count > b.count end)
      for _, s in ipairs(sortedSpells) do
        table.insert(lines, string.format("  %dx %s", s.count, s.name))
      end
    else
      table.insert(lines, "  No healing spells used")
    end
    table.insert(lines, "  Total: " .. formatNum(healData.spellCasts or 0) .. " casts")
    if healData.manaWaste and healData.manaWaste > 0 then
      table.insert(lines, "  Mana Wasted: " .. formatNum(healData.manaWaste))
    end
    table.insert(lines, "")
    
    table.insert(lines, "[HEALBOT - POTIONS]")
    table.insert(lines, "--------------------------------------------")
    if hasData(healData.potions) then
      local sortedPotions = {}
      for itemId, count in pairs(healData.potions) do
        table.insert(sortedPotions, {id = itemId, name = getItemName(itemId), count = count})
      end
      table.sort(sortedPotions, function(a, b) return a.count > b.count end)
      for _, p in ipairs(sortedPotions) do
        table.insert(lines, string.format("  %dx %s", p.count, p.name))
      end
    else
      table.insert(lines, "  No potions used")
    end
    table.insert(lines, "  Total: " .. formatNum(healData.potionUses or 0) .. " used")
    if healData.potionWaste and healData.potionWaste > 0 then
      table.insert(lines, "  Wasted (used when already healthy): " .. formatNum(healData.potionWaste))
    end
    table.insert(lines, "")
  end
  
  -- ==================== ATTACKBOT ANALYTICS ====================
  if attackData then
    table.insert(lines, "[ATTACKBOT - ATTACK SPELLS]")
    table.insert(lines, "--------------------------------------------")
    if hasData(attackData.spells) then
      local sortedSpells = {}
      for spell, count in pairs(attackData.spells) do
        table.insert(sortedSpells, {name = spell, count = count})
      end
      table.sort(sortedSpells, function(a, b) return a.count > b.count end)
      for _, s in ipairs(sortedSpells) do
        table.insert(lines, string.format("  %dx %s", s.count, s.name))
      end
    else
      table.insert(lines, "  No attack spells used")
    end
    if attackData.empowerments and attackData.empowerments > 0 then
      table.insert(lines, "  Empowerment Buffs: " .. formatNum(attackData.empowerments))
    end
    table.insert(lines, "")
    
    table.insert(lines, "[ATTACKBOT - RUNES]")
    table.insert(lines, "--------------------------------------------")
    if hasData(attackData.runes) then
      local sortedRunes = {}
      for runeId, count in pairs(attackData.runes) do
        table.insert(sortedRunes, {id = runeId, name = getItemName(runeId), count = count})
      end
      table.sort(sortedRunes, function(a, b) return a.count > b.count end)
      for _, r in ipairs(sortedRunes) do
        table.insert(lines, string.format("  %dx %s", r.count, r.name))
      end
    else
      table.insert(lines, "  No attack runes used")
    end
    table.insert(lines, "  Total Attacks: " .. formatNum(attackData.totalAttacks or 0))
    table.insert(lines, "")
  end
  
  -- ==================== DAMAGE OUTPUT (from Analyzer) ====================
  if getHuntingData then
    local totalDmg, totalHeal, _, _, _ = getHuntingData()
    local elapsedHour = elapsed / 3600000
    
    table.insert(lines, "[DAMAGE OUTPUT]")
    table.insert(lines, "--------------------------------------------")
    table.insert(lines, "  Total Damage Dealt: " .. formatNum(totalDmg or 0))
    table.insert(lines, "  Damage/Hour: " .. formatNum(math.floor((totalDmg or 0) / math.max(0.1, elapsedHour))))
    
    -- Damage per kill
    if m.kills > 0 then
      local dmgPerKill = (totalDmg or 0) / m.kills
      table.insert(lines, "  Avg Damage/Kill: " .. formatNum(math.floor(dmgPerKill)))
    end
    
    -- Damage per attack (if AttackBot data available)
    if attackData and attackData.totalAttacks and attackData.totalAttacks > 0 then
      local dmgPerAttack = (totalDmg or 0) / attackData.totalAttacks
      table.insert(lines, "  Avg Damage/Attack: " .. formatNum(math.floor(dmgPerAttack)))
    end
    
    table.insert(lines, "")
  end
  
  -- Monster Breakdown
  if hasData(analytics.monsters) then
    table.insert(lines, "[MONSTER KILLS]")
    table.insert(lines, "--------------------------------------------")
    local sorted = {}
    for name, count in pairs(analytics.monsters) do
      table.insert(sorted, {name = name, count = count})
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    for i = 1, math.min(10, #sorted) do
      local mon = sorted[i]
      table.insert(lines, string.format("  %dx %s", mon.count, mon.name))
    end
    table.insert(lines, "")
  end
  
  -- ==================== ECONOMY (from Analyzer) ====================
  if bottingStats then
    local loot, waste, balance = bottingStats()
    local elapsedHour = elapsed / 3600000
    
    table.insert(lines, "[ECONOMY]")
    table.insert(lines, "--------------------------------------------")
    table.insert(lines, "  Loot Value: " .. formatNum(loot) .. " gp")
    table.insert(lines, "  Waste Value: " .. formatNum(waste) .. " gp")
    
    local balanceColor = balance >= 0 and "+" or ""
    table.insert(lines, "  Balance: " .. balanceColor .. formatNum(balance) .. " gp")
    
    local profitPerHour = balance / math.max(0.1, elapsedHour)
    table.insert(lines, "  Profit/Hour: " .. formatNum(math.floor(profitPerHour)) .. " gp/h")
    table.insert(lines, "")
  end
  
  -- ==================== SURVIVABILITY ====================
  table.insert(lines, "[SURVIVABILITY]")
  table.insert(lines, "--------------------------------------------")
  table.insert(lines, "  Deaths: " .. formatNum(m.deathCount))
  table.insert(lines, "  Near-Death Events: " .. formatNum(m.nearDeathCount))
  table.insert(lines, "  Lowest HP: " .. analytics.peakStats.lowestHpPercent .. "%")
  table.insert(lines, "  Highest Hit Taken: " .. formatNum(analytics.peakStats.highestDamageHit))
  
  -- Damage ratio
  if m.healingDone > 0 then
    local ratio = m.damageTaken / m.healingDone
    local ratioStatus = "Safe"
    if ratio > 1.2 then ratioStatus = "DANGEROUS"
    elseif ratio > 0.9 then ratioStatus = "Risky"
    elseif ratio < 0.5 then ratioStatus = "Very Safe"
    end
    table.insert(lines, "  Damage Ratio: " .. string.format("%.2f", ratio) .. " (" .. ratioStatus .. ")")
  end
  table.insert(lines, "")
  
  -- ==================== PEAK PERFORMANCE ====================
  -- Update peak stats before display
  updatePeakStats()
  
  table.insert(lines, "[PEAK PERFORMANCE]")
  table.insert(lines, "--------------------------------------------")
  table.insert(lines, "  Best XP/Hour: " .. formatNum(math.floor(analytics.peakStats.maxXpPerHour)))
  table.insert(lines, "  Best Kills/Hour: " .. formatNum(math.floor(analytics.peakStats.maxKillsPerHour)))
  
  -- Current vs Peak comparison
  local currentXpH = perHour(xpGained, elapsed)
  local currentKillsH = perHour(m.kills, elapsed)
  if analytics.peakStats.maxXpPerHour > 0 then
    local xpEfficiency = (currentXpH / analytics.peakStats.maxXpPerHour) * 100
    table.insert(lines, "  Current vs Peak XP: " .. string.format("%.0f%%", xpEfficiency))
  end
  table.insert(lines, "")
  
  -- ==================== RESOURCE TRACKING ====================
  local currentCap = getFreeCap()
  local currentStamina = getStaminaMinutes()
  local capUsed = analytics.session.startCap - currentCap
  local staminaUsed = analytics.session.startStamina - currentStamina
  
  table.insert(lines, "[RESOURCES]")
  table.insert(lines, "--------------------------------------------")
  table.insert(lines, "  Capacity Used: " .. formatNum(capUsed) .. " oz")
  table.insert(lines, "  Current Cap: " .. formatNum(currentCap) .. " oz")
  if staminaUsed > 0 then
    table.insert(lines, "  Stamina Used: " .. staminaUsed .. " minutes")
  end
  table.insert(lines, "  Current Stamina: " .. currentStamina .. " minutes")
  table.insert(lines, "")
  
  -- ==================== EFFICIENCY SCORE ====================
  local score = Insights.calculateScore()
  table.insert(lines, "[HUNT EFFICIENCY SCORE]")
  table.insert(lines, "--------------------------------------------")
  table.insert(lines, "  " .. Insights.scoreBar(score))
  table.insert(lines, "")
  table.insert(lines, "  Score Factors:")
  table.insert(lines, "    Efficiency (XP+Kills+Movement): 40 pts max")
  table.insert(lines, "    Survivability (Deaths+Damage): 30 pts max")
  table.insert(lines, "    Resources (Potions+Mana): 20 pts max")
  table.insert(lines, "    Economy (Profit): 10 pts max")
  table.insert(lines, "")
  
  -- ==================== AI INSIGHTS ====================
  local insightsList = Insights.analyze()
  table.insert(lines, "[AI INSIGHTS & RECOMMENDATIONS]")
  table.insert(lines, "--------------------------------------------")
  local insightLines = Insights.format(insightsList)
  for _, line in ipairs(insightLines) do
    table.insert(lines, line)
  end
  table.insert(lines, "")
  table.insert(lines, "  Legend: [!]=Critical [*]=Warning [>]=Tip [i]=Info")
  
  table.insert(lines, "")
  table.insert(lines, "============================================")
  
  return table.concat(lines, "\n")
end

-- ============================================================================
-- UI WINDOW
-- ============================================================================

local analyticsWindow = nil

local function showAnalytics()
  if analyticsWindow then
    analyticsWindow:destroy()
    analyticsWindow = nil
  end
  
  analyticsWindow = UI.createWindow('SmartHuntAnalyticsWindow')
  if not analyticsWindow then
    print(buildSummary())
    info("[Analytics] Printed to console")
    return
  end
  
  analyticsWindow.content.textContent:setText(buildSummary())
  
  analyticsWindow.buttons.refreshButton.onClick = function()
    analyticsWindow.content.textContent:setText(buildSummary())
  end
  
  analyticsWindow.buttons.closeButton.onClick = function()
    analyticsWindow:destroy()
    analyticsWindow = nil
  end
  
  analyticsWindow.buttons.resetButton.onClick = function()
    startSession()
    analyticsWindow.content.textContent:setText(buildSummary())
    info("[Analytics] Session reset!")
  end
  
  analyticsWindow:show()
  analyticsWindow:raise()
  analyticsWindow:focus()
end

-- ============================================================================
-- AUTO-START SESSION WITH CAVEBOT
-- ============================================================================

UI.Separator()

macro(5000, "SmartHunt Tracker", function()
  if CaveBot and CaveBot.isOn() then
    if not isSessionActive() then
      startSession()
      info("[Analytics] Session started automatically")
    end
  end
end)

-- ============================================================================
-- UI BUTTON
-- ============================================================================

local analyticsBtn = UI.Button("SmartHunt Analytics", function()
  local status, err = pcall(showAnalytics)
  if not status then
    warn("[Analytics] Error: " .. tostring(err))
    print(buildSummary())
  end
end)

if analyticsBtn then
  analyticsBtn:setTooltip("View hunting analytics:\n- Session duration and XP\n- Skill gains\n- Kill statistics\n- Supply consumption\n- Movement data")
end

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

print("[SmartHunt] Analytics v2.0 loaded (EventBus-driven)")
