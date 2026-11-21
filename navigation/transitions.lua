--[[
  navigation/transitions.lua — floor-transition coordinator (P0.6 / P0.8).

  Owns the WHOLE lifecycle of a transition edge after the final approach step:
    * begin(edge, playerPos)  -> APPROACHING / WAITING_Z (invariant 4).
    * tick(ports, ctx)        -> dispatches the actual Z step on the entry tile,
                                  or returns nil while waiting on ack.
    * onZChange(newPos, oldPos) -> EXPECTED_TRANSITION_COMPLETED (Z delta +
                                  landing tile verified) or WRONG_EXIT.
    * classify(...)           -> TRANSITION_CLASS for unexpected Z changes.
    * isActive()              -> a transition is mid-flight.
    * snapshot()

  Port contract: unknown capability = fail-safe. No raw GoTo bursts: the Z step
  is dispatched through the movement port as a single validated step, and
  completion is only acknowledged after Z delta + exit tile verification.
]]

local domain = require("navigation.domain")
local D = domain
local StepValidator = require("navigation.step_validator")
local StepExecutor = require("navigation.step_executor")
local Obs = require("navigation.observability")

local TransitionCoordinator = {}

local function new()
  local self = setmetatable({}, { __index = TransitionCoordinator })
  self.phase = "IDLE"
  self.edge = nil
  self.entryPos = nil
  self.expectedFloorDelta = 0
  self.startedAtMs = 0
  self.cmd = nil
  self.landing = nil

  -- Instance-bound closures: Session calls these with DOT syntax, so they
  -- must not require an implicit self argument.
  self.isActive = function()
    return self.phase ~= "IDLE"
  end
  self.begin = function(edge, playerPos)
    return TransitionCoordinator.begin(self, edge, playerPos)
  end
  self.tick = function(ports, ctx)
    return TransitionCoordinator.tick(self, ports, ctx)
  end
  self.onZChange = function(newPos, oldPos)
    return TransitionCoordinator.onZChange(self, newPos, oldPos)
  end
  self.classify = function(newPos, oldPos, activeEdge)
    return TransitionCoordinator.classify(self, newPos, oldPos, activeEdge)
  end
  self.snapshot = function()
    return TransitionCoordinator.snapshot(self)
  end
  return self
end
TransitionCoordinator.new = new

function TransitionCoordinator:begin(edge, playerPos)
  self.edge = edge
  self.entryPos = edge.entryPos or edge.toPos
  self.expectedFloorDelta = edge.expectedFloorDelta or 0
  self.phase = "WAITING_Z"
  self.landing = nil
  self.startedAtMs = 0
  Obs.record({
    reasonCodes = { D.REASON.TRANSITION_BEGIN },
    detail = { edgeId = edge.id, kind = edge.kind, entry = self.entryPos, playerPos = playerPos },
  })
end

-- The final approach chunk may include the Z step itself; dispatch it through
-- the strict executor (single validated step) when no command is in flight.
function TransitionCoordinator:tick(ports, ctx)
  if self.phase ~= "WAITING_Z" then return nil end
  if self.cmd then
    local timeout = StepExecutor.tick((ctx and ctx.nowMs) or 0)
    if timeout then
      self.phase = "FAILED"
      return D.result(D.NavStatus.FAILED_RETRYABLE, D.FAILURE.TRANSITION_TIMEOUT)
    end
    return D.result(D.NavStatus.WAITING_ACK, "TRANSITION_AWAITING_ACK", { commandIssued = false })
  end

  local playerPos = ctx and ctx.playerPos
  if not playerPos then return nil end

  -- The step direction is normally derived from the edge's own geometry
  -- (entry tile -> landing tile), not supplied by the caller: nothing in
  -- production ever populates ctx.zStepDirection, so relying on it left
  -- this dispatch unreachable whenever begin() fires without a walk
  -- already in flight (e.g. two transition edges chained back to back).
  -- ctx.zStepDirection is kept as an explicit override for tests/fixtures.
  local dir = (ctx and ctx.zStepDirection) or D.directionBetween(self.entryPos, self.edge.toPos)
  if not dir then
    self.phase = "FAILED"
    return D.result(D.NavStatus.FAILED_RETRYABLE, D.FAILURE.ROUTE_CONFIGURATION_ERROR, {
      detail = "cannot derive zStepDirection: entry/exit tile are not adjacent",
    })
  end

  local policy = {
    world = ports.world,
    ignoreCreatures = false, allowFields = false,
    allowFloorChange = true, strictCorners = false,
  }
  local ok, reason = StepValidator.validate(playerPos, dir, policy)
  if not ok then
    Obs.bump("transitionWrongExitRate", 1)
    return D.result(D.NavStatus.FAILED_RETRYABLE, D.FAILURE.TRANSITION_FIRST_STEP_INVALID, {
      detail = reason,
    })
  end

  local nowMs = (ports.time and ports.time.nowMs and ports.time.nowMs()) or 0
  local cmd = StepExecutor.dispatch({
    ports = ports,
    routeId = ctx.routeId, edgeId = self.edge.id, attemptId = 1,
    generation = ctx.generation or 0,
    startPosition = playerPos, path = { dir }, chunkSize = 1,
    expectsFloorChange = true, floorDelta = self.expectedFloorDelta,
    mapGeneration = ctx.mapGeneration,
  })
  if not cmd then return nil end
  self.cmd = cmd
  self.startedAtMs = nowMs
  return D.result(D.NavStatus.PROGRESS, D.REASON.TRANSITION_STEP_DISPATCHED, {
    commandIssued = true, observedProgress = false,
  })
end

-- Completion criterion (invariant 4): Z delta matches AND the landing tile is
-- the expected exit. Anything else is a wrong exit / unknown change.
function TransitionCoordinator:onZChange(newPos, oldPos)
  local delta = newPos.z - oldPos.z
  local class
  if delta == self.expectedFloorDelta and self:landingVerified(newPos) then
    class = D.TRANSITION_CLASS.EXPECTED_TRANSITION_COMPLETED
  else
    class = D.TRANSITION_CLASS.EXPECTED_TRANSITION_WRONG_EXIT
  end
  local result = { class = class, zDelta = delta, newPos = newPos, landing = newPos }
  self.phase = "IDLE"
  self.cmd = nil
  return result
end

function TransitionCoordinator:landingVerified(pos)
  if not self.edge then return false end
  local toPos = self.edge.toPos
  if not toPos then return false end
  -- Invariant 4: the exit REGION (exact tile) must be verified, not just Z.
  return toPos.x == pos.x and toPos.y == pos.y and toPos.z == pos.z
end

function TransitionCoordinator.classify(_self, newPos, oldPos, activeEdge)
  if activeEdge and D.TRANSITION_EDGES[activeEdge.kind] and newPos.z ~= oldPos.z then
    return D.TRANSITION_CLASS.EXPECTED_TRANSITION_TIMEOUT
  end
  return D.TRANSITION_CLASS.UNKNOWN_Z_CHANGE
end

function TransitionCoordinator:snapshot()
  return {
    phase = self.phase,
    edgeId = self.edge and self.edge.id,
    kind = self.edge and self.edge.kind,
    expectedFloorDelta = self.expectedFloorDelta,
    startedAtMs = self.startedAtMs,
  }
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.transitions"] = TransitionCoordinator end
return TransitionCoordinator