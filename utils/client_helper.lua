--[[
  ClientHelper - Unified Client Abstraction
  
  Consolidates the 10+ duplicate getClient(), getClientVersion(), getLocalPlayer()
  implementations scattered across the codebase.
  
  DESIGN:
  - Single source of truth for client access
  - Cross-client compatibility (OTCv8, OpenTibiaBR)
  - Cached player reference with auto-refresh
  - All module-local getClient() functions should be replaced with:
    local ClientHelper = dofile("utils/client_helper.lua")
  
  PERFORMANCE:
  - Player reference cached and refreshed on login
  - Client service reference cached at load time
  - Version cached after first call
]]

local ClientHelper = {}

-- Cached references
local _clientService = nil
local _cachedVersion = nil
local _cachedPlayer = nil
local _lastPlayerCheck = 0
local PLAYER_CACHE_TTL = 100  -- Refresh player reference every 100ms

--[[
  Get current time in milliseconds
  Consolidates 12+ duplicate nowMs() implementations across the codebase
  @return number milliseconds
]]
function ClientHelper.nowMs()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

--[[
  Get ClientService reference
  @return ClientService or nil
]]
function ClientHelper.getClient()
  if _clientService then return _clientService end
  _clientService = ClientService
  return _clientService
end

--[[
  Get g_game reference (cross-client)
  @return g_game table
]]
function ClientHelper.getGame()
  local Client = ClientHelper.getClient()
  return (Client and Client.g_game) or g_game
end

--[[
  Get g_map reference (cross-client)
  @return g_map table
]]
function ClientHelper.getMap()
  local Client = ClientHelper.getClient()
  return (Client and Client.g_map) or g_map
end

--[[
  Get local player with caching
  @return Player object or nil
]]
function ClientHelper.getLocalPlayer()
  -- Check cache validity
  local nowTime = now or os.time() * 1000
  if _cachedPlayer and (nowTime - _lastPlayerCheck) < PLAYER_CACHE_TTL then
    -- Validate cached player is still valid
    local ok, valid = pcall(function()
      return _cachedPlayer:getId() ~= nil
    end)
    if ok and valid then
      return _cachedPlayer
    end
  end
  
  -- Refresh player reference
  local Client = ClientHelper.getClient()
  local player = nil
  
  if Client and Client.getLocalPlayer then
    player = Client.getLocalPlayer()
  elseif g_game and g_game.getLocalPlayer then
    player = g_game.getLocalPlayer()
  end
  
  _cachedPlayer = player
  _lastPlayerCheck = nowTime
  return player
end

--[[
  Get player position
  @return Position or nil
]]
function ClientHelper.getPlayerPosition()
  local player = ClientHelper.getLocalPlayer()
  if not player then return nil end
  
  local ok, pos = pcall(function()
    return player:getPosition()
  end)
  return ok and pos or nil
end

--[[
  Get client version number
  @return number (e.g., 1200)
]]
function ClientHelper.getClientVersion()
  if _cachedVersion then return _cachedVersion end
  
  local Client = ClientHelper.getClient()
  local version = 1200  -- Default fallback
  
  if Client and Client.getClientVersion then
    version = Client.getClientVersion()
  elseif g_game and g_game.getClientVersion then
    version = g_game.getClientVersion()
  end
  
  _cachedVersion = version
  return version
end

--[[
  Get protocol version
  @return number
]]
function ClientHelper.getProtocolVersion()
  local Client = ClientHelper.getClient()
  if Client and Client.getProtocolVersion then
    return Client.getProtocolVersion()
  elseif g_game and g_game.getProtocolVersion then
    return g_game.getProtocolVersion()
  end
  return 1200
end

--[[
  Check if player is online
  @return boolean
]]
function ClientHelper.isOnline()
  local game = ClientHelper.getGame()
  if game and game.isOnline then
    return game.isOnline()
  end
  return ClientHelper.getLocalPlayer() ~= nil
end

--[[
  Attack a creature
  @param creature Creature to attack
  @return boolean success
]]
function ClientHelper.attack(creature)
  if not creature then return false end
  
  local Client = ClientHelper.getClient()
  if Client and Client.attack then
    Client.attack(creature)
    return true
  elseif g_game and g_game.attack then
    g_game.attack(creature)
    return true
  end
  return false
end

--[[
  Follow a creature
  @param creature Creature to follow
  @return boolean success
]]
function ClientHelper.follow(creature)
  if not creature then return false end
  
  local Client = ClientHelper.getClient()
  if Client and Client.follow then
    Client.follow(creature)
    return true
  elseif g_game and g_game.follow then
    g_game.follow(creature)
    return true
  end
  return false
end

--[[
  Get attacked creature
  @return Creature or nil
]]
function ClientHelper.getAttackingCreature()
  local Client = ClientHelper.getClient()
  if Client and Client.getAttackingCreature then
    return Client.getAttackingCreature()
  elseif g_game and g_game.getAttackingCreature then
    return g_game.getAttackingCreature()
  end
  return nil
end

--[[
  Get spectators in range
  @param pos Position center
  @param multiFloor boolean include other floors
  @param rangeX number horizontal range
  @param rangeY number vertical range (optional, defaults to rangeX)
  @return array of creatures
]]
function ClientHelper.getSpectatorsInRange(pos, multiFloor, rangeX, rangeY)
  if not pos then return {} end
  rangeY = rangeY or rangeX
  multiFloor = multiFloor or false
  
  local Client = ClientHelper.getClient()
  if Client and Client.getSpectatorsInRange then
    return Client.getSpectatorsInRange(pos, multiFloor, rangeX, rangeY) or {}
  elseif g_map and g_map.getSpectatorsInRange then
    return g_map.getSpectatorsInRange(pos, multiFloor, rangeX, rangeY) or {}
  end
  return {}
end

--[[
  Get tile at position
  @param pos Position
  @return Tile or nil
]]
function ClientHelper.getTile(pos)
  if not pos then return nil end
  
  local map = ClientHelper.getMap()
  if map and map.getTile then
    return map.getTile(pos)
  end
  return nil
end

--[[
  Open URL in browser
  @param url string
]]
function ClientHelper.openUrl(url)
  if not url then return end
  
  local Client = ClientHelper.getClient()
  if Client and Client.openUrl then
    Client.openUrl(url)
  elseif g_platform and g_platform.openUrl then
    g_platform.openUrl(url)
  end
end

--[[
  Say text
  @param mode SpeakType
  @param text string
  @param channel number (optional)
]]
function ClientHelper.say(text, mode, channel)
  if not text then return end
  mode = mode or 1  -- SpeakSay
  
  local game = ClientHelper.getGame()
  if game and game.talk then
    if channel then
      game.talk(text, mode, channel)
    else
      game.talk(text, mode)
    end
  end
end

--[[
  Use item on yourself
  @param item Item or itemId
]]
function ClientHelper.useOnSelf(item)
  if not item then return end
  
  local game = ClientHelper.getGame()
  local player = ClientHelper.getLocalPlayer()
  if game and game.useInventoryItemWith and player then
    game.useInventoryItemWith(item, player)
  end
end

--[[
  Invalidate all caches (call on relogin)
]]
function ClientHelper.invalidate()
  _cachedPlayer = nil
  _lastPlayerCheck = 0
  _cachedVersion = nil
end

-- Auto-invalidate on player events if EventBus is available
if EventBus and EventBus.on then
  EventBus.on("player:login", function()
    ClientHelper.invalidate()
  end, 1)
  
  EventBus.on("player:logout", function()
    ClientHelper.invalidate()
  end, 1)
end

-- Expose as global for use by all modules (no _G in OTClient sandbox)
if not ClientHelper then ClientHelper = ClientHelper end

return ClientHelper
