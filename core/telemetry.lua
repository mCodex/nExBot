-- Simple Telemetry helper
nExBot = nExBot or {}
nExBot.Telemetry = nExBot.Telemetry or { counters = {} }

nExBot.Telemetry.increment = function(name, amount)
  amount = amount or 1
  nExBot.Telemetry.counters[name] = (nExBot.Telemetry.counters[name] or 0) + amount
end

nExBot.Telemetry.get = function(name)
  if name then return nExBot.Telemetry.counters[name] or 0 end
  return nExBot.Telemetry.counters
end

return nExBot.Telemetry