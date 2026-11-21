IntelligenceHorizonCounters = {}
local Counters = IntelligenceHorizonCounters
Counters.__index = Counters

local names = { "immediate", "combat", "route", "session" }

function Counters.new(limits)
  return setmetatable({ limits = limits or { immediate = 8, combat = 64, route = 256, session = 1024 }, values = {} }, Counters)
end

function Counters:add(metric, amount)
  amount = amount or 1
  local metricValues = self.values[metric] or {}
  self.values[metric] = metricValues
  for _, horizon in ipairs(names) do metricValues[horizon] = math.min(self.limits[horizon], (metricValues[horizon] or 0) + amount) end
end

function Counters:get(metric, horizon) return (self.values[metric] or {})[horizon] or 0 end

function Counters:reset(horizon)
  assert(self.limits[horizon], "invalid horizon")
  for _, values in pairs(self.values) do values[horizon] = 0 end
end

return Counters
