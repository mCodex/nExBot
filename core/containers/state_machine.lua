-- state_machine.lua
-- Explicit discovery state machine with generation tracking.
-- Every transition records: source, target, reason, generation, timestamp.
-- Generation increments whenever a session resets (cancel, relog, reconnect).

local StateMachine = {}

-- All valid states.
StateMachine.States = {
  DISABLED                    = "DISABLED",
  IDLE                        = "idle",
  WAITING_FOR_SESSION         = "waitingForSession",
  WAITING_FOR_INVENTORY       = "waitingForInventory",
  DISCOVERING_ROOTS           = "discoveringRoots",
  RECONCILING_OPEN_WINDOWS    = "reconciling",
  PLANNING                    = "planning",
  TRAVERSING                  = "traversing",
  WAITING_FOR_ACTION_BUDGET   = "waitingForActionBudget",
  OPENING_CONTAINER           = "openingContainer",
  WAITING_FOR_ACKNOWLEDGEMENT = "waitingForAcknowledgement",
  SCANNING_PAGE               = "scanningPage",
  WAITING_FOR_PAGE            = "waitingForPage",
  INDEXING_ITEMS              = "indexingItems",
  DISCOVERING_CHILDREN        = "discoveringChildren",
  VERIFYING_CRITICAL_READINESS= "verifyingCriticalReadiness",
  VERIFYING_FULL_READINESS    = "verifyingFullReadiness",
  COMPLETED                   = "completed",
  COMPLETED_DEGRADED          = "completedDegraded",
  RETRY_BACKOFF               = "retryBackoff",
  PAUSED_FOR_CRITICAL_ACTION  = "pausedForCriticalAction",
  CANCELLED                   = "cancelled",
  FAILED                      = "failed",
}

local S = StateMachine.States

-- Allowed transitions: state → list of valid next states.
local TRANSITIONS = {
  [S.IDLE]                        = { S.WAITING_FOR_SESSION, S.DISABLED },
  [S.WAITING_FOR_SESSION]         = { S.WAITING_FOR_INVENTORY, S.DISCOVERING_ROOTS },
  [S.WAITING_FOR_INVENTORY]       = { S.DISCOVERING_ROOTS },
  [S.DISCOVERING_ROOTS]           = { S.RECONCILING_OPEN_WINDOWS, S.PLANNING },
  [S.RECONCILING_OPEN_WINDOWS]    = { S.PLANNING, S.TRAVERSING },
  [S.PLANNING]                    = { S.TRAVERSING, S.WAITING_FOR_ACTION_BUDGET },
  [S.TRAVERSING]                  = {
    S.OPENING_CONTAINER,
    S.WAITING_FOR_ACTION_BUDGET,
    S.VERIFYING_CRITICAL_READINESS,
    S.VERIFYING_FULL_READINESS,
    S.COMPLETED,
    S.COMPLETED_DEGRADED,
    S.PAUSED_FOR_CRITICAL_ACTION,
  },
  [S.WAITING_FOR_ACTION_BUDGET]   = { S.TRAVERSING, S.OPENING_CONTAINER },
  [S.OPENING_CONTAINER]           = { S.WAITING_FOR_ACKNOWLEDGEMENT },
  [S.WAITING_FOR_ACKNOWLEDGEMENT] = {
    S.SCANNING_PAGE,
    S.INDEXING_ITEMS,
    S.TRAVERSING,
    S.RETRY_BACKOFF,
  },
  [S.SCANNING_PAGE]               = { S.WAITING_FOR_PAGE, S.INDEXING_ITEMS },
  [S.WAITING_FOR_PAGE]            = { S.SCANNING_PAGE, S.INDEXING_ITEMS, S.TRAVERSING },
  [S.INDEXING_ITEMS]              = { S.DISCOVERING_CHILDREN, S.TRAVERSING },
  [S.DISCOVERING_CHILDREN]        = { S.TRAVERSING },
  [S.VERIFYING_CRITICAL_READINESS]= { S.TRAVERSING, S.COMPLETED, S.COMPLETED_DEGRADED },
  [S.VERIFYING_FULL_READINESS]    = { S.COMPLETED, S.COMPLETED_DEGRADED },
  [S.COMPLETED]                   = { S.IDLE },
  [S.COMPLETED_DEGRADED]          = { S.IDLE, S.TRAVERSING },
  [S.RETRY_BACKOFF]               = { S.TRAVERSING, S.OPENING_CONTAINER },
  [S.PAUSED_FOR_CRITICAL_ACTION]  = { S.TRAVERSING },
  [S.FAILED]                      = { S.IDLE },
  [S.DISABLED]                    = { S.IDLE },
  -- Legacy state names kept for backward compat.
  ["recovering"]  = { S.IDLE },
  ["degraded"]    = { S.TRAVERSING, S.CANCELLED },
}

-- States reachable from ANY state (bypass normal allowed list).
local ANY_SOURCE = { [S.CANCELLED] = true, [S.FAILED] = true,
  ["recovering"] = true, ["degraded"] = true }

-- States that reset the generation (new session).
local GENERATION_RESET = { [S.CANCELLED] = true }

function StateMachine.new()
  return setmetatable({
    state      = S.IDLE,
    generation = 0,
    history    = {},      -- Bounded transition log (last 50).
    _transitions = TRANSITIONS,
  }, { __index = StateMachine })
end

function StateMachine:canTransition(to)
  if ANY_SOURCE[to] then return true end
  local allowed = self._transitions[self.state]
  if not allowed then return false end
  for _, s in ipairs(allowed) do
    if s == to then return true end
  end
  return false
end

-- Transition to `to`.  Returns true on success.
-- reason : optional string describing why the transition occurred.
function StateMachine:transition(to, reason)
  if not self:canTransition(to) then return false end

  local entry = {
    from       = self.state,
    to         = to,
    reason     = reason,
    generation = self.generation,
    ts         = os.time(),
  }

  self.state = to

  if GENERATION_RESET[to] then
    self.generation = self.generation + 1
    entry.newGeneration = self.generation
  end

  -- Keep bounded history.
  table.insert(self.history, entry)
  if #self.history > 50 then
    table.remove(self.history, 1)
  end

  return true
end

-- Increment generation without changing state (reconnect / bot reload).
function StateMachine:incrementGeneration(reason)
  self.generation = self.generation + 1
  table.insert(self.history, {
    from       = self.state,
    to         = self.state,
    reason     = reason or "generationIncrement",
    generation = self.generation,
    ts         = os.time(),
  })
  if #self.history > 50 then
    table.remove(self.history, 1)
  end
end

function StateMachine:is(st)
  return self.state == st
end

function StateMachine:isTerminal()
  return self.state == S.CANCELLED
    or self.state == S.FAILED
    or self.state == S.COMPLETED
    or self.state == S.COMPLETED_DEGRADED
    or self.state == "completed"   -- legacy alias
    or self.state == "failed"      -- legacy alias
    or self.state == "cancelled"   -- legacy alias
end

function StateMachine:reset(reason)
  self:incrementGeneration(reason or "reset")
  self.state = S.IDLE
end

function StateMachine:getLastTransition()
  return self.history[#self.history]
end

return StateMachine

