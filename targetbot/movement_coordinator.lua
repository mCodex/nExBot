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
  
  -- Minimum confidence to execute movement (raised for smoother behavior)
  CONFIDENCE_THRESHOLDS = {
    [1] = 0.45,  -- EMERGENCY: Higher (avoid false emergencies)
    [2] = 0.70,  -- WAVE_AVOIDANCE: High (only move when really needed)
    [3] = 0.65,  -- FINISH_KILL: Medium-high
    [4] = 0.80,  -- SPELL_POSITION: Very high (rarely move for spells)
    [5] = 0.65,  -- KEEP_DISTANCE: Medium-high
    [6] = 0.75,  -- REPOSITION: High (stay put unless clearly better)
    [7] = 0.60,  -- CHASE: Medium
    [8] = 0.55,  -- FACE_MONSTER: Medium
    [9] = 0.60,  -- LURE: Medium
    [10] = 1.0   -- IDLE: Never execute
  },
  
  -- Timing (extended for smoother behavior)
  TIMING = {
    DECISION_COOLDOWN = 200,     -- Min time between decisions (ms)
    EXECUTION_COOLDOWN = 350,    -- Min time between movements (slower)
    INTENT_TTL = 400,            -- Intent valid for 400ms (shorter)
    OSCILLATION_WINDOW = 2500,   -- Track moves in this window (longer)
    MAX_OSCILLATIONS = 3,        -- Max moves before pause (stricter)
    HYSTERESIS_BONUS = 0.15,     -- Extra confidence needed to leave safe pos
    POSITION_MEMORY = 800        -- Remember safe position for 800ms
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
  lastUpdate = 0
}

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
      debounceUpdate()
    end
  end, 10)

  EventBus.on("creature:move", function(c, oldPos)
    if c and c:isMonster() and not c:isDead() then
      updateMonsterCacheFromCreature(c)
      debounceUpdate()
    end
  end, 10)

  EventBus.on("monster:disappear", function(c)
    removeCreatureFromCache(c)
    debounceUpdate()
  end, 10)
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
  local res = {}
  local p = player and player:getPosition()
  if not p then return res end
  for id, c in pairs(MovementCoordinator.MonsterCache.monsters) do
    if c and not c:isDead() then
      local pos = c:getPosition()
      if pos and math.max(math.abs(pos.x - p.x), math.abs(pos.y - p.y)) <= radius then
        table.insert(res, c)
      end
    end
  end
  return res
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
  
  -- Check if already at target
  if playerPos.x == targetPos.x and playerPos.y == targetPos.y then
    return false, "already_at_target"
  end
  
  -- Track this move for oscillation detection
  table.insert(State.recentMoves, {
    time = now,
    position = {x = targetPos.x, y = targetPos.y}
  })
  
  -- Execute the move
  local success = false
  
  -- Use appropriate movement method based on intent type
  if intent.type == INTENT.LURE then
    -- Delegate to CaveBot
    if TargetBot and TargetBot.allowCaveBot then
      TargetBot.allowCaveBot(150)
      success = true
    end
  elseif intent.type == INTENT.WAVE_AVOIDANCE or 
         intent.type == INTENT.EMERGENCY_ESCAPE then
    -- Quick movement for emergencies
    if TargetBot and TargetBot.walkTo then
      success = TargetBot.walkTo(targetPos, 2, {ignoreNonPathable = true, precision = 0})
    end
  else
    -- Standard movement
    if TargetBot and TargetBot.walkTo then
      success = TargetBot.walkTo(targetPos, 10, {ignoreNonPathable = true, precision = 1})
    elseif CaveBot and CaveBot.GoTo then
      success = CaveBot.GoTo(targetPos, 0)
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

-- Register emergency escape
function MovementCoordinator.emergencyEscape(escapePos, confidence)
  MovementCoordinator.Intent.register(
    INTENT.EMERGENCY_ESCAPE, escapePos, confidence, "emergency"
  )
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

print("[MovementCoordinator] Movement Coordinator v" .. MovementCoordinator.VERSION .. " loaded")

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
