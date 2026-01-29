--------------------------------------------------------------------------------
-- TARGETBOT CREATURE ATTACK v1.2
-- Uses TargetBotCore for shared pure functions (DRY, SRP)
-- Dynamic scaling based on monster count for better reactivity
-- v1.1: Integrated PathUtils for shared floor-change detection and tile utilities
-- v1.2: Integrated SafeCreature for safe creature access (DRY)
--------------------------------------------------------------------------------

-- Safe function calls to prevent "attempt to call global function (a nil value)" errors
local SafeCall = SafeCall or require("core.safe_call")

-- SafeCreature module for safe creature access (prevents pcall boilerplate)
local SC = SafeCreature

-- Load PathUtils if available (shared module for DRY)
local PathUtils = nil
local function ensurePathUtils()
  if PathUtils then return PathUtils end
  -- OTClient compatible - just try dofile
  local success = pcall(function()
    dofile("nExBot/utils/path_utils.lua")
  end)
  -- After dofile, PathUtils should be global
  if success then
    PathUtils = PathUtils  -- Re-check global
  end
  return PathUtils
end
ensurePathUtils()

-- Load ChaseController if available (OTClient compatible)
local ChaseController = ChaseController  -- Try existing global
local function ensureChaseController()
  if ChaseController then return ChaseController end
  -- Try to load ChaseController from targetbot folder
  local success = pcall(function()
    dofile("nExBot/targetbot/chase_controller.lua")
  end)
  -- After dofile, ChaseController should be global
  if success then
    ChaseController = ChaseController  -- Re-check global
  end
  return ChaseController
end
ensureChaseController()

local targetBotLure = false
local targetCount = 0 
local delayValue = 0
local lureMax = 0
local anchorPosition = nil
local lastCall = now
local delayFrom = nil
local dynamicLureDelay = false
local smartPullState = { lastEval = 0, lowStreak = 0, highStreak = 0, active = false, lastChange = 0 }
local dynamicLureState = { lastTrigger = 0 }

-- Use TargetCore if available (DRY - avoid duplicate implementations)
local Core = TargetCore or {}
local Geometry = Core.Geometry or {}
-- Spectator cache (safe require)
local SpectatorCache = SpectatorCache or (type(require) == 'function' and (function() local ok, mod = pcall(require, "utils.spectator_cache"); if ok then return mod end; return nil end)() or nil)

-- Helper: check MovementCoordinator for movement allowance
local zigzagState = { blockUntil = 0, cooldown = 250 }

local function movementAllowed()
  local nowt = now or (os.time() * 1000)
  if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.isZigzagging then
    if MonsterAI.Scenario.isZigzagging() then
      if nowt < zigzagState.blockUntil then
        return false
      end
      zigzagState.blockUntil = nowt + zigzagState.cooldown
      return false
    end
  end
  if nExBot and nExBot.MovementCoordinator and nExBot.MovementCoordinator.canMove then
    return nExBot.MovementCoordinator.canMove()
  end
  return true
end

-- Use Directions constant module if available (DRY - Phase 3)
local Dirs = Directions

-- Pre-computed direction offsets (use Directions module, fallback to Geometry)
-- Adjacent offsets array (use Directions.ADJACENT_OFFSETS if provided)
local DIRECTIONS = (Dirs and Dirs.ADJACENT_OFFSETS) or Geometry.ADJACENT_OFFSETS or Geometry.DIRECTIONS or {
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
local DIR_VECTORS = (Dirs and Dirs.DIR_TO_OFFSET) or Geometry.DIR_VECTORS or {
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
-- CLIENTSERVICE HELPERS (using global ClientHelper for consistency)
--------------------------------------------------------------------------------
local function getClient()
  return ClientHelper and ClientHelper.getClient() or ClientService
end

local function getClientVersion()
  return ClientHelper and ClientHelper.getClientVersion() or ((g_game and g_game.getClientVersion and g_game.getClientVersion()) or 1200)
end

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

-- Avoidance tuning knobs (can be tuned via TargetCore.CONSTANTS)
local AVOID_PREDICT_CONF = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.AVOID_PREDICT_CONF) or 0.5 -- min confidence to treat predicted wave as threat
local AVOID_PREDICT_DANGER = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.AVOID_PREDICT_DANGER) or 3.0 -- added danger weight for predicted wave


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
  -- Prefer TargetCore's implementation when available
  if Core and Core.isInFrontArc then
    return Core.isInFrontArc(pos, monsterPos, monsterDir, range, arcWidth)
  end
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
  
  local distFromCenter
  if dirVec.x == 0 then
    local inDirection = (dy * dirVec.y) > 0
    distFromCenter = math.abs(dx)
    return inDirection and distFromCenter <= arcWidth, distFromCenter
  elseif dirVec.y == 0 then
    local inDirection = (dx * dirVec.x) > 0
    distFromCenter = math.abs(dy)
    return inDirection and distFromCenter <= arcWidth, distFromCenter
  else
    local inX = (dirVec.x > 0 and dx > 0) or (dirVec.x < 0 and dx < 0)
    local inY = (dirVec.y > 0 and dy > 0) or (dirVec.y < 0 and dy < 0)
    distFromCenter = math.abs(dx - dy) / 2
    return inX and inY, distFromCenter
  end
end

-- Pure function: Score a position's danger level
-- Returns detailed danger analysis for better decision making
-- Enhanced with MonsterAI.RealTime metrics for high-accuracy threat assessment
-- @param pos: position to check
-- @param monsters: array of monster creatures
-- @param usePrediction: when true, consult MonsterAI predictions (only enabled for rePosition)
-- @return table {totalDanger, waveThreats, meleeThreats, details, realTimeMetrics}
local function analyzePositionDanger(pos, monsters, usePrediction)
  -- Prefer TargetCore if available
  if Core and Core.calculatePositionDanger then
    local danger = Core.calculatePositionDanger(pos, monsters)
    if type(danger) == 'table' then
      return danger
    end
    -- Wrap scalar danger value into expected table shape
    return { totalDanger = danger or 0, waveThreats = 0, meleeThreats = 0, details = {} }
  end
  
  local result = { 
    totalDanger = 0, 
    waveThreats = 0, 
    meleeThreats = 0, 
    details = {},
    -- New: RealTime metrics summary
    realTimeMetrics = {
      monstersFacingPos = 0,
      highTurnRateMonsters = 0,
      imminentAttacks = 0,
      avgPredictionConfidence = 0
    }
  }
  
  local predCache = {}
  local totalConfidence = 0
  local confCount = 0
  
  -- Query MonsterAI.RealTime threat cache for fast O(1) threat assessment
  local rtThreatCache = nil
  if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.threatCache then
    rtThreatCache = MonsterAI.RealTime.threatCache
  end
  
  for i = 1, #monsters do
    local monster = monsters[i]
    if monster and not monster:isDead() then
      local mpos = monster:getPosition()
      local mdir = monster:getDirection()
      local dist = math.max(math.abs(pos.x - mpos.x), math.abs(pos.y - mpos.y))
      local threat = { monster = monster, distance = dist, inWaveArc = false, arcDistance = 99 }
      
      local monsterId = monster:getId()
      
      -- ═══════════════════════════════════════════════════════════════════════
      -- NEW: MonsterAI.RealTime Integration
      -- Use direction tracking, turn rate, and facing detection for better accuracy
      -- ═══════════════════════════════════════════════════════════════════════
      local rtData = nil
      if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.directions then
        rtData = MonsterAI.RealTime.directions[monsterId]
      end
      
      if rtData then
        -- Check if monster is facing this position
        local isFacing = false
        if MonsterAI and MonsterAI.Predictor and MonsterAI.Predictor.isFacingPosition then
          isFacing = MonsterAI.Predictor.isFacingPosition(mpos, mdir, pos)
        end
        
        if isFacing then
          result.realTimeMetrics.monstersFacingPos = result.realTimeMetrics.monstersFacingPos + 1
          
          -- High turn rate = monster actively tracking player = higher threat
          local turnRate = rtData.turnRate or 0
          if turnRate > 0.5 then
            result.realTimeMetrics.highTurnRateMonsters = result.realTimeMetrics.highTurnRateMonsters + 1
            -- Add extra danger for high turn rate (actively tracking)
            result.totalDanger = result.totalDanger + turnRate * 1.5
          end
          
          -- Check how long monster has been facing this direction
          local facingDuration = 0
          if rtData.facingPlayerSince then
            facingDuration = (now or 0) - rtData.facingPlayerSince
          end
          
          -- Long facing duration + in position = imminent attack
          if facingDuration > 300 then
            result.totalDanger = result.totalDanger + math.min(2, facingDuration / 500)
          end
        end
        
        -- Check consecutive direction changes (erratic = about to attack)
        if rtData.consecutiveChanges and rtData.consecutiveChanges >= 2 then
          result.totalDanger = result.totalDanger + rtData.consecutiveChanges * 0.5
        end
      end

      -- If prediction mode is active (only used by rePosition and our avoidance integration), prefer learned predictions
      if usePrediction and MonsterAI and MonsterAI.Predictor then
        local pid = monsterId
        local pattern = MonsterAI.Patterns.get(monster:getName())
        local isPred, confidence, timeToAttack = nil, nil, nil
        if predCache[pid] then
          isPred, confidence, timeToAttack = predCache[pid].isPred, predCache[pid].conf, predCache[pid].tta
        else
          local ok, p, c, tta = pcall(function() return MonsterAI.Predictor.predictWaveAttack(monster) end)
          if ok then isPred, confidence, timeToAttack = p, c, tta else isPred, confidence, timeToAttack = false, 0, 999999 end
          predCache[pid] = { isPred = isPred, conf = confidence, tta = timeToAttack }
        end
        
        -- Track confidence for averaging
        if confidence then
          totalConfidence = totalConfidence + confidence
          confCount = confCount + 1
        end
        
        -- NEW: Use learned tracker data for better cooldown estimation
        local trackerData = nil
        if MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.monsters then
          trackerData = MonsterAI.Tracker.monsters[pid]
        end
        
        -- Override timeToAttack with more accurate tracker estimate if available
        if trackerData and trackerData.ewmaCooldown and trackerData.ewmaCooldown > 0 then
          local lastAttack = trackerData.lastWaveTime or trackerData.lastAttackTime or 0
          local elapsed = (now or 0) - lastAttack
          local cooldown = trackerData.ewmaCooldown
          timeToAttack = math.max(0, cooldown - elapsed)
          
          -- Boost confidence if we have learned data
          confidence = math.max(confidence or 0, trackerData.confidence or 0.5)
        end

        local inPredPath = false
        -- Use confidence threshold as the primary gating; allow TTA to be larger but scale urgency with a configurable window
        if confidence and confidence >= AVOID_PREDICT_CONF then
          inPredPath = pcall(function()
            return MonsterAI.Predictor.isPositionInWavePath(pos, mpos, mdir, pattern.waveRange, pattern.waveWidth)
          end)
        end
        if inPredPath then
          local maxWindow = AVOID_PREDICT_TTA_WINDOW or 3000
          local urgency = 1 - math.max(0, math.min(timeToAttack, maxWindow)) / maxWindow
          local pdanger = (pattern.dangerLevel or 1) * urgency * (confidence or 1)
          -- Add a baseline predicted danger scaled by confidence to make avoidance decisive
          pdanger = pdanger + AVOID_PREDICT_DANGER * (confidence or 1)
          
          -- NEW: Boost danger if RealTime shows imminent attack
          if timeToAttack < 800 then
            result.realTimeMetrics.imminentAttacks = result.realTimeMetrics.imminentAttacks + 1
            pdanger = pdanger * 1.3  -- 30% boost for imminent attacks
          end
          
          threat.inWaveArc = true
          threat.arcDistance = 0
          threat.predicted = true
          threat.predConf = confidence
          threat.predTTA = timeToAttack
          result.waveThreats = result.waveThreats + 1
          result.totalDanger = result.totalDanger + pdanger
        
        end
      else
        -- Fallback to simple front arc detection when prediction is not enabled
        local inArc, arcDist = isInFrontArc(pos, mpos, mdir, 5, 1)
        if inArc then
          threat.inWaveArc = true
          threat.arcDistance = arcDist
          result.waveThreats = result.waveThreats + 1
          result.totalDanger = result.totalDanger + (3 - arcDist)
        end
      end

      if dist == 1 then
        result.meleeThreats = result.meleeThreats + 1
        result.totalDanger = result.totalDanger + 2
      elseif dist == 2 then
        result.totalDanger = result.totalDanger + 0.5
      end
      result.details[#result.details + 1] = threat
    end
  end
  
  -- Calculate average prediction confidence
  if confCount > 0 then
    result.realTimeMetrics.avgPredictionConfidence = totalConfidence / confCount
  end
  
  -- NEW: Query MonsterAI.isPositionDangerous for additional validation
  if usePrediction and MonsterAI and MonsterAI.isPositionDangerous then
    local isDangerous, dangerLevel = MonsterAI.isPositionDangerous(pos)
    if isDangerous then
      -- Blend MonsterAI danger assessment (it considers all direction tracking)
      result.totalDanger = result.totalDanger + dangerLevel * 2
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
  return analysis.totalDanger > 0, (analysis.waveThreats or 0) + (analysis.meleeThreats or 0)
end

-- Pure function: Find the safest adjacent tile with improved scoring
-- Enhanced with MonsterAI.RealTime metrics for smarter avoidance
-- @param playerPos: current player position
-- @param monsters: array of monsters
-- @param currentTarget: current attack target (to maintain range)
-- @param scaling: scaling factors from calculateScaling() (optional, defaults to conservative)
-- @return position or nil, score
local function findSafeAdjacentTile(playerPos, monsters, currentTarget, scaling)
  local candidates = {}
  local currentAnalysis = analyzePositionDanger(playerPos, monsters, true)
  
  -- Default scaling if not provided (conservative behavior)
  scaling = scaling or calculateScaling(#monsters)
  
  -- Dynamic danger threshold based on monster count
  local dynamicDangerThreshold = avoidanceState.baseDangerThreshold * scaling.dangerThresholdMultiplier
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- NEW: Check MonsterAI.RealTime for immediate threats
  -- Lower threshold if under immediate threat for faster reaction
  -- ═══════════════════════════════════════════════════════════════════════════
  local immediateThreat = false
  if MonsterAI and MonsterAI.getImmediateThreat then
    local threatData = MonsterAI.getImmediateThreat()
    immediateThreat = threatData.immediateThreat or false
    if immediateThreat then
      dynamicDangerThreshold = dynamicDangerThreshold * 0.5  -- Lower threshold
    end
  end
  
  -- Prefer Core's safest tile search if available
  if Core and Core.findSafestTile then
    local coreRes = Core.findSafestTile(playerPos, monsters, currentTarget)
    if coreRes and coreRes.pos then
      return coreRes.pos, coreRes.score or 0
    end
  end
  
  -- When many monsters (7+), any danger is concerning
  -- Skip threshold check if under immediate threat
  if not immediateThreat and currentAnalysis.totalDanger < dynamicDangerThreshold then
    return nil, 0
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- NEW: Get threat directions for perpendicular escape scoring
  -- ═══════════════════════════════════════════════════════════════════════════
  local threatDirections = {}
  if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.directions then
    for id, rtData in pairs(MonsterAI.RealTime.directions) do
      if rtData.facingPlayerSince then
        local dir = rtData.dir
        if DIR_VECTORS[dir] then
          threatDirections[#threatDirections + 1] = {
            vec = DIR_VECTORS[dir],
            turnRate = rtData.turnRate or 0,
            consecutiveChanges = rtData.consecutiveChanges or 0
          }
        end
      end
    end
  end
  
  -- Score weights for decision making (enhanced with RealTime)
  local WEIGHTS = {
    DANGER = -25,              -- Penalize danger heavily
    TARGET_ADJACENT = 20,      -- Bonus for being adjacent to target
    TARGET_CLOSE = 10,         -- Bonus for being close to target
    TARGET_FAR = -5,           -- Penalty per tile beyond range 3
    ESCAPE_ROUTES = 4,         -- Bonus per escape route
    STABILITY = 8,             -- Bonus for not being in any wave arc
    PREVIOUS_SAFE = 15,        -- Bonus for returning to previous safe position
    STAY_BONUS = 10,           -- Bonus for current position (prefer staying)
    -- NEW: MonsterAI-enhanced weights
    PERPENDICULAR = 10,        -- Bonus for perpendicular escape
    NOT_FACING = 8,            -- Bonus if no monster facing this tile
    LOW_TURN_RATE = 5,         -- Bonus for low turn rate zone
    IMMINENT_SAFE = 12         -- Bonus if no imminent attacks here
  }
  
  -- Check all adjacent tiles (8 directions)
  for i = 1, 8 do
    local dir = DIRECTIONS[i]
    local checkPos = {
      x = playerPos.x + dir.x,
      y = playerPos.y + dir.y,
      z = playerPos.z
    }
    
    local tileSafe = (TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isTileSafe)
      and TargetCore.PathSafety.isTileSafe(checkPos)
      or (function()
        local Client = getClient()
        local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile and g_map.getTile(checkPos))
        local hasCreature = tile and tile.hasCreature and tile:hasCreature()
        return tile and tile:isWalkable() and not hasCreature
      end)()
    if tileSafe then
      local analysis = analyzePositionDanger(checkPos, monsters, true)
      local score = 0
      
      -- Factor 1: Danger level (most important)
      score = score + analysis.totalDanger * WEIGHTS.DANGER
      
      -- Factor 2: Stability bonus (no wave threats at all)
      if analysis.waveThreats == 0 then
        score = score + WEIGHTS.STABILITY
      end
      
      -- ═══════════════════════════════════════════════════════════════════════
      -- NEW: RealTime metrics scoring
      -- ═══════════════════════════════════════════════════════════════════════
      if analysis.realTimeMetrics then
        local rtm = analysis.realTimeMetrics
        
        -- Bonus if no monsters facing this position
        if rtm.monstersFacingPos == 0 then
          score = score + WEIGHTS.NOT_FACING
        end
        
        -- Bonus if no imminent attacks at this position
        if rtm.imminentAttacks == 0 then
          score = score + WEIGHTS.IMMINENT_SAFE
        end
        
        -- Bonus for low turn rate zone
        if rtm.highTurnRateMonsters == 0 then
          score = score + WEIGHTS.LOW_TURN_RATE
        end
      end
      
      -- Perpendicular escape bonus
      if #threatDirections > 0 then
        local moveVec = { x = dir.x, y = dir.y }
        local perpBonus = 0
        for _, threat in ipairs(threatDirections) do
          local threatVec = threat.vec
          local dot = moveVec.x * threatVec.x + moveVec.y * threatVec.y
          local moveMag = math.sqrt(moveVec.x^2 + moveVec.y^2)
          local threatMag = math.sqrt(threatVec.x^2 + threatVec.y^2)
          if moveMag > 0 and threatMag > 0 then
            local normalizedDot = math.abs(dot) / (moveMag * threatMag)
            perpBonus = perpBonus + (1 - normalizedDot) * WEIGHTS.PERPENDICULAR
            
            -- Extra bonus if moving away from high turn rate monster
            if threat.turnRate > 0.5 then
              perpBonus = perpBonus + (1 - normalizedDot) * 3
            end
          end
        end
        score = score + perpBonus / math.max(1, #threatDirections)
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
      if Core and Core.countEscapeRoutes then
        escapeRoutes = Core.countEscapeRoutes(checkPos)
      else
        for j = 1, 8 do
          local escapeDir = DIRECTIONS[j]
          local escapePos = { x = checkPos.x + escapeDir.x, y = checkPos.y + escapeDir.y, z = checkPos.z }
          local escapeSafe = (TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isTileSafe)
            and TargetCore.PathSafety.isTileSafe(escapePos)
            or (function()
              local Client = getClient()
              local et = (Client and Client.getTile) and Client.getTile(escapePos) or (g_map and g_map.getTile and g_map.getTile(escapePos))
              return et and et:isWalkable()
            end)()
          if escapeSafe then
            escapeRoutes = escapeRoutes + 1
          end
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
  local Client = getClient()
  local creatures = (MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby) and MovementCoordinator.MonsterCache.getNearby(7) or (SpectatorCache and SpectatorCache.getNearby(7, 7) or ((Client and Client.getSpectatorsInRange) and Client.getSpectatorsInRange(playerPos, false, 7, 7) or (g_map and g_map.getSpectatorsInRange and g_map.getSpectatorsInRange(playerPos, false, 7, 7))))
  local monsters = {}
  
  for i = 1, #creatures do
    local c = creatures[i]
    if c and c:isMonster() and not c:isDead() then
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
      local analysis = analyzePositionDanger(playerPos, monsters, true)
      -- Dynamic threshold to leave safe position
      local leaveThreshold = avoidanceState.baseDangerThreshold * scaling.dangerThresholdMultiplier + 0.5
      if analysis.totalDanger < leaveThreshold then
        return false  -- Still safe enough, don't move
      end
      -- Danger increased significantly, allow movement despite stickiness
    end
  end
  
  -- Find safe tile with dynamic thresholds
  local currentTarget = target and target()
  local safePos, score = findSafeAdjacentTile(playerPos, monsters, currentTarget, scaling)
  
  if safePos then
    avoidanceState.lastMove = currentTime
    avoidanceState.lastSafePos = safePos
    avoidanceState.consecutiveMoves = avoidanceState.consecutiveMoves + 1
    if movementAllowed() then
      TargetBot.walkTo(safePos, 2, {ignoreNonPathable = true, precision = 0})
    end
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
  
  -- ============================================================================
  -- EVENT-DRIVEN AVOIDANCE TRIGGERS
  -- React immediately to monster direction changes and movements
  -- ============================================================================
  
  -- Track monster facing direction for instant wave prediction
  local monsterDirections = {}  -- id -> lastDirection
  
  EventBus.on("creature:move", function(creature, oldPos)
    -- Safe creature checks using SafeCreature module
    if not SC then return end
    if not SC.isMonster(creature) then return end
    if SC.isDead(creature) then return end
    
    -- Safe property access
    local id = SC.getId(creature)
    local newDir = SC.getDirection(creature)
    if not id or not newDir then return end
    
    local oldDir = monsterDirections[id]
    
    -- Store new direction
    monsterDirections[id] = newDir
    
    -- If direction changed, monster might be turning to attack
    if oldDir and oldDir ~= newDir then
      local okPpos, playerPos = pcall(function() return player and player:getPosition() end)
      local monsterPos = SC.getPosition(creature)
      if not okPpos or not playerPos or not monsterPos then return end
      
      local dist = math.max(math.abs(playerPos.x - monsterPos.x), math.abs(playerPos.y - monsterPos.y))
      
      -- Only react if monster is close
      if dist <= 5 then
        -- Check if player is now in the monster's attack arc
        local inArc, arcDist = isInFrontArc(playerPos, monsterPos, newDir, 5, 1)
        
        if inArc then
          -- Immediate danger! Register high-confidence wave avoidance
          local monsters = {}
          local creatures = (MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby) 
            and MovementCoordinator.MonsterCache.getNearby(7) 
            or {}
          for _, c in ipairs(creatures) do
            -- Safe monster check using SafeCreature
            if SC.isMonster(c) and not SC.isDead(c) then
              monsters[#monsters + 1] = c
            end
          end
          
          if #monsters > 0 then
            local Client = getClient()
            local currentTarget = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
            local safePos, score = findSafeAdjacentTile(playerPos, monsters, currentTarget)
            
            if safePos and MovementCoordinator and MovementCoordinator.Intent then
              local confidence = 0.75 + (5 - dist) * 0.03  -- Higher confidence for closer monsters
              local mName = SC.getName(creature) or "unknown"
              MovementCoordinator.Intent.register(
                MovementCoordinator.CONSTANTS.INTENT.WAVE_AVOIDANCE, 
                safePos, 
                confidence, 
                "wave_direction_change",
                {triggered = "direction_change", monster = mName}
              )
            end
          end
        end
      end
    end
  end, 8)  -- High priority for quick response
  
  -- Pure function: Count walkable tiles around a position
  -- Uses TargetBotCore.Geometry if available, or PathUtils.findEveryPath for optimization
  -- @param position: center position
  -- @return number
  local function countWalkableTiles(position)
    -- OPTIMIZED: Use PathUtils.findEveryPath if available (native API is faster)
    if PathUtils and PathUtils.findEveryPath then
      local reachable = PathUtils.findEveryPath(position, 1, {
        ignoreCreatures = false,  -- Don't count tiles blocked by creatures
      })
      if reachable then
        return #reachable
      end
    end
    
    -- Fallback: manual check of adjacent tiles
    local count = 0
    
    for i = 1, 8 do
      local dir = DIRECTIONS[i]
      local checkPos = {
        x = position.x + dir.x,
        y = position.y + dir.y,
        z = position.z
      }
      local safe = (PathUtils and PathUtils.isTileSafe and PathUtils.isTileSafe(checkPos))
        or (TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isTileSafe and TargetCore.PathSafety.isTileSafe(checkPos))
        or (function()
          local Client = getClient()
          local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile and g_map.getTile(checkPos))
          return tile and tile:isWalkable()
        end)()
      if safe then
        count = count + 1
      end
    end
    
    return count
  end
  
  -- When monster appears close, immediately check if repositioning is needed
  EventBus.on("monster:appear", function(creature)
    -- Safe creature checks using SafeCreature module
    if not SC or not SC.isMonster(creature) then return end
    
    -- Safe position access
    local okPpos, playerPos = pcall(function() return player and player:getPosition() end)
    local monsterPos = SC.getPosition(creature)
    if not okPpos or not playerPos or not monsterPos then return end
    
    local dist = math.max(math.abs(playerPos.x - monsterPos.x), math.abs(playerPos.y - monsterPos.y))
    
    -- Monster appeared very close - immediate reposition check
    if dist <= 2 then
      -- Count walkable tiles
      local walkable = countWalkableTiles(playerPos)
      
      if walkable < 5 then  -- Getting cornered
        -- Find better position immediately
        local monsters = {}
        local creatures = (MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby) 
          and MovementCoordinator.MonsterCache.getNearby(5) 
          or {}
        for _, c in ipairs(creatures) do
          -- Safe monster check using SafeCreature
          if SC.isMonster(c) and not SC.isDead(c) then
            monsters[#monsters + 1] = c
          end
        end
        
        -- Quick search for better tile
        local bestPos, bestScore = nil, walkable * 12
        local Client = getClient()
        for dx = -1, 1 do
          for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
              local checkPos = {x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z}
              local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile and g_map.getTile(checkPos))
              local hasCreature = tile and tile.hasCreature and tile:hasCreature()
              if tile and tile:isWalkable() and not hasCreature then
                local newWalkable = countWalkableTiles(checkPos)
                local score = newWalkable * 12
                if score > bestScore + 15 then
                  bestScore = score
                  bestPos = checkPos
                end
              end
            end
          end
        end
        
        if bestPos and MovementCoordinator and MovementCoordinator.Intent then
          MovementCoordinator.Intent.register(
            MovementCoordinator.CONSTANTS.INTENT.REPOSITION, 
            bestPos, 
            0.65, 
            "reposition_monster_appear",
            {triggered = "monster_appear", walkable = walkable}
          )
        end
      end
    end
  end, 12)
  
  -- Clear direction tracking when monster disappears
  EventBus.on("monster:disappear", function(creature)
    if creature then
      local id = creature:getId()
      if id then
        monsterDirections[id] = nil
      end
    end
  end, 25)
end

-- Export functions for external use
nExBot.avoidWaveAttacks = avoidWaveAttacks
nExBot.isInFrontArc = isInFrontArc
nExBot.isDangerousPosition = isDangerousPosition
nExBot.analyzePositionDanger = analyzePositionDanger
nExBot.findSafeAdjacentTile = findSafeAdjacentTile

-- Event-driven hookup: debounce avoidWaveAttacks on creature changes nearby
if EventBus and nExBot and nExBot.EventUtil and nExBot.EventUtil.debounce then
  local debounceAvoid = nExBot.EventUtil.debounce(200, function()
    -- Run avoidance in schedule to avoid blocking EventBus handlers (debounced)
    schedule(60, function()
      pcall(avoidWaveAttacks)
    end)
  end)

  EventBus.on("creature:appear", function(creature)
    if creature and creature:isMonster() then
      local p = player and player:getPosition()
      local cpos = creature and creature:getPosition()
      if p and cpos and math.max(math.abs(p.x-cpos.x), math.abs(p.y-cpos.y)) <= 7 then
        debounceAvoid()
      end
    end
  end, 10)

  EventBus.on("creature:move", function(creature, oldPos)
    if creature and creature:isMonster() then
      local p = player and player:getPosition()
      local cpos = creature and creature:getPosition()
      if p and cpos and math.max(math.abs(p.x-cpos.x), math.abs(p.y-cpos.y)) <= 7 then
        debounceAvoid()
      end
    end
  end, 10)

  EventBus.on("monster:disappear", function(creature)
    -- disappear may reduce danger; trigger a check
    debounceAvoid()
  end, 10)
end

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS (Optimized with TargetBotCore integration)
--------------------------------------------------------------------------------

-- Pure function: Check if player is trapped (no walkable adjacent tiles)
-- @param playerPos: player position
-- @return boolean
local function isPlayerTrapped(playerPos)
  return countWalkableTiles(playerPos) == 0
end

-- Reposition to tile with more escape routes and better tactical position
-- Enhanced with MonsterAI.RealTime metrics for smarter tile selection
-- @param minTiles: minimum walkable tiles threshold
-- @param config: creature config for context (includes anchor settings)
local function rePosition(minTiles, config)
  minTiles = minTiles or 6
  
  -- Extended cooldown to prevent jitter (was 350)
  if now - lastCall < 500 then return end
  
  local playerPos = player:getPosition()
  local currentWalkable = countWalkableTiles(playerPos)
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- NEW: Check MonsterAI.RealTime for immediate threats
  -- If imminent threat detected, reduce minimum tile requirement for faster escape
  -- ═══════════════════════════════════════════════════════════════════════════
  local immediateThreat = false
  local threatBoost = 0
  if MonsterAI and MonsterAI.getImmediateThreat then
    local threatData = MonsterAI.getImmediateThreat()
    immediateThreat = threatData.immediateThreat or false
    if immediateThreat then
      -- Under immediate threat - be more aggressive about repositioning
      minTiles = math.max(3, minTiles - 2)  -- Lower threshold
      threatBoost = threatData.totalThreat * 5  -- Boost urgency
    end
  end
  
  -- Don't reposition if we have enough space (unless under immediate threat)
  if currentWalkable >= minTiles and not immediateThreat then return end
  
  -- Get nearby monsters for scoring
  local Client = getClient()
  local creatures = (MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby) and MovementCoordinator.MonsterCache.getNearby(5) or (SpectatorCache and SpectatorCache.getNearby(5, 5) or ((Client and Client.getSpectatorsInRange) and Client.getSpectatorsInRange(playerPos, false, 5, 5) or (g_map and g_map.getSpectatorsInRange and g_map.getSpectatorsInRange(playerPos, false, 5, 5))))
  local monsters = {}
  for i = 1, #creatures do
    local c = creatures[i]
    if c and c:isMonster() and not c:isDead() then
      monsters[#monsters + 1] = c
    end
  end
  
  local currentTarget = target and target()
  local bestPos = nil
  local bestScore = -9999
  
  -- Get anchor constraints
  local anchorPos = config and config.anchor and anchorPosition
  local anchorRange = config and config.anchorRange or 5
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- NEW: Get high-threat monster directions for perpendicular escape preference
  -- ═══════════════════════════════════════════════════════════════════════════
  local threatDirections = {}  -- List of vectors monsters are facing
  if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.directions then
    for id, rtData in pairs(MonsterAI.RealTime.directions) do
      if rtData.facingPlayerSince then
        -- This monster is facing player - record its direction
        local dir = rtData.dir
        if DIR_VECTORS[dir] then
          threatDirections[#threatDirections + 1] = DIR_VECTORS[dir]
        end
      end
    end
  end
  
  -- Score weights (enhanced with RealTime metrics)
  local WEIGHTS = {
    WALKABLE = 15,           -- Per walkable tile
    DANGER = -22,            -- Per danger point
    TARGET_ADJ = 20,         -- Adjacent to target
    TARGET_CLOSE = 10,       -- Within 3 tiles
    TARGET_FAR = -4,         -- Per tile beyond 3
    MOVE_COST = -4,          -- Per movement tile
    CARDINAL = 3,            -- Bonus for cardinal movement
    STAY_BONUS = 15,         -- Bonus for not moving
    -- NEW: MonsterAI-enhanced weights
    PERPENDICULAR_ESCAPE = 12,  -- Bonus for moving perpendicular to threats
    AWAY_FROM_FACING = 8,       -- Bonus for moving away from facing monsters
    LOW_TURN_RATE_ZONE = 6,     -- Bonus for positions where monsters have low turn rate
    PREDICTION_SAFE = 10        -- Bonus if MonsterAI.isPositionDangerous returns false
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
          local tileSafe = (TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isTileSafe)
            and TargetCore.PathSafety.isTileSafe(checkPos)
            or (function()
              local Client = getClient()
              local t = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile and g_map.getTile(checkPos))
              local hasCreature = t and t.hasCreature and t:hasCreature()
              return t and t:isWalkable() and not hasCreature
            end)()
          if tileSafe then
            -- Score this position using improved danger analysis
            local score = 0
            
            -- Factor 1: Walkable tiles (escape routes)
            local walkable = countWalkableTiles(checkPos)
            score = score + walkable * WEIGHTS.WALKABLE
            
            -- Factor 2: Danger analysis (uses improved analyzePositionDanger with RealTime metrics)
            local analysis = analyzePositionDanger(checkPos, monsters, true)
            score = score + analysis.totalDanger * WEIGHTS.DANGER
            
            -- ═══════════════════════════════════════════════════════════════
            -- NEW: MonsterAI.RealTime Enhanced Scoring
            -- ═══════════════════════════════════════════════════════════════
            
            -- Factor 2b: Bonus if no monsters facing this position
            if analysis.realTimeMetrics and analysis.realTimeMetrics.monstersFacingPos == 0 then
              score = score + WEIGHTS.AWAY_FROM_FACING
            end
            
            -- Factor 2c: Bonus if no imminent attacks at this position
            if analysis.realTimeMetrics and analysis.realTimeMetrics.imminentAttacks == 0 then
              score = score + WEIGHTS.PREDICTION_SAFE
            end
            
            -- Factor 2d: Bonus for low turn rate zone (monsters not actively tracking)
            if analysis.realTimeMetrics and analysis.realTimeMetrics.highTurnRateMonsters == 0 then
              score = score + WEIGHTS.LOW_TURN_RATE_ZONE
            end
            
            -- Factor 2e: Perpendicular escape bonus
            -- Moving perpendicular to threat direction is safer than moving along attack axis
            if #threatDirections > 0 then
              local moveVec = { x = dx, y = dy }
              local perpBonus = 0
              for _, threatVec in ipairs(threatDirections) do
                -- Calculate dot product (0 = perpendicular, 1/-1 = parallel)
                local dot = moveVec.x * threatVec.x + moveVec.y * threatVec.y
                local moveMag = math.sqrt(moveVec.x^2 + moveVec.y^2)
                local threatMag = math.sqrt(threatVec.x^2 + threatVec.y^2)
                if moveMag > 0 and threatMag > 0 then
                  local normalizedDot = math.abs(dot) / (moveMag * threatMag)
                  -- Lower dot = more perpendicular = better
                  perpBonus = perpBonus + (1 - normalizedDot) * WEIGHTS.PERPENDICULAR_ESCAPE
                end
              end
              score = score + perpBonus / math.max(1, #threatDirections)
            end
            
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
            
            -- Factor 6: Threat boost from immediate danger
            if immediateThreat then
              -- When under threat, prioritize safety over other factors
              local safetyBonus = (8 - analysis.totalDanger) * 3
              score = score + safetyBonus
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
  -- CRITICAL: Do not attack if TargetBot is disabled or explicitly turned off
  if TargetBot then
    if TargetBot.canAttack and not TargetBot.canAttack() then
      return
    elseif TargetBot.explicitlyDisabled then
      return
    elseif TargetBot.isOn and not TargetBot.isOn() then
      return
    end
  end
  
  if player:isWalking() then
    lastWalk = now
  end

  local config = params.config
  local creature = params.creature
  local creaturePos = creature:getPosition()
  local playerPos = player:getPosition()
  
  -- DEBUG: Verify chase config is being passed correctly
  -- Uncomment to debug: print(\"[Chase] config.chase=\" .. tostring(config.chase) .. \" keepDistance=\" .. tostring(config.keepDistance))

  -- Update ActiveMovementConfig for EventBus-driven movement intents
  if TargetBot.ActiveMovementConfig then
    TargetBot.ActiveMovementConfig.chase = config.chase or false
    TargetBot.ActiveMovementConfig.keepDistance = config.keepDistance or false
    TargetBot.ActiveMovementConfig.keepDistanceRange = config.keepDistanceRange or 4
    TargetBot.ActiveMovementConfig.finishKillThreshold = storage.extras and storage.extras.killUnder or 30
    TargetBot.ActiveMovementConfig.anchor = config.anchor and playerPos or nil
    TargetBot.ActiveMovementConfig.anchorRange = config.anchorRange or 5
  end

  -- ═══════════════════════════════════════════════════════════════════════════
  -- NATIVE CHASE MODE SETUP (MUST happen BEFORE g_game.attack())
  -- 
  -- OTClient Chase Mode (g_game.setChaseMode):
  --   0 = DontChase (Stand) - Player won't auto-walk to target
  --   1 = ChaseOpponent - Client automatically walks toward attacked creature
  --
  -- CRITICAL: When chase mode is enabled, we should NOT use custom walking
  -- (autoWalk, walkTo, etc.) as it interferes with the native chase behavior.
  -- The client handles pathfinding and walking automatically.
  --
  -- NOTE: avoidAttacks doesn't prevent chase - it only temporarily overrides
  -- when an attack needs to be avoided. Chase is the default movement mode.
  -- ═══════════════════════════════════════════════════════════════════════════
  -- Chase should be enabled unless keepDistance is ON (mutually exclusive)
  -- avoidAttacks is handled separately in the walk function (temporary override)
  local useNativeChase = config.chase and not config.keepDistance
  
  -- DEBUG: Log chase mode decision (can be commented out in production)
  -- print(\"[Chase Debug] config.chase=\" .. tostring(config.chase) .. \" keepDistance=\" .. tostring(config.keepDistance) .. \" useNativeChase=\" .. tostring(useNativeChase))
  
  -- Use ChaseController if available (unified chase management)
  local Client = getClient()
  if ChaseController then
    ChaseController.setDesiredChase(useNativeChase)
    ChaseController.syncMode()
  elseif (Client and Client.setChaseMode) or (g_game and g_game.setChaseMode) then
    -- Fallback: direct chase mode control
    local desiredMode = useNativeChase and 1 or 0
    local currentMode = (Client and Client.getChaseMode) and Client.getChaseMode() or (g_game and g_game.getChaseMode and g_game.getChaseMode()) or -1
    if currentMode ~= desiredMode then
      if Client and Client.setChaseMode then
        Client.setChaseMode(desiredMode)
      elseif g_game and g_game.setChaseMode then
        g_game.setChaseMode(desiredMode)
      end
      -- Cache the mode for other modules
      if TargetCore and TargetCore.Native then
        TargetCore.Native.lastChaseMode = desiredMode
      end
    end
  end
  
  -- Store whether we're using native chase for the walk function
  TargetBot.usingNativeChase = useNativeChase
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- REACHABILITY VALIDATION (v2.1): Verify target before attack
  -- Prevents "Creature not reachable" errors
  -- ═══════════════════════════════════════════════════════════════════════════
  if MonsterAI and MonsterAI.Reachability and MonsterAI.Reachability.validateTarget then
    local isValid, reason, path = MonsterAI.Reachability.validateTarget(creature)
    
    if not isValid then
      -- Target is not reachable - skip attack and allow CaveBot to proceed
      if reason == "no_path" or reason == "blocked_tile" then
        -- Clear attack target to prevent OTClient errors
        local Client2 = getClient()
        local currentTarget = (Client2 and Client2.getAttackingCreature) and Client2.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
        if currentTarget and currentTarget:getId() == creature:getId() then
          pcall(function()
            if Client2 and Client2.cancelAttackAndFollow then
              Client2.cancelAttackAndFollow()
            elseif g_game and g_game.cancelAttackAndFollow then
              g_game.cancelAttackAndFollow()
            end
          end)
        end
        
        -- Allow CaveBot to walk away from blocked creature
        if TargetBot.allowCavebot then
          TargetBot.allowCavebot("blocked_creature")
        end
        
        return  -- Skip attack
      end
    end
  end
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- UNIFIED ATTACK MANAGEMENT (v4.0)
  -- Use ID comparison (not reference) to detect target changes
  -- Defer to AttackStateMachine for rate-limited, consistent attacks
  -- ═══════════════════════════════════════════════════════════════════════════
  local currentTarget = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
  
  -- Get IDs for proper comparison (reference comparison can give false positives)
  local currentTargetId = nil
  local wantedTargetId = nil
  pcall(function() currentTargetId = currentTarget and currentTarget:getId() end)
  pcall(function() wantedTargetId = creature and creature:getId() end)
  
  -- Only issue attack if we're not already attacking the correct target
  local needsAttack = (currentTargetId ~= wantedTargetId) or (not currentTarget)
  
  if needsAttack and wantedTargetId then
    -- Delegate to AttackStateMachine for rate-limited attack management
    -- This prevents attack spam while ensuring continuous attacking
    local attackIssued = false
    if AttackStateMachine and AttackStateMachine.requestSwitch then
      -- Use requestSwitch for rate-limited attack
      local priority = params.priority or (params.config and params.config.priority) or 100
      attackIssued = AttackStateMachine.requestSwitch(creature, priority * 100)
    end
    
    -- Fallback only if AttackStateMachine not available
    if not attackIssued then
      local ok, err = pcall(function()
        if Client and Client.attack then
          Client.attack(creature)
        elseif g_game and g_game.attack then
          g_game.attack(creature)
        end
      end)
      if not ok then warn("[TargetBot] attack pcall failed: " .. tostring(err)) end
    end
    
    -- IMPORTANT: Do NOT call g_game.follow() - it cancels the attack!
    -- When chase mode is set to 1 (ChaseOpponent), OTClient handles walking automatically
    
    -- Notify EventTargeting of target acquisition
    if EventTargeting and EventTargeting.CombatCoordinator then
      local dist = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
      if dist > 1 then
        pcall(function() EventTargeting.CombatCoordinator.registerChaseIntent(creature, creaturePos, dist) end)
      end
      pcall(function() EventTargeting.CombatCoordinator.pauseCaveBot() end)
    end
    
    -- Emit target acquired event for other modules
    if EventBus then
      pcall(function() EventBus.emit("targetbot/target_acquired", creature, creaturePos) end)
    end
    
    schedule(200, function()
      local atk = g_game.getAttackingCreature and g_game.getAttackingCreature() or nil
      -- No debug info emitted about registration status
    end)
  end

  if not isLooting then
    -- When using native chase mode, skip custom walking - OTClient handles it
    -- Only use custom walking for keepDistance, avoidAttacks, rePosition, or when chase is disabled
    if not useNativeChase then
      TargetBot.Creature.walk(creature, config, targets)
    elseif config.avoidAttacks or config.rePosition then
      -- Still allow wave avoidance and repositioning even with chase enabled
      -- These are safety features that should override chase temporarily
      TargetBot.Creature.walk(creature, config, targets)
    end
    -- When useNativeChase is true and no safety features needed,
    -- OTClient's chase mode handles the walking automatically
  end

  -- Cache mana check
  local mana = player:getMana()
  local playerPos = player:getPosition()
  

end

TargetBot.Creature.walk = function(creature, config, targets)
  local cpos = creature:getPosition()
  local pos = player:getPosition()
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- PARTY HUNT: Force Follow Mode Check
  -- When force follow mode is active from Follow Player, skip TargetBot's
  -- movement logic to allow the follower to catch up to the party leader
  -- ═══════════════════════════════════════════════════════════════════════════
  if TargetBot.isForceFollowActive and TargetBot.isForceFollowActive() then
    -- Skip all TargetBot movement - let Follow Player take control
    -- The attack function will still run, but we won't chase or reposition
    return
  end
  
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
    -- ENHANCED: Consider MonsterAI threat data for smarter decisions
    if config.smartPull then
      local nowt = now or (os.time() * 1000)
      if (nowt - smartPullState.lastEval) >= 300 then
        smartPullState.lastEval = nowt

        -- SAFEGUARD: Only try to pull if there are ANY monsters on screen
        local screenMonsters = 0
        if EventTargeting and EventTargeting.getLiveMonsterCount then
          screenMonsters = EventTargeting.getLiveMonsterCount() or 0
        else
          screenMonsters = SafeCall.getMonsters(7) or 0
        end

        if screenMonsters == 0 then
          smartPullState.active = false
          smartPullState.lowStreak = 0
          smartPullState.highStreak = 0
        else
          local pullRange = config.smartPullRange or 2
          local pullMin = config.smartPullMin or 3
          local pullShape = config.smartPullShape or (nExBot.SHAPE and nExBot.SHAPE.CIRCLE) or 2
          local pullOff = pullMin + 1  -- hysteresis

          local nearbyMonsters = 0
          if getMonstersAdvanced then
            nearbyMonsters = SafeCall.global("getMonstersAdvanced", pullRange, pullShape) or 0
          else
            nearbyMonsters = getMonsters(pullRange) or 0
          end

          -- ENHANCED: Check MonsterAI for imminent threats
          local underImmediateThreat = false
          if MonsterAI and MonsterAI.getImmediateThreat then
            local threatData = MonsterAI.getImmediateThreat()
            underImmediateThreat = threatData.immediateThreat and threatData.highestConfidence >= 0.7
          end

          if underImmediateThreat then
            smartPullState.active = false
            smartPullState.lowStreak = 0
            smartPullState.highStreak = 0
          else
            if nearbyMonsters < pullMin then
              smartPullState.lowStreak = smartPullState.lowStreak + 1
              smartPullState.highStreak = 0
            elseif nearbyMonsters >= pullOff then
              smartPullState.highStreak = smartPullState.highStreak + 1
              smartPullState.lowStreak = 0
            else
              smartPullState.lowStreak = 0
              smartPullState.highStreak = 0
            end

            if smartPullState.lowStreak >= 2 then
              smartPullState.active = true
              smartPullState.lastChange = nowt
            elseif smartPullState.highStreak >= 2 then
              smartPullState.active = false
              smartPullState.lastChange = nowt
            end
          end
        end
      end
      TargetBot.smartPullActive = smartPullState.active
    else
      TargetBot.smartPullActive = false
      smartPullState.active = false
      smartPullState.lowStreak = 0
      smartPullState.highStreak = 0
    end
    
    -- Dynamic lure: Pull more monsters when target count is low
    -- Only trigger if smartPull is not pausing us
    if not TargetBot.smartPullActive and TargetBot.canLure() and config.dynamicLure then
      local nowt = now or (os.time() * 1000)
      if targetBotLure and (nowt - (dynamicLureState.lastTrigger or 0)) > 700 then
        dynamicLureState.lastTrigger = nowt
        return TargetBot.allowCaveBot(150)
      end
    end
    
    -- Legacy closeLure support
    if config.closeLure and config.closeLureAmount then
      if SafeCall.getMonsters(1) >= config.closeLureAmount then
        return TargetBot.allowCaveBot(150)
      end
    end
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- KILL BEFORE WALK: When dynamicLure is DISABLED, do NOT allow CaveBot
    -- to proceed until all monsters on screen are killed.
    -- This ensures the screen is cleared before moving to the next waypoint.
    -- ═══════════════════════════════════════════════════════════════════════
    if not config.dynamicLure then
      -- Check if there are still monsters on screen that need to be killed
      local screenMonsters = SafeCall.getMonsters(7)  -- Full visible range
      if screenMonsters > 0 then
        -- Do NOT call allowCaveBot - keep CaveBot paused until screen is clear
        -- Continue with normal attack/positioning below
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
  local creatures = (MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby)
    and MovementCoordinator.MonsterCache.getNearby(7)
    or (SpectatorCache and SpectatorCache.getNearby(7, 7) or g_map.getSpectatorsInRange(pos, false, 7, 7))
  local monsters = {}
  for i = 1, #creatures do
    local c = creatures[i]
    if c and c:isMonster() and not c:isDead() then
      monsters[#monsters + 1] = c
    end
  end
  
  -- Update MonsterAI tracking if available
  if MonsterAI and MonsterAI.updateAll then
    MonsterAI.updateAll()
  end

  -- ─────────────────────────────────────────────────────────────────────────
  -- AUTO-FOLLOW MANAGEMENT: Handle native chase vs precision control
  -- 
  -- OTClient chase mode (setChaseMode(1)) works WITH attacking - we don't
  -- need to cancel it. Only g_game.follow() (which we're not using for 
  -- monsters) needs to be managed.
  --
  -- Native chase is compatible with:
  -- - Chase (that's what it's for!)
  -- - Basic attacking (no movement override)
  -- - rePosition (can coexist - rePosition is opportunistic)
  --
  -- But we need to TEMPORARILY disable chase mode for:
  -- - Wave avoidance (needs instant custom direction changes)
  -- - Keep distance (needs precise range maintenance)
  -- ─────────────────────────────────────────────────────────────────────────
  -- Only avoidAttacks and keepDistance require disabling native chase
  -- rePosition is opportunistic and works alongside native chase
  local needsPrecisionControl = config.avoidAttacks or config.keepDistance
  
  -- When precision control is needed, temporarily set chase mode to Stand
  -- This allows our custom walking to work without interference
  local Client = getClient()
  if needsPrecisionControl then
    -- Set chase mode to Stand temporarily for precision control
    local hasSetChaseMode = (Client and Client.setChaseMode) or (g_game and g_game.setChaseMode)
    local hasGetChaseMode = (Client and Client.getChaseMode) or (g_game and g_game.getChaseMode)
    if hasSetChaseMode and hasGetChaseMode then
      local currentMode = (Client and Client.getChaseMode) and Client.getChaseMode() or (g_game and g_game.getChaseMode and g_game.getChaseMode())
      if currentMode == 1 then
        if Client and Client.setChaseMode then
          Client.setChaseMode(0)  -- DontChase/Stand
        elseif g_game and g_game.setChaseMode then
          g_game.setChaseMode(0)  -- DontChase/Stand
        end
        TargetBot.usingNativeChase = false
      end
    end
    
    -- Also cancel follow if active (shouldn't be for monsters, but safety check)
    local hasCancelFollow = (Client and Client.cancelFollow) or (g_game and g_game.cancelFollow)
    local hasGetFollowingCreature = (Client and Client.getFollowingCreature) or (g_game and g_game.getFollowingCreature)
    if hasCancelFollow and hasGetFollowingCreature then
      local currentFollow = (Client and Client.getFollowingCreature) and Client.getFollowingCreature() or (g_game and g_game.getFollowingCreature and g_game.getFollowingCreature())
      if currentFollow then
        if Client and Client.cancelFollow then
          Client.cancelFollow()
        elseif g_game and g_game.cancelFollow then
          g_game.cancelFollow()
        end
      end
    end
  elseif config.chase then
    -- Chase mode without precision control - ensure native chase is active
    local hasSetChaseMode = (Client and Client.setChaseMode) or (g_game and g_game.setChaseMode)
    local hasGetChaseMode = (Client and Client.getChaseMode) or (g_game and g_game.getChaseMode)
    if hasSetChaseMode and hasGetChaseMode then
      local currentMode = (Client and Client.getChaseMode) and Client.getChaseMode() or (g_game and g_game.getChaseMode and g_game.getChaseMode())
      if currentMode ~= 1 then
        if Client and Client.setChaseMode then
          Client.setChaseMode(1)  -- ChaseOpponent
        elseif g_game and g_game.setChaseMode then
          g_game.setChaseMode(1)  -- ChaseOpponent
        end
        TargetBot.usingNativeChase = true
      end
    end
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
        if movementAllowed() then
          return TargetBot.walkTo(cpos, 10, {ignoreNonPathable = true, precision = 1})
        end
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
            if movementAllowed() then
              return TargetBot.walkTo(cpos, 10, walkParams)
            end
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
            local tileSafe = (TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isTileSafe)
              and TargetCore.PathSafety.isTileSafe(checkPos)
              or (function()
                local Client = getClient()
                local t = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile and g_map.getTile(checkPos))
                local hasCreature = t and t.hasCreature and t:hasCreature()
                return t and t:isWalkable() and not hasCreature
              end)()
            
            if tileSafe then
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
  -- 
  -- OTClient native chase mode (setChaseMode(1)) handles basic chasing when
  -- the player is attacking. When native chase is active, we should NOT
  -- call autoWalk or custom pathfinding as it interferes.
  --
  -- This fallback is ONLY used when:
  -- 1. Native chase mode is not active (usingNativeChase = false)
  -- 2. OR there's an anchor constraint that native chase can't respect
  -- 3. OR the server doesn't support native chase
  --
  -- IMPROVED: Only chase when monster is FAR from player (distance > 2)
  -- This prevents unnecessary movement when already in melee/close range.
  --
  -- NOTE: Do NOT use g_game.follow() - it cancels the attack!
  -- ─────────────────────────────────────────────────────────────────────────
  
  -- Calculate direct distance (Chebyshev) to creature for chase decision
  local chaseDistanceThreshold = config.chaseDistanceThreshold or 2  -- Only chase if farther than this
  local directDist = math.max(math.abs(pos.x - cpos.x), math.abs(pos.y - cpos.y))
  
  local chaseExecuted = false
  -- Only trigger chase when monster is FAR (distance > threshold) - prevents chasing when already close
  if config.chase and not config.keepDistance and pathLen > 1 and directDist > chaseDistanceThreshold then
    -- First check: Is native chase already handling this?
    local nativeChaseMayWork = false
    local Client2 = getClient()
    local hasGetChaseMode = (Client2 and Client2.getChaseMode) or (g_game and g_game.getChaseMode)
    local hasIsAttacking = (Client2 and Client2.isAttacking) or (g_game and g_game.isAttacking)
    if hasGetChaseMode and hasIsAttacking then
      local isAttacking = (Client2 and Client2.isAttacking) and Client2.isAttacking() or (g_game and g_game.isAttacking and g_game.isAttacking())
      local chaseMode = (Client2 and Client2.getChaseMode) and Client2.getChaseMode() or (g_game and g_game.getChaseMode and g_game.getChaseMode())
      nativeChaseMayWork = isAttacking and chaseMode == 1
    end
    
    -- Check anchor constraint
    local anchorValid = true
    local hasAnchorConstraint = false
    if config.anchor and anchorPosition then
      hasAnchorConstraint = true
      local anchorDist = math.max(
        math.abs(cpos.x - anchorPosition.x),
        math.abs(cpos.y - anchorPosition.y)
      )
      anchorValid = anchorDist <= (config.anchorRange or 5)
    end
    
    -- Only use custom chase if:
    -- 1. Native chase isn't active/working, OR
    -- 2. There's an anchor constraint (native chase doesn't know about anchors)
    local needsCustomChase = not nativeChaseMayWork or hasAnchorConstraint
    
    if needsCustomChase and anchorValid then
      -- Use player:autoWalk() for direct client-side movement
      if player and player.autoWalk and not player:isWalking() then
        pcall(function() player:autoWalk(cpos) end)
        chaseExecuted = true
        return true
      end
    elseif nativeChaseMayWork and anchorValid then
      -- Native chase is working, just return success
      chaseExecuted = true
      return true
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
        local tileSafe = (TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isTileSafe)
          and TargetCore.PathSafety.isTileSafe(candidates[i])
          or (function()
            local Client3 = getClient()
            local t = (Client3 and Client3.getTile) and Client3.getTile(candidates[i]) or (g_map and g_map.getTile and g_map.getTile(candidates[i]))
            local hasCreature = t and t.hasCreature and t:hasCreature()
            return t and t:isWalkable() and not hasCreature
          end)()
        if tileSafe then
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
              if movementAllowed() then
                return TargetBot.walkTo(candidates[i], 2, {ignoreNonPathable = true})
              end
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
    
    -- CHASE FALLBACK: If MovementCoordinator didn't execute but chase is enabled
    -- Check if native chase is already working before using custom pathfinding
    -- IMPROVED: Only chase when monster is FAR from player (distance > threshold)
    local fallbackDirectDist = math.max(math.abs(pos.x - cpos.x), math.abs(pos.y - cpos.y))
    local fallbackChaseThreshold = config.chaseDistanceThreshold or 2
    
    if config.chase and not config.keepDistance and pathLen > 1 and fallbackDirectDist > fallbackChaseThreshold then
      -- First check if native chase is active and should be working
      local nativeChaseMayWork = false
      local Client4 = getClient()
      local hasGetChaseMode = (Client4 and Client4.getChaseMode) or (g_game and g_game.getChaseMode)
      local hasIsAttacking = (Client4 and Client4.isAttacking) or (g_game and g_game.isAttacking)
      if hasGetChaseMode and hasIsAttacking then
        local isAttacking = (Client4 and Client4.isAttacking) and Client4.isAttacking() or (g_game and g_game.isAttacking and g_game.isAttacking())
        local chaseMode = (Client4 and Client4.getChaseMode) and Client4.getChaseMode() or (g_game and g_game.getChaseMode and g_game.getChaseMode())
        nativeChaseMayWork = isAttacking and chaseMode == 1
      end
      
      -- If native chase is active, trust it and don't interfere
      if nativeChaseMayWork then
        return true  -- Native chase is handling movement
      end
      
      -- Only use custom fallback if native chase isn't working
      if not player:isWalking() then
        local anchorValid = true
        if config.anchor and anchorPosition then
          local anchorDist = math.max(
            math.abs(cpos.x - anchorPosition.x),
            math.abs(cpos.y - anchorPosition.y)
          )
          anchorValid = anchorDist <= (config.anchorRange or 5)
        end
        
        if anchorValid then
          -- Use direct autoWalk for immediate chase
          if player and player.autoWalk then
            pcall(function() player:autoWalk(cpos) end)
            return true
          end
        end
      end
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
  if targetCount < targetThreshold or not (target and target()) then return end
  CaveBot.delay(delayValue or 0)
end)

-- ============================================================================
-- EVENT-DRIVEN LURE COORDINATION (DRY, SRP)
-- 
-- Integrates lure system with EventBus for instant responsiveness:
-- - Emits lure state changes for CaveBot coordination
-- - Registers LURE intents with MovementCoordinator
-- - Provides pure function for lure eligibility check
-- ============================================================================

-- Pure function: Calculate lure eligibility (no side effects)
-- @param config: creature config with lure settings
-- @param targets: current target count
-- @return table { shouldLure: boolean, confidence: number, reason: string }
local function calculateLureEligibility(config, targets)
  if not config then
    return { shouldLure = false, confidence = 0, reason = "no_config" }
  end
  
  if not config.dynamicLure then
    return { shouldLure = false, confidence = 0, reason = "disabled" }
  end
  
  local lureMin = config.lureMin or 3
  local lurMax = config.lureMax or 6
  
  -- Not enough targets - should lure more
  if targets < lureMin then
    local deficit = lureMin - targets
    local confidence = 0.5 + (deficit / lureMin) * 0.3
    return { 
      shouldLure = true, 
      confidence = math.min(0.85, confidence), 
      reason = "below_min",
      deficit = deficit
    }
  end
  
  -- At max capacity - stop luring
  if targets >= lurMax then
    return { shouldLure = false, confidence = 0.9, reason = "at_max" }
  end
  
  -- Between min and max - prefer fighting
  return { shouldLure = false, confidence = 0.6, reason = "sufficient" }
end

-- Export pure function for external use
nExBot.calculateLureEligibility = calculateLureEligibility

-- Event-driven lure state management
if EventBus then
  -- Track lure state for change detection
  local lastLureState = { active = false, time = 0 }
  
  -- React to target count changes for lure decisions
  EventBus.on("targetbot/target_count_change", function(newCount, oldCount)
    if not TargetBot or not TargetBot.isOn or not TargetBot.isOn() then return end
    
    -- Get current creature config
    local activeConfig = TargetBot.ActiveMovementConfig
    if not activeConfig then return end
    
    local eligibility = calculateLureEligibility(activeConfig, newCount)
    
    -- State changed - emit event
    if eligibility.shouldLure ~= lastLureState.active then
      lastLureState.active = eligibility.shouldLure
      lastLureState.time = now
      
      if eligibility.shouldLure then
        -- Start luring - emit event for CaveBot
        pcall(function()
          EventBus.emit("targetbot/lure_start", {
            reason = eligibility.reason,
            confidence = eligibility.confidence,
            deficit = eligibility.deficit
          })
        end)
        
        -- Register LURE intent with MovementCoordinator
        if MovementCoordinator and MovementCoordinator.Intent then
          local playerPos = player and player:getPosition()
          if playerPos then
            -- Lure intent uses player's current position (CaveBot handles destination)
            MovementCoordinator.Intent.register(
              MovementCoordinator.CONSTANTS.INTENT.LURE,
              playerPos,
              eligibility.confidence,
              "lure_event",
              { triggered = "target_count", targets = newCount, deficit = eligibility.deficit }
            )
          end
        end
      else
        -- Stop luring - emit event
        pcall(function()
          EventBus.emit("targetbot/lure_stop", {
            reason = eligibility.reason,
            targets = newCount
          })
        end)
      end
    end
  end, 15)
  
  -- React to monster deaths to update lure decisions quickly
  EventBus.on("monster:disappear", function(creature)
    if not creature then return end
    
    -- Check if this affects our target count significantly
    local monsterCount = 0
    if MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby then
      local nearby = MovementCoordinator.MonsterCache.getNearby(7)
      monsterCount = #nearby
    end
    
    -- Emit target count change event
    pcall(function()
      EventBus.emit("targetbot/target_count_change", monsterCount, monsterCount + 1)
    end)
  end, 18)
  
  -- React to monster appearances
  EventBus.on("monster:appear", function(creature)
    if not creature then return end
    
    local playerPos = player and player:getPosition()
    local creaturePos = creature:getPosition()
    if not playerPos or not creaturePos then return end
    
    local dist = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
    
    -- Only count nearby monsters
    if dist <= 7 then
      local monsterCount = 0
      if MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby then
        local nearby = MovementCoordinator.MonsterCache.getNearby(7)
        monsterCount = #nearby
      end
      
      -- Emit target count change event
      pcall(function()
        EventBus.emit("targetbot/target_count_change", monsterCount, monsterCount - 1)
      end)
    end
  end, 18)
  
  -- Emit pull system state changes for CaveBot coordination
  local lastPullState = false
  
  EventBus.on("targetbot/combat_start", function(creature, data)
    -- When combat starts, evaluate pull system state
    schedule(100, function()
      if TargetBot and TargetBot.smartPullActive ~= lastPullState then
        lastPullState = TargetBot.smartPullActive
        if TargetBot.smartPullActive then
          pcall(function()
            EventBus.emit("targetbot/pull_active", {
              creature = creature,
              time = now
            })
          end)
        end
      end
    end)
  end, 12)
  
  EventBus.on("targetbot/combat_end", function()
    -- Combat ended - clear pull state
    if lastPullState then
      lastPullState = false
      pcall(function()
        EventBus.emit("targetbot/pull_inactive")
      end)
    end
  end, 12)
end