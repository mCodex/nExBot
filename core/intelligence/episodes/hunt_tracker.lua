local IntelligenceEpisodeBase = nExBot.IntelligenceEpisodeBase
  or dofile("core/intelligence/episodes/episode_base.lua")

local Tracker = {}
Tracker.__index = Tracker

function Tracker.new(config)
  if not config or not config.episodeBase then return nil end
  local self = setmetatable({}, Tracker)
  self._base = config.episodeBase
  self._episodes = {}
  self._open = {}
  return self
end

function Tracker:start(config)
  if not config then return nil end
  local required = { "huntId", "sessionId", "characterKey", "profileKey", "routeId" }
  for _, k in ipairs(required) do
    if config[k] == nil then return nil end
  end

  local ep = self._base:create({
    episodeId = config.huntId,
    episodeType = "hunt",
    sessionId = config.sessionId,
    huntId = config.huntId,
    routeId = config.routeId,
    startedAt = os.time(),
    metadata = config.metadata,
  })
  if not ep then return nil end

  ep.characterKey = config.characterKey
  ep.profileKey = config.profileKey
  ep.huntMetrics = {
    xpDelta = 0,
    lootValue = 0,
    resourcesConsumed = 0,
    deaths = 0,
    nearDeaths = 0,
    manualInterventions = 0,
    downtime = 0,
  }

  self._episodes[config.huntId] = ep
  self._open[config.huntId] = true
  return ep
end

function Tracker:close(huntId, reason)
  local ep = self._episodes[huntId]
  if not ep then return nil end
  if not self._open[huntId] then return nil end

  local closed = self._base:close(ep, reason)
  if not closed then return nil end

  self._episodes[huntId] = closed
  self._open[huntId] = nil
  return closed
end

function Tracker:get(huntId)
  return self._episodes[huntId]
end

function Tracker:getOpen()
  local result = {}
  for id in pairs(self._open) do
    table.insert(result, self._episodes[id])
  end
  return result
end

nExBot = nExBot or {}
nExBot.IntelligenceHuntTracker = Tracker

return Tracker
