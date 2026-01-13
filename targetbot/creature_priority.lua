--[[
  Optimized Priority Calculation System v1.0
  
  Integrates with TargetCore for pure function calculations.
  
  Features:
  1. Health-based priority with exponential scaling (finish kills!)
  2. Target stickiness (maintain focus on wounded targets)
  3. Distance optimization (closer = easier to kill)
  4. AOE optimization (for group attacks)
  5. RP Safe mode (avoid pulling extra monsters)
  
  The algorithm uses the centralized TargetCore.calculatePriority()
  with local configuration handling.
]]

-- Use TargetCore constants if available, otherwise define locally
local PRIO = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.PRIORITY) or {
  CRITICAL_HEALTH = 80,
  VERY_LOW_HEALTH = 55,
  LOW_HEALTH = 35,
  WOUNDED = 18,
  CURRENT_TARGET = 15,
  CURRENT_WOUNDED = 25,
  ADJACENT = 14,
  CLOSE = 10,
  NEAR = 6,
  MEDIUM = 3,
  CHASE_BONUS = 12,
  AOE_BONUS = 8,
}

local DIST_W = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.DISTANCE_WEIGHTS) or {
  [1] = 14, [2] = 10, [3] = 6, [4] = 3, [5] = 3,
  [6] = 1, [7] = 1, [8] = 0, [9] = 0, [10] = 0
}

-- MonsterAI tuning knobs (can be overridden in TargetCore.CONSTANTS if desired)
local MONSTER_AI_WAVE_MULT = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.MONSTER_AI_WAVE_MULT) or 30   -- multiplier for wave-confidence bonus
local MONSTER_AI_WAVE_MIN_CONF = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.MONSTER_AI_WAVE_MIN_CONF) or 0.35 -- min confidence to apply wave bonus
local MONSTER_AI_DPS_MULT = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.MONSTER_AI_DPS_MULT) or 1.0     -- multiplier applied to DPS
local MONSTER_AI_DPS_CAP = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.MONSTER_AI_DPS_CAP) or 15      -- cap added to priority from DPS
local MONSTER_AI_FACING_WEIGHT = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.MONSTER_AI_FACING_WEIGHT) or 10 -- maximum weight for facing% bonus


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

-- Pure function: Get monsters in area around position
local function getMonstersInArea(pos, offsets, maxDist)
  -- Guard against nil position
  if not pos or not pos.x or not pos.y then
    return 0
  end
  
  local count = 0

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

    local tile = g_map.getTile(checkPos)
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
      return config.priority * 0.4
    end
    
    -- RP Safe: Cancel attack on out-of-range target
    if config.rpSafe then
      local currentTarget = g_game.getAttackingCreature()
      if currentTarget == creature then
        g_game.cancelAttackAndFollow()
      end
    end
    return 0
  end
  
  local priority = config.priority or 1
  local currentTarget = g_game.getAttackingCreature()
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
  -- CURRENT TARGET BONUS (Target stickiness)
  -- Prevents constant target switching, ensures kills complete
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if isCurrentTarget then
    priority = priority + PRIO.CURRENT_TARGET
    
    -- Progressive bonus for wounded targets
    if hp < 50 then
      priority = priority + PRIO.CURRENT_WOUNDED
    end
    if hp < 25 then
      priority = priority + 20  -- Don't switch when target almost dead!
    end
    if hp < 10 then
      priority = priority + 15  -- FINISH THIS KILL
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
          g_game.cancelAttackAndFollow()
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

  -- Integrate MonsterAI telemetry if available (improves targeting accuracy)
  if MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.monsters then
    local id = creature:getId()
    local data = id and MonsterAI.Tracker.monsters[id]
    if data then
      -- Predict imminent wave attack and increase priority to avoid being hit
      local ok, predicted, conf, tta = pcall(function() return MonsterAI.Predictor.predictWaveAttack(creature) end)
      if ok and predicted and conf and conf > MONSTER_AI_WAVE_MIN_CONF then
        priority = priority + (conf * MONSTER_AI_WAVE_MULT) -- scale by confidence
        
        -- Extra urgency if attack is imminent (tta = time to attack)
        if tta and tta < 1000 then
          priority = priority + 15 -- Attack within 1 second!
        elseif tta and tta < 2000 then
          priority = priority + 8
        end
      end

      -- High DPS monsters are more dangerous: add a capped bonus based on DPS
      local dps = MonsterAI.Tracker.getDPS and MonsterAI.Tracker.getDPS(id) or 0
      if dps and dps > 0.5 then
        priority = priority + math.min(dps * MONSTER_AI_DPS_MULT, MONSTER_AI_DPS_CAP)
      end

      -- If monster frequently faces player, prefer it (it's about to attack)
      local facePct = math.floor(((data.facingCount or 0) / math.max(1, data.movementSamples or 1)) * 100)
      if facePct > 30 then
        priority = priority + (facePct / 100) * MONSTER_AI_FACING_WEIGHT
      end
      
      -- ═══════════════════════════════════════════════════════════════════════
      -- ENHANCED MONSTER AI METRICS (turnRate, cooldown prediction, variance)
      -- ═══════════════════════════════════════════════════════════════════════
      
      -- Turn rate: Rapid direction changes indicate aggressive behavior
      if MonsterAI.RealTime and MonsterAI.RealTime.directions then
        local dirData = MonsterAI.RealTime.directions[id]
        if dirData then
          local turnRate = dirData.turnRate or 0
          local consecutiveChanges = dirData.consecutiveChanges or 0
          
          -- Monster turning rapidly toward player = imminent attack
          if turnRate > 2 or consecutiveChanges >= 3 then
            priority = priority + 10
          elseif turnRate > 1 then
            priority = priority + 5
          end
          
          -- Facing player for extended time = locked onto target
          local facingSince = dirData.facingPlayerSince
          if facingSince and (os.time() * 1000 - facingSince) > 1500 then
            priority = priority + 8 -- Sustained facing = preparing attack
          end
        end
      end
      
      -- Attack cooldown prediction: prioritize monsters off cooldown
      local cooldown = data.ewmaCooldown or 0
      local lastAttack = data.lastAttackTime or 0
      local timeSinceAttack = (os.time() * 1000) - lastAttack
      
      if cooldown > 0 and timeSinceAttack > cooldown * 0.8 then
        -- Monster is near end of cooldown, likely to attack soon
        priority = priority + 7
      end
      
      -- Variance-based confidence: Low variance = predictable, high variance = unpredictable
      local variance = data.ewmaVariance or 0
      if variance > 0 and cooldown > 0 then
        local cvRatio = math.sqrt(variance) / cooldown -- coefficient of variation
        if cvRatio < 0.2 then
          -- Very predictable attack pattern - we can anticipate better
          priority = priority + 3
        elseif cvRatio > 0.5 then
          -- Unpredictable - might attack anytime, stay cautious
          priority = priority + 5
        end
      end
    end
  end

  return priority
end