local LootPriority = {}
LootPriority.__index = LootPriority

function LootPriority.new(config)
  assert(config and config.modelInterface, "config.modelInterface required")
  assert(config and config.itemValueProvider, "config.itemValueProvider required")
  return setmetatable({
    _model = config.modelInterface,
    _valueProvider = config.itemValueProvider,
    _metrics = { total = 0, avgValue = 0, avgCost = 0 },
  }, LootPriority)
end

local function scoreAction(self, action, context)
  local value = self._valueProvider:getValue(action.itemId) or 0
  local cost = action.moveCost or 0
  local distance = action.distance or 0
  local expiry = action.expiryTurns or 999

  local score = value - cost - (distance * 2)

  -- ponytail: hardcoded urgency weight, tune if expiry rules change
  if expiry <= 5 then
    score = score + value * 0.5
  elseif expiry <= 20 then
    score = score + value * 0.2
  end

  return score, value, cost
end

function LootPriority:prioritize(lootActions, context)
  if not lootActions or #lootActions == 0 then return {} end

  local safe = {}
  for _, action in ipairs(lootActions) do
    if action.containerReady ~= false and action.safe ~= false then
      safe[#safe + 1] = action
    end
  end

  local scored = {}
  for _, action in ipairs(safe) do
    local score, value, cost = scoreAction(self, action, context)
    scored[#scored + 1] = { action = action, score = score, value = value, cost = cost }
  end

  table.sort(scored, function(a, b) return a.score > b.score end)

  local totalValue, totalCost = 0, 0
  local result = {}
  for i, entry in ipairs(scored) do
    result[i] = entry.action
    totalValue = totalValue + entry.value
    totalCost = totalCost + entry.cost
  end

  self._metrics.total = #result
  self._metrics.avgValue = #result > 0 and (totalValue / #result) or 0
  self._metrics.avgCost = #result > 0 and (totalCost / #result) or 0

  return result
end

function LootPriority:getMetrics()
  return { total = self._metrics.total, avgValue = self._metrics.avgValue, avgCost = self._metrics.avgCost }
end

nExBot = nExBot or {}
nExBot.IntelligenceLootPriority = LootPriority

return LootPriority
