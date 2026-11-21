nExBot = nExBot or {}
IntelligenceResourceCost = {}
local Cost = IntelligenceResourceCost
Cost.__index = Cost

function Cost.new(config)
  config = config or {}
  local costs = {}
  local counts = {}
  local sums = {}
  if config.initialCosts then
    for action, c in pairs(config.initialCosts) do
      costs[action] = c
    end
  end
  return setmetatable({ costs = costs, counts = counts, sums = sums }, Cost)
end

function Cost:getCost(action, context)
  local base = self.costs[action] or 0
  if context and context.costMultiplier then
    return base * context.costMultiplier
  end
  return base
end

function Cost:recordCost(action, cost)
  self.costs[action] = cost
  self.counts[action] = (self.counts[action] or 0) + 1
  self.sums[action] = (self.sums[action] or 0) + cost
end

function Cost:getAverage(action)
  local count = self.counts[action]
  if not count or count == 0 then return 0 end
  return self.sums[action] / count
end

nExBot.IntelligenceResourceCost = Cost
return Cost
