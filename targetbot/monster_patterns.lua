--[[
  Monster Patterns Module v3.0 — Extracted from monster_ai.lua
  
  Single Responsibility: Known monster pattern storage, lookup, and persistence.
  
  Handles:
  - Pattern registration and retrieval
  - UnifiedStorage-based persistence (single source of truth)
  - Periodic decay of stale patterns
  
  Depends on: monster_ai_core.lua (MonsterAI namespace + constants)
  Populates: MonsterAI.Patterns
]]

-- ============================================================================
-- HELPERS (from core)
-- ============================================================================

local H = MonsterAI._helpers
local nowMs = H.nowMs

local CONST = MonsterAI.CONSTANTS

-- ============================================================================
-- PATTERNS NAMESPACE
-- ============================================================================

MonsterAI.Patterns = MonsterAI.Patterns or {
  knownMonsters = {},
  
  -- Default pattern for unknown monsters (conservative estimate)
  default = {
    hasWaveAttack = true,
    waveWidth = 1,
    waveRange = 5,
    waveCooldown = 2000,
    hasAreaAttack = false,
    areaRadius = 0,
    movementPattern = CONST.MOVEMENT_PATTERN.CHASE,
    dangerLevel = CONST.WAVE_DANGER.MEDIUM,
    preferredDistance = 1
  }
}

-- ============================================================================
-- STORAGE HELPERS (UnifiedStorage only — no dual fallback)
-- ============================================================================

local function getStoredPatterns()
  if UnifiedStorage and UnifiedStorage.isReady and UnifiedStorage.isReady() then
    return UnifiedStorage.get("targetbot.monsterPatterns") or {}
  end
  return storage and storage.monsterPatterns or {}
end

local function setStoredPatterns(patterns)
  if UnifiedStorage and UnifiedStorage.isReady and UnifiedStorage.isReady() then
    UnifiedStorage.set("targetbot.monsterPatterns", patterns)
    if EventBus and EventBus.emit then
      EventBus.emit("monsterAI:patternsUpdated", patterns)
    end
  end
  -- Keep in global storage for backward compatibility
  if storage then
    storage.monsterPatterns = patterns
  end
end

-- ============================================================================
-- PATTERN API
-- ============================================================================

-- Register a known monster pattern
function MonsterAI.Patterns.register(monsterName, pattern)
  MonsterAI.Patterns.knownMonsters[monsterName:lower()] = pattern
end

-- Get pattern for a monster (returns default if unknown)
function MonsterAI.Patterns.get(monsterName)
  if not monsterName then return MonsterAI.Patterns.default end
  return MonsterAI.Patterns.knownMonsters[monsterName:lower()]
    or MonsterAI.Patterns.default
end

-- Persist partial updates to a known monster pattern
function MonsterAI.Patterns.persist(monsterName, updates)
  if not monsterName then return end
  local name = monsterName:lower()
  MonsterAI.Patterns.knownMonsters[name] = MonsterAI.Patterns.knownMonsters[name] or {}
  for k, v in pairs(updates) do
    MonsterAI.Patterns.knownMonsters[name][k] = v
  end
  local patterns = getStoredPatterns()
  patterns[name] = MonsterAI.Patterns.knownMonsters[name]
  setStoredPatterns(patterns)
end

-- Save a specific pattern to storage
function MonsterAI.savePattern(monsterName)
  if not monsterName then return end
  local name = monsterName:lower()
  local patterns = getStoredPatterns()
  patterns[name] = MonsterAI.Patterns.knownMonsters[name]
  setStoredPatterns(patterns)
  if EventBus and EventBus.emit then
    EventBus.emit("monsterAI:patternUpdated", name, MonsterAI.Patterns.knownMonsters[name])
  end
end

-- ============================================================================
-- PATTERN DECAY (reduce confidence of stale patterns)
-- ============================================================================

function MonsterAI.decayPatterns()
  local nowt = nowMs()
  local decayWindow = 7 * 24 * 3600 * 1000 -- 7 days
  local patterns = getStoredPatterns()
  for k, v in pairs(patterns) do
    if v.lastSeen and (nowt - v.lastSeen) > decayWindow then
      v.confidence = (v.confidence or 0.5) * 0.9
      if v.waveCooldown then v.waveCooldown = v.waveCooldown * 1.05 end
      patterns[k] = v
      MonsterAI.Patterns.knownMonsters[k] = v
    end
  end
  setStoredPatterns(patterns)
end

-- ============================================================================
-- INITIALIZATION — Load persisted patterns
-- ============================================================================

local storedPatterns = getStoredPatterns()
for k, v in pairs(storedPatterns) do
  MonsterAI.Patterns.knownMonsters[k] = v
end

-- Schedule recurring decay (hourly)
if schedule then
  schedule(3600000, function()
    MonsterAI.decayPatterns()
    schedule(3600000, function() MonsterAI.decayPatterns() end)
  end)
end

if MonsterAI.DEBUG then
  print("[MonsterAI] Patterns module loaded (" .. tostring(#storedPatterns) .. " patterns)")
end
