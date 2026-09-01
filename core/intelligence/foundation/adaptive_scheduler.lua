IntelligenceAdaptiveScheduler = {}
local Scheduler = IntelligenceAdaptiveScheduler
Scheduler.__index = Scheduler

function Scheduler.new(intervals)
  intervals = intervals or {}
  local rates = {
    idle = intervals.idle or 500,
    route = intervals.route or 200,
    combat = intervals.combat or 50,
    emergency = intervals.emergency or 20,
    max = intervals.max or 2000,
  }
  for name, value in pairs(rates) do
    assert(type(value) == "number" and value > 0, name .. " interval must be positive")
  end
  return setmetatable({ rates = rates }, Scheduler)
end

function Scheduler:interval(state)
  state = state or {}
  local interval = self.rates.idle
  if state.routeActive then interval = self.rates.route end
  if state.combat then interval = self.rates.combat end
  if state.emergency then interval = self.rates.emergency end
  if state.overBudget and state.optional then interval = math.min(interval * 2, self.rates.max) end
  return interval
end

return Scheduler
