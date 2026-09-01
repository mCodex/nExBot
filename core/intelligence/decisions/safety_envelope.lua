IntelligenceSafetyEnvelope = {}
IntelligenceSafetyEnvelope.__index = IntelligenceSafetyEnvelope

function IntelligenceSafetyEnvelope.new(options)
  options = options or {}
  return setmetatable({ validators = options.validators or {} }, IntelligenceSafetyEnvelope)
end

function IntelligenceSafetyEnvelope:validate(proposal, context)
  for index, validator in ipairs(self.validators) do
    local name = validator.name or tostring(index)
    local ok, valid, reason = pcall(validator.check, proposal, context or {})
    if not ok then return false, "validator_error:" .. name end
    if not valid then return false, reason or "unsafe:" .. name end
  end
  return true
end

return IntelligenceSafetyEnvelope
