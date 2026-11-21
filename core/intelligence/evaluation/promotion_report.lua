IntelligencePromotionReport = {}
local Report = IntelligencePromotionReport
Report.__index = Report

local GATE_DEFS = {
  { key = "minEpisodes",          field = "episodes",                    check = function(v, cfg) return v >= cfg.minEpisodes end },
  { key = "minHunts",             field = "hunts",                       check = function(v, cfg) return v >= cfg.minHunts end },
  { key = "observationPeriod",    field = "observationDays",             check = function(v) return v >= 7 end },
  { key = "featureCoverage",      field = "featureCoverage",             check = function(v) return v >= 0.8 end },
  { key = "calibrationQuality",   field = "calibrationError",            check = function(v) return v <= 0.05 end },
  { key = "predictionError",      field = "predictionError",             check = function(v) return v <= 0.2 end },
  { key = "replayStable",         field = "replayStable",                check = function(v) return v == true end },
  { key = "safetyRegression",     field = "safetyRegression",            check = function(v) return v == false end },
  { key = "deathRegression",      field = "deathRegression",             check = function(v) return v == false end },
  { key = "pathFailureRegression",field = "pathFailureRegression",       check = function(v) return v == false end },
  { key = "targetThrashRegression", field = "targetThrashRegression",    check = function(v) return v == false end },
  { key = "lootCaptureRegression",field = "lootCaptureRegression",       check = function(v) return v == false end },
  { key = "resourceEfficiencyRegression", field = "resourceEfficiencyRegression", check = function(v) return v == false end },
  { key = "manualInterventionRegression", field = "manualInterventionRegression", check = function(v) return v == false end },
  { key = "performanceBudget",    field = "performanceBudgetOk",        check = function(v) return v == true end },
  { key = "persistenceValidation",field = "persistenceValid",            check = function(v) return v == true end },
  { key = "confidenceInterval",   field = "confidenceIntervalOk",       check = function(v) return v == true end },
}

function Report.new(config)
  config = config or {}
  return setmetatable({
    config = { minEpisodes = config.minEpisodes or 100, minHunts = config.minHunts or 10 },
  }, Report)
end

function Report:generate(model, metrics)
  metrics = metrics or {}
  local gates = {}
  for _, def in ipairs(GATE_DEFS) do
    local value = metrics[def.field]
    local passed
    if value == nil then
      passed = false
    else
      passed = def.check(value, self.config)
    end
    gates[#gates + 1] = { name = def.key, passed = passed, value = value }
  end
  local allPassed = true
  for _, g in ipairs(gates) do
    if not g.passed then allPassed = false break end
  end
  return { model = model, gates = gates, passed = allPassed }
end

function Report:canPromote(report)
  return report.passed == true
end

nExBot = nExBot or {}
nExBot.IntelligencePromotionReport = IntelligencePromotionReport

return IntelligencePromotionReport
