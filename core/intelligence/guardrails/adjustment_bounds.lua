local Bounds = {}
Bounds.__index = Bounds

local DEFAULTS = {
  OFF = 0,
  OBSERVE = 0,
  SHADOW = 0,
  CANARY = 0.02,
  ACTIVE_LOW = 0.05,
  ACTIVE = 0.10,
}

function Bounds.new(config)
  if not config or type(config.bounds) ~= "table" then
    error("Bounds.new: config must include 'bounds' table")
  end
  local self = setmetatable({}, Bounds)
  self._bounds = {}
  for mode, max in pairs(DEFAULTS) do
    self._bounds[mode] = config.bounds[mode] or max
  end
  for mode, max in pairs(config.bounds) do
    self._bounds[mode] = max
  end
  return self
end

function Bounds:clamp(value, mode)
  local b = self._bounds[mode]
  if not b then return 0 end
  return math.max(-b, math.min(b, value))
end

function Bounds:getBounds(mode)
  local b = self._bounds[mode]
  if not b then return { min = 0, max = 0 } end
  return { min = -b, max = b }
end

nExBot = nExBot or {}
nExBot.IntelligenceAdjustmentBounds = Bounds

return Bounds
