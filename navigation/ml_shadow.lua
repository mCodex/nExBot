--[[
  navigation/ml_shadow.lua — ML recommendation shadow (T8).

  Runs alongside the strict session and proposes the step it WOULD take, purely
  for measurement. A recommendation is NEVER authoritative: the guardrail
  rejects any recommendation whose step fails StepValidator under the same
  policy, so an invalid step can never be dispatched through the ML path.

  Metrics: agreement rate, guardrail rejection rate, per-recommendation reason.
]]

local domain = require("navigation.domain")
local D = domain
local StepValidator = require("navigation.step_validator")
local Obs = require("navigation.observability")

local MLShadow = {}

local function new(session)
  local self = setmetatable({}, { __index = MLShadow })
  self.session = session
  self.agreements = 0
  self.recommendations = 0
  self.guardrailRejections = 0
  self.last = nil

  -- Session calls snapshot() with DOT syntax; bind the instance.
  self.snapshot = function()
    return MLShadow.snapshot(self)
  end
  return self
end
MLShadow.new = new

-- A recommendation must already have passed the strict validator; otherwise
-- the guardrail rejects it. Never returns a validated directive that the
-- session did not independently validate.
function MLShadow:observe(ctx)
  self.recommendations = self.recommendations + 1
  local rec = ctx and ctx.recommendation
  if not rec then return false end

  local ok, _, reason = StepValidator.validate(ctx.playerPos, rec.direction, {
    world = ctx.world,
    ignoreCreatures = false,
    allowFields = (ctx.edgeKind == D.EDGE_KIND.FIELD_CROSSING),
    allowFloorChange = false,
    strictCorners = true,
  })
  if not ok then
    self.guardrailRejections = self.guardrailRejections + 1
    self.last = { accepted = false, reason = reason }
    Obs.bump("mlGuardrailRejections", 1)
    Obs.record({ reasonCodes = { D.REASON.ML_REJECTED_BY_GUARDRAIL }, detail = reason })
    return false
  end

  self.agreements = self.agreements + 1
  self.last = { accepted = true, direction = rec.direction }
  Obs.bump("mlShadowAgreement", 1)
  return true
end

function MLShadow:snapshot()
  local total = self.recommendations
  return {
    recommendations = total,
    agreements = self.agreements,
    guardrailRejections = self.guardrailRejections,
    agreementRate = (total > 0) and (self.agreements / total) or 0,
    last = self.last,
  }
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.ml_shadow"] = MLShadow end
return MLShadow