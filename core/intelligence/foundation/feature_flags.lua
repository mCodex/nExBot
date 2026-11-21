IntelligenceFeatureFlags = {}
IntelligenceFeatureFlags.__index = IntelligenceFeatureFlags

function IntelligenceFeatureFlags.new(defaults)
  local values = {}
  for name, enabled in pairs(defaults or {}) do values[name] = enabled == true end
  return setmetatable({ values = values }, IntelligenceFeatureFlags)
end

function IntelligenceFeatureFlags:enabled(name) return self.values[name] == true end

function IntelligenceFeatureFlags:set(name, enabled)
  if self.values[name] == nil then return false, "unknown_flag" end
  self.values[name] = enabled == true
  return true
end

function IntelligenceFeatureFlags:snapshot()
  local result = {}
  for name, enabled in pairs(self.values) do result[name] = enabled end
  return result
end

return IntelligenceFeatureFlags
