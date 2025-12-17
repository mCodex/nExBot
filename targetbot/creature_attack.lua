--------------------------------------------------------------------------------
-- TARGETBOT CREATURE ATTACK v1.0
-- Uses TargetBotCore for shared pure functions (DRY, SRP)
-- Dynamic scaling based on monster count for better reactivity
--------------------------------------------------------------------------------

local targetBotLure = false
local targetCount = 0 
local delayValue = 0
local lureMax = 0
local anchorPosition = nil
local lastCall = now
local delayFrom = nil
local dynamicLureDelay = false

-- Use TargetCore if available (DRY - avoid duplicate implementations)
local Core = TargetCore or {}
local Geometry = Core.Geometry or {}

-- Pre-computed direction offsets (fallback if Core not available)
local DIRECTIONS = Geometry.DIRECTIONS or {
  {x = 0, y = -1},   -- North
  {x = 1, y = 0},    -- East  
  {x = 0, y = 1},    -- South
  {x = -1, y = 0},   -- West
  {x = 1, y = -1},   -- NorthEast
  {x = 1, y = 1},    -- SouthEast
  {x = -1, y = 1},   -- SouthWest
  {x = -1, y = -1}   -- NorthWest
}

-- Direction index to vector (monster facing)
local DIR_VECTORS = Geometry.DIR_VECTORS or {
  [0] = {x = 0, y = -1},  -- North
  [1] = {x = 1, y = 0},   -- East
  [2] = {x = 0, y = 1},   -- South
  [3] = {x = -1, y = 0},  -- West
  [4] = {x = 1, y = -1},  -- NorthEast
  [5] = {x = 1, y = 1},   -- SouthEast
  [6] = {x = -1, y = 1},  -- SouthWest
  [7] = {x = -1, y = -1}  -- NorthWest
}

--------------------------------------------------------------------------------
-- IMPROVED WAVE AVOIDANCE SYSTEM
-- 
-- Uses TargetBotCore pure functions and improved scoring algorithm.
-- Key improvements:
-- 1. Dynamic scaling based on monster count (more reactive when surrounded)
-- 2. Better front arc detection with configurable width
-- 3. Multi-factor safe tile scoring
-- 4. Balanced anti-oscillation (not too sticky when danger is high)
-- 5. Adaptive thresholds based on threat level
--------------------------------------------------------------------------------

-- Avoidance state (prevents oscillation)
local avoidanceState = {
  lastMove = 0,
  baseCooldown = 350,      -- Base cooldown (scales down with more monsters)
  lastSafePos = nil,
  baseStickiness = 600,    -- Base stickiness (scales down with danger)
  consecutiveMoves = 0,    -- Track consecutive avoidance moves
  maxConsecutive = 3,      -- Increased back (was 2, too restrictive)
  baseDangerThreshold = 1.5, -- Base danger threshold (scales with monster count)
  lastMonsterCount = 0     -- Track monster count for scaling
}

-- Pure function: Calculate dynamic scaling factor based on monster count
-- More monsters = more reactive (lower thresholds, shorter cooldowns)
-- @param monsterCount: number of nearby monsters
-- @return table with scaling factors
local function calculateScaling(monsterCount)
  -- Scale from 1.0 (few monsters) to 0.4 (many monsters)
  -- 1-2 monsters: full conservative behavior
  -- 3-4 monsters: moderate reactivity  
  -- 5-6 monsters: high reactivity
  -- 7+ monsters: maximum reactivity
  local reactivityScale = 1.0
  if monsterCount >= 7 then
    reactivityScale = 0.4
  elseif monsterCount >= 5 then
    reactivityScale = 0.55
  elseif monsterCount >= 3 then
    reactivityScale = 0.75
  end
  
  return {
    -- Cooldown and stickiness scale DOWN (faster reactions when surrounded)
    cooldownMultiplier = reactivityScale,
    stickinessMultiplier = reactivityScale,
    -- Danger threshold scales DOWN (more willing to move when surrounded)
    dangerThresholdMultiplier = reactivityScale,
    -- Score threshold scales DOWN (accept smaller improvements when surrounded)
    scoreThresholdMultiplier = reactivityScale,
    -- Monster count for reference
    monsterCount = monsterCount
  }
end

-- Pure function: Check if position is in front of a monster (in its attack arc)
-- Improved with configurable arc width and better edge detection
-- @param pos: position to check {x, y, z}
-- @param monsterPos: monster position {x, y, z}
-- @param monsterDir: monster direction (0-7)
-- @param range: how far the attack reaches (default 5)
-- @param arcWidth: how wide the arc is (default 1 tile on each side)
-- @return boolean, number (isInArc, distanceToCenter)
local function isInFrontArc(pos, monsterPos, monsterDir, range, arcWidth)
  range = range or 5
  arcWidth = arcWidth or 1
  
  local dirVec = DIR_VECTORS[monsterDir]
  if not dirVec then return false, 99 end
  
  local dx = pos.x - monsterPos.x
  local dy = pos.y - monsterPos.y
  
  -- Use Chebyshev distance for game tiles
  local dist = math.max(math.abs(dx), math.abs(dy))
  if dist == 0 or dist > range then
    return false, dist
  end
  
  -- Calculate distance from center of attack line
  local distFromCenter
  
  if dirVec.x == 0 then
    -- North or South: check vertical alignment
    local inDirection = (dy * dirVec.y) > 0
    distFromCenter = math.abs(dx)
    return inDirection and distFromCenter <= arcWidth, distFromCenter
  elseif dirVec.y == 0 then
    -- East or West: check horizontal alignment
    local inDirection = (dx * dirVec.x) > 0
    distFromCenter = math.abs(dy)
    return inDirection and distFromCenter <= arcWidth, distFromCenter
  else
    -- Diagonal: check if in the quadrant cone
    local inX = (dirVec.x > 0 and dx > 0) or (dirVec.x < 0 and dx < 0)
    local inY = (dirVec.y > 0 and dy > 0) or (dirVec.y < 0 and dy < 0)
    -- For diagonals, use the perpendicular distance from the diagonal line
    distFromCenter = math.abs(dx - dy) / 2
    return inX and inY, distFromCenter
  end
end

-- Pure function: Score a position's danger level
-- Returns detailed danger analysis for better decision making
-- @param pos: position to check
-- @param monsters: array of monster creatures
-- @return table {totalDanger, waveThreats, meleeThreats, details}
local function analyzePositionDanger(pos, monsters)
  local result = {
    totalDanger = 0,
    waveThreats = 0,
    meleeThreats = 0,
    details = {}
  }
  
  for i = 1, #monsters do
    local monster = monsters[i]
    if monster and not monster:isDead() then
      local mpos = monster:getPosition()
      local mdir = monster:getDirection()
      local dist = math.max(math.abs(pos.x - mpos.x), math.abs(pos.y - mpos.y))
      
      local threat = {
        monster = monster,
        distance = dist,
        inWaveArc = false,
        arcDistance = 99
      }
      
      -- Check wave attack danger
      local inArc, arcDist = isInFrontArc(pos, mpos, mdir, 5, 1)
      if inArc then
        threat.inWaveArc = true
        threat.arcDistance = arcDist
        result.waveThreats = result.waveThreats + 1
        -- Closer to center of arc = more dangerous
        result.totalDanger = result.totalDanger + (3 - arcDist)
      end
      
      -- Check melee danger
      if dist == 1 then
        result.meleeThreats = result.meleeThreats + 1
        result.totalDanger = result.totalDanger + 2
      elseif dist == 2 then
        result.totalDanger = result.totalDanger + 0.5
      end
      
      result.details[#result.details + 1] = threat
    end
  end
  
  return result
end

-- Pure function: Check if a position is dangerous (simplified wrapper)
-- @param pos: position to check
-- @param monsters: array of monster creatures
-- @return boolean, number (isDangerous, dangerCount)
local function isDangerousPosition(pos, monsters)
  local analysis = analyzePositionDanger(pos, monsters)
  return analysis.totalDanger > 0, analysis.waveThreats + analysis.meleeThreats
end

-- Pure function: Find the safest adjacent tile with improved scoring
-- Uses multi-factor scoring: danger, target distance, escape routes, stability
-- @param playerPos: current player position
-- @param monsters: array of monsters
-- @param currentTarget: current attack target (to maintain range)
-- @param scaling: scaling factors from calculateScaling() (optional, defaults to conservative)
-- @return position or nil, score
local function findSafeAdjacentTile(playerPos, monsters, currentTarget, scaling)
  local candidates = {}
  local currentAnalysis = analyzePositionDanger(playerPos, monsters)
  
  -- Default scaling if not provided (conservative behavior)
  scaling = scaling or calculateScaling(#monsters)
  
  -- Dynamic danger threshold based on monster count
  local dynamicDangerThreshold = avoidanceState.baseDangerThreshold * scaling.dangerThresholdMultiplier
  
  -- When many monsters (7+), any danger is concerning
  -- When few monsters (1-2), need more danger to trigger movement
  if currentAnalysis.totalDanger < dynamicDangerThreshold then
    return nil, 0
  end
  
  -- Score weights for decision making (SRP: separated concerns)
  -- Same weights, but threshold for movement is dynamic
  local WEIGHTS = {
    DANGER = -25,        -- Penalize danger heavily
    TARGET_ADJACENT = 20,-- Bonus for being adjacent to target
    TARGET_CLOSE = 10,   -- Bonus for being close to target
    TARGET_FAR = -5,     -- Penalty per tile beyond range 3
    ESCAPE_ROUTES = 4,   -- Bonus per escape route
    STABILITY = 8,       -- Bonus for not being in any wave arc
    PREVIOUS_SAFE = 15,  -- Bonus for returning to previous safe position
    STAY_BONUS = 10      -- Bonus for current position (prefer staying)
  }
  
  -- Check all adjacent tiles (8 directions)
  for i = 1, 8 do
    local dir = DIRECTIONS[i]
    local checkPos = {
      x = playerPos.x + dir.x,
      y = playerPos.y + dir.y,
      z = playerPos.z
    }
    
    local tile = g_map.getTile(checkPos)
    if tile and tile:isWalkable() and not tile:hasCreature() then
      local analysis = analyzePositionDanger(checkPos, monsters)
      local score = 0
      
      -- Factor 1: Danger level (most important)
      score = score + analysis.totalDanger * WEIGHTS.DANGER
      
      -- Factor 2: Stability bonus (no wave threats at all)
      if analysis.waveThreats == 0 then
        score = score + WEIGHTS.STABILITY
      end
      
      -- Factor 3: Distance to current target
      if currentTarget then
        local tpos = currentTarget:getPosition()
        local targetDist = math.max(math.abs(checkPos.x - tpos.x), math.abs(checkPos.y - tpos.y))
        if targetDist <= 1 then
          score = score + WEIGHTS.TARGET_ADJACENT
        elseif targetDist <= 3 then
          score = score + WEIGHTS.TARGET_CLOSE
        else
          score = score + (targetDist - 3) * WEIGHTS.TARGET_FAR
        end
      end
      
      -- Factor 4: Escape routes (walkable adjacent tiles)
      local escapeRoutes = 0
      for j = 1, 8 do
        local escapeDir = DIRECTIONS[j]
        local escapePos = {
          x = checkPos.x + escapeDir.x,
          y = checkPos.y + escapeDir.y,
          z = checkPos.z
        }
        local escapeTile = g_map.getTile(escapePos)
        if escapeTile and escapeTile:isWalkable() then
          escapeRoutes = escapeRoutes + 1
        end
      end
      score = score + escapeRoutes * WEIGHTS.ESCAPE_ROUTES
      
      -- Factor 5: Previous safe position bonus (reduces oscillation)
      if avoidanceState.lastSafePos then
        local isPreviousSafe = checkPos.x == avoidanceState.lastSafePos.x and 
                               checkPos.y == avoidanceState.lastSafePos.y
        if isPreviousSafe then
          score = score + WEIGHTS.PREVIOUS_SAFE
        end
      end
      
      candidates[#candidates + 1] = {
        pos = checkPos,
        score = score,
        danger = analysis.totalDanger,
        waveThreats = analysis.waveThreats
      }
    end
  end
  
  if #candidates == 0 then
    return nil, 0
  end
  
  -- Sort by score (highest first)
  table.sort(candidates, function(a, b)
    return a.score > b.score
  end)
  
  -- Return best candidate if it's significantly safer than current position
  -- Score threshold scales with monster count
  local best = candidates[1]
  local currentScore = currentAnalysis.totalDanger * WEIGHTS.DANGER + WEIGHTS.STAY_BONUS
  
  -- Base threshold of 12 points, scales down when many monsters
  -- 7+ monsters: threshold = 12 * 0.4 = 4.8 (very willing to move)
  -- 3-4 monsters: threshold = 12 * 0.75 = 9 (moderate)
  -- 1-2 monsters: threshold = 12 * 1.0 = 12 (conservative)
  local baseScoreThreshold = 12
  local dynamicScoreThreshold = baseScoreThreshold * scaling.scoreThresholdMultiplier
  
  if best.score > currentScore + dynamicScoreThreshold then
    return best.pos, best.score
  end
  
  return nil, 0
end

-- Main avoidance function (called from walk logic)
-- Dynamic scaling based on monster count
-- More monsters = faster reactions, lower thresholds
-- @return boolean: true if avoidance move was initiated
local function avoidWaveAttacks()
  local currentTime = now
  
  -- Get monsters in range FIRST (needed for scaling)
  local playerPos = player:getPosition()
  local creatures = g_map.getSpectatorsInRange(playerPos, false, 7, 7)
  local monsters = {}
  
  for i = 1, #creatures do
    local c = creatures[i]
    if c:isMonster() and not c:isDead() then
      monsters[#monsters + 1] = c
    end
  end
  
  local monsterCount = #monsters
  
  if monsterCount == 0 then
    avoidanceState.consecutiveMoves = 0
    avoidanceState.lastSafePos = nil
    avoidanceState.lastMonsterCount = 0
    return false
  end
  
  -- Calculate dynamic scaling based on monster count
  local scaling = calculateScaling(monsterCount)
  avoidanceState.lastMonsterCount = monsterCount
  
  -- Dynamic cooldown: faster when surrounded
  -- 7+ monsters: 350 * 0.4 = 140ms (fast reactions)
  -- 3-4 monsters: 350 * 0.75 = 262ms (moderate)
  -- 1-2 monsters: 350 * 1.0 = 350ms (conservative)
  local dynamicCooldown = avoidanceState.baseCooldown * scaling.cooldownMultiplier
  
  -- Anti-oscillation: check consecutive moves
  -- Allow more consecutive moves when surrounded (danger is real)
  local maxConsecutive = avoidanceState.maxConsecutive
  if monsterCount >= 5 then
    maxConsecutive = maxConsecutive + 1  -- Allow 4 moves when heavily surrounded
  end
  
  if avoidanceState.consecutiveMoves >= maxConsecutive then
    -- Too many consecutive avoidance moves - take a break
    -- But shorter break when many monsters (danger is real)
    local pauseDuration = 1200 * scaling.cooldownMultiplier  -- 480ms-1200ms
    if currentTime - avoidanceState.lastMove < pauseDuration then
      return false
    end
    avoidanceState.consecutiveMoves = 0
  end
  
  -- Cooldown check (dynamic)
  if currentTime - avoidanceState.lastMove < dynamicCooldown then
    return false
  end
  
  -- Dynamic stickiness: shorter when many monsters
  -- 7+ monsters: 600 * 0.4 = 240ms (don't stay still long)
  -- 1-2 monsters: 600 * 1.0 = 600ms (stay at safe spots)
  local dynamicStickiness = avoidanceState.baseStickiness * scaling.stickinessMultiplier
  
  if avoidanceState.lastSafePos then
    local atSafePos = playerPos.x == avoidanceState.lastSafePos.x and 
                      playerPos.y == avoidanceState.lastSafePos.y
    
    if atSafePos and currentTime - avoidanceState.lastMove < dynamicStickiness then
      -- We're at a safe position and within stickiness window
      -- Check if danger has increased (new threats)
      local analysis = analyzePositionDanger(playerPos, monsters)
      -- Dynamic threshold to leave safe position
      local leaveThreshold = avoidanceState.baseDangerThreshold * scaling.dangerThresholdMultiplier + 0.5
      if analysis.totalDanger < leaveThreshold then
        return false  -- Still safe enough, don't move
      end
      -- Danger increased significantly, allow movement despite stickiness
    end
  end
  
  -- Find safe tile with dynamic thresholds
  local currentTarget = target()
  local safePos, score = findSafeAdjacentTile(playerPos, monsters, currentTarget, scaling)
  
  if safePos then
    avoidanceState.lastMove = currentTime
    avoidanceState.lastSafePos = safePos
    avoidanceState.consecutiveMoves = avoidanceState.consecutiveMoves + 1
    TargetBot.walkTo(safePos, 2, {ignoreNonPathable = true, precision = 0})
    return true
  end
  
  -- No safe tile found, but we tried - reset consecutive counter
  avoidanceState.consecutiveMoves = 0
  return false
end

-- EventBus integration: Reset avoidance state when monsters change
if EventBus then
  EventBus.on("monster:disappear", function(creature)
    avoidanceState.lastSafePos = nil
    avoidanceState.consecutiveMoves = 0
  end, 20)
  
  EventBus.on("player:move", function(newPos, oldPos)
    -- Reset stickiness when player moves away from safe position
    if avoidanceState.lastSafePos then
      local atSafe = newPos.x == avoidanceState.lastSafePos.x and
                     newPos.y == avoidanceState.lastSafePos.y
      if not atSafe then
        avoidanceState.lastSafePos = nil
      end
    end
  end, 20)
end

-- Export functions for external use
nExBot.avoidWaveAttacks = avoidWaveAttacks
nExBot.isInFrontArc = isInFrontArc
nExBot.isDangerousPosition = isDangerousPosition
nExBot.analyzePositionDanger = analyzePositionDanger
nExBot.findSafeAdjacentTile = findSafeAdjacentTile

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS (Optimized with TargetBotCore integration)
--------------------------------------------------------------------------------

-- Pure function: Count walkable tiles around a position
-- Uses TargetBotCore.Geometry if available
-- @param position: center position
-- @return number
local function countWalkableTiles(position)
  local count = 0
  
  for i = 1, 8 do
    local dir = DIRECTIONS[i]
    local checkPos = {
      x = position.x + dir.x,
      y = position.y + dir.y,
      z = position.z
    }
    local tile = g_map.getTile(checkPos)
    if tile and tile:isWalkable() then
      count = count + 1
    end
  end
  
  return count
end

-- Pure function: Check if player is trapped (no walkable adjacent tiles)
-- @param playerPos: player position
-- @return boolean
local function isPlayerTrapped(playerPos)
  return countWalkableTiles(playerPos) == 0
end

-- Reposition to tile with more escape routes and better tactical position
-- Conservative movement algorithm
-- @param minTiles: minimum walkable tiles threshold
-- @param config: creature config for context (includes anchor settings)
local function rePosition(minTiles, config)
  minTiles = minTiles or 6
  
  -- Extended cooldown to prevent jitter (was 350)
  if now - lastCall < 500 then return end
  
  local playerPos = player:getPosition()
  local currentWalkable = countWalkableTiles(playerPos)
  
  -- Don't reposition if we have enough space
  if currentWalkable >= minTiles then return end
  
  -- Get nearby monsters for scoring
  local creatures = g_map.getSpectatorsInRange(playerPos, false, 5, 5)
  local monsters = {}
  for i = 1, #creatures do
    local c = creatures[i]
    if c:isMonster() and not c:isDead() then
      monsters[#monsters + 1] = c
    end
  end
  
  local currentTarget = target()
  local bestPos = nil
  local bestScore = -9999
  
  -- Get anchor constraints
  local anchorPos = config and config.anchor and anchorPosition
  local anchorRange = config and config.anchorRange or 5
  
  -- Score weights (conservative tuning)
  local WEIGHTS = {
    WALKABLE = 15,      -- Per walkable tile (was 12)
    DANGER = -22,       -- Per danger point (was -18)
    TARGET_ADJ = 20,    -- Adjacent to target (was 25)
    TARGET_CLOSE = 10,  -- Within 3 tiles (was 12)
    TARGET_FAR = -4,    -- Per tile beyond 3 (was -3)
    MOVE_COST = -4,     -- Per movement tile (was -2)
    CARDINAL = 3,       -- Bonus for cardinal movement (was 4)
    STAY_BONUS = 15     -- Bonus for not moving
  }
  
  -- Search in a 2-tile radius for better positions
  for dx = -2, 2 do
    for dy = -2, 2 do
      if dx ~= 0 or dy ~= 0 then
        local checkPos = {
          x = playerPos.x + dx,
          y = playerPos.y + dy,
          z = playerPos.z
        }
        
        local shouldSkip = false
        
        -- Check anchor constraint FIRST (skip if violates anchor)
        if anchorPos then
          local anchorDist = math.max(
            math.abs(checkPos.x - anchorPos.x),
            math.abs(checkPos.y - anchorPos.y)
          )
          if anchorDist > anchorRange then
            shouldSkip = true  -- Skip this position, violates anchor
          end
        end
        
        if not shouldSkip then
          local tile = g_map.getTile(checkPos)
          if tile and tile:isWalkable() and not tile:hasCreature() then
            -- Score this position using improved danger analysis
            local score = 0
            
            -- Factor 1: Walkable tiles (escape routes)
            local walkable = countWalkableTiles(checkPos)
            score = score + walkable * WEIGHTS.WALKABLE
            
            -- Factor 2: Danger analysis (uses improved analyzePositionDanger)
            local analysis = analyzePositionDanger(checkPos, monsters)
            score = score + analysis.totalDanger * WEIGHTS.DANGER
            
            -- Factor 3: Distance to current target
            if currentTarget then
              local tpos = currentTarget:getPosition()
              local targetDist = math.max(math.abs(checkPos.x - tpos.x), math.abs(checkPos.y - tpos.y))
              if targetDist <= 1 then
                score = score + WEIGHTS.TARGET_ADJ
              elseif targetDist <= 3 then
                score = score + WEIGHTS.TARGET_CLOSE
              else
                score = score + (targetDist - 3) * WEIGHTS.TARGET_FAR
              end
            end
            
            -- Factor 4: Movement cost
            local moveDist = math.abs(dx) + math.abs(dy)
            score = score + moveDist * WEIGHTS.MOVE_COST
            
            -- Factor 5: Cardinal direction bonus
            if dx == 0 or dy == 0 then
              score = score + WEIGHTS.CARDINAL
            end
            
            if score > bestScore then
              bestScore = score
              bestPos = checkPos
            end
          end
        end
      end
    end
  end
  
  -- Only move if we found a significantly better position (was +8)
  local currentScore = currentWalkable * WEIGHTS.WALKABLE + WEIGHTS.STAY_BONUS
  if bestPos and bestScore > currentScore + 20 then
    lastCall = now
    return CaveBot.GoTo(bestPos, 0)
  end
end

TargetBot.Creature.attack = function(params, targets, isLooting)
  if player:isWalking() then
    lastWalk = now
  end

  local config = params.config
  local creature = params.creature
  
  -- Cache attacking creature check
  local currentTarget = g_game.getAttackingCreature()
  if currentTarget ~= creature then
    g_game.attack(creature)
  end

  if not isLooting then
    TargetBot.Creature.walk(creature, config, targets)
  end

  -- Cache mana check
  local mana = player:getMana()
  local playerPos = player:getPosition()
  
  -- Group attack spell check
  if config.useGroupAttack and config.groupAttackSpell:len() > 1 and mana > config.minManaGroup then
    local creatures = g_map.getSpectatorsInRange(playerPos, false, config.groupAttackRadius, config.groupAttackRadius)
    local playersAround = false
    local monsters = 0
    
    for i = 1, #creatures do
      local c = creatures[i]
      if c:isPlayer() and not c:isLocalPlayer() then
        if not config.groupAttackIgnoreParty or c:getShield() <= 2 then
          playersAround = true
        end
      elseif c:isMonster() then
        monsters = monsters + 1
      end
    end
    
    if monsters >= config.groupAttackTargets and (not playersAround or config.groupAttackIgnorePlayers) then
      if TargetBot.sayAttackSpell(config.groupAttackSpell, config.groupAttackDelay) then
        return
      end
    end
  end

  -- Group attack rune check
  if config.useGroupAttackRune and config.groupAttackRune > 100 then
    local creaturePos = creature:getPosition()
    local creatures = g_map.getSpectatorsInRange(creaturePos, false, config.groupRuneAttackRadius, config.groupRuneAttackRadius)
    local playersAround = false
    local monsters = 0
    
    for i = 1, #creatures do
      local c = creatures[i]
      if c:isPlayer() and not c:isLocalPlayer() then
        if not config.groupAttackIgnoreParty or c:getShield() <= 2 then
          playersAround = true
        end
      elseif c:isMonster() then
        monsters = monsters + 1
      end
    end
    
    if monsters >= config.groupRuneAttackTargets and (not playersAround or config.groupAttackIgnorePlayers) then
      if TargetBot.useAttackItem(config.groupAttackRune, 0, creature, config.groupRuneAttackDelay) then
        return
      end
    end
  end
  
  -- Single target spell attack
  if config.useSpellAttack and config.attackSpell:len() > 1 and mana > config.minMana then
    if TargetBot.sayAttackSpell(config.attackSpell, config.attackSpellDelay) then
      return
    end
  end
  
  -- Single target rune attack
  if config.useRuneAttack and config.attackRune > 100 then
    if TargetBot.useAttackItem(config.attackRune, 0, creature, config.attackRuneDelay) then
      return
    end
  end
end

TargetBot.Creature.walk = function(creature, config, targets)
  local cpos = creature:getPosition()
  local pos = player:getPosition()
  
  --[[
    ═══════════════════════════════════════════════════════════════════════════
    TARGETBOT UNIFIED MOVEMENT SYSTEM v3
    ═══════════════════════════════════════════════════════════════════════════
    
    All features work together with clear priority and mutual awareness.
    
    PHASE 1: CONTEXT GATHERING
    - Collect all relevant state: health, distance, monsters, traps, etc.
    
    PHASE 2: LURE DECISIONS (CaveBot delegation)
    - smartPull, dynamicLure, closeLure
    - Only if target is NOT low health
    - Only if NOT trapped
    
    PHASE 3: MOVEMENT PRIORITY
    1. SAFETY: avoidAttacks (wave avoidance)
    2. SURVIVAL: Chase low-health targets (ignore other settings)
    3. DISTANCE: keepDistance (ranged positioning)
    4. TACTICAL: rePosition (better tile when cornered)
    5. MELEE: chase (close the gap)
    6. FACING: faceMonster (diagonal correction)
    
    INTEGRATIONS:
    - anchor is respected by keepDistance AND rePosition
    - avoidAttacks considers target distance
    - rePosition considers danger zones from monsters
    - All lure features respect killUnder threshold
  ]]
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- PHASE 1: CONTEXT GATHERING
  -- ═══════════════════════════════════════════════════════════════════════════
  
  local creatureHealth = creature:getHealthPercent()
  local killUnder = storage.extras.killUnder or 30
  local targetIsLowHealth = creatureHealth < killUnder
  local isTrapped = isPlayerTrapped(pos)
  
  -- Calculate path distance to creature
  local path = findPath(pos, cpos, 10, {ignoreCreatures = true, ignoreNonPathable = true, ignoreCost = true})
  local pathLen = path and #path or 0
  
  -- Count nearby monsters for lure decisions
  local nearbyMonsterCount = targets  -- Use passed target count
  
  -- Anchor position management (used by keepDistance and rePosition)
  if config.anchor then
    if not anchorPosition or distanceFromPlayer(anchorPosition) > (config.anchorRange or 5) * 2 then
      anchorPosition = pos  -- Set new anchor
    end
  else
    anchorPosition = nil  -- Clear anchor if disabled
  end
  
  -- External data for dynamic lure delay system
  if config.lureMin and config.lureMax and config.dynamicLure then
    targetBotLure = config.lureMin >= targets
    if targets >= config.lureMax then
      targetBotLure = false
    end
  end
  targetCount = targets
  delayValue = config.lureDelay
  lureMax = config.lureMax or 0
  dynamicLureDelay = config.dynamicLureDelay
  delayFrom = config.delayFrom

  -- ═══════════════════════════════════════════════════════════════════════════
  -- PHASE 2: LURE DECISIONS (CaveBot delegation)
  -- These all delegate to CaveBot and return early
  -- Never trigger if target has low health
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if not targetIsLowHealth and not isTrapped then
    -- Pull System: Pause CaveBot when monster pack is too small but we have targets
    -- This prevents running to next waypoint and losing the respawn
    if config.smartPull then
      -- SAFEGUARD: Only try to pull if there are ANY monsters on screen
      -- No point in pausing waypoints if there's nothing to fight
      local screenMonsters = getMonsters(7)  -- Check entire visible range first
      if screenMonsters == 0 then
        -- No monsters on screen - don't activate pull system, let CaveBot work
        TargetBot.smartPullActive = false
      else
        local pullRange = config.smartPullRange or 2
        local pullMin = config.smartPullMin or 3
        local pullShape = config.smartPullShape or (nExBot.SHAPE and nExBot.SHAPE.CIRCLE) or 2
        
        local nearbyMonsters
        if getMonstersAdvanced then
          nearbyMonsters = getMonstersAdvanced(pullRange, pullShape)
        else
          nearbyMonsters = getMonsters(pullRange)
        end
        
        -- If we have fewer monsters than minimum, PAUSE waypoint movement
        -- but keep attacking current targets (don't walk to next waypoint!)
        if nearbyMonsters < pullMin then
          -- Signal to CaveBot that smartPull is active (pause waypoints)
          -- But DON'T call allowCaveBot - we want to FIGHT, not walk away
          TargetBot.smartPullActive = true
        
          -- Stay here and fight - don't walk to waypoint
          -- Return nil to continue with normal attack/positioning below
        else
          -- Enough monsters - clear the pause
          TargetBot.smartPullActive = false
        end
      end  -- end screenMonsters check
    else
      TargetBot.smartPullActive = false
    end
    
    -- Dynamic lure: Pull more monsters when target count is low
    -- Only trigger if smartPull is not pausing us
    if not TargetBot.smartPullActive and TargetBot.canLure() and config.dynamicLure then
      if targetBotLure then
        return TargetBot.allowCaveBot(150)
      end
    end
    
    -- Legacy closeLure support
    if config.closeLure and config.closeLureAmount then
      if getMonsters(1) >= config.closeLureAmount then
        return TargetBot.allowCaveBot(150)
      end
    end
  else
    TargetBot.smartPullActive = false
  end

  -- ═══════════════════════════════════════════════════════════════════════════
  -- PHASE 3: COORDINATED MOVEMENT SYSTEM
  -- 
  -- Uses MovementCoordinator for unified decision making.
  -- Each system registers its intent with confidence score.
  -- Coordinator aggregates, resolves conflicts, and executes best decision.
  -- ═══════════════════════════════════════════════════════════════════════════
  
  -- Check if MovementCoordinator is available
  local useCoordinator = MovementCoordinator and MovementCoordinator.Intent
  
  -- Get nearby monsters for danger analysis
  local creatures = g_map.getSpectatorsInRange(pos, false, 7, 7)
  local monsters = {}
  for i = 1, #creatures do
    local c = creatures[i]
    if c:isMonster() and not c:isDead() then
      monsters[#monsters + 1] = c
    end
  end
  
  -- Update MonsterAI tracking if available
  if MonsterAI and MonsterAI.updateAll then
    MonsterAI.updateAll()
  end

  -- ─────────────────────────────────────────────────────────────────────────
  -- INTENT 1: WAVE AVOIDANCE (Highest priority movement)
  -- Higher base confidence, only move when really needed
  -- ─────────────────────────────────────────────────────────────────────────
  if config.avoidAttacks then
    local safePos, safeScore = findSafeAdjacentTile(pos, monsters, creature)
    
    if safePos then
      -- Calculate confidence based on danger analysis
      -- Start with higher base, require real danger
      local confidence = 0.5  -- Base confidence (lower than threshold)
      
      -- Analyze current danger
      local currentDanger = analyzePositionDanger(pos, monsters)
      
      -- Only boost confidence if we're actually in danger
      if currentDanger.waveThreats >= 2 then
        confidence = 0.85  -- Multiple wave threats = high confidence
      elseif currentDanger.waveThreats == 1 and currentDanger.meleeThreats >= 2 then
        confidence = 0.80  -- Wave + melee = high confidence
      elseif currentDanger.totalDanger >= 4 then
        confidence = 0.75  -- High total danger
      elseif currentDanger.totalDanger >= 2 then
        confidence = 0.70  -- Moderate danger (meets threshold)
      end
      
      if useCoordinator then
        MovementCoordinator.avoidWave(safePos, confidence)
      else
        -- Fallback: direct execution with confidence check
        if confidence >= 0.70 then
          avoidWaveAttacks()
          return true
        end
      end
    end
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- INTENT 2: FINISH KILL (High priority - chase wounded targets)
  -- Higher thresholds, only for very low HP targets
  -- ─────────────────────────────────────────────────────────────────────────
  if targetIsLowHealth and pathLen > 1 then
    local confidence = 0.55  -- Base (below threshold)
    
    -- Only high confidence for very low HP targets
    if creatureHealth < 10 then
      confidence = 0.85  -- Critical HP
    elseif creatureHealth < 15 then
      confidence = 0.75  -- Very low HP
    elseif creatureHealth < 20 then
      confidence = 0.70  -- Low HP (meets threshold)
    end
    
    if useCoordinator then
      MovementCoordinator.finishKill(cpos, confidence)
    else
      -- Fallback: direct execution only for critical targets
      if confidence >= 0.70 then
        return TargetBot.walkTo(cpos, 10, {ignoreNonPathable = true, precision = 1})
      end
    end
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- INTENT 3: SPELL POSITION OPTIMIZATION
  -- Position for maximum AoE damage (if SpellOptimizer available)
  -- ─────────────────────────────────────────────────────────────────────────
  if SpellOptimizer and config.optimizeSpellPosition and #monsters >= 2 then
    -- Get configured spell shape from config (default to adjacent)
    local spellShape = config.spellShape or SpellOptimizer.CONSTANTS.SHAPE.ADJACENT
    
    local optPos, score, confidence, details = SpellOptimizer.findOptimalPosition(
      spellShape, monsters, { minMonsters = 2, avoidDanger = config.avoidAttacks }
    )
    
    if optPos and details and details.monstersHit >= 2 then
      -- Only suggest movement if significantly better than current
      if details.distance > 0 and confidence >= 0.6 then
        if useCoordinator then
          MovementCoordinator.positionForSpell(optPos, confidence, "AoE")
        end
      end
    end
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- INTENT 4: KEEP DISTANCE (Ranged combat positioning)
  -- ─────────────────────────────────────────────────────────────────────────
  if config.keepDistance then
    local keepRange = config.keepDistanceRange or 4
    local currentDist = pathLen
    
    if currentDist ~= keepRange and currentDist ~= keepRange + 1 then
      -- Calculate position at correct distance
      local dx = cpos.x - pos.x
      local dy = cpos.y - pos.y
      local dist = math.sqrt(dx * dx + dy * dy)
      
      if dist > 0 then
        local targetDist = keepRange
        local ratio = targetDist / dist
        local keepPos = {
          x = math.floor(cpos.x - dx * ratio + 0.5),
          y = math.floor(cpos.y - dy * ratio + 0.5),
          z = pos.z
        }
        
        -- Check anchor constraint
        local anchorValid = true
        if config.anchor and anchorPosition then
          local anchorDist = math.max(
            math.abs(keepPos.x - anchorPosition.x),
            math.abs(keepPos.y - anchorPosition.y)
          )
          anchorValid = anchorDist <= (config.anchorRange or 5)
        end
        
        if anchorValid then
          local confidence = 0.55
          -- Higher confidence if too close (dangerous)
          if currentDist < keepRange then
            confidence = 0.7
          end
          
          if useCoordinator then
            MovementCoordinator.keepDistance(keepPos, confidence)
          else
            local walkParams = {
              ignoreNonPathable = true,
              marginMin = keepRange,
              marginMax = keepRange + 1
            }
            if config.anchor and anchorPosition then
              walkParams.maxDistanceFrom = {anchorPosition, config.anchorRange or 5}
            end
            return TargetBot.walkTo(cpos, 10, walkParams)
          end
        end
      end
    end
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- INTENT 5: REPOSITION (Better tactical tile)
  -- ─────────────────────────────────────────────────────────────────────────
  if config.rePosition and not isTrapped then
    local currentWalkable = countWalkableTiles(pos)
    local threshold = config.rePositionAmount or 5
    
    if currentWalkable < threshold then
      -- Find better position
      local betterPos = nil
      local bestScore = currentWalkable * 12  -- Current score
      
      -- Search nearby tiles
      for dx = -2, 2 do
        for dy = -2, 2 do
          if dx ~= 0 or dy ~= 0 then
            local checkPos = {x = pos.x + dx, y = pos.y + dy, z = pos.z}
            local tile = g_map.getTile(checkPos)
            
            if tile and tile:isWalkable() and not tile:hasCreature() then
              -- Check anchor
              local anchorValid = true
              if config.anchor and anchorPosition then
                local anchorDist = math.max(
                  math.abs(checkPos.x - anchorPosition.x),
                  math.abs(checkPos.y - anchorPosition.y)
                )
                anchorValid = anchorDist <= (config.anchorRange or 5)
              end
              
              if anchorValid then
                local walkable = countWalkableTiles(checkPos)
                local score = walkable * 12
                
                -- Penalty for danger
                local analysis = analyzePositionDanger(checkPos, monsters)
                score = score - analysis.totalDanger * 15
                
                if score > bestScore + 10 then
                  bestScore = score
                  betterPos = checkPos
                end
              end
            end
          end
        end
      end
      
      if betterPos then
        local confidence = math.min(0.4 + (bestScore - currentWalkable * 12) / 100, 0.75)
        
        if useCoordinator then
          MovementCoordinator.reposition(betterPos, confidence)
        else
          if confidence >= 0.5 then
            return CaveBot.GoTo(betterPos, 0)
          end
        end
      end
    end
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- INTENT 6: CHASE (Close gap to target)
  -- ─────────────────────────────────────────────────────────────────────────
  if config.chase and not config.keepDistance and pathLen > 1 then
    local confidence = 0.5
    
    -- Higher confidence for closer targets (easier to reach)
    if pathLen <= 3 then
      confidence = 0.65
    end
    
    -- Check anchor constraint
    local anchorValid = true
    if config.anchor and anchorPosition then
      local anchorDist = math.max(
        math.abs(cpos.x - anchorPosition.x),
        math.abs(cpos.y - anchorPosition.y)
      )
      anchorValid = anchorDist <= (config.anchorRange or 5)
    end
    
    if anchorValid then
      if useCoordinator then
        MovementCoordinator.chase(cpos, confidence)
      else
        local walkParams = {ignoreNonPathable = true, precision = 1}
        if config.anchor and anchorPosition then
          walkParams.maxDistanceFrom = {anchorPosition, config.anchorRange or 5}
        end
        return TargetBot.walkTo(cpos, 10, walkParams)
      end
    end
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- INTENT 7: FACE MONSTER (Diagonal correction)
  -- ─────────────────────────────────────────────────────────────────────────
  if config.faceMonster then
    local dx = cpos.x - pos.x
    local dy = cpos.y - pos.y
    local dist = math.max(math.abs(dx), math.abs(dy))
    
    if dist == 1 and math.abs(dx) == 1 and math.abs(dy) == 1 then
      -- Need to move to cardinal position
      local candidates = {
        {x = pos.x + dx, y = pos.y, z = pos.z},
        {x = pos.x, y = pos.y + dy, z = pos.z}
      }
      
      for i = 1, 2 do
        local tile = g_map.getTile(candidates[i])
        if tile and tile:isWalkable() and not tile:hasCreature() then
          -- Check anchor
          local anchorValid = true
          if config.anchor and anchorPosition then
            local anchorDist = math.max(
              math.abs(candidates[i].x - anchorPosition.x),
              math.abs(candidates[i].y - anchorPosition.y)
            )
            anchorValid = anchorDist <= (config.anchorRange or 5)
          end
          
          if anchorValid then
            if useCoordinator then
              MovementCoordinator.faceMonster(candidates[i], 0.45)
            else
              return TargetBot.walkTo(candidates[i], 2, {ignoreNonPathable = true})
            end
            break
          end
        end
      end
    elseif dist <= 1 then
      -- Just face the monster (no movement needed)
      local dir = player:getDirection()
      if dx == 1 and dir ~= 1 then turn(1)
      elseif dx == -1 and dir ~= 3 then turn(3)
      elseif dy == 1 and dir ~= 2 then turn(2)
      elseif dy == -1 and dir ~= 0 then turn(0)
      end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- EXECUTE COORDINATED MOVEMENT
  -- ═══════════════════════════════════════════════════════════════════════════
  if useCoordinator then
    local success, reason = MovementCoordinator.tick()
    if success then
      return true
    end
  end
end

onPlayerPositionChange(function(newPos, oldPos)
  if not CaveBot or not CaveBot.isOff or CaveBot.isOff() then return end
  if not TargetBot or not TargetBot.isOff or TargetBot.isOff() then return end
  if not lureMax then return end
  if storage.TargetBotDelayWhenPlayer then return end
  if not dynamicLureDelay then return end

  local targetThreshold = delayFrom or lureMax * 0.5
  if targetCount < targetThreshold or not target() then return end
  CaveBot.delay(delayValue or 0)
end)