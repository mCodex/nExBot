local StateMachine = {}

local STATES = {
  idle = { "waitingForSession" },
  waitingForSession = { "discoveringRoots" },
  discoveringRoots = { "reconciling" },
  reconciling = { "traversing" },
  traversing = { "waitingForAcknowledgement", "waitingForPage", "completed", "pausedForCriticalAction" },
  waitingForAcknowledgement = { "traversing", "waitingForPage", "failed" },
  waitingForPage = { "traversing", "failed" },
  pausedForCriticalAction = { "traversing" },
  completed = { "degraded" },
  degraded = { "traversing", "cancelled" },
  recovering = { "idle" },
  cancelled = { "idle" },
  failed = { "recovering" },
}

local ANY_STATE_TRANSITIONS = { cancelled = true, failed = true }

function StateMachine.new()
  return setmetatable({
    state = "idle",
    generation = 0,
    _transitions = STATES,
  }, { __index = StateMachine })
end

function StateMachine:canTransition(to)
  if ANY_STATE_TRANSITIONS[to] then return true end
  local allowed = self._transitions[self.state]
  if not allowed then return false end
  for _, s in ipairs(allowed) do
    if s == to then return true end
  end
  return false
end

function StateMachine:transition(to)
  if not self:canTransition(to) then return false end
  self.state = to
  if to == "cancelled" then
    self.generation = self.generation + 1
  end
  return true
end

function StateMachine:is(st)
  return self.state == st
end

return StateMachine
