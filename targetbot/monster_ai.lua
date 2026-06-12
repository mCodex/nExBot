--[[
  Monster AI Analysis Module v4.0 — Stripped orchestrator.

  Single responsibility: connect EventBus creature events to MonsterAI.Tracker,
  and run periodic updateAll() for basic creature maintenance.

  Kept from v3.x:
    - MonsterAI.Tracker integration (creature tracking data)
    - EventBus wiring (appear/disappear/health/move/damage)
    - updateAll() with periodic tracker refresh
    - UnifiedTick registration
    - Public API wrappers for Scenario, Reachability, Core

  Removed modules (moved to separate files or deleted):
    - VolumeAdaptation, RealTime, Telemetry, Metrics
    - Predictor, CombatFeedback, AutoTuner, SpellTracker
    - TBI, Patterns, Classifier, Tracking

  Dependencies (loaded BEFORE this file in targetbot_init.lua):
    - monster_ai_core.lua  → MonsterAI._helpers, MonsterAI.CONSTANTS
    - monster_tracking.lua → MonsterAI.Tracker
    - monster_scenario.lua → MonsterAI.Scenario
    - monster_reachability.lua → MonsterAI.Reachability
]]

MonsterAI = MonsterAI or {}
MonsterAI.VERSION = "4.0"

local getClient = nExBot.Shared.getClient
local getClientVersion = nExBot.Shared.getClientVersion

local nowMs = ClientHelper and ClientHelper.nowMs or function()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

local _H = MonsterAI._helpers or {}
local isValidAliveMonster = _H.isValidAliveMonster or function(c)
  return c ~= nil
end
local safeGetId = _H.safeGetId

-- Aliases for simpler use
MonsterAI.DEBUG = MonsterAI.DEBUG or false
MonsterAI.COLLECT_ENABLED = (MonsterAI.COLLECT_ENABLED == nil) and true or MonsterAI.COLLECT_ENABLED

local function tbOff()
  return not TargetBot or not TargetBot.isOn or not TargetBot.isOn()
end

local function shouldCollect()
  if not MonsterAI.COLLECT_ENABLED then return false end
  if TargetBot and TargetBot.isOn and not TargetBot.isOn() then return false end
  return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EVENTBUS WIRING (keep Tracker in sync with creature lifecycle)
-- ═══════════════════════════════════════════════════════════════════════════

if EventBus then
  EventBus.on("monster:appear", function(creature)
    if tbOff() then return end
    if MonsterAI.Tracker then MonsterAI.Tracker.track(creature) end
  end, 35)

  EventBus.on("monster:disappear", function(creature)
    if tbOff() then return end
    if creature and MonsterAI.Tracker then
      local id = safeGetId(creature)
      if id then MonsterAI.Tracker.untrack(id) end
    end
  end, 35)

  EventBus.on("creature:move", function(creature)
    if tbOff() then return end
    if not creature then return end
    if MonsterAI.Tracker then MonsterAI.Tracker.update(creature) end
  end, 40)

  EventBus.on("monster:health", function(creature)
    if tbOff() then return end
    if creature and MonsterAI.Tracker then MonsterAI.Tracker.update(creature) end
  end, 30)

  EventBus.on("player:damage", function(damage, source)
    if tbOff() then return end
    if not MonsterAI.Tracker then return end
    MonsterAI.Tracker.stats.totalDamageReceived =
      (MonsterAI.Tracker.stats.totalDamageReceived or 0) + damage

    if not source then return end
    local sid = safeGetId(source)
    if sid then
      local data = MonsterAI.Tracker.monsters[sid]
      if data then
        data.lastDamageTime = nowMs()
        data.lastAttackTime = nowMs()
        data.damageSamples = data.damageSamples or {}
        data.damageSamples[#data.damageSamples + 1] = { time = nowMs(), amount = damage }
        data.totalDamage = (data.totalDamage or 0) + damage
      end
    end
  end, 30)

  EventBus.on("player:attack", function(target)
    if tbOff() then return end
    if not target then return end
    local id = safeGetId(target)
    if id and MonsterAI.Tracker and MonsterAI.Tracker.monsters[id] then
      MonsterAI.Tracker.monsters[id].lastActivityTime = nowMs()
    end
  end, 25)

  EventBus.on("creature:death", function(creature)
    if tbOff() then return end
    if not creature then return end
    local id = safeGetId(creature)
    if id and MonsterAI.Tracker and MonsterAI.Tracker.monsters[id] then
      local data = MonsterAI.Tracker.monsters[id]
      if data.engagementStart then
        data.engagementDuration = nowMs() - data.engagementStart
      end
    end
  end, 30)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PERIODIC UPDATE
-- ═══════════════════════════════════════════════════════════════════════════

function MonsterAI.updateAll()
  local playerPos = player and player:getPosition()
  if not playerPos then return end

  local creatures
  if MovementCoordinator and MovementCoordinator.MonsterCache
    and MovementCoordinator.MonsterCache.getNearby then
    creatures = MovementCoordinator.MonsterCache.getNearby(8)
  end
  if not creatures or #creatures == 0 then
    local Client = getClient()
    local ok, result = pcall(function()
      if Client and Client.getSpectatorsInRange then
        return Client.getSpectatorsInRange(playerPos, false, 8, 8)
      elseif g_map and g_map.getSpectatorsInRange then
        return g_map.getSpectatorsInRange(playerPos, false, 8, 8)
      end
      return {}
    end)
    creatures = ok and result or {}
  end
  if not creatures then return end

  for i = 1, #creatures do
    local creature = creatures[i]
    if creature and isValidAliveMonster(creature) then
      pcall(function() if MonsterAI.Tracker then MonsterAI.Tracker.update(creature) end end)
    end
  end

  -- Checksum guard: emit monsterai:state_updated only when state changes
  local nowt = nowMs()
  local chk = 0
  if MonsterAI.Tracker and MonsterAI.Tracker.monsters then
    for id, d in pairs(MonsterAI.Tracker.monsters) do
      chk = (chk + (id % 997) + ((d.lastAttackTime or 0) % 997)) % 65521
    end
  end
  if chk ~= MonsterAI._stateChecksum then
    MonsterAI._stateChecksum = chk
    if EventBus then
      pcall(function() EventBus.emit("monsterai:state_updated") end)
    end
  end
  MonsterAI.lastUpdate = nowt
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API (thin wrappers for Scenario, Reachability, Tracker)
-- ═══════════════════════════════════════════════════════════════════════════

local function getMonsterCount()
  if MonsterAI.Tracker and MonsterAI.Tracker.monsters then
    local count = 0
    for _ in pairs(MonsterAI.Tracker.monsters) do count = count + 1 end
    return count
  end
  return 0
end

function MonsterAI.getStatsSummary()
  local nowt = nowMs()
  local session = MonsterAI.Tracker and MonsterAI.Tracker.stats or {}
  return {
    version = MonsterAI.VERSION,
    session = {
      activeMonsters = getMonsterCount(),
      damageReceived = session.totalDamageReceived or 0,
    }
  }
end

function MonsterAI.resetSession()
  if MonsterAI.Tracker then
    MonsterAI.Tracker.stats = {
      waveAttacksObserved = 0,
      areaAttacksObserved = 0,
      totalDamageReceived = 0,
    }
  end
end

-- Emit periodic stats update for UI
if EventBus then
  schedule(5000, function()
    local function emitStatsUpdate()
      if not tbOff() and EventBus and EventBus.emit then
        local stats = MonsterAI.getStatsSummary()
        EventBus.emit("monsterai:stats_update", stats)
      end
      schedule(10000, emitStatsUpdate)
    end
    emitStatsUpdate()
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- UNIFIED TICK INTEGRATION
-- ═══════════════════════════════════════════════════════════════════════════

if UnifiedTick and UnifiedTick.register then
  UnifiedTick.register({
    id = "monsterai_update",
    interval = 500,
    priority = UnifiedTick.PRIORITY and UnifiedTick.PRIORITY.NORMAL or 50,
    callback = function()
      if shouldCollect() and MonsterAI.updateAll then
        pcall(function() MonsterAI.updateAll() end)
      end
    end
  })
else
  macro(500, function()
    if zChanging() then return end
    if shouldCollect() and MonsterAI.updateAll then
      pcall(function() MonsterAI.updateAll() end)
    end
  end)
end

nExBot = nExBot or {}
nExBot.MonsterAI = MonsterAI

if MonsterAI.DEBUG then
  print("[MonsterAI] v" .. MonsterAI.VERSION .. " loaded; collection=" .. tostring(MonsterAI.COLLECT_ENABLED))
end
