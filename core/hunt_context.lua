--[[
  HuntContext Module v1.0

  Bridge between Hunt Analyzer (smart_hunt.lua) and PriorityEngine.
  Provides a lazy-cached signal struct consumed by PriorityEngine.huntScore().

  SRP  — owns only the translation of hunt metrics → targeting signal.
  DRY  — single source of truth for the hunt→targeting bridge.
  KISS — flat struct, no nested logic, O(1) read in hot path.
  SOLID — open for new signal fields, closed for modification of callers.

  API:
    HuntContext.getSignal() → { survivability, manaStress, efficiency, threatBias }
    All values: 0.0–1.0 (normalized). Always returns the cached struct,
    never nil — safe to read from every PriorityEngine scoring cycle.

  Cache policy:
    - Recompute when any input metric changes by ≥ CHANGE_THRESHOLD (5%).
    - Force recompute after CACHE_MAX_AGE_MS (30 s) regardless.
    - Guard: if HuntAnalytics is absent or session inactive, returns neutral signal.
]]

HuntContext = HuntContext or {}
HuntContext.VERSION = "1.0"

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================

local nowMs = (ClientHelper and ClientHelper.nowMs) or function()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local CACHE_MAX_AGE_MS  = 30000  -- force recompute every 30 s
local CHANGE_THRESHOLD  = 0.05   -- 5% drift in any input triggers recompute

-- Normalisation baselines (tunable via EventBus recalibrate event)
local BASELINE = {
  killsPerHour_max   = 200,   -- 200 kills/hr → efficiency = 1.0
  manaPotions_stress = 60,    -- 60 potions/hr → manaStress = 1.0
}

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

-- Neutral signal returned when no session data is available
local _signal = {
  survivability = 1.0,
  manaStress    = 0.0,
  efficiency    = 1.0,
  threatBias    = 0.0,
}

local _lastComputed = 0
local _lastRaw      = {}

-- ============================================================================
-- PURE HELPERS
-- ============================================================================

local function clamp01(v)
  return math.max(0.0, math.min(1.0, v or 0.0))
end

-- Returns true when at least one raw value drifted beyond CHANGE_THRESHOLD
local function hasChanged(raw)
  for k, v in pairs(raw) do
    local prev = _lastRaw[k] or 0
    if prev == 0 then
      if v ~= 0 then return true end
    elseif math.abs((v - prev) / prev) >= CHANGE_THRESHOLD then
      return true
    end
  end
  return false
end

-- ============================================================================
-- SIGNAL COMPUTATION
-- ============================================================================

local function computeSignal()
  if not (HuntAnalytics and HuntAnalytics.getMetrics) then return end

  local ok, metrics = pcall(HuntAnalytics.getMetrics)
  if not ok or not metrics then return end

  local raw = {
    survivabilityIndex = metrics.survivabilityIndex or 100,
    damageRatio        = metrics.damageRatio        or 0,
    potionsPerHour     = metrics.potionsPerHour     or 0,
    efficiency         = metrics.efficiency         or 0,
    killsPerHour       = metrics.killsPerHour       or 0,
    nearDeathPerHour   = metrics.nearDeathPerHour   or 0,
  }

  if not hasChanged(raw) then return end
  _lastRaw = raw

  -- survivability: survivabilityIndex is 0–100; normalize to 0–1
  local surv = clamp01(raw.survivabilityIndex / 100)

  -- manaStress: potionsPerHour proxy; 60+/hr = full stress
  local manaStress = clamp01(raw.potionsPerHour / BASELINE.manaPotions_stress)

  -- efficiency: killsPerHour normalized; 200+/hr = optimal
  local eff = clamp01(raw.killsPerHour / BASELINE.killsPerHour_max)

  -- threatBias: composite push signal — high when survivability is low AND mana stressed
  local threatBias = clamp01((1 - surv) * 0.6 + manaStress * 0.4)

  _signal.survivability = surv
  _signal.manaStress    = manaStress
  _signal.efficiency    = eff
  _signal.threatBias    = threatBias
  _lastComputed = nowMs()
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Returns the hunt signal struct. Always O(1) — recomputes lazily only when
--- input metrics drift beyond threshold or cache expires.
--- Never nil. Safe to call from every PriorityEngine scoring cycle.
---@return table { survivability, manaStress, efficiency, threatBias }
function HuntContext.getSignal()
  local t = nowMs()
  if (t - _lastComputed) >= CACHE_MAX_AGE_MS then
    -- Cache expired: force recompute
    pcall(computeSignal)
    -- Bump timestamp even on failure so we don't hammer a missing HuntAnalytics
    _lastComputed = t
  else
    -- Within cache window: only recompute if inputs drifted
    pcall(computeSignal)
  end
  return _signal
end

--- Reset signal to neutral defaults (call on session start or stop).
function HuntContext.reset()
  _signal       = { survivability = 1.0, manaStress = 0.0, efficiency = 1.0, threatBias = 0.0 }
  _lastComputed = 0
  _lastRaw      = {}
end

--- Recalibrate normalisation baselines (e.g. for different vocation/spawn).
---@param overrides table { killsPerHour_max?, manaPotions_stress? }
function HuntContext.recalibrate(overrides)
  if type(overrides) ~= "table" then return end
  for k, v in pairs(overrides) do
    if BASELINE[k] ~= nil and type(v) == "number" and v > 0 then
      BASELINE[k] = v
    end
  end
  -- Invalidate cache so next getSignal() recomputes with new baselines
  _lastComputed = 0
  _lastRaw      = {}
end

-- ============================================================================
-- EVENTBUS WIRING
-- ============================================================================

if EventBus and EventBus.on then
  -- Reset on each hunt session start
  EventBus.on("analytics:session:start", function()
    HuntContext.reset()
  end, 0)

  -- Allow runtime recalibration
  EventBus.on("hunt_context:recalibrate", function(overrides)
    HuntContext.recalibrate(overrides)
  end, 0)
end

if MonsterAI and MonsterAI.DEBUG then
  print("[HuntContext] v" .. HuntContext.VERSION .. " loaded")
end
