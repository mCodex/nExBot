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

local function detectClient()
  if _detected then
    return _clientType
  end
  
  -- Detection heuristics based on unique features
  
  -- Check for OpenTibiaBR specific features
  local isOpenTibiaBR = false
  local isOTCv8 = false
  
  -- OpenTibiaBR has g_gameConfig, paperdoll support, and protobuf
  if g_gameConfig ~= nil then
    isOpenTibiaBR = true
  end
  
  -- OpenTibiaBR uses Controller:new() pattern in modules
  if Controller ~= nil and type(Controller.new) == "function" then
    isOpenTibiaBR = true
  end
  
  -- OpenTibiaBR has g_paperdolls
  if g_paperdolls ~= nil then
    isOpenTibiaBR = true
  end
  
  -- OTCv8 has specific bot module structure
  if modules and modules.game_bot then
    local botModule = modules.game_bot
    -- OTCv8 uses contentsPanel.config pattern
    if botModule.contentsPanel and botModule.contentsPanel.config then
      isOTCv8 = true
    end
  end
  
  -- OTCv8 has g_creatures.getCreatures as a common pattern
  if g_creatures and type(g_creatures.getCreatures) == "function" then
    -- Both have this, but OTCv8 doesn't have g_gameConfig
    if not g_gameConfig then
      isOTCv8 = true
    end
  end
  
  -- Check for moveRaw which is OTCv8 specific
  if g_game and type(g_game.moveRaw) == "function" then
    isOTCv8 = true
  end
  
  -- Final decision
  if isOpenTibiaBR and not isOTCv8 then
    _clientType = ACL.ClientType.OPENTIBIABR
    ACL.clientName = "OpenTibiaBR"
  elseif isOTCv8 then
    _clientType = ACL.ClientType.OTCV8
    ACL.clientName = "OTCv8"
  else
    -- Default fallback based on common features
    if g_game and g_map and g_ui then
      -- Try to detect based on forceWalk (OpenTibiaBR has it, OTCv8 doesn't)
      if type(g_game.forceWalk) == "function" then
        _clientType = ACL.ClientType.OPENTIBIABR
        ACL.clientName = "OpenTibiaBR"
      else
        _clientType = ACL.ClientType.OTCV8
        ACL.clientName = "OTCv8"
      end
    end
  end
  
  _detected = true
  ACL.currentClient = _clientType
  
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

--------------------------------------------------------------------------------
-- ADAPTER LOADING
-- Loads the appropriate adapter based on detected client
--------------------------------------------------------------------------------

local adapters = {}
local adapterLoaded = false

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
    warn("[ACL] Failed to load adapter: " .. adapterPath)
    -- Return base adapter with noop functions
    adapters = require("acl/adapters/base")
  end
  
  adapterLoaded = true
  return adapters
end

--------------------------------------------------------------------------------
-- PUBLIC INTERFACE
-- Unified API that delegates to the appropriate adapter
--------------------------------------------------------------------------------

-- Lazy-load adapters on first access
setmetatable(ACL, {
  __index = function(t, key)
    local adapter = loadAdapter()
    if adapter[key] then
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
  
  return true
end

-- Auto-detect on load
detectClient()

return ACL
