local IntelligenceOutcomeReasons = nExBot.IntelligenceOutcomeReasons
  or dofile("core/intelligence/contracts/outcome_reasons.lua")

local EpisodeBase = {}
EpisodeBase.__index = EpisodeBase

local VALID_EPISODE_TYPES = {
  action = true,
  encounter = true,
  loot = true,
  route_segment = true,
  hunt = true,
}

local VALID_STATES = {
  open = true,
  closed = true,
}

function EpisodeBase.new(_config)
  local self = setmetatable({}, EpisodeBase)
  return self
end

function EpisodeBase:create(config)
  if not config then return nil end
  if not config.episodeId then return nil end
  if not config.episodeType then return nil end
  if not VALID_EPISODE_TYPES[config.episodeType] then return nil end
  if not config.sessionId then return nil end
  if not config.startedAt then return nil end

  return {
    episodeId = config.episodeId,
    episodeType = config.episodeType,
    sessionId = config.sessionId,
    huntId = config.huntId,
    routeId = config.routeId,
    segmentId = config.segmentId,
    encounterId = config.encounterId,
    startedAt = config.startedAt,
    closedAt = nil,
    state = "open",
    closureReason = nil,
    metadata = config.metadata or {},
  }
end

function EpisodeBase:close(episode, reason)
  if not episode then return nil end
  if episode.state ~= "open" then return episode end
  if not IntelligenceOutcomeReasons.isValid(reason) then return nil end

  local closed = {}
  for k, v in pairs(episode) do closed[k] = v end
  closed.state = "closed"
  closed.closedAt = os.time()
  closed.closureReason = reason
  return closed
end

function EpisodeBase:validate(episode)
  if type(episode) ~= "table" then return false end
  if type(episode.episodeId) ~= "string" then return false end
  if not VALID_STATES[episode.state] then return false end
  return true
end

function EpisodeBase:isOpen(episode)
  if type(episode) ~= "table" then return false end
  return episode.state == "open"
end

nExBot = nExBot or {}
nExBot.IntelligenceEpisodeBase = EpisodeBase

return EpisodeBase
