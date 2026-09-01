IntelligenceContextAdjustment = {}
local ContextAdjustment = IntelligenceContextAdjustment
ContextAdjustment.__index = ContextAdjustment

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function ContextAdjustment.new(options)
  options = options or {}
  return setmetatable({
    contexts = {},
    maxContexts = options.maxContexts or 128,
    minSamples = options.minSamples or 30,
    minConfidence = options.minConfidence or 0.7,
    maxAdjustment = options.maxAdjustment or 0.1,
  }, ContextAdjustment)
end

function ContextAdjustment:observe(key, success, now)
  assert(type(key) == "string" and key ~= "" and type(success) == "boolean", "invalid context observation")
  local entry = self.contexts[key] or { samples = 0, successes = 0, updatedAt = 0 }
  entry.samples = math.min(1000, entry.samples + 1)
  entry.successes = math.min(entry.samples, entry.successes + (success and 1 or 0))
  entry.updatedAt = now or 0
  self.contexts[key] = entry

  local keys = {}
  for contextKey in pairs(self.contexts) do keys[#keys + 1] = contextKey end
  if #keys > self.maxContexts then
    table.sort(keys, function(a, b)
      local left, right = self.contexts[a], self.contexts[b]
      return left.updatedAt == right.updatedAt and a < b or left.updatedAt < right.updatedAt
    end)
    self.contexts[keys[1]] = nil
  end
end

function ContextAdjustment:get(key)
  local entry = self.contexts[key]
  if not entry then return 0, { samples = 0, confidence = 0, actionable = false } end
  local confidence = math.min(1, entry.samples / self.minSamples)
  local actionable = entry.samples >= self.minSamples and confidence >= self.minConfidence
  local probability = (entry.successes + 1) / (entry.samples + 2)
  local adjustment = actionable and clamp((probability - 0.5) * 2 * self.maxAdjustment,
    -self.maxAdjustment, self.maxAdjustment) or 0
  return adjustment, { samples = entry.samples, confidence = confidence,
    probability = probability, actionable = actionable }
end

function ContextAdjustment:serialize()
  local contexts = {}
  for key, entry in pairs(self.contexts) do
    contexts[key] = { samples = entry.samples, successes = entry.successes, updatedAt = entry.updatedAt }
  end
  return { schemaVersion = 1, contexts = contexts }
end

function ContextAdjustment:restore(saved)
  if type(saved) ~= "table" or saved.schemaVersion ~= 1 or type(saved.contexts) ~= "table" then return false end
  self.contexts = {}
  for key, entry in pairs(saved.contexts) do
    if type(key) == "string" and type(entry) == "table" and type(entry.samples) == "number"
        and type(entry.successes) == "number" and entry.samples >= 0 and entry.successes >= 0
        and entry.successes <= entry.samples then
      self.contexts[key] = { samples = math.min(1000, entry.samples),
        successes = math.min(1000, entry.successes), updatedAt = tonumber(entry.updatedAt) or 0 }
    end
  end
  while true do
    local count, oldestKey, oldest = 0, nil, nil
    for key, entry in pairs(self.contexts) do
      count = count + 1
      if not oldest or entry.updatedAt < oldest then oldestKey, oldest = key, entry.updatedAt end
    end
    if count <= self.maxContexts then break end
    self.contexts[oldestKey] = nil
  end
  return true
end

return ContextAdjustment
