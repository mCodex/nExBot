-- TargetBot Events Module
-- All EventBus handlers from target.lua

local getClient = nExBot.Shared.getClient

local SC = SafeCreature or {}

local I = TargetBot.__internals

if EventBus then
  -- invalidate + recalc on creature changes
  EventBus.on("monster:appear", function(creature)
    if TargetBot.isOff() then return end
    if creature then I.debouncedInvalidateAndRecalc() end
  end, 20)
  EventBus.on("monster:disappear", function(creature)
    if TargetBot.isOff() then return end
    I.debouncedInvalidateAndRecalc()
  end, 20)
  EventBus.on("creature:move", function(creature, oldPos)
    if TargetBot.isOff() then return end
    local okMonster, isMonster = pcall(function() return creature and creature:isMonster() end)
    if okMonster and isMonster then I.debouncedInvalidateAndRecalc() end
  end, 20)
  EventBus.on("monster:health", function(creature, percent)
    if TargetBot.isOff() then return end
    I.debouncedInvalidateAndRecalc()
  end, 20)
  EventBus.on("player:move", function(newPos, oldPos)
    if TargetBot.isOff() then return end
    if newPos and oldPos and newPos.z ~= oldPos.z then return end
    I.debouncedInvalidateAndRecalc()
  end, 10)
  EventBus.on("player:z_change_settled", function()
    if TargetBot.isOff() then return end
    if MonsterAI and MonsterAI.Reachability then
      MonsterAI.Reachability.clearCache()
      MonsterAI.Reachability.blockedCreatures = {}
    end
    I.invalidateCache()
    if I.recalculateBestTarget then I.recalculateBestTarget() end
  end, 5)
  EventBus.on("combat:target", function(creature, oldCreature)
    if TargetBot.isOff() then return end
    I.debouncedInvalidateAndRecalc()
  end, 20)
  -- Follow player integration
  EventBus.on("followplayer/force_follow", function(leaderPos, distance)
    if TargetBot.isOff() then return end
    pcall(function()
      I.followPlayerForceMode = true
      I.followPlayerForceExpiry = now + 2500
      TargetBot.allowCaveBot(100)
    end)
  end, 100)
  EventBus.on("followplayer/enabled", function(playerName)
    if TargetBot.isOff() then return end
    pcall(function() I.followPlayerForceMode = false; I.followPlayerForceExpiry = 0 end)
  end, 80)
  EventBus.on("followplayer/disabled", function()
    if TargetBot.isOff() then return end
    pcall(function() I.followPlayerForceMode = false; I.followPlayerForceExpiry = 0 end)
  end, 80)
  -- CreatureCache handlers
  EventBus.on("monster:appear", function(creature)
    if TargetBot.isOff() then return end
    I.updateCreatureInCache(creature)
  end, 50)
  EventBus.on("monster:disappear", function(creature)
    if TargetBot.isOff() then return end
    I.removeCreatureFromCache(creature)
  end, 50)
  EventBus.on("monster:health", function(creature, percent)
    if TargetBot.isOff() then return end
    if percent <= 0 then I.removeCreatureFromCache(creature) end
  end, 80)
  EventBus.on("player:move", function(newPos, oldPos)
    if TargetBot.isOff() then return end
    if newPos and oldPos and newPos.z ~= oldPos.z then
      I.invalidateCache()
      if AttackStateMachine and AttackStateMachine.clearSkipList then AttackStateMachine.clearSkipList() end
      return
    end
    I.clearPaths()
    I.invalidateCache()
  end, 60)
  -- combat:target with deferred combat_end
  local lastCombatTargetId = nil
  local _combatEndPending = nil
  local COMBAT_END_GRACE_MS = 1200
  EventBus.on("combat:target", function(creature, oldCreature)
    if TargetBot.isOff() then return end
    I.invalidateCache()
    local newId = creature and creature:getId() or nil
    if newId ~= lastCombatTargetId then
      if creature then
        if _combatEndPending then removeEvent(_combatEndPending); _combatEndPending = nil end
        if UnifiedStorage then UnifiedStorage.set("targetbot.combatActive", true) else storage.targetbotCombatActive = true end
        pcall(function() EventBus.emit("targetbot/combat_start", creature, { id = newId, pos = creature:getPosition() }) end)
        lastCombatTargetId = newId
      else
        if _combatEndPending then return end
        _combatEndPending = schedule(COMBAT_END_GRACE_MS, function()
          _combatEndPending = nil
          if AttackStateMachine and AttackStateMachine.isActive and AttackStateMachine.isActive() then return end
          if UnifiedStorage then UnifiedStorage.set("targetbot.combatActive", false) else storage.targetbotCombatActive = false end
          pcall(function() EventBus.emit("targetbot/combat_end") end)
          lastCombatTargetId = nil
        end)
      end
    end
  end, 70)
  -- player:health emergency detection
  EventBus.on("player:health", function(health, maxHealth, oldHealth, oldMax)
    if TargetBot.isOff() then return end
    local cfg = (UnifiedStorage and UnifiedStorage.get("targetbot.priority")) or (ProfileStorage and ProfileStorage.get and ProfileStorage.get('targetPriority')) or {}
    local threshold = cfg and cfg.emergencyHP or 25
    local percent = 100
    if maxHealth and maxHealth > 0 then percent = math.floor(health / maxHealth * 100) end
    local currentEmergency = (UnifiedStorage and UnifiedStorage.get("targetbot.emergency")) or storage.targetbotEmergency
    if percent <= threshold and not currentEmergency then
      if UnifiedStorage then UnifiedStorage.set("targetbot.emergency", true) else storage.targetbotEmergency = true end
      pcall(function() EventBus.emit("targetbot/emergency", percent) end)
    elseif percent > threshold and currentEmergency then
      if UnifiedStorage then UnifiedStorage.set("targetbot.emergency", false) else storage.targetbotEmergency = false end
      pcall(function() EventBus.emit("targetbot/emergency_cleared", percent) end)
    end
  end, 90)
  -- Event-driven movement intents (keepDistance, chase)
  EventBus.on("creature:move", function(creature, oldPos)
    if TargetBot and TargetBot.isOn and not TargetBot.isOn() then return end
    local isMonster = creature and SC.isMonster(creature)
    if not isMonster then return end
    local Client = getClient()
    local target = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
    if not target then return end
    local cid = SC.getId(creature)
    local tid = SC.getId(target)
    if not cid or not tid or cid ~= tid then return end
    local config = TargetBot.ActiveMovementConfig
    if not config then return end
    local playerPos = SC.getPosition(player)
    local creaturePos = SC.getPosition(creature)
    if not playerPos or not creaturePos then return end
    local dist = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
    if config.keepDistance then
      local keepRange = config.keepDistanceRange or 4
      if dist < keepRange - 1 or dist > keepRange + 2 then
        local dx = creaturePos.x - playerPos.x; local dy = creaturePos.y - playerPos.y
        local currentDist = math.sqrt(dx * dx + dy * dy)
        if currentDist > 0 then
          local ratio = keepRange / currentDist
          local keepPos = { x = math.floor(creaturePos.x - dx * ratio + 0.5), y = math.floor(creaturePos.y - dy * ratio + 0.5), z = playerPos.z }
          local anchorValid = true
          if config.anchor then
            local anchorDist = math.max(math.abs(keepPos.x - config.anchor.x), math.abs(keepPos.y - config.anchor.y))
            anchorValid = anchorDist <= (config.anchorRange or 5)
          end
          if anchorValid and MovementCoordinator and MovementCoordinator.Intent then
            local confidence = 0.55; if dist < keepRange - 1 then confidence = 0.70 end
            MovementCoordinator.Intent.register(MovementCoordinator.CONSTANTS.INTENT.KEEP_DISTANCE, keepPos, confidence, "keepdist_event", {triggered = "target_move", currentDist = dist, targetDist = keepRange})
          end
        end
      end
    end
    if config.chase and not config.keepDistance and dist > 1 then
      local confidence = 0.62; if dist <= 3 then confidence = 0.68 end; if dist >= 5 then confidence = 0.75 end
      local anchorValid = true
      if config.anchor then
        local anchorDist = math.max(math.abs(creaturePos.x - config.anchor.x), math.abs(creaturePos.y - config.anchor.y))
        anchorValid = anchorDist <= (config.anchorRange or 5)
      end
      if anchorValid and MovementCoordinator and MovementCoordinator.Intent then
        MovementCoordinator.Intent.register(MovementCoordinator.CONSTANTS.INTENT.CHASE, creaturePos, confidence, "chase_target_move", {triggered = "target_move", dist = dist})
      end
    end
  end, 15)
  -- Event-driven finish kill
  EventBus.on("monster:health", function(creature, percent)
    if TargetBot.isOff() then return end
    if not creature then return end
    local Client = getClient()
    local target = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
    if not target then return end
    local cid = SC.getId(creature)
    local tid = SC.getId(target)
    if not cid or not tid or cid ~= tid then return end
    local config = TargetBot.ActiveMovementConfig
    local threshold = config and config.finishKillThreshold or 30
    if percent and percent < threshold and percent > 0 then
      local playerPos = SC.getPosition(player)
      local creaturePos = SC.getPosition(creature)
      if not playerPos or not creaturePos then return end
      local dist = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
      if dist > 1 and MovementCoordinator and MovementCoordinator.Intent then
        local confidence = 0.65; if percent < 15 then confidence = 0.80 end; if percent < 10 then confidence = 0.90 end
        MovementCoordinator.Intent.register(MovementCoordinator.CONSTANTS.INTENT.FINISH_KILL, creaturePos, confidence, "finish_kill_hp", {triggered = "health_change", hp = percent, dist = dist})
      end
    end
  end, 25)
  EventBus.on("combat:target", function(creature, oldCreature)
    if TargetBot.isOff() then return end
    if creature and MovementCoordinator then
      pcall(function()
        local pos = SC.getPosition(creature)
        EventBus.emit("targetbot/target_acquired", creature, pos)
      end)
    end
  end, 65)
  -- Chase mode enforcement
  I.ChaseModeEnforcer = I.ChaseModeEnforcer or {
    enabled = false, lastEnforcedMode = nil, lastEnforceTime = 0, enforceCooldown = 100,
    shouldChase = false, keepDistance = false
  }
  local CME = I.ChaseModeEnforcer
  I.enforceChaseModeNow = function()
    if not TargetBot.isOn or not TargetBot.isOn() then CME.enabled = false; return end
    local currentTime = now or (os.time() * 1000)
    if (currentTime - CME.lastEnforceTime) < CME.enforceCooldown then return end
    local config = TargetBot.ActiveMovementConfig
    if config then CME.shouldChase = config.chase == true; CME.keepDistance = config.keepDistance == true end
    local desiredMode = 0
    if CME.shouldChase and not CME.keepDistance then desiredMode = 1 end
    local Client = getClient()
    local isAttacking = (Client and Client.isAttacking) and Client.isAttacking() or (g_game and g_game.isAttacking and g_game.isAttacking())
    if not isAttacking then CME.enabled = false; return end
    CME.enabled = true
    local currentMode = (Client and Client.getChaseMode) and Client.getChaseMode() or (g_game and g_game.getChaseMode and g_game.getChaseMode()) or 0
    if currentMode ~= desiredMode then
      if Client and Client.setChaseMode then Client.setChaseMode(desiredMode); CME.lastEnforcedMode = desiredMode; CME.lastEnforceTime = currentTime
        if EventBus then pcall(function() EventBus.emit("targetbot/chase_mode_enforced", desiredMode, desiredMode == 1 and "chase" or "stand") end) end
      elseif g_game and g_game.setChaseMode then g_game.setChaseMode(desiredMode); CME.lastEnforcedMode = desiredMode; CME.lastEnforceTime = currentTime
        if EventBus then pcall(function() EventBus.emit("targetbot/chase_mode_enforced", desiredMode, desiredMode == 1 and "chase" or "stand") end) end
      end
    end
  end
  EventBus.on("targetbot/target_acquired", function(creature, creaturePos)
    if TargetBot.isOff() then return end; pcall(function() I.enforceChaseModeNow() end)
  end, 60)
  EventBus.on("targetbot/combat_start", function(creature, data)
    if TargetBot.isOff() then return end; pcall(function() I.enforceChaseModeNow() end)
  end, 60)
  EventBus.on("targetbot/combat_end", function()
    if TargetBot.isOff() then return end; pcall(function() CME.enabled = false end)
  end, 60)
  EventBus.on("player:move", function(newPos, oldPos)
    if TargetBot.isOff() then return end
    if newPos and oldPos and newPos.z ~= oldPos.z then return end
    if CME.enabled then pcall(function() I.enforceChaseModeNow() end) end
  end, 5)
  EventBus.on("creature:move", function(creature, oldPos)
    if TargetBot.isOff() then return end; if not CME.enabled then return end
    local Client = getClient()
    local target = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
    if not target then return end
    local cid = SC.getId(creature)
    local tid = SC.getId(target)
    if cid and tid and cid == tid then pcall(function() I.enforceChaseModeNow() end) end
  end, 5)
end

-- OTClient native chase mode hook
TargetBot.ChaseModeEnforcer = I.ChaseModeEnforcer
TargetBot.enforceChaseModeNow = I.enforceChaseModeNow
if g_game and type(g_game) == "table" then
  pcall(function()
    connect(g_game, { onChaseModeChange = function(newMode)
      if not CME.enabled then return end
      if not TargetBot.isOn or not TargetBot.isOn() then return end
      local config = TargetBot.ActiveMovementConfig
      if config then CME.shouldChase = config.chase == true; CME.keepDistance = config.keepDistance == true end
      local desiredMode = 0
      if CME.shouldChase and not CME.keepDistance then desiredMode = 1 end
      if newMode ~= desiredMode then
        schedule(50, function()
          if CME.enabled and TargetBot.isOn and TargetBot.isOn() then I.enforceChaseModeNow() end
        end)
      end
    end})
  end)
end

-- Non-EventBus fallbacks
if not EventBus then
  if onCreatureAppear then onCreatureAppear(function(creature)
    if creature then I.invalidateCache(); if I.debouncedInvalidateAndRecalc then I.debouncedInvalidateAndRecalc() end end
  end) end
  if onCreatureDisappear then onCreatureDisappear(function(creature)
    I.invalidateCache(); if I.debouncedInvalidateAndRecalc then I.debouncedInvalidateAndRecalc() end
  end) end
  if onCreatureMove then onCreatureMove(function(creature, oldPos)
    local okMonster, isMonster = pcall(function() return creature and creature:isMonster() end)
    if okMonster and isMonster then I.invalidateCache(); if I.debouncedInvalidateAndRecalc then I.debouncedInvalidateAndRecalc() end end
  end) end
end

-- Relogin recovery
if onPlayerHealthChange then onPlayerHealthChange(function(healthPercent)
  if healthPercent and healthPercent > 0 then
    I.attackWatchdog.attempts = 0; I.attackWatchdog.lastForce = 0
    local storedEnabled = nil
    if UnifiedStorage then storedEnabled = UnifiedStorage.get("targetbot.enabled") end
    if storedEnabled == nil then storedEnabled = storage.targetbotEnabled end
    if storedEnabled ~= true then return end
    if TargetBot and TargetBot.explicitlyDisabled then return end
    if TargetBot and TargetBot.isOn then
      I.reloginRecovery.active = true; I.reloginRecovery.endTime = now + I.reloginRecovery.duration; I.reloginRecovery.lastAttempt = 0
      local Client = getClient()
      player = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer()) or player
      I.debouncedInvalidateAndRecalc()
      if storedEnabled == true and not TargetBot.isOn() and not TargetBot.explicitlyDisabled then pcall(function() TargetBot.setOn() end) end
      if I.ui and I.ui.status and I.ui.status.right then I.setStatusRight("Recovering...") end
      if I.targetbotMacro then
        local function attemptRecovery()
          if TargetBot and TargetBot.explicitlyDisabled then I.reloginRecovery.active = false; return end
          local storedEnabled2 = (UnifiedStorage and UnifiedStorage.get("targetbot.enabled"))
          if storedEnabled2 == nil then storedEnabled2 = storage.targetbotEnabled end
          if storedEnabled2 == true and TargetBot.isOn() then
            pcall(I.targetbotMacro)
            local ok2, best2 = pcall(function() return I.recalculateBestTarget() end)
            if ok2 then
              local count = I.getMonsterCount()
              if I.ui and I.ui.status and I.ui.status.right then
                if best2 and best2.creature then I.setStatusRight("Recovering ("..tostring(count)..") best: "..best2.creature:getName())
                else I.setStatusRight("Recovering ("..tostring(count)..")") end
              end
              if best2 and best2.creature then pcall(function() TargetBot.requestAttack(best2.creature, "relogin_recovery") end) end
            end
          end
        end
        schedule(200, attemptRecovery)
        schedule(1000, attemptRecovery)
        schedule(5000, attemptRecovery)
      end
    end
  end
end) end

-- EventTargeting EventBus handlers (from event_targeting.lua)
if EventBus then
  EventBus.on("player:z_change_settled", function()
    if TargetBot.isOff() then return end
    if EventTargeting then EventTargeting.refreshLiveCount() end
  end, 3)
  local etDebounce = (nExBot and nExBot.EventUtil and nExBot.EventUtil.debounce) and nExBot.EventUtil.debounce(150, function()
    if EventTargeting then EventTargeting.refreshLiveCount() end
  end)
  if etDebounce then
    EventBus.on("monster:appear", function(creature)
      if TargetBot.isOff() then return end; etDebounce()
    end, 30)
    EventBus.on("monster:disappear", function(creature)
      if TargetBot.isOff() then return end; etDebounce()
    end, 30)
    EventBus.on("monster:health", function(creature, percent)
      if TargetBot.isOff() then return end; etDebounce()
    end, 35)
    EventBus.on("creature:move", function(creature, oldPos)
      if TargetBot.isOff() then return end
      local ok, isMonster = pcall(function() return creature and creature:isMonster() end)
      if ok and isMonster then etDebounce() end
    end, 35)
  end
  EventBus.on("player:move", function(newPos, oldPos)
    if TargetBot.isOff() then return end
    local ppos = player and player:getPosition()
    if ppos and EventTargeting then EventTargeting.refreshLiveCount() end
  end, 8)
  EventBus.on("combat:target", function(creature, oldCreature)
    if TargetBot.isOff() then return end
    if EventTargeting and EventTargeting.CombatCoordinator then
      EventTargeting.CombatCoordinator.onTargetChanged(creature, oldCreature)
    end
  end, 30)
  EventBus.on("player:health", function(health, maxHealth, oldHealth, oldMax)
    if TargetBot.isOff() then return end
    if EventTargeting and EventTargeting.CombatCoordinator then
      EventTargeting.CombatCoordinator.onPlayerHealthChange(health, maxHealth, oldHealth, oldMax)
    end
  end, 30)
end
