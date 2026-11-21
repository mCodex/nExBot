--[[
  navigation/recovery.lua — post-combat / off-route recovery (P0.7, WP26).

  Invariants owned here:
    * Recovery never repeats the same unreachable waypoint without NEW
      evidence (invariant 5) — suppression via evidenceRevision.
    * Targets come from the ROUTE GRAPH only (never geometric projection of
      the old WaypointNavigator), so the WP26 repeated-log is structurally
      impossible to produce.
    * Recovery dispatches ZERO raw GoTo bursts: it selects a route anchor and
      hands back to the session's strict, ack-driven edge flow.

  Interface consumed by Session:
    RecoveryPlanner.new(session)
    instance:onCombatState(prev, next)
    instance:onUnexpectedZChange(newPos, classification)
    instance:tick(session, ctx)   -> NavigationResult | nil (may set .recovered)
    instance:snapshot()           -> table
]]

local domain = require("navigation.domain")
local D = domain
local PathPlanner = require("navigation.path_planner")
local Obs = require("navigation.observability")

local RecoveryPlanner = {}

function RecoveryPlanner.new()
  local self = setmetatable({}, { __index = RecoveryPlanner })
  self.combatActive = false
  self.episodes = 0
  self.suppressed = {}       -- nodeId -> external evidence (last suppressed)
  self.lastTarget = nil
  self.selections = 0        -- focusNode FOCUSED count (self-generated bumps)
  self.phase = "IDLE"
  self.target = nil
  return self
end

-- ── Combat life-cycle ──────────────────────────────────────────────────────

function RecoveryPlanner:onCombatState(prev, next)
  if prev == next then return end
  self.combatActive = next
  if not next then
    self.episodes = self.episodes + 1
    self.phase = "COMBAT_END_RESOLVE"
  end
end

function RecoveryPlanner:onUnexpectedZChange(_newPos, _classification)
  Obs.bump("wrongFloorRecoveryCount", 1)
  self.phase = "RECOVERING"
end

-- ── Target selection (route nodes only) ────────────────────────────────────

local function routeTargets(session)
  -- Recovery targets only EDGE DESTINATIONS: the session walks node->node via
  -- edges, so a focusable recovery node must be some edge's toNode. The pure
  -- start node (no incoming edge) is not a valid focus target.
  local route = session.route
  if not route or not route.edges then return {} end
  local out, seen = {}, {}
  for _, edge in ipairs(route.edges) do
    if edge.toPos and not seen[edge.toNode] then
      seen[edge.toNode] = true
      out[#out + 1] = { nodeId = edge.toNode, pos = edge.toPos }
    end
  end
  return out
end

local function pickTarget(session, targets, fromPos)
  local best = nil
  for _, t in ipairs(targets) do
    if fromPos.z == t.pos.z then
      local reachable = PathPlanner.isReachable(session.ports, fromPos, t.pos, { useCache = true })
      if reachable then
        local dist = D.chebyshev(fromPos, t.pos)
        if not best or dist < best.dist then
          best = { nodeId = t.nodeId, pos = t.pos, dist = dist }
        end
      end
    end
  end
  return best
end

function RecoveryPlanner:tick(session, hostCtx)
  local targets = routeTargets(session)
  local nowMs = hostCtx and hostCtx.nowMs or 0

  local failSafe = function(reason)
    self.phase = "FAILED_SAFE"
    return D.result(D.NavStatus.FAILED_TERMINAL, reason, { recovery = self:snapshot() })
  end

  if #targets == 0 then
    return failSafe(D.REASON.RECOVERY_TARGET_UNREACHABLE)
  end

  local anchor = session:getAnchor()
  local fromPos = (anchor and anchor.pos) or hostCtx.playerPos
  if not fromPos then
    return D.result(D.NavStatus.WAITING_BLOCKER, "RECOVERY_DEFERRED", { recovery = self:snapshot() })
  end

  local chosen = pickTarget(session, targets, fromPos)
  if not chosen then
    Obs.bump("wrongRouteRecoveryCount", 1)
    return failSafe(D.REASON.RECOVERY_TARGET_UNREACHABLE)
  end

  -- Invariant 5: never repeat the same target without NEW external evidence.
  -- focusNode() bumps evidenceRevision via selectEdge, so subtract the bumps
  -- recovery itself caused to isolate genuinely new player-world evidence.
  local external = (session.evidenceRevision or 0) - self.selections
  if self.lastTarget == chosen.nodeId and self.suppressed[chosen.nodeId]
     and self.suppressed[chosen.nodeId] >= external then
    Obs.bump("identicalUnchangedRecoveryLoopCount", 1)
    return failSafe(D.REASON.RECOVERY_TARGET_DUPLICATE_SUPPRESSED)
  end

  self.suppressed[chosen.nodeId] = external
  self.lastTarget = chosen.nodeId
  self.target = chosen
  self.phase = "ANCHOR_SELECTED"

  local focus = session:focusNode(chosen.nodeId)
  if focus == "FOCUSED" then self.selections = self.selections + 1 end
  if focus == "NODE_NOT_FOUND" then
    Obs.bump("wrongRouteRecoveryCount", 1)
    return failSafe(D.REASON.RECOVERY_TARGET_UNREACHABLE)
  end

  Obs.record({
    tickId = session._tickId, timestamp = nowMs, playerPosition = fromPos,
    reasonCodes = { D.REASON.RECOVERY_ANCHOR_SELECTED },
    detail = { targetNode = chosen.nodeId, anchor = fromPos },
  })

  -- Signal the session to leave RECOVERING and resume strict edge dispatch.
  return D.result(D.NavStatus.PROGRESS, D.REASON.RECOVERY_ANCHOR_SELECTED, {
    recovered = true, observedProgress = false,
    targetNode = chosen.nodeId, recovery = self:snapshot(),
  })
end

function RecoveryPlanner:snapshot()
  return {
    phase = self.phase,
    combatActive = self.combatActive,
    episodes = self.episodes,
    target = self.target,
    suppressed = self.suppressed,
  }
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.recovery"] = RecoveryPlanner end
return RecoveryPlanner