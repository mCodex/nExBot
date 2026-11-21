local CI = {}
CI.__index = CI

local Z_SCORES = {
  [0.90] = 1.645,
  [0.95] = 1.96,
  [0.99] = 2.576,
}

function CI.new(_config)
  local self = setmetatable({}, CI)
  return self
end

function CI:compute(values, confidence)
  if not values or #values == 0 then return nil end

  confidence = confidence or 0.95
  local n = #values

  local sum = 0
  for _, v in ipairs(values) do sum = sum + v end
  local mean = sum / n

  if n == 1 then
    return { mean = mean, std = 0, lower = mean, upper = mean }
  end

  local sqSum = 0
  for _, v in ipairs(values) do sqSum = sqSum + (v - mean) ^ 2 end
  local std = math.sqrt(sqSum / (n - 1))

  local z = Z_SCORES[confidence] or 1.96
  local margin = z * (std / math.sqrt(n))

  return {
    mean = mean,
    std = std,
    lower = mean - margin,
    upper = mean + margin,
  }
end

function CI:isSignificant(ci1, ci2)
  return ci1.upper < ci2.lower or ci2.upper < ci1.lower
end

nExBot = nExBot or {}
nExBot.IntelligenceConfidenceInterval = CI

return CI
