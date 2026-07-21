IntelligenceDecisionExplainer = {}
local Explainer = IntelligenceDecisionExplainer
Explainer.__index = Explainer

function Explainer.new(_config)
  return setmetatable({}, Explainer)
end

function Explainer:explain(decision)
  decision = decision or {}
  local prediction = decision.prediction or {}
  local baseline = decision.baseline or {}

  local factors = {}
  if decision.factors then
    for _, f in ipairs(decision.factors) do
      factors[#factors + 1] = type(f) == "table" and f.name or tostring(f)
    end
  end

  return {
    baseline = {
      choice = baseline.selectedCandidateId,
      score = baseline.score or 0,
    },
    selected = decision.selectedCandidateId,
    adjustment = prediction.adjustment or 0,
    confidence = prediction.confidence or 0,
    evidence = prediction.evidence or 0,
    factors = factors,
    guardrails = decision.guardrails or {},
    pricesKnown = decision.pricesKnown or false,
    modelVersion = prediction.modelVersion or 0,
  }
end

function Explainer:format(explanation)
  explanation = explanation or {}
  local b = explanation.baseline or {}
  if not b.choice and not explanation.selected then
    return "No decision to explain"
  end

  local parts = {}
  parts[#parts + 1] = "Baseline: " .. tostring(b.choice or "?") .. " (score " .. tostring(b.score or 0) .. ")"
  parts[#parts + 1] = "Selected: " .. tostring(explanation.selected or "?")
  parts[#parts + 1] = "Adjustment: " .. tostring(explanation.adjustment or 0)
  parts[#parts + 1] = "Confidence: " .. tostring(explanation.confidence or 0) .. " (evidence " .. tostring(explanation.evidence or 0) .. ")"

  if #explanation.factors > 0 then
    parts[#parts + 1] = "Factors: " .. table.concat(explanation.factors, ", ")
  end
  if #explanation.guardrails > 0 then
    parts[#parts + 1] = "Guardrails: " .. table.concat(explanation.guardrails, ", ")
  end

  parts[#parts + 1] = "Prices known: " .. tostring(explanation.pricesKnown)
  parts[#parts + 1] = "Model v" .. tostring(explanation.modelVersion)

  return table.concat(parts, "\n")
end

nExBot = nExBot or {}
nExBot.IntelligenceDecisionExplainer = Explainer

return Explainer
