IntelligencePerformanceBudget = {}
local Budget = IntelligencePerformanceBudget
Budget.__index = Budget

local ORDER = { "diagnostics", "replay", "learning", "neuralModel", "routeAlternatives" }

function Budget.new(maxMilliseconds)
  assert(type(maxMilliseconds) == "number" and maxMilliseconds >= 0, "budget must be non-negative")
  return setmetatable({ maxMilliseconds = maxMilliseconds, disabled = {}, nextDegradation = 1 }, Budget)
end

function Budget:record(elapsedMilliseconds)
  assert(type(elapsedMilliseconds) == "number" and elapsedMilliseconds >= 0, "elapsed time must be non-negative")
  if elapsedMilliseconds <= self.maxMilliseconds then return nil end
  local feature = ORDER[self.nextDegradation]
  if feature then
    self.disabled[feature] = true
    self.nextDegradation = self.nextDegradation + 1
  end
  return feature
end

function Budget:enabled(feature)
  return not self.disabled[feature]
end

return Budget
