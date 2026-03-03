-- Cooldown Manager: Unified spell cooldown state tracking
-- Purpose: Replace dual-track spell/rune cooldown system with single, reliable tracker
-- Architecture: Per-spell state machine with next-cast-time snapshots

---@class CooldownManager
---@field spellRegistry SpellRegistry Reference to spell definitions
---@field cooldownState {[string]: {lastCastTime: number, nextCastTime: number}} Per-spell state

local CooldownManager = {}

-- ============================================================================
-- Cooldown State Machine
-- ============================================================================

---Initialize cooldown manager with spell registry
---@param spellRegistry SpellRegistry
---@return CooldownManager
function CooldownManager:new(spellRegistry)
  local instance = {
    spellRegistry = spellRegistry,
    cooldownState = {}, -- {[spellName]: {lastCastTime, nextCastTime, consecutiveFailures}}
    debugLogging = false,
  }
  
  -- Initialize state for all registered spells
  for spell, spellName in spellRegistry:iterate() do
    instance.cooldownState[spellName] = {
      lastCastTime = 0,
      nextCastTime = 0,
      consecutiveFailures = 0,
      lastFailTime = 0,
    }
  end
  
  setmetatable(instance, self)
  self.__index = self
  
  return instance
end

-- ============================================================================
-- Core API: Readiness Checks
-- ============================================================================

---Check if spell is off cooldown and ready to cast
---@param spellName string
---@return boolean
function CooldownManager:isReady(spellName)
  local state = self.cooldownState[spellName]
  if not state then
    return false
  end
  
  local now = g_clock.millis()
  return now >= state.nextCastTime
end

---Get remaining cooldown in milliseconds (0 if ready)
---@param spellName string
---@return number Milliseconds remaining, or 0 if ready
function CooldownManager:getRemainingCooldown(spellName)
  local state = self.cooldownState[spellName]
  if not state then
    return 0
  end
  
  local now = g_clock.millis()
  local remaining = state.nextCastTime - now
  
  return math.max(0, remaining)
end

---Get planned next cast time as absolute timestamp
---@param spellName string
---@return number Absolute millisecond timestamp
function CooldownManager:getNextCastTime(spellName)
  local state = self.cooldownState[spellName]
  if not state then
    return 0
  end
  
  return state.nextCastTime
end

---Get last successful cast time
---@param spellName string
---@return number Absolute timestamp, or 0 if never cast
function CooldownManager:getLastCastTime(spellName)
  local state = self.cooldownState[spellName]
  if not state then
    return 0
  end
  
  return state.lastCastTime
end

---Get time since last cast in milliseconds
---@param spellName string
---@return number Milliseconds since last cast
function CooldownManager:getTimeSinceLastCast(spellName)
  local lastCast = self:getLastCastTime(spellName)
  if lastCast == 0 then
    return math.huge -- Never cast
  end
  
  return g_clock.millis() - lastCast
end

-- ============================================================================
-- Cast Recording: Success vs Failure
-- ============================================================================

---Mark spell as successfully cast
---Starts cooldown countdown based on spell's cooldownMs
---@param spellName string
---@param overrideCooldownMs number|nil Override spell's cooldown (for variable duration)
function CooldownManager:markCastSuccess(spellName, overrideCooldownMs)
  local spell = self.spellRegistry:get(spellName)
  if not spell then
    return
  end
  
  local now = g_clock.millis()
  local cooldownMs = overrideCooldownMs or spell.cooldownMs
  
  self.cooldownState[spellName] = {
    lastCastTime = now,
    nextCastTime = now + cooldownMs,
    consecutiveFailures = 0,
    lastFailTime = 0,
  }
  
  if self.debugLogging then
    logger:debug(("[COOLDOWN] %s cast (cooldown: %dms, ready at: +%dms)"):format(
      spellName, cooldownMs, cooldownMs))
  end
end

---Mark spell cast as failed (invalid target, blocked, etc.)
---Applies exponential backoff: 1st fail = 500ms, 2nd = 1s, 3rd = 2s, 4th+ = 4s
---Resets on successful cast or after timeout
---@param spellName string
---@param backoffMs number|nil Override backoff duration (default: exponential)
function CooldownManager:markCastFailure(spellName, backoffMs)
  local state = self.cooldownState[spellName]
  if not state then
    return
  end
  
  local now = g_clock.millis()
  
  -- Track consecutive failures
  if now - state.lastFailTime > 5000 then
    -- Reset failure count if >5s passed since last failure
    state.consecutiveFailures = 0
  end
  
  state.consecutiveFailures = state.consecutiveFailures + 1
  state.lastFailTime = now
  
  -- Exponential backoff: 500ms, 1s, 2s, 4s, 4s, 4s, ...
  local baseFailureBackoff = 500
  local failureBackoff = math.min(4000, baseFailureBackoff * math.pow(2, state.consecutiveFailures - 1))
  
  backoffMs = backoffMs or failureBackoff
  
  state.nextCastTime = now + backoffMs
  
  if self.debugLogging then
    logger:debug(("[COOLDOWN] %s failed (backoff: %dms, failures: %d)"):format(
      spellName, backoffMs, state.consecutiveFailures))
  end
end

-- ============================================================================
-- Cooldown Reset and Configuration
-- ============================================================================

---Manually reset cooldown for a spell (e.g., after server-side proc)
---@param spellName string
function CooldownManager:resetCooldown(spellName)
  local state = self.cooldownState[spellName]
  if state then
    state.nextCastTime = 0
    state.consecutiveFailures = 0
    
    if self.debugLogging then
      logger:debug(("[COOLDOWN] %s cooldown reset"):format(spellName))
    end
  end
end

---Manually set cooldown duration for a spell
---Overrides spell registry's cooldownMs (useful for dynamic tuning)
---@param spellName string
---@param newCooldownMs number
function CooldownManager:setCooldown(spellName, newCooldownMs)
  local spell = self.spellRegistry:get(spellName)
  if not spell then
    return
  end
  
  -- Create modified copy of spell with new cooldown
  local modified = {}
  for k, v in pairs(spell) do
    modified[k] = v
  end
  modified.cooldownMs = newCooldownMs
  
  -- Update registry (this is a hack; proper way is to re-register, but this is simpler)
  self.spellRegistry._spells[spellName] = modified
  
  if self.debugLogging then
    logger:debug(("[COOLDOWN] %s cooldown updated: %dms"):format(spellName, newCooldownMs))
  end
end

---Reset all cooldowns
function CooldownManager:resetAll()
  for spellName in pairs(self.cooldownState) do
    self:resetCooldown(spellName)
  end
  
  if self.debugLogging then
    logger:debug("[COOLDOWN] All cooldowns reset")
  end
end

-- ============================================================================
-- Statistics and Debugging
-- ============================================================================

---Get stats for a single spell
---@param spellName string
---@return table {ready: bool, remaining: number, lastCast: number, failures: number}
function CooldownManager:getStats(spellName)
  local state = self.cooldownState[spellName]
  if not state then
    return nil
  end
  
  return {
    spellName = spellName,
    ready = self:isReady(spellName),
    remainingMs = self:getRemainingCooldown(spellName),
    lastCastTime = state.lastCastTime,
    timeSinceLastCastMs = self:getTimeSinceLastCast(spellName),
    nextCastTime = state.nextCastTime,
    consecutiveFailures = state.consecutiveFailures,
  }
end

---Get stats for all spells
---@return table {spellName: {ready, remaining, lastCast, failures}}
function CooldownManager:getAllStats()
  local stats = {}
  
  for spellName in pairs(self.cooldownState) do
    stats[spellName] = self:getStats(spellName)
  end
  
  return stats
end

---Print cooldown summary to logger
---Shows spells ready, on cooldown, and failure backoff
function CooldownManager:printSummary()
  local stats = self:getAllStats()
  
  local ready = {}
  local onCooldown = {}
  local onFailureBackoff = {}
  
  for spellName, stat in pairs(stats) do
    if stat.ready then
      table.insert(ready, spellName)
    elseif stat.consecutiveFailures > 0 then
      table.insert(onFailureBackoff, spellName .. "/" .. stat.consecutiveFailures .. "f")
    else
      table.insert(onCooldown, spellName .. "/" .. math.ceil(stat.remainingMs / 100) / 10 .. "s")
    end
  end
  
  table.sort(ready)
  table.sort(onCooldown)
  table.sort(onFailureBackoff)
  
  logger:info(("[COOLDOWN STATUS]"))
  logger:info(("  Ready: %s"):format(#ready > 0 and table.concat(ready, ", ") or "(none)"))
  logger:info(("  Cooldown: %s"):format(#onCooldown > 0 and table.concat(onCooldown, ", ") or "(none)"))
  logger:info(("  Failure backoff: %s"):format(#onFailureBackoff > 0 and table.concat(onFailureBackoff, ", ") or "(none)"))
end

---Enable/disable debug logging
---@param enabled boolean
function CooldownManager:setDebugLogging(enabled)
  self.debugLogging = enabled
end

-- ============================================================================
-- Cooldown Validation Hook (for external persistence)
-- ============================================================================

---Get cooldown state for serialization to storage
---@return table Serializable state snapshot
function CooldownManager:getSerializableState()
  return {
    version = 1,
    timestamp = g_clock.millis(),
    cooldownState = self.cooldownState,
  }
end

---Load cooldown state from storage
---Useful for resuming cooldowns after restart
---@param serialized table Previously saved state
function CooldownManager:restoreFromState(serialized)
  if serialized.version == 1 then
    self.cooldownState = serialized.cooldownState or {}
  end
end

return CooldownManager
