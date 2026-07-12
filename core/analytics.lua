--[[
  Bot Analytics Module
  
  Reports bot usage to nexbot.cc API.
  Uses g_http.get for OTClient compatibility (no POST support).
  
  Heartbeat sent after game starts + every 5 minutes.
  Last-seen state is retained after game end.
]]

local Analytics = {}

local API_URL = "https://www.nexbot.cc/api/track"
local HEARTBEAT_INTERVAL = 300000 -- 5 minutes in ms
local botId = nil
local heartbeatEvent = nil
local started = false

local function getBotId()
  if botId then return botId end
  if storage then
    storage.analyticsBotId = storage.analyticsBotId or tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
    botId = storage.analyticsBotId
  else
    botId = tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
  end
  return botId
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
      print("[Analytics] g_http resp: data=" .. tostring(data) .. " err=" .. tostring(err))
    end)
    return true
  end
  if type(HTTP) == "table" and type(HTTP.get) == "function" then
    HTTP.get(url, function(response, err)
      print("[Analytics] HTTP resp: data=" .. tostring(response) .. " err=" .. tostring(err))
    end)
    return true
  end
  return false
end

local function sendHeartbeat()
  local id = getBotId()
  local version = getVersion()
  local url = API_URL .. "?id=" .. id .. "&version=" .. version
  print("[Analytics] Sending: " .. url)
  print("[Analytics] g_http=" .. type(g_http) .. " HTTP=" .. type(HTTP))
  httpGet(url)
end

local function startHeartbeat()
  if started then return end
  started = true
  sendHeartbeat()
  local function scheduleNext()
    heartbeatEvent = schedule(HEARTBEAT_INTERVAL, function()
      sendHeartbeat()
      scheduleNext()
    end)
  end
  scheduleNext()
end

function Analytics.start()
  schedule(3000, startHeartbeat)
end

function Analytics.stop()
  if heartbeatEvent then
    removeEvent(heartbeatEvent)
    heartbeatEvent = nil
  end
end

nExBot.Analytics = Analytics
