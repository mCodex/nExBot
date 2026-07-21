IntelligenceKillSwitch = {}
IntelligenceKillSwitch.__index = IntelligenceKillSwitch

function IntelligenceKillSwitch.new()
  return setmetatable({ disabled = {} }, IntelligenceKillSwitch)
end

function IntelligenceKillSwitch:isEnabled(scope)
  if self.disabled["global"] then return true end
  return self.disabled[scope] == true
end

function IntelligenceKillSwitch:enable(scope)
  self.disabled[scope] = true
end

function IntelligenceKillSwitch:disable(scope)
  self.disabled[scope] = nil
end

function IntelligenceKillSwitch:getStatus()
  local result = {}
  for scope, _ in pairs(self.disabled) do result[scope] = true end
  return result
end

return IntelligenceKillSwitch
