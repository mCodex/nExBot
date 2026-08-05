--[[
  navigation/step_executor.lua — acknowledged movement command executor.

  P0.4 / P0.5 / P0.6 live here:
    * cursor/command state advances ONLY from observed player position changes;
    * player:isWalking() is never treated as progress;
    * one movement owner at a time (arbitration via movement port);
    * chunk policy shrinks in corridors / near corners / transitions;
    * partial auto-walk advances exactly the observed prefix.

  Domain object:
    MovementCommand = {
      id, owner="CAVEBOT", routeId, edgeId, attemptId, generation,
      startPosition, expectedPositions, expectedFloor, mapGeneration,
      dispatchedAt, acknowledgedSteps=0, state, dispatchType
    }
]]

local domain = require("navigation.domain")

local StepExecutor = {}

local _cmdId = 0
local function nextId()
  _cmdId = _cmdId + 1
  return _cmdId
end

local STEP_TIMEOUT_MS = 6000      -- absolute deadline for any command

local DEFAULT_CHUNK = 8

-- Chunk size policy (bounded, deterministic).
function StepExecutor.computeChunk(clearance, nearCorner, nearTransition, nearObstacle, partialDefault)
  if clearance ~= nil and clearance <= 1 then return 1 end
  if nearCorner or nearTransition or nearObstacle then return 1 end
  if clearance ~= nil and clearance <= 2 then return 3 end
  if partialDefault == true then return 3 end
  return DEFAULT_CHUNK
end

--- Start (or reuse) a movement command.
-- @param ctx { ports, routeId, edgeId, attemptId, generation,
--              startPosition, path, chunkSize, expectsFloorChange, floorDelta,
--              policy }
-- @return command | nil  (nil when ownership not available)
function StepExecutor.dispatch(ctx)
  local ports = ctx.ports
  if not ports or not ports.movement then return nil end

  local owner = ports.movement.getOwner and ports.movement.getOwner()
  if owner and owner ~= "CAVEBOT" and owner ~= "NONE" then
    return nil  -- another movement owner is active
  end

  local path = ctx.path
  if not path or #path == 0 then return nil end

  local startPos = ctx.startPosition
  local chunkSize = math.max(1, math.min(ctx.chunkSize or DEFAULT_CHUNK, #path))

  local expected = {}
  local p = { x = startPos.x, y = startPos.y, z = startPos.z }
  for i = 1, chunkSize do
    local off = domain.offsetOf(path[i])
    if not off then break end
    p = domain.addOffset(p, off)
    expected[#expected + 1] = { x = p.x, y = p.y, z = p.z }
  end
  if #expected == 0 then return nil end

  local nowMs = (ports.time and ports.time.nowMs and ports.time.nowMs()) or 0

  local cmd = {
    id = nextId(),
    owner = "CAVEBOT",
    routeId = ctx.routeId,
    edgeId = ctx.edgeId,
    attemptId = ctx.attemptId,
    generation = ctx.generation,
    startPosition = { x = startPos.x, y = startPos.y, z = startPos.z },
    expectedPositions = expected,
    expectedFloor = ctx.expectsFloorChange and (startPos.z + (ctx.floorDelta or 0)) or startPos.z,
    mapGeneration = ctx.mapGeneration,
    dispatchedAt = nowMs,
    acknowledgedSteps = 0,
    state = "DISPATCHED",
    dispatchType = (#expected == 1) and "KEYBOARD" or "AUTOWALK",
    deadline = nowMs + STEP_TIMEOUT_MS,
  }

  if cmd.dispatchType == "KEYBOARD" then
    local okD = ports.movement.walk(path[1])
    if okD == false then return nil end
  else
    local dest = expected[#expected]
    local okA = ports.movement.autoWalk(dest, chunkSize)
    if okA == false then return nil end
  end

  -- Capture ownership AFTER a successful dispatch.
  if ports.movement.acquireOwnership then
    ports.movement.acquireOwnership("CAVEBOT", 1)
  end

  StepExecutor.active = cmd
  return cmd
end

--- Feed an observed position change into the active command.
-- ackedSteps is the DELTA of newly acknowledged steps (the session cursor
-- advances by exactly this); ackedTotal is the cumulative count.
-- Returns a table or nil:
--   { ackedSteps=n, ackedTotal=n, progressed=true, completed=false, partial=false }
--   { zChange=true, newZ=z }        -- expected floor change observed
--   { diverged=true, reason="..." }  -- movement not on the expected path
--   { noCommand=true }               -- no active command (nothing to ack)
function StepExecutor.onPositionChange(newPos, oldPos, _nowMs)
  if not StepExecutor.active then return { noCommand = true } end
  local cmd = StepExecutor.active
  if cmd.state ~= "DISPATCHED" and cmd.state ~= "ACKNOWLEDGING" then return nil end

  if not newPos then return nil end

  -- Z handoff: if the command expected a floor change and the player changed Z,
  -- ownership transfers to the TransitionCoordinator.
  if newPos.z ~= cmd.startPosition.z then
    if newPos.z == cmd.expectedFloor then
      cmd.state = "COMPLETED"
      StepExecutor.active = nil
      if StepExecutor.releaseOwnership then StepExecutor.releaseOwnership("CAVEBOT") end
      return { zChange = true, commandId = cmd.id }
    end
    cmd.state = "DIVERGED"
    StepExecutor.active = nil
    if StepExecutor.releaseOwnership then StepExecutor.releaseOwnership("CAVEBOT") end
    return { diverged = true, reason = "WRONG_FLOOR" }
  end

  if domain.posEquals(newPos, oldPos) then return nil end

  -- Sequential prefix match (allows the client to skip intermediate tiles on
  -- bursty servers = partial auto-walk).
  local expected = cmd.expectedPositions
  local matchIdx = nil
  for i = cmd.acknowledgedSteps + 1, #expected do
    if domain.posEquals(newPos, expected[i]) then
      matchIdx = i
      break
    end
  end

  if matchIdx == nil then
    -- Also accept a position equal to the command start (rejected step bounced
    -- back): the client may nudge then fail; treat as divergence.
    if domain.posEquals(newPos, cmd.startPosition) and cmd.acknowledgedSteps == 0 then
      cmd.state = "DIVERGED"
      StepExecutor.active = nil
      if StepExecutor.releaseOwnership then StepExecutor.releaseOwnership("CAVEBOT") end
      return { diverged = true, reason = "SERVER_STEP_REJECTED" }
    end
    cmd.state = "DIVERGED"
    StepExecutor.active = nil
    if StepExecutor.releaseOwnership then StepExecutor.releaseOwnership("CAVEBOT") end
    return { diverged = true, reason = "PATH_DIVERGENCE", position = newPos }
  end

  local delta = matchIdx - cmd.acknowledgedSteps
  cmd.acknowledgedSteps = matchIdx

  if matchIdx >= #expected then
    cmd.state = "COMPLETED"
    StepExecutor.active = nil
    if StepExecutor.releaseOwnership then StepExecutor.releaseOwnership("CAVEBOT") end
    return { ackedSteps = delta, ackedTotal = matchIdx, progressed = true, completed = true }
  end

  cmd.state = "ACKNOWLEDGING"
  return {
    ackedSteps = delta,
    ackedTotal = matchIdx,
    progressed = true,
    partial = true,  -- observed prefix shorter than the dispatched chunk
    partialAutoWalk = (cmd.dispatchType == "AUTOWALK"),
  }
end

--- Periodic timeout check. Called every tick while a command is active.
function StepExecutor.tick(nowMs)
  local cmd = StepExecutor.active
  if not cmd then return nil end
  if nowMs and nowMs > cmd.deadline then
    cmd.state = (cmd.acknowledgedSteps == 0) and "REJECTED" or "STALE"
    local reason = (cmd.acknowledgedSteps == 0) and "NO_POSITION_ACK" or "STALE_COMMAND"
    local old = StepExecutor.active
    StepExecutor.active = nil
    if StepExecutor.releaseOwnership then StepExecutor.releaseOwnership("CAVEBOT") end
    return { timedOut = true, reason = reason, commandId = old.id }
  end
  return nil
end

--- Cancel the active command (preemption / replan / recovery).
function StepExecutor.cancel(reason)
  local cmd = StepExecutor.active
  if not cmd then return nil end
  cmd.state = reason == "PREEMPTED" and "PREEMPTED" or "CANCELLED"
  StepExecutor.active = nil
  if StepExecutor.releaseOwnership then StepExecutor.releaseOwnership("CAVEBOT") end
  return cmd
end

-- Ownership hook (set by session so executor stays pure).
StepExecutor.releaseOwnership = nil

function StepExecutor.getActive()
  return StepExecutor.active
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.step_executor"] = StepExecutor end
return StepExecutor