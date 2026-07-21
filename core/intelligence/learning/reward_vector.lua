-- core/intelligence/learning/reward_vector.lua
-- Versioned multi-objective reward vector

IntelligenceRewardVector = {}
local RewardVector = IntelligenceRewardVector
RewardVector.__index = RewardVector

function RewardVector.new(config)
  config = config or {}
  assert(config.componentNames, "componentNames is required")
  return setmetatable({
    version = config.version or 1,
    componentNames = config.componentNames,
  }, RewardVector)
end

function RewardVector:create(components)
  components = components or {}
  local c = {}
  for _, name in ipairs(self.componentNames) do
    c[name] = tonumber(components[name]) or 0
  end
  return setmetatable({
    version = self.version,
    timestamp = os.time(),
    components = c,
  }, RewardVector)
end

function RewardVector:add(v1, v2)
  local c = {}
  for _, name in ipairs(self.componentNames) do
    c[name] = (v1.components[name] or 0) + (v2.components[name] or 0)
  end
  return setmetatable({
    version = v1.version,
    timestamp = os.time(),
    components = c,
  }, RewardVector)
end

function RewardVector:scale(v, factor)
  local c = {}
  for _, name in ipairs(self.componentNames) do
    c[name] = (v.components[name] or 0) * factor
  end
  return setmetatable({
    version = v.version,
    timestamp = os.time(),
    components = c,
  }, RewardVector)
end

function RewardVector:dot(v1, v2)
  local sum = 0
  for _, name in ipairs(self.componentNames) do
    sum = sum + (v1.components[name] or 0) * (v2.components[name] or 0)
  end
  return sum
end

function RewardVector:validate(reward)
  if type(reward) ~= "table" then return false end
  if type(reward.version) ~= "number" then return false end
  if type(reward.components) ~= "table" then return false end
  for name, value in pairs(reward.components) do
    if type(value) ~= "number" then return false end
  end
  return true
end

return RewardVector
