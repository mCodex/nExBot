local RingBuffer = nExBot and nExBot.RingBuffer or dofile("utils/ring_buffer.lua")

IntelligenceMetrics = {}
local Metrics = IntelligenceMetrics
Metrics.__index = Metrics

local function number(value, name)
  assert(type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge,
    name .. " must be finite")
end

function Metrics.new(maxSamples)
  maxSamples = maxSamples or 100
  assert(type(maxSamples) == "number" and maxSamples >= 1, "maxSamples must be positive")
  return setmetatable({ maxSamples = maxSamples, counters = {}, gauges = {}, samples = {} }, Metrics)
end

function Metrics:increment(name, amount)
  assert(type(name) == "string" and name ~= "", "metric name is required")
  amount = amount or 1
  number(amount, "counter amount")
  assert(amount >= 0, "counter amount must be non-negative")
  self.counters[name] = (self.counters[name] or 0) + amount
end

function Metrics:gauge(name, value)
  assert(type(name) == "string" and name ~= "", "metric name is required")
  number(value, "gauge value")
  self.gauges[name] = value
end

function Metrics:sample(name, value)
  assert(type(name) == "string" and name ~= "", "metric name is required")
  number(value, "sample value")
  local samples = self.samples[name]
  if not samples then
    samples = RingBuffer.new(self.maxSamples)
    self.samples[name] = samples
  end
  samples:push(value)
end

function Metrics:snapshot()
  local result = { counters = {}, gauges = {}, samples = {}, averages = {} }
  for name, value in pairs(self.counters) do result.counters[name] = value end
  for name, value in pairs(self.gauges) do result.gauges[name] = value end
  for name, samples in pairs(self.samples) do
    result.samples[name] = samples:toArray()
    result.averages[name] = samples:average(function(value) return value end)
  end
  return result
end

return Metrics
