local IntelligenceEventDeduplicator = {}
IntelligenceEventDeduplicator.__index = IntelligenceEventDeduplicator

function IntelligenceEventDeduplicator.new(config)
  local self = setmetatable({}, IntelligenceEventDeduplicator)
  local cfg = config or {}
  self._maxSize = cfg.maxSize or 1000
  self._seen = {}
  self._keyMap = {}
  self._order = {}
  self._totalSeen = 0
  self._totalDuplicates = 0
  return self
end

function IntelligenceEventDeduplicator:isDuplicate(event)
  if type(event) ~= "table" then return false end
  local eid = event.eventId
  if type(eid) == "string" and self._seen[eid] then return true end
  local idem = event.idempotencyKey
  if type(idem) == "string" and self._seen[idem] then return true end
  return false
end

function IntelligenceEventDeduplicator:record(event)
  if type(event) ~= "table" then return end
  local eid = event.eventId
  if type(eid) ~= "string" then return end

  self._totalSeen = self._totalSeen + 1

  if self._seen[eid] then
    self._totalDuplicates = self._totalDuplicates + 1
    return
  end

  local idem = event.idempotencyKey
  if type(idem) == "string" and self._seen[idem] then
    self._totalDuplicates = self._totalDuplicates + 1
    return
  end

  while #self._order >= self._maxSize do
    local oldest = table.remove(self._order, 1)
    self._seen[oldest] = nil
    local idem = self._keyMap[oldest]
    if idem then
      self._seen[idem] = nil
      self._keyMap[oldest] = nil
    end
  end

  table.insert(self._order, eid)
  self._seen[eid] = true

  if type(idem) == "string" then
    self._seen[idem] = true
    self._keyMap[eid] = idem
  end
end

function IntelligenceEventDeduplicator:stats()
  return {
    totalSeen = self._totalSeen,
    totalDuplicates = self._totalDuplicates,
    total = self._totalSeen - self._totalDuplicates,
    maxSize = self._maxSize,
  }
end

function IntelligenceEventDeduplicator:reset()
  self._seen = {}
  self._keyMap = {}
  self._order = {}
  self._totalSeen = 0
  self._totalDuplicates = 0
end

nExBot = nExBot or {}
nExBot.IntelligenceEventDeduplicator = IntelligenceEventDeduplicator

return IntelligenceEventDeduplicator
