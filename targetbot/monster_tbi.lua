--[[
  Monster TargetBot Integration (TBI) Module v4.0

  Single Responsibility: Danger assessment, debug helpers, and EventBus wiring
  for the TargetBot subsystem. Priority calculation is fully delegated to
  PriorityEngine (single source of truth — see priority_engine.lua).

  REMOVED in v4.0 (consolidated into PriorityEngine):
    - TBI.calculatePriority()   → PriorityEngine.calculate()
    - TBI.getSortedTargets()    → PriorityEngine handles per-creature scoring
    - TBI.getBestTarget()       → use PriorityEngine directly
    - schedule() emit loop      → no more unconditional targetbot:ai_recommendation flood

  KEPT / REFACTORED:
    - TBI.getDangerLevel()      → uses PriorityEngine.calculate() for consistency
    - TBI.getStats()            → subsystem health summary
    - TBI.debugCreature()       → delegates to PriorityEngine for breakdown
    - TBI.isCreatureFacingPosition() / TBI.predictPosition() → pure geometry helpers

  Depends on: monster_ai_core.lua, PriorityEngine (priority_engine.lua)
  Populates:  MonsterAI.TargetBot (TBI)
]]

local H               = MonsterAI._helpers
local nowMs           = H.nowMs
local safeGetId       = H.safeGetId
local safeIsDead      = H.safeIsDead
local safeIsRemoved   = H.safeIsRemoved
local safeCreatureCall = H.safeCreatureCall
local getClient       = H.getClient
local isValidAliveMonster = H.isValidAliveMonster

-- Guard: returns true when TargetBot is disabled
local function tbOff() return not TargetBot or not TargetBot.isOn or not TargetBot.isOn() end

-- ============================================================================
-- STATE
-- ============================================================================

MonsterAI.TargetBot = MonsterAI.TargetBot or {}
local TBI = MonsterAI.TargetBot

-- Default config used when building a minimal config for PriorityEngine calls
TBI._defaultConfig = {
  priority    = 1,
  maxDistance = 8,
  chase       = false,
  danger      = 0,
}

-- ============================================================================
-- GEOMETRY HELPERS (pure — unchanged from v3.0)
-- ============================================================================

function TBI.isCreatureFacingPosition(cpos, dir, tpos)
  if not cpos or not dir or not tpos then return false end
  local dx, dy = tpos.x - cpos.x, tpos.y - cpos.y
  if dir == 0 then return dy < 0 and math.abs(dx) <= math.abs(dy)
  elseif dir == 1 then return dx > 0 and math.abs(dy) <= math.abs(dx)
  elseif dir == 2 then return dy > 0 and math.abs(dx) <= math.abs(dy)
  elseif dir == 3 then return dx < 0 and math.abs(dy) <= math.abs(dx) end
  return false
end

function TBI.predictPosition(pos, dir, steps)
  if not pos or not dir then return nil end
  steps = steps or 1
  local m = {
    [0]={0,-1},[1]={1,0},[2]={0,1},[3]={-1,0},
    [4]={1,-1},[5]={1,1},[6]={-1,1},[7]={-1,-1}
  }
  local d = m[dir]
  if not d then return nil end
  return { x = pos.x + d[1]*steps, y = pos.y + d[2]*steps, z = pos.z }
end

-- ============================================================================
-- DANGER LEVEL (delegates scoring to PriorityEngine)
-- ============================================================================

--- Compute overall danger level and active threat list using PriorityEngine.
--- @param maxRange number  optional search radius (default 8)
--- @return number (0–10), table threats
function TBI.getDangerLevel(maxRange)
  maxRange = maxRange or 8
  local ppos = player and player:getPosition()
  if not ppos then return 0, {} end
  if not (PriorityEngine and PriorityEngine.calculate) then return 0, {} end

  local level  = 0
  local threats = {}
  local cfg    = TBI._defaultConfig

  local C = getClient()
  local creatures = (C and C.getSpectators) and C.getSpectators(ppos, false)
    or (g_map and g_map.getSpectators and g_map.getSpectators(ppos, false)) or {}

  for _, cr in ipairs(creatures) do
    if cr and isValidAliveMonster(cr) then
      local cp = safeCreatureCall(cr, "getPosition", nil)
      if cp and cp.z == ppos.z then
        local d = math.max(math.abs(cp.x - ppos.x), math.abs(cp.y - ppos.y))
        if d <= maxRange then
          local pri = PriorityEngine.calculate(cr, cfg, nil)
          local tl  = pri / 200
          level = level + tl
          if tl >= 1.0 then
            local id = safeGetId(cr)
            local td = MonsterAI.Tracker and id and MonsterAI.Tracker.monsters[id]
            threats[#threats+1] = {
              name     = safeCreatureCall(cr, "getName", "unknown"),
              level    = tl,
              imminent = td and td.wavePredicted or false,
            }
          end
        end
      end
    end
  end

  return math.min(10, level), threats
end

-- ============================================================================
-- STATS / DEBUG
-- ============================================================================

function TBI.getStats()
  return {
    feedbackActive = MonsterAI.CombatFeedback ~= nil,
    trackerActive  = MonsterAI.Tracker        ~= nil,
    realTimeActive = MonsterAI.RealTime       ~= nil,
    priorityEngine = PriorityEngine           ~= nil,
    feedback       = MonsterAI.CombatFeedback and MonsterAI.CombatFeedback.getStats
                       and MonsterAI.CombatFeedback.getStats() or nil,
  }
end

--- Print a full PriorityEngine breakdown for a specific creature to console.
function TBI.debugCreature(creature)
  if not creature then print("[TBI] No creature specified"); return end
  if not (PriorityEngine and PriorityEngine.calculate) then
    print("[TBI] PriorityEngine not loaded"); return
  end
  local cfg = TBI._defaultConfig
  -- Build a minimal path estimate using Chebyshev distance
  local ppos = player and player:getPosition()
  local cpos = safeCreatureCall(creature, "getPosition", nil)
  local path = nil
  if ppos and cpos then
    local d = math.max(math.abs(cpos.x - ppos.x), math.abs(cpos.y - ppos.y))
    -- Fake a path table of length d so distanceScore behaves correctly
    path = {}
    for i = 1, d do path[i] = 0 end
  end
  local pri = PriorityEngine.calculate(creature, cfg, path)
  local name = safeCreatureCall(creature, "getName", "unknown")
  print(string.format("[TBI] PriorityEngine score for '%s': %d", name, pri))
  -- Dump MonsterAI tracker data if available
  local id = safeGetId(creature)
  if id and MonsterAI.Tracker and MonsterAI.Tracker.monsters then
    local td = MonsterAI.Tracker.monsters[id]
    if td then
      print(string.format("  DPS=%.1f  waveCount=%d  confidence=%.2f  ewmaCooldown=%s",
        td.ewmaDps or 0, td.waveCount or 0, td.confidence or 0,
        td.ewmaCooldown and string.format("%dms", math.floor(td.ewmaCooldown)) or "-"))
    end
  end
  -- Dump HuntContext signal
  if HuntContext and HuntContext.getSignal then
    local sig = HuntContext.getSignal()
    print(string.format("  HuntContext: surv=%.2f  manaStress=%.2f  eff=%.2f  threatBias=%.2f",
      sig.survivability, sig.manaStress, sig.efficiency, sig.threatBias))
  end
end

-- ============================================================================
-- EVENTBUS
-- ============================================================================

if EventBus and EventBus.on then
  -- Respond to direct priority requests from other modules
  EventBus.on("targetbot:request_priority", function(creature, callback)
    if tbOff() then return end
    if creature and callback then
      local cfg = TBI._defaultConfig
      local pri = PriorityEngine and PriorityEngine.calculate(creature, cfg, nil) or 0
      callback(pri)
    end
  end)
end

if MonsterAI.DEBUG then print("[MonsterAI] TBI module v4.0 loaded (delegates to PriorityEngine)") end
