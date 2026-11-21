IntelligenceDecisionEngine = {}
IntelligenceDecisionEngine.__index = IntelligenceDecisionEngine
local nowMs = nExBot and nExBot.Shared and nExBot.Shared.nowMs or function() return os.time() * 1000 end

local GENERATIONS = { "snapshot", "route", "combat" }
local SCORES = { "safety", "configuredPriority", "priority", "confidence", "utility" }

function IntelligenceDecisionEngine.new(options)
  options = options or {}
  return setmetatable({
    now = options.now or nowMs,
    safetyEnvelope = options.safetyEnvelope,
  }, IntelligenceDecisionEngine)
end

local function staleReason(proposal, generations)
  for _, name in ipairs(GENERATIONS) do
    local proposalGeneration = proposal[name .. "Generation"]
    if proposalGeneration and proposalGeneration < (generations[name] or 0) then
      return "stale_" .. name .. "_generation"
    end
  end
end

local function better(a, b)
  for _, field in ipairs(SCORES) do
    local left, right = tonumber(a.proposal[field]) or 0, tonumber(b.proposal[field]) or 0
    if left ~= right then return left > right end
  end
  return a.order < b.order
end

function IntelligenceDecisionEngine:select(proposals, generations, context)
  generations = generations or {}
  local valid, rejected = {}, {}
  for order, proposal in ipairs(proposals or {}) do
    local reason
    if type(proposal) ~= "table" then
      reason = "invalid_proposal"
    elseif proposal.expiresAt and proposal.expiresAt > 0 and proposal.expiresAt <= self.now() then
      reason = "expired"
    else
      reason = staleReason(proposal, generations)
      if not reason and self.safetyEnvelope then
        local safe, safetyReason = self.safetyEnvelope:validate(proposal, context)
        if not safe then reason = safetyReason end
      end
    end
    if reason then
      rejected[#rejected + 1] = { proposal = proposal, reason = reason }
    else
      valid[#valid + 1] = { proposal = proposal, order = order }
    end
  end
  table.sort(valid, better)
  return valid[1] and valid[1].proposal or nil, rejected
end

return IntelligenceDecisionEngine
