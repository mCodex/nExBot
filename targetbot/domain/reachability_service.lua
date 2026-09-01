ReachabilityService = {}
local S = ReachabilityService

local MAX_EVIDENCE = 64
local MAX_SAMPLES = 10

local evidence = {}

local function nowMs()
  return nExBot.Shared.nowMs()
end

local function posKey(p)
  if not p then return "?" end
  return tostring(p.x) .. "," .. tostring(p.y) .. "," .. tostring(p.z)
end

local function creatureId(c)
  if SafeCreature and SafeCreature.getId then return SafeCreature.getId(c) end
  if c and c.getId then return c:getId() end
end

local function creaturePos(c)
  if SafeCreature and SafeCreature.getPosition then return SafeCreature.getPosition(c) end
  if c and c.getPosition then return c:getPosition() end
end

local function playerPos()
  local p = player
  if not p and g_game and g_game.getLocalPlayer then p = g_game.getLocalPlayer() end
  return creaturePos(p)
end

local function newEvidence(id)
  return {
    creatureId = id,
    samples = {},
    firstFailureAt = nil,
    lastFailureAt = nil,
    failureCount = 0,
    consecutiveFailures = 0,
    lastSuccessAt = nil,
  }
end

local function evictIfNeeded()
  local count = 0
  for _ in pairs(evidence) do count = count + 1 end
  while count >= MAX_EVIDENCE do
    local oldest, oldestAt = nil, math.huge
    for id, e in pairs(evidence) do
      local t = e.lastFailureAt or e.lastSuccessAt or math.huge
      if t < oldestAt then oldest, oldestAt = id, t end
    end
    if oldest then evidence[oldest] = nil; count = count - 1 else break end
  end
end

local function addSample(e, state, pp, cp)
  local sample = { state = state, at = nowMs(), playerPos = pp and { x = pp.x, y = pp.y, z = pp.z }, creaturePos = cp and { x = cp.x, y = cp.y, z = cp.z } }
  table.insert(e.samples, sample)
  while #e.samples > MAX_SAMPLES do table.remove(e.samples, 1) end
end

local function mapState(tr)
  if tr.reason == "removed" then return ReachabilityState.REMOVED end
  if tr.reason == "different_floor" then return ReachabilityState.DIFFERENT_FLOOR end
  if tr.attackable then return ReachabilityState.ATTACKABLE_NOW end
  if tr.reason == "no_path_api" then return ReachabilityState.PATH_API_UNAVAILABLE end
  if tr.reason == "no_line_of_sight" then return ReachabilityState.REPOSITION_REQUIRED end
  if tr.reason == "no_attack_position" then return ReachabilityState.TEMPORARILY_BLOCKED end
  if tr.reason == "creature_blocked" then return ReachabilityState.TEMPORARILY_BLOCKED end
  if tr.reason == "incomplete_map" then return ReachabilityState.TEMPORARILY_BLOCKED end
  return ReachabilityState.VISIBILITY_UNKNOWN
end

local function isHardFailure(state)
  return state == ReachabilityState.TEMPORARILY_BLOCKED
    or state == ReachabilityState.CONFIRMED_HARD_UNREACHABLE
    or state == ReachabilityState.VISIBILITY_UNKNOWN
    or state == ReachabilityState.PATH_API_UNAVAILABLE
end

local function checkConfirmed(e)
  if e.failureCount < 3 then return false end
  local positions = {}
  local uniqueCount = 0
  for _, s in ipairs(e.samples) do
    if s.playerPos then
      local k = posKey(s.playerPos)
      if not positions[k] then positions[k] = true; uniqueCount = uniqueCount + 1 end
    end
  end
  if uniqueCount >= 3 then return true end
  if e.consecutiveFailures >= 5 and e.firstFailureAt and e.lastFailureAt then
    local span = e.lastFailureAt - e.firstFailureAt
    if span >= 3000 then return true end
  end
  return false
end

function S.evaluate(creature, context)
  local tr = TargetReachability.evaluate(creature, context)
  local id = creatureId(creature)
  local pp = playerPos()
  local cp = creaturePos(creature)
  local state = mapState(tr)

  if not id then
    return { state = state, reason = tr.reason, path = tr.path, evidence = nil, attackable = state == ReachabilityState.ATTACKABLE_NOW }
  end

  local e = evidence[id]
  if not e then evictIfNeeded(); e = newEvidence(id); evidence[id] = e end

  if state == ReachabilityState.ATTACKABLE_NOW then
    e.lastSuccessAt = nowMs()
    e.consecutiveFailures = 0
    e.failureCount = 0
    e.firstFailureAt = nil
    e.lastFailureAt = nil
    addSample(e, state, pp, cp)
    return { state = state, reason = tr.reason, path = tr.path, evidence = e, attackable = true }
  end

  if isHardFailure(state) then
    local t = nowMs()
    if not e.firstFailureAt then e.firstFailureAt = t end
    e.lastFailureAt = t
    e.failureCount = e.failureCount + 1
    e.consecutiveFailures = e.consecutiveFailures + 1
  end

  addSample(e, state, pp, cp)

  if isHardFailure(state) and checkConfirmed(e) then
    state = ReachabilityState.CONFIRMED_HARD_UNREACHABLE
  end

  return { state = state, reason = tr.reason, path = tr.path, evidence = e, attackable = false }
end

function S.getEvidence(cid)
  return evidence[cid]
end

function S.invalidateOnPlayerMove()
  evidence = {}
end

function S.invalidateOnCreatureMove(cid)
  evidence[cid] = nil
end

function S.reset()
  evidence = {}
end

if EventBus and EventBus.on then
  pcall(EventBus.on, "player:position", function()
    ReachabilityService.invalidateOnPlayerMove()
  end)
  pcall(EventBus.on, "creature:move", function(creature)
    local id = creature and creature.getId and creature:getId()
    if id then ReachabilityService.invalidateOnCreatureMove(id) end
  end)
  pcall(EventBus.on, "monster:disappear", function(creature)
    local id = creature and creature.getId and creature:getId()
    if id then ReachabilityService.invalidateOnCreatureMove(id) end
  end)
end

return S
