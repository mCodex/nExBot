local _presenterOk, _presenterResult = pcall(dofile, "core/intelligence/ui/ui_presenter.lua")
local Presenter = (_presenterOk and type(_presenterResult) == "table") and _presenterResult or IntelligenceUiPresenter

nExBot = nExBot or {}

local Tactical = nExBot.TacticalIntelligence or {
  refreshMs = 200,
}
Tactical.__index = Tactical

local function nowMs()
  return nExBot.Shared and nExBot.Shared.nowMs and nExBot.Shared.nowMs() or os.time() * 1000
end

local function copy(value, seen)
  if type(value) ~= "table" then
    return value
  end
  seen = seen or {}
  if seen[value] then
    return seen[value]
  end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do
    result[copy(key, seen)] = copy(item, seen)
  end
  return result
end

local function countKeys(value)
  local count = 0
  if type(value) ~= "table" then
    return count
  end
  for _ in pairs(value) do
    count = count + 1
  end
  return count
end

local function hasEntries(value)
  if type(value) ~= "table" then
    return false
  end
  for _ in pairs(value) do
    return true
  end
  return false
end

-- Dirty section tracking for incremental projections
local SectionTracker = {}
SectionTracker.__index = SectionTracker

function SectionTracker.new()
  return setmetatable({ dirty = {} }, SectionTracker)
end

function SectionTracker:markDirty(section)
  self.dirty[section] = true
end

local sectionTracker = SectionTracker.new()

-- EventBus integration for dirty tracking
if EventBus then
  EventBus.on("player:health", function()
    sectionTracker:markDirty("overview")
    sectionTracker:markDirty("hunt")
  end)
  
  EventBus.on("player:mana", function()
    sectionTracker:markDirty("overview")
    sectionTracker:markDirty("hunt")
  end)
  
  EventBus.on("creature:appear", function()
    sectionTracker:markDirty("monsters")
    sectionTracker:markDirty("targeting")
  end)
  
  EventBus.on("creature:disappear", function()
    sectionTracker:markDirty("monsters")
    sectionTracker:markDirty("targeting")
  end)
  
  EventBus.on("monster:health", function()
    sectionTracker:markDirty("monsters")
    sectionTracker:markDirty("targeting")
  end)
  
  EventBus.on("combat:target", function()
    sectionTracker:markDirty("targeting")
    sectionTracker:markDirty("overview")
  end)
  
  EventBus.on("player:damage", function()
    sectionTracker:markDirty("hunt")
    sectionTracker:markDirty("overview")
  end)
  
  EventBus.on("container:update", function()
    sectionTracker:markDirty("resources")
  end)
  
  EventBus.on("intelligence:pipelineEvent", function()
    sectionTracker:markDirty("pipeline")
    sectionTracker:markDirty("overview")
  end)
  
  EventBus.on("intelligence:modelUpdate", function()
    sectionTracker:markDirty("models")
  end)
  
  EventBus.on("cavebot:waypoint_arrived", function()
    sectionTracker:markDirty("routes")
    sectionTracker:markDirty("overview")
  end)
end

local function tail(values, limit)
  local result = {}
  if type(values) ~= "table" then
    return result
  end
  local start = math.max(1, #values - (tonumber(limit) or 0) + 1)
  for index = start, #values do
    result[#result + 1] = copy(values[index])
  end
  return result
end

local function getAnalytics()
  local huntMetrics = nExBot.HuntMetrics
  if not huntMetrics then
    return { active = false, elapsedMs = 0, metrics = {}, trends = {} }
  end
  local instance = huntMetrics.instance or huntMetrics
  return {
    active = instance.isActive and instance.isActive() or false,
    elapsedMs = instance.getElapsed and instance:getElapsed() or 0,
    metrics = instance.getMetrics and instance:getMetrics() or {},
    trends = instance.getTrends and instance:getTrends() or {},
  }
end

local function getBlackboardValue(intelligence, key)
  local blackboard = intelligence and intelligence.blackboard
  if blackboard and type(blackboard.read) == "function" then
    return copy(blackboard:read(key))
  end
end

local function modelSnapshots(intelligence)
  local names = IntelligenceModelCatalog and IntelligenceModelCatalog.names and IntelligenceModelCatalog.names() or {}
  local items = {}
  local summary = { total = 0, actionable = 0, shadow = 0, observing = 0, off = 0, samples = 0, pending = 0 }

  for _, name in ipairs(names) do
    local entry = intelligence.models and intelligence.models.entries and intelligence.models.entries[name]
    local diagnostics = entry and entry.model and entry.model.diagnostics and entry.model:diagnostics() or {}
    local mode = entry and entry.mode or "OFF"
    local minEvidence = entry and entry.definition and (entry.definition.minEvidence or entry.definition.minimumSamples) or 0
    local actionable = mode == "ACTIVE" and (diagnostics.samples or 0) >= minEvidence
    local whyNotActionable

    if mode == "OFF" then
      whyNotActionable = "disabled"
      summary.off = summary.off + 1
    elseif mode == "OBSERVE" then
      whyNotActionable = "observe_only"
      summary.observing = summary.observing + 1
    elseif mode == "SHADOW" then
      whyNotActionable = (diagnostics.samples or 0) < minEvidence and "waiting_for_evidence" or "shadow_mode"
      summary.shadow = summary.shadow + 1
    else
      summary.active = (summary.active or 0) + 1
    end

    summary.total = summary.total + 1
    summary.samples = summary.samples + (diagnostics.samples or 0)
    summary.pending = summary.pending + (diagnostics.pending or 0)
    if actionable then
      summary.actionable = summary.actionable + 1
    end

    items[#items + 1] = {
      name = name,
      capability = diagnostics.capability or name,
      mode = mode,
      samples = diagnostics.samples or 0,
      pending = diagnostics.pending or 0,
      confidence = diagnostics.confidence or 0,
      accuracy = diagnostics.accuracy,
      memoryUse = diagnostics.memoryBudgetBytes,
      cpuCost = diagnostics.cpuBudgetMicros,
      promotionStatus = mode,
      whyNotActionable = whyNotActionable,
      lastUpdate = diagnostics.lastUpdate,
      rejectedObservations = diagnostics.rejectedObservations,
      contexts = diagnostics.contexts or {},
      actionable = actionable,
    }
  end

  return { items = items, summary = summary }
end

local function resourceSnapshot(intelligence)
  local totals = intelligence.resources and intelligence.resources.totals and intelligence.resources:totals() or {}
  local recent = intelligence.resources and intelligence.resources.recent and intelligence.resources:recent() or {}
  local loot = intelligence.loot and intelligence.loot.recent and intelligence.loot:recent() or {}
  return {
    totals = copy(totals or {}),
    recent = tail(recent, 20),
    loot = tail(loot, 20),
  }
end

local function targetingSnapshot(intelligence)
  local events = intelligence.events and type(intelligence.events.recent) == "function" and intelligence.events:recent() or {}
  local recent = tail(events, 12)
  return {
    currentTarget = getBlackboardValue(intelligence, "currentTarget"),
    currentRouteObjective = getBlackboardValue(intelligence, "currentRouteObjective"),
    currentMovementIntent = getBlackboardValue(intelligence, "currentMovementIntent"),
    currentAttackIntent = getBlackboardValue(intelligence, "currentAttackIntent"),
    currentLureState = getBlackboardValue(intelligence, "currentLureState"),
    currentPullState = getBlackboardValue(intelligence, "currentPullState"),
    currentWavePrediction = getBlackboardValue(intelligence, "currentWavePrediction"),
    recentDecisions = recent,
  }
end

local function pipelineSnapshot(intelligence, modelCount)
  local events = intelligence.events and type(intelligence.events.recent) == "function" and intelligence.events:recent() or {}
  local counts = {}
  for _, event in ipairs(events) do
    counts[event.type] = (counts[event.type] or 0) + 1
  end
  local lastEvent = events[#events]
  return {
    eventCount = #events,
    modelCount = modelCount or 0,
    lastEvent = lastEvent and {
      type = lastEvent.type,
      source = lastEvent.source,
      timestamp = lastEvent.timestamp,
    } or nil,
    eventCounts = counts,
    recentEvents = tail(events, 12),
    health = #events > 0 and "healthy" or "empty",
  }
end

local function monsterSnapshot()
  local patterns = UnifiedStorage and UnifiedStorage.get and UnifiedStorage.get("targetbot.monsterPatterns") or {}
  local telemetry = UnifiedStorage and UnifiedStorage.get and UnifiedStorage.get("targetbot.monsterMetrics.typeStats") or {}
  local monsterKeys = {}
  for monsterKey in pairs(patterns) do monsterKeys[monsterKey] = true end
  for monsterKey in pairs(telemetry) do monsterKeys[monsterKey] = true end
  local profiles = {}
  for monsterKey in pairs(monsterKeys) do
    local pattern = patterns[monsterKey] or {}
    local stats = telemetry[monsterKey] or {}
    local samples = math.max(tonumber(pattern.samples) or countKeys(pattern.samplesByKey), tonumber(stats.sampleCount) or 0)
    local kills = tonumber(stats.killCount) or 0
    local confidence = tonumber(pattern.confidence) or 0
    local dataSources = copy(pattern.dataSources or {})
    if hasEntries(pattern) then dataSources[#dataSources + 1] = "MonsterPatterns" end
    if hasEntries(stats) then dataSources[#dataSources + 1] = "MonsterAI.Telemetry" end
    profiles[#profiles + 1] = {
      monsterKey = monsterKey,
      displayName = pattern.displayName or pattern.name or stats.name or monsterKey,
      samples = samples,
      lastSeenAt = math.max(tonumber(pattern.lastSeen) or 0, tonumber(stats.lastSeen) or 0),
      confidence = confidence,
      averageSpeed = pattern.averageSpeed or stats.avgSpeed or 0,
      preferredDistance = pattern.preferredDistance or 0,
      chaseProbability = pattern.chaseProbability or 0,
      retreatProbability = pattern.retreatProbability or 0,
      observedAttacks = pattern.observedAttacks or 0,
      estimatedAttackIntervalMs = pattern.attackIntervalMs or 0,
      waveSamples = pattern.waveSamples or stats.waveAttackCount or 0,
      waveProbability = pattern.waveProbability or 0,
      estimatedWaveCooldownMs = pattern.waveCooldown or 0,
      waveVariance = pattern.waveVariance or 0,
      damageSamples = pattern.damageSamples or 0,
      estimatedDps = pattern.estimatedDps or stats.avgDPS or 0,
      averageTtkMs = pattern.averageTtkMs or (kills > 0 and (tonumber(stats.totalKillTime) or 0) / kills or 0),
      reachabilitySamples = pattern.reachabilitySamples or 0,
      reachabilityRate = pattern.reachabilityRate or 0,
      targetSelections = pattern.targetSelections or 0,
      successfulEngagements = pattern.successfulEngagements or 0,
      cancelledEngagements = pattern.cancelledEngagements or 0,
      dataSources = dataSources,
      evidence = pattern.evidence or samples,
      observationQuality = pattern.observationQuality or 0,
      state = confidence >= 0.8 and "CONFIDENT" or samples > 0 and "LEARNING" or hasEntries(pattern) and "INSUFFICIENT_EVIDENCE" or "NO_DATA",
    }
  end

  table.sort(profiles, function(a, b)
    if a.confidence == b.confidence then
      return (a.samples or 0) > (b.samples or 0)
    end
    return (a.confidence or 0) > (b.confidence or 0)
  end)

  local tracker = nExBot.MonsterAI and nExBot.MonsterAI.Tracker and nExBot.MonsterAI.Tracker.monsters or {}
  local live = 0
  for _ in pairs(tracker) do
    live = live + 1
  end

  local prediction = nExBot.MonsterAI and nExBot.MonsterAI.getPredictionStats and nExBot.MonsterAI.getPredictionStats() or {}
  local feedback = nExBot.MonsterAI and nExBot.MonsterAI.CombatFeedback and nExBot.MonsterAI.CombatFeedback.getAccuracy and nExBot.MonsterAI.CombatFeedback.getAccuracy() or {}

  return {
    profiles = profiles,
    liveMonsters = live,
    summary = {
      liveMonsters = live,
      persistedProfiles = #profiles,
      predictionAccuracy = prediction.accuracy or 0,
      waveAccuracy = feedback.waveAttack or 0,
      combatFeedback = feedback,
    },
  }
end

local function replaySnapshot(intelligence)
  local replay = intelligence.replay and type(intelligence.replay.export) == "function" and intelligence.replay:export() or {}
  return {
    recordCount = #replay,
    records = tail(replay, 20),
  }
end

local function diagnosticSnapshot(intelligence, state)
  local capture = IntelligenceBotDoctor and IntelligenceBotDoctor.capture and IntelligenceBotDoctor.capture(intelligence, {
    subscriptions = EventBus and EventBus.listenerCount and EventBus.listenerCount() or 0,
    replayVersion = IntelligenceReplay and IntelligenceReplay.SCHEMA_VERSION or 1,
    pipeline = state and state.pipeline or nil,
    models = state and state.models or nil,
    monsters = state and state.monsters or nil,
    session = state and state.session or nil,
    elapsedMs = state and state.session and state.session.elapsedMs or 0,
  }) or {}
  local issues = IntelligenceBotDoctor and IntelligenceBotDoctor.inspect and IntelligenceBotDoctor.inspect(capture) or {}
  return {
    capture = capture,
    issues = issues,
    issueCount = #issues,
  }
end

local function buildState()
  local intelligence = nExBot.Intelligence or {}
  local analytics = getAnalytics()
  local lifecycle = intelligence.lifecycle or {}
  local route = intelligence.route or {}
  
  local state = {
    revision = type(lifecycle.generation) == "function" and lifecycle:generation("snapshot") or 0,
    generatedAt = nowMs(),
    sessionId = tostring(type(lifecycle.generation) == "function" and lifecycle:generation("lifecycle") or 0),
    session = {
      id = tostring(type(lifecycle.generation) == "function" and lifecycle:generation("lifecycle") or 0),
      active = lifecycle.active == true,
      elapsedMs = analytics.elapsedMs or 0,
      updatedAt = nowMs(),
    },
    overview = {
      lifecycle = lifecycle.active and "active" or "stopped",
      snapshotGeneration = type(lifecycle.generation) == "function" and lifecycle:generation("snapshot") or 0,
      routeState = route.state,
      routeGeneration = route.generation,
      waypointIndex = route.waypointIndex,
      xpGained = analytics.metrics.xpGained or 0,
      xpPerHour = analytics.metrics.xpPerHour or 0,
      kills = analytics.metrics.kills or 0,
      killsPerHour = analytics.metrics.killsPerHour or 0,
      combatUptime = analytics.metrics.combatUptime or 0,
      modelCount = 0,
      actionableModels = 0,
      lastEvent = nil,
      pipelineHealth = nil,
    },
    hunt = {
      metrics = analytics.metrics,
      trends = analytics.trends,
      summary = {
        elapsedMs = analytics.elapsedMs or 0,
        xpGained = analytics.metrics.xpGained or 0,
        xpPerHour = analytics.metrics.xpPerHour or 0,
        kills = analytics.metrics.kills or 0,
        killsPerHour = analytics.metrics.killsPerHour or 0,
        combatUptime = analytics.metrics.combatUptime or 0,
        tilesWalked = analytics.metrics.tilesWalked or 0,
        tilesPerKill = analytics.metrics.tilesPerKill or 0,
        damageTaken = analytics.metrics.damageTaken or 0,
        healingDone = analytics.metrics.healingDone or 0,
        survivabilityIndex = analytics.metrics.survivabilityIndex or 0,
        nearDeathCount = analytics.metrics.nearDeathCount or 0,
        hpPotions = analytics.metrics.hpPotionsUsed or analytics.metrics.potionsUsed or 0,
        manaPotions = analytics.metrics.manaPotionsUsed or 0,
        runes = analytics.metrics.runesUsed or 0,
        healingSpells = analytics.metrics.healSpellsCast or 0,
        attackSpells = analytics.metrics.attackSpellsCast or 0,
        manaSpent = analytics.metrics.manaSpent or 0,
        potionsPerHour = analytics.metrics.potionsPerHour or 0,
        runesPerHour = analytics.metrics.runesPerHour or 0,
        manaPerHour = analytics.metrics.manaSpentPerHour or 0,
      },
    },
    routes = {
      state = route.state,
      generation = route.generation,
      waypointIndex = route.waypointIndex,
      currentObjective = getBlackboardValue(intelligence, "currentRouteObjective"),
    },
    pipeline = nil,
    diagnostics = nil,
  }
  
  state.models = modelSnapshots(intelligence)
  state.overview.modelCount = state.models.summary.total
  state.overview.actionableModels = state.models.summary.actionable
  state.resources = resourceSnapshot(intelligence)
  state.monsters = monsterSnapshot()
  state.targeting = targetingSnapshot(intelligence)
  state.replay = replaySnapshot(intelligence)
  state.pipeline = pipelineSnapshot(intelligence, state.models and state.models.summary.total or 0)
  state.overview.lastEvent = state.pipeline.lastEvent and state.pipeline.lastEvent.type or nil
  state.overview.pipelineHealth = state.pipeline.health
  state.diagnostics = diagnosticSnapshot(intelligence, state)
  state.overview.lastPersistenceSave = intelligence.lastPersistAt

  return state
end

function Tactical:refresh()
  local now = nowMs()
  local refreshMs = self.refreshMs or 200
  if self.cached and self.cachedAt and now - self.cachedAt < refreshMs then
    return self.cached
  end

  self.revision = (self.revision or 0) + 1
  self.state = buildState()
  self.state.revision = self.revision
  self.state.generatedAt = now
  self.state.updatedAt = now
  self.cached = self.state
  self.cachedAt = now
  if self.presenter then
    self.presenter.state = self.state
  end
  if self.listeners then
    for _, listener in pairs(self.listeners) do
      pcall(listener, self.state)
    end
  end
  return self.cached
end

function Tactical:view(viewport)
  if not self.presenter then
    local P = Presenter or IntelligenceUiPresenter
    if not P then
      return self:refresh()
    end
    self.presenter = P.new({
      state = self:refresh(),
      nowMs = nowMs,
      refreshMs = 200,
    })
  end
  self.presenter.state = self:refresh()
  return self.presenter:view(viewport)
end

-- Mark section dirty for incremental update
function Tactical:markDirty(section) end

function Tactical:invalidate()
  self.cached = nil
  self.cachedAt = 0
end

local function sectionSnapshot(self, section)
  local state = self:refresh()
  local snapshot = copy(state[section] or {})
  snapshot.revision = state.revision
  snapshot.sessionId = state.sessionId
  snapshot.updatedAt = state.updatedAt or state.generatedAt
  return snapshot
end

function Tactical:getOverviewSnapshot()
  return sectionSnapshot(self, "overview")
end

function Tactical:getHuntSnapshot()
  return sectionSnapshot(self, "hunt")
end

function Tactical:getResourceSnapshot()
  return sectionSnapshot(self, "resources")
end

function Tactical:getMonsterProfilesSnapshot()
  return sectionSnapshot(self, "monsters")
end

function Tactical:getLootSnapshot()
  return sectionSnapshot(self, "resources")
end

function Tactical:getInsightsSnapshot()
  return sectionSnapshot(self, "hunt")
end

function Tactical:getTrendSnapshot()
  return sectionSnapshot(self, "hunt")
end

function Tactical:getModelSnapshot()
  return sectionSnapshot(self, "models")
end

function Tactical:getPipelineSnapshot()
  return sectionSnapshot(self, "pipeline")
end

function Tactical:getDiagnosticsSnapshot()
  return sectionSnapshot(self, "diagnostics")
end

function Tactical:subscribe(listener)
  assert(type(listener) == "function", "listener must be a function")
  self.listeners = self.listeners or {}
  self.nextToken = (self.nextToken or 0) + 1
  self.listeners[self.nextToken] = listener
  return self.nextToken
end

function Tactical:unsubscribe(token)
  if self.listeners then
    self.listeners[token] = nil
  end
end

-- Event-driven dirty marking (unique events only — player:health, player:mana,
-- container:update, combat:target already handled by sectionTracker block above)
if EventBus then
  EventBus.on("creature:health", function() Tactical:markDirty("monsters") end)
  EventBus.on("monster:appear", function() Tactical:markDirty("monsters") end)
  EventBus.on("monster:disappear", function() Tactical:markDirty("monsters") end)
  EventBus.on("container:addItem", function() Tactical:markDirty("resources") end)
  EventBus.on("container:removeItem", function() Tactical:markDirty("resources") end)
  EventBus.on("TargetCandidateEvaluated", function() Tactical:markDirty("pipeline") end)
  EventBus.on("TargetSelected", function() Tactical:markDirty("pipeline") end)
  EventBus.on("TargetRejected", function() Tactical:markDirty("pipeline") end)
  EventBus.on("model:diagnostics", function() Tactical:markDirty("diagnostics") end)
  EventBus.on("replay:recorded", function() Tactical:markDirty("replay") end)
  EventBus.on("route:stateChanged", function() Tactical:markDirty("targeting") end)
end

nExBot.TacticalIntelligence = Tactical

return nExBot.TacticalIntelligence
