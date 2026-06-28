-- TargetBot Attack Waves Module
-- Wave/damage zone detection and avoidance

local getClient = nExBot.Shared.getClient
local SC = SafeCreature or {}
local Dirs = Directions
local DIRECTIONS = (Dirs and Dirs.ADJACENT_OFFSETS) or {
  {x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0},
  {x = 1, y = -1}, {x = 1, y = 1}, {x = -1, y = 1}, {x = -1, y = -1}
}
local DIR_VECTORS = Directions.DIR_TO_OFFSET

local avoidanceState = {
  lastMove = 0, baseCooldown = 350, lastSafePos = nil,
  baseStickiness = 600, consecutiveMoves = 0, maxConsecutive = 3,
  baseDangerThreshold = 1.5, lastMonsterCount = 0
}

local AVOID_PREDICT_CONF = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.AVOID_PREDICT_CONF) or 0.5
local AVOID_PREDICT_DANGER = (TargetCore and TargetCore.CONSTANTS and TargetCore.CONSTANTS.AVOID_PREDICT_DANGER) or 3.0

local function calculateScaling(monsterCount)
  local reactivityScale = 1.0
  if monsterCount >= 7 then reactivityScale = 0.4
  elseif monsterCount >= 5 then reactivityScale = 0.55
  elseif monsterCount >= 3 then reactivityScale = 0.75
  end
  return {
    cooldownMultiplier = reactivityScale,
    stickinessMultiplier = reactivityScale,
    dangerThresholdMultiplier = reactivityScale,
    scoreThresholdMultiplier = reactivityScale,
    monsterCount = monsterCount
  }
end

local function isInFrontArc(pos, monsterPos, monsterDir, range, arcWidth)
  range = range or 5
  arcWidth = arcWidth or 1
  local dirVec = DIR_VECTORS[monsterDir]
  if not dirVec then return false, 99 end
  local dx = pos.x - monsterPos.x
  local dy = pos.y - monsterPos.y
  local dist = math.max(math.abs(dx), math.abs(dy))
  if dist == 0 or dist > range then return false, dist end
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

local function analyzePositionDanger(pos, monsters, usePrediction)
  local result = {
    totalDanger = 0, waveThreats = 0, meleeThreats = 0, details = {},
    realTimeMetrics = {
      monstersFacingPos = 0, highTurnRateMonsters = 0,
      imminentAttacks = 0, avgPredictionConfidence = 0
    }
  }
  local predCache = {}
  local totalConfidence = 0
  local confCount = 0
  local rtThreatCache = nil
  if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.threatCache then
    rtThreatCache = MonsterAI.RealTime.threatCache
  end
  for i = 1, #monsters do
    local monster = monsters[i]
    if monster and not monster:isDead() then
      local mpos = monster:getPosition()
      if mpos then
      local mdir = monster:getDirection()
      local dist = math.max(math.abs(pos.x - mpos.x), math.abs(pos.y - mpos.y))
      local threat = { monster = monster, distance = dist, inWaveArc = false, arcDistance = 99 }
      local monsterId = monster:getId()
      local rtData = nil
      if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.directions then
        rtData = MonsterAI.RealTime.directions[monsterId]
      end
      if rtData then
        local isFacing = false
        if MonsterAI and MonsterAI.Predictor and MonsterAI.Predictor.isFacingPosition then
          isFacing = MonsterAI.Predictor.isFacingPosition(mpos, mdir, pos)
        end
        if isFacing then
          result.realTimeMetrics.monstersFacingPos = result.realTimeMetrics.monstersFacingPos + 1
          local turnRate = rtData.turnRate or 0
          if turnRate > 0.5 then
            result.realTimeMetrics.highTurnRateMonsters = result.realTimeMetrics.highTurnRateMonsters + 1
            result.totalDanger = result.totalDanger + turnRate * 1.5
          end
          local facingDuration = 0
          if rtData.facingPlayerSince then
            facingDuration = (now or 0) - rtData.facingPlayerSince
          end
          if facingDuration > 300 then
            result.totalDanger = result.totalDanger + math.min(2, facingDuration / 500)
          end
        end
        if rtData.consecutiveChanges and rtData.consecutiveChanges >= 2 then
          result.totalDanger = result.totalDanger + rtData.consecutiveChanges * 0.5
        end
      end
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
        if confidence then
          totalConfidence = totalConfidence + confidence
          confCount = confCount + 1
        end
        local trackerData = nil
        if MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.monsters then
          trackerData = MonsterAI.Tracker.monsters[pid]
        end
        if trackerData and trackerData.ewmaCooldown and trackerData.ewmaCooldown > 0 then
          local lastAttack = trackerData.lastWaveTime or trackerData.lastAttackTime or 0
          local elapsed = (now or 0) - lastAttack
          local cooldown = trackerData.ewmaCooldown
          timeToAttack = math.max(0, cooldown - elapsed)
          confidence = math.max(confidence or 0, trackerData.confidence or 0.5)
        end
        local inPredPath = false
        if confidence and confidence >= AVOID_PREDICT_CONF then
          local ok, pathResult = pcall(MonsterAI.Predictor.isPositionInWavePath, pos, mpos, mdir, pattern.waveRange, pattern.waveWidth)
          inPredPath = ok and pathResult
        end
        if inPredPath then
          local maxWindow = AVOID_PREDICT_TTA_WINDOW or 3000
          local urgency = 1 - math.max(0, math.min(timeToAttack, maxWindow)) / maxWindow
          local pdanger = (pattern.dangerLevel or 1) * urgency * (confidence or 1)
          pdanger = pdanger + AVOID_PREDICT_DANGER * (confidence or 1)
          if timeToAttack < 800 then
            result.realTimeMetrics.imminentAttacks = result.realTimeMetrics.imminentAttacks + 1
            pdanger = pdanger * 1.3
          end
          threat.inWaveArc = true; threat.arcDistance = 0; threat.predicted = true
          threat.predConf = confidence; threat.predTTA = timeToAttack
          result.waveThreats = result.waveThreats + 1
          result.totalDanger = result.totalDanger + pdanger
        end
      else
        local inArc, arcDist = isInFrontArc(pos, mpos, mdir, 5, 1)
        if inArc then
          threat.inWaveArc = true; threat.arcDistance = arcDist
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
      end -- if mpos
    end
  end
  if confCount > 0 then
    result.realTimeMetrics.avgPredictionConfidence = totalConfidence / confCount
  end
  if usePrediction and MonsterAI and MonsterAI.isPositionDangerous then
    local isDangerous, dangerLevel = MonsterAI.isPositionDangerous(pos)
    if isDangerous then
      result.totalDanger = result.totalDanger + dangerLevel * 2
    end
  end
  return result
end

local function isDangerousPosition(pos, monsters)
  local analysis = analyzePositionDanger(pos, monsters)
  return analysis.totalDanger > 0, (analysis.waveThreats or 0) + (analysis.meleeThreats or 0)
end

local function countWalkableTiles(position)
  if PathUtils and PathUtils.findEveryPath then
    local reachable = PathUtils.findEveryPath(position, 1, { ignoreCreatures = false })
    if reachable then return #reachable end
  end
  local count = 0
  for i = 1, 8 do
    local dir = DIRECTIONS[i]
    local checkPos = { x = position.x + dir.x, y = position.y + dir.y, z = position.z }
    local safe = (PathUtils and PathUtils.isTileSafe and PathUtils.isTileSafe(checkPos))
      or (TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isTileSafe and TargetCore.PathSafety.isTileSafe(checkPos))
      or (function()
        local Client = getClient()
        local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile and g_map.getTile(checkPos))
        return tile and tile:isWalkable()
      end)()
    if safe then count = count + 1 end
  end
  return count
end

local function isPlayerTrapped(playerPos)
  return countWalkableTiles(playerPos) == 0
end

local function findSafeAdjacentTile(playerPos, monsters, currentTarget, scaling)
  local candidates = {}
  local currentAnalysis = analyzePositionDanger(playerPos, monsters, true)
  scaling = scaling or calculateScaling(#monsters)
  local dynamicDangerThreshold = avoidanceState.baseDangerThreshold * scaling.dangerThresholdMultiplier
  local immediateThreat = false
  if MonsterAI and MonsterAI.getImmediateThreat then
    local threatData = MonsterAI.getImmediateThreat()
    immediateThreat = threatData.immediateThreat or false
    if immediateThreat then dynamicDangerThreshold = dynamicDangerThreshold * 0.5 end
  end
  if not immediateThreat and currentAnalysis.totalDanger < dynamicDangerThreshold then
    return nil, 0
  end
  local threatDirections = {}
  if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.directions then
    for id, rtData in pairs(MonsterAI.RealTime.directions) do
      if rtData.facingPlayerSince then
        local dir = rtData.dir
        if DIR_VECTORS[dir] then
          threatDirections[#threatDirections + 1] = {
            vec = DIR_VECTORS[dir], turnRate = rtData.turnRate or 0,
            consecutiveChanges = rtData.consecutiveChanges or 0
          }
        end
      end
    end
  end
  local WEIGHTS = {
    DANGER = -25, TARGET_ADJACENT = 20, TARGET_CLOSE = 10, TARGET_FAR = -5,
    ESCAPE_ROUTES = 4, STABILITY = 8, PREVIOUS_SAFE = 15, STAY_BONUS = 10,
    PERPENDICULAR = 10, NOT_FACING = 8, LOW_TURN_RATE = 5, IMMINENT_SAFE = 12
  }
  for i = 1, 8 do
    local dir = DIRECTIONS[i]
    local checkPos = { x = playerPos.x + dir.x, y = playerPos.y + dir.y, z = playerPos.z }
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
      score = score + analysis.totalDanger * WEIGHTS.DANGER
      if analysis.waveThreats == 0 then score = score + WEIGHTS.STABILITY end
      if analysis.realTimeMetrics then
        local rtm = analysis.realTimeMetrics
        if rtm.monstersFacingPos == 0 then score = score + WEIGHTS.NOT_FACING end
        if rtm.imminentAttacks == 0 then score = score + WEIGHTS.IMMINENT_SAFE end
        if rtm.highTurnRateMonsters == 0 then score = score + WEIGHTS.LOW_TURN_RATE end
      end
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
            if threat.turnRate > 0.5 then
              perpBonus = perpBonus + (1 - normalizedDot) * 3
            end
          end
        end
        score = score + perpBonus / math.max(1, #threatDirections)
      end
      if currentTarget then
        local tpos = currentTarget:getPosition()
        local targetDist = math.max(math.abs(checkPos.x - tpos.x), math.abs(checkPos.y - tpos.y))
        if targetDist <= 1 then score = score + WEIGHTS.TARGET_ADJACENT
        elseif targetDist <= 3 then score = score + WEIGHTS.TARGET_CLOSE
        else score = score + (targetDist - 3) * WEIGHTS.TARGET_FAR end
      end
      local escapeRoutes = 0
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
        if escapeSafe then escapeRoutes = escapeRoutes + 1 end
      end
      score = score + escapeRoutes * WEIGHTS.ESCAPE_ROUTES
      if avoidanceState.lastSafePos then
        local isPreviousSafe = checkPos.x == avoidanceState.lastSafePos.x and checkPos.y == avoidanceState.lastSafePos.y
        if isPreviousSafe then score = score + WEIGHTS.PREVIOUS_SAFE end
      end
      candidates[#candidates + 1] = { pos = checkPos, score = score, danger = analysis.totalDanger, waveThreats = analysis.waveThreats }
    end
  end
  if #candidates == 0 then return nil, 0 end
  table.sort(candidates, function(a, b) return a.score > b.score end)
  local best = candidates[1]
  local currentScore = currentAnalysis.totalDanger * WEIGHTS.DANGER + WEIGHTS.STAY_BONUS
  local baseScoreThreshold = 12
  local dynamicScoreThreshold = baseScoreThreshold * scaling.scoreThresholdMultiplier
  if best.score > currentScore + dynamicScoreThreshold then return best.pos, best.score end
  return nil, 0
end

local function avoidWaveAttacks()
  local currentTime = now
  local playerPos = player:getPosition()
  local creatures = CreatureCache.getNearby(7) or {}
  local monsters = {}
  for i = 1, #creatures do
    local c = creatures[i]
    if c and c:isMonster() and not c:isDead() then monsters[#monsters + 1] = c end
  end
  local monsterCount = #monsters
  if monsterCount == 0 then
    avoidanceState.consecutiveMoves = 0; avoidanceState.lastSafePos = nil; avoidanceState.lastMonsterCount = 0
    return false
  end
  local scaling = calculateScaling(monsterCount)
  avoidanceState.lastMonsterCount = monsterCount
  local dynamicCooldown = avoidanceState.baseCooldown * scaling.cooldownMultiplier
  local maxConsecutive = avoidanceState.maxConsecutive
  if monsterCount >= 5 then maxConsecutive = maxConsecutive + 1 end
  if avoidanceState.consecutiveMoves >= maxConsecutive then
    local pauseDuration = 1200 * scaling.cooldownMultiplier
    if currentTime - avoidanceState.lastMove < pauseDuration then return false end
    avoidanceState.consecutiveMoves = 0
  end
  if currentTime - avoidanceState.lastMove < dynamicCooldown then return false end
  local dynamicStickiness = avoidanceState.baseStickiness * scaling.stickinessMultiplier
  if avoidanceState.lastSafePos then
    local atSafePos = playerPos.x == avoidanceState.lastSafePos.x and playerPos.y == avoidanceState.lastSafePos.y
    if atSafePos and currentTime - avoidanceState.lastMove < dynamicStickiness then
      local analysis = analyzePositionDanger(playerPos, monsters, true)
      local leaveThreshold = avoidanceState.baseDangerThreshold * scaling.dangerThresholdMultiplier + 0.5
      if analysis.totalDanger < leaveThreshold then return false end
    end
  end
  local currentTarget = target and target()
  local safePos, score = findSafeAdjacentTile(playerPos, monsters, currentTarget, scaling)
  if safePos then
    if MovementCoordinator and MovementCoordinator.canMove and MovementCoordinator.canMove() then
      avoidanceState.lastMove = currentTime; avoidanceState.lastSafePos = safePos
      avoidanceState.consecutiveMoves = avoidanceState.consecutiveMoves + 1
      TargetBot.walkTo(safePos, 2, {ignoreNonPathable = true, precision = 0})
      return true
    end
    return false
  end
  avoidanceState.consecutiveMoves = 0
  return false
end

local function rePosition(minTiles, config)
  minTiles = minTiles or 6
  if now - (lastCall or 0) < 500 then return end
  lastCall = now
  local playerPos = player:getPosition()
  local currentWalkable = countWalkableTiles(playerPos)
  local immediateThreat = false; local threatBoost = 0
  if MonsterAI and MonsterAI.getImmediateThreat then
    local threatData = MonsterAI.getImmediateThreat()
    immediateThreat = threatData.immediateThreat or false
    if immediateThreat then
      minTiles = math.max(3, minTiles - 2); threatBoost = threatData.totalThreat * 5
    end
  end
  if currentWalkable >= minTiles and not immediateThreat then return end
  local creatures = CreatureCache.getNearby(5) or {}
  local monsters = {}
  for i = 1, #creatures do
    local c = creatures[i]
    if c and c:isMonster() and not c:isDead() then monsters[#monsters + 1] = c end
  end
  local currentTarget = target and target()
  local bestPos = nil; local bestScore = -9999
  local anchorPos = config and config.anchor and anchorPosition
  local anchorRange = config and config.anchorRange or 5
  local threatDirections = {}
  if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.directions then
    for id, rtData in pairs(MonsterAI.RealTime.directions) do
      if rtData.facingPlayerSince then
        local dir = rtData.dir
        if DIR_VECTORS[dir] then threatDirections[#threatDirections + 1] = DIR_VECTORS[dir] end
      end
    end
  end
  local WEIGHTS = {
    WALKABLE = 15, DANGER = -22, TARGET_ADJ = 20, TARGET_CLOSE = 10, TARGET_FAR = -4,
    MOVE_COST = -4, CARDINAL = 3, STAY_BONUS = 15, PERPENDICULAR_ESCAPE = 12,
    AWAY_FROM_FACING = 8, LOW_TURN_RATE_ZONE = 6, PREDICTION_SAFE = 10
  }
  for dx = -2, 2 do
    for dy = -2, 2 do
      if dx ~= 0 or dy ~= 0 then
        local checkPos = { x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z }
        local shouldSkip = false
        if anchorPos then
          local anchorDist = math.max(math.abs(checkPos.x - anchorPos.x), math.abs(checkPos.y - anchorPos.y))
          if anchorDist > anchorRange then shouldSkip = true end
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
            local score = 0
            local walkable = countWalkableTiles(checkPos)
            score = score + walkable * WEIGHTS.WALKABLE
            local analysis = analyzePositionDanger(checkPos, monsters, true)
            score = score + analysis.totalDanger * WEIGHTS.DANGER
            if analysis.realTimeMetrics then
              if analysis.realTimeMetrics.monstersFacingPos == 0 then score = score + WEIGHTS.AWAY_FROM_FACING end
              if analysis.realTimeMetrics.imminentAttacks == 0 then score = score + WEIGHTS.PREDICTION_SAFE end
              if analysis.realTimeMetrics.highTurnRateMonsters == 0 then score = score + WEIGHTS.LOW_TURN_RATE_ZONE end
            end
            if #threatDirections > 0 then
              local moveVec = { x = dx, y = dy }
              local perpBonus = 0
              for _, threatVec in ipairs(threatDirections) do
                local dot = moveVec.x * threatVec.x + moveVec.y * threatVec.y
                local moveMag = math.sqrt(moveVec.x^2 + moveVec.y^2)
                local threatMag = math.sqrt(threatVec.x^2 + threatVec.y^2)
                if moveMag > 0 and threatMag > 0 then
                  local normalizedDot = math.abs(dot) / (moveMag * threatMag)
                  perpBonus = perpBonus + (1 - normalizedDot) * WEIGHTS.PERPENDICULAR_ESCAPE
                end
              end
              score = score + perpBonus / math.max(1, #threatDirections)
            end
            if currentTarget then
              local tpos = currentTarget:getPosition()
              local targetDist = math.max(math.abs(checkPos.x - tpos.x), math.abs(checkPos.y - tpos.y))
              if targetDist <= 1 then score = score + WEIGHTS.TARGET_ADJ
              elseif targetDist <= 3 then score = score + WEIGHTS.TARGET_CLOSE
              else score = score + (targetDist - 3) * WEIGHTS.TARGET_FAR end
            end
            local moveDist = math.abs(dx) + math.abs(dy)
            score = score + moveDist * WEIGHTS.MOVE_COST
            if dx == 0 or dy == 0 then score = score + WEIGHTS.CARDINAL end
            if immediateThreat then
              local safetyBonus = (8 - analysis.totalDanger) * 3
              score = score + safetyBonus
            end
            if score > bestScore then bestScore = score; bestPos = checkPos end
          end
        end
      end
    end
  end
  local currentScore = currentWalkable * WEIGHTS.WALKABLE + WEIGHTS.STAY_BONUS
  if bestPos and bestScore > currentScore + 20 then
    return CaveBot.GoTo(bestPos, 0)
  end
end

if EventBus then
  EventBus.on("monster:disappear", function(creature)
    if TargetBot.isOff() then return end
    avoidanceState.lastSafePos = nil
    avoidanceState.consecutiveMoves = 0
  end, 20)
  EventBus.on("player:move", function(newPos, oldPos)
    if TargetBot.isOff() then return end
    if avoidanceState.lastSafePos then
      local atSafe = newPos.x == avoidanceState.lastSafePos.x and newPos.y == avoidanceState.lastSafePos.y
      if not atSafe then avoidanceState.lastSafePos = nil end
    end
  end, 20)
  local monsterDirections = {}
  EventBus.on("creature:move", function(creature, oldPos)
    if TargetBot.isOff() then return end
    if not SC.isMonster(creature) then return end
    if SC.isDead(creature) then return end
    local id = SC.getId(creature)
    local newDir = nil
    newDir = SC.getDirection(creature)
    if not id or not newDir then return end
    local oldDir = monsterDirections[id]
    monsterDirections[id] = newDir
    if oldDir and oldDir ~= newDir then
      local playerPos = player and SC.getPosition(player) or nil
      local monsterPos = SC.getPosition(creature)
      if not playerPos or not monsterPos then return end
      local dist = math.max(math.abs(playerPos.x - monsterPos.x), math.abs(playerPos.y - monsterPos.y))
      if dist <= 5 then
        local inArc, arcDist = isInFrontArc(playerPos, monsterPos, newDir, 5, 1)
        if inArc then
          local monsters = {}
          local creatures = CreatureCache.getNearby(7) or {}
          for _, c in ipairs(creatures) do
            if SC.isMonster(c) and not SC.isDead(c) then monsters[#monsters + 1] = c end
          end
          if #monsters > 0 then
            local Client = getClient()
            local currentTarget = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
            local safePos, score = findSafeAdjacentTile(playerPos, monsters, currentTarget)
            if safePos and MovementCoordinator and MovementCoordinator.Intent then
              local confidence = 0.75 + (5 - dist) * 0.03
              local mName = SC.getName(creature) or "unknown"
              MovementCoordinator.Intent.register(
                MovementCoordinator.CONSTANTS.INTENT.WAVE_AVOIDANCE, safePos, confidence, "wave_direction_change",
                {triggered = "direction_change", monster = mName}
              )
            end
          end
        end
      end
    end
  end, 8)
  EventBus.on("monster:appear", function(creature)
    if TargetBot.isOff() then return end
    if not SC.isMonster(creature) then return end
    local okPpos, playerPos = pcall(function() return player and player:getPosition() end)
    local monsterPos = SC.getPosition(creature)
    if not okPpos or not playerPos or not monsterPos then return end
    local dist = math.max(math.abs(playerPos.x - monsterPos.x), math.abs(playerPos.y - monsterPos.y))
    if dist <= 2 then
      local walkable = countWalkableTiles(playerPos)
      if walkable < 5 then
        local monsters = {}
        local creatures = CreatureCache.getNearby(5) or {}
        for _, c in ipairs(creatures) do
          if SC.isMonster(c) and not SC.isDead(c) then monsters[#monsters + 1] = c end
        end
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
                if score > bestScore + 15 then bestScore = score; bestPos = checkPos end
              end
            end
          end
        end
        if bestPos and MovementCoordinator and MovementCoordinator.Intent then
          MovementCoordinator.Intent.register(
            MovementCoordinator.CONSTANTS.INTENT.REPOSITION, bestPos, 0.65, "reposition_monster_appear",
            {triggered = "monster_appear", walkable = walkable}
          )
        end
      end
    end
  end, 12)
  EventBus.on("monster:disappear", function(creature)
    if TargetBot.isOff() then return end
    if creature then
      local id = creature:getId()
      if id then monsterDirections[id] = nil end
    end
  end, 25)
  local debounceAvoid = (nExBot and nExBot.EventUtil and nExBot.EventUtil.debounce) and nExBot.EventUtil.debounce(200, function()
    schedule(60, function() pcall(avoidWaveAttacks) end)
  end)
  if debounceAvoid then
    EventBus.on("creature:appear", function(creature)
      if TargetBot.isOff() then return end
      if creature and creature:isMonster() then
        local p = player and player:getPosition()
        local cpos = creature and creature:getPosition()
        if p and cpos and math.max(math.abs(p.x-cpos.x), math.abs(p.y-cpos.y)) <= 7 then debounceAvoid() end
      end
    end, 10)
    EventBus.on("creature:move", function(creature, oldPos)
      if TargetBot.isOff() then return end
      if creature and creature:isMonster() then
        local p = player and player:getPosition()
        local cpos = creature and creature:getPosition()
        if p and cpos and math.max(math.abs(p.x-cpos.x), math.abs(p.y-cpos.y)) <= 7 then debounceAvoid() end
      end
    end, 10)
    EventBus.on("monster:disappear", function(creature)
      if TargetBot.isOff() then return end
      debounceAvoid()
    end, 10)
  end
end

nExBot.avoidWaveAttacks = avoidWaveAttacks
nExBot.isInFrontArc = isInFrontArc
nExBot.isDangerousPosition = isDangerousPosition
nExBot.analyzePositionDanger = analyzePositionDanger
nExBot.findSafeAdjacentTile = findSafeAdjacentTile
nExBot.rePosition = rePosition
nExBot.countWalkableTiles = countWalkableTiles
nExBot.isPlayerTrapped = isPlayerTrapped
nExBot.avoidanceState = avoidanceState
