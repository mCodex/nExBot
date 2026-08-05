--[[
  navigation/session.lua — NavigationSession aggregate root.

  Owns ALL navigation invariants:
    1. No movement command unless its exact next step is valid.
    2. The path cursor advances only from observed player movement.
    3. A route edge advances only after its explicit postcondition is observed.
    4. A floor-transition edge completes only after expected Z delta + landing
       region are confirmed.
    5. Post-combat recovery never repeats the same unreachable waypoint
       without new evidence.
    6. ML may rank validated choices but never make an invalid one valid.

  Depends only on navigation.* modules + ports. No OTClient globals.
]]

local domain = require("navigation.domain")
local D = domain
local StepValidator = require("navigation.step_validator")
local PathPlanner = require("navigation.path_planner")
local StepExecutor = require("navigation.step_executor")
local RetryPolicy = require("navigation.retry")
local Obs = require("navigation.observability")

local Session = {}

local WALK_PRECISION = 1

function Session.new(ports, deps)
  local self = setmetatable({}, { __index = Session })
  self.ports = ports
  self.deps = deps or {}

  self.sessionId = 1
  self.routeId = nil
  self.routeVersion = 0
  self.route = nil            -- { nodes = {}, edges = {} }
  self.edgeIndex = 0
  self.activeEdge = nil       -- current edge record
  self.edgePath = nil         -- { directions, positions, mapGeneration, plannedFrom }
  self.cursor = 0             -- acked steps consumed on edgePath
  self.retry = nil            -- RetryPolicy context
  self.state = D.SESSION_STATE.IDLE
  self.lastReason = nil
  self.lastConfirmedAnchor = nil
  self.evidenceRevision = 0
  self.mapGeneration = nil
  self.observedFloor = nil
  self.combatActive = false
  self._lastTick = 0

  -- Infrastructure wiring.
  StepExecutor.releaseOwnership = function(owner)
    if ports.movement and ports.movement.releaseOwnership then
      ports.movement.releaseOwnership(owner)
    end
  end

  self.movement = ports.movement
  if self.movement and self.movement.onPositionChange then
    self._unsubPos = self.movement.onPositionChange(function(newPos, oldPos)
      self:onPositionChange(newPos, oldPos)
    end)
  end
  if self.movement and self.movement.onWalkError then
    self._unsubErr = self.movement.onWalkError(function(reason)
      self._walkError = reason
    end)
  end
  return self
end

-- ── Route loading ──────────────────────────────────────────────────────────

--- Set the current route (ordered node/edge graph). Rebuilds cursors.
function Session:setRoute(route)
  self.route = route
  self.routeId = route and route.id or nil
  self.routeVersion = (self.routeVersion or 0) + 1
  self.edgeIndex = 0
  self.activeEdge = nil
  self.edgePath = nil
  self.cursor = 0
  self.state = D.SESSION_STATE.IDLE
  self.retry = nil
  self:invalidate()
end

--- Select the edge whose destination node is `nodeId`. Idempotent:
-- returns "NO_CHANGE" when the edge is already active.
function Session:focusNode(nodeId)
  if not self.route then return "NO_ROUTE" end
  if self.activeEdge and self.activeEdge.toNode == nodeId and self.state ~= D.SESSION_STATE.FAILED_SAFE then
    return D.REASON.RECOVERY_NO_CHANGE
  end
  for i, edge in ipairs(self.route.edges) do
    if edge.toNode == nodeId then
      self:selectEdge(i)
      return "FOCUSED"
    end
  end
  return "NODE_NOT_FOUND"
end

function Session:selectEdge(edgeIndex)
  if not self.route or not self.route.edges[edgeIndex] then return false end
  self:endEdge(false)
  self.edgeIndex = edgeIndex
  self.activeEdge = self.route.edges[edgeIndex]
  self.edgePath = nil
  self.cursor = 0
  self.retry = RetryPolicy.new(self.routeId, self.activeEdge.id)
  self.state = D.SESSION_STATE.EDGE_ACTIVE
  self:emit("RouteEdgeSelected", { edgeId = self.activeEdge.id, edgeKind = self.activeEdge.kind })
  self:invalidated("ACTIVE_EDGE_CHANGED")
  return true
end

-- ── Evidence / invalidation ────────────────────────────────────────────────

function Session:invalidated(why)
  self.evidenceRevision = self.evidenceRevision + 1
  self.lastEvidenceWhy = why
end

Session.invalidate = function()
  PathPlanner.invalidate()
end

-- ── Position change (the ONLY cursor driver) ───────────────────────────────

function Session:onPositionChange(newPos, oldPos)
  if not newPos or not oldPos then return end
  if D.posEquals(newPos, oldPos) then return end
  self:invalidated("PLAYER_MOVED")

  -- Z change: hand over to the transition coordinator / unexpected-Z logic.
  if newPos.z ~= oldPos.z then
    self:handleZChange(newPos, oldPos)
    return
  end

  -- Advance the cursor ONLY through the active command's expected prefix.
  local nowMs = (self.ports.time and self.ports.time.nowMs and self.ports.time.nowMs()) or 0
  local ack = StepExecutor.onPositionChange(newPos, oldPos, nowMs)
  if not ack then return end

  if ack.noCommand then
    -- Player moved without an active CaveBot command: unrelated movement.
    -- Cursor untouched. Anchor stays.
    return
  end

  if ack.diverged then
    Obs.bump("pathDivergenceRate", 1)
    Obs.record({
      tickId = self._tickId, timestamp = nowMs, playerPosition = newPos,
      acknowledgedCursor = self.cursor, reasonCodes = { D.REASON.PATH_DIVERGED },
    })
    self:_onFailure(ack.reason or D.FAILURE.PATH_DIVERGENCE, newPos)
    return
  end

  if ack.zChange then
    -- Expected floor change completed; transitions module continues.
    return
  end

  if ack.progressed then
    -- ONLY observed movement advances the cursor.
    self:advanceCursor(ack.ackedSteps or 0)
    if ack.partial then
      Obs.bump("partialAutoWalkRate", 1)
      Obs.record({
        tickId = self._tickId, timestamp = nowMs, playerPosition = newPos,
        acknowledgedCursor = self.cursor, reasonCodes = { D.REASON.PARTIAL_AUTOWALK },
      })
      -- Remaining path is replanned from the observed position next tick.
      self.edgePath = nil
    end
  end
end

function Session:advanceCursor(steps)
  if not steps or steps <= 0 then return end
  local before = self.cursor
  if self.edgePath then
    self.cursor = math.min(self.cursor + steps, #self.edgePath.directions)
  else
    -- The path was dropped on a partial ack; keep counting observed steps
    -- (the next replan resets the cursor from the observed position).
    self.cursor = self.cursor + steps
  end
  local nowMs = (self.ports.time and self.ports.time.nowMs and self.ports.time.nowMs()) or 0
  Obs.record({
    tickId = self._tickId, timestamp = nowMs, acknowledgedCursor = self.cursor,
    reasonCodes = { D.REASON.MOVEMENT_ACKNOWLEDGED },
  })
  -- Observed progress resets retry state (single retry owner).
  if self.retry then RetryPolicy.onProgress(self.retry) end
  if self.cursor > before then
    self:_updateAnchor()
  end
end

-- ── Z change handling ──────────────────────────────────────────────────────

function Session:handleZChange(newPos, oldPos)
  local nowMs = (self.ports.time and self.ports.time.nowMs and self.ports.time.nowMs()) or 0
  local transitions = self.deps.transitions

  if transitions and transitions.isActive() then
    local result = transitions.onZChange(newPos, oldPos)
    if result and result.class == D.TRANSITION_CLASS.EXPECTED_TRANSITION_COMPLETED then
      Obs.bump("transitionWrongExitRate", 0)
      Obs.record({
        tickId = self._tickId, timestamp = nowMs, playerPosition = newPos,
        transition = result, reasonCodes = { D.REASON.EXPECTED_TRANSITION_COMPLETED },
      })
      self:commitTransition(result)
      return
    end
    if result and result.class == D.TRANSITION_CLASS.EXPECTED_TRANSITION_WRONG_EXIT then
      Obs.record({
        tickId = self._tickId, timestamp = nowMs, playerPosition = newPos,
        transition = result, reasonCodes = { D.REASON.WRONG_TRANSITION_EXIT },
      })
      self:_onFailure(D.FAILURE.WRONG_TRANSITION_EXIT, newPos)
      return
    end
    return
  end

  -- Unexpected Z change: freeze ordinary advancement, classify, recover
  -- through route-compatible anchors only.
  local classification = (transitions and transitions.classify(newPos, oldPos, self.activeEdge))
    or D.TRANSITION_CLASS.UNKNOWN_Z_CHANGE
  Obs.record({
    tickId = self._tickId, timestamp = nowMs, playerPosition = newPos,
    reasonCodes = { D.REASON.UNEXPECTED_Z_CHANGE },
    classification = classification,
  })
  self:endEdge(true)
  self.state = D.SESSION_STATE.RECOVERING
  if self.deps.recovery then
    self.deps.recovery:onUnexpectedZChange(newPos, classification)
  end
end

function Session:commitTransition()
  -- Edge completed ONLY after Z delta + exit region verified (invariant 4).
  self:endEdge(true)
  self:_selectSuccessor()
  self:invalidated("TRANSITION_COMPLETED")
end

function Session:_selectSuccessor()
  if not self.route then return end
  local next = self.edgeIndex + 1
  if next > #self.route.edges then
    self.state = D.SESSION_STATE.IDLE
    self.activeEdge = nil
    self:emit("RouteCompleted", { routeId = self.routeId })
    return
  end
  self:selectEdge(next)
end

-- ── Tick ───────────────────────────────────────────────────────────────────

--- Execute one navigation tick.
-- @param ctx { playerPos, isWalking=bool (informational), combatActive=bool,
--              preempted=bool, mapGeneration=number }
-- @return NavigationResult
function Session:tick(ctx)
  self._tickId = (self._tickId or 0) + 1
  ctx = ctx or {}
  local playerPos = ctx.playerPos
  self.observedFloor = playerPos and playerPos.z or self.observedFloor

  local mapGen = ctx.mapGeneration
  if mapGen and mapGen ~= self.mapGeneration then
    self.mapGeneration = mapGen
    if self.edgePath then
      self:invalidated("MAP_GENERATION_CHANGED")
      -- Replan the remaining path from the acked cursor.
      self.edgePath = nil
    end
  end

  -- Combat lifecycle -> recovery episodes.
  if self.deps.recovery then
    self.deps.recovery:onCombatState(self.combatActive, ctx.combatActive or false)
  end

  -- Preemption: another movement owner (TargetBot / manual) is active.
  if ctx.preempted then
    StepExecutor.cancel("PREEMPTED")
    self.state = D.SESSION_STATE.WAITING_BLOCKER
    return D.result(D.NavStatus.WAITING_BLOCKER, D.FAILURE.MANUAL_PREEMPTED, {
      observedProgress = false, evidenceRevision = self.evidenceRevision,
    })
  end

  -- Walk error observed by the client adapter (server rejected a step).
  if self._walkError then
    self._walkError = nil
    StepExecutor.cancel("REJECTED")
    self:_onFailure(D.FAILURE.SERVER_STEP_REJECTED, playerPos)
    return self:_lastResult()
  end

  -- Active command: wait for acknowledgement.
  local cmd = StepExecutor.getActive()
  if cmd then
    local nowMs = (self.ports.time and self.ports.time.nowMs and self.ports.time.nowMs()) or 0
    local timeout = StepExecutor.tick(nowMs)
    if timeout then
      self:_onFailure(timeout.reason, playerPos)
      return self:_lastResult()
    end
    return D.result(D.NavStatus.WAITING_ACK, "AWAITING_POSITION_ACK", {
      commandIssued = false, observedProgress = false,
      evidenceRevision = self.evidenceRevision,
      commandId = cmd.id,
    })
  end

  -- Recovery active (post-combat or failure escalation).
  if self.state == D.SESSION_STATE.RECOVERING or self.state == D.SESSION_STATE.FAILED_SAFE then
    local res = self:_recoveryTick(ctx)
    return res
  end

  -- Transition pending (approaching / waiting Z / verifying exit).
  if self.deps.transitions and self.deps.transitions.isActive() then
    local res = self.deps.transitions.tick(self.ports, ctx)
    if res then return res end
  end

  -- No active edge: nothing to do.
  if not self.route or not self.activeEdge then
    self.state = D.SESSION_STATE.IDLE
    return D.result(D.NavStatus.PROGRESS, "NO_ACTIVE_EDGE", { observedProgress = false })
  end

  -- Plan / refresh the current edge path from the acknowledged position.
  local pathResult = self:_ensureEdgePath(playerPos)
  if not pathResult then
    -- First-step invalid or no strict path: classify and retry/recover.
    local reason = self:_edgePathFailure()
    self:_onFailure(reason, playerPos)
    return self:_lastResult()
  end

  -- Edge completion gate (invariant 3): cursor consumed the path AND the
  -- player reached the destination node within precision.
  if self.cursor >= #pathResult.directions then
    if self:_atEdgeDestination(playerPos) then
      self:completeEdge()
      return D.result(D.NavStatus.PROGRESS, "EDGE_COMPLETED", {
        observedProgress = true, evidenceRevision = self.evidenceRevision,
      })
    end
    -- Path ended but not at destination: plan the last approach step.
  end

  -- Dispatch the next validated step / bounded chunk.
  local dispatchResult = self:_dispatchNext(playerPos)
  if dispatchResult then return dispatchResult end

  return D.result(D.NavStatus.WAITING_BLOCKER, "MOVEMENT_UNAVAILABLE", {
    observedProgress = false, evidenceRevision = self.evidenceRevision,
  })
end

-- ── Edge path planning ─────────────────────────────────────────────────────

function Session:_ensureEdgePath(playerPos)
  local edge = self.activeEdge
  if not edge then return nil end

  if edge.kind == D.EDGE_KIND.WALK or edge.kind == D.EDGE_KIND.FIELD_CROSSING then
    if self.edgePath and self.edgePath.mapGeneration == self.mapGeneration then
      return self.edgePath
    end
    local goal = edge.toPos
    local res = PathPlanner.find(self.ports, playerPos, goal, {
      maxSteps = 120,
      ignoreCreatures = false,
      allowFields = (edge.kind == D.EDGE_KIND.FIELD_CROSSING),
      allowFloorChange = false,
      useCache = true,
    })
    if not res or res.status ~= "FOUND" then
      self._lastPathFailure = res
      return nil
    end
    self.edgePath = {
      directions = res.directions,
      positions = res.positions,
      mapGeneration = self.mapGeneration,
      plannedFrom = D.copyPos(playerPos),
    }
    self.cursor = 0
    self._lastPathFailure = nil
    return self.edgePath
  end

  if D.TRANSITION_EDGES[edge.kind] then
    -- Approach the entry tile on the player's floor; the transition
    -- coordinator takes over from there.
    if self.edgePath and self.edgePath.mapGeneration == self.mapGeneration then
      return self.edgePath
    end
    local entry = edge.entryPos or edge.toPos
    local approachGoal = { x = entry.x, y = entry.y, z = playerPos.z }
    local res = PathPlanner.find(self.ports, playerPos, approachGoal, {
      maxSteps = 120, ignoreCreatures = false, allowFields = false,
      allowFloorChange = false, useCache = true,
    })
    if not res or res.status ~= "FOUND" then
      self._lastPathFailure = res
      return nil
    end
    self.edgePath = {
      directions = res.directions,
      positions = res.positions,
      mapGeneration = self.mapGeneration,
      plannedFrom = D.copyPos(playerPos),
    }
    self.cursor = 0
    self._lastPathFailure = nil
    return self.edgePath
  end

  -- Action edges (door / machete / scythe / rope / shovel): approach first.
  if self.edgePath and self.edgePath.mapGeneration == self.mapGeneration then
    return self.edgePath
  end
  local target = edge.actionPos or edge.toPos
  local res = PathPlanner.find(self.ports, playerPos, target, {
    maxSteps = 120, ignoreCreatures = false, allowFields = false,
    allowFloorChange = false, useCache = true,
  })
  if not res or res.status ~= "FOUND" then
    self._lastPathFailure = res
    return nil
  end
  self.edgePath = {
    directions = res.directions,
    positions = res.positions,
    mapGeneration = self.mapGeneration,
    plannedFrom = D.copyPos(playerPos),
  }
  self.cursor = 0
  self._lastPathFailure = nil
  return self.edgePath
end

function Session:_edgePathFailure()
  local res = self._lastPathFailure
  if res and res.failure then return res.failure end
  -- No path result at all: check the destination tile.
  local goal = self.activeEdge and (self.activeEdge.toPos or self.activeEdge.entryPos)
  if goal then
    local tile = self.ports.world and self.ports.world.getTile and self.ports.world.getTile(goal)
    if tile and tile.creature and not tile.walkable then
      return D.FAILURE.TEMPORARY_CREATURE_BLOCK
    end
  end
  return D.FAILURE.NO_PATH_CURRENT_MAP
end

-- ── Dispatch ───────────────────────────────────────────────────────────────

function Session:_dispatchNext(playerPos)
  if not playerPos or not self.edgePath then return nil end
  local path = self.edgePath.directions
  local nextIdx = self.cursor + 1
  if nextIdx > #path then return nil end

  local edge = self.activeEdge

  -- Invariant 1: exact next step must be valid before ANY command.
  local policy = {
    world = self.ports.world,
    ignoreCreatures = false,
    allowFields = (edge.kind == D.EDGE_KIND.FIELD_CROSSING),
    allowFloorChange = (D.TRANSITION_EDGES[edge.kind] and nextIdx == #path),
    strictCorners = true,
  }
  local ok, _, reason = StepValidator.validate(playerPos, path[nextIdx], policy)
  if not ok then
    Obs.record({
      tickId = self._tickId, playerPosition = playerPos, reasonCodes = { D.REASON.STEP_REJECTED_BLOCKED },
      detail = reason,
    })
    -- The step was NOT dispatched: invalidStepCommandCount stays 0 by
    -- construction (invariant: never dispatch an invalid step).
    return nil
  end

  -- Validate the full chunk when auto-walking (bounded).
  local clearance = PathPlanner.clearanceAt(self.ports, playerPos, 4)
  local nearTransition = (D.TRANSITION_EDGES[edge.kind])
  local nearCorner = false
  for i = nextIdx + 1, math.min(nextIdx + 4, #path) do
    if path[i] and path[nextIdx] and path[i] ~= path[nextIdx] then nearCorner = true break end
  end
  local chunk = StepExecutor.computeChunk(clearance, nearCorner, nearTransition, false)

  local chunkDirs = {}
  local p = D.copyPos(playerPos)
  for i = nextIdx, math.min(nextIdx + chunk - 1, #path) do
    local dir = path[i]
    local okS, dest = StepValidator.validate(p, dir, policy)
    if not okS then
      chunk = i - nextIdx
      if chunk <= 0 then chunk = 1 end
      break
    end
    chunkDirs[#chunkDirs + 1] = dir
    p = dest
  end
  if #chunkDirs == 0 then return nil end

  local nowMs = (self.ports.time and self.ports.time.nowMs and self.ports.time.nowMs()) or 0
  local cmd = StepExecutor.dispatch({
    ports = self.ports,
    routeId = self.routeId,
    edgeId = edge.id,
    attemptId = self.retry and self.retry.attemptId or 1,
    generation = self.evidenceRevision,
    startPosition = playerPos,
    path = chunkDirs,
    chunkSize = chunk,
    expectsFloorChange = (D.TRANSITION_EDGES[edge.kind] and nextIdx + #chunkDirs - 1 >= #path),
    floorDelta = edge.expectedFloorDelta or 0,
    mapGeneration = self.mapGeneration,
  })

  if not cmd then
    return nil  -- ownership unavailable -> caller waits
  end

  Obs.bump("movementCommandsPerAcknowledgedStep", 1)
  Obs.record({
    tickId = self._tickId, timestamp = nowMs, routeId = self.routeId,
    activeEdgeId = edge.id, playerPosition = playerPos,
    movementCommandId = cmd.id, movementOwner = "CAVEBOT",
    mapGeneration = self.mapGeneration, retryPhase = self.retry and self.retry.lastPhase,
    reasonCodes = { D.REASON.MOVEMENT_DISPATCHED },
  })

  -- For a transition edge, once the final step lands on the entry tile, the
  -- TransitionCoordinator takes ownership.
  if D.TRANSITION_EDGES[edge.kind] and cmd.dispatchType == "KEYBOARD" then
    if self.deps.transitions then
      self.deps.transitions.begin(edge, playerPos)
    end
  end

  return D.result(D.NavStatus.PROGRESS, "STEP_DISPATCHED", {
    commandIssued = true, observedProgress = false,
    evidenceRevision = self.evidenceRevision, commandId = cmd.id,
  })
end

-- ── Edge completion ────────────────────────────────────────────────────────

function Session:_atEdgeDestination(playerPos)
  local edge = self.activeEdge
  if not edge or not playerPos then return false end
  local dest = edge.toPos
  if not dest then return false end
  if playerPos.z ~= dest.z then return false end
  local precision = edge.precision or WALK_PRECISION
  return math.abs(playerPos.x - dest.x) <= precision
     and math.abs(playerPos.y - dest.y) <= precision
end

function Session:completeEdge()
  local edge = self.activeEdge
  if not edge then return end
  local nowMs = (self.ports.time and self.ports.time.nowMs and self.ports.time.nowMs()) or 0
  Obs.bump("edgeCompletionRate", 1)
  Obs.record({
    tickId = self._tickId, timestamp = nowMs, activeEdgeId = edge.id,
    reasonCodes = { "EDGE_COMPLETED" },
  })
  self:_updateAnchor()
  self:emit("RouteEdgeCompleted", { edgeId = edge.id, edgeKind = edge.kind })
  if D.TRANSITION_EDGES[edge.kind] then
    -- Transition edges complete through commitTransition; guard anyway.
    return
  end
  self:endEdge(true)
  self:_selectSuccessor()
end

function Session:endEdge(_keepAnchor)
  -- lastConfirmedAnchor is retained on reselection (endEdge(false)) and
  -- updated from observed progress (endEdge(true)).
  self.edgePath = nil
  self.cursor = 0
  self.retry = nil
  self.activeEdge = nil
end

-- ── Failure handling (single retry owner) ─────────────────────────────────

function Session:_onFailure(failure, playerPos)
  local nowMs = (self.ports.time and self.ports.time.nowMs and self.ports.time.nowMs()) or 0
  self.lastReason = failure
  self.lastFailureAt = nowMs
  self.lastFailurePos = playerPos and D.copyPos(playerPos) or nil
  Obs.bump("stuckEvents", 1)

  if failure == D.FAILURE.STATIC_TOPOLOGY_BLOCK or failure == D.FAILURE.NO_PATH_CURRENT_MAP then
    Obs.bump("wallDirectedCommandCount", 0)  -- never dispatch toward walls
  end

  -- Obstacle diagnosis may resolve the failure inline (doors, tools, fields).
  if self.deps.obstacles then
    local handled = self.deps.obstacles.handleFailure(self, failure, playerPos)
    if handled then return end
  end

  -- Critical edges are never skipped or blacklisted.
  if self.activeEdge and D.CRITICAL_EDGES[self.activeEdge.kind] then
    Obs.record({
      tickId = self._tickId, timestamp = nowMs, playerPosition = playerPos,
      activeEdgeId = self.activeEdge.id, reasonCodes = { D.REASON.CRITICAL_EDGE_NOT_SKIPPED },
    })
  end

  if not self.retry then
    self.retry = RetryPolicy.new(self.routeId, self.activeEdge and self.activeEdge.id)
  end
  local decision = RetryPolicy.recordFailure(self.retry, failure, nowMs, {
    hasProgress = (self.cursor or 0) > 0,
    newEvidence = (self.evidenceRevision or 0) > 0,
  })

  self._retryDecision = decision

  if decision.action == "FAILED_SAFE" then
    self.state = D.SESSION_STATE.FAILED_SAFE
    Obs.record({
      tickId = self._tickId, timestamp = nowMs, playerPosition = playerPos,
      reasonCodes = { D.REASON.NAVIGATION_FAILED_SAFE }, detail = failure,
    })
    self:emit("NavigationFailedSafe", { reason = failure })
    return
  end

  if decision.action == "RECOVER" or decision.phase == D.RETRY_PHASE.ROUTE_EDGE_RECOVERY
     or decision.phase == D.RETRY_PHASE.BACKTRACK_CONFIRMED_ANCHOR then
    self.state = D.SESSION_STATE.RECOVERING
    return
  end

  -- WAIT / RETRY / ESCALATE: keep the edge, refresh the path.
  self.state = D.SESSION_STATE.EDGE_ACTIVE
  self.edgePath = nil
  self.cursor = 0
end

function Session:_lastResult()
  local d = self._retryDecision
  local status
  if self.state == D.SESSION_STATE.FAILED_SAFE then
    status = D.NavStatus.FAILED_TERMINAL
  elseif self.state == D.SESSION_STATE.RECOVERING then
    status = D.NavStatus.REPLAN
  elseif d and (d.phase == D.RETRY_PHASE.WAIT_TEMPORARY_BLOCKER) then
    status = D.NavStatus.WAITING_BLOCKER
  else
    status = D.NavStatus.FAILED_RETRYABLE
  end
  return D.result(status, self.lastReason or "UNKNOWN", {
    retryAfterMs = d and d.retryAfterMs,
    evidenceRevision = self.evidenceRevision,
    retryPhase = d and d.phase,
    attemptId = d and d.attemptId,
  })
end

-- ── Recovery ───────────────────────────────────────────────────────────────

function Session:_recoveryTick(ctx)
  if not self.deps.recovery then
    self.state = D.SESSION_STATE.FAILED_SAFE
    return D.result(D.NavStatus.FAILED_TERMINAL, D.FAILURE.RECOVERY_TARGET_UNREACHABLE)
  end
  local res = self.deps.recovery:tick(self, ctx)
  if res then
    -- Recovery selected a route anchor: leave RECOVERING and resume the
    -- strict, ack-driven edge flow (recovery itself never dispatches GoTo).
    if res.recovered then self.state = D.SESSION_STATE.EDGE_ACTIVE end
    return res
  end
  return D.result(D.NavStatus.WAITING_BLOCKER, "RECOVERY_DEFERRED")
end

-- ── Anchor bookkeeping ─────────────────────────────────────────────────────

function Session:_updateAnchor()
  if not self.activeEdge or not self.edgePath then return end
  -- positions[1] is the start; position after `cursor` acked steps is
  -- positions[cursor+1].
  self.lastConfirmedAnchor = {
    pos = self.edgePath.positions and self.edgePath.positions[self.cursor + 1]
      or (self.edgePath.plannedFrom and D.copyPos(self.edgePath.plannedFrom)),
    edgeId = self.activeEdge.id,
    pathIndex = self.cursor,
    evidenceRevision = self.evidenceRevision,
    mapGeneration = self.mapGeneration,
    ts = (self.ports.time and self.ports.time.nowMs and self.ports.time.nowMs()) or 0,
  }
end

function Session:getAnchor()
  return self.lastConfirmedAnchor
end

-- ── Events / snapshot ──────────────────────────────────────────────────────

function Session:emit(event, payload)
  if self.ports.bus and self.ports.bus.emit then
    pcall(self.ports.bus.emit, event, payload)
  end
end

function Session:snapshot()
  local edge = self.activeEdge
  return {
    sessionId = self.sessionId,
    routeId = self.routeId,
    routeVersion = self.routeVersion,
    state = self.state,
    activeEdgeId = edge and edge.id,
    activeEdgeKind = edge and edge.kind,
    activeNode = edge and edge.toNode,
    cursor = self.cursor,
    edgePathLength = self.edgePath and #self.edgePath.directions or 0,
    lastConfirmedAnchor = self.lastConfirmedAnchor,
    evidenceRevision = self.evidenceRevision,
    mapGeneration = self.mapGeneration,
    retryPhase = self.retry and self.retry.lastPhase,
    failureReason = self.lastReason,
    retryDecision = self._retryDecision,
    recovery = self.deps.recovery and self.deps.recovery:snapshot(),
    transition = self.deps.transitions and self.deps.transitions:snapshot(),
    ml = self.deps.ml and self.deps.ml:snapshot(),
  }
end

Session.routeGraphDirty = function()
  return false
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.session"] = Session end
return Session