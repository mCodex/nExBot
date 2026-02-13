--[[
  nExBot ACL — Init v2.0

  Client detection + adapter loading.
  Changes from v1.0:
  - Calls Interfaces.validateAll() after adapter load (runtime enforcement)
  - Cleaner detection: scored signal table instead of if/elseif chain
  - Removed recursive __index lazy-load (fragile) — explicit loadAdapter()
  - Late re-detection via onGameStart still supported
]]

local ACL = {}

ACL.VERSION  = "2.0.0"
ACL.NAME     = "nExBot ACL"

ACL.ClientType = {
  UNKNOWN      = 0,
  OTCV8        = 1,
  OPENTIBIABR  = 2,
}

ACL.currentClient = ACL.ClientType.UNKNOWN
ACL.clientName    = "Unknown"

-- =========================================================================
-- DETECTION (scored signal table)
-- =========================================================================

local _detected   = false
local _clientType = ACL.ClientType.UNKNOWN

local function detectClient(force)
  if not force and _detected then return _clientType end

  -- Cached from a previous boot
  if not force and nExBot and nExBot.clientDetection and nExBot.clientDetection.type then
    _clientType     = nExBot.clientDetection.type
    ACL.clientName  = nExBot.clientDetection.name or ACL.clientName
    ACL.currentClient = _clientType
    _detected = true
    return _clientType
  end

  -- ---- Gather signals ----
  local signals = {}

  -- Disk fingerprint (most reliable)
  if g_resources and type(g_resources.fileExists) == "function" then
    local otbrPaths = {
      "/modules/game_cyclopedia/game_cyclopedia.otmod",
      "/modules/game_forge/game_forge.otmod",
      "/modules/game_attachedeffects/attachedeffects.otmod",
      "/modules/game_healthcircle/game_healthcircle.otmod",
      "/modules/game_wheel/game_wheel.otmod",
    }
    for i = 1, #otbrPaths do
      if g_resources.fileExists(otbrPaths[i]) then
        signals.file = "otbr"; break
      end
    end
  end

  -- App branding
  if g_app then
    local ok, n = pcall(g_app.getName)
    if ok and type(n) == "string" and n:lower():find("redemption") then
      signals.app = "otbr"
    end
    local ok2, o = pcall(g_app.getOrganizationName)
    if ok2 and type(o) == "string" then
      local low = o:lower()
      if low == "otcr" or low == "otbr" then signals.app = "otbr" end
    end
  end

  -- API fingerprints
  if g_game then
    if type(g_game.moveRaw) == "function"  then signals.moveRaw   = true end
    if type(g_game.forceWalk) == "function" then signals.forceWalk = true end
  end
  if g_gameConfig ~= nil then signals.gameConfig = true end
  if g_map then
    if type(g_map.findEveryPath) == "function"
      or type(g_map.getSpectatorsInRangeEx) == "function" then
      signals.mapApi = "otbr"
    end
  end

  -- ---- Decide (priority order) ----
  if signals.file == "otbr"    then _clientType = ACL.ClientType.OPENTIBIABR; ACL.clientName = "OpenTibiaBR"
  elseif signals.app == "otbr" then _clientType = ACL.ClientType.OPENTIBIABR; ACL.clientName = "OpenTibiaBR"
  elseif signals.moveRaw       then _clientType = ACL.ClientType.OTCV8;       ACL.clientName = "OTCv8"
  elseif signals.forceWalk     then _clientType = ACL.ClientType.OPENTIBIABR; ACL.clientName = "OpenTibiaBR"
  elseif signals.gameConfig    then _clientType = ACL.ClientType.OPENTIBIABR; ACL.clientName = "OpenTibiaBR"
  elseif signals.mapApi == "otbr" then _clientType = ACL.ClientType.OPENTIBIABR; ACL.clientName = "OpenTibiaBR"
  else                              _clientType = ACL.ClientType.OTCV8;       ACL.clientName = "OTCv8"
  end

  _detected        = true
  ACL.currentClient = _clientType
  ACL.lastDetection = { type = _clientType, name = ACL.clientName, signals = signals }
  if nExBot then nExBot.clientDetection = ACL.lastDetection end

  if not ACL._signalsPrinted then
    ACL._signalsPrinted = true
    local parts = {}
    for k, v in pairs(signals) do parts[#parts + 1] = k .. "=" .. tostring(v) end
    print("[ACL] Detection: " .. ACL.clientName .. " | " .. table.concat(parts, ", "))
  end

  return _clientType
end

-- =========================================================================
-- PUBLIC DETECTION API
-- =========================================================================

function ACL.getClientType()           return detectClient() end
function ACL.getClientName()           detectClient(); return ACL.clientName end
function ACL.isOTCv8()                 return detectClient() == ACL.ClientType.OTCV8 end
function ACL.isOpenTibiaBR()           return detectClient() == ACL.ClientType.OPENTIBIABR end
function ACL.refreshDetection()        _detected = false; return detectClient(true) end
function ACL.getDetectionInfo()        detectClient(); return ACL.lastDetection end

-- =========================================================================
-- ADAPTER LOADING
-- =========================================================================

local adapter       = nil
local adapterLoaded = false

local function loadAdapter()
  if adapterLoaded then return adapter end

  local clientType = detectClient()
  local path = (clientType == ACL.ClientType.OPENTIBIABR)
    and "acl/adapters/opentibiabr"
    or  "acl/adapters/otcv8"

  -- Load base first (sets global ACL_BaseAdapter)
  pcall(dofile, "/core/acl/adapters/base.lua")

  -- Load specific adapter
  local ok, result = pcall(dofile, "/core/" .. path .. ".lua")
  if ok and type(result) == "table" then
    adapter = result
  elseif ACL_LoadedAdapter then
    adapter = ACL_LoadedAdapter
    ACL_LoadedAdapter = nil
  else
    warn("[ACL] Adapter load failed (" .. path .. "): " .. tostring(result))
    adapter = ACL_BaseAdapter or {}
  end

  adapterLoaded = true

  -- Runtime interface validation (non-fatal — warns on missing methods)
  local ifOk, ifResult = pcall(function()
    return dofile("/core/acl/interfaces.lua")
  end)
  if ifOk and ifResult and ifResult.validateAll then
    local allOk, reports = ifResult.validateAll(adapter)
    if not allOk then
      for iface, r in pairs(reports) do
        if not r.ok and r.report and r.report.missing then
          local m = r.report.missing
          if #m > 0 and m[1] ~= "(domain missing)" then
            print("[ACL] " .. iface .. " missing: " .. table.concat(m, ", "))
          end
        end
      end
    end
  end

  return adapter
end

-- =========================================================================
-- LAZY ACCESS — metatabled so ACL.game / ACL.map / etc resolve to adapter
-- =========================================================================

setmetatable(ACL, {
  __index = function(t, key)
    if not adapterLoaded then loadAdapter() end
    if adapter and adapter[key] ~= nil then
      rawset(t, key, adapter[key])   -- cache for next access
      return adapter[key]
    end
    return nil
  end,
})

-- =========================================================================
-- INIT (called by _Loader.lua)
-- =========================================================================

local _lateDetectionDone = false

function ACL.init()
  detectClient()
  loadAdapter()

  -- Late re-detection after game start (catches edge cases)
  if not _lateDetectionDone then
    local function lateRefresh(reason)
      if _lateDetectionDone then return end
      _lateDetectionDone = true
      local prev = _clientType
      local new  = detectClient(true)
      if new ~= prev and nExBot and nExBot.showDebug then
        print("[ACL] Late detection via " .. tostring(reason) .. ": " .. ACL.clientName)
      end
    end
    if type(schedule) == "function" then
      schedule(1500, function() lateRefresh("delay") end)
    end
    if type(connect) == "function" and g_game then
      pcall(connect, g_game, {
        onGameStart = function()
          if type(schedule) == "function" then
            schedule(100, function() lateRefresh("onGameStart") end)
          else lateRefresh("onGameStart") end
        end,
      })
    end
  end

  return true
end

-- Auto-detect on load
detectClient()

return ACL
