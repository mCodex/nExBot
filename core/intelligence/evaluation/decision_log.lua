local DEFAULT_MAX_SIZE = 10000

local DecisionLog = {}
DecisionLog.__index = DecisionLog

function DecisionLog.new(config)
  local self = setmetatable({}, DecisionLog)
  config = config or {}
  self._entries = {}
  self._maxSize = config.maxSize or DEFAULT_MAX_SIZE
  return self
end

function DecisionLog:log(decision)
  if type(decision) ~= "table" then return false end
  if type(decision.decisionId) ~= "string" then return false end
  if type(decision.decisionType) ~= "string" then return false end

  table.insert(self._entries, decision)

  while #self._entries > self._maxSize do
    table.remove(self._entries, 1)
  end

  return true
end

function DecisionLog:getLogs(criteria)
  criteria = criteria or {}
  local results = {}

  for i = #self._entries, 1, -1 do
    local entry = self._entries[i]
    local match = true

    if criteria.decisionType and entry.decisionType ~= criteria.decisionType then
      match = false
    end
    if criteria.sessionId and entry.sessionId ~= criteria.sessionId then
      match = false
    end
    if criteria.huntId and entry.huntId ~= criteria.huntId then
      match = false
    end

    if match then
      table.insert(results, 1, entry)
    end
  end

  if criteria.limit and #results > criteria.limit then
    for i = #results, criteria.limit + 1, -1 do
      results[i] = nil
    end
  end

  return results
end

function DecisionLog:getStats()
  local stats = { total = #self._entries, byType = {}, bySession = {} }

  for _, entry in ipairs(self._entries) do
    stats.byType[entry.decisionType] = (stats.byType[entry.decisionType] or 0) + 1
    stats.bySession[entry.sessionId] = (stats.bySession[entry.sessionId] or 0) + 1
  end

  return stats
end

nExBot = nExBot or {}
nExBot.IntelligenceDecisionLog = DecisionLog

return DecisionLog
