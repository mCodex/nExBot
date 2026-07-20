--[[
  Backward compatibility shim for nExBot.Analytics
  Redirects to nExBot.TelemetryClient
]]

local Analytics = {}

function Analytics.start()
  if nExBot.TelemetryClient then
    return nExBot.TelemetryClient:start()
  end
end

function Analytics.stop()
  if nExBot.TelemetryClient then
    return nExBot.TelemetryClient:stop()
  end
end

function Analytics.isActive()
  if nExBot.TelemetryClient then
    return nExBot.TelemetryClient:isActive()
  end
  return false
end

function Analytics.getElapsed()
  if nExBot.TelemetryClient then
    return nExBot.TelemetryClient:getElapsed()
  end
  return 0
end

nExBot.Analytics = Analytics

return Analytics
