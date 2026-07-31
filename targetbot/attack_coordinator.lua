-- TargetBot Attack Coordinator Module
-- Main attack loop, walk/chase/reposition, lure/pull system

local getClient = nExBot.Shared.getClient
local SC = SafeCreature or {}
local Dirs = Directions
local DIRECTIONS = (Dirs and Dirs.ADJACENT_OFFSETS) or {
  {x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0},
  {x = 1, y = -1}, {x = 1, y = 1}, {x = -1, y = 1}, {x = -1, y = -1}
}
local DIR_VECTORS = Directions.DIR_TO_OFFSET


local function isTileSafe(pos)
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isTileSafe then
    return TargetCore.PathSafety.isTileSafe(pos)
  end
  return nExBot.Shared.isTileSafe(pos)
end

local anchorPosition = nil

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
  local Intelligence = nExBot.Intelligence
  if not Intelligence then return false end
  local safe = not targetIsLowHealth and not isTrapped
  local generations = Intelligence.lifecycle.generations
  local snapshot = Intelligence.currentSnapshot or { visibleMonsters = {} }
  local ids = {}
  for _, monster in ipairs(snapshot.visibleMonsters or {}) do ids[#ids + 1] = monster.id end
  local proposals = {}
  if config.dynamicLure then
    local proposal = Intelligence.dynamicLure:update({
      snapshotGeneration = generations.snapshot,
      creatures = ids,
      minCount = config.lureMin or 3,
      maxCount = config.lureMax or 6,
      safe = safe,
    }, { generations = generations, now = now })
    if proposal and TargetBot.canLure() then proposals[#proposals + 1] = proposal end
  end
  if config.smartPull then
    Intelligence.pull.enterDistance = config.smartPullRange or 5
    local proposal = Intelligence.pull:update({
      snapshotGeneration = generations.snapshot,
      participantId = creature:getId(),
      distance = math.max(math.abs(pos.x - cpos.x), math.abs(pos.y - cpos.y)),
      safe = safe,
    }, { generations = generations, now = now })
    if proposal then proposals[#proposals + 1] = proposal end
  end
  local selected = Intelligence.decisions:select(proposals, generations, {
    healthRatio = player:getHealth() / math.max(1, player:getMaxHealth()),
    playerPosition = pos,
  })
  TargetBot.smartPullActive = selected and selected.action == "pull" or false
  Intelligence.blackboard:write("currentLureState", Intelligence.dynamicLure.state, { owner = "DynamicLure" })
  Intelligence.blackboard:write("currentPullState", Intelligence.pull.state, { owner = "PullSystem" })
  if selected and MovementCoordinator and MovementCoordinator.executeTactical then
    Intelligence.events:publish("TacticalActionSelected", selected, { source = "IntelligenceDecisionEngine" })
    return MovementCoordinator.executeTactical(selected)
  end
  return false
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
  if MovementCoordinator then MovementCoordinator.setChaseMode(useNativeChase) end
  TargetBot.usingNativeChase = useNativeChase
  local ASM = AttackFSM or AttackStateMachine
  -- Skip reachability check if ASM is already locked on this target — the attack is working
  local creatureId = nil
  pcall(function() creatureId = creature:getId() end)
  local asmAlreadyAttacking = ASM and ASM.isActive and ASM.isActive()
  local asmTargetId = nil
  if asmAlreadyAttacking then
    pcall(function() asmTargetId = ASM.getTargetId and ASM.getTargetId() end)
  end
  local sameTarget = asmAlreadyAttacking and creatureId == asmTargetId
  if not sameTarget and MonsterAI and MonsterAI.Reachability and MonsterAI.Reachability.validateTarget then
    local isValid = MonsterAI.Reachability.validateTarget(creature)
    if not isValid then
      return
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
    local requestSwitch = ASM and (ASM.requestSwitch or ASM.requestAttack)
    if requestSwitch then
      local priority = params.priority or (params.config and params.config.priority) or 100
      attackIssued = requestSwitch(creature, priority * 100)
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
  if not useCoordinator then return false end
  local creatures = BotCore.Creatures.getNearby(7) or {}
  local monsters = {}
  for i = 1, #creatures do
    local c = creatures[i]
    if c and c:isMonster() and not c:isDead() then monsters[#monsters + 1] = c end
  end
  if MonsterAI and MonsterAI.updateAll then MonsterAI.updateAll() end
  local creatureHealth = creature and creature:getHealthPercent() or 100
  local killUnder = storage.extras.killUnder or 30
  local targetIsLowHealth = creatureHealth < killUnder
  local isTrapped = nExBot.isPlayerTrapped and nExBot.isPlayerTrapped(pos) or false
  local pathLen = 0
  local path = findPath(pos, cpos, 10, {ignoreNonPathable = true, ignoreCreatures = true})
  if path then pathLen = #path end
  if config.avoidAttacks then
    local safePos, safeScore = nExBot.findSafeAdjacentTile(pos, monsters, creature)
    if safePos then
      local confidence = 0.5
      local currentDanger = nExBot.analyzePositionDanger(pos, monsters)
      if currentDanger.waveThreats >= 2 then confidence = 0.85
      elseif currentDanger.waveThreats == 1 and currentDanger.meleeThreats >= 2 then confidence = 0.80
      elseif currentDanger.totalDanger >= 4 then confidence = 0.75
      elseif currentDanger.totalDanger >= 2 then confidence = 0.70 end
      MovementCoordinator.avoidWave(safePos, confidence)
    end
  end
  if targetIsLowHealth and pathLen > 1 then
    local confidence = 0.55
    if creatureHealth < 10 then confidence = 0.85
    elseif creatureHealth < 15 then confidence = 0.75
    elseif creatureHealth < 20 then confidence = 0.70 end
    MovementCoordinator.finishKill(cpos, confidence)
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
          MovementCoordinator.keepDistance(keepPos, confidence)
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
            local tileSafe = isTileSafe(checkPos)
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
        MovementCoordinator.reposition(betterPos, confidence)
      end
    end
  end
  local chaseDistanceThreshold = config.chaseDistanceThreshold or 2
  local directDist = math.max(math.abs(pos.x - cpos.x), math.abs(pos.y - cpos.y))
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
      MovementCoordinator.Intent.register(MovementCoordinator.CONSTANTS.INTENT.CHASE, cpos, 0.7, "target_chase")
    elseif nativeChaseMayWork and anchorValid then
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
        local tileSafe = isTileSafe(candidates[i])
        if tileSafe then
          local anchorValid = true
          if config.anchor and anchorPosition then
            local anchorDist = math.max(math.abs(candidates[i].x - anchorPosition.x), math.abs(candidates[i].y - anchorPosition.y))
            anchorValid = anchorDist <= (config.anchorRange or 5)
          end
          if anchorValid then
            MovementCoordinator.faceMonster(candidates[i], 0.45)
            break
          end
        end
      end
    elseif dist <= 1 then
      MovementCoordinator.faceMonster(cpos, 0.6)
    end
  end
  if useCoordinator then
    local success, reason = MovementCoordinator.tick()
    if success then return true end
    return false, reason
  end
end
