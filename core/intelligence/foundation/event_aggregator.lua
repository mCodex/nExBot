local RingBuffer = nExBot and nExBot.RingBuffer or dofile("utils/ring_buffer.lua")
local nowMs = nExBot and nExBot.Shared and nExBot.Shared.nowMs or function() return os.time() * 1000 end

IntelligenceEventAggregator = {}
IntelligenceEventAggregator.__index = IntelligenceEventAggregator

local function copy(source, seen)
  if type(source) ~= "table" then return source end
  seen = seen or {}
  if seen[source] then return seen[source] end
  local result = {}
  seen[source] = result
  for key, value in pairs(source) do result[copy(key, seen)] = copy(value, seen) end
  return result
end

function IntelligenceEventAggregator.new(options)
  options = options or {}
  return setmetatable({
    now = options.now or nowMs,
    listeners = {},
    listenerOrder = 0,
    generations = { snapshot = 0, route = 0, combat = 0 },
    history = RingBuffer.new(options.maxEvents or 500),
  }, IntelligenceEventAggregator)
end

function IntelligenceEventAggregator:setGenerations(generations)
  for name, value in pairs(generations) do self.generations[name] = value end
end

function IntelligenceEventAggregator:subscribe(eventType, callback, priority)
  local listeners = self.listeners[eventType] or {}
  self.listeners[eventType] = listeners
  self.listenerOrder = self.listenerOrder + 1
  local entry = { callback = callback, priority = priority or 0, order = self.listenerOrder }
  listeners[#listeners + 1] = entry
  table.sort(listeners, function(a, b)
    return a.priority == b.priority and a.order < b.order or a.priority > b.priority
  end)
  return function()
    for index, listener in ipairs(listeners) do
      if listener == entry then table.remove(listeners, index); return end
    end
  end
end

function IntelligenceEventAggregator:publish(eventType, payload, metadata)
  metadata = metadata or {}
  assert(metadata.source, "event source is required")

  for _, name in ipairs({ "snapshot", "route", "combat" }) do
    local value = metadata[name .. "Generation"]
    if value and value < self.generations[name] then
      return nil, "stale_" .. name .. "_generation"
    end
  end

  local event = {
    type = eventType,
    timestamp = self.now(),
    source = metadata.source,
    snapshotGeneration = metadata.snapshotGeneration or self.generations.snapshot,
    routeGeneration = metadata.routeGeneration or self.generations.route,
    combatGeneration = metadata.combatGeneration or self.generations.combat,
    payload = copy(payload),
  }
  if metadata.correlationId then event.correlationId = metadata.correlationId end

  self.history:push(event)
  for _, listener in ipairs(self.listeners[eventType] or {}) do
    local ok, err = pcall(listener.callback, copy(event))
    if not ok and warn then warn("[IntelligenceEventAggregator] " .. tostring(err)) end
  end
  return copy(event)
end

function IntelligenceEventAggregator:recent()
  return copy(self.history:toArray())
end

return IntelligenceEventAggregator
