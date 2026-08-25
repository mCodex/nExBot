local Session = {}
Session.__index = Session

function Session.new(config)
  local self = setmetatable({}, Session)
  config = config or {}
  self.root = config.root or ""
  self.now = config.now or os.time
  self.schemaVersion = config.schemaVersion or 1
  self.collectorVersion = config.collectorVersion or "1.0.0"
  self.botVersion = config.botVersion or "unknown"
  self.active = false
  self.sessionId = nil
  self.characterScope = nil
  self.dir = nil
  self.startedAt = nil
  self.endedAt = nil
  self.closeReason = nil
  return self
end

function Session:open(sessionId, characterScope)
  if type(sessionId) ~= "string" or sessionId == "" then
    return false, "invalid_session_id"
  end
  if self.active then
    return false, "already_active"
  end

  self.sessionId = sessionId
  self.characterScope = characterScope or ""
  self.startedAt = self.now()
  self.active = true
  self.endedAt = nil
  self.closeReason = nil
  self.dir = self.root .. os.date("%Y-%m-%d", self.startedAt) .. "/session-" .. sessionId .. "/"

  return true, self.dir
end

function Session:close(reason)
  if not self.active then
    return false, "not_active"
  end

  self.endedAt = self.now()
  self.active = false
  self.closeReason = reason or "unknown"

  return true, self:manifest()
end

function Session:isActive()
  return self.active
end

function Session:currentDir()
  return self.dir
end

function Session:manifest()
  return {
    schemaVersion = self.schemaVersion,
    collectorVersion = self.collectorVersion,
    botVersion = self.botVersion,
    sessionId = self.sessionId,
    characterScope = self.characterScope,
    startedAt = self.startedAt,
    endedAt = self.endedAt,
    closeReason = self.closeReason,
    active = self.active,
  }
end

nExBot = nExBot or {}
nExBot.IntelligenceTelemetrySession = Session

return Session
