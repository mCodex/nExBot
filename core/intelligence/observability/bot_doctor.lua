IntelligenceBotDoctor = {}
local Doctor = IntelligenceBotDoctor

local function issue(issues, code, message, action)
  issues[#issues + 1] = { code = code, message = message, action = action }
end

function Doctor.inspect(runtime)
  assert(type(runtime) == "table", "runtime inspection data is required")
  local issues = {}

  for _, domain in ipairs({ "movement", "attack" }) do
    local owners = runtime.owners and runtime.owners[domain] or {}
    if #owners == 0 then
      issue(issues, "OWNERSHIP_MISSING", domain .. " has no owner", "Register exactly one " .. domain .. " owner")
    elseif #owners > 1 then
      issue(issues, "OWNERSHIP_MULTIPLE", domain .. " has multiple owners",
        "Route " .. domain .. " through " .. tostring(owners[1]) .. " and remove other writers")
    end
  end

  local lifecycle = runtime.lifecycle or {}
  if lifecycle.active and (lifecycle.subscriptions or 0) == 0 then
    issue(issues, "LIFECYCLE_DISCONNECTED", "active lifecycle has no subscriptions",
      "Reconnect event subscriptions or terminate the inactive lifecycle")
  end

  local schemaNames = {}
  for name in pairs(runtime.schemas or {}) do schemaNames[#schemaNames + 1] = name end
  table.sort(schemaNames)
  for _, name in ipairs(schemaNames) do
    local schema = runtime.schemas[name]
    if schema.current ~= schema.expected then
      issue(issues, "SCHEMA_MISMATCH", name .. " schema is not current", "Run the " .. name .. " migration")
    end
  end

  local performance = runtime.performance or {}
  if type(performance.tickMs) == "number" and type(performance.budgetMs) == "number"
      and performance.tickMs > performance.budgetMs then
    issue(issues, "PERFORMANCE_BUDGET", "tick exceeds its performance budget",
      "Profile the measured tick and degrade optional work")
  end

  return issues
end

function Doctor.capture(intelligence, live)
  live = live or {}
  local tick = live.tick or (UnifiedTick and UnifiedTick.getDiagnostics and UnifiedTick.getDiagnostics()) or {}
  local storageVersion = live.storageVersion
    or (UnifiedStorage and UnifiedStorage.get and UnifiedStorage.get("version"))
  local movementOwner = live.movementOwner or MovementCoordinator
  local attackOwner = live.attackOwner or AttackStateMachine
  return {
    owners = {
      movement = movementOwner and { "MovementCoordinator" } or {},
      attack = attackOwner and { "AttackStateMachine" } or {},
    },
    lifecycle = { active = intelligence and intelligence.lifecycle and intelligence.lifecycle.active or false,
      subscriptions = live.subscriptions
        or (EventBus and EventBus.listenerCount and EventBus.listenerCount()) or 0 },
    schemas = { config = { current = storageVersion, expected = 5 },
      replay = { current = live.replayVersion
        or (IntelligenceReplay and IntelligenceReplay.SCHEMA_VERSION), expected = 1 } },
    performance = { tickMs = tick.avgTickTime,
      budgetMs = intelligence and intelligence.budgets and intelligence.budgets.maxMilliseconds },
  }
end

return Doctor
