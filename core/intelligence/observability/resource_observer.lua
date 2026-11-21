local RingBuffer = nExBot and nExBot.RingBuffer or dofile("utils/ring_buffer.lua")

IntelligenceResourceObserver = {}
local ResourceObserver = IntelligenceResourceObserver
ResourceObserver.__index = ResourceObserver

local FIELDS = {
  "hpPotions", "manaPotions", "runes", "ammunition", "healingCasts",
  "emergencyHeals", "damageTaken", "burstDamage", "timeBelowSafeHp", "combatTime",
}
local METADATA = { "timestamp", "latencyClass", "observationQuality", "confidence", "correlationId" }

local function normalize(values, metadata)
  for _, name in ipairs(METADATA) do
    if metadata[name] == nil then return nil, "missing_" .. name end
  end
  local result = {}
  for _, name in ipairs(FIELDS) do
    local value = tonumber(values[name])
    if value and value > 0 then result[name] = value end
  end
  for _, name in ipairs(METADATA) do result[name] = metadata[name] end
  return result
end

function ResourceObserver.new(maxObservations)
  return setmetatable({ history = RingBuffer.new(maxObservations or 500) }, ResourceObserver)
end

function ResourceObserver:observe(values, metadata)
  local observation, err = normalize(values or {}, metadata or {})
  if not observation then return nil, err end
  self.history:push(observation)
  return observation
end

function ResourceObserver:recent()
  return self.history:toArray()
end

function ResourceObserver:totals()
  local totals = {}
  for observation in self.history:iterate() do
    for _, name in ipairs(FIELDS) do
      if observation[name] then totals[name] = (totals[name] or 0) + observation[name] end
    end
  end
  return totals
end

return ResourceObserver
