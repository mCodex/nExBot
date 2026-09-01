IntelligenceTacticalMemory = {}
local TacticalMemory = IntelligenceTacticalMemory
TacticalMemory.__index = TacticalMemory

function TacticalMemory.new(options)
  options = options or {}
  return setmetatable({ entries = {}, size = 0, maxEntries = options.maxEntries or 128, ttlMs = options.ttlMs or 300000 }, TacticalMemory)
end

function TacticalMemory:compact(now)
  for key, entry in pairs(self.entries) do
    if now - entry.updatedAt >= self.ttlMs then self.entries[key], self.size = nil, self.size - 1 end
  end
  while self.size > self.maxEntries do
    local oldestKey, oldest
    for key, entry in pairs(self.entries) do
      if not oldest or entry.updatedAt < oldest or entry.updatedAt == oldest and tostring(key) < tostring(oldestKey) then
        oldestKey, oldest = key, entry.updatedAt
      end
    end
    self.entries[oldestKey], self.size = nil, self.size - 1
  end
end

function TacticalMemory:remember(key, value, now)
  assert(key ~= nil and type(now) == "number", "invalid tactical memory")
  if not self.entries[key] then self.size = self.size + 1 end
  self.entries[key] = { value = value, updatedAt = now }
  self:compact(now)
end

function TacticalMemory:get(key, now)
  self:compact(now)
  local entry = self.entries[key]
  if not entry then return nil end
  return entry.value, math.max(0, 1 - (now - entry.updatedAt) / self.ttlMs)
end

return TacticalMemory
