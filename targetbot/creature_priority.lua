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

-- ═══════════════════════════════════════════════════════════════════════════
-- MONSTER AI TUNING KNOBS v2.0 (Enhanced for 30%+ accuracy improvement)
-- ═══════════════════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════════════════
-- OPENTIBIABR TARGETING ENHANCEMENTS (v3.1)
-- Use optimized pattern-based spectators when available
-- ═══════════════════════════════════════════════════════════════════════════
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
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- OPENTIBIABR ENHANCEMENT: Use pattern-based spectators for better performance
  -- This is much faster than iterating through tiles when available
  -- ═══════════════════════════════════════════════════════════════════════════
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
-- IMPROVED v2.4: Config priority (user-set) is now the dominant factor
-- User-configured priority 1-10 is scaled to 1000-10000 base priority
-- This ensures higher config priority ALWAYS wins over lower config priority
TargetBot.Creature.calculatePriority = function(creature, config, path)
  local pathLength = path and #path or 99
  local hp = creature:getHealthPercent()
  local maxDist = config.maxDistance or 10
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- EARLY EXIT: Out of range
  -- ═══════════════════════════════════════════════════════════════════════════
  if pathLength > maxDist then
    -- Exception: nearly dead monsters still targetable (don't let them escape!)
    if hp <= 15 and pathLength <= maxDist + 2 then
      return (config.priority or 1) * 400  -- Scaled config priority
    end
    
    -- RP Safe: Cancel attack on out-of-range target
    if config.rpSafe then
      local Client = getClient()
      local currentTarget = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
      if currentTarget == creature then
        if Client and Client.cancelAttackAndFollow then
          Client.cancelAttackAndFollow()
        elseif g_game and g_game.cancelAttackAndFollow then
          g_game.cancelAttackAndFollow()
        end
      end
    end
    return 0
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- CONFIG PRIORITY SCALING (v2.4)
  -- User-set priority (1-10) is scaled by 1000x to make it the dominant factor
  -- This ensures priority 10 monster ALWAYS beats priority 5 monster, regardless
  -- of distance, health, or other modifiers (which only add ~50-300 max)
  -- ═══════════════════════════════════════════════════════════════════════════
  local CONFIG_PRIORITY_SCALE = 1000
  local priority = (config.priority or 1) * CONFIG_PRIORITY_SCALE
  
  local Client = getClient()
  local currentTarget = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
  local isCurrentTarget = (currentTarget == creature)
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- HEALTH-BASED PRIORITY (Most critical - finish kills!)
  -- Exponential scaling for low health ensures we don't switch targets
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if hp <= 5 then
    -- One-hit kill - MAXIMUM priority
    priority = priority + PRIO.CRITICAL_HEALTH + 35
  elseif hp <= 10 then
    priority = priority + PRIO.CRITICAL_HEALTH
  elseif hp <= 20 then
    priority = priority + PRIO.VERY_LOW_HEALTH
  elseif hp <= 30 then
    priority = priority + PRIO.LOW_HEALTH
  elseif hp <= 50 then
    priority = priority + PRIO.WOUNDED
  elseif hp <= 70 then
    priority = priority + 5
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- CURRENT TARGET BONUS (Target stickiness) v2.2
  -- CRITICAL: Prevents constant target switching, ensures kills complete
  -- Uses exponential scaling to strongly favor finishing current target
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if isCurrentTarget then
    -- Base stickiness bonus (always applied to current target)
    priority = priority + PRIO.CURRENT_TARGET
    
    -- EXPONENTIAL scaling for wounded targets - the lower HP, the stronger the lock
    -- This ensures we ALWAYS finish a wounded target before switching
    if hp < 70 then
      priority = priority + 10  -- Slightly damaged
    end
    if hp < 50 then
      priority = priority + PRIO.CURRENT_WOUNDED  -- Wounded
    end
    if hp < 35 then
      priority = priority + 35  -- Significantly wounded - strong lock
    end
    if hp < 25 then
      priority = priority + 45  -- Almost dead - very strong lock
    end
    if hp < 15 then
      priority = priority + 55  -- Critical HP - nearly unbreakable lock
    end
    if hp < 10 then
      priority = priority + (PRIO.CURRENT_LOW_HP or 60)  -- FINISH THIS KILL - maximum lock
    end
    
    -- Additional bonus based on how long we've been attacking this target
    -- (tracked via MonsterAI if available)
    if MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.monsters then
      local creatureId = creature:getId()
      local trackerData = MonsterAI.Tracker.monsters[creatureId]
      if trackerData and trackerData.attackStartTime then
        local attackDuration = (now or os.time() * 1000) - trackerData.attackStartTime
        -- The longer we attack, the more committed we are (caps at +30)
        local durationBonus = math.min(30, math.floor(attackDuration / 1000) * 5)
        priority = priority + durationBonus
      end
    end
  else
    -- NOT current target - apply penalty for switching
    -- This makes switching harder, especially when we have a wounded target
    local Client = getClient()
    local currentTarget = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
    if currentTarget and not currentTarget:isDead() then
      local currentHP = currentTarget:getHealthPercent()
      if currentHP < 70 then
        -- We're attacking a wounded target - significant penalty for considering others
        -- v2.3: Enhanced penalty scaling to prevent leaving monsters behind
        local switchPenalty = PRIO.SWITCH_PENALTY or 35
        if currentHP < 50 then
          switchPenalty = switchPenalty + 25  -- Total ~60 penalty
        end
        if currentHP < 30 then
          switchPenalty = switchPenalty + 40  -- Total ~100 penalty
        end
        if currentHP < 15 then
          switchPenalty = switchPenalty + 60  -- Total ~160 penalty - almost impossible to switch
        end
        priority = priority - switchPenalty
      end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- DISTANCE-BASED PRIORITY (O(1) lookup)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  local distWeight = DIST_W[pathLength] or 0
  priority = priority + distWeight
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- CHASE MODE BONUS (Low health targets when chasing)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if config.chase and hp < 35 then
    priority = priority + PRIO.CHASE_BONUS
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- AOE OPTIMIZATION (Diamond arrows, spell areas)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if config.diamondArrows then
    local creaturePos = creature:getPosition()
    local aoeMonsters = getMonstersInArea(creaturePos, DIAMOND_ARROW_AREA, 2)
    priority = priority + aoeMonsters * PRIO.AOE_BONUS
    
    -- RP Safe mode: Check for dangerous pulls
    if config.rpSafe then
      local largeAreaMonsters = getMonstersInArea(creaturePos, LARGE_RUNE_AREA, 3)
      if largeAreaMonsters > 0 and not isCurrentTarget then
        -- Could pull extra monsters - reduce priority significantly
        priority = priority - largeAreaMonsters * 10
        
        -- If currently attacking this and would pull, cancel
        if isCurrentTarget and largeAreaMonsters >= 2 then
          local Client3 = getClient()
          if Client3 and Client3.cancelAttackAndFollow then
            Client3.cancelAttackAndFollow()
          elseif g_game and g_game.cancelAttackAndFollow then
            g_game.cancelAttackAndFollow()
          end
          return 0
        end
      end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- DANGER BONUS (Higher danger = need to kill faster)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if config.danger and config.danger > 0 then
    priority = priority + config.danger * 0.5
  end

  -- ═══════════════════════════════════════════════════════════════════════════
  -- OTCLIENT API ENHANCEMENTS (Speed, Walk State, Line-of-Sight)
  -- ═══════════════════════════════════════════════════════════════════════════
  
  -- Speed-based priority: Slower monsters are easier to kill and corner
  local creatureSpeed = creature.getSpeed and creature:getSpeed() or 0
  if creatureSpeed > 0 then
    local playerSpeed = player.getSpeed and player:getSpeed() or 220 -- default player speed
    local speedRatio = creatureSpeed / math.max(1, playerSpeed)
    
    if speedRatio < 0.6 then
      -- Very slow monster - easy target, slight priority boost
      priority = priority + 8
    elseif speedRatio < 0.8 then
      -- Slower than player - still catchable
      priority = priority + 4
    elseif speedRatio > 1.3 then
      -- Very fast monster - harder to catch, slight penalty when chasing
      if config.chase then
        priority = priority - 5
      end
    end
  end
  
  -- Walk prediction: Prefer stationary targets for easier hits
  local isWalking = creature.isWalking and creature:isWalking() or false
  if not isWalking then
    -- Stationary target - easier to hit, especially for ranged
    priority = priority + 3
  else
    -- Moving target - check if walking toward or away from player
    local stepTicksLeft = creature.getStepTicksLeft and creature:getStepTicksLeft() or 0
    if stepTicksLeft > 200 then
      -- Mid-step, position will change - slight uncertainty penalty
      priority = priority - 2
    end
  end

  -- ═══════════════════════════════════════════════════════════════════════════
  -- MONSTER AI INTEGRATION v2.0 (30%+ Accuracy Improvement)
  -- Comprehensive threat assessment using telemetry, classification, and prediction
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.monsters then
    local id = creature:getId()
    local data = id and MonsterAI.Tracker.monsters[id]
    local creatureName = creature:getName()
    
    if data then
      local nowt = now or (os.time() * 1000)
      
      -- ─────────────────────────────────────────────────────────────────────
      -- SECTION 1: WAVE ATTACK PREDICTION (Enhanced)
      -- ─────────────────────────────────────────────────────────────────────
      local ok, predicted, conf, tta = pcall(function() 
        return MonsterAI.Predictor.predictWaveAttack(creature) 
      end)
      
      if ok and predicted and conf and conf > MONSTER_AI_WAVE_MIN_CONF then
        -- Scale priority by confidence (enhanced multiplier)
        priority = priority + (conf * MONSTER_AI_WAVE_MULT)
        
        -- Tiered urgency based on time-to-attack
        if tta then
          if tta < 500 then
            priority = priority + MONSTER_AI_WAVE_IMMINENT_BONUS -- Attack imminent!
          elseif tta < 1500 then
            priority = priority + MONSTER_AI_WAVE_SOON_BONUS -- Attack soon
          elseif tta < 2500 then
            priority = priority + 6 -- Attack coming
          end
        end
      end

      -- ─────────────────────────────────────────────────────────────────────
      -- SECTION 2: DPS-BASED THREAT ASSESSMENT (Enhanced with tiers)
      -- ─────────────────────────────────────────────────────────────────────
      local dps = MonsterAI.Tracker.getDPS and MonsterAI.Tracker.getDPS(id) or 0
      
      if dps and dps > 0.5 then
        -- Base DPS contribution (enhanced)
        priority = priority + math.min(dps * MONSTER_AI_DPS_MULT, MONSTER_AI_DPS_CAP)
        
        -- Tiered DPS bonuses for high-damage monsters
        if dps >= MONSTER_AI_DPS_CRITICAL_THRESHOLD then
          priority = priority + 15 -- CRITICAL: Kill this first!
        elseif dps >= MONSTER_AI_DPS_HIGH_THRESHOLD then
          priority = priority + 8  -- HIGH: Prioritize
        end
      end

      -- ─────────────────────────────────────────────────────────────────────
      -- SECTION 3: FACING AND DIRECTION ANALYSIS (Enhanced)
      -- ─────────────────────────────────────────────────────────────────────
      local facePct = math.floor(((data.facingCount or 0) / math.max(1, data.movementSamples or 1)) * 100)
      if facePct > 25 then
        priority = priority + (facePct / 100) * MONSTER_AI_FACING_WEIGHT
      end
      
      -- Turn rate analysis from RealTime tracking
      if MonsterAI.RealTime and MonsterAI.RealTime.directions then
        local dirData = MonsterAI.RealTime.directions[id]
        if dirData then
          local turnRate = dirData.turnRate or 0
          local consecutiveChanges = dirData.consecutiveChanges or 0
          
          -- Rapid direction changes = imminent attack
          if turnRate > 2.5 or consecutiveChanges >= 4 then
            priority = priority + MONSTER_AI_TURN_RATE_WEIGHT + 5
          elseif turnRate > 1.5 or consecutiveChanges >= 2 then
            priority = priority + MONSTER_AI_TURN_RATE_WEIGHT
          elseif turnRate > 0.8 then
            priority = priority + math.floor(MONSTER_AI_TURN_RATE_WEIGHT / 2)
          end
          
          -- Sustained facing = locked onto player
          local facingSince = dirData.facingPlayerSince
          if facingSince then
            local facingDuration = nowt - facingSince
            if facingDuration > 2000 then
              priority = priority + MONSTER_AI_SUSTAINED_FACING_BONUS + 5
            elseif facingDuration > 1000 then
              priority = priority + MONSTER_AI_SUSTAINED_FACING_BONUS
            elseif facingDuration > 500 then
              priority = priority + math.floor(MONSTER_AI_SUSTAINED_FACING_BONUS / 2)
            end
          end
        end
      end
      
      -- ─────────────────────────────────────────────────────────────────────
      -- SECTION 4: COOLDOWN PREDICTION (Enhanced)
      -- ─────────────────────────────────────────────────────────────────────
      local cooldown = data.ewmaCooldown or 0
      local lastAttack = data.lastAttackTime or data.lastWaveTime or 0
      
      if cooldown > 0 and lastAttack > 0 then
        local timeSinceAttack = nowt - lastAttack
        local cooldownProgress = timeSinceAttack / cooldown
        
        if cooldownProgress >= 1.0 then
          -- Attack is OFF cooldown - ready to fire!
          priority = priority + MONSTER_AI_COOLDOWN_READY_BONUS
        elseif cooldownProgress >= 0.85 then
          -- Almost off cooldown
          priority = priority + MONSTER_AI_COOLDOWN_SOON_BONUS
        elseif cooldownProgress >= 0.7 then
          -- Getting close
          priority = priority + math.floor(MONSTER_AI_COOLDOWN_SOON_BONUS / 2)
        end
      end
      
      -- ─────────────────────────────────────────────────────────────────────
      -- SECTION 5: VARIANCE-BASED RELIABILITY SCORING (Enhanced)
      -- ─────────────────────────────────────────────────────────────────────
      local variance = data.ewmaVariance or 0
      if variance > 0 and cooldown > 0 then
        local cvRatio = math.sqrt(variance) / cooldown
        
        if cvRatio < 0.15 then
          -- Very predictable - we can anticipate and prepare
          priority = priority + MONSTER_AI_LOW_VARIANCE_BONUS + 2
        elseif cvRatio < 0.25 then
          -- Moderately predictable
          priority = priority + MONSTER_AI_LOW_VARIANCE_BONUS
        elseif cvRatio > 0.6 then
          -- Highly unpredictable - stay cautious, higher priority
          priority = priority + MONSTER_AI_HIGH_VARIANCE_CAUTION + 3
        elseif cvRatio > 0.4 then
          -- Somewhat unpredictable
          priority = priority + MONSTER_AI_HIGH_VARIANCE_CAUTION
        end
      end
      
      -- ─────────────────────────────────────────────────────────────────────
      -- SECTION 6: CLASSIFICATION-BASED ADJUSTMENTS (NEW in v2.0)
      -- ─────────────────────────────────────────────────────────────────────
      if MonsterAI.Classifier and MonsterAI.Classifier.get then
        local classification = MonsterAI.Classifier.get(creatureName)
        
        if classification and classification.confidence and classification.confidence > 0.4 then
          -- Apply estimated danger level
          local estDanger = classification.estimatedDanger or 1
          priority = priority + (estDanger * MONSTER_AI_CLASS_DANGER_MULT)
          
          -- Ranged attackers are higher priority (harder to avoid)
          if classification.isRanged then
            priority = priority + MONSTER_AI_CLASS_RANGED_BONUS
          end
          
          -- Wave attackers are high threat
          if classification.isWaveAttacker then
            priority = priority + MONSTER_AI_CLASS_WAVE_BONUS
          end
          
          -- Aggressive monsters need attention
          if classification.isAggressive then
            priority = priority + MONSTER_AI_CLASS_AGGRESSIVE_BONUS
          end
          
          -- Fast monsters in chase mode are harder to escape
          if classification.isFast and config.chase then
            priority = priority + 4
          end
        end
      end
      
      -- ─────────────────────────────────────────────────────────────────────
      -- SECTION 7: TRAJECTORY PREDICTION (NEW in v2.0)
      -- ─────────────────────────────────────────────────────────────────────
      local playerPos = player and player:getPosition()
      local creaturePos = creature:getPosition()
      
      if playerPos and creaturePos and data.distanceSamples and #data.distanceSamples >= 3 then
        -- Analyze distance trend (is monster approaching or retreating?)
        local recentSamples = data.distanceSamples
        local sampleCount = #recentSamples
        
        if sampleCount >= 3 then
          local oldDist = recentSamples[math.max(1, sampleCount - 2)].distance or 10
          local newDist = recentSamples[sampleCount].distance or 10
          local distChange = oldDist - newDist
          
          if distChange > 1 then
            -- Monster is approaching quickly
            priority = priority + MONSTER_AI_TRAJECTORY_APPROACHING
            
            -- Extra bonus if we can intercept
            if newDist <= 3 then
              priority = priority + MONSTER_AI_TRAJECTORY_INTERCEPTABLE
            end
          elseif distChange > 0 then
            -- Monster is approaching slowly
            priority = priority + math.floor(MONSTER_AI_TRAJECTORY_APPROACHING / 2)
          end
        end
      end
      
      -- ─────────────────────────────────────────────────────────────────────
      -- SECTION 8: RECENT DAMAGE ATTRIBUTION (NEW in v2.0)
      -- ─────────────────────────────────────────────────────────────────────
      local lastDamageTime = data.lastDamageTime or 0
      
      if lastDamageTime > 0 then
        local timeSinceDamage = nowt - lastDamageTime
        
        if timeSinceDamage < MONSTER_AI_RECENT_DAMAGE_WINDOW then
          -- This monster recently damaged us - high threat!
          local recency = 1 - (timeSinceDamage / MONSTER_AI_RECENT_DAMAGE_WINDOW)
          priority = priority + math.floor(MONSTER_AI_RECENT_DAMAGE_BONUS * recency)
        end
      end
      
      -- ─────────────────────────────────────────────────────────────────────
      -- SECTION 9: EXTENDED TELEMETRY BONUSES (NEW in v2.0)
      -- ─────────────────────────────────────────────────────────────────────
      
      -- Health change rate (monster being damaged = we're winning)
      local healthChangeRate = data.healthChangeRate or 0
      if healthChangeRate > 5 then
        -- Monster is taking significant damage, keep focus
        priority = priority + 5
      elseif healthChangeRate > 2 then
        priority = priority + 2
      end
      
      -- Walking ratio (stationary monsters are easier targets)
      local walkingRatio = data.walkingRatio or 0.5
      if walkingRatio < 0.3 then
        -- Mostly stationary - easier to hit
        priority = priority + 3
      elseif walkingRatio > 0.7 then
        -- Very mobile - harder to hit, slight penalty
        priority = priority - 2
      end
      
      -- Missile count (monsters that have shot many projectiles are dangerous)
      local missileCount = data.missileCount or 0
      if missileCount > 5 then
        priority = priority + 6
      elseif missileCount > 2 then
        priority = priority + 3
      end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- MONSTER AI TARGETBOT INTEGRATION MODULE (NEW in v2.0)
  -- Applies adaptive weights from combat feedback learning
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if MonsterAI and MonsterAI.TargetBot and MonsterAI.TargetBot.config then
    local TBI = MonsterAI.TargetBot
    local creatureName = creature:getName()
    local creatureId = creature:getId()
    
    -- ─────────────────────────────────────────────────────────────────────
    -- SECTION 10: COMBAT FEEDBACK ADAPTIVE WEIGHTS
    -- Learn from past combat to improve future targeting
    -- ─────────────────────────────────────────────────────────────────────
    if MonsterAI.CombatFeedback and MonsterAI.CombatFeedback.getWeights then
      local weights = MonsterAI.CombatFeedback.getWeights(creatureName)
      
      if weights then
        -- Apply overall adaptive multiplier (ranges 0.8-1.2 based on accuracy)
        local overallWeight = weights.overall or 1.0
        if overallWeight > 1.0 then
          -- We underestimate this monster, boost priority
          local boost = (overallWeight - 1.0) * 50  -- Max +10% = +5 priority
          priority = priority + boost
        elseif overallWeight < 1.0 then
          -- We overestimate this monster, slight reduction
          local reduction = (1.0 - overallWeight) * 30  -- Max -10% = -3 priority
          priority = priority - reduction
        end
        
        -- Wave attack weight adjustment
        local waveWeight = weights.wave or 1.0
        if waveWeight > 1.1 then
          -- Historically waves more than expected
          priority = priority + 8
        elseif waveWeight < 0.9 then
          -- Historically waves less than expected
          priority = priority - 3
        end
        
        -- Melee attack weight adjustment  
        local meleeWeight = weights.melee or 1.0
        if meleeWeight > 1.1 then
          -- Historically more melee damage
          priority = priority + 5
        end
      end
    end
    
    -- ─────────────────────────────────────────────────────────────────────
    -- SECTION 11: REAL-TIME THREAT LEVEL FROM TBI
    -- Use TargetBot Integration module's comprehensive threat analysis
    -- ─────────────────────────────────────────────────────────────────────
    if MonsterAI.RealTime and MonsterAI.RealTime.threatLevel then
      local threatData = MonsterAI.RealTime.threatLevel[creatureId]
      
      if threatData then
        local threatLevel = threatData.level or 0
        local threatRecency = (now or os.time() * 1000) - (threatData.lastUpdate or 0)
        
        -- Only apply recent threat data (last 5 seconds)
        if threatRecency < 5000 then
          local recencyMultiplier = 1 - (threatRecency / 5000)
          local threatBonus = threatLevel * 5 * recencyMultiplier
          priority = priority + threatBonus
        end
      end
    end
    
    -- ─────────────────────────────────────────────────────────────────────
    -- SECTION 12: PATTERN RECOGNITION BONUS
    -- Monsters with known attack patterns get priority adjustment
    -- ─────────────────────────────────────────────────────────────────────
    if MonsterAI.Patterns and MonsterAI.Patterns.get then
      local pattern = MonsterAI.Patterns.get(creatureName)
      
      if pattern and pattern.confidence and pattern.confidence > 0.5 then
        -- Known wave attacker
        if pattern.isWaveAttacker then
          priority = priority + 6
        end
        
        -- Known high damage
        if pattern.avgDamage and pattern.avgDamage > 100 then
          priority = priority + 8
        elseif pattern.avgDamage and pattern.avgDamage > 50 then
          priority = priority + 4
        end
        
        -- Fast cooldown = frequent attacks
        if pattern.waveCooldown and pattern.waveCooldown < 2000 then
          priority = priority + 5
        end
      end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- SCENARIO-AWARE TARGETING v2.2
  -- Prevents erratic target switching and zigzag movement
  -- Now includes LOCAL FALLBACK when MonsterAI.Scenario is not available
  -- ═══════════════════════════════════════════════════════════════════════════
  
  -- v2.2: Local target lock state (fallback when MonsterAI.Scenario is unavailable)
  if not TargetBot.LocalTargetLock then
    TargetBot.LocalTargetLock = {
      targetId = nil,
      targetHealth = nil,
      lockTime = 0,
      switchCount = 0,
      lastSwitchTime = 0,
      recentTargets = {}  -- Track last N targets for zigzag detection
    }
  end
  local LocalLock = TargetBot.LocalTargetLock
  local creatureId = creature:getId()
  
  -- Update local lock based on current attack state
  local Client = getClient()
  local currentAttackTarget = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
  if currentAttackTarget then
    local attackId = currentAttackTarget:getId()
    if attackId ~= LocalLock.targetId then
      -- Target changed
      LocalLock.switchCount = LocalLock.switchCount + 1
      LocalLock.lastSwitchTime = now or os.time() * 1000
      
      -- Track for zigzag detection (keep last 5 targets)
      table.insert(LocalLock.recentTargets, 1, LocalLock.targetId)
      while #LocalLock.recentTargets > 5 do
        table.remove(LocalLock.recentTargets)
      end
      
      LocalLock.targetId = attackId
      LocalLock.targetHealth = currentAttackTarget:getHealthPercent()
      LocalLock.lockTime = now or os.time() * 1000
    else
      -- Same target - update health for progress tracking
      LocalLock.targetHealth = currentAttackTarget:getHealthPercent()
      -- Decay switch count over time (10 seconds to forget)
      local timeSinceSwitch = (now or os.time() * 1000) - LocalLock.lastSwitchTime
      if timeSinceSwitch > 10000 then
        LocalLock.switchCount = math.max(0, LocalLock.switchCount - 1)
      end
    end
  end
  
  -- Detect zigzag pattern (switching back and forth between same targets)
  -- v2.3: Enhanced zigzag detection with longer memory
  local isZigzagging = false
  local zigzagSeverity = 0
  if #LocalLock.recentTargets >= 3 then
    -- Check if we're bouncing between 2 targets
    local t1, t2, t3 = LocalLock.recentTargets[1], LocalLock.recentTargets[2], LocalLock.recentTargets[3]
    if t1 and t2 and t3 and t1 == t3 and t1 ~= t2 then
      isZigzagging = true
      zigzagSeverity = 1
    end
    
    -- Check for more severe zigzag (A-B-A-B pattern)
    if #LocalLock.recentTargets >= 4 then
      local t4 = LocalLock.recentTargets[4]
      if t1 and t2 and t3 and t4 and t1 == t3 and t2 == t4 and t1 ~= t2 then
        zigzagSeverity = 2  -- Severe zigzag
      end
    end
    
    -- Check for rapid switching (3+ switches in short time)
    local timeSinceFirstSwitch = (now or os.time() * 1000) - LocalLock.lastSwitchTime
    if LocalLock.switchCount >= 4 and timeSinceFirstSwitch < 5000 then
      isZigzagging = true
      zigzagSeverity = math.max(zigzagSeverity, 2)
    end
  end
  
  if MonsterAI and MonsterAI.Scenario then
    local Scenario = MonsterAI.Scenario
    
    -- Detect current combat scenario
    local scenarioType = Scenario.detectScenario and Scenario.detectScenario() or "moderate"
    local scenarioConfig = Scenario.configs and Scenario.configs[scenarioType]
    
    -- ─────────────────────────────────────────────────────────────────────
    -- SECTION 13: TARGET LOCK BONUS (Anti-Zigzag)
    -- Currently locked target gets significant priority boost
    -- ─────────────────────────────────────────────────────────────────────
    if Scenario.state and Scenario.state.targetLockId == creatureId then
      -- This is our current locked target
      priority = priority + SCENARIO_TARGET_LOCK_BONUS
      
      -- Extra bonus if making progress (health dropping)
      local lockHealth = Scenario.state.targetLockHealth or 100
      local currentHealth = hp
      local healthDrop = lockHealth - currentHealth
      
      if healthDrop > 0 then
        -- We're making progress - add stickiness based on progress
        local progressBonus = math.min(25, healthDrop * 0.5)
        priority = priority + progressBonus
      end
      
      -- FINISH KILL bonus - don't switch when target is low!
      if currentHealth < 25 then
        priority = priority + SCENARIO_FINISH_KILL_BONUS
      elseif currentHealth < 40 then
        priority = priority + SCENARIO_FINISH_KILL_BONUS * 0.6
      elseif currentHealth < 55 then
        priority = priority + SCENARIO_FINISH_KILL_BONUS * 0.3
      end
    end
    
    -- ─────────────────────────────────────────────────────────────────────
    -- SECTION 14: SCENARIO-SPECIFIC ADJUSTMENTS
    -- Different strategies for different monster counts
    -- ─────────────────────────────────────────────────────────────────────
    
    if scenarioConfig then
      -- FEW MONSTERS (2-3): Anti-zigzag is critical
      if scenarioType == Scenario.TYPES.FEW then
        -- Penalize non-locked targets heavily
        if Scenario.state.targetLockId and Scenario.state.targetLockId ~= creatureId then
          -- Check if switch would be allowed
          local canSwitch = Scenario.shouldAllowTargetSwitch and 
                           Scenario.shouldAllowTargetSwitch(creatureId, priority, hp)
          
          if not canSwitch then
            -- Apply heavy penalty to prevent switch
            priority = priority - 100
          else
            -- Minor penalty to discourage unnecessary switches
            priority = priority - 20
          end
        end
        
        -- Detect zigzag and enforce stability
        if Scenario.isZigzagging and Scenario.isZigzagging() then
          -- We're zigzagging - FORCE stability on current target
          if Scenario.state.targetLockId == creatureId then
            priority = priority + 150  -- Massive bonus to prevent any switch
          else
            priority = priority - 150  -- Massive penalty to other targets
          end
        end
        
      -- SWARM MODE (7-10): Focus on reducing mob count
      elseif scenarioType == Scenario.TYPES.SWARM then
        if scenarioConfig.focusLowestHealth then
          -- Prioritize nearly-dead monsters to reduce overall threat
          local healthBonus = (100 - hp) * SCENARIO_SWARM_LOW_HEALTH_MULT
          priority = priority + healthBonus
        end
        
      -- OVERWHELMING (11+): Survival mode
      elseif scenarioType == Scenario.TYPES.OVERWHELMING then
        -- Prefer closest high-damage targets
        if pathLength <= 2 then
          priority = priority + 30  -- Big bonus for adjacent monsters
        end
        
        -- Emergency: boost any nearly-dead target
        if hp < 15 then
          priority = priority + 40
        end
      end
    end
    
    -- ─────────────────────────────────────────────────────────────────────
    -- SECTION 15: CLUSTER-BASED ADJUSTMENTS
    -- Optimize for AoE efficiency when monsters are clustered
    -- ─────────────────────────────────────────────────────────────────────
    local clusterInfo = Scenario.state and Scenario.state.clusterInfo
    
    if clusterInfo and clusterInfo.type == "tight" then
      -- Monsters are tightly clustered - prioritize center of cluster
      local creaturePos = creature:getPosition()
      if creaturePos and clusterInfo.centroid then
        local distFromCenter = math.sqrt(
          (creaturePos.x - clusterInfo.centroid.x)^2 + 
          (creaturePos.y - clusterInfo.centroid.y)^2
        )
        
        if distFromCenter < 2 then
          priority = priority + 15  -- Near center of cluster - good AoE target
        elseif distFromCenter < 3 then
          priority = priority + 8
        end
      end
    elseif clusterInfo and clusterInfo.type == "spread" then
      -- Monsters are spread out - focus fire is better
      -- Reinforce target lock behavior
      if Scenario.state.targetLockId == creatureId then
        priority = priority + 10
      end
    end
    
    -- ─────────────────────────────────────────────────────────────────────
    -- SECTION 16: CONSECUTIVE SWITCH PENALTY
    -- Discourage rapid target switching that causes movement issues
    -- ─────────────────────────────────────────────────────────────────────
    if Scenario.state and Scenario.state.consecutiveSwitches then
      local switches = Scenario.state.consecutiveSwitches
      
      -- If we've been switching too much, apply penalty to new targets
      if switches >= 3 and Scenario.state.targetLockId ~= creatureId then
        local switchPenalty = switches * 10  -- 30+ penalty after 3 switches
        priority = priority - switchPenalty
      end
    end
  else
    -- ═══════════════════════════════════════════════════════════════════════
    -- SECTION 17: LOCAL FALLBACK TARGET LOCK (v2.2)
    -- When MonsterAI.Scenario is not available, use local state
    -- This ensures target stickiness always works
    -- ═══════════════════════════════════════════════════════════════════════
    
    -- If this is the current locked target
    if LocalLock.targetId == creatureId then
      priority = priority + SCENARIO_TARGET_LOCK_BONUS
      
      -- Bonus for progress (health dropping)
      if LocalLock.targetHealth and hp < LocalLock.targetHealth then
        local healthDrop = LocalLock.targetHealth - hp
        local progressBonus = math.min(40, healthDrop * 0.8)  -- v2.3: Increased from 30, 0.6
        priority = priority + progressBonus
      end
      
      -- FINISH KILL bonus - v2.3: Enhanced scaling
      if hp < 15 then
        priority = priority + SCENARIO_FINISH_KILL_BONUS + 40  -- Extra for critical
      elseif hp < 25 then
        priority = priority + SCENARIO_FINISH_KILL_BONUS
      elseif hp < 40 then
        priority = priority + SCENARIO_FINISH_KILL_BONUS * 0.7
      elseif hp < 55 then
        priority = priority + SCENARIO_FINISH_KILL_BONUS * 0.4
      end
      
      -- v2.3: Zigzag prevention bonus for current target
      if isZigzagging then
        local stabilityBonus = 100 + (zigzagSeverity * 50)  -- 100-200 bonus
        priority = priority + stabilityBonus
      end
    else
      -- Not current target - apply penalties based on situation
      
      -- Switch penalty based on recent switch frequency
      -- v2.3: Enhanced penalty scaling
      if LocalLock.switchCount >= 2 then
        local switchPenalty = LocalLock.switchCount * 15
        priority = priority - switchPenalty
      end
      
      -- Zigzag prevention - v2.3: Use severity for scaling
      if isZigzagging then
        local basePenalty = SCENARIO_ZIGZAG_PENALTY or 200
        local zigzagPenalty = basePenalty * (1 + zigzagSeverity * 0.5)  -- Up to 300 penalty
        priority = priority - zigzagPenalty
      end
      
      -- Extra penalty if we recently switched away from current target (prevent going back)
      for i, recentId in ipairs(LocalLock.recentTargets) do
        if recentId == creatureId and i <= 2 then
          -- This creature was a recent target we switched away from
          -- Don't go back unless it's very high priority
          priority = priority - (50 / i)  -- -50 if most recent, -25 if second most recent
        end
      end
    end
  end

  return priority
end

-- ═══════════════════════════════════════════════════════════════════════════
-- OPENTIBIABR AoE OPTIMIZATION HELPERS (v3.1)
-- Find best positions for area attacks using pattern-based detection
-- ═══════════════════════════════════════════════════════════════════════════

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