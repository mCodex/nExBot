local IntelligenceOutcomeReasons = nExBot.IntelligenceOutcomeReasons
  or dofile("core/intelligence/contracts/outcome_reasons.lua")
local EpisodeBase = nExBot.IntelligenceEpisodeBase
  or dofile("core/intelligence/episodes/episode_base.lua")

local Tracker = {}
Tracker.__index = Tracker

function Tracker.new(config)
  local self = setmetatable({}, Tracker)
  self._episodeBase = config.episodeBase or EpisodeBase
  self._episodes = {}
  self._closed = {}
  return self
end

function Tracker:start(config)
  if not config then return nil end
  if not config.lootEpisodeId then return nil end
  if not config.sessionId then return nil end
  if not config.corpseId then return nil end
  if not config.encounterId then return nil end
  if self._episodes[config.lootEpisodeId] then return nil end

  local ep = self._episodeBase:create({
    episodeId = config.lootEpisodeId,
    episodeType = "loot",
    sessionId = config.sessionId,
    huntId = config.huntId,
    encounterId = config.encounterId,
    startedAt = os.time(),
  })
  if not ep then return nil end

  ep.corpseId = config.corpseId
  ep.lootLifecycle = {
    corpseObserved = 0,
    corpseIdentified = 0,
    containerOpened = 0,
    itemsListed = 0,
    itemsAttempted = 0,
    itemsSucceeded = 0,
    itemsFailed = 0,
    captureVerified = 0,
  }

  self._episodes[config.lootEpisodeId] = ep
  return ep
end

function Tracker:close(lootEpisodeId, reason)
  local ep = self._episodes[lootEpisodeId]
  if not ep then return nil end
  if not IntelligenceOutcomeReasons.isValid(reason) then return nil end

  local closed = self._episodeBase:close(ep, reason)
  if not closed then return nil end
  self._episodes[lootEpisodeId] = nil
  self._closed[lootEpisodeId] = closed
  return closed
end

function Tracker:get(lootEpisodeId)
  return self._episodes[lootEpisodeId]
end

function Tracker:getOpen()
  local list = {}
  for _, ep in pairs(self._episodes) do
    if self._episodeBase:isOpen(ep) then
      table.insert(list, ep)
    end
  end
  return list
end

function Tracker:stats()
  local total, open, closed, byReason = 0, 0, 0, {}
  for _ in pairs(self._episodes) do
    total = total + 1
    open = open + 1
  end
  for _, ep in pairs(self._closed) do
    total = total + 1
    closed = closed + 1
    byReason[ep.closureReason] = (byReason[ep.closureReason] or 0) + 1
  end
  return { total = total, open = open, closed = closed, byReason = byReason }
end

nExBot = nExBot or {}
nExBot.IntelligenceLootEpisodeTracker = Tracker

return Tracker
