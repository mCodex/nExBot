local RollbackMonitor = {}
RollbackMonitor.__index = RollbackMonitor

local DEFAULTS = {
  safetyEventRate = 0.1,
  nearDeathRate = 0.05,
  deathRate = 0.01,
  targetSwitchRate = 0.3,
  pathFailureRate = 0.2,
  stuckDuration = 30,
  lootCaptureRate = 0.5,
  resourceConsumption = 2.0,
  manualInterventionRate = 0.1,
  modelExceptionRate = 0.01,
  latencyMs = 500,
}

local REASONS = {
  safetyEventRate = "safety event rate exceeded",
  nearDeathRate = "near-death rate exceeded",
  deathRate = "death rate exceeded",
  targetSwitchRate = "target switch rate exceeded",
  pathFailureRate = "path failure rate exceeded",
  stuckDuration = "stuck duration exceeded",
  lootCaptureRate = "loot capture rate too low",
  resourceConsumption = "resource consumption exceeded",
  manualInterventionRate = "manual intervention rate exceeded",
  modelExceptionRate = "model exception rate exceeded",
  latencyMs = "latency exceeded",
}

local REASON_ORDER = {
  "deathRate", "nearDeathRate", "safetyEventRate", "resourceConsumption",
  "modelExceptionRate", "manualInterventionRate", "stuckDuration",
  "pathFailureRate", "targetSwitchRate", "lootCaptureRate", "latencyMs",
}

function RollbackMonitor.new(config)
  local self = setmetatable({}, RollbackMonitor)
  self.thresholds = {}
  for k, v in pairs(DEFAULTS) do
    self.thresholds[k] = v
  end
  if config then
    for k, v in pairs(config) do
      if self.thresholds[k] ~= nil then
        self.thresholds[k] = v
      end
    end
  end
  self._breach = nil
  self._reason = nil
  return self
end

function RollbackMonitor:check(metrics)
  self._breach = nil
  self._reason = nil
  metrics = metrics or {}

  for _, key in ipairs(REASON_ORDER) do
    local val = metrics[key]
    if val ~= nil then
      local threshold = self.thresholds[key]
      local breached = false
      if key == "lootCaptureRate" then
        breached = val < threshold
      else
        breached = val > threshold
      end
      if breached then
        self._breach = key
        self._reason = REASONS[key]
        return true
      end
    end
  end

  return false
end

function RollbackMonitor:shouldRollback()
  return self._breach ~= nil
end

function RollbackMonitor:getReason()
  return self._reason
end

nExBot = nExBot or {}
nExBot.IntelligenceRollbackMonitor = RollbackMonitor

return RollbackMonitor
