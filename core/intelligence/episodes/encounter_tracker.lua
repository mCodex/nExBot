local IntelligenceOutcomeReasons = nExBot.IntelligenceOutcomeReasons
  or dofile("core/intelligence/contracts/outcome_reasons.lua")

local Tracker = {}
Tracker.__index = Tracker

function Tracker.new(config)
  local self = setmetatable({}, Tracker)
  self._episodeBase = config and config.episodeBase
  self._encounters = {}
  self._closedReasons = {}
  return self
end

function Tracker:start(config)
  if not config then return nil end
  if not config.encounterId then return nil end
  if not config.sessionId then return nil end
  if not config.huntId then return nil end
  if not config.targetInstanceId then return nil end
  if self._encounters[config.encounterId] then return nil end

  local ep = self._episodeBase:create({
    episodeId = config.encounterId,
    episodeType = "encounter",
    sessionId = config.sessionId,
    huntId = config.huntId,
    startedAt = os.time(),
  })
  if not ep then return nil end

  ep.encounterId = config.encounterId
  ep.targetInstanceId = config.targetInstanceId
  ep.encounters = {
    firstEngagement = 0,
    targetSwitches = 0,
    damageWindows = 0,
    resourceUses = 0,
  }

  self._encounters[config.encounterId] = ep
  return ep
end

function Tracker:close(encounterId, reason)
  if not encounterId then return nil end
  if not reason then return nil end
  if not IntelligenceOutcomeReasons.isValid(reason) then return nil end

  local ep = self._encounters[encounterId]
  if not ep then return nil end
  if ep.state ~= "open" then return nil end

  local closed = self._episodeBase:close(ep, reason)
  if not closed then return nil end

  self._encounters[encounterId] = closed
  self._closedReasons[reason] = (self._closedReasons[reason] or 0) + 1
  return closed
end

function Tracker:get(encounterId)
  if not encounterId then return nil end
  return self._encounters[encounterId]
end

function Tracker:getOpen()
  local result = {}
  for _, ep in pairs(self._encounters) do
    if ep.state == "open" then
      table.insert(result, ep)
    end
  end
  return result
end

function Tracker:stats()
  local total = 0
  local open = 0
  local closed = 0
  for _, ep in pairs(self._encounters) do
    total = total + 1
    if ep.state == "open" then
      open = open + 1
    else
      closed = closed + 1
    end
  end
  return { total = total, open = open, closed = closed, byReason = self._closedReasons }
end

nExBot = nExBot or {}
nExBot.IntelligenceEncounterTracker = Tracker

return Tracker
