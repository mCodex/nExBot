--[[
  Z-Change Guard
  
  Frame-based burst detection for floor transitions.
  During z-changes, hundreds of creature events fire in a single frame.
  This module detects the burst and blocks expensive callbacks.
  
  Also handles tile-event burst detection for crowded areas.
  
  Extracted from event_bus.lua for SRP compliance.
]]

ZChangeGuard = {}

-- Z-change state
local _zBlocked = false
local _zCooldown = 150
local _zLastLog = 0
local _zLastKnown = nil
local _burstFrame = 0
local _burstCount = 0
local _zGen = 0

-- Tile-event burst state
local _tileBlocked = false
local _tileBurstFrame = 0
local _tileBurstCount = 0
local TILE_BURST_THRESHOLD = 12
local TILE_COOLDOWN_MS = 80

-- ═══════════════════════════════════════════════════════════════════
-- Z-CHANGE GUARD
-- ═══════════════════════════════════════════════════════════════════

--- Check if a z-change is in progress.
-- Ultra-fast guard: single boolean check.
-- @return boolean
function ZChangeGuard.isBlocked()
  return _zBlocked
end

--- Activate z-change block (idempotent).
-- Schedules automatic clear after cooldown.
local function activate()
  if _zBlocked then return end
  _zBlocked = true
  _zGen = _zGen + 1
  local myGen = _zGen
  schedule(_zCooldown, function()
    if _zGen ~= myGen then return end
    _zBlocked = false
    local ok, p = pcall(pos)
    if ok and p then _zLastKnown = p.z end
    EventBus.emit("player:z_change_settled")
  end)
  -- Safety valve: guarantee clear within 500ms
  schedule(500, function()
    if _zBlocked and _zGen == myGen then
      _zBlocked = false
      EventBus.emit("player:z_change_settled")
    end
  end)
end

--- Count creature events per frame. 5+ in same frame = floor transition.
-- @return boolean true if burst detected (caller should suppress)
function ZChangeGuard.checkBurst()
  if _zBlocked then return true end
  if now ~= _burstFrame then
    _burstFrame = now
    _burstCount = 1
  else
    _burstCount = _burstCount + 1
  end
  if _burstCount >= 5 then
    activate()
    return true
  end
  return false
end

--- Handle explicit z-change from position change event.
-- @param oldPos table {x, y, z}
-- @param newPos table {x, y, z}
function ZChangeGuard.onZChange(oldPos, newPos)
  if not newPos then return end
  _zLastKnown = newPos.z
  if (now - _zLastLog) >= 800 then
    _zLastLog = now
  end
  activate()
end

--- Get last known z level.
-- @return number|nil
function ZChangeGuard.getLastKnownZ()
  return _zLastKnown
end

-- Initialize last known z from player position
schedule(200, function()
  local ok, p = pcall(pos)
  if ok and p then _zLastKnown = p.z end
end)

-- ═══════════════════════════════════════════════════════════════════
-- TILE-EVENT BURST GUARD
-- ═══════════════════════════════════════════════════════════════════

--- Check if tile events are throttled.
-- @return boolean
function ZChangeGuard.isTileThrottled()
  return _tileBlocked
end

--- Count tile events per frame. 12+ in one tick = burst.
-- @return boolean true if burst detected (caller should suppress)
function ZChangeGuard.checkTileBurst()
  if _tileBlocked then return true end
  if now ~= _tileBurstFrame then
    _tileBurstFrame = now
    _tileBurstCount = 1
  else
    _tileBurstCount = _tileBurstCount + 1
  end
  if _tileBurstCount >= TILE_BURST_THRESHOLD then
    if not _tileBlocked then
      _tileBlocked = true
      schedule(TILE_COOLDOWN_MS, function()
        _tileBlocked = false
      end)
    end
    return true
  end
  return false
end

-- Export for global access
nExBot = nExBot or {}
nExBot.zChanging = ZChangeGuard.isBlocked
nExBot.tileThrottled = ZChangeGuard.isTileThrottled

-- Global aliases for backward compatibility
zChanging = ZChangeGuard.isBlocked
tileThrottled = ZChangeGuard.isTileThrottled

return ZChangeGuard
