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
  local required = { "segmentId", "sessionId", "huntId", "routeId", "routeGeneration", "startWaypoint" }
  for _, k in ipairs(required) do
    if config[k] == nil then return nil end
  end

  local ep = self._base:create({
    episodeId = config.segmentId,
    episodeType = "route_segment",
    sessionId = config.sessionId,
    huntId = config.huntId,
    routeId = config.routeId,
    segmentId = config.segmentId,
    startedAt = os.time(),
    metadata = config.metadata,
  })
  if not ep then return nil end

  ep.routeGeneration = config.routeGeneration
  ep.startWaypoint = config.startWaypoint
  ep.segmentMetrics = {
    retries = 0,
    stuckEvents = 0,
    deviations = 0,
    pathFailures = 0,
  }

  self._episodes[config.segmentId] = ep
  self._open[config.segmentId] = true
  return ep
end

function Tracker:close(segmentId, reason)
  local ep = self._episodes[segmentId]
  if not ep then return nil end
  if not self._open[segmentId] then return nil end

  local closed = self._base:close(ep, reason)
  if not closed then return nil end

  self._episodes[segmentId] = closed
  self._open[segmentId] = nil
  return closed
end

function Tracker:get(segmentId)
  return self._episodes[segmentId]
end

function Tracker:getOpen()
  local result = {}
  for id in pairs(self._open) do
    table.insert(result, self._episodes[id])
  end
  return result
end

nExBot = nExBot or {}
nExBot.IntelligenceRouteSegmentTracker = Tracker

return Tracker
