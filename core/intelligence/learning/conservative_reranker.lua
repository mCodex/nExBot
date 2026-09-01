local Reranker = {}
Reranker.__index = Reranker

local VALID_MODES = { OFF = true, OBSERVE = true, SHADOW = true, CANARY = true, ACTIVE = true }

function Reranker.new(config)
  if not config or not config.adjustmentBounds then
    error("Reranker.new: config must include 'adjustmentBounds'")
  end
  if not config.modelInterface then
    error("Reranker.new: config must include 'modelInterface'")
  end
  local self = setmetatable({}, Reranker)
  self._bounds = config.adjustmentBounds
  self._model = config.modelInterface
  self._lastAdjustment = 0
  return self
end

function Reranker:rerank(candidates, prediction, mode)
  if not candidates or #candidates == 0 then return {} end
  if not VALID_MODES[mode] then mode = "OFF" end
  if mode == "OFF" or mode == "OBSERVE" or mode == "SHADOW" then
    return candidates
  end

  local prediction_adjustment = 0
  if prediction and prediction.prediction and prediction.prediction.probability then
    prediction_adjustment = (prediction.prediction.probability - 0.5) * 0.05
  end

  local bounded = self._bounds:clamp(prediction_adjustment, mode)
  self._lastAdjustment = bounded

  local result = {}
  for i, c in ipairs(candidates) do
    result[i] = {
      id = c.id,
      score = c.score + bounded,
      tier = c.tier,
      originalScore = c.score,
    }
  end

  table.sort(result, function(a, b) return a.score > b.score end)
  return result
end

function Reranker:getAdjustment()
  return self._lastAdjustment
end

nExBot = nExBot or {}
nExBot.IntelligenceConservativeReranker = Reranker

return Reranker
