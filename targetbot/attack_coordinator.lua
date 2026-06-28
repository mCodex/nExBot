-- TargetBot Attack Coordinator Module
-- Main attack loop, walk/chase/reposition, lure/pull system

local zChanging = nExBot.zChanging or function() return false end
local getClient = nExBot.Shared.getClient
local SC = SafeCreature or {}
local Dirs = Directions
local DIRECTIONS = (Dirs and Dirs.ADJACENT_OFFSETS) or {
  {x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0},
  {x = 1, y = -1}, {x = 1, y = 1}, {x = -1, y = 1}, {x = -1, y = -1}
}
local DIR_VECTORS = Directions.DIR_TO_OFFSET

local targetBotLure = false
local targetCount = 0
local delayValue = 0
local lureMax = 0
local anchorPosition = nil
local delayFrom = nil
local dynamicLureDelay = false
local smartPullState = { lastEval = 0, lowStreak = 0, highStreak = 0, active = false, lastChange = 0 }
local dynamicLureState = { lastTrigger = 0 }

local function countMonstersByRange(range)
  local specs = CreatureCache.getNearby(range, range)
  if not specs then return 0 end
  local count = 0
  for i = 1, #specs do
    local creature = specs[i]
    if creature and SC.isMonster(creature) and not SC.isDead(creature) then
      count = count + 1
    end
  end
  return count
end

local function safeGetMonsters(range)
  if SafeCall and SafeCall.getMonsters then
    return SafeCall.getMonsters(range) or 0
  end
  if getMonsters then
    return getMonsters(range) or 0
  end
  return countMonstersByRange(range)
end

local zigzagState = { blockUntil = 0, cooldown = 250 }

local function movementAllowed()
  local nowt = now or (os.time() * 1000)
  if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.isZigzagging then
    if MonsterAI.Scenario.isZigzagging() then
      if nowt < zigzagState.blockUntil then return false end
      zigzagState.blockUntil = nowt + zigzagState.cooldown
      return false
    end
  end
  if nExBot and nExBot.MovementCoordinator and nExBot.MovementCoordinator.canMove then
    return nExBot.MovementCoordinator.canMove()
  end
  return true
end

local function evaluateLureAndPull(creature, config, targets)
  if not creature or not config then return false end
  local cpos = creature:getPosition()
  local pos = player:getPosition()
  if not cpos or not pos then return false end
  local creatureHealth = creature:getHealthPercent()
  local killUnder = storage.extras.killUnder or 30
  local targetIsLowHealth = creatureHealth < killUnder
  local isTrapped = nExBot.isPlayerTrapped(pos)
  if config.anchor then
    if not anchorPosition or nExBot.distanceFromPlayer(anchorPosition) > (config.anchorRange or 5) * 2 then
      anchorPosition = pos
    end
  else
    anchorPosition = nil
  end
  if config.lureMin and config.lureMax and config.dynamicLure then
    targetBotLure = config.lureMin >= targets
    if targets >= config.lureMax then targetBotLure = false end
  end
  targetCount = targets
  delayValue = config.lureDelay
  lureMax = config.lureMax or 0
  dynamicLureDelay = config.dynamicLureDelay
  delayFrom = config.delayFrom
  if not targetIsLowHealth and not isTrapped then
    if config.smartPull then
      local nowt = now or (os.time() * 1000)
      if (nowt - smartPullState.lastEval) >= 300 then
        smartPullState.lastEval = nowt
        local screenMonsters = 0
        if EventTargeting and EventTargeting.getLiveMonsterCount then
          screenMonsters = EventTargeting.getLiveMonsterCount() or 0
        else
          screenMonsters = countMonstersByRange(7)
        end
        if screenMonsters == 0 then
          smartPullState.active = false
          smartPullState.lowStreak = 0
          smartPullState.highStreak = 0
        else
          local pullRange = config.smartPullRange or 2
          local pullMin = config.smartPullMin or 3
          local pullShape = config.smartPullShape or (nExBot.SHAPE and nExBot.SHAPE.CIRCLE) or 2
          local pullOff = pullMin + 1
          local nearbyMonsters = 0
          if getMonstersAdvanced then
            nearbyMonsters = SafeCall.global("getMonstersAdvanced", pullRange, pullShape) or 0
          elseif getMonsters then
            nearbyMonsters = getMonsters(pullRange) or 0
          else
            nearbyMonsters = countMonstersByRange(pullRange)
          end
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
    if not TargetBot.smartPullActive and TargetBot.canLure() and config.dynamicLure then
      local nowt = now or (os.time() * 1000)
      if targetBotLure and (nowt - (dynamicLureState.lastTrigger or 0)) > 700 then
        dynamicLureState.lastTrigger = nowt
        TargetBot.allowCaveBot(250)
        return true
      end
    end
    if config.closeLure and config.closeLureAmount then
      if safeGetMonsters(1) >= config.closeLureAmount then
        local asmActive = AttackStateMachine and AttackStateMachine.isActive and AttackStateMachine.isActive()
        if not asmActive then
          TargetBot.allowCaveBot(250)
        end
        return true
      end
    end
    if not config.dynamicLure then
      safeGetMonsters(7)
    end
  else
    TargetBot.smartPullActive = false
  end
  return false
end

local function calculateLureEligibility(config, targets)
  if not config then
    return { shouldLure = false, confidence = 0, reason = "no_config" }
  end
  if not config.dynamicLure then
    return { shouldLure = false, confidence = 0, reason = "disabled" }
  end
  local lureMin = config.lureMin or 3
  local lurMax = config.lureMax or 6
  if targets < lureMin then
    local deficit = lureMin - targets
    local confidence = 0.5 + (deficit / lureMin) * 0.3
    return { shouldLure = true, confidence = math.min(0.85, confidence), reason = "below_min", deficit = deficit }
  end
  if targets >= lurMax then
    return { shouldLure = false, confidence = 0.9, reason = "at_max" }
  end
  return { shouldLure = false, confidence = 0.6, reason = "sufficient" }
end

TargetBot.Creature.attack = function(params, targets, isLooting)
  if TargetBot then
    if TargetBot.canAttack and not TargetBot.canAttack() then return
    elseif TargetBot.explicitlyDisabled then return
    elseif TargetBot.isOn and not TargetBot.isOn() then return end
  end
  if player:isWalking() then lastWalk = now end
  local config = params.config
  local creature = params.creature
  local creaturePos = creature:getPosition()
  local playerPos = player:getPosition()
  if TargetBot.ActiveMovementConfig then
    TargetBot.ActiveMovementConfig.chase = config.chase or false
    TargetBot.ActiveMovementConfig.keepDistance = config.keepDistance or false
    TargetBot.ActiveMovementConfig.keepDistanceRange = config.keepDistanceRange or 4
    TargetBot.ActiveMovementConfig.finishKillThreshold = storage.extras and storage.extras.killUnder or 30
    TargetBot.ActiveMovementConfig.anchor = config.anchor and playerPos or nil
    TargetBot.ActiveMovementConfig.anchorRange = config.anchorRange or 5
  end
  local useNativeChase = config.chase and not config.keepDistance
  local Client = getClient()
  if ChaseController then
    ChaseController.setDesiredChase(useNativeChase)
    ChaseController.syncMode()
  elseif (Client and Client.setChaseMode) or (g_game and g_game.setChaseMode) then
    local desiredMode = useNativeChase and 1 or 0
    local currentMode = ClientService.getChaseMode() or -1
    if currentMode ~= desiredMode then
      if Client and Client.setChaseMode then Client.setChaseMode(desiredMode)
      elseif g_game and g_game.setChaseMode then g_game.setChaseMode(desiredMode) end
      if TargetCore and TargetCore.Native then TargetCore.Native.lastChaseMode = desiredMode end
    end
  end
  TargetBot.usingNativeChase = useNativeChase
  -- Skip reachability check if ASM is already locked on this target — the attack is working
  local creatureId = nil
  pcall(function() creatureId = creature:getId() end)
  local asmAlreadyAttacking = AttackStateMachine and AttackStateMachine.isActive and AttackStateMachine.isActive()
  local asmTargetId = nil
  if asmAlreadyAttacking then
    pcall(function() asmTargetId = AttackStateMachine.getTargetId and AttackStateMachine.getTargetId() end)
  end
  local sameTarget = asmAlreadyAttacking and creatureId == asmTargetId
  if not sameTarget and MonsterAI and MonsterAI.Reachability and MonsterAI.Reachability.validateTarget then
    if TargetBot then
      TargetBot.UnreachableTracker = TargetBot.UnreachableTracker or {
        entries = {}, ttl = 800, lastCleanup = 0, cleanupInterval = 2000
      }
    end
    local tracker = TargetBot and TargetBot.UnreachableTracker or nil
    local timeNow = now or (os.time() * 1000)
    local isValid, reason, path = MonsterAI.Reachability.validateTarget(creature)
    if isValid and tracker and creatureId then tracker.entries[creatureId] = nil end
    if not isValid then
      if reason == "no_path" or reason == "blocked_tile" then
        if tracker and creatureId then
          local entry = tracker.entries[creatureId]
          if not entry then
            entry = { firstSeen = timeNow, lastSeen = timeNow }
            tracker.entries[creatureId] = entry
          else
            entry.lastSeen = timeNow
          end
          if (timeNow - (entry.firstSeen or timeNow)) < tracker.ttl then return end
          if (timeNow - (tracker.lastCleanup or 0)) > tracker.cleanupInterval then
            for id, data in pairs(tracker.entries) do
              if (timeNow - (data.lastSeen or timeNow)) > tracker.cleanupInterval then tracker.entries[id] = nil end
            end
            tracker.lastCleanup = timeNow
          end
        end
        if AttackStateMachine and AttackStateMachine.isActive and AttackStateMachine.isActive() then
          pcall(AttackStateMachine.stop)
        else
          local Client2 = getClient()
          if Client2 and Client2.cancelAttackAndFollow then pcall(Client2.cancelAttackAndFollow)
          elseif g_game and g_game.cancelAttackAndFollow then pcall(g_game.cancelAttackAndFollow) end
        end
        if TargetBot.allowCaveBot then TargetBot.allowCaveBot(300) end
        return
      end
    end
  end
  local currentTarget = ClientService.getAttackingCreature()
  local currentTargetId = nil
  local wantedTargetId = nil
  pcall(function() currentTargetId = currentTarget and currentTarget:getId() end)
  pcall(function() wantedTargetId = creature and creature:getId() end)
  local needsAttack = (currentTargetId ~= wantedTargetId) or (not currentTarget)
  if needsAttack and wantedTargetId then
    local attackIssued = false
    if AttackStateMachine and AttackStateMachine.requestSwitch then
      local priority = params.priority or (params.config and params.config.priority) or 100
      attackIssued = AttackStateMachine.requestSwitch(creature, priority * 100)
    else
      log("[TargetBot] AttackStateMachine unavailable — skipping attack (no fallback)")
    end
    if EventTargeting and EventTargeting.CombatCoordinator then
      local dist = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
      if dist > 1 then pcall(function() EventTargeting.CombatCoordinator.registerChaseIntent(creature, creaturePos, dist) end) end
      pcall(function() EventTargeting.CombatCoordinator.pauseCaveBot() end)
    end
    if EventBus then pcall(function() EventBus.emit("targetbot/target_acquired", creature, creaturePos) end) end
    schedule(200, function()
      local atk = ClientService.getAttackingCreature()
    end)
  end
  local lureTriggered = evaluateLureAndPull(creature, config, targets)
  if not isLooting then
    if lureTriggered then
    elseif not useNativeChase then
      TargetBot.Creature.walk(creature, config, targets)
    elseif config.avoidAttacks or config.rePosition then
      TargetBot.Creature.walk(creature, config, targets)
    end
  end
  local mana = player:getMana()
end

TargetBot.Creature.walk = function(creature, config, targets)
  local cpos = creature:getPosition()
  local pos = player:getPosition()
  if TargetBot.isForceFollowActive and TargetBot.isForceFollowActive() then return end
  if config.anchor and not anchorPosition then anchorPosition = pos end
  local useCoordinator = MovementCoordinator and MovementCoordinator.Intent
  local creatures = CreatureCache.getNearby(7) or {}
  local monsters = {}
  for i = 1, #creatures do
    local c = creatures[i]
    if c and c:isMonster() and not c:isDead() then monsters[#monsters + 1] = c end
  end
  if MonsterAI and MonsterAI.updateAll then MonsterAI.updateAll() end
  local needsPrecisionControl = config.avoidAttacks or config.keepDistance
  local Client = getClient()
  if needsPrecisionControl then
    local hasSetChaseMode = (Client and Client.setChaseMode) or (g_game and g_game.setChaseMode)
    local hasGetChaseMode = (Client and Client.getChaseMode) or (g_game and g_game.getChaseMode)
    if hasSetChaseMode and hasGetChaseMode then
      local currentMode = ClientService.getChaseMode()
      if currentMode == 1 then
        if Client and Client.setChaseMode then Client.setChaseMode(0)
        elseif g_game and g_game.setChaseMode then g_game.setChaseMode(0) end
        TargetBot.usingNativeChase = false
      end
    end
    local hasCancelFollow = (Client and Client.cancelFollow) or (g_game and g_game.cancelFollow)
    local hasGetFollowingCreature = (Client and Client.getFollowingCreature) or (g_game and g_game.getFollowingCreature)
    if hasCancelFollow and hasGetFollowingCreature then
      local currentFollow = ClientService.getFollowingCreature()
      if currentFollow then
        ClientService.cancelFollow()
      end
    end
  elseif config.chase then
    local hasSetChaseMode = (Client and Client.setChaseMode) or (g_game and g_game.setChaseMode)
    local hasGetChaseMode = (Client and Client.getChaseMode) or (g_game and g_game.getChaseMode)
    if hasSetChaseMode and hasGetChaseMode then
      local currentMode = ClientService.getChaseMode()
      if currentMode ~= 1 then
        if Client and Client.setChaseMode then Client.setChaseMode(1)
        elseif g_game and g_game.setChaseMode then g_game.setChaseMode(1) end
        TargetBot.usingNativeChase = true
      end
    end
  end
  if config.avoidAttacks then
    local safePos, safeScore = nExBot.findSafeAdjacentTile(pos, monsters, creature)
    if safePos then
      local confidence = 0.5
      local currentDanger = nExBot.analyzePositionDanger(pos, monsters)
      if currentDanger.waveThreats >= 2 then confidence = 0.85
      elseif currentDanger.waveThreats == 1 and currentDanger.meleeThreats >= 2 then confidence = 0.80
      elseif currentDanger.totalDanger >= 4 then confidence = 0.75
      elseif currentDanger.totalDanger >= 2 then confidence = 0.70 end
      if useCoordinator then
        MovementCoordinator.avoidWave(safePos, confidence)
      else
        if confidence >= 0.70 then
          nExBot.avoidWaveAttacks()
          return true
        end
      end
    end
  end
  if targetIsLowHealth and pathLen > 1 then
    local confidence = 0.55
    if creatureHealth < 10 then confidence = 0.85
    elseif creatureHealth < 15 then confidence = 0.75
    elseif creatureHealth < 20 then confidence = 0.70 end
    if useCoordinator then
      MovementCoordinator.finishKill(cpos, confidence)
    else
      if confidence >= 0.70 then
        if movementAllowed() then return TargetBot.walkTo(cpos, 10, {ignoreNonPathable = true, precision = 1}) end
      end
    end
  end
  if SpellOptimizer and config.optimizeSpellPosition and #monsters >= 2 then
    local spellShape = config.spellShape or SpellOptimizer.CONSTANTS.SHAPE.ADJACENT
    local optPos, score, confidence, details = SpellOptimizer.findOptimalPosition(
      spellShape, monsters, { minMonsters = 2, avoidDanger = config.avoidAttacks }
    )
    if optPos and details and details.monstersHit >= 2 then
      if details.distance > 0 and confidence >= 0.6 then
        if useCoordinator then MovementCoordinator.positionForSpell(optPos, confidence, "AoE") end
      end
    end
  end
  if config.keepDistance then
    local keepRange = config.keepDistanceRange or 4
    local currentDist = pathLen
    if currentDist ~= keepRange and currentDist ~= keepRange + 1 then
      local dx = cpos.x - pos.x
      local dy = cpos.y - pos.y
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist > 0 then
        local targetDist = keepRange
        local ratio = targetDist / dist
        local keepPos = {
          x = math.floor(cpos.x - dx * ratio + 0.5), y = math.floor(cpos.y - dy * ratio + 0.5), z = pos.z
        }
        local anchorValid = true
        if config.anchor and anchorPosition then
          local anchorDist = math.max(math.abs(keepPos.x - anchorPosition.x), math.abs(keepPos.y - anchorPosition.y))
          anchorValid = anchorDist <= (config.anchorRange or 5)
        end
        if anchorValid then
          local confidence = 0.55
          if currentDist < keepRange then confidence = 0.7 end
          if useCoordinator then
            MovementCoordinator.keepDistance(keepPos, confidence)
          else
            local walkParams = { ignoreNonPathable = true, marginMin = keepRange, marginMax = keepRange + 1 }
            if config.anchor and anchorPosition then walkParams.maxDistanceFrom = {anchorPosition, config.anchorRange or 5} end
            if movementAllowed() then return TargetBot.walkTo(cpos, 10, walkParams) end
          end
        end
      end
    end
  end
  if config.rePosition and not isTrapped then
    local currentWalkable = nExBot.countWalkableTiles(pos)
    local threshold = config.rePositionAmount or 5
    if currentWalkable < threshold then
      local betterPos = nil
      local bestScore = currentWalkable * 12
      for dx = -2, 2 do
        for dy = -2, 2 do
          if dx ~= 0 or dy ~= 0 then
            local checkPos = {x = pos.x + dx, y = pos.y + dy, z = pos.z}
            local tileSafe = (TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isTileSafe)
              and TargetCore.PathSafety.isTileSafe(checkPos)
              or (function()
                local C = getClient()
                local t = (C and C.getTile) and C.getTile(checkPos) or (g_map and g_map.getTile and g_map.getTile(checkPos))
                local hasCreature = t and t.hasCreature and t:hasCreature()
                return t and t:isWalkable() and not hasCreature
              end)()
            if tileSafe then
              local anchorValid = true
              if config.anchor and anchorPosition then
                local anchorDist = math.max(math.abs(checkPos.x - anchorPosition.x), math.abs(checkPos.y - anchorPosition.y))
                anchorValid = anchorDist <= (config.anchorRange or 5)
              end
              if anchorValid then
                local walkable = nExBot.countWalkableTiles(checkPos)
                local score = walkable * 12
                local analysis = nExBot.analyzePositionDanger(checkPos, monsters)
                score = score - analysis.totalDanger * 15
                if score > bestScore + 10 then bestScore = score; betterPos = checkPos end
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
          if confidence >= 0.5 then return CaveBot.GoTo(betterPos, 0) end
        end
      end
    end
  end
  local chaseDistanceThreshold = config.chaseDistanceThreshold or 2
  local directDist = math.max(math.abs(pos.x - cpos.x), math.abs(pos.y - cpos.y))
  local chaseExecuted = false
  if config.chase and not config.keepDistance and pathLen > 1 and directDist > chaseDistanceThreshold then
    local nativeChaseMayWork = false
    local Client2 = getClient()
    local hasGetChaseMode = (Client2 and Client2.getChaseMode) or (g_game and g_game.getChaseMode)
    local hasIsAttacking = (Client2 and Client2.isAttacking) or (g_game and g_game.isAttacking)
    if hasGetChaseMode and hasIsAttacking then
      local isAttacking = ClientService.isAttacking()
      local chaseMode = ClientService.getChaseMode()
      nativeChaseMayWork = isAttacking and chaseMode == 1
    end
    local anchorValid = true
    local hasAnchorConstraint = false
    if config.anchor and anchorPosition then
      hasAnchorConstraint = true
      local anchorDist = math.max(math.abs(cpos.x - anchorPosition.x), math.abs(cpos.y - anchorPosition.y))
      anchorValid = anchorDist <= (config.anchorRange or 5)
    end
    local needsCustomChase = not nativeChaseMayWork or hasAnchorConstraint
    if needsCustomChase and anchorValid then
      if player and player.autoWalk and not player:isWalking() then
        pcall(function() player:autoWalk(cpos) end)
        chaseExecuted = true
        return true
      end
    elseif nativeChaseMayWork and anchorValid then
      chaseExecuted = true
      return true
    end
  end
  if config.faceMonster then
    local dx = cpos.x - pos.x
    local dy = cpos.y - pos.y
    local dist = math.max(math.abs(dx), math.abs(dy))
    if dist == 1 and math.abs(dx) == 1 and math.abs(dy) == 1 then
      local candidates = {
        {x = pos.x + dx, y = pos.y, z = pos.z}, {x = pos.x, y = pos.y + dy, z = pos.z}
      }
      for i = 1, 2 do
        local tileSafe = (TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isTileSafe)
          and TargetCore.PathSafety.isTileSafe(candidates[i])
          or (function()
            local C = getClient()
            local t = (C and C.getTile) and C.getTile(candidates[i]) or (g_map and g_map.getTile and g_map.getTile(candidates[i]))
            local hasCreature = t and t.hasCreature and t:hasCreature()
            return t and t:isWalkable() and not hasCreature
          end)()
        if tileSafe then
          local anchorValid = true
          if config.anchor and anchorPosition then
            local anchorDist = math.max(math.abs(candidates[i].x - anchorPosition.x), math.abs(candidates[i].y - anchorPosition.y))
            anchorValid = anchorDist <= (config.anchorRange or 5)
          end
          if anchorValid then
            if useCoordinator then MovementCoordinator.faceMonster(candidates[i], 0.45)
            else if movementAllowed() then return TargetBot.walkTo(candidates[i], 2, {ignoreNonPathable = true}) end end
            break
          end
        end
      end
    elseif dist <= 1 then
      local dir = player:getDirection()
      if dx == 1 and dir ~= 1 then turn(1)
      elseif dx == -1 and dir ~= 3 then turn(3)
      elseif dy == 1 and dir ~= 2 then turn(2)
      elseif dy == -1 and dir ~= 0 then turn(0) end
    end
  end
  if useCoordinator then
    local success, reason = MovementCoordinator.tick()
    if success then return true end
    local fallbackDirectDist = math.max(math.abs(pos.x - cpos.x), math.abs(pos.y - cpos.y))
    local fallbackChaseThreshold = config.chaseDistanceThreshold or 2
    if config.chase and not config.keepDistance and pathLen > 1 and fallbackDirectDist > fallbackChaseThreshold then
      local nativeChaseMayWork = false
      local Client = getClient()
      local hasGetChaseMode = (Client and Client.getChaseMode) or (g_game and g_game.getChaseMode)
      local hasIsAttacking = (Client and Client.isAttacking) or (g_game and g_game.isAttacking)
      if hasGetChaseMode and hasIsAttacking then
        local isAttacking = ClientService.isAttacking()
        local chaseMode = ClientService.getChaseMode()
        nativeChaseMayWork = isAttacking and chaseMode == 1
      end
      if nativeChaseMayWork then return true end
      if not player:isWalking() then
        local anchorValid = true
        if config.anchor and anchorPosition then
          local anchorDist = math.max(math.abs(cpos.x - anchorPosition.x), math.abs(cpos.y - anchorPosition.y))
          anchorValid = anchorDist <= (config.anchorRange or 5)
        end
        if anchorValid then
          if player and player.autoWalk then pcall(function() player:autoWalk(cpos) end); return true end
        end
      end
    end
  end
end

onPlayerPositionChange(function(newPos, oldPos)
  if zChanging() then return end
  if not CaveBot or not CaveBot.isOff or CaveBot.isOff() then return end
  if not TargetBot or not TargetBot.isOff or TargetBot.isOff() then return end
  if not lureMax then return end
  if storage.TargetBotDelayWhenPlayer then return end
  if not dynamicLureDelay then return end
  local targetThreshold = delayFrom or lureMax * 0.5
  if targetCount < targetThreshold or not (target and target()) then return end
  CaveBot.delay(delayValue or 0)
end)

if EventBus then
  local lastLureState = { active = false, time = 0 }
  EventBus.on("targetbot/target_count_change", function(newCount, oldCount)
    if not TargetBot or not TargetBot.isOn or not TargetBot.isOn() then return end
    local activeConfig = TargetBot.ActiveMovementConfig
    if not activeConfig then return end
    local eligibility = calculateLureEligibility(activeConfig, newCount)
    if eligibility.shouldLure ~= lastLureState.active then
      lastLureState.active = eligibility.shouldLure
      lastLureState.time = now
      if eligibility.shouldLure then
        pcall(function() EventBus.emit("targetbot/lure_start", { reason = eligibility.reason, confidence = eligibility.confidence, deficit = eligibility.deficit }) end)
        if MovementCoordinator and MovementCoordinator.Intent then
          local playerPos = player and player:getPosition()
          if playerPos then
            MovementCoordinator.Intent.register(MovementCoordinator.CONSTANTS.INTENT.LURE, playerPos, eligibility.confidence, "lure_event", { triggered = "target_count", targets = newCount, deficit = eligibility.deficit })
          end
        end
      else
        pcall(function() EventBus.emit("targetbot/lure_stop", { reason = eligibility.reason, targets = newCount }) end)
      end
    end
  end, 15)
  EventBus.on("monster:disappear", function(creature)
    if TargetBot.isOff() then return end
    if not creature then return end
    local monsterCount = 0
    if MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby then
      local nearby = MovementCoordinator.MonsterCache.getNearby(7)
      monsterCount = #nearby
    end
    pcall(function() EventBus.emit("targetbot/target_count_change", monsterCount, monsterCount + 1) end)
  end, 18)
  EventBus.on("monster:appear", function(creature)
    if TargetBot.isOff() then return end
    if not creature then return end
    local playerPos = player and player:getPosition()
    local creaturePos = creature:getPosition()
    if not playerPos or not creaturePos then return end
    local dist = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
    if dist <= 7 then
      local monsterCount = 0
      if MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby then
        local nearby = MovementCoordinator.MonsterCache.getNearby(7)
        monsterCount = #nearby
      end
      pcall(function() EventBus.emit("targetbot/target_count_change", monsterCount, monsterCount - 1) end)
    end
  end, 18)
  local lastPullState = false
  EventBus.on("targetbot/combat_start", function(creature, data)
    if TargetBot.isOff() then return end
    schedule(100, function()
      if TargetBot and TargetBot.smartPullActive ~= lastPullState then
        lastPullState = TargetBot.smartPullActive
        if TargetBot.smartPullActive then pcall(function() EventBus.emit("targetbot/pull_active", { creature = creature, time = now }) end) end
      end
    end)
  end, 12)
  EventBus.on("targetbot/combat_end", function()
    if TargetBot.isOff() then return end
    if lastPullState then
      lastPullState = false
      pcall(function() EventBus.emit("targetbot/pull_inactive") end)
    end
  end, 12)
end

nExBot.calculateLureEligibility = calculateLureEligibility
