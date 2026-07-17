local RingBuffer = nExBot and nExBot.RingBuffer or dofile("utils/ring_buffer.lua")

IntelligenceLootObserver = {}
local LootObserver = IntelligenceLootObserver
LootObserver.__index = LootObserver

local METADATA = { "timestamp", "latencyClass", "observationQuality", "confidence", "correlationId" }

function LootObserver.new(maxObservations, maxItems)
  return setmetatable({
    history = RingBuffer.new(maxObservations or 500),
    maxItems = maxItems or 100,
  }, LootObserver)
end

function LootObserver.adapt(adapter, payload, metadata)
  assert(type(adapter) == "function", "loot adapter must be a function")
  local observation = adapter(payload) or {}
  for _, name in ipairs(METADATA) do observation[name] = metadata and metadata[name] end
  return observation
end

function LootObserver:observe(observation)
  observation = observation or {}
  for _, name in ipairs(METADATA) do
    if observation[name] == nil then return nil, "missing_" .. name end
  end

  local normalized = {
    monsterId = observation.monsterId,
    corpseId = observation.corpseId,
    routeSegment = observation.routeSegment,
    combatDuration = math.max(0, tonumber(observation.combatDuration) or 0),
    resourcesConsumed = observation.resourcesConsumed,
    itemsAvailable = math.max(0, tonumber(observation.itemsAvailable) or 0),
    itemsCaptured = math.max(0, tonumber(observation.itemsCaptured) or 0),
    items = {},
  }
  normalized.itemsCaptured = math.min(normalized.itemsCaptured, normalized.itemsAvailable)
  for index = 1, math.min(#(observation.items or {}), self.maxItems) do
    local item = observation.items[index]
    normalized.items[index] = { id = item.id, count = math.max(0, tonumber(item.count) or 0) }
  end
  for _, name in ipairs(METADATA) do normalized[name] = observation[name] end
  self.history:push(normalized)
  return normalized
end

function LootObserver:recent()
  return self.history:toArray()
end

function LootObserver:captureRate()
  local available, captured = 0, 0
  for observation in self.history:iterate() do
    available = available + observation.itemsAvailable
    captured = captured + observation.itemsCaptured
  end
  return available > 0 and captured / available or 0
end

return LootObserver
