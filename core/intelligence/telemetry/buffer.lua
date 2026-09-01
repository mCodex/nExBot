local DEFAULT_MAX_SIZE = 2000
local DEFAULT_PRIORITY = 2
local WORST_TIER = 4

local TelemetryBuffer = {}
TelemetryBuffer.__index = TelemetryBuffer

-- Each tier is a queue with running head/tail indices (no table.remove(t,1)
-- shifting): push appends at last+1, pop clears and advances first.
local function newTier()
  return { items = {}, first = 1, last = 0 }
end

local function tierCount(tier)
  return tier.last - tier.first + 1
end

local function tierPush(tier, event)
  tier.last = tier.last + 1
  tier.items[tier.last] = event
end

local function tierPopFront(tier)
  if tier.first > tier.last then return nil end
  local item = tier.items[tier.first]
  tier.items[tier.first] = nil
  tier.first = tier.first + 1
  return item
end

function TelemetryBuffer.new(config)
  config = config or {}
  local self = setmetatable({}, TelemetryBuffer)
  self.maxSize = config.maxSize or DEFAULT_MAX_SIZE
  self.priorityFor = config.priorityFor
  self.defaultPriority = config.defaultPriority or DEFAULT_PRIORITY

  self._size = 0
  self._accepted = 0
  self._tiers = {}
  self._dropped = {}
  for tier = 0, WORST_TIER do
    self._tiers[tier] = newTier()
    self._dropped[tier] = 0
  end

  return self
end

function TelemetryBuffer:priorityOf(eventType)
  if type(self.priorityFor) == "function" then
    local priority = self.priorityFor(eventType)
    if type(priority) == "number" and priority >= 0 and priority <= WORST_TIER then
      return priority
    end
  end
  return self.defaultPriority
end

function TelemetryBuffer:push(event)
  if type(event) ~= "table" or type(event.type) ~= "string" then
    return false
  end

  local priority = self:priorityOf(event.type)

  if self._size < self.maxSize then
    tierPush(self._tiers[priority], event)
    self._size = self._size + 1
    self._accepted = self._accepted + 1
    return true
  end

  local worst = nil
  for tier = WORST_TIER, 0, -1 do
    if tierCount(self._tiers[tier]) > 0 then
      worst = tier
      break
    end
  end

  if worst and priority < worst then
    tierPopFront(self._tiers[worst])
    self._dropped[worst] = self._dropped[worst] + 1
    tierPush(self._tiers[priority], event)
    self._accepted = self._accepted + 1
    return true
  end

  self._dropped[priority] = self._dropped[priority] + 1
  return false
end

function TelemetryBuffer:drain(maxCount)
  local result = {}
  local remaining = maxCount

  for tier = 0, WORST_TIER do
    if remaining ~= nil and remaining <= 0 then break end
    local t = self._tiers[tier]
    while tierCount(t) > 0 and (remaining == nil or remaining > 0) do
      result[#result + 1] = tierPopFront(t)
      self._size = self._size - 1
      if remaining ~= nil then remaining = remaining - 1 end
    end
  end

  return result
end

function TelemetryBuffer:size()
  return self._size
end

function TelemetryBuffer:stats()
  local dropped = {}
  local droppedTotal = 0
  for tier = 0, WORST_TIER do
    dropped[tier] = self._dropped[tier]
    droppedTotal = droppedTotal + self._dropped[tier]
  end

  return {
    size = self._size,
    capacity = self.maxSize,
    accepted = self._accepted,
    dropped = dropped,
    droppedTotal = droppedTotal,
  }
end

nExBot = nExBot or {}
nExBot.IntelligenceTelemetryBuffer = TelemetryBuffer

return TelemetryBuffer
