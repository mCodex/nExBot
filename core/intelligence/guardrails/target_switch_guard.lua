local TargetSwitchGuard = {}
TargetSwitchGuard.__index = TargetSwitchGuard

local DEFAULT_CONFIG = {
  maxSwitchesPerWindow = 5,
  windowSeconds = 60,
  minHoldTime = 3,
  manualLockWindow = 30,
}

local SCORE_DIFF_THRESHOLD = 0.05
local MANUAL_LOCK_WINDOW = 30

function TargetSwitchGuard.new(config)
  local self = setmetatable({}, TargetSwitchGuard)
  local cfg = {}
  for k, v in pairs(DEFAULT_CONFIG) do
    cfg[k] = v
  end
  if config then
    for k, v in pairs(config) do
      if cfg[k] ~= nil then
        cfg[k] = v
      end
    end
  end
  self._maxSwitchesPerWindow = cfg.maxSwitchesPerWindow
  self._windowSeconds = cfg.windowSeconds
  self._minHoldTime = cfg.minHoldTime
  self._manualLockWindow = cfg.manualLockWindow or MANUAL_LOCK_WINDOW
  self._switchHistory = {}
  self._lastManualSwitch = nil
  return self
end

function TargetSwitchGuard:canSwitch(context)
  context = context or {}

  if context.manualOverride then
    return true
  end

  local now = context.now or os.time()

  if self._lastManualSwitch then
    if (now - self._lastManualSwitch) < self._manualLockWindow then
      return false
    end
  end

  local pruned = {}
  for _, entry in ipairs(self._switchHistory) do
    if (now - entry.time) <= self._windowSeconds then
      pruned[#pruned + 1] = entry
    end
  end
  self._switchHistory = pruned

  if #self._switchHistory >= self._maxSwitchesPerWindow then
    return false
  end

  if #self._switchHistory > 0 then
    local lastSwitch = self._switchHistory[#self._switchHistory]
    if (now - lastSwitch.time) < self._minHoldTime then
      if context.nearDeath then
        return true
      end
      if context.scoreDiff and context.scoreDiff < SCORE_DIFF_THRESHOLD then
        return false
      end
      return false
    end
  end

  return true
end

function TargetSwitchGuard:recordSwitch(opts)
  opts = opts or {}
  local time = opts.time or opts.now or os.time()
  self._switchHistory[#self._switchHistory + 1] = { time = time }
end

function TargetSwitchGuard:recordManualSwitch(opts)
  opts = opts or {}
  local now = opts.now or os.time()
  self._lastManualSwitch = now
  self._switchHistory[#self._switchHistory + 1] = { time = now }
end

function TargetSwitchGuard:getStats()
  local now = os.time()
  local active = {}
  for _, entry in ipairs(self._switchHistory) do
    if (now - entry.time) <= self._windowSeconds then
      active[#active + 1] = entry
    end
  end

  return {
    switches = #active,
    window = self._maxSwitchesPerWindow,
    rate = #active / self._windowSeconds,
  }
end

nExBot = nExBot or {}
nExBot.IntelligenceTargetSwitchGuard = TargetSwitchGuard

return TargetSwitchGuard
