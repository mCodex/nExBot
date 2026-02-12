--[[
  nExBot Anti-Corruption Layer (ACL)
  
  This module provides a unified interface for multiple OTClient implementations:
  - OTCv8 (original implementation)
  - OpenTibiaBR/OTClient Redemption
  
  Design Principles Applied:
  - SOLID: Each component has a single responsibility
  - KISS: Simple detection and delegation
  - DRY: Shared logic in base interfaces
  - ACL Pattern: Isolates external client dependencies
  
  Usage:
    local Client = require("acl")
    Client.game.attack(creature)
    Client.player.getHealth()
]]

-- ACL Module
local ACL = {}

-- Version info
ACL.VERSION = "1.0.0"
ACL.NAME = "nExBot ACL"

-- Client type enum
ACL.ClientType = {
  UNKNOWN = 0,
  OTCV8 = 1,
  OPENTIBIABR = 2,
}

-- Current detected client
ACL.currentClient = ACL.ClientType.UNKNOWN
ACL.clientName = "Unknown"

-- Detection flags (cached for performance)
local _detected = false
local _clientType = ACL.ClientType.UNKNOWN

--------------------------------------------------------------------------------
-- CLIENT DETECTION
-- Detects which OTClient variant is running based on available APIs
--------------------------------------------------------------------------------

local function detectClient(force)
  if not force and _detected then
    return _clientType
  end

  if not force and nExBot and nExBot.clientDetection and nExBot.clientDetection.type then
    _clientType = nExBot.clientDetection.type
    ACL.clientName = nExBot.clientDetection.name or ACL.clientName
    ACL.currentClient = _clientType
    _detected = true
    return _clientType
  end

  -- ======================================================================
  -- FINGERPRINT 1: OTBR-only module files on disk (instant, always works)
  -- These modules ship exclusively with OpenTibiaBR/OTClient-Redemption
  -- and never exist in OTCv8.  g_resources.fileExists is available in the
  -- bot sandbox from the very first line of _Loader.lua.
  -- ======================================================================
  local fileFingerprintOTBR = false
  if g_resources and type(g_resources.fileExists) == "function" then
    -- Any ONE hit is sufficient; ordered by likelihood of presence
    local otbrOnlyPaths = {
      "/modules/game_cyclopedia/game_cyclopedia.otmod",
      "/modules/game_forge/game_forge.otmod",
      "/modules/game_attachedeffects/attachedeffects.otmod",
      "/modules/game_healthcircle/game_healthcircle.otmod",
      "/modules/game_wheel/game_wheel.otmod",
    }
    for i = 1, #otbrOnlyPaths do
      if g_resources.fileExists(otbrOnlyPaths[i]) then
        fileFingerprintOTBR = true
        break
      end
    end
  end

  -- ======================================================================
  -- FINGERPRINT 2: g_app branding strings
  -- OTBR sets org="otcr", name contains "Redemption"
  -- ======================================================================
  local appName = nil
  local appCompactName = nil
  local appOrgName = nil
  if g_app then
    if type(g_app.getName) == "function" then
      local ok, result = pcall(g_app.getName)
      if ok then appName = result end
    end
    if type(g_app.getCompactName) == "function" then
      local ok, result = pcall(g_app.getCompactName)
      if ok then appCompactName = result end
    end
    if type(g_app.getOrganizationName) == "function" then
      local ok, result = pcall(g_app.getOrganizationName)
      if ok then appOrgName = result end
    end
  end

  local appNameLower = type(appName) == "string" and appName:lower() or nil
  local appOrgLower = type(appOrgName) == "string" and appOrgName:lower() or nil

  local appFingerprintOTBR = false
  if appOrgLower == "otcr" or appOrgLower == "otbr" then
    appFingerprintOTBR = true
  elseif appNameLower and appNameLower:find("redemption") then
    appFingerprintOTBR = true
  end

  -- ======================================================================
  -- FINGERPRINT 3: OTBR-exclusive g_map / g_game APIs
  -- ======================================================================
  local apiFingerprintOTBR = false
  if g_map then
    if type(g_map.findEveryPath) == "function"
      or type(g_map.getSightSpectators) == "function"
      or type(g_map.getSpectatorsInRangeEx) == "function"
      or type(g_map.getTilesInRange) == "function" then
      apiFingerprintOTBR = true
    end
  end

  local signals = {
    fileFingerprintOTBR = fileFingerprintOTBR,
    appName = appName,
    appCompactName = appCompactName,
    appOrganizationName = appOrgName,
    appFingerprintOTBR = appFingerprintOTBR,
    apiFingerprintOTBR = apiFingerprintOTBR,
    forceWalk = (g_game and type(g_game.forceWalk) == "function") or false,
    moveRaw = (g_game and type(g_game.moveRaw) == "function") or false,
    g_gameConfig = (g_gameConfig ~= nil) or false,
  }

  -- Always log once so the user can report what the detection saw
  if not ACL._signalsPrinted then
    ACL._signalsPrinted = true
    local parts = {}
    for k, v in pairs(signals) do
      parts[#parts + 1] = k .. "=" .. tostring(v)
    end
    print("[ACL] Detection signals: " .. table.concat(parts, ", "))
  end

  -- ======================================================================
  -- DECISION: file fingerprint > app fingerprint > API fingerprint
  --           > legacy API probes > default OTCv8
  -- ======================================================================
  if signals.fileFingerprintOTBR then
    _clientType = ACL.ClientType.OPENTIBIABR
    ACL.clientName = "OpenTibiaBR"
  elseif signals.appFingerprintOTBR then
    _clientType = ACL.ClientType.OPENTIBIABR
    ACL.clientName = "OpenTibiaBR"
  elseif signals.apiFingerprintOTBR then
    _clientType = ACL.ClientType.OPENTIBIABR
    ACL.clientName = "OpenTibiaBR"
  elseif signals.forceWalk then
    _clientType = ACL.ClientType.OPENTIBIABR
    ACL.clientName = "OpenTibiaBR"
  elseif signals.moveRaw then
    _clientType = ACL.ClientType.OTCV8
    ACL.clientName = "OTCv8"
  elseif signals.g_gameConfig then
    _clientType = ACL.ClientType.OPENTIBIABR
    ACL.clientName = "OpenTibiaBR"
  else
    _clientType = ACL.ClientType.OTCV8
    ACL.clientName = "OTCv8"
  end

  _detected = true
  ACL.currentClient = _clientType
  ACL.lastDetection = {
    type = _clientType,
    name = ACL.clientName,
    signals = signals
  }

  if nExBot then
    nExBot.clientDetection = ACL.lastDetection
  end

  return _clientType
end

-- Public detection function
function ACL.getClientType()
  return detectClient()
end

function ACL.getClientName()
  detectClient()
  return ACL.clientName
end

function ACL.isOTCv8()
  return detectClient() == ACL.ClientType.OTCV8
end

function ACL.isOpenTibiaBR()
  return detectClient() == ACL.ClientType.OPENTIBIABR
end

function ACL.refreshDetection()
  _detected = false
  return detectClient(true)
end

function ACL.getDetectionInfo()
  detectClient()
  return ACL.lastDetection
end

--------------------------------------------------------------------------------
-- ADAPTER LOADING
-- Loads the appropriate adapter based on detected client
--------------------------------------------------------------------------------

local adapters = {}
local adapterLoaded = false
local _lateDetectionQueued = false
local _lateDetectionDone = false

local function loadAdapter()
  if adapterLoaded then
    return adapters
  end
  
  local clientType = detectClient()
  local adapterPath
  
  if clientType == ACL.ClientType.OPENTIBIABR then
    adapterPath = "acl/adapters/opentibiabr"
  else
    -- Default to OTCv8 adapter
    adapterPath = "acl/adapters/otcv8"
  end
  
  -- Load adapter modules
  local status, result = pcall(function()
    return dofile("/core/" .. adapterPath .. ".lua")
  end)
  
  if status and result then
    adapters = result
  else
    warn("[ACL] Failed to load adapter: " .. adapterPath .. " (" .. tostring(result) .. ")")
    -- Return base adapter with noop functions
    local baseOk, baseResult = pcall(function()
      return dofile("/core/acl/adapters/base.lua")
    end)
    if baseOk and baseResult then
      adapters = baseResult
    else
      adapters = {}
    end
  end
  
  adapterLoaded = true
  return adapters
end

--------------------------------------------------------------------------------
-- PUBLIC INTERFACE
-- Unified API that delegates to the appropriate adapter
--------------------------------------------------------------------------------

-- Lazy-load adapters on first access (with recursion guard)
local _adapterLookupActive = false
setmetatable(ACL, {
  __index = function(t, key)
    -- Prevent infinite recursion: if we're already inside loadAdapter,
    -- don't try to load again
    if _adapterLookupActive then return nil end
    _adapterLookupActive = true
    local ok, adapter = pcall(loadAdapter)
    _adapterLookupActive = false
    if ok and adapter and adapter[key] then
      rawset(t, key, adapter[key])
      return adapter[key]
    end
    return nil
  end
})

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function ACL.init()
  local clientType = detectClient()
  
  if nExBot and nExBot.showDebug then
    print("[ACL] Detected client: " .. ACL.clientName)
    print("[ACL] Client type: " .. tostring(clientType))
  end
  
  -- Pre-load adapters
  loadAdapter()

  if not _lateDetectionQueued then
    _lateDetectionQueued = true
    local function lateRefresh(reason)
      if _lateDetectionDone then return end
      _lateDetectionDone = true
      local previousType = _clientType
      local newType = detectClient(true)
      if nExBot and nExBot.showDebug and newType ~= previousType then
        print("[ACL] Late detection updated via " .. tostring(reason) .. ": " .. ACL.clientName)
      end
    end

    if type(schedule) == "function" then
      schedule(1500, function() lateRefresh("delay") end)
    end

    if type(connect) == "function" and g_game then
      connect(g_game, {
        onGameStart = function()
          if type(schedule) == "function" then
            schedule(100, function() lateRefresh("onGameStart") end)
          else
            lateRefresh("onGameStart")
          end
        end
      })
    end
  end
  
  return true
end

-- Auto-detect on load
detectClient()

return ACL
