--[[
  Bot Analytics Module
  
  Reports bot usage to nexbot.cc API.
  Uses g_http.get for OTClient compatibility (no POST support).
  
  Heartbeat sent on startup + every 5 minutes.
  Shutdown signal sent on game end.
]]

local Analytics = {}

local API_URL = "https://www.nexbot.cc/api/track"
local HEARTBEAT_INTERVAL = 300000 -- 5 minutes in ms
local botId = nil
local heartbeatTimer = nil

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
    g_http.get(url, function(_data, err)
      if err then
        warn("[Analytics] HTTP error: " .. tostring(err))
      end
    end)
    return true
  end
  if type(HTTP) == "table" and type(HTTP.get) == "function" then
    HTTP.get(url, function(_response, err)
      if err then
        warn("[Analytics] HTTP error: " .. tostring(err))
      end
    end)
    return true
  end
  return false
end

local function sendHeartbeat()
  local id = getBotId()
  local version = getVersion()
  local url = API_URL .. "?id=" .. id .. "&version=" .. version
  if not httpGet(url) then
    warn("[Analytics] No HTTP backend available")
  end
end

local function sendShutdown()
  local id = getBotId()
  local url = API_URL .. "?id=" .. id .. "&delete=true"
  httpGet(url)
end

function Analytics.start()
  sendHeartbeat()
  heartbeatTimer = periodic(HEARTBEAT_INTERVAL, function()
    sendHeartbeat()
  end)
end

function Analytics.stop()
  if heartbeatTimer then
    heartbeatTimer:cancel()
    heartbeatTimer = nil
  end
  sendShutdown()
end

return Analytics
