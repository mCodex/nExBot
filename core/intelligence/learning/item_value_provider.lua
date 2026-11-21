IntelligenceItemValueProvider = {}
local Provider = IntelligenceItemValueProvider
Provider.__index = Provider

function Provider.new(config)
  assert(config and config.valueTable, "config.valueTable required")
  local values = {}
  for k, v in pairs(config.valueTable) do values[k] = v end
  return setmetatable({ values = values }, Provider)
end

function Provider:getValue(itemId)
  return self.values[itemId] or 0
end

function Provider:getConfidence(itemId)
  if self.values[itemId] then return 0.5 end
  return 0
end

function Provider:getAllValues()
  local copy = {}
  for k, v in pairs(self.values) do copy[k] = v end
  return copy
end

nExBot = nExBot or {}
nExBot.IntelligenceItemValueProvider = Provider

return IntelligenceItemValueProvider
