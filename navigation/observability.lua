--[[
  navigation/observability.lua — bounded decision records + navigation metrics.

  * NavigationDecisionRecord ring buffer (bounded, default 256).
  * Mandatory soak counters (wall-directed commands etc. must stay 0).
  * Tactical UI snapshot is read-only; building it never touches combat ticks
    (callers sample it at most once per second).
]]

local Obs = {}

local ring = {}
local ringMax = 256
local ringCount = 0

local metrics = {
  routeCompletionRate = 0,
  edgeCompletionRate = 0,
  stuckEvents = 0,
  wallDirectedCommandCount = 0,        -- MUST stay 0
  invalidStepCommandCount = 0,         -- MUST stay 0
  criticalEdgeSkipCount = 0,           -- MUST stay 0
  duplicateRecoveryProposalCount = 0,
  duplicateRecoveryCommandCount = 0,   -- MUST stay 0
  wrongRouteRecoveryCount = 0,         -- MUST stay 0
  wrongFloorRecoveryCount = 0,
  averageRetriesPerEdge = 0,
  partialAutoWalkRate = 0,
  pathDivergenceRate = 0,
  movementCommandsPerAcknowledgedStep = 0,
  ladderSuccessRate = 0,
  ropeSuccessRate = 0,
  transitionWrongExitRate = 0,
  manualInterventionRate = 0,
  averageDecisionTime = 0,
  p95DecisionTime = 0,
  p99DecisionTime = 0,
  memoryGrowth = 0,
  MLShadowAgreement = 0,
  MLActiveRegressionRate = 0,
  unexplainedWaypointAdvanceCount = 0, -- MUST stay 0
  identicalUnchangedRecoveryLoopCount = 0, -- MUST stay 0
  missingToolCount = 0,
  actionNoEffectCount = 0,
  mlShadowAgreement = 0,
  mlGuardrailRejections = 0,
}

local decisionTimes = {}

function Obs.setRingMax(n)
  ringMax = math.max(16, math.floor(n or 256))
end

--- Record one navigation decision (sampled if the ring is full).
-- @param record NavigationDecisionRecord
function Obs.record(record)
  ringCount = ringCount + 1
  local slot = (ringCount % ringMax) + 1
  ring[slot] = record
end

function Obs.recent(n)
  local out = {}
  local count = math.min(n or 50, ringCount, ringMax)
  local start = (ringCount - count) % ringMax + 1
  for i = 0, count - 1 do
    local idx = (start + i - 1) % ringMax + 1
    if ring[idx] then out[#out + 1] = ring[idx] end
  end
  return out
end

function Obs.last(reasonCode)
  for i = #Obs.recent(ringMax), 1, -1 do
    local rec = ring[i]
    if rec and rec.reasonCodes then
      for _, rc in ipairs(rec.reasonCodes) do
        if rc == reasonCode then return rec end
      end
    end
  end
  return nil
end

-- ── Metrics ────────────────────────────────────────────────────────────────

local function bump(key, delta)
  metrics[key] = (metrics[key] or 0) + (delta or 1)
end

function Obs.bump(key, delta)
  bump(key, delta)
end

function Obs.trackDecisionTime(ms)
  decisionTimes[#decisionTimes + 1] = ms
  if #decisionTimes > 512 then table.remove(decisionTimes, 1) end
end

local function percentile(sorted, p)
  if #sorted == 0 then return 0 end
  local idx = math.max(1, math.min(#sorted, math.ceil(p * #sorted)))
  return sorted[idx]
end

function Obs.snapshot()
  local times = {}
  for _, t in ipairs(decisionTimes) do times[#times + 1] = t end
  table.sort(times)
  local avg = 0
  for _, t in ipairs(times) do avg = avg + t end
  if #times > 0 then avg = avg / #times end
  local s = {}
  for k, v in pairs(metrics) do s[k] = v end
  s.averageDecisionTime = avg
  s.p95DecisionTime = percentile(times, 0.95)
  s.p99DecisionTime = percentile(times, 0.99)
  s.ringCount = ringCount
  s.memoryGrowth = math.floor(collectgarbage("count"))
  return s
end

function Obs.resetMetrics()
  for k in pairs(metrics) do metrics[k] = 0 end
  decisionTimes = {}
  ring = {}
  ringCount = 0
end

-- ── Tactical UI snapshot (read-only view of navigation state) ──────────────
function Obs.uiSnapshot(session)
  local s = {
    currentRoute = nil,
    activeEdge = nil,
    activeNode = nil,
    acknowledgedCursor = nil,
    movementCommandId = nil,
    movementOwner = nil,
    mapGeneration = nil,
    pathGeneration = nil,
    retryPhase = nil,
    failureReason = nil,
    obstacle = nil,
    transition = nil,
    recovery = nil,
    ml = { mode = "SHADOW", recommendation = nil, guardrail = nil },
  }
  if not session then return s end
  local srv = session:snapshot()
  for k, v in pairs(srv) do s[k] = v end
  return s
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.observability"] = Obs end
return Obs