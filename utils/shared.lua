--[[
  nExBot Shared Utilities
  
  Single source of truth for commonly used helper functions.
  Eliminates 40+ duplicate definitions across the codebase.
  
  Principles:
    - DRY: Every utility defined exactly once
    - SRP: Each function does one thing
    - KISS: Simple, pure functions where possible
  
  Usage:
    -- Already loaded globally by _Loader.lua
    nExBot.Shared.getClient()
    nExBot.Shared.getClientVersion()
    nExBot.Shared.nowMs()
    nExBot.Shared.deepClone(t)
]]

local Shared = {}

--------------------------------------------------------------------------------
-- CLIENT ACCESS (was duplicated in 20+ files)
--------------------------------------------------------------------------------

--- Get the ClientService reference for cross-client compatibility.
-- @return ClientService or nil
function Shared.getClient()
  return ClientService
end

--- Get the client version number (cached per session).
-- @return number (e.g. 1200)
local _cachedClientVersion = nil
function Shared.getClientVersion()
  if _cachedClientVersion then return _cachedClientVersion end
  local Client = Shared.getClient()
  if Client and Client.getClientVersion then
    _cachedClientVersion = Client.getClientVersion()
  else
    _cachedClientVersion = g_game and g_game.getClientVersion and g_game.getClientVersion() or 1200
  end
  return _cachedClientVersion
end

--- Check if client is old Tibia (pre-960).
-- @return boolean
function Shared.isOldTibia()
  return Shared.getClientVersion() < 960
end

--------------------------------------------------------------------------------
-- TIME (was duplicated in 5+ files)
--------------------------------------------------------------------------------

--- Get current time in milliseconds.
-- @return number
function Shared.nowMs()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

--------------------------------------------------------------------------------
-- TABLE UTILITIES (deepClone was duplicated in 4 files)
--------------------------------------------------------------------------------

--- Deep clone a table (recursive copy).
-- @param t any - value to clone
-- @return any - deep copy
function Shared.deepClone(t)
  if type(t) ~= "table" then return t end
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = Shared.deepClone(v)
  end
  return copy
end

--- Trim an array to max length (keep most recent entries).
-- @param arr table - array to trim
-- @param maxLen number - maximum length
function Shared.trimArray(arr, maxLen)
  if not arr or type(arr) ~= "table" then return end
  local excess = #arr - maxLen
  if excess <= 0 then return end
  -- Single-pass: shift retained elements to front, then nil-out tail
  for i = 1, maxLen do
    arr[i] = arr[i + excess]
  end
  for i = maxLen + 1, maxLen + excess do
    arr[i] = nil
  end
end

--- Capitalize the first letter of a string.
-- @param str string
-- @return string
function Shared.capitalizeFirst(str)
  if not str or #str == 0 then return str or "" end
  return str:sub(1, 1):upper() .. str:sub(2)
end

--- Capitalize each word in a string (proper case).
-- @param str string
-- @return string (no leading/trailing spaces)
function Shared.properCase(str)
  if not str or #str == 0 then return str or "" end
  local words = {}
  for word in str:gmatch("%S+") do
    words[#words + 1] = Shared.capitalizeFirst(word)
  end
  return table.concat(words, " ")
end

--------------------------------------------------------------------------------
-- COOLDOWN UTILITIES (shared healing/potion cooldown checks)
--------------------------------------------------------------------------------

--- Check if healing group cooldown is active.
-- @return boolean
function Shared.isHealingOnCooldown()
  if BotCore and BotCore.Cooldown and BotCore.Cooldown.isHealingOnCooldown then
    return BotCore.Cooldown.isHealingOnCooldown()
  end
  if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
    return modules.game_cooldown.isGroupCooldownIconActive(2)
  end
  return false
end

--- Check if potion exhaustion is active.
-- @return boolean
function Shared.isPotionOnCooldown()
  if BotCore and BotCore.Cooldown and BotCore.Cooldown.canUsePotion then
    return not BotCore.Cooldown.canUsePotion()
  end
  if nExBot and nExBot.isUsingPotion then return true end
  if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
    return modules.game_cooldown.isGroupCooldownIconActive(6)
  end
  return false
end

--------------------------------------------------------------------------------
-- PLAYER STAT ACCESSORS (used across heal modules)
--------------------------------------------------------------------------------

--- Get player HP percent safely.
-- @return number (0-100)
function Shared.getHpPercent()
  if hppercent then return hppercent() or 0 end
  if player and player.getHealthPercent then return player:getHealthPercent() or 0 end
  return 100
end

--- Get player MP percent safely.
-- @return number (0-100)
function Shared.getMpPercent()
  if manapercent then return manapercent() or 0 end
  if player and player.getManaPercent then return player:getManaPercent() or 0 end
  return 100
end

--- Get player current mana safely.
-- @return number
function Shared.getCurrentMana()
  if mana then return mana() or 0 end
  if player and player.getMana then return player:getMana() or 0 end
  return 0
end

--- Check if player is in protection zone.
-- @return boolean
function Shared.isInPz()
  if isInPz then return isInPz() end
  return false
end

--------------------------------------------------------------------------------
-- SEMVER UTILITIES (used by updater)
--------------------------------------------------------------------------------

--- Parse a semver string into {major, minor, patch}.
-- @param str string - e.g. "3.0.0"
-- @return table {major=number, minor=number, patch=number} or nil
function Shared.parseSemver(str)
  if not str or type(str) ~= "string" then return nil end
  str = str:match("^%s*(.-)%s*$") -- trim
  local major, minor, patch = str:match("^(%d+)%.(%d+)%.(%d+)")
  if not major then return nil end
  return {
    major = tonumber(major),
    minor = tonumber(minor),
    patch = tonumber(patch),
  }
end

--- Compare two semver tables. Returns 1 if a > b, -1 if a < b, 0 if equal.
-- @param a table {major, minor, patch}
-- @param b table {major, minor, patch}
-- @return number (-1, 0, 1)
function Shared.compareSemver(a, b)
  if not a or not b then return 0 end
  if a.major ~= b.major then return a.major > b.major and 1 or -1 end
  if a.minor ~= b.minor then return a.minor > b.minor and 1 or -1 end
  if a.patch ~= b.patch then return a.patch > b.patch and 1 or -1 end
  return 0
end

--- Format a semver table back to string.
-- @param v table {major, minor, patch}
-- @return string
function Shared.formatSemver(v)
  if not v then return "0.0.0" end
  return string.format("%d.%d.%d", v.major or 0, v.minor or 0, v.patch or 0)
end

-- Export globally
nExBot = nExBot or {}
nExBot.Shared = Shared

return Shared
