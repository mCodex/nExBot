--[[
  Monster Spell Tracker Module v3.0
  
  Single Responsibility: Comprehensive spell/missile tracking for
  monster attack analysis — projectile types, cast frequency,
  target patterns, cooldowns, reactivity.
  
  Depends on: monster_ai_core.lua, monster_tracking.lua
  Populates: MonsterAI.SpellTracker
]]

-- BoundedPush/TrimArray are set as globals by utils/ring_buffer.lua (Phase 3)
local BoundedPush = BoundedPush
local TrimArray = TrimArray

local H = MonsterAI._helpers
local nowMs            = H.nowMs
local isCreatureValid  = H.isCreatureValid
local safeCreatureCall = H.safeCreatureCall
local safeGetId        = H.safeGetId

local CONST = MonsterAI.CONSTANTS

-- ============================================================================
-- SPELL TRACKER STATE
-- ============================================================================

MonsterAI.SpellTracker = MonsterAI.SpellTracker or {
  stats = {
    totalSpellsCast  = 0,
    totalMissiles    = 0,
    uniqueMissileTypes = 0,
    spellsPerMinute  = 0,
    lastMinuteSpells = 0,
    sessionStartTime = nowMs()
  },
  monsterSpells  = {},
  spellCatalog   = {},
  recentSpells   = {},
  MAX_RECENT_SPELLS = 100,
  typeSpellStats = {}
}

-- ============================================================================
-- PER-MONSTER INIT
-- ============================================================================

function MonsterAI.SpellTracker.initMonster(creature)
  if not creature or not isCreatureValid(creature) then return nil end
  local id = safeGetId(creature)
  if not id then return nil end
  if MonsterAI.SpellTracker.monsterSpells[id] then
    return MonsterAI.SpellTracker.monsterSpells[id]
  end

  local data = {
    id   = id,
    name = safeCreatureCall(creature, "getName", "Unknown"),
    totalSpellsCast       = 0,
    missilesByType        = {},
    spellHistory          = {},
    ewmaSpellCooldown     = nil,
    ewmaSpellVariance     = 0,
    lastSpellTime         = 0,
    spellCooldownSamples  = {},
    spellSequence         = {},
    detectedPatterns      = {},
    spellsAtPlayer        = 0,
    spellsAtOthers        = 0,
    avgSpellRange         = 0,
    castFrequency         = 0,
    frequencyWindow       = {},
    firstSpellTime        = nil,
    lastObservedMissileType = nil
  }
  MonsterAI.SpellTracker.monsterSpells[id] = data
  return data
end

-- ============================================================================
-- RECORD SPELL
-- ============================================================================

function MonsterAI.SpellTracker.recordSpell(creatureId, missileType, sourcePos, targetPos)
  local nowt = nowMs()
  local data = MonsterAI.SpellTracker.monsterSpells[creatureId]

  if not data then
    local trackerData = MonsterAI.Tracker and MonsterAI.Tracker.monsters[creatureId]
    if trackerData and trackerData.creature then
      data = MonsterAI.SpellTracker.initMonster(trackerData.creature)
    end
  end
  if not data then return end

  -- Counts
  data.totalSpellsCast = (data.totalSpellsCast or 0) + 1
  data.missilesByType[missileType] = (data.missilesByType[missileType] or 0) + 1
  if not data.firstSpellTime then data.firstSpellTime = nowt end

  -- EWMA cooldown tracking
  if data.lastSpellTime > 0 then
    local interval = nowt - data.lastSpellTime
    if interval > 200 then -- ignore multi-projectile
      BoundedPush(data.spellCooldownSamples, interval, 30)
      local alpha = CONST.EWMA.ALPHA_DEFAULT
      if data.ewmaSpellCooldown then
        local diff = interval - data.ewmaSpellCooldown
        data.ewmaSpellCooldown = data.ewmaSpellCooldown * (1 - alpha) + interval * alpha
        data.ewmaSpellVariance = data.ewmaSpellVariance * (1 - alpha) + (diff * diff) * alpha
      else
        data.ewmaSpellCooldown = interval
        data.ewmaSpellVariance = 0
      end
    end
  end
  data.lastSpellTime = nowt
  data.lastObservedMissileType = missileType

  -- History & sequence
  BoundedPush(data.spellHistory, {
    time = nowt, missileType = missileType,
    sourcePos = sourcePos, targetPos = targetPos
  }, 50)
  BoundedPush(data.spellSequence, missileType, 10)

  -- Target analysis
  local playerPos = player and player:getPosition()
  if playerPos and targetPos then
    local distToPlayer = math.max(
      math.abs(targetPos.x - playerPos.x),
      math.abs(targetPos.y - playerPos.y))
    if distToPlayer <= 1 then
      data.spellsAtPlayer = (data.spellsAtPlayer or 0) + 1
    else
      data.spellsAtOthers = (data.spellsAtOthers or 0) + 1
    end
    if sourcePos then
      local range = math.max(
        math.abs(targetPos.x - sourcePos.x),
        math.abs(targetPos.y - sourcePos.y))
      data.avgSpellRange = (data.avgSpellRange or 0) * 0.8 + range * 0.2
    end
  end

  -- Frequency (rolling 60 s window)
  data.frequencyWindow = data.frequencyWindow or {}
  data.frequencyWindow[#data.frequencyWindow + 1] = nowt
  local oldest = data.frequencyWindow[1]
  if oldest and (nowt - oldest) > 60000 then
    local cutoff = 1
    while cutoff <= #data.frequencyWindow and (nowt - data.frequencyWindow[cutoff]) > 60000 do
      cutoff = cutoff + 1
    end
    if cutoff > 1 then
      for i = 1, #data.frequencyWindow - cutoff + 1 do
        data.frequencyWindow[i] = data.frequencyWindow[i + cutoff - 1]
      end
      for i = #data.frequencyWindow - cutoff + 2, #data.frequencyWindow do
        data.frequencyWindow[i] = nil
      end
    end
  end
  data.castFrequency = #data.frequencyWindow

  -- Global stats
  local stats = MonsterAI.SpellTracker.stats
  stats.totalSpellsCast = (stats.totalSpellsCast or 0) + 1
  stats.totalMissiles   = (stats.totalMissiles or 0) + 1

  table.insert(MonsterAI.SpellTracker.recentSpells, {
    time = nowt, monsterId = creatureId, monsterName = data.name,
    missileType = missileType,
    targetedPlayer = playerPos and targetPos and
      math.max(math.abs(targetPos.x - playerPos.x), math.abs(targetPos.y - playerPos.y)) <= 1
  })
  TrimArray(MonsterAI.SpellTracker.recentSpells, MonsterAI.SpellTracker.MAX_RECENT_SPELLS)

  -- Spell catalog
  if not MonsterAI.SpellTracker.spellCatalog[missileType] then
    MonsterAI.SpellTracker.spellCatalog[missileType] = {
      typeId = missileType, firstSeen = nowt,
      totalCasts = 0, monstersSeen = {}
    }
    stats.uniqueMissileTypes = (stats.uniqueMissileTypes or 0) + 1
  end
  local cat = MonsterAI.SpellTracker.spellCatalog[missileType]
  cat.totalCasts = cat.totalCasts + 1
  cat.lastSeen   = nowt
  cat.monstersSeen[data.name:lower()] = true

  -- Type-aggregated stats
  local nameLower = data.name:lower()
  local ts = MonsterAI.SpellTracker.typeSpellStats[nameLower]
  if not ts then
    ts = { name = data.name, totalSpells = 0, avgCooldown = nil,
           missileTypes = {}, spellsPerEncounter = 0, encounterCount = 0 }
    MonsterAI.SpellTracker.typeSpellStats[nameLower] = ts
  end
  ts.totalSpells = ts.totalSpells + 1
  ts.missileTypes[missileType] = (ts.missileTypes[missileType] or 0) + 1
  if data.ewmaSpellCooldown then
    ts.avgCooldown = ts.avgCooldown
      and (ts.avgCooldown * 0.9 + data.ewmaSpellCooldown * 0.1)
      or data.ewmaSpellCooldown
  end

  -- Emit event
  if EventBus and EventBus.emit then
    EventBus.emit("monsterai:spell_cast", {
      creatureId = creatureId, monsterName = data.name,
      missileType = missileType, totalSpells = data.totalSpellsCast,
      cooldown = data.ewmaSpellCooldown, frequency = data.castFrequency,
      targetedPlayer = playerPos and targetPos and
        math.max(math.abs(targetPos.x - playerPos.x), math.abs(targetPos.y - playerPos.y)) <= 1
    })
  end
end

-- ============================================================================
-- ACCESSORS
-- ============================================================================

function MonsterAI.SpellTracker.getMonsterSpells(creatureId)
  return MonsterAI.SpellTracker.monsterSpells[creatureId]
end

function MonsterAI.SpellTracker.getTypeSpellStats(monsterName)
  if not monsterName then return nil end
  return MonsterAI.SpellTracker.typeSpellStats[monsterName:lower()]
end

function MonsterAI.SpellTracker.getStats()
  local stats = MonsterAI.SpellTracker.stats
  local nowt  = nowMs()
  local sessionMin = math.max(1, (nowt - stats.sessionStartTime) / 60000)
  stats.spellsPerMinute = stats.totalSpellsCast / sessionMin

  local recentCount = 0
  for i = #MonsterAI.SpellTracker.recentSpells, 1, -1 do
    if (nowt - MonsterAI.SpellTracker.recentSpells[i].time) <= 60000 then
      recentCount = recentCount + 1
    else break end
  end
  stats.lastMinuteSpells = recentCount
  return stats
end

-- ============================================================================
-- REACTIVITY ANALYSIS
-- ============================================================================

function MonsterAI.SpellTracker.analyzeReactivity()
  local result = {
    avgTimeBetweenSpells = 0, spellBurstDetected = false,
    highVolumeThreshold  = false, lowVolumeThreshold = false,
    activeMonsterCount   = 0, totalRecentSpells = 0
  }
  local nowt = nowMs()
  local recentWindow = 10000
  local recentSpells = {}

  for i = #MonsterAI.SpellTracker.recentSpells, 1, -1 do
    local spell = MonsterAI.SpellTracker.recentSpells[i]
    if (nowt - spell.time) <= recentWindow then
      recentSpells[#recentSpells + 1] = spell
    else break end
  end
  result.totalRecentSpells = #recentSpells

  local unique = {}
  for _, s in ipairs(recentSpells) do unique[s.monsterId] = true end
  for _ in pairs(unique) do result.activeMonsterCount = result.activeMonsterCount + 1 end

  if #recentSpells >= 2 then
    local totalInt = 0
    for i = 2, #recentSpells do
      totalInt = totalInt + (recentSpells[i - 1].time - recentSpells[i].time)
    end
    result.avgTimeBetweenSpells = totalInt / (#recentSpells - 1)
  end

  if #recentSpells >= 5 and result.avgTimeBetweenSpells < 500 then
    result.spellBurstDetected = true
  end
  result.highVolumeThreshold = result.activeMonsterCount >= 4 or #recentSpells >= 15
  result.lowVolumeThreshold  = result.activeMonsterCount <= 1 and #recentSpells <= 3
  return result
end

-- ============================================================================
-- CLEANUP + SUMMARY
-- ============================================================================

function MonsterAI.SpellTracker.cleanup(creatureId)
  if not creatureId then return end
  local data = MonsterAI.SpellTracker.monsterSpells[creatureId]
  if data then
    local nameLower = data.name:lower()
    local ts = MonsterAI.SpellTracker.typeSpellStats[nameLower]
    if ts then
      ts.encounterCount = (ts.encounterCount or 0) + 1
      if data.totalSpellsCast > 0 then
        ts.spellsPerEncounter = (ts.spellsPerEncounter or 0) * 0.8 + data.totalSpellsCast * 0.2
      end
    end
  end
  MonsterAI.SpellTracker.monsterSpells[creatureId] = nil
end

function MonsterAI.SpellTracker.getSummary()
  local stats      = MonsterAI.SpellTracker.getStats()
  local reactivity = MonsterAI.SpellTracker.analyzeReactivity()
  local summary    = { stats = stats, reactivity = reactivity, catalogSize = 0, trackedMonsters = 0 }
  for _ in pairs(MonsterAI.SpellTracker.spellCatalog)   do summary.catalogSize     = summary.catalogSize + 1 end
  for _ in pairs(MonsterAI.SpellTracker.monsterSpells)   do summary.trackedMonsters = summary.trackedMonsters + 1 end
  return summary
end

if MonsterAI.DEBUG then
  print("[MonsterAI] SpellTracker module v3.0 loaded")
end
