--[[
  Monster AI Core Module v3.0
  
  Foundation module for the Monster AI Analysis system.
  Provides the shared namespace, safe creature validation helpers,
  constants, and configuration flags used by ALL MonsterAI subsystems.
  
  This file MUST be loaded first in the MonsterAI module chain.
  Every other monster_*.lua file depends on this module.
  
  Architecture (SRP decomposition):
    monster_ai_core.lua      -> Namespace, constants, safe helpers
    monster_patterns.lua     -> Pattern persistence & lookup
    monster_tracking.lua     -> Per-creature data collection
    monster_prediction.lua   -> Behavior prediction & confidence
    monster_combat_feedback.lua -> Adaptive learning from combat
    monster_spell_tracker.lua   -> Spell/missile analysis
    auto_tuner.lua           -> Classification & danger tuning
    monster_scenario.lua     -> Anti-zigzag & engagement locks
    monster_reachability.lua -> Path analysis & blocked creatures
    monster_tbi.lua          -> TargetBot Integration (priority scoring)
    monster_ai.lua           -> Orchestrator (VolumeAdaptation, RealTime,
                                 Telemetry, Metrics, Classifier, EventBus,
                                 updateAll, public API, tick registration)
]]

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

MonsterAI = MonsterAI or {}
MonsterAI.VERSION = "3.0"

-- ============================================================================
-- CLIENT SERVICE HELPERS (shared aliases)
-- ============================================================================

local getClient = nExBot.Shared.getClient
local getClientVersion = nExBot.Shared.getClientVersion

-- Time helper (use ClientHelper for DRY)
local nowMs = ClientHelper and ClientHelper.nowMs or function()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

-- ============================================================================
-- SAFE CREATURE VALIDATION (Prevents C++ crashes)
-- The OTClient C++ layer can crash even when methods exist if the creature
-- object is in an invalid internal state. These helpers prevent that.
-- ============================================================================

-- Cache for recently validated creatures to reduce overhead
local validatedCreatures = {}
local validatedCreaturesTTL = 100 -- ms

-- Check if a creature is valid and safe to call methods on
local function isCreatureValid(creature)
  if not creature then return false end
  if type(creature) ~= "userdata" and type(creature) ~= "table" then return false end
  
  local ok, id = pcall(function() return creature:getId() end)
  if not ok or not id then return false end
  
  -- Check validation cache
  local nowt = nowMs()
  local cached = validatedCreatures[id]
  if cached and (nowt - cached.time) < validatedCreaturesTTL then
    return cached.valid
  end
  
  -- Perform full validation
  local okPos, pos = pcall(function() return creature:getPosition() end)
  local valid = okPos and pos ~= nil
  
  -- Cache result
  validatedCreatures[id] = { valid = valid, time = nowt }
  
  -- Cleanup old cache entries periodically
  if math.random(1, 50) == 1 then
    for cid, data in pairs(validatedCreatures) do
      if (nowt - data.time) > validatedCreaturesTTL * 10 then
        validatedCreatures[cid] = nil
      end
    end
  end
  
  return valid
end

-- Safely call a method on a creature, returning default if it fails
local function safeCreatureCall(creature, methodName, default)
  if not creature then return default end
  
  local ok, result = pcall(function()
    local method = creature[methodName]
    if not method then return nil end
    return method(creature)
  end)
  
  if ok then
    return result ~= nil and result or default
  else
    return default
  end
end

-- Safely get creature ID
local function safeGetId(creature)
  if not creature then return nil end
  local ok, id = pcall(function() return creature:getId() end)
  return ok and id or nil
end

-- Safely check if creature is dead
local function safeIsDead(creature)
  if not creature then return true end
  local ok, dead = pcall(function() return creature:isDead() end)
  return ok and dead or true
end

-- Safely check if creature is a monster
local function safeIsMonster(creature)
  if not creature then return false end
  local ok, monster = pcall(function() return creature:isMonster() end)
  return ok and monster or false
end

-- Safely check if creature is removed
local function safeIsRemoved(creature)
  if not creature then return true end
  local ok, removed = pcall(function() return creature:isRemoved() end)
  if not ok then return true end
  return removed or false
end

-- Combined safe check: is the creature a valid, alive monster?
local function isValidAliveMonster(creature)
  if not creature then return false end
  
  local ok, result = pcall(function()
    return creature:isMonster() and not creature:isDead() and not creature:isRemoved()
  end)
  
  return ok and result or false
end

-- ============================================================================
-- EXPORT HELPERS AS MODULE-LEVEL GLOBALS FOR OTHER MonsterAI FILES
-- These are used by monster_tracking, monster_prediction, etc.
-- ============================================================================

MonsterAI._helpers = {
  getClient = getClient,
  getClientVersion = getClientVersion,
  nowMs = nowMs,
  isCreatureValid = isCreatureValid,
  safeCreatureCall = safeCreatureCall,
  safeGetId = safeGetId,
  safeIsDead = safeIsDead,
  safeIsMonster = safeIsMonster,
  safeIsRemoved = safeIsRemoved,
  isValidAliveMonster = isValidAliveMonster,
}

-- ============================================================================
-- CONSTANTS (Shared across all subsystems)
-- ============================================================================

MonsterAI.CONSTANTS = {
  -- Behavior analysis window (in ms)
  ANALYSIS_WINDOW = 10000,
  SAMPLE_INTERVAL = 100,
  
  -- Prediction confidence thresholds
  CONFIDENCE = {
    VERY_HIGH = 0.85,
    HIGH = 0.70,
    MEDIUM = 0.50,
    LOW = 0.30,
    VERY_LOW = 0.15
  },
  
  -- Monster attack types
  ATTACK_TYPE = {
    MELEE = 1,
    TARGETED_SPELL = 2,
    WAVE_BEAM = 3,
    AREA_SPELL = 4,
    SUMMON = 5
  },
  
  -- Movement patterns
  MOVEMENT_PATTERN = {
    STATIC = 1,
    CHASE = 2,
    KITE = 3,
    ERRATIC = 4,
    PATROL = 5
  },
  
  -- Wave attack danger levels
  WAVE_DANGER = {
    NONE = 0,
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3,
    CRITICAL = 4
  },

  -- EWMA / learning tuning
  EWMA = {
    ALPHA_DEFAULT = 0.25,
    VARIANCE_PENALTY_SCALE = 0.28,
    VARIANCE_PENALTY_MAX = 0.45
  },

  -- Damage correlation tuning
  DAMAGE = {
    CORRELATION_RADIUS = 7,
    CORRELATION_THRESHOLD = 0.4
  },
  
  -- Event-driven thresholds
  EVENT_DRIVEN = {
    DIRECTION_CHANGE_COOLDOWN = 150,
    TURN_RATE_WINDOW = 2000,
    CONSECUTIVE_TURNS_ALERT = 2,
    IMMEDIATE_THREAT_WINDOW = 800,
    THREAT_CACHE_TTL = 100,
    ATTACK_PREDICTION_HORIZON = 2000,
    FACING_PLAYER_THRESHOLD = 0.6
  }
}

-- ============================================================================
-- CONFIGURATION FLAGS
-- ============================================================================

MonsterAI.COLLECT_EXTENDED = (MonsterAI.COLLECT_EXTENDED == nil) and true or MonsterAI.COLLECT_EXTENDED
MonsterAI.DPS_WINDOW = MonsterAI.DPS_WINDOW or 5000
MonsterAI.AUTO_TUNE_ENABLED = (MonsterAI.AUTO_TUNE_ENABLED == nil) and true or MonsterAI.AUTO_TUNE_ENABLED
MonsterAI.TELEMETRY_INTERVAL = MonsterAI.TELEMETRY_INTERVAL or 200
MonsterAI.COLLECT_ENABLED = (MonsterAI.COLLECT_ENABLED == nil) and true or MonsterAI.COLLECT_ENABLED
MonsterAI.DEBUG = MonsterAI.DEBUG or false

-- Export for external use
nExBot = nExBot or {}
nExBot.MonsterAI = MonsterAI

if MonsterAI.DEBUG then
  print("[MonsterAI] Core v" .. MonsterAI.VERSION .. " loaded")
end
