IntelligenceRewardNormalizer = {}
local RewardNormalizer = IntelligenceRewardNormalizer
RewardNormalizer.__index = RewardNormalizer

function RewardNormalizer.new(config)
  config = config or {}
  local windowSize = config.windowSize or 1000
  local version = config.version or 1
  return setmetatable({
    version = version,
    windowSize = windowSize,
    _buffer = {},
    _pos = 0,
    _count = 0,
    _sum = {},
    _sumSq = {},
  }, RewardNormalizer)
end

local function clamp01(x)
  return math.max(-1, math.min(1, x))
end

function RewardNormalizer:updateStats(reward)
  reward = reward or {}
  local components = reward.components or {}
  -- Advance position; the next slot is the oldest entry when full
  self._pos = (self._pos % self.windowSize) + 1
  -- Evict oldest if buffer is full
  if self._count >= self.windowSize then
    local old = self._buffer[self._pos]
    if old then
      local oldComp = old.components or {}
      for k, v in pairs(oldComp) do
        self._sum[k] = (self._sum[k] or 0) - v
        self._sumSq[k] = (self._sumSq[k] or 0) - v * v
      end
      self._count = self._count - 1
    end
  end

  self._buffer[self._pos] = reward
  self._count = self._count + 1

  for k, v in pairs(components) do
    self._sum[k] = (self._sum[k] or 0) + v
    self._sumSq[k] = (self._sumSq[k] or 0) + v * v
  end
end

function RewardNormalizer:normalize(reward)
  reward = reward or {}
  local components = reward.components or {}
  local normalized = {}
  local n = self._count

  for k, v in pairs(components) do
    if n < 2 then
      normalized[k] = 0
    else
      local mean = (self._sum[k] or 0) / n
      local variance = (self._sumSq[k] or 0) / n - mean * mean
      local std = math.sqrt(math.max(0, variance))
      if std == 0 then
        normalized[k] = 0
      else
        normalized[k] = clamp01((v - mean) / std)
      end
    end
  end

  return { version = reward.version, timestamp = reward.timestamp, components = normalized }
end

function RewardNormalizer:getStats()
  local n = self._count
  local mean = {}
  local std = {}
  for k, s in pairs(self._sum) do
    mean[k] = n > 0 and s / n or 0
  end
  for k, s in pairs(self._sumSq) do
    local m = mean[k] or 0
    local variance = s / n - m * m
    std[k] = n > 0 and math.sqrt(math.max(0, variance)) or 0
  end
  return { mean = mean, std = std, count = n }
end

nExBot = nExBot or {}
nExBot.IntelligenceRewardNormalizer = RewardNormalizer

return RewardNormalizer
