local TelemetryClient = {}
TelemetryClient.__index = TelemetryClient

local API_URL = "https://www.nexbot.cc/api/track"
local HEARTBEAT_INTERVAL = 300000

function TelemetryClient.new()
  local self = setmetatable({}, TelemetryClient)
  self.botId = nil
  self.heartbeatEvent = nil
  self.started = false
  return self
end

local function getBotId()
  if storage then
    storage.analyticsBotId = storage.analyticsBotId or tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
    return storage.analyticsBotId
  end
  return tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
end

local function getVersion()
  if nExBot and nExBot.version then
    return nExBot.version
  end
  return "unknown"
end

local function httpGet(url)
  if type(g_http) == "table" and type(g_http.get) == "function" then
    g_http.get(url, function(data, err)
      print("[Telemetry] g_http resp: data=" .. tostring(data) .. " err=" .. tostring(err))
    end)
    return true
  end
  if type(HTTP) == "table" and type(HTTP.get) == "function" then
    HTTP.get(url, function(response, err)
      print("[Telemetry] HTTP resp: data=" .. tostring(response) .. " err=" .. tostring(err))
    end)
    return true
  end
  return false
end

local function sendHeartbeat(self)
  local id = getBotId()
  local version = getVersion()
  local url = API_URL .. "?id=" .. id .. "&version=" .. version
  print("[Telemetry] Sending: " .. url)
  print("[Telemetry] g_http=" .. type(g_http) .. " HTTP=" .. type(HTTP))
  httpGet(url)
end

local function scheduleNext(self)
  self.heartbeatEvent = schedule(HEARTBEAT_INTERVAL, function()
    sendHeartbeat(self)
    scheduleNext(self)
  end)
end

function TelemetryClient:start()
  if self.started then return end
  self.started = true
  sendHeartbeat(self)
  scheduleNext(self)
end

function TelemetryClient:stop()
  if self.heartbeatEvent then
    removeEvent(self.heartbeatEvent)
    self.heartbeatEvent = nil
  end
  self.started = false
end

function TelemetryClient:isActive()
  return self.started
end

function TelemetryClient:getElapsed()
  return 0
end

nExBot = nExBot or {}
nExBot.TelemetryClient = TelemetryClient.new()

return TelemetryClient