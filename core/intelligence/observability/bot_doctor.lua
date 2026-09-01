IntelligenceBotDoctor = {}
local Doctor = IntelligenceBotDoctor

local function issue(issues, code, message, action)
  issues[#issues + 1] = {
    code = code,
    message = message,
    action = action,
  }
end

function Doctor.inspect(runtime)
  assert(type(runtime) == "table", "runtime inspection data is required")

  local issues = {}

  for _, domain in ipairs({ "movement", "attack" }) do
    local owners = runtime.owners and runtime.owners[domain] or {}
    if #owners == 0 then
      issue(issues, "OWNERSHIP_MISSING", domain .. " has no owner", "Register exactly one " .. domain .. " owner")
    elseif #owners > 1 then
      issue(issues, "OWNERSHIP_MULTIPLE", domain .. " has multiple owners", "Route " .. domain .. " through " .. tostring(owners[1]) .. " and remove other writers")
    end
  end

  local lifecycle = runtime.lifecycle or {}
  if lifecycle.active and (lifecycle.subscriptions or 0) == 0 then
    issue(issues, "LIFECYCLE_DISCONNECTED", "active lifecycle has no subscriptions", "Reconnect event subscriptions or terminate inactive lifecycle")
  end

  local schemaNames = {}
  for name in pairs(runtime.schemas or {}) do
    schemaNames[#schemaNames + 1] = name
  end
  table.sort(schemaNames)
  for _, name in ipairs(schemaNames) do
    local schema = runtime.schemas[name]
    if schema.current ~= schema.expected then
      issue(issues, "SCHEMA_MISMATCH", name .. " schema is not current", "Run " .. name .. " migration")
    end
  end

  local performance = runtime.performance or {}
  if type(performance.tickMs) == "number" and type(performance.budgetMs) == "number" and performance.tickMs > performance.budgetMs then
    issue(issues, "PERFORMANCE_BUDGET", "tick exceeds its performance budget", "Profile measured tick and degrade optional work")
  end

  local pipeline = runtime.pipeline or {}
  local models = runtime.models or {}
  local monsters = runtime.monsters or {}
  local elapsedMs = runtime.session and runtime.session.elapsedMs or lifecycle.elapsedMs or 0

  if lifecycle.active and elapsedMs >= 10 * 60 * 1000 and (pipeline.eventCount or 0) == 0 then
    issue(issues, "DATA_PIPELINE_NO_EVENTS", "session is active but no intelligence events were recorded", "Check the event producers and the observation gateway")
  end

  if lifecycle.active and elapsedMs >= 10 * 60 * 1000 and (models.summary and models.summary.samples or 0) == 0 then
    issue(issues, "MODEL_ZERO_SAMPLES", "session is active but models still have zero samples", "Verify the canonical event contract and model observers")
  end

  if (monsters.liveMonsters or 0) > 0 and (monsters.summary and monsters.summary.persistedProfiles or 0) == 0 then
    issue(issues, "MONSTER_INSIGHTS_EMPTY", "monster activity exists but no monster profiles are available", "Check the monster projection and persistence path")
  end

  if lifecycle.active and (pipeline.lastEvent == nil) and (pipeline.eventCount or 0) == 0 then
    issue(issues, "UI_PROJECTION_EMPTY", "intelligence projection has no events to render", "Trace the source adapter and the unified facade")
  end

  return issues
end

function Doctor.capture(intelligence, live)
  live = live or {}
  local tick = live.tick or (UnifiedTick and UnifiedTick.getDiagnostics and UnifiedTick.getDiagnostics()) or {}
  return {
    lifecycle = {
      active = intelligence and intelligence.lifecycle and intelligence.lifecycle.active or false,
      subscriptions = live.subscriptions or (EventBus and EventBus.listenerCount and EventBus.listenerCount()) or 0,
      elapsedMs = live.elapsedMs or 0,
    },
    owners = {
      movement = { live.movementOwner or "MovementCoordinator" },
      attack = { live.attackOwner or "AttackStateMachine" },
    },
    schemas = {
      storage = { current = live.storageVersion or 0, expected = 5 },
      replay = { current = live.replayVersion or (IntelligenceReplay and IntelligenceReplay.SCHEMA_VERSION) or 1, expected = 1 },
    },
    performance = {
      tickMs = tick.avgTickTime,
      budgetMs = intelligence and intelligence.budgets and intelligence.budgets.maxMilliseconds,
    },
    pipeline = live.pipeline or {},
    models = live.models or {},
    monsters = live.monsters or {},
    session = live.session or {},
  }
end

return Doctor
