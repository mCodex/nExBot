local Session = nExBot and nExBot.IntelligenceTelemetrySession or dofile("core/intelligence/telemetry/session.lua")
local Buffer = nExBot and nExBot.IntelligenceTelemetryBuffer or dofile("core/intelligence/telemetry/buffer.lua")
local Writer = nExBot and nExBot.IntelligenceTelemetryWriter or dofile("core/intelligence/telemetry/writer.lua")
local Retention = nExBot and nExBot.IntelligenceTelemetryRetention or dofile("core/intelligence/telemetry/retention.lua")

local DEFAULT_MAX_EVENTS_PER_FLUSH = 500
local DEFAULT_RETENTION_INTERVAL_FLUSHES = 60

local Collector = {}
Collector.__index = Collector

function Collector.new(config)
  config = config or {}
  local self = setmetatable({}, Collector)

  self.resources = config.resources
  self.codec = config.codec
  self.root = config.root or ""

  self.session = Session.new({
    root = self.root,
    now = config.now,
    schemaVersion = config.schemaVersion,
    collectorVersion = config.collectorVersion,
    botVersion = config.botVersion,
  })
  self.buffer = Buffer.new({ maxSize = config.maxBufferSize, priorityFor = config.priorityFor })
  self.writer = Writer.new({ resources = self.resources, codec = self.codec })
  self.retention = Retention.new({
    resources = self.resources,
    maxSessions = config.maxSessions,
    maxAgeSeconds = config.maxAgeSeconds,
    now = config.now,
  })

  self.maxEventsPerFlush = config.maxEventsPerFlush or DEFAULT_MAX_EVENTS_PER_FLUSH
  self.retentionIntervalFlushes = config.retentionIntervalFlushes or DEFAULT_RETENTION_INTERVAL_FLUSHES
  self._chunkIndex = 0
  self._flushCount = 0
  self._unsubscribe = nil

  return self
end

function Collector:attach(eventAggregator)
  if self._unsubscribe then return true end
  if not eventAggregator or type(eventAggregator.subscribeAll) ~= "function" then return false end

  local self_ = self
  self._unsubscribe = eventAggregator:subscribeAll(function(event)
    self_:capture(event)
  end)
  return true
end

function Collector:detach()
  if self._unsubscribe then
    self._unsubscribe()
    self._unsubscribe = nil
  end
end

-- Only buffered while a session is active: nothing durable exists yet to flush
-- pre-session events into, and this keeps memory bounded during idle periods.
function Collector:capture(event)
  if type(event) ~= "table" or type(event.type) ~= "string" then return false end
  if not self.session:isActive() then return false end
  return self.buffer:push(event)
end

function Collector:startSession(sessionId, characterScope)
  local ok, dirOrErr = self.session:open(sessionId, characterScope)
  if not ok then return false, dirOrErr end

  self._chunkIndex = 0
  self.writer:writeManifest(self.session:currentDir(), self.session:manifest())
  return true, dirOrErr
end

function Collector:endSession(reason)
  if not self.session:isActive() then return false, "not_active" end

  local dir = self.session:currentDir()
  self:flush()

  local ok, manifest = self.session:close(reason)
  if ok and dir then
    self.writer:writeManifest(dir, manifest)
  end
  return ok, manifest
end

function Collector:flush()
  if not self.session:isActive() then return false end
  if self.buffer:size() == 0 then return true end

  local events = self.buffer:drain(self.maxEventsPerFlush)
  if #events == 0 then return true end

  self._chunkIndex = self._chunkIndex + 1
  local ok = self.writer:writeChunk(self.session:currentDir(), self._chunkIndex, events)

  self._flushCount = self._flushCount + 1
  if self._flushCount % self.retentionIntervalFlushes == 0 then
    self.retention:enforce(self.root, self.session:currentDir())
  end

  return ok
end

function Collector:stats()
  return {
    bufferedEvents = self.buffer:size(),
    bufferStats = self.buffer:stats(),
    sessionActive = self.session:isActive(),
    sessionDir = self.session:currentDir(),
    chunkIndex = self._chunkIndex,
  }
end

nExBot = nExBot or {}
nExBot.IntelligenceTelemetryCollector = Collector

return Collector
