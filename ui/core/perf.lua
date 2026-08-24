--[[
  Perf — bounded timing capture for UI operations (render, tick, module switch).

  Uses RingBuffer-style bounded arrays so memory stays stable under long
  sessions. p95/p99 are computed from the bounded sample window, never from an
  unbounded log. All operations are cheap; callers opt in on hot paths.
]]

local Perf = {}
local buckets = {}

Perf.bucketSize = 256

local function ensure(name)
  local bucket = buckets[name]
  if not bucket then
    bucket = { samples = {}, count = 0 }
    buckets[name] = bucket
  end
  return bucket
end

function Perf.begin(name)
  ensure(name)._start = os.clock()
end

function Perf.end_(name)
  local bucket = buckets[name]
  if not bucket or not bucket._start then return end
  local elapsed = (os.clock() - bucket._start) * 1000
  bucket._start = nil
  local samples = bucket.samples
  if #samples >= Perf.bucketSize then
    table.remove(samples, 1)
  end
  samples[#samples + 1] = elapsed
  bucket.count = bucket.count + 1
end

function Perf.stats(name)
  local bucket = buckets[name]
  if not bucket or #bucket.samples == 0 then return nil end
  return {
    samples = #bucket.samples,
    total = bucket.count,
    mean = (function()
      local s = 0
      for i = 1, #bucket.samples do s = s + bucket.samples[i] end
      return s / #bucket.samples
    end)(),
  }
end

local function percentile(name, p)
  local bucket = buckets[name]
  if not bucket or #bucket.samples == 0 then return nil end
  local sorted = {}
  for i = 1, #bucket.samples do sorted[i] = bucket.samples[i] end
  table.sort(sorted)
  local idx = math.max(1, math.ceil(#sorted * p))
  return sorted[idx]
end

function Perf.p95(name) return percentile(name, 0.95) end
function Perf.p99(name) return percentile(name, 0.99) end

function Perf.reset()
  buckets = {}
end

Perf.ops = function() return buckets end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.Perf = Perf
end

return Perf
