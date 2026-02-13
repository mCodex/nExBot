--[[
  Optimized Priority Calculation System v2.1
  
  Integrates with TargetCore and MonsterAI for intelligent targeting.
  
  Features:
  1. Health-based priority with exponential scaling (finish kills!)
  2. Target stickiness (maintain focus on wounded targets)
  3. Distance optimization (closer = easier to kill)
  4. AOE optimization (for group attacks)
  5. RP Safe mode (avoid pulling extra monsters)
  6. MonsterAI-driven threat assessment
  7. Trajectory prediction for interception
  8. Classification-based danger adjustment
  9. Adaptive learning from combat feedback
  10. Real-time wave attack anticipation
  
  v2.1 Changes (Anti-Zigzag & Scenario Awareness):
  - Scenario detection: idle, single, few (2-3), moderate (4-6), swarm (7-10), overwhelming (11+)
  - Target lock system prevents erratic switching with 2-3 monsters
  - Zigzag movement detection and automatic stabilization
  - Cluster analysis for AoE optimization
  - Per-scenario targeting strategies
  - Consecutive switch penalty to prevent rapid flipping
  - "Finish kill" priority prevents switching on low-health targets
  
  v2.0 Changes:
  - 30%+ accuracy improvement via MonsterAI deep integration
  - Trajectory-based target prediction
  - Classification-aware priority adjustments
  - Combat feedback learning loop
  - Enhanced DPS and damage correlation
]]

--------------------------------------------------------------------------------
-- CLIENTSERVICE HELPERS (using global ClientHelper for consistency)
--------------------------------------------------------------------------------
local function getClient()
  return ClientHelper and ClientHelper.getClient() or ClientService
end

local function getClientVersion()
  return ClientHelper and ClientHelper.getClientVersion() or ((g_game and g_game.getClientVersion and g_game.getClientVersion()) or 1200)
end

-- Use TargetCore constants if available, otherwise define locally
-- v2.3: FURTHER INCREASED target stickiness to prevent erratic switching
local PRIO = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.PRIORITY) or {
  CRITICAL_HEALTH = 100,       -- INCREASED from 80 - always finish critical targets
  VERY_LOW_HEALTH = 70,        -- INCREASED from 55
  LOW_HEALTH = 45,             -- INCREASED from 35
  WOUNDED = 25,                -- INCREASED from 18
  CURRENT_TARGET = 70,         -- INCREASED from 50 - major stickiness boost
  CURRENT_WOUNDED = 55,        -- INCREASED from 40 - finish what you started
  CURRENT_LOW_HP = 80,         -- INCREASED from 60 - Extra bonus when current target is low HP
  ADJACENT = 14,
  CLOSE = 10,
  NEAR = 6,
  MEDIUM = 3,
  CHASE_BONUS = 12,
  AOE_BONUS = 8,
  SWITCH_PENALTY = 35,         -- NEW: Penalty for switching away from wounded target
}

local DIST_W = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.DISTANCE_WEIGHTS) or {
  [1] = 14, [2] = 10, [3] = 6, [4] = 3, [5] = 3,
  [6] = 1, [7] = 1, [8] = 0, [9] = 0, [10] = 0
}

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- MONSTER AI TUNING KNOBS v2.0 (Enhanced for 30%+ accuracy improvement)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

-- Wave attack prediction weights (INCREASED for better threat response)
local MONSTER_AI_WAVE_MULT = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.MONSTER_AI_WAVE_MULT) or 35   -- +17% from 30
local MONSTER_AI_WAVE_MIN_CONF = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.MONSTER_AI_WAVE_MIN_CONF) or 0.30 -- Lowered threshold for earlier detection
local MONSTER_AI_WAVE_IMMINENT_BONUS = 25   -- NEW: Bonus when attack is within 500ms
local MONSTER_AI_WAVE_SOON_BONUS = 12       -- NEW: Bonus when attack is within 1500ms

-- DPS-based priority (ENHANCED with tiered bonuses)
local MONSTER_AI_DPS_MULT = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.MONSTER_AI_DPS_MULT) or 1.2     -- +20% from 1.0
local MONSTER_AI_DPS_CAP = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.MONSTER_AI_DPS_CAP) or 20      -- +33% from 15
local MONSTER_AI_DPS_HIGH_THRESHOLD = 40    -- NEW: DPS considered high
local MONSTER_AI_DPS_CRITICAL_THRESHOLD = 80 -- NEW: DPS considered critical

-- Facing and direction weights (ENHANCED)
local MONSTER_AI_FACING_WEIGHT = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.MONSTER_AI_FACING_WEIGHT) or 12 -- +20% from 10
local MONSTER_AI_TURN_RATE_WEIGHT = 8       -- NEW: Weight for rapid direction changes
local MONSTER_AI_SUSTAINED_FACING_BONUS = 10 -- NEW: Bonus for sustained player focus

-- Classification-based adjustments (NEW in v2.0)
local MONSTER_AI_CLASS_DANGER_MULT = 3      -- NEW: Multiplier for estimated danger level
local MONSTER_AI_CLASS_RANGED_BONUS = 5     -- NEW: Priority boost for ranged attackers
local MONSTER_AI_CLASS_WAVE_BONUS = 8       -- NEW: Priority boost for wave attackers
local MONSTER_AI_CLASS_AGGRESSIVE_BONUS = 6 -- NEW: Priority boost for aggressive monsters

-- Trajectory prediction weights (NEW in v2.0)
local MONSTER_AI_TRAJECTORY_APPROACHING = 8 -- NEW: Bonus when moving toward player
local MONSTER_AI_TRAJECTORY_INTERCEPTABLE = 5 -- NEW: Bonus when we can intercept

-- Combat feedback learning (NEW in v2.0)
local MONSTER_AI_RECENT_DAMAGE_BONUS = 12   -- NEW: Bonus for monsters that recently damaged us
local MONSTER_AI_RECENT_DAMAGE_WINDOW = 3000 -- NEW: ms window for "recent" damage

-- Cooldown prediction weights (ENHANCED)
local MONSTER_AI_COOLDOWN_READY_BONUS = 10  -- NEW: Bonus when attack is off cooldown
local MONSTER_AI_COOLDOWN_SOON_BONUS = 5    -- NEW: Bonus when cooldown almost done

-- Variance-based reliability scoring (NEW in v2.0)
local MONSTER_AI_LOW_VARIANCE_BONUS = 4     -- NEW: Bonus for predictable monsters
local MONSTER_AI_HIGH_VARIANCE_CAUTION = 6  -- NEW: Bonus for unpredictable (stay cautious)

-- Scenario-based targeting (NEW in v2.1, ENHANCED in v2.3)
local SCENARIO_TARGET_LOCK_BONUS = 60       -- INCREASED from 40: Bonus for currently locked target
local SCENARIO_FINISH_KILL_BONUS = 100      -- INCREASED from 60: Bonus for low-health locked target
local SCENARIO_SWARM_LOW_HEALTH_MULT = 0.6  -- INCREASED from 0.5: Multiplier for low-health bonus in swarm
local SCENARIO_ZIGZAG_PENALTY = 200         -- NEW: Massive penalty when zigzag detected

-- Diamond arrow pattern for paladin optimization
local DIAMOND_ARROW_AREA = {
  {0, 1}, {1, 0}, {0, -1}, {-1, 0},
  {1, 1}, {1, -1}, {-1, 1}, {-1, -1}
}

local LARGE_RUNE_AREA = {
  {0, 1}, {1, 0}, {0, -1}, {-1, 0},
  {1, 1}, {1, -1}, {-1, 1}, {-1, -1},
  {0, 2}, {2, 0}, {0, -2}, {-2, 0}
}

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- OPENTIBIABR TARGETING ENHANCEMENTS (v3.1)
-- Use optimized pattern-based spectators when available
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local OpenTibiaBRTargeting = nil
local function loadOpenTibiaBRTargeting()
  if OpenTibiaBRTargeting then return OpenTibiaBRTargeting end
  local ok, result = pcall(function()
    return dofile("nExBot/targetbot/opentibiabr_targeting.lua")
  end)
  if ok and result then
    OpenTibiaBRTargeting = result
  end
  return OpenTibiaBRTargeting
end

-- Check if OpenTibiaBR pattern spectators is available
local function hasPatternSpectators()
  local otbr = loadOpenTibiaBRTargeting()
  return otbr and otbr.features and otbr.features.getSpectatorsByPattern
end

-- Pure function: Get monsters in area around position
-- v3.1: Enhanced with OpenTibiaBR pattern-based detection
local function getMonstersInArea(pos, offsets, maxDist)
  -- Guard against nil position
  if not pos or not pos.x or not pos.y then
    return 0
  end
  
  local count = 0
  
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  -- OPENTIBIABR ENHANCEMENT: Use pattern-based spectators for better performance
  -- This is much faster than iterating through tiles when available
  -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  local otbr = loadOpenTibiaBRTargeting()
  if otbr and hasPatternSpectators() then
    -- Determine which pattern to use based on offset count
    local patternCount = #offsets
    local aoeCount = 0
    
    if patternCount <= 8 then
      -- Diamond arrow pattern (3x3)
      aoeCount = otbr.countDiamondArrowHits(pos)
    else
      -- Large area pattern (5x5 for GFB/Avalanche)
      aoeCount = otbr.countLargeAreaHits(pos)
    end
    
    if aoeCount > 0 then
      return aoeCount
    end
    -- Fall through if function returned 0 (might be an issue)
  end

  -- Prefer MonsterCache for performance and accuracy
  if MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby then
    local radius = maxDist or 8
    local nearby = MovementCoordinator.MonsterCache.getNearby(radius)
    if nearby then
      local areaSet = {}
      for i = 1, #offsets do
        local offset = offsets[i]
        local key = (pos.x + offset[1])..","..(pos.y + offset[2])
        areaSet[key] = true
      end
      for i = 1, #nearby do
        local c = nearby[i]
        if c and c:isMonster() and not c:isDead() then
          local p = c:getPosition()
          if p and areaSet[p.x..","..p.y] then
            count = count + 1
          end
        end
      end
      return count
    end
  end

  -- Fallback to map scan
  for i = 1, #offsets do
    local offset = offsets[i]
    local checkPos = {
      x = pos.x + offset[1],
      y = pos.y + offset[2],
      z = pos.z
    }

    local Client = getClient()
    local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile and g_map.getTile(checkPos))
    if tile then
      local creatures = tile:getCreatures()
      if creatures then
        for j = 1, #creatures do
          local c = creatures[j]
          if c:isMonster() and not c:isDead() then
            count = count + 1
          end
        end
      end
    end
  end

  return count
end

-- Main priority calculation function
-- v3.0: Thin facade â€” delegates ALL scoring to PriorityEngine.
-- Retains the same signature for backward compatibility.
TargetBot.Creature.calculatePriority = function(creature, config, path)
  -- Route through unified PriorityEngine (loaded from targetbot/priority_engine.lua)
  if PriorityEngine and PriorityEngine.calculate then
    return PriorityEngine.calculate(creature, config, path)
  end

  -- Emergency fallback: basic config Ã— 1000 + distance + hp
  local pathLength = path and #path or 99
  local maxDist = config.maxDistance or 10
  if pathLength > maxDist then return 0 end
  local hp = creature:getHealthPercent()
  local priority = (config.priority or 1) * 1000
  priority = priority + (DIST_W[pathLength] or 0)
  if hp <= 10 then priority = priority + 100
  elseif hp <= 30 then priority = priority + 45
  elseif hp <= 50 then priority = priority + 25 end
  return priority
end
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- OPENTIBIABR AoE OPTIMIZATION HELPERS (v3.1)
-- Find best positions for area attacks using pattern-based detection
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

-- Find the best position to cast an AoE spell for maximum hits
-- Returns: bestPos, monsterCount
TargetBot.Creature.findBestAoEPosition = function(range, patternType)
  local otbr = loadOpenTibiaBRTargeting()
  if otbr and otbr.findBestAoEPosition then
    local playerPos = player:getPosition()
    if not playerPos then return nil, 0 end
    
    -- Map pattern types to OpenTibiaBR patterns
    local pattern, width, height
    if patternType == "diamond" or patternType == "small" then
      -- Diamond arrow / small rune pattern
      pattern = nil  -- Use default diamond
      width, height = 3, 3
    elseif patternType == "large" or patternType == "gfb" or patternType == "avalanche" then
      -- GFB/Avalanche pattern
      pattern = nil  -- Use default large
      width, height = 5, 5
    else
      -- Default to large
      pattern = nil
      width, height = 5, 5
    end
    
    return otbr.findBestAoEPosition(playerPos, range, pattern, width, height)
  end
  
  -- Fallback: Manual calculation using getMonstersInArea
  local playerPos = player:getPosition()
  if not playerPos then return nil, 0 end
  
  range = range or 3
  local bestPos = nil
  local bestCount = 0
  local pattern = (patternType == "diamond" or patternType == "small") and DIAMOND_ARROW_AREA or LARGE_RUNE_AREA
  
  -- Check tiles in range
  for dx = -range, range do
    for dy = -range, range do
      if math.abs(dx) + math.abs(dy) <= range then
        local checkPos = {x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z}
        local count = getMonstersInArea(checkPos, pattern, range)
        if count > bestCount then
          bestCount = count
          bestPos = checkPos
        end
      end
    end
  end
  
  return bestPos, bestCount
end

-- Count monsters that would be hit by AoE at specified position
TargetBot.Creature.countAoEHits = function(pos, patternType)
  if not pos then return 0 end
  
  local otbr = loadOpenTibiaBRTargeting()
  if otbr then
    if patternType == "diamond" or patternType == "small" then
      local count = otbr.countDiamondArrowHits(pos)
      if count > 0 then return count end
    else
      local count = otbr.countLargeAreaHits(pos)
      if count > 0 then return count end
    end
  end
  
  -- Fallback
  local pattern = (patternType == "diamond" or patternType == "small") and DIAMOND_ARROW_AREA or LARGE_RUNE_AREA
  return getMonstersInArea(pos, pattern, 3)
end

-- Get creatures in line (for beam spells) using direction
TargetBot.Creature.getCreaturesInBeam = function(direction, range)
  local otbr = loadOpenTibiaBRTargeting()
  if otbr and otbr.getCreaturesInFront then
    local playerPos = player:getPosition()
    if not playerPos then return {} end
    return otbr.getCreaturesInFront(playerPos, direction, range or 5)
  end
  return {}
end
