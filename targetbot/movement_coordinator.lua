--[[
  Movement Coordinator v1.0
  
  Unified movement decision system that coordinates all TargetBot movement
  features to prevent conflicting behaviors and erratic movement.
  
  Problem Solved:
  - Multiple systems (avoidance, chase, positioning, lure) can conflict
  - Player moves erratically when systems fight each other
  - No unified confidence threshold for movement decisions
  
  Solution:
  - Single decision point for all movement
  - Confidence-weighted voting from each system
  - DYNAMIC thresholds based on monster count
  - Movement intent queue with deduplication
  - Strong anti-oscillation protection with hysteresis
  - Position stickiness to prevent jitter (scales with danger)
  
  Features:
  - Dynamic threshold scaling based on monster count
  - More reactive when surrounded (7+ monsters)
  - Conservative when few monsters (1-2)
  - Hysteresis scales with danger level
  - Smoother transitions between reactive/conservative modes
  
  Architecture:
  - MovementCoordinator.Intent: Movement intent definitions
  - MovementCoordinator.Vote: System voting mechanism  
  - MovementCoordinator.Decide: Final decision maker
  - MovementCoordinator.Execute: Safe movement execution
  - MovementCoordinator.Scaling: Dynamic threshold scaling
]]

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

MovementCoordinator = MovementCoordinator or {}
MovementCoordinator.VERSION = "1.0"
-- Toggle to enable movement coordinator debugging output
MovementCoordinator.DEBUG = MovementCoordinator.DEBUG or false

-- ============================================================================
-- CONSTANTS
-- ============================================================================

MovementCoordinator.CONSTANTS = {
  -- Movement intent types (priority order)
  INTENT = {
    EMERGENCY_ESCAPE = 1,    -- HP critical, must escape
    WAVE_AVOIDANCE = 2,      -- Avoid wave attack
    FINISH_KILL = 3,         -- Chase low-HP target
    SPELL_POSITION = 4,      -- Position for AoE spell
    KEEP_DISTANCE = 5,       -- Maintain distance (ranged)
    REPOSITION = 6,          -- Better tactical position
    CHASE = 7,               -- Close gap to target
    FACE_MONSTER = 8,        -- Diagonal correction
    LURE = 9,                -- Pull more monsters (CaveBot)
    IDLE = 10                -- No movement needed
  },
  
  -- Intent priorities (higher = more important)
  PRIORITY = {
    [1] = 100,  -- EMERGENCY_ESCAPE
    [2] = 90,   -- WAVE_AVOIDANCE
    [3] = 80,   -- FINISH_KILL
    [4] = 60,   -- SPELL_POSITION
    [5] = 55,   -- KEEP_DISTANCE
    [6] = 40,   -- REPOSITION
    [7] = 35,   -- CHASE
    [8] = 20,   -- FACE_MONSTER
    [9] = 15,   -- LURE
    [10] = 0    -- IDLE
  },
  
  -- Minimum confidence to execute movement (tuned for responsiveness)
  CONFIDENCE_THRESHOLDS = {
    [1] = 0.40,  -- EMERGENCY: Responsive to danger
    [2] = 0.55,  -- WAVE_AVOIDANCE: Lowered for faster reaction
    [3] = 0.55,  -- FINISH_KILL: Chase wounded targets quickly
    [4] = 0.70,  -- SPELL_POSITION: High (avoid unnecessary moves)
    [5] = 0.55,  -- KEEP_DISTANCE: Responsive to range changes
    [6] = 0.60,  -- REPOSITION: Moderate threshold
    [7] = 0.50,  -- CHASE: Lower for faster target acquisition
    [8] = 0.45,  -- FACE_MONSTER: Quick diagonal correction
    [9] = 0.50,  -- LURE: Responsive to lure needs
    [10] = 1.0   -- IDLE: Never execute
  },
  
  -- Timing (tuned for responsiveness while preventing oscillation)
  TIMING = {
    DECISION_COOLDOWN = 120,     -- Min time between decisions (ms) - faster
    EXECUTION_COOLDOWN = 200,    -- Min time between movements - faster
    INTENT_TTL = 350,            -- Intent valid for 350ms
    OSCILLATION_WINDOW = 2000,   -- Track moves in this window
    MAX_OSCILLATIONS = 4,        -- Max moves before pause (more forgiving)
    HYSTERESIS_BONUS = 0.10,     -- Extra confidence needed to leave safe pos (reduced)
    POSITION_MEMORY = 600        -- Remember safe position for 600ms (shorter)
  },
  
  -- Conflict resolution
  CONFLICT = {
    SAME_POSITION_THRESHOLD = 1,  -- Positions within 1 tile are "same"
    OPPOSITE_CANCEL_WEIGHT = 0.5  -- Weight reduction for conflicting intents
  }
}

local CONST = MovementCoordinator.CONSTANTS
local INTENT = CONST.INTENT
local PRIORITY = CONST.PRIORITY
local THRESHOLDS = CONST.CONFIDENCE_THRESHOLDS
local TIMING = CONST.TIMING

-- ============================================================================
-- DYNAMIC SCALING
-- Adjusts thresholds based on monster count for reactive behavior
-- ============================================================================

MovementCoordinator.Scaling = {}

-- Cache for monster count to avoid recalculating every tick
local scalingCache = {
  monsterCount = 0,
  lastUpdate = 0,
  TTL = 150  -- Update every 150ms
}

-- Lightweight monster cache maintained from EventBus
MovementCoordinator.MonsterCache = MovementCoordinator.MonsterCache or {
  monsters = {}, -- map id -> creature
  lastUpdate = 0,
  stats = { queries = 0, hits = 0, misses = 0, lastQuery = 0 }
}

-- Expose simple stats getter
function MovementCoordinator.MonsterCache.getStats()
  return MovementCoordinator.MonsterCache.stats
end

local function updateMonsterCacheFromCreature(creature)
  if not creature then return end
  local id = creature:getId() or tostring(creature)
  MovementCoordinator.MonsterCache.monsters[id] = creature
  MovementCoordinator.MonsterCache.lastUpdate = now
end

local function removeCreatureFromCache(creature)
  if not creature then return end
  local id = creature:getId() or tostring(creature)
  MovementCoordinator.MonsterCache.monsters[id] = nil
  MovementCoordinator.MonsterCache.lastUpdate = now
end

-- Subscribe to creature events to maintain a local monster cache (lower latency)
if EventBus then
  -- Debounced updater to avoid storms
  local function makeDebounce(ms, fn)
    if nExBot and nExBot.EventUtil and nExBot.EventUtil.debounce then
      return nExBot.EventUtil.debounce(ms, fn)
    end
    -- Simple fallback debounce using schedule
    local scheduled = false
    return function()
      if scheduled then return end
      scheduled = true
      schedule(ms, function()
        scheduled = false
        pcall(fn)
      end)
    end
  end

  local debounceUpdate = makeDebounce(100, function() scalingCache.lastUpdate = 0 end)

  EventBus.on("creature:appear", function(c)
    if c and c:isMonster() and not c:isDead() then
      updateMonsterCacheFromCreature(c)
      -- Notify WavePredictor if available (non-blocking)
      if WavePredictor and WavePredictor.ensurePattern then
        pcall(WavePredictor.ensurePattern, c)
      end
      debounceUpdate()
    end
  end, 10)

  EventBus.on("creature:move", function(c, oldPos)
    if c and c:isMonster() and not c:isDead() then
      updateMonsterCacheFromCreature(c)
      -- Update WavePredictor about movement
      if WavePredictor and WavePredictor.onMove then
        pcall(WavePredictor.onMove, c, oldPos)
      end
      debounceUpdate()
    end
  end, 10)

  EventBus.on("monster:disappear", function(c)
    removeCreatureFromCache(c)
    
    -- IMPROVED: Also clean up MonsterAI tracker data for this creature
    -- This ensures all modules stay in sync when monsters disappear
    if c and MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.untrack then
      local ok, id = pcall(function() return c:getId() end)
      if ok and id then
        pcall(function() MonsterAI.Tracker.untrack(id) end)
      end
    end
    
    debounceUpdate()
  end, 10)
  
  -- ============================================================================
  -- EVENT-DRIVEN INTENT SYSTEM
  -- React immediately to game events instead of polling
  -- ============================================================================
  
  -- Track current target creature for event-driven chase
  local currentTargetId = nil
  local lastTargetMoveTime = 0
  local targetMoveIntent = nil
  
  -- When our target moves, instantly register chase intent with walk prediction
  EventBus.on("creature:move", function(creature, oldPos)
    if not creature then return end
    
    -- Check if this is our current attack target
    local attackingCreature = g_game and g_game.getAttackingCreature and g_game.getAttackingCreature()
    if not attackingCreature then return end
    if creature:getId() ~= attackingCreature:getId() then return end
    
    -- Target moved! Calculate chase intent immediately
    local playerPos = player and player:getPosition()
    local creaturePos = creature:getPosition()
    if not playerPos or not creaturePos then return end
    
    local dist = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
    
    -- Only register chase if target is moving away and out of melee range
    if dist > 1 then
      -- Use walk prediction to get optimal intercept position
      local targetPos = creaturePos
      local interceptConfidence = 0
      
      if MovementCoordinator.WalkPrediction and MovementCoordinator.WalkPrediction.calculateIntercept then
        local interceptPos, conf = MovementCoordinator.WalkPrediction.calculateIntercept(creature, playerPos)
        if interceptPos then
          targetPos = interceptPos
          interceptConfidence = conf or 0
        end
      end
      
      -- Confidence values - tuned to pass lowered CHASE threshold (0.50)
      local confidence = 0.55  -- Base passes threshold
      if dist <= 2 then confidence = 0.62 end  -- Very close - quick chase
      if dist <= 4 then confidence = 0.68 end  -- Close - high priority
      if dist > 5 then confidence = 0.75 end   -- Far - very high priority
      
      -- Boost confidence if walk prediction was successful
      if interceptConfidence > 0.7 then
        confidence = math.min(0.90, confidence + 0.05)
      end
      
      -- Boost confidence if target is wounded (finish kill priority)
      local creatureHP = creature.getHealthPercent and creature:getHealthPercent() or 100
      if creatureHP < 30 then
        confidence = math.min(0.90, confidence + 0.15)  -- Boost for wounded targets
      elseif creatureHP < 50 then
        confidence = math.min(0.85, confidence + 0.08)
      end
      
      -- Register chase intent with predicted intercept position
      MovementCoordinator.Intent.register(
        INTENT.CHASE, targetPos, confidence, "chase_event", {
          triggered = "creature_move", 
          hp = creatureHP,
          predicted = (targetPos ~= creaturePos)
        }
      )
      lastTargetMoveTime = now
    end
  end, 5)  -- High priority
  
  -- When monster appears nearby, check for danger
  EventBus.on("monster:appear", function(creature)
    if not creature then return end
    local playerPos = player and player:getPosition()
    local creaturePos = creature:getPosition()
    if not playerPos or not creaturePos then return end
    
    local dist = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
    
    -- If monster appeared very close, may need reposition
    if dist <= 2 then
      -- Trigger reposition check (higher confidence now to pass threshold)
      MovementCoordinator.Intent.register(
        INTENT.REPOSITION, playerPos, 0.55, "monster_appear_reposition", {triggered = "monster_appear"}
      )
    end
  end, 15)
  
  -- When monster health changes to low, register finish kill intent
  EventBus.on("monster:health", function(creature, percent)
    if not creature or not percent then return end
    
    -- Check if this is our target
    local attackingCreature = g_game and g_game.getAttackingCreature and g_game.getAttackingCreature()
    if not attackingCreature then return end
    if creature:getId() ~= attackingCreature:getId() then return end
    
    local creaturePos = creature:getPosition()
    local playerPos = player and player:getPosition()
    if not creaturePos or not playerPos then return end
    
    local dist = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
    
    -- Low HP target that moved away - high priority finish
    if percent < 20 and dist > 1 then
      local confidence = 0.70
      if percent < 10 then confidence = 0.85 end
      
      MovementCoordinator.Intent.register(
        INTENT.FINISH_KILL, creaturePos, confidence, "finish_kill_event", {triggered = "health_change", hp = percent}
      )
    end
  end, 8)
  
  -- When player takes damage, consider emergency escape
  EventBus.on("player:health", function(health, maxHealth, oldHealth, oldMax)
    if not health or not maxHealth then return end
    local percent = (health / maxHealth) * 100
    local oldPercent = oldHealth and oldMax and ((oldHealth / oldMax) * 100) or 100
    
    -- Check if we took significant damage
    local damageTaken = oldPercent - percent
    if damageTaken >= 10 and percent < 40 then
      -- Emergency! Find escape direction (opposite of closest monster)
      local playerPos = player and player:getPosition()
      if not playerPos then return end
      
      -- Simple escape: find walkable tile away from center of nearby monsters
      local monsterCenterX, monsterCenterY = 0, 0
      local monsterCount = 0
      for id, c in pairs(MovementCoordinator.MonsterCache.monsters) do
        if c and not c:isDead() then
          local pos = c:getPosition()
          if pos then
            monsterCenterX = monsterCenterX + pos.x
            monsterCenterY = monsterCenterY + pos.y
            monsterCount = monsterCount + 1
          end
        end
      end
      
      if monsterCount > 0 then
        monsterCenterX = monsterCenterX / monsterCount
        monsterCenterY = monsterCenterY / monsterCount
        
        -- Move away from monster center
        local escapeX = playerPos.x + (playerPos.x > monsterCenterX and 1 or -1)
        local escapeY = playerPos.y + (playerPos.y > monsterCenterY and 1 or -1)
        local escapePos = {x = escapeX, y = escapeY, z = playerPos.z}
        
        local confidence = 0.5 + (40 - percent) / 100  -- Higher confidence at lower HP
        MovementCoordinator.Intent.register(
          INTENT.EMERGENCY_ESCAPE, escapePos, confidence, "emergency_event", {triggered = "damage", hp = percent}
        )
      end
    end
  end, 5)  -- High priority
  
  -- Clear stale intents when combat ends
  EventBus.on("targetbot/combat_end", function()
    MovementCoordinator.Intent.clear()
  end, 20)
  
  -- Clear chase intents when target dies
  EventBus.on("monster:disappear", function(creature)
    if not creature then return end
    local attackingCreature = g_game and g_game.getAttackingCreature and g_game.getAttackingCreature()
    if attackingCreature and creature:getId() == attackingCreature:getId() then
      -- Target died, clear movement intents
      MovementCoordinator.Intent.clear()
    end
  end, 15)
end

-- Get current monster count (cached), uses MonsterCache when available
function MovementCoordinator.Scaling.getMonsterCount()
  if now - scalingCache.lastUpdate < scalingCache.TTL then
    return scalingCache.monsterCount
  end

  -- Prefer MonsterCache if populated
  local count = 0
  for id, c in pairs(MovementCoordinator.MonsterCache.monsters) do
    if c and not c:isDead() then
      -- Optional range check: only count monsters within 7 tiles
      local p = player and player:getPosition()
      local pos = c:getPosition()
      if p and pos and math.max(math.abs(p.x-pos.x), math.abs(p.y-pos.y)) <= 7 then
        count = count + 1
      end
    end
  end

  scalingCache.monsterCount = count
  scalingCache.lastUpdate = now
  return count
end

-- Get list of nearby monsters within given chebyshev radius
function MovementCoordinator.MonsterCache.getNearby(radius)
  radius = radius or 7
  MovementCoordinator.MonsterCache.stats.queries = MovementCoordinator.MonsterCache.stats.queries + 1
  MovementCoordinator.MonsterCache.stats.lastQuery = now
  local res = {}
  local p = player and player:getPosition()
  if not p then
    MovementCoordinator.MonsterCache.stats.misses = MovementCoordinator.MonsterCache.stats.misses + 1
    return res
  end
  for id, c in pairs(MovementCoordinator.MonsterCache.monsters) do
    if c and not c:isDead() then
      local pos = c:getPosition()
      if pos and math.max(math.abs(pos.x - p.x), math.abs(pos.y - p.y)) <= radius then
        table.insert(res, c)
      end
    end
  end
  if #res > 0 then
    MovementCoordinator.MonsterCache.stats.hits = MovementCoordinator.MonsterCache.stats.hits + 1
  else
    MovementCoordinator.MonsterCache.stats.misses = MovementCoordinator.MonsterCache.stats.misses + 1
  end
  return res
end

-- ============================================================================
-- WALK PREDICTION (OTClient API Enhancement)
-- Predicts where a creature will be based on current walk state
-- ============================================================================

MovementCoordinator.WalkPrediction = {}

-- Direction vectors for walk prediction
local DIR_VECTORS = {
  [0] = {x = 0, y = -1},  -- North
  [1] = {x = 1, y = 0},   -- East
  [2] = {x = 0, y = 1},   -- South
  [3] = {x = -1, y = 0},  -- West
  [4] = {x = 1, y = -1},  -- NE
  [5] = {x = 1, y = 1},   -- SE
  [6] = {x = -1, y = 1},  -- SW
  [7] = {x = -1, y = -1}, -- NW
}

-- Predict where creature will be after its current step completes
-- @param creature The creature to predict
-- @return pos, isWalking, ticksLeft - predicted position, walk state, time until arrival
function MovementCoordinator.WalkPrediction.predictPosition(creature)
  if not creature then return nil, false, 0 end
  
  local currentPos = creature:getPosition()
  if not currentPos then return nil, false, 0 end
  
  -- Check if creature has OTClient walk API
  local isWalking = creature.isWalking and creature:isWalking() or false
  if not isWalking then
    return currentPos, false, 0
  end
  
  -- Get walk completion time
  local ticksLeft = creature.getStepTicksLeft and creature:getStepTicksLeft() or 0
  
  -- Get walk direction if available
  local direction = creature.getDirection and creature:getDirection()
  if direction and DIR_VECTORS[direction] then
    local vec = DIR_VECTORS[direction]
    -- Creature is walking toward this position
    local targetPos = {
      x = currentPos.x + vec.x,
      y = currentPos.y + vec.y,
      z = currentPos.z
    }
    return targetPos, true, ticksLeft
  end
  
  -- Fallback: try getLastStepToPosition
  if creature.getLastStepToPosition then
    local lastDest = creature:getLastStepToPosition()
    if lastDest and lastDest.x then
      return lastDest, true, ticksLeft
    end
  end
  
  return currentPos, true, ticksLeft
end

-- Calculate optimal intercept position for chasing a walking creature
-- @param creature The creature to intercept
-- @param playerPos Player's current position
-- @return interceptPos, confidence - best position to move to
function MovementCoordinator.WalkPrediction.calculateIntercept(creature, playerPos)
  if not creature or not playerPos then return nil, 0 end
  
  local predictedPos, isWalking, ticksLeft = MovementCoordinator.WalkPrediction.predictPosition(creature)
  if not predictedPos then return nil, 0 end
  
  -- If not walking, just chase to current position
  if not isWalking then
    return predictedPos, 0.8
  end
  
  -- Get creature speed for prediction accuracy
  local creatureSpeed = creature.getSpeed and creature:getSpeed() or 200
  local playerSpeed = player and player.getSpeed and player:getSpeed() or 220
  
  -- If we're faster, intercept at predicted position
  if playerSpeed >= creatureSpeed then
    -- High confidence - we can catch up
    return predictedPos, 0.85
  else
    -- Slower than target - try to cut them off
    -- Calculate where creature will be after 2 steps
    local direction = creature.getDirection and creature:getDirection()
    if direction and DIR_VECTORS[direction] then
      local vec = DIR_VECTORS[direction]
      local futurePos = {
        x = predictedPos.x + vec.x,
        y = predictedPos.y + vec.y,
        z = predictedPos.z
      }
      -- Lower confidence since we're predicting further ahead
      return futurePos, 0.65
    end
  end
  
  return predictedPos, 0.7
end

-- Get walk state information for a creature
-- @return table with isWalking, progress, ticksLeft, speed
function MovementCoordinator.WalkPrediction.getWalkState(creature)
  if not creature then return nil end
  
  return {
    isWalking = creature.isWalking and creature:isWalking() or false,
    progress = creature.getStepProgress and creature:getStepProgress() or 0,
    ticksLeft = creature.getStepTicksLeft and creature:getStepTicksLeft() or 0,
    elapsed = creature.getWalkTicksElapsed and creature:getWalkTicksElapsed() or 0,
    speed = creature.getSpeed and creature:getSpeed() or 0,
    stepDuration = creature.getStepDuration and creature:getStepDuration() or 0
  }
end

-- Calculate scaling factor based on monster count
-- More monsters = lower thresholds = more reactive movement
-- @return number between 0.5 (many monsters) and 1.0 (few monsters)
function MovementCoordinator.Scaling.getFactor()
  local monsterCount = MovementCoordinator.Scaling.getMonsterCount()
  
  -- Scale from 1.0 (few monsters) to 0.5 (many monsters)
  -- 1-2 monsters: 1.0 (full conservative)
  -- 3-4 monsters: 0.85 (slight reactivity)
  -- 5-6 monsters: 0.7 (moderate reactivity)
  -- 7+ monsters: 0.5 (maximum reactivity)
  if monsterCount >= 7 then
    return 0.5
  elseif monsterCount >= 5 then
    return 0.7
  elseif monsterCount >= 3 then
    return 0.85
  else
    return 1.0
  end
end

-- Get adjusted confidence threshold for an intent type
-- @param intentType: INTENT constant
-- @return adjusted threshold (lower when many monsters)
function MovementCoordinator.Scaling.getThreshold(intentType)
  local baseThreshold = THRESHOLDS[intentType] or 0.7
  local scaleFactor = MovementCoordinator.Scaling.getFactor()
  
  -- WAVE_AVOIDANCE and EMERGENCY_ESCAPE scale more aggressively
  if intentType == INTENT.WAVE_AVOIDANCE or intentType == INTENT.EMERGENCY_ESCAPE then
    -- These can drop to 50% of base threshold when surrounded
    return baseThreshold * scaleFactor
  elseif intentType == INTENT.KEEP_DISTANCE or intentType == INTENT.REPOSITION then
    -- These scale moderately (down to 70% of base)
    return baseThreshold * (0.3 + scaleFactor * 0.7)
  else
    -- Other intents scale minimally (down to 85% of base)
    return baseThreshold * (0.15 + scaleFactor * 0.85)
  end
end

-- Get adjusted hysteresis bonus (less sticky when surrounded)
function MovementCoordinator.Scaling.getHysteresis()
  local scaleFactor = MovementCoordinator.Scaling.getFactor()
  -- Full hysteresis when few monsters, minimal when many
  return TIMING.HYSTERESIS_BONUS * scaleFactor
end

-- ============================================================================
-- STATE
-- ============================================================================

MovementCoordinator.State = {
  -- Current intents from each system
  intents = {},
  
  -- Last decision
  lastDecision = nil,
  lastDecisionTime = 0,
  
  -- Last execution
  lastExecution = nil,
  lastExecutionTime = 0,
  
  -- Anti-oscillation tracking
  recentMoves = {},  -- {time, position}
  
  -- Hysteresis: track safe positions to prefer staying
  safePosition = nil,
  safePositionTime = 0,
  consecutiveSafeTicks = 0,  -- How many ticks at safe position
  
  -- Position memory: where we came from
  previousPosition = nil,
  previousPositionTime = 0,
  
  -- Statistics
  stats = {
    decisionsBlocked = 0,
    oscillationsDetected = 0,
    intentsByType = {}
  }
}

local State = MovementCoordinator.State

-- ============================================================================
-- INTENT MANAGEMENT
-- ============================================================================

MovementCoordinator.Intent = {}

-- Register a movement intent from a system
-- @param intentType: INTENT constant
-- @param targetPos: target position {x, y, z}
-- @param confidence: 0-1 confidence score
-- @param source: string name of source system
-- @param data: optional additional data
function MovementCoordinator.Intent.register(intentType, targetPos, confidence, source, data)
  if not intentType or not targetPos then return end
  
  -- Validate intent type
  if not PRIORITY[intentType] then
    return
  end
  
  -- CRITICAL SAFETY: Validate target position for floor changes
  -- Prevent accidental Z-level changes during wave avoidance, chase, follow, etc.
  local currentPos = player and player:getPosition()
  if currentPos and TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isPositionSafeForMovement then
    if not TargetCore.PathSafety.isPositionSafeForMovement(targetPos, currentPos) then
      -- Log blocked unsafe intent (for debugging)
      if nExBot and nExBot.Telemetry and nExBot.Telemetry.increment then
        nExBot.Telemetry.increment("movement.intent.blocked.floor_change")
      end
      return -- Block unsafe movement intent
    end
  end
  
  -- Create intent object
  local intent = {
    type = intentType,
    position = {x = targetPos.x, y = targetPos.y, z = targetPos.z},
    confidence = math.min(math.max(confidence or 0.5, 0), 1),
    source = source or "unknown",
    priority = PRIORITY[intentType],
    threshold = THRESHOLDS[intentType],
    timestamp = now,
    data = data
  }
  
  -- Store intent (keyed by source to prevent duplicates)
  State.intents[source] = intent
  
  -- Track statistics
  State.stats.intentsByType[intentType] = (State.stats.intentsByType[intentType] or 0) + 1

  -- Telemetry: record intent registration counts (safe)
  if nExBot and nExBot.Telemetry and nExBot.Telemetry.increment then
    -- find intent name
    local intentName = "unknown"
    for k,v in pairs(CONST.INTENT) do if v == intentType then intentName = k; break end end
    nExBot.Telemetry.increment("movement.intent.registered")
    nExBot.Telemetry.increment("movement.intent.registered." .. intentName)
  end
end

-- Clear all intents (called after decision)
function MovementCoordinator.Intent.clear()
  State.intents = {}
end

-- Remove stale intents
function MovementCoordinator.Intent.cleanup()
  local cutoff = now - TIMING.INTENT_TTL
  for source, intent in pairs(State.intents) do
    if intent.timestamp < cutoff then
      State.intents[source] = nil
    end
  end
end

-- Get all current intents sorted by priority
function MovementCoordinator.Intent.getSorted()
  local sorted = {}
  for _, intent in pairs(State.intents) do
    table.insert(sorted, intent)
  end
  
  table.sort(sorted, function(a, b)
    -- Sort by priority descending, then confidence descending
    if a.priority ~= b.priority then
      return a.priority > b.priority
    end
    return a.confidence > b.confidence
  end)
  
  return sorted
end

-- ============================================================================
-- VOTING SYSTEM
-- Multiple intents can vote for same/similar positions
-- ============================================================================

MovementCoordinator.Vote = {}

-- Check if two positions are similar (within threshold)
function MovementCoordinator.Vote.positionsAreSimilar(pos1, pos2, threshold)
  threshold = threshold or CONST.CONFLICT.SAME_POSITION_THRESHOLD
  return math.abs(pos1.x - pos2.x) <= threshold and
         math.abs(pos1.y - pos2.y) <= threshold
end

-- Check if two intents conflict (want to go opposite directions)
function MovementCoordinator.Vote.intentsConflict(intent1, intent2)
  local playerPos = player:getPosition()
  if not playerPos then return false end
  
  -- Calculate direction vectors
  local dx1 = intent1.position.x - playerPos.x
  local dy1 = intent1.position.y - playerPos.y
  local dx2 = intent2.position.x - playerPos.x
  local dy2 = intent2.position.y - playerPos.y
  
  -- Dot product: negative means opposite directions
  local dot = dx1 * dx2 + dy1 * dy2
  return dot < 0
end

-- Aggregate votes from all intents
-- @return winningIntent, aggregatedConfidence
function MovementCoordinator.Vote.aggregate()
  local intents = MovementCoordinator.Intent.getSorted()
  
  if #intents == 0 then
    return nil, 0
  end
  
  -- Group similar intents
  local groups = {}
  
  for i = 1, #intents do
    local intent = intents[i]
    local foundGroup = false
    
    for j = 1, #groups do
      if MovementCoordinator.Vote.positionsAreSimilar(intent.position, groups[j].position) then
        -- Add to existing group
        groups[j].votes = groups[j].votes + 1
        groups[j].totalConfidence = groups[j].totalConfidence + intent.confidence
        groups[j].totalPriority = groups[j].totalPriority + intent.priority
        groups[j].intents[#groups[j].intents + 1] = intent
        foundGroup = true
        break
      end
    end
    
    if not foundGroup then
      -- Create new group
      table.insert(groups, {
        position = intent.position,
        votes = 1,
        totalConfidence = intent.confidence,
        totalPriority = intent.priority,
        intents = {intent},
        leadIntent = intent  -- Highest priority intent in group
      })
    end
  end
  
  -- Check for conflicts and reduce confidence
  for i = 1, #groups do
    for j = i + 1, #groups do
      if MovementCoordinator.Vote.intentsConflict(groups[i].leadIntent, groups[j].leadIntent) then
        -- Reduce confidence of lower priority group
        local lower = groups[i].totalPriority < groups[j].totalPriority and i or j
        groups[lower].totalConfidence = groups[lower].totalConfidence * CONST.CONFLICT.OPPOSITE_CANCEL_WEIGHT
      end
    end
  end
  
  -- Score each group
  local bestGroup = nil
  local bestScore = -99999
  
  for i = 1, #groups do
    local group = groups[i]
    -- Score = priority * confidence * (vote boost)
    local voteBoost = 1 + (group.votes - 1) * 0.2  -- 20% boost per additional vote
    local score = group.totalPriority * (group.totalConfidence / group.votes) * voteBoost
    
    if score > bestScore then
      bestScore = score
      bestGroup = group
    end
  end
  
  if bestGroup then
    local avgConfidence = bestGroup.totalConfidence / bestGroup.votes
    return bestGroup.leadIntent, avgConfidence
  end
  
  return nil, 0
end

-- ============================================================================
-- DECISION MAKER
-- ============================================================================

MovementCoordinator.Decide = {}

-- Make final movement decision with dynamic scaling
-- @return decision { shouldMove, intent, confidence, blocked, reason }
function MovementCoordinator.Decide.make()
  -- Cleanup stale intents
  MovementCoordinator.Intent.cleanup()
  
  -- Check decision cooldown
  if now - State.lastDecisionTime < TIMING.DECISION_COOLDOWN then
    if nExBot and nExBot.Telemetry and nExBot.Telemetry.increment then
      nExBot.Telemetry.increment("movement.decision.blocked.cooldown")
      nExBot.Telemetry.increment("movement.decision.blocked")
    end
    return { shouldMove = false, blocked = true, reason = "cooldown" }
  end
  
  -- Aggregate votes
  local winningIntent, confidence = MovementCoordinator.Vote.aggregate()
  
  if not winningIntent then
    -- No movement needed - track this as safe position
    MovementCoordinator.Decide.markCurrentAsSafe()
    return { shouldMove = false, blocked = false, reason = "no_intents" }
  end
  
  -- Get DYNAMIC threshold based on monster count
  -- More monsters = lower threshold = more willing to move
  local effectiveThreshold = MovementCoordinator.Scaling.getThreshold(winningIntent.type)
  
  -- Apply hysteresis: require extra confidence to leave safe position
  -- Hysteresis also scales with monster count (less sticky when surrounded)
  if State.safePosition and now - State.safePositionTime < TIMING.POSITION_MEMORY then
    -- Check if we're still at safe position
    local playerPos = player:getPosition()
    if playerPos and State.safePosition.x == playerPos.x and State.safePosition.y == playerPos.y then
      -- Add dynamic hysteresis bonus to threshold
      local hysteresisBonus = MovementCoordinator.Scaling.getHysteresis()
      effectiveThreshold = effectiveThreshold + hysteresisBonus
      State.consecutiveSafeTicks = State.consecutiveSafeTicks + 1
    else
      -- Moved away from safe position
      State.consecutiveSafeTicks = 0
    end
  end
  
  -- Check confidence threshold (with dynamic scaling and hysteresis applied)
  if confidence < effectiveThreshold then
    State.stats.decisionsBlocked = State.stats.decisionsBlocked + 1
    -- Telemetry: low-confidence blocks
    if nExBot and nExBot.Telemetry and nExBot.Telemetry.increment then
      local intentName = "unknown"
      if winningIntent and winningIntent.type then
        for k,v in pairs(CONST.INTENT) do if v == winningIntent.type then intentName = k; break end end
      end
      nExBot.Telemetry.increment("movement.decision.blocked.low_confidence")
      nExBot.Telemetry.increment("movement.decision.blocked")
      nExBot.Telemetry.increment("movement.decision.blocked.intent." .. intentName)
    end
    return {
      shouldMove = false,
      blocked = true,
      reason = "low_confidence",
      intent = winningIntent,
      confidence = confidence,
      threshold = effectiveThreshold,
      monsterCount = MovementCoordinator.Scaling.getMonsterCount()
    }
  end
  
  -- Check anti-oscillation
  if MovementCoordinator.Decide.isOscillating() then
    State.stats.oscillationsDetected = State.stats.oscillationsDetected + 1
    if nExBot and nExBot.Telemetry and nExBot.Telemetry.increment then
      local intentName = "unknown"
      if winningIntent and winningIntent.type then
        for k,v in pairs(CONST.INTENT) do if v == winningIntent.type then intentName = k; break end end
      end
      nExBot.Telemetry.increment("movement.oscillation")
      nExBot.Telemetry.increment("movement.decision.blocked.oscillation")
      nExBot.Telemetry.increment("movement.decision.blocked.intent." .. intentName)
    end
    return {
      shouldMove = false,
      blocked = true,
      reason = "oscillation",
      intent = winningIntent,
      confidence = confidence
    }
  end
  
  -- Decision approved
  State.lastDecision = winningIntent
  State.lastDecisionTime = now
  
  -- Clear safe position since we're moving
  State.safePosition = nil
  State.consecutiveSafeTicks = 0
  
  return {
    shouldMove = true,
    blocked = false,
    intent = winningIntent,
    confidence = confidence,
    reason = "approved"
  }
end

-- Mark current position as safe (for hysteresis)
function MovementCoordinator.Decide.markCurrentAsSafe()
  local playerPos = player:getPosition()
  if playerPos then
    State.safePosition = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
    State.safePositionTime = now
  end
end

-- Check if player is oscillating (moving back and forth)
function MovementCoordinator.Decide.isOscillating()
  local cutoff = now - TIMING.OSCILLATION_WINDOW
  
  -- Clean old moves
  local newMoves = {}
  for i = 1, #State.recentMoves do
    if State.recentMoves[i].time > cutoff then
      table.insert(newMoves, State.recentMoves[i])
    end
  end
  State.recentMoves = newMoves
  
  -- Check if too many moves in window (reduced from 4 to 3)
  if #State.recentMoves >= TIMING.MAX_OSCILLATIONS then
    -- Check if positions are similar (bouncing between same spots)
    local uniquePositions = {}
    local positionCounts = {}
    
    for i = 1, #State.recentMoves do
      local pos = State.recentMoves[i].position
      local key = math.floor(pos.x) .. "," .. math.floor(pos.y)
      uniquePositions[key] = true
      positionCounts[key] = (positionCounts[key] or 0) + 1
    end
    
    local uniqueCount = 0
    local maxRevisits = 0
    for key, count in pairs(positionCounts) do
      uniqueCount = uniqueCount + 1
      if count > maxRevisits then
        maxRevisits = count
      end
    end
    
    -- Oscillating if:
    -- 1. Few unique positions (bouncing between 2-3 spots)
    -- 2. OR any position visited multiple times
    if uniqueCount <= 2 or maxRevisits >= 2 then
      return true
    end
  end
  
  return false
end

-- ============================================================================
-- EXECUTION
-- ============================================================================

MovementCoordinator.Execute = {}

-- Execute a movement decision safely
-- @param decision: result from Decide.make()
-- @return success, message
function MovementCoordinator.Execute.move(decision)
  if not decision.shouldMove or not decision.intent then
    return false, decision.reason
  end
  
  -- Check execution cooldown
  if now - State.lastExecutionTime < TIMING.EXECUTION_COOLDOWN then
    return false, "execution_cooldown"
  end
  
  local intent = decision.intent
  local targetPos = intent.position
  
  -- Validate target position
  local playerPos = player:getPosition()
  if not playerPos or not targetPos then
    return false, "invalid_position"
  end
  
  -- ADDITIONAL SAFETY: Double-check target position for floor changes
  -- This is a backup validation in case intent registration missed something
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isPositionSafeForMovement then
    if not TargetCore.PathSafety.isPositionSafeForMovement(targetPos, playerPos) then
      -- Log blocked unsafe execution (for debugging)
      if nExBot and nExBot.Telemetry and nExBot.Telemetry.increment then
        nExBot.Telemetry.increment("movement.execution.blocked.floor_change")
      end
      return false, "unsafe_position_floor_change"
    end
  end
  
  -- Check if already at target
  if playerPos.x == targetPos.x and playerPos.y == targetPos.y then
    return false, "already_at_target"
  end
  
  -- Track this move for oscillation detection
  table.insert(State.recentMoves, {
    time = now,
    position = {x = targetPos.x, y = targetPos.y}
  })

  -- Telemetry: attempt
  local intentName = "unknown"
  for k,v in pairs(CONST.INTENT) do if v == intent.type then intentName = k; break end end
  if nExBot and nExBot.Telemetry and nExBot.Telemetry.increment then
    nExBot.Telemetry.increment("movement.execution.attempt")
    nExBot.Telemetry.increment("movement.execution.attempt." .. intentName)
  end
  
  -- Execute the move
  local success = false
  
  -- OTCLIENT API: Check if player is already walking to avoid interrupting smooth movement
  if player and (player.isWalking and player:isWalking()) then
    -- Check if current movement is already heading toward target
    local currentTarget = player:getPosition()
    if currentTarget then
      local distToTarget = math.abs(currentTarget.x - targetPos.x) + math.abs(currentTarget.y - targetPos.y)
      if distToTarget <= 3 then  -- Close enough, let current walk continue
        return true, "already_moving_to_target"
      end
    end
  end
  
  -- Use appropriate movement method based on intent type
  if intent.type == INTENT.LURE then
    -- Delegate to CaveBot
    if TargetBot and TargetBot.allowCaveBot then
      TargetBot.allowCaveBot(150)
      success = true
    end
  elseif intent.type == INTENT.WAVE_AVOIDANCE or 
         intent.type == INTENT.EMERGENCY_ESCAPE then
    -- OTCLIENT API: Quick emergency movement with optimized parameters
    if TargetBot and TargetBot.walkTo then
      success = TargetBot.walkTo(targetPos, 2, {
        ignoreNonPathable = true, 
        precision = 0,
        ignoreCreatures = false  -- Allow weaving through creatures in emergencies
      })
    end
  elseif intent.type == INTENT.CHASE or intent.type == INTENT.FINISH_KILL then
    -- CHASE/FINISH_KILL: Use custom pathfinding with native chase mode as backup
    -- Many servers don't properly support native chase mode, so we use walkTo
    -- to ensure the character actually moves toward the target
    
    -- Set native chase mode as well (helps on servers that support it)
    if g_game.setChaseMode then
      g_game.setChaseMode(1) -- ChaseOpponent
    end
    
    -- Use custom pathfinding to actually move toward the target
    if TargetBot and TargetBot.walkTo then
      success = TargetBot.walkTo(targetPos, 10, {
        ignoreNonPathable = true,
        precision = 1,
        allowOnlyVisibleTiles = true
      })
    end
    
    -- If walkTo didn't work, still consider it partial success since chase mode is set
    if not success then
      success = true -- Native chase mode is set, may still work on some servers
    end
  else
    -- OTCLIENT API: Standard movement with walkability validation
    if TargetBot and TargetBot.walkTo then
      success = TargetBot.walkTo(targetPos, 10, {
        ignoreNonPathable = true, 
        precision = 1,
        allowOnlyVisibleTiles = true  -- Safety first
      })
    elseif CaveBot and CaveBot.GoTo then
      success = CaveBot.GoTo(targetPos, 0)
    end
  end

  -- Telemetry: success/failure
  if nExBot and nExBot.Telemetry and nExBot.Telemetry.increment then
    if success then
      nExBot.Telemetry.increment("movement.execution.success")
      nExBot.Telemetry.increment("movement.execution.success." .. intentName)
    else
      nExBot.Telemetry.increment("movement.execution.failed")
      nExBot.Telemetry.increment("movement.execution.failed." .. intentName)
    end
  end
  
  if success then
    State.lastExecution = intent
    State.lastExecutionTime = now
  end
  
  -- Clear intents after execution attempt
  MovementCoordinator.Intent.clear()
  
  return success, success and "executed" or "execution_failed"
end

-- ============================================================================
-- INTEGRATION HELPERS
-- Easy functions for other systems to register intents
-- ============================================================================

-- Register wave avoidance intent
function MovementCoordinator.avoidWave(safePos, confidence)
  MovementCoordinator.Intent.register(
    INTENT.WAVE_AVOIDANCE, safePos, confidence, "wave_avoidance"
  )
end

-- Register chase intent
function MovementCoordinator.chase(targetPos, confidence)
  MovementCoordinator.Intent.register(
    INTENT.CHASE, targetPos, confidence, "chase"
  )
end

-- Register finish kill intent (high priority chase)
function MovementCoordinator.finishKill(targetPos, confidence)
  MovementCoordinator.Intent.register(
    INTENT.FINISH_KILL, targetPos, confidence, "finish_kill"
  )
end

-- Register keep distance intent
function MovementCoordinator.keepDistance(safePos, confidence)
  MovementCoordinator.Intent.register(
    INTENT.KEEP_DISTANCE, safePos, confidence, "keep_distance"
  )
end

-- Register spell position intent
function MovementCoordinator.positionForSpell(optimalPos, confidence, spellName)
  MovementCoordinator.Intent.register(
    INTENT.SPELL_POSITION, optimalPos, confidence, "spell_position", {spell = spellName}
  )
end

-- Register reposition intent
function MovementCoordinator.reposition(betterPos, confidence)
  MovementCoordinator.Intent.register(
    INTENT.REPOSITION, betterPos, confidence, "reposition"
  )
end

-- Register lure intent
function MovementCoordinator.lure(lurePos, confidence)
  MovementCoordinator.Intent.register(
    INTENT.LURE, lurePos, confidence, "lure"
  )
end

-- Register face monster intent
function MovementCoordinator.faceMonster(cardinalPos, confidence)
  MovementCoordinator.Intent.register(
    INTENT.FACE_MONSTER, cardinalPos, confidence, "face_monster"
  )
end

-- Emergency escape disabled per user request (no-op)
function MovementCoordinator.emergencyEscape(escapePos, confidence)

  return
end

-- ============================================================================
-- MAIN TICK
-- Call this from main TargetBot loop
-- ============================================================================

function MovementCoordinator.tick()
  local decision = MovementCoordinator.Decide.make()
  
  if decision.shouldMove then
    return MovementCoordinator.Execute.move(decision)
  end
  
  return false, decision.reason
end

-- TUNING utilities: analyze telemetry and suggest conservative adjustments
MovementCoordinator.Tuning = {}

-- Analyze telemetry counters and return a list of human-friendly suggestions and raw counters
function MovementCoordinator.Tuning.analyze()
  local tele = nExBot and nExBot.Telemetry and nExBot.Telemetry.get and nExBot.Telemetry.get()
  tele = tele or {}
  local suggestions = {}

  local executed = tele["movement.execution.success"] or 0
  local failed = tele["movement.execution.failed"] or 0
  local oscillations = tele["movement.oscillation"] or 0
  local blocked_low = tele["movement.decision.blocked.low_confidence"] or 0
  local totalBlocked = tele["movement.decision.blocked"] or 0
  local registeredWave = tele["movement.intent.registered.WAVE_AVOIDANCE"] or 0

  -- Heuristic: if oscillations are high relative to executed moves, suggest increasing hysteresis
  if executed > 0 and (oscillations / math.max(1, executed)) > 0.15 then
    table.insert(suggestions, "High oscillation rate: consider increasing TIMING.MAX_OSCILLATIONS by 1 or increasing HYSTERESIS_BONUS by ~0.05")
  end

  -- Heuristic: many low confidence blocks while wave predictions are frequent
  if registeredWave > 0 and blocked_low > executed * 1.5 then
    table.insert(suggestions, "Many low-confidence blocks for wave avoidance: consider lowering WAVE_AVOIDANCE threshold or reduce its scale factor")
  end

  -- Heuristic: many execution failures relative to attempts
  local attempts = tele["movement.execution.attempt"] or 0
  if attempts > 0 and (failed / attempts) > 0.25 then
    table.insert(suggestions, "High execution failure rate: inspect pathing and consider raising EXECUTION_COOLDOWN or increasing PATH safety checks")
  end

  return suggestions, tele
end

function MovementCoordinator.Tuning.report()
  local suggestions, tele = MovementCoordinator.Tuning.analyze()

  for k,v in pairs(tele) do
    -- data: k,v (silent)
  end
  if #suggestions == 0 then
    -- No suggestions (metrics look healthy)
  else
    -- Suggestions available (silent)
    for i,s in ipairs(suggestions) do
      -- suggestion: s (silent)
    end
  end
end

-- Run a short synthetic trace to generate representative telemetry for tuning
function MovementCoordinator.Tuning.runSyntheticTrace()
  if not (nExBot and nExBot.Telemetry and nExBot.Telemetry.increment) then
    print("[MovementCoordinator][Tuning] telemetry not available; cannot run synthetic trace")
    return false
  end

  -- Run synthetic trace (silent)
  nExBot.Telemetry.increment("movement.execution.attempt", 100)
  nExBot.Telemetry.increment("movement.execution.success", 70)
  nExBot.Telemetry.increment("movement.execution.failed", 30)
  nExBot.Telemetry.increment("movement.oscillation", 20)
  nExBot.Telemetry.increment("movement.decision.blocked.low_confidence", 200)
  nExBot.Telemetry.increment("movement.decision.blocked", 220)
  nExBot.Telemetry.increment("movement.intent.registered.WAVE_AVOIDANCE", 20)

  local suggestions, tele = MovementCoordinator.Tuning.analyze()
  -- suggestions handled silently
  if #suggestions > 0 then
    MovementCoordinator.Tuning.applyRecommendations(suggestions)
  end
  return true
end

-- Apply conservative adjustments based on analyzer suggestions
function MovementCoordinator.Tuning.applyRecommendations(suggestions)
  suggestions = suggestions or MovementCoordinator.Tuning.analyze()
  if type(suggestions) == "table" and suggestions[1] then
    suggestions = suggestions
  else
    -- If passed (suggestions, tele) pair
    suggestions = suggestions
  end

  local applied = {}

  for _, s in ipairs(suggestions) do
    -- Oscillation suggestion: increase MAX_OSCILLATIONS by 1 and HYSTERESIS_BONUS by 0.05
    if s:find("High oscillation rate") then
      local old = TIMING.MAX_OSCILLATIONS
      TIMING.MAX_OSCILLATIONS = math.max(1, TIMING.MAX_OSCILLATIONS + 1)
      table.insert(applied, string.format("MAX_OSCILLATIONS: %d -> %d", old, TIMING.MAX_OSCILLATIONS))
      local oldH = TIMING.HYSTERESIS_BONUS
      TIMING.HYSTERESIS_BONUS = TIMING.HYSTERESIS_BONUS + 0.05
      table.insert(applied, string.format("HYSTERESIS_BONUS: %.3f -> %.3f", oldH, TIMING.HYSTERESIS_BONUS))
    end

    -- Low-confidence/wave suggestion: reduce WAVE_AVOIDANCE threshold by 0.05 (clamped)
    if s:find("lowering WAVE_AVOIDANCE") then
      local old = THRESHOLDS[INTENT.WAVE_AVOIDANCE]
      local newv = math.max(0.4, old - 0.05)
      THRESHOLDS[INTENT.WAVE_AVOIDANCE] = newv
      table.insert(applied, string.format("WAVE_AVOIDANCE threshold: %.2f -> %.2f", old, newv))
    end

    -- Execution failure suggestion: raise EXECUTION_COOLDOWN by +100ms
    if s:find("High execution failure rate") then
      local old = TIMING.EXECUTION_COOLDOWN
      TIMING.EXECUTION_COOLDOWN = TIMING.EXECUTION_COOLDOWN + 100
      table.insert(applied, string.format("EXECUTION_COOLDOWN: %d -> %d", old, TIMING.EXECUTION_COOLDOWN))
    end
  end

  -- Additional conservative adjustments regardless of which suggestions matched
  -- Slightly increase OSCILLATION_WINDOW to make detection a bit more forgiving
  local oldWin = TIMING.OSCILLATION_WINDOW
  TIMING.OSCILLATION_WINDOW = TIMING.OSCILLATION_WINDOW + 500
  table.insert(applied, string.format("OSCILLATION_WINDOW: %d -> %d", oldWin, TIMING.OSCILLATION_WINDOW))

  -- Print applied adjustments
  print("[MovementCoordinator][Tuning] Applied adjustments:")
  for _, a in ipairs(applied) do print("  - " .. a) end

  -- Record telemetry for applied tuning ops
  if nExBot and nExBot.Telemetry and nExBot.Telemetry.increment then
    nExBot.Telemetry.increment("movement.tuning.applied")
  end
end

-- Get current state for debugging
function MovementCoordinator.getState()
  return {
    intents = State.intents,
    lastDecision = State.lastDecision,
    recentMoves = #State.recentMoves,
    stats = State.stats
  }
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

nExBot = nExBot or {}
nExBot.MovementCoordinator = MovementCoordinator

if MovementCoordinator.DEBUG then print("[MovementCoordinator] Movement Coordinator v" .. MovementCoordinator.VERSION .. " loaded") end

-- Public API: whether movement should be allowed for TargetBot
function MovementCoordinator.canMove()
  -- Disallow movement when oscillating
  if MovementCoordinator.Decide.isOscillating() then
    return false
  end
  -- Also enforce execution cooldown to prevent command spam
  if now - MovementCoordinator.State.lastExecutionTime < TIMING.EXECUTION_COOLDOWN then
    return false
  end
  return true
end

nExBot.MovementCoordinator.canMove = MovementCoordinator.canMove
