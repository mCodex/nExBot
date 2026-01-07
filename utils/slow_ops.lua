-- Opt-in slow operation instrumentation (disabled by default)
-- Usage:
--  local slow = require('utils.slow_ops')
--  local t = slow.start('name')
--  ... heavy work ...
--  slow.finish(t, 'name')

local M = {}
M.records = {}
M.thresholdMs = 120 -- default threshold for recording (ms)

local function nowMs()
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.clock() * 1000
end

function M.isEnabled()
  return (type(nExBot) == 'table' and nExBot.slowOpInstrumentation) or false
end

function M.start(name)
  if not M.isEnabled() then return nil end
  return nowMs()
end

function M.finish(startMs, name)
  if not M.isEnabled() or not startMs then return end
  local elapsed = nowMs() - startMs
  if elapsed >= (M.thresholdMs or 120) then
    table.insert(M.records, { name = name, elapsed = elapsed, ts = os.date('%Y-%m-%d %H:%M:%S') })
  end
end

-- Convenience wrapper
function M.with(name, fn)
  if not M.isEnabled() then return fn() end
  local t = nowMs()
  local ok, res = pcall(fn)
  local elapsed = nowMs() - t
  if elapsed >= (M.thresholdMs or 120) then
    table.insert(M.records, { name = name, elapsed = elapsed, ts = os.date('%Y-%m-%d %H:%M:%S') })
  end
  if not ok then error(res) end
  return res
end

function M.dump(limit)
  limit = limit or 50
  table.sort(M.records, function(a,b) return a.elapsed > b.elapsed end)
  for i=1, math.min(limit, #M.records) do
    local r = M.records[i]
    print(string.format('[SLOW_OP] %s: %dms @ %s', r.name, math.floor(r.elapsed), r.ts))
  end
end

function M.clear()
  M.records = {}
end

return M
