--[[
  BotCore: Stats Manager
  
  Single source of truth for player stats with memoization.
  Updates once per tick, provides pure getter functions.
  
  Principles: SRP, Memoization, Pure Functions
]]

local StatsManager = {}

-- Private state
local _cache = {
  hp = 0,
  maxHp = 0,
  hpPercent = 0,
  mp = 0,
  maxMp = 0,
  mpPercent = 0,
  burst = 0,
  level = 0,
  soul = 0,
  stamina = 0,
  speed = 0,
  lastUpdate = 0
}

-- Cached player reference (avoid repeated lookups)
local _cachedPlayer = nil
local _lastPlayerCheck = 0
local PLAYER_CHECK_INTERVAL = 1000  -- Revalidate every 1s

-- ============================================================================
-- PRIVATE FUNCTIONS
-- ============================================================================

-- Get cached local player (with periodic revalidation)
local function getLocalPlayerCached()
  local currentTime = now or os.time() * 1000
  if not _cachedPlayer or (currentTime - _lastPlayerCheck) > PLAYER_CHECK_INTERVAL then
    _cachedPlayer = g_game.getLocalPlayer()
    _lastPlayerCheck = currentTime
  end
  return _cachedPlayer
end

-- Calculate percentage safely (pure function)
local function safePercent(current, max)
  if not max or max <= 0 then return 0 end
  return math.floor((current / max) * 100)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Update all stats once per tick (call from main loop)
function StatsManager.update()
  local currentTime = now or os.time() * 1000
  
  -- Skip if already updated this tick
  if currentTime == _cache.lastUpdate then
    return _cache
  end
  
  local localPlayer = getLocalPlayerCached()
  if not localPlayer then return _cache end
  
  -- Batch read all stats
  local hp = localPlayer:getHealth() or 0
  local maxHp = localPlayer:getMaxHealth() or 1
  local mp = localPlayer:getMana() or 0
  local maxMp = localPlayer:getMaxMana() or 1
  
  -- Only update if values changed (reduce memory writes)
  if _cache.hp ~= hp or _cache.maxHp ~= maxHp then
    _cache.hp = hp
    _cache.maxHp = maxHp
    _cache.hpPercent = safePercent(hp, maxHp)
  end
  
  if _cache.mp ~= mp or _cache.maxMp ~= maxMp then
    _cache.mp = mp
    _cache.maxMp = maxMp
    _cache.mpPercent = safePercent(mp, maxMp)
  end
  
  -- Optional stats (less frequently needed)
  _cache.level = localPlayer:getLevel() or 0
  _cache.soul = localPlayer:getSoul() or 0
  _cache.stamina = localPlayer:getStamina() or 0
  _cache.speed = localPlayer:getSpeed() or 0
  
  -- Burst damage (if available)
  if burstDamageValue then
    _cache.burst = burstDamageValue() or 0
  end
  
  _cache.lastUpdate = currentTime
  return _cache
end

-- ============================================================================
-- PURE GETTERS (no side effects, read from cache)
-- ============================================================================

function StatsManager.getHp() return _cache.hp end
function StatsManager.getMaxHp() return _cache.maxHp end
function StatsManager.getHpPercent() return _cache.hpPercent end

function StatsManager.getMp() return _cache.mp end
function StatsManager.getMaxMp() return _cache.maxMp end
function StatsManager.getMpPercent() return _cache.mpPercent end

function StatsManager.getBurst() return _cache.burst end
function StatsManager.getLevel() return _cache.level end
function StatsManager.getSoul() return _cache.soul end
function StatsManager.getStamina() return _cache.stamina end
function StatsManager.getSpeed() return _cache.speed end

-- Get full cache (for condition checking)
function StatsManager.getAll()
  return _cache
end

-- Get stat by name (for dynamic condition checking)
function StatsManager.get(statName)
  if statName == "HP%" then return _cache.hpPercent end
  if statName == "HP" then return _cache.hp end
  if statName == "MP%" then return _cache.mpPercent end
  if statName == "MP" then return _cache.mp end
  if statName == "burst" then return _cache.burst end
  if statName == "level" then return _cache.level end
  if statName == "soul" then return _cache.soul end
  return nil
end

-- Check if cache is fresh (within given ms)
function StatsManager.isFresh(maxAgeMs)
  maxAgeMs = maxAgeMs or 100
  local currentTime = now or os.time() * 1000
  return (currentTime - _cache.lastUpdate) <= maxAgeMs
end

-- Force invalidate cache (for event-driven updates)
function StatsManager.invalidate()
  _cache.lastUpdate = 0
end

-- Direct update from event (faster than polling)
function StatsManager.setHealth(hp, maxHp)
  _cache.hp = hp
  _cache.maxHp = maxHp
  _cache.hpPercent = safePercent(hp, maxHp)
  _cache.lastUpdate = now or os.time() * 1000
end

function StatsManager.setMana(mp, maxMp)
  _cache.mp = mp
  _cache.maxMp = maxMp
  _cache.mpPercent = safePercent(mp, maxMp)
  _cache.lastUpdate = now or os.time() * 1000
end

-- Export for global access
BotCore = BotCore or {}
BotCore.Stats = StatsManager

return StatsManager
