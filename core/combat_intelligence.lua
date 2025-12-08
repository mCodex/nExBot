--[[
  Combat Intelligence Module for nExBot
  Implements ROADMAP Features 11-15:
  - Feature 11: Multi-Target Wave Optimizer
  - Feature 12: Combo Sequencer
  - Feature 13: Threat Prediction System
  - Feature 14: Kill Priority Optimizer
  - Feature 15: Exori/Area Spell Timing
  
  Author: nExBot Team
  Version: 1.0
]]

CombatIntelligence = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local Config = {
  -- Wave Optimizer
  waveOptimizer = {
    enabled = true,
    minMonstersForWave = 2,       -- Minimum monsters to consider wave spell
    optimalWaveMonsters = 4,      -- Optimal monster count for max efficiency
    maxPathfindRange = 6,         -- Max tiles to consider for repositioning
    repositionCooldown = 2000,    -- Cooldown before suggesting reposition (ms)
  },
  
  -- Combo Sequencer
  comboSequencer = {
    enabled = true,
    minManaPercent = 30,          -- Minimum mana to execute combo
    burstThreshold = 3,           -- Monster count to trigger burst combo
    finisherThreshold = 15,       -- HP% to use finisher spells
    comboCooldown = 1000,         -- Minimum time between combo suggestions
  },
  
  -- Threat Prediction
  threatPrediction = {
    enabled = true,
    dangerRadius = 5,             -- Radius to check for dangerous monsters
    flankerWeight = 1.5,          -- Multiplier for monsters approaching from behind
    groupWeight = 0.5,            -- Additional weight per grouped monster
    highDangerThreshold = 100,    -- Threat score considered high danger
    criticalThreshold = 200,      -- Threat score considered critical
  },
  
  -- Kill Priority
  killPriority = {
    enabled = true,
    lowHpBonus = 50,              -- Priority bonus for low HP targets
    dangerBonus = 30,             -- Priority bonus for dangerous monsters
    lootValueWeight = 0.1,        -- Weight for loot value (if available)
    escapePreventionRadius = 8,   -- Consider monsters running away
    updateInterval = 200,         -- Update priority every N ms
  },
  
  -- Area Spell Timing
  areaSpellTiming = {
    enabled = true,
    stackingDelay = 300,          -- Wait time for monsters to stack (ms)
    minStackSize = 3,             -- Minimum monsters for optimal stack
    maxWaitTime = 2000,           -- Maximum wait time for optimal stack
    movementThreshold = 0.5,      -- Speed threshold to detect movement
  }
}

-- ============================================================================
-- STATE
-- ============================================================================
local State = {
  -- Wave Optimizer State
  lastWaveCheck = 0,
  lastRepositionSuggestion = 0,
  optimalWavePosition = nil,
  waveEfficiencyHistory = {},
  
  -- Combo Sequencer State
  lastComboTime = 0,
  currentComboSequence = {},
  comboIndex = 0,
  
  -- Threat State
  threatMap = {},
  lastThreatUpdate = 0,
  currentThreatLevel = "safe",
  
  -- Kill Priority State
  priorityList = {},
  lastPriorityUpdate = 0,
  
  -- Area Timing State
  stackingStartTime = 0,
  monsterPositions = {},
  lastStackCheck = 0,
  isWaitingForStack = false
}

-- ============================================================================
-- FEATURE 11: MULTI-TARGET WAVE OPTIMIZER
-- ============================================================================
CombatIntelligence.WaveOptimizer = {}

-- Wave spell patterns (direction -> affected tiles relative to player)
local wavePatterns = {
  small = {
    -- Small wave covers 3x7 tiles in front
    getTiles = function(playerPos, direction)
      local tiles = {}
      local dx, dy = 0, 0
      if direction == 0 then dy = -1 -- North
      elseif direction == 1 then dx = 1 -- East
      elseif direction == 2 then dy = 1 -- South
      elseif direction == 3 then dx = -1 -- West
      end
      
      -- Generate wave pattern tiles
      for distance = 1, 3 do
        local spread = math.min(distance, 2)
        for offset = -spread, spread do
          local tileX = playerPos.x + (dx * distance) + (dy ~= 0 and offset or 0)
          local tileY = playerPos.y + (dy * distance) + (dx ~= 0 and offset or 0)
          table.insert(tiles, {x = tileX, y = tileY, z = playerPos.z})
        end
      end
      return tiles
    end,
    range = 3,
    width = 5
  },
  
  large = {
    getTiles = function(playerPos, direction)
      local tiles = {}
      local dx, dy = 0, 0
      if direction == 0 then dy = -1
      elseif direction == 1 then dx = 1
      elseif direction == 2 then dy = 1
      elseif direction == 3 then dx = -1
      end
      
      for distance = 1, 5 do
        local spread = math.min(distance, 3)
        for offset = -spread, spread do
          local tileX = playerPos.x + (dx * distance) + (dy ~= 0 and offset or 0)
          local tileY = playerPos.y + (dy * distance) + (dx ~= 0 and offset or 0)
          table.insert(tiles, {x = tileX, y = tileY, z = playerPos.z})
        end
      end
      return tiles
    end,
    range = 5,
    width = 7
  }
}

-- Count monsters in wave pattern for given position and direction
local function countMonstersInWave(position, direction, waveType)
  local pattern = wavePatterns[waveType or "small"]
  if not pattern then return 0 end
  
  local tiles = pattern.getTiles(position, direction)
  local count = 0
  
  for _, tilePos in ipairs(tiles) do
    local tile = g_map.getTile({x = tilePos.x, y = tilePos.y, z = tilePos.z})
    if tile then
      for _, creature in ipairs(tile:getCreatures()) do
        if creature:isMonster() and creature:getHealthPercent() > 0 then
          count = count + 1
        end
      end
    end
  end
  
  return count
end

-- Find optimal position and direction for wave spell
function CombatIntelligence.WaveOptimizer.findOptimalCast()
  if not Config.waveOptimizer.enabled then return nil end
  
  local playerPos = pos()
  local bestResult = {
    position = nil,
    direction = nil,
    monsterCount = 0,
    needsReposition = false,
    waveType = "small"
  }
  
  -- Check current position first
  for direction = 0, 3 do
    for _, waveType in ipairs({"small", "large"}) do
      local count = countMonstersInWave(playerPos, direction, waveType)
      if count > bestResult.monsterCount then
        bestResult = {
          position = playerPos,
          direction = direction,
          monsterCount = count,
          needsReposition = false,
          waveType = waveType
        }
      end
    end
  end
  
  -- Check nearby positions for better coverage (if time allows)
  if now - State.lastRepositionSuggestion > Config.waveOptimizer.repositionCooldown then
    for dx = -2, 2 do
      for dy = -2, 2 do
        if dx ~= 0 or dy ~= 0 then
          local checkPos = {x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z}
          local tile = g_map.getTile(checkPos)
          if tile and tile:isWalkable() then
            for direction = 0, 3 do
              local count = countMonstersInWave(checkPos, direction, "large")
              if count > bestResult.monsterCount + 1 then -- +1 to justify movement
                bestResult = {
                  position = checkPos,
                  direction = direction,
                  monsterCount = count,
                  needsReposition = true,
                  waveType = "large"
                }
              end
            end
          end
        end
      end
    end
    
    if bestResult.needsReposition then
      State.lastRepositionSuggestion = now
    end
  end
  
  State.optimalWavePosition = bestResult.monsterCount >= Config.waveOptimizer.minMonstersForWave and bestResult or nil
  State.lastWaveCheck = now
  
  return State.optimalWavePosition
end

-- Get wave efficiency score (for analytics)
function CombatIntelligence.WaveOptimizer.getEfficiency()
  if not State.optimalWavePosition then return 0 end
  
  local count = State.optimalWavePosition.monsterCount
  local optimal = Config.waveOptimizer.optimalWaveMonsters
  
  return math.min(1.0, count / optimal)
end

-- Should reposition for better wave?
function CombatIntelligence.WaveOptimizer.shouldReposition()
  local result = CombatIntelligence.WaveOptimizer.findOptimalCast()
  return result and result.needsReposition and result.monsterCount >= Config.waveOptimizer.minMonstersForWave + 2
end

-- ============================================================================
-- FEATURE 12: COMBO SEQUENCER
-- ============================================================================
CombatIntelligence.ComboSequencer = {}

-- Pre-defined combo sequences based on vocation and situation
local ComboSequences = {
  knight = {
    aoe_burst = {"exori gran", "exori", "exori min"},
    single_target = {"exori gran ico", "exori ico"},
    finisher = {"exori ico"},
    defensive = {"exeta res", "utito tempo"}
  },
  
  paladin = {
    aoe_burst = {"exori san", "exori gran con"},
    single_target = {"exori con", "exori san"},
    ranged = {"exori gran con"},
    finisher = {"exori con"}
  },
  
  sorcerer = {
    aoe_burst = {"exevo gran mas vis", "exevo vis hur"},
    single_target = {"exori gran vis", "exori vis"},
    finisher = {"exori mort"},
    elemental = {"exevo flam hur", "exevo frigo hur", "exevo tera hur"}
  },
  
  druid = {
    aoe_burst = {"exevo gran mas frigo", "exevo frigo hur"},
    single_target = {"exori gran frigo", "exori frigo"},
    support_combo = {"exura gran mas res", "exevo gran mas frigo"},
    finisher = {"exori mort"}
  }
}

-- Determine current combo type based on situation
local function determineComboType()
  local monsters = getCreaturesInArea(pos(), [[
    11111
    11111
    11011
    11111
    11111
  ]], 2)
  
  local target = getTarget and getTarget() or g_game.getAttackingCreature()
  local targetHp = target and target:getHealthPercent() or 100
  
  if targetHp <= Config.comboSequencer.finisherThreshold then
    return "finisher"
  elseif monsters >= Config.comboSequencer.burstThreshold then
    return "aoe_burst"
  else
    return "single_target"
  end
end

-- Get vocation-appropriate combo sequence
function CombatIntelligence.ComboSequencer.getOptimalSequence()
  if not Config.comboSequencer.enabled then return nil end
  if manapercent() < Config.comboSequencer.minManaPercent then return nil end
  if now - State.lastComboTime < Config.comboSequencer.comboCooldown then return nil end
  
  local vocId = voc and voc() or 0
  local vocName = "knight"
  
  if vocId == 1 or vocId == 11 then vocName = "knight"
  elseif vocId == 2 or vocId == 12 then vocName = "paladin"
  elseif vocId == 3 or vocId == 13 then vocName = "sorcerer"
  elseif vocId == 4 or vocId == 14 then vocName = "druid"
  end
  
  local comboType = determineComboType()
  local sequences = ComboSequences[vocName]
  
  if not sequences or not sequences[comboType] then
    return nil
  end
  
  return {
    type = comboType,
    spells = sequences[comboType],
    vocation = vocName
  }
end

-- Get next spell in current combo
function CombatIntelligence.ComboSequencer.getNextSpell()
  local sequence = CombatIntelligence.ComboSequencer.getOptimalSequence()
  if not sequence then return nil end
  
  -- Reset combo if type changed
  if #State.currentComboSequence == 0 or State.currentComboSequence[1] ~= sequence.spells[1] then
    State.currentComboSequence = sequence.spells
    State.comboIndex = 1
  end
  
  local spell = State.currentComboSequence[State.comboIndex]
  
  -- Check if spell is castable
  if spell and canCast and canCast(spell, false, false) then
    return spell
  end
  
  -- Try next spell in sequence
  State.comboIndex = State.comboIndex + 1
  if State.comboIndex > #State.currentComboSequence then
    State.comboIndex = 1
    State.lastComboTime = now
  end
  
  return nil
end

-- Record combo execution
function CombatIntelligence.ComboSequencer.recordExecution(spell)
  State.comboIndex = State.comboIndex + 1
  if State.comboIndex > #State.currentComboSequence then
    State.comboIndex = 1
    State.lastComboTime = now
  end
end

-- ============================================================================
-- FEATURE 13: THREAT PREDICTION SYSTEM
-- ============================================================================
CombatIntelligence.ThreatPredictor = {}

-- Monster danger ratings (higher = more dangerous)
local MonsterDanger = {
  -- Default values, can be extended
  default = 10,
  high = 30,
  very_high = 50,
  extreme = 100
}

-- Known dangerous monsters
local DangerousMonsters = {
  ["demon"] = MonsterDanger.extreme,
  ["dragon lord"] = MonsterDanger.very_high,
  ["hydra"] = MonsterDanger.very_high,
  ["giant spider"] = MonsterDanger.high,
  ["dragon"] = MonsterDanger.high,
  ["behemoth"] = MonsterDanger.extreme,
  ["war golem"] = MonsterDanger.high,
  ["hellhound"] = MonsterDanger.very_high,
  ["juggernaut"] = MonsterDanger.extreme,
  ["plaguesmith"] = MonsterDanger.very_high,
  -- Add more as needed
}

-- Calculate threat for a single monster
local function calculateMonsterThreat(creature)
  if not creature or not creature:isMonster() then return 0 end
  
  local playerPos = pos()
  local creaturePos = creature:getPosition()
  local distance = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
  
  if distance > Config.threatPrediction.dangerRadius then return 0 end
  
  local name = creature:getName():lower()
  local baseDanger = DangerousMonsters[name] or MonsterDanger.default
  
  -- Distance factor (closer = more threatening)
  local distanceFactor = (Config.threatPrediction.dangerRadius - distance + 1) / Config.threatPrediction.dangerRadius
  
  -- Flank detection (behind player is more dangerous)
  local playerDir = player:getDirection()
  local isBehind = false
  if playerDir == 0 and creaturePos.y > playerPos.y then isBehind = true
  elseif playerDir == 1 and creaturePos.x < playerPos.x then isBehind = true
  elseif playerDir == 2 and creaturePos.y < playerPos.y then isBehind = true
  elseif playerDir == 3 and creaturePos.x > playerPos.x then isBehind = true
  end
  
  local flankMultiplier = isBehind and Config.threatPrediction.flankerWeight or 1.0
  
  -- Health factor (healthy monsters more threatening)
  local healthFactor = creature:getHealthPercent() / 100
  
  return baseDanger * distanceFactor * flankMultiplier * healthFactor
end

-- Calculate total threat and update threat map
function CombatIntelligence.ThreatPredictor.analyze()
  if not Config.threatPrediction.enabled then return end
  
  local totalThreat = 0
  local threats = {}
  local groupCount = 0
  
  -- Analyze all nearby monsters
  for _, creature in ipairs(getSpectators and getSpectators() or {}) do
    if creature:isMonster() and creature:getHealthPercent() > 0 then
      local threat = calculateMonsterThreat(creature)
      if threat > 0 then
        groupCount = groupCount + 1
        -- Add group threat bonus
        threat = threat + (groupCount * Config.threatPrediction.groupWeight * MonsterDanger.default)
        
        table.insert(threats, {
          creature = creature,
          name = creature:getName(),
          threat = threat,
          position = creature:getPosition()
        })
        
        totalThreat = totalThreat + threat
      end
    end
  end
  
  -- Sort by threat (highest first)
  table.sort(threats, function(a, b) return a.threat > b.threat end)
  
  -- Determine threat level
  local level = "safe"
  if totalThreat >= Config.threatPrediction.criticalThreshold then
    level = "critical"
  elseif totalThreat >= Config.threatPrediction.highDangerThreshold then
    level = "high"
  elseif totalThreat > 0 then
    level = "moderate"
  end
  
  -- Update state
  State.threatMap = threats
  State.currentThreatLevel = level
  State.lastThreatUpdate = now
  
  return {
    level = level,
    totalThreat = totalThreat,
    threats = threats,
    groupCount = groupCount
  }
end

-- Get current threat level
function CombatIntelligence.ThreatPredictor.getThreatLevel()
  return State.currentThreatLevel
end

-- Get most threatening monster
function CombatIntelligence.ThreatPredictor.getMostThreatening()
  if #State.threatMap == 0 then return nil end
  return State.threatMap[1]
end

-- Get threats from behind (flankers)
function CombatIntelligence.ThreatPredictor.getFlankers()
  local flankers = {}
  local playerPos = pos()
  local playerDir = player:getDirection()
  
  for _, threat in ipairs(State.threatMap) do
    local creaturePos = threat.position
    local isBehind = false
    
    if playerDir == 0 and creaturePos.y > playerPos.y then isBehind = true
    elseif playerDir == 1 and creaturePos.x < playerPos.x then isBehind = true
    elseif playerDir == 2 and creaturePos.y < playerPos.y then isBehind = true
    elseif playerDir == 3 and creaturePos.x > playerPos.x then isBehind = true
    end
    
    if isBehind then
      table.insert(flankers, threat)
    end
  end
  
  return flankers
end

-- ============================================================================
-- FEATURE 14: KILL PRIORITY OPTIMIZER
-- ============================================================================
CombatIntelligence.KillPriority = {}

-- Loot value estimates (can be extended/configured)
local LootValues = {
  ["dragon"] = 500,
  ["dragon lord"] = 2000,
  ["demon"] = 10000,
  ["hydra"] = 3000,
  ["giant spider"] = 800,
  ["behemoth"] = 5000,
  -- Default for unknown monsters
  default = 100
}

-- Calculate kill priority for a single monster
local function calculateKillPriority(creature)
  if not creature or not creature:isMonster() then return 0 end
  
  local hp = creature:getHealthPercent()
  local name = creature:getName():lower()
  local playerPos = pos()
  local creaturePos = creature:getPosition()
  local distance = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
  
  local priority = 0
  
  -- Low HP bonus (prevent escapes)
  if hp <= 15 then
    priority = priority + Config.killPriority.lowHpBonus * 2
  elseif hp <= 25 then
    priority = priority + Config.killPriority.lowHpBonus * 1.5
  elseif hp <= 40 then
    priority = priority + Config.killPriority.lowHpBonus
  end
  
  -- Danger bonus (kill dangerous monsters first)
  local danger = DangerousMonsters[name] or MonsterDanger.default
  priority = priority + (danger / MonsterDanger.default) * Config.killPriority.dangerBonus
  
  -- Loot value bonus
  local lootValue = LootValues[name] or LootValues.default
  priority = priority + lootValue * Config.killPriority.lootValueWeight
  
  -- Distance penalty (closer targets preferred)
  priority = priority - (distance * 2)
  
  -- Escape prevention (monsters far away with low HP)
  if hp <= 30 and distance > 3 and distance <= Config.killPriority.escapePreventionRadius then
    priority = priority + 20  -- Extra priority to prevent escape
  end
  
  return math.max(0, priority)
end

-- Update kill priority list
function CombatIntelligence.KillPriority.update()
  if not Config.killPriority.enabled then return end
  if now - State.lastPriorityUpdate < Config.killPriority.updateInterval then
    return State.priorityList
  end
  
  local priorities = {}
  
  for _, creature in ipairs(getSpectators and getSpectators() or {}) do
    if creature:isMonster() and creature:getHealthPercent() > 0 then
      local priority = calculateKillPriority(creature)
      table.insert(priorities, {
        creature = creature,
        name = creature:getName(),
        hp = creature:getHealthPercent(),
        priority = priority,
        position = creature:getPosition()
      })
    end
  end
  
  -- Sort by priority (highest first)
  table.sort(priorities, function(a, b) return a.priority > b.priority end)
  
  State.priorityList = priorities
  State.lastPriorityUpdate = now
  
  return priorities
end

-- Get optimal target
function CombatIntelligence.KillPriority.getOptimalTarget()
  local priorities = CombatIntelligence.KillPriority.update()
  if not priorities or #priorities == 0 then return nil end
  return priorities[1]
end

-- Get finisher targets (low HP, should die soon)
function CombatIntelligence.KillPriority.getFinisherTargets()
  local finishers = {}
  
  for _, entry in ipairs(State.priorityList) do
    if entry.hp <= Config.comboSequencer.finisherThreshold then
      table.insert(finishers, entry)
    end
  end
  
  return finishers
end

-- ============================================================================
-- FEATURE 15: EXORI/AREA SPELL TIMING
-- ============================================================================
CombatIntelligence.AreaTiming = {}

-- Track monster positions over time
local function updateMonsterPositions()
  local positions = {}
  
  for _, creature in ipairs(getSpectators and getSpectators() or {}) do
    if creature:isMonster() and creature:getHealthPercent() > 0 then
      local id = creature:getId()
      local currentPos = creature:getPosition()
      local prevData = State.monsterPositions[id]
      
      local isMoving = false
      if prevData then
        isMoving = (prevData.x ~= currentPos.x or prevData.y ~= currentPos.y)
      end
      
      positions[id] = {
        x = currentPos.x,
        y = currentPos.y,
        z = currentPos.z,
        isMoving = isMoving,
        lastUpdate = now
      }
    end
  end
  
  State.monsterPositions = positions
end

-- Count stationary monsters around player
local function countStationaryMonsters(range)
  local count = 0
  local playerPos = pos()
  
  for id, data in pairs(State.monsterPositions) do
    if not data.isMoving and data.z == playerPos.z then
      local distance = math.max(math.abs(playerPos.x - data.x), math.abs(playerPos.y - data.y))
      if distance <= range then
        count = count + 1
      end
    end
  end
  
  return count
end

-- Analyze stack formation
function CombatIntelligence.AreaTiming.analyzeStack()
  if not Config.areaSpellTiming.enabled then return nil end
  
  updateMonsterPositions()
  
  local playerPos = pos()
  local monstersInRange = 0
  local stationaryMonsters = countStationaryMonsters(3)
  
  -- Count total monsters in AoE range
  for _, creature in ipairs(getSpectators and getSpectators() or {}) do
    if creature:isMonster() and creature:getHealthPercent() > 0 then
      local creaturePos = creature:getPosition()
      local distance = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
      if distance <= 3 then
        monstersInRange = monstersInRange + 1
      end
    end
  end
  
  return {
    total = monstersInRange,
    stationary = stationaryMonsters,
    isOptimal = stationaryMonsters >= Config.areaSpellTiming.minStackSize,
    stackRatio = monstersInRange > 0 and stationaryMonsters / monstersInRange or 0
  }
end

-- Check if we should wait for better stack
function CombatIntelligence.AreaTiming.shouldWaitForStack()
  if not Config.areaSpellTiming.enabled then return false end
  
  local stack = CombatIntelligence.AreaTiming.analyzeStack()
  if not stack then return false end
  
  -- Already optimal
  if stack.isOptimal then
    State.isWaitingForStack = false
    return false
  end
  
  -- Not enough monsters to wait for
  if stack.total < Config.areaSpellTiming.minStackSize then
    State.isWaitingForStack = false
    return false
  end
  
  -- Start waiting timer
  if not State.isWaitingForStack then
    State.stackingStartTime = now
    State.isWaitingForStack = true
  end
  
  -- Check if we've waited too long
  if now - State.stackingStartTime > Config.areaSpellTiming.maxWaitTime then
    State.isWaitingForStack = false
    return false  -- Cast anyway, waited too long
  end
  
  -- Most monsters still moving, wait a bit
  if stack.stackRatio < 0.5 then
    return true
  end
  
  return false
end

-- Get optimal cast timing
function CombatIntelligence.AreaTiming.isOptimalCastTime()
  local stack = CombatIntelligence.AreaTiming.analyzeStack()
  if not stack then return false end
  
  return stack.isOptimal or (stack.total >= 2 and stack.stackRatio >= 0.7)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Get comprehensive combat analysis
function CombatIntelligence.analyze()
  return {
    wave = CombatIntelligence.WaveOptimizer.findOptimalCast(),
    combo = CombatIntelligence.ComboSequencer.getOptimalSequence(),
    threat = CombatIntelligence.ThreatPredictor.analyze(),
    priority = CombatIntelligence.KillPriority.update(),
    timing = CombatIntelligence.AreaTiming.analyzeStack()
  }
end

-- Get recommended action
function CombatIntelligence.getRecommendedAction()
  local threat = CombatIntelligence.ThreatPredictor.analyze()
  local priority = CombatIntelligence.KillPriority.getOptimalTarget()
  local wave = CombatIntelligence.WaveOptimizer.findOptimalCast()
  local timing = CombatIntelligence.AreaTiming.analyzeStack()
  
  -- Critical threat - prioritize survival
  if threat and threat.level == "critical" then
    return {
      action = "defensive",
      reason = "Critical threat level detected",
      data = threat
    }
  end
  
  -- Optimal wave opportunity
  if wave and wave.monsterCount >= 4 and not CombatIntelligence.AreaTiming.shouldWaitForStack() then
    return {
      action = "wave_spell",
      reason = "Optimal wave position: " .. wave.monsterCount .. " targets",
      direction = wave.direction,
      data = wave
    }
  end
  
  -- Finisher opportunity
  local finishers = CombatIntelligence.KillPriority.getFinisherTargets()
  if #finishers > 0 then
    return {
      action = "finisher",
      reason = #finishers .. " low HP target(s) - prevent escape",
      target = finishers[1],
      data = finishers
    }
  end
  
  -- Normal priority target
  if priority then
    return {
      action = "attack",
      reason = "Optimal target: " .. priority.name,
      target = priority,
      data = priority
    }
  end
  
  return {
    action = "none",
    reason = "No combat action needed"
  }
end

-- Get combat summary for display
function CombatIntelligence.getSummary()
  local threat = CombatIntelligence.ThreatPredictor.analyze()
  local priorities = CombatIntelligence.KillPriority.update()
  local wave = CombatIntelligence.WaveOptimizer.findOptimalCast()
  local timing = CombatIntelligence.AreaTiming.analyzeStack()
  
  local summary = "=== Combat Intelligence ===\n"
  summary = summary .. "\n[Threat Level]: " .. (threat and threat.level or "unknown"):upper()
  
  if threat and threat.groupCount > 0 then
    summary = summary .. " (" .. threat.groupCount .. " threats, score: " .. math.floor(threat.totalThreat) .. ")"
  end
  
  if wave then
    local dirNames = {"North", "East", "South", "West"}
    summary = summary .. "\n\n[Wave Optimizer]: " .. wave.monsterCount .. " targets"
    summary = summary .. " | Direction: " .. (dirNames[wave.direction + 1] or "?")
    if wave.needsReposition then
      summary = summary .. " (reposition recommended)"
    end
  end
  
  if timing then
    summary = summary .. "\n\n[Area Timing]: " .. timing.stationary .. "/" .. timing.total .. " stationary"
    summary = summary .. " | " .. (timing.isOptimal and "OPTIMAL" or "waiting...")
  end
  
  if priorities and #priorities > 0 then
    summary = summary .. "\n\n[Kill Priority]:"
    for i = 1, math.min(3, #priorities) do
      local p = priorities[i]
      summary = summary .. "\n  " .. i .. ". " .. p.name .. " (" .. p.hp .. "% HP) - Priority: " .. math.floor(p.priority)
    end
  end
  
  local flankers = CombatIntelligence.ThreatPredictor.getFlankers()
  if #flankers > 0 then
    summary = summary .. "\n\n[!] FLANKERS DETECTED: " .. #flankers
    for _, f in ipairs(flankers) do
      summary = summary .. "\n  - " .. f.name .. " (behind you!)"
    end
  end
  
  return summary
end

-- Configuration functions
function CombatIntelligence.setConfig(module, key, value)
  if Config[module] and Config[module][key] ~= nil then
    Config[module][key] = value
    return true
  end
  return false
end

function CombatIntelligence.getConfig(module, key)
  if Config[module] then
    return key and Config[module][key] or Config[module]
  end
  return nil
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
-- Initialization messages removed for clean output
