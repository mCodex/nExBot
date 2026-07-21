nExBot.Intelligence = nExBot.Intelligence or {}
local Intelligence = nExBot.Intelligence

if not Intelligence.lifecycle then
  Intelligence.lifecycle = IntelligenceLifecycle.new()
  Intelligence.events = IntelligenceEventAggregator.new()
  Intelligence.blackboard = TacticalBlackboard.new({ keys = {
    currentTarget = { owner = "TargetBot" },
    currentRouteObjective = { owner = "CaveBot" },
    currentMovementIntent = { owner = "MovementCoordinator" },
    currentAttackIntent = { owner = "AttackStateMachine" },
    currentLureState = { owner = "DynamicLure" },
    currentPullState = { owner = "PullSystem" },
    currentWavePrediction = { owner = "WaveModel" },
    recentEmergency = { owner = "SafetyEnvelope" },
  } })
  Intelligence.snapshots = IntelligenceSnapshotBuilder.new()
  Intelligence.features = IntelligenceFeaturePipeline.new()
  Intelligence.safety = IntelligenceDefaultSafety.new()
  Intelligence.decisions = IntelligenceDecisionEngine.new({ safetyEnvelope = Intelligence.safety })
  Intelligence.route = IntelligenceCaveBotRouteState.new()
  Intelligence.models = IntelligenceModelCatalog.registerAll(IntelligenceModelRegistry.new())
  Intelligence.flags = IntelligenceFeatureFlags.new({ replay = true, diagnostics = true, learning = true, neuralModel = false, routeAlternatives = true })
  Intelligence.replay = IntelligenceReplay.new()
  Intelligence.calibration = IntelligenceCalibration.new()
  Intelligence.budgets = IntelligencePerformanceBudget.new(5)
  Intelligence.dynamicLure = IntelligenceDynamicLureState.new()
  Intelligence.pull = IntelligencePullState.new()
  Intelligence.waveBeam = IntelligenceWaveBeamState.new()
  Intelligence.navigationCosts = IntelligenceNavigationCost.new()
  Intelligence.memory = IntelligenceTacticalMemory.new()
  Intelligence.sessionId = ""
  Intelligence.huntId = ""
  local EpisodeBase = nExBot.IntelligenceEpisodeBase or dofile("core/intelligence/episodes/episode_base.lua")
  local EncounterTracker = nExBot.IntelligenceEncounterTracker or dofile("core/intelligence/episodes/encounter_tracker.lua")
  local LootEpisodeTracker = nExBot.IntelligenceLootEpisodeTracker or dofile("core/intelligence/episodes/loot_episode_tracker.lua")
  local RouteSegmentTracker = nExBot.IntelligenceRouteSegmentTracker or dofile("core/intelligence/episodes/route_segment_tracker.lua")
  local HuntTracker = nExBot.IntelligenceHuntTracker or dofile("core/intelligence/episodes/hunt_tracker.lua")
  Intelligence.episodeBase = EpisodeBase.new({})
  Intelligence.encounterTracker = EncounterTracker.new({
    episodeBase = Intelligence.episodeBase,
  })
  Intelligence.lootEpisodeTracker = LootEpisodeTracker.new({
    episodeBase = Intelligence.episodeBase,
  })
  Intelligence.routeSegmentTracker = RouteSegmentTracker.new({
    episodeBase = Intelligence.episodeBase,
  })
  Intelligence.huntTracker = HuntTracker.new({
    episodeBase = Intelligence.episodeBase,
  })
  Intelligence.contextAdjustments = IntelligenceContextAdjustment.new()
  Intelligence.latency = IntelligenceLatencyClassifier.new()
  Intelligence.horizons = IntelligenceHorizonCounters.new()
  Intelligence.resources = IntelligenceResourceObserver.new()
  Intelligence.loot = IntelligenceLootObserver.new()
  Intelligence.reward = IntelligenceRewardModel.new()
  Intelligence.metrics = IntelligenceMetrics.new()
  Intelligence.scheduler = IntelligenceAdaptiveScheduler.new()
  Intelligence.nextSnapshotAt = 0
  Intelligence.uiState = { lifecycle = {}, route = {}, models = {}, metrics = {}, diagnostics = {}, safety = {} }
  Intelligence.ui = IntelligenceUiPresenter.new({ state = Intelligence.uiState, commands = {
    setOperatingMode = function(args) return Intelligence.models:setMode(args.name, args.mode) end,
    pauseRoute = function(args) return Intelligence.route:pause(args and args.reason or "user") end,
    resumeRoute = function() return Intelligence.route:resume() end,
    resetModels = { destructive = true, run = function()
      for _, entry in pairs(Intelligence.models.entries) do entry.model:reset() end
      return true
    end },
    exportReplay = function(args)
      if args and args.path then return Intelligence.replay:exportFile(args.path, g_resources, json) end
      return Intelligence.replay:exportDocument()
    end,
    exportDiagnostics = function(args) return IntelligenceBotDoctor.inspect(args or IntelligenceBotDoctor.capture(Intelligence)) end,
  } })

  function Intelligence.migrateConfiguration()
    if not UnifiedStorage or not UnifiedStorage.get or UnifiedStorage.get("intelligence.migrated") then return false end
    local unified = UnifiedStorage.get()
    local root = "/bot/" .. tostring(BotConfigName or "") .. "/"
    local profiles = IntelligenceConfigMigration.readProfiles(g_resources, json, root, {
      targetbot = UnifiedStorage.get("targetbot.selectedConfig"),
      cavebot = UnifiedStorage.get("cavebot.selectedConfig"),
    })
    local migrated = IntelligenceConfigMigration.migrate({ unified = unified,
      targetbotProfile = profiles.targetbot, cavebotProfile = profiles.cavebot })
    migrated.migrated = true
    UnifiedStorage.batch({ version = 5, intelligence = migrated })
    Intelligence.flags = IntelligenceFeatureFlags.new(migrated.flags)
    return true
  end

  function Intelligence.loadModels()
    if not UnifiedStorage or not UnifiedStorage.get then return false end
    local states = UnifiedStorage.get("intelligence.models.states") or {}
    for name, saved in pairs(states) do
      if Intelligence.models.entries[name] then Intelligence.models:restore(name, saved) end
    end
    Intelligence.contextAdjustments:restore(UnifiedStorage.get("intelligence.contexts") or {})
    return true
  end

  function Intelligence.persistModels()
    if not UnifiedStorage or not UnifiedStorage.set then return false end
    local states = {}
    for _, name in ipairs(IntelligenceModelCatalog.names()) do states[name] = Intelligence.models:serialize(name) end
    UnifiedStorage.set("intelligence.models.states", states)
    UnifiedStorage.set("intelligence.contexts", Intelligence.contextAdjustments:serialize())
    return true
  end

  function Intelligence.contextKey(selection)
    if type(selection) ~= "table" then return nil end
    local route = UnifiedStorage and UnifiedStorage.get and UnifiedStorage.get("cavebot.selectedConfig") or ""
    local profile = selection.config and (selection.config.name or selection.config.pattern) or ""
    if route == "" or profile == "" then return nil end
    return tostring(route) .. "|" .. tostring(profile)
  end

  function Intelligence.applyContextAdjustment(proposal, selection)
    local key = Intelligence.contextKey(selection)
    if not key then return proposal end
    local adjustment, evidence = Intelligence.contextAdjustments:get(key)
    if not Intelligence.optionalEnabled("learning") then adjustment, evidence.actionable = 0, false end
    proposal.contextKey, proposal.learningEvidence = key, evidence
    proposal.learningAdjustment = adjustment
    proposal.priority = proposal.basePriority * (1 + adjustment)
    return proposal
  end

  local function syncGenerations()
    local generations = Intelligence.lifecycle.generations
    Intelligence.events:setGenerations(generations)
    Intelligence.blackboard:setGenerations(generations)
  end

  function Intelligence.optionalEnabled(name)
    return Intelligence.budgets:enabled(name) and Intelligence.flags:enabled(name)
  end

  local function observeModels(names, success, weight)
    if not Intelligence.optionalEnabled("learning") or type(success) ~= "boolean" then return false end
    for _, name in ipairs(names) do
      local prediction = Intelligence.models:predict(name)
      if prediction then
        Intelligence.models:get(name).model:evaluate(success)
        Intelligence.calibration:observe(prediction.probability, success)
      end
      Intelligence.models:observe(name, { success = success, weight = weight or 1 })
      Intelligence.models:get(name).model:update()
    end
    return true
  end

  function Intelligence.navigationKey(position)
    if type(position) ~= "table" then return nil end
    return table.concat({ position.x or "?", position.y or "?", position.z or "?" }, ":")
  end

  function Intelligence.navigationPenalty(position, timestamp, baseCost)
    local entry = Intelligence.models:get("NavigationCostModel")
    local key = Intelligence.navigationKey(position)
    if not key or entry.mode ~= IntelligenceModelRegistry.ACTIVE or type(baseCost) ~= "number" then return 0 end
    return math.min(Intelligence.navigationCosts:get(key, timestamp or nExBot.Shared.nowMs()), math.max(0, baseCost) * 0.1)
  end

  local function schedulerState()
    local combat = UnifiedStorage and UnifiedStorage.get and UnifiedStorage.get("targetbot.combatActive") == true
    local emergency = UnifiedStorage and UnifiedStorage.get and UnifiedStorage.get("targetbot.emergency") == true
    return {
      routeActive = Intelligence.route.state == "running" or Intelligence.route.state == "recovering",
      combat = combat,
      emergency = emergency,
      overBudget = Intelligence.budgets.nextDegradation > 1,
      optional = true,
    }
  end

  function Intelligence.initialize()
    if not Intelligence.lifecycle:initialize() then return false end
    syncGenerations()
    Intelligence.events:publish("LifecycleInitialized", {}, { source = "IntelligenceLifecycle" })
    return true
  end

  function Intelligence.terminate()
    if not Intelligence.lifecycle.active then return false end
    Intelligence.events:publish("LifecycleTerminating", {}, { source = "IntelligenceLifecycle" })
    Intelligence.persistModels()
    Intelligence.lifecycle:terminate()
    syncGenerations()
    return true
  end

  function Intelligence.advanceGeneration(name)
    local generation = Intelligence.lifecycle:advance(name)
    syncGenerations()
    return generation
  end

  function Intelligence.tick()
    if not Intelligence.lifecycle.active then return false end
    local now = nExBot.Shared.nowMs()
    if now < Intelligence.nextSnapshotAt then return false end
    Intelligence.nextSnapshotAt = now + Intelligence.scheduler:interval(schedulerState())
    local started = os.clock()
    local generation = Intelligence.lifecycle:advance("snapshot")
    syncGenerations()
    Intelligence.currentSnapshot = Intelligence.snapshots:build({ generation = generation })
    Intelligence.events:publish("analytics:snapshot", { generation = generation }, {
      source = "SnapshotBuilder",
      snapshotGeneration = generation,
    })
    local elapsed = (os.clock() - started) * 1000
    Intelligence.metrics:sample("snapshot.time_ms", elapsed)
    local degraded = Intelligence.budgets:record(elapsed)
    if degraded then
      Intelligence.flags:set(degraded, false)
      Intelligence.metrics:increment("budget.degraded." .. degraded)
    end
    Intelligence.uiState.lifecycle = { active = Intelligence.lifecycle.active, generation = Intelligence.lifecycle:generation("lifecycle") }
    Intelligence.uiState.route = { state = Intelligence.route.state, generation = Intelligence.route.generation, waypointIndex = Intelligence.route.waypointIndex }
    Intelligence.uiState.metrics = Intelligence.metrics:snapshot()
    return true
  end

  if UnifiedTick and UnifiedTick.register then
    UnifiedTick.register("intelligence_orchestrator", {
      interval = 50,
      priority = UnifiedTick.Priority.HIGH,
      group = "intelligence",
      handler = Intelligence.tick,
    })
  end

  if EventBus and EventBus.on then
    local observationId = 0
    local function metadata(prefix)
      observationId = observationId + 1
      return {
        timestamp = nExBot.Shared.nowMs(), latencyClass = "unknown",
        observationQuality = 0.7, confidence = 0.8,
        correlationId = prefix .. ":" .. observationId,
      }
    end
    EventBus.on("heal:spell", function() Intelligence.resources:observe({ healingCasts = 1 }, metadata("heal_spell")) end)
    EventBus.on("heal:potion", function(_, potionType)
      local values = potionType == "mana" and { manaPotions = 1 } or { hpPotions = 1 }
      Intelligence.resources:observe(values, metadata("heal_potion"))
    end)
    local function runeUsed() Intelligence.resources:observe({ runes = 1 }, metadata("rune")) end
    EventBus.on("attack:aoe_rune", runeUsed)
    EventBus.on("attack:single_rune", runeUsed)
    EventBus.on("analytics:session:start", function(data)
      Intelligence.sessionId = data and data.sessionId or tostring(os.time())
      Intelligence.events:publish("analytics:session_started", { active = true, sourceEvent = "analytics:session:start" }, { source = "TacticalIntelligence" })
    end)
    EventBus.on("analytics:session:end", function()
      Intelligence.sessionId = ""
      Intelligence.huntId = ""
      Intelligence.events:publish("analytics:session_ended", { active = false, sourceEvent = "analytics:session:end" }, { source = "TacticalIntelligence" })
    end)
    EventBus.on("combat:target_changed", function(data)
      if Intelligence.optionalEnabled("learning") then
        Intelligence.encounterTracker:start({
          encounterId = data.encounterId,
          sessionId = Intelligence.sessionId,
          huntId = Intelligence.huntId,
          targetInstanceId = data.targetInstanceId,
        })
      end
    end)
    EventBus.on("loot:received", function(data)
      if Intelligence.optionalEnabled("learning") then
        Intelligence.lootEpisodeTracker:start({
          lootEpisodeId = data.lootEpisodeId,
          sessionId = Intelligence.sessionId,
          huntId = Intelligence.huntId,
          corpseId = data.corpseId,
          encounterId = data.encounterId,
        })
      end
    end)
    local function onLootObserved(monsterName, items)
  local observed = metadata("loot")
  observed.monsterId = monsterName
  observed.itemsAvailable = items ~= "" and 1 or 0
  observed.itemsCaptured = items ~= "" and 1 or 0
  Intelligence.loot:observe(observed)
  Intelligence.events:publish("analytics:loot_observed", observed, {
    source = "loot:received",
    snapshotGeneration = Intelligence.lifecycle:generation("snapshot"),
    combatGeneration = Intelligence.lifecycle:generation("combat"),
  })
end

local function classifyAttackTransition(state, previous, reason)
  if reason == "target_killed" then
    return "TargetKilled"
  elseif reason == "unreachable" or reason == "path_failed" or reason == "retry_exhausted" then
    return "AttackCancelled"
  elseif state == "ENGAGING" then
    return "AttackStarted"
  elseif state == "LOCKED" then
    return "AttackCompleted"
  end
  return "AttackCancelled"
end

EventBus.on("loot:received", onLootObserved)
EventBus.on("attacksm:state_changed", function(state, previous, reason)
 local eventType = classifyAttackTransition(state, previous, reason)
 Intelligence.events:publish(eventType, { state = state, previous = previous, reason = reason }, {
 source = "AttackStateMachine",
 combatGeneration = Intelligence.lifecycle:generation("combat"),
 })
 if Intelligence.optionalEnabled("replay") then
 Intelligence.replay:record({ outcome = { type = eventType, reason = reason } })
 end
 if eventType == "TargetKilled" then
 observeModels({ "MonsterBehaviorModel", "TargetUtilityModel" }, true)
 elseif eventType == "AttackCompleted" then
 observeModels({ "MonsterBehaviorModel", "TargetUtilityModel", "TargetSwitchModel" }, true)
 elseif eventType == "AttackCancelled" and reason then
 observeModels({ "MonsterBehaviorModel", "TargetUtilityModel", "TargetSwitchModel" }, false)
 end
 if Intelligence.optionalEnabled("learning") and eventType == "TargetKilled" and Intelligence.activeCombatContext then
 Intelligence.contextAdjustments:observe(Intelligence.activeCombatContext, true, nExBot.Shared.nowMs())
 elseif Intelligence.optionalEnabled("learning") and eventType == "AttackCancelled" and Intelligence.activeCombatContext and (reason == "unreachable" or reason == "path_failed" or reason == "retry_exhausted") then
 Intelligence.contextAdjustments:observe(Intelligence.activeCombatContext, false, nExBot.Shared.nowMs())
 end
end)

EventBus.on("movement:outcome", function(success, reason, intent)
      Intelligence.events:publish(success and "MovementCompleted" or "MovementInterrupted", {
        reason = reason,
        intent = intent,
      }, { source = "MovementCoordinator" })
      local models = { "RouteReliabilityModel", "NavigationCostModel" }
      local action = intent and (intent.action or (intent.data and intent.data.action))
      if action == "lure" then models[#models + 1] = "LureSafetyModel"
      elseif action == "pull" then models[#models + 1] = "PullContinuationModel"
      elseif action == "wave" then models[#models + 1] = "WavePredictionModel" end
      observeModels(models, success == true)
      local position = intent and (intent.position or (intent.data and intent.data.destination))
      local key = Intelligence.navigationKey(position)
      if key then Intelligence.navigationCosts:observe(key, success and -1 or 2, 0.8, nExBot.Shared.nowMs()) end
    end, 100)
  end

  if onGameStart then onGameStart(function()
    Intelligence.initialize()
    Intelligence.migrateConfiguration()
    Intelligence.loadModels()
    if EventBus and EventBus.emit then EventBus.emit("player:login") end
  end) end
  if onGameEnd then onGameEnd(function()
    if EventBus and EventBus.emit then EventBus.emit("player:logout") end
    Intelligence.terminate()
  end) end

  local player = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer()
  if player then Intelligence.initialize(); Intelligence.migrateConfiguration(); Intelligence.loadModels() end
end

return Intelligence
