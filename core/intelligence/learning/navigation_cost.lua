IntelligenceNavigationCost = {}
local NavigationCost = IntelligenceNavigationCost
NavigationCost.__index = NavigationCost

function NavigationCost.new(options)
  options = options or {}
  return setmetatable({ entries = {}, decayMs = options.decayMs or 60000, maxCost = options.maxCost or 10 }, NavigationCost)
end

function NavigationCost:observe(key, cost, confidence, now)
  assert(key ~= nil and type(cost) == "number" and type(now) == "number", "invalid navigation observation")
  confidence = math.max(0, math.min(1, confidence or 0))
  local entry = self.entries[key]
  local current = entry and self:get(key, now) or 0
  self.entries[key] = { cost = math.min(self.maxCost, math.max(0, current + cost * confidence)), updatedAt = now }
  return self.entries[key].cost
end

function NavigationCost:get(key, now)
  local entry = self.entries[key]
  if not entry then return 0 end
  return entry.cost * math.max(0, 1 - math.max(0, now - entry.updatedAt) / self.decayMs)
end

return NavigationCost
