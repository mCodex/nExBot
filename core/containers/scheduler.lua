-- scheduler.lua
-- Serializes container open and move actions.
-- Enforces: one open in flight, cooldown, ack timeout, exhaustion backoff.
-- Generation-aware: rejects actions from a previous generation.

local Queue = dofile("core/containers/queue.lua")

local Scheduler = {}

-- Priority constants (lower = higher priority).
Scheduler.Priority = {
  EMERGENCY_SURVIVAL      = 0,
  CRITICAL_HEAL           = 1,
  EMERGENCY_ESCAPE        = 2,
  CRITICAL_AMMO_REFILL    = 3,
  CRITICAL_CONTAINER      = 4,
  COMBAT_SUPPORT          = 5,
  NORMAL_DISCOVERY        = 25,
  LOOT_SORTING            = 50,
  MAINTENANCE             = 100,
}

-- Exhaustion reason codes.
Scheduler.Reason = {
  SERVER_EXHAUSTED  = "SERVER_EXHAUSTED",
  ACTION_COOLDOWN   = "ACTION_COOLDOWN",
  ACK_TIMEOUT       = "ACK_TIMEOUT",
  CONTAINER_LIMIT   = "CONTAINER_LIMIT",
  STALE_GENERATION  = "STALE_GENERATION",
  UNKNOWN           = "UNKNOWN",
}

local DEFAULT_COOLDOWN_MS  = 400
local DEFAULT_ACK_TIMEOUT  = 5000
local MAX_BACKOFF_MS       = 30000
local BASE_BACKOFF_MS      = 1000
local MAX_EXHAUSTION_LOG   = 20

function Scheduler.new()
  return setmetatable({
    queue            = Queue.new(200),
    generation       = 0,
    activeAction     = nil,
    activeAt         = nil,
    lastActionTime   = 0,
    cooldownMs       = DEFAULT_COOLDOWN_MS,
    ackTimeoutMs     = DEFAULT_ACK_TIMEOUT,
    backoffUntil     = 0,
    backoffMultiplier= 1,
    exhaustionCount  = 0,
    exhaustionLog    = {},
    latencyEwma      = 0,
    enabled          = true,
  }, { __index = Scheduler })
end

-- Enqueue an action.  action = { type, identity, generation, priority, callback, correlationId }
-- Returns false when queue is full.
function Scheduler:enqueue(action)
  action.generation = action.generation or self.generation
  action.priority   = action.priority or Scheduler.Priority.NORMAL_DISCOVERY
  return self.queue:enqueue(action)
end

-- Returns true when a new action can be dispatched.
function Scheduler:canRun()
  if not self.enabled then return false end
  if self.activeAction then
    -- Check ack timeout.
    if self.activeAt and (os.clock() * 1000 - self.activeAt) >= self.ackTimeoutMs then
      self:_handleAckTimeout()
    end
    return false
  end
  local now = os.clock() * 1000
  if now < self.backoffUntil then return false end
  if (now - self.lastActionTime) < self.cooldownMs then return false end
  return true
end

-- Dequeue and activate the next eligible action, or return nil.
function Scheduler:processNext()
  if not self:canRun() then return nil end

  local action = self.queue:dequeue()
  if not action then return nil end

  -- Reject stale generation.
  if action.generation ~= self.generation then
    return self:processNext()  -- Try next; bounded by queue size.
  end

  self.activeAction   = action
  self.activeAt       = os.clock() * 1000
  self.lastActionTime = self.activeAt
  return action
end

-- Call when an acknowledgement arrives for the active action.
-- latencyMs : measured ack latency in milliseconds (optional)
function Scheduler:acknowledge(correlationId, latencyMs)
  if not self.activeAction then return false end
  if correlationId and self.activeAction.correlationId ~= correlationId then
    return false
  end

  if latencyMs and latencyMs > 0 then
    -- EWMA with α=0.25.
    if self.latencyEwma == 0 then
      self.latencyEwma = latencyMs
    else
      self.latencyEwma = self.latencyEwma * 0.75 + latencyMs * 0.25
    end
    -- Adapt cooldown: add 50% of observed latency, bounded.
    local adaptive = math.min(math.max(latencyMs * 0.5, DEFAULT_COOLDOWN_MS), 2000)
    self.cooldownMs = self.cooldownMs * 0.9 + adaptive * 0.1
  end

  self.activeAction   = nil
  self.activeAt       = nil
  self.backoffMultiplier = 1  -- Reset backoff on success.
  return true
end

-- Notify the scheduler of a server exhaustion event.
-- reason : Scheduler.Reason constant
function Scheduler:onExhaustion(reason)
  self.exhaustionCount = self.exhaustionCount + 1
  local entry = { time = os.time(), reason = reason or Scheduler.Reason.UNKNOWN }
  table.insert(self.exhaustionLog, entry)
  if #self.exhaustionLog > MAX_EXHAUSTION_LOG then
    table.remove(self.exhaustionLog, 1)
  end

  -- Exponential backoff with bounded jitter.
  local base = BASE_BACKOFF_MS * self.backoffMultiplier
  local jitter = math.random(0, math.floor(base * 0.2))
  local delay = math.min(base + jitter, MAX_BACKOFF_MS)
  self.backoffUntil = os.clock() * 1000 + delay
  self.backoffMultiplier = math.min(self.backoffMultiplier * 2, 16)

  -- Clear the in-flight action so it can be re-queued by the caller.
  self.activeAction = nil
  self.activeAt     = nil
end

-- Update the generation.  Clears the active action and purges stale queued items.
function Scheduler:setGeneration(gen)
  if gen == self.generation then return end
  self.generation       = gen
  self.activeAction     = nil
  self.activeAt         = nil
  self.backoffUntil     = 0
  self.backoffMultiplier= 1
  self.queue:clear()
end

-- Diagnostics snapshot.
function Scheduler:getStatus()
  local now = os.clock() * 1000
  return {
    generation       = self.generation,
    activeAction     = self.activeAction,
    queueSize        = self.queue.size,
    cooldownMs       = self.cooldownMs,
    backoffRemaining = math.max(0, self.backoffUntil - now),
    latencyEwmaMs    = self.latencyEwma,
    exhaustionCount  = self.exhaustionCount,
    lastExhaustion   = self.exhaustionLog[#self.exhaustionLog],
  }
end

function Scheduler:clear()
  self.queue:clear()
  self.activeAction = nil
  self.activeAt     = nil
end

-- Backward-compatible alias.
function Scheduler:getQueueSize()
  return self.queue.size
end

-- Internal: handle ack timeout on the active action.
function Scheduler:_handleAckTimeout()
  local action = self.activeAction
  self.activeAction = nil
  self.activeAt     = nil
  -- Re-enqueue if retryable and generation is current.
  if action and action.generation == self.generation then
    action.attempt = (action.attempt or 0) + 1
    if action.attempt <= (action.maxAttempts or 3) then
      self.queue:enqueue(action)
    end
  end
  self:onExhaustion(Scheduler.Reason.ACK_TIMEOUT)
end

return Scheduler
