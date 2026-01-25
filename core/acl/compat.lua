--[[
  nExBot ACL - Compatibility Layer
  
  This module provides backward-compatible global function wrappers
  that use the ClientService/ACL under the hood. This allows existing
  modules to work without modification while benefiting from the ACL.
  
  The compatibility layer:
  1. Wraps common g_game/g_map operations with client-aware implementations
  2. Provides optimized versions using client-specific features when available
  3. Maintains full backward compatibility with existing code
  
  Principles:
  - KISS: Simple drop-in replacements
  - DRY: Single implementation source (ClientService)
  - Open/Closed: Existing code works, new code can use ClientService directly
]]

-- Get ClientService reference (should be loaded before this)
local Client = ClientService

if not Client then
  warn("[ACL Compat] ClientService not found, compatibility layer disabled")
  return
end

--------------------------------------------------------------------------------
-- SAFE CALL ENHANCEMENTS
-- Enhance SafeCall global with client-aware implementations
--------------------------------------------------------------------------------

if SafeCall then
  -- Store original implementations for fallback
  local originalUseWith = SafeCall.useWith
  local originalGetCreatureByName = SafeCall.getCreatureByName
  
  -- Enhanced useWith that uses client-specific optimizations
  function SafeCall.useWith(item, target, subType)
    -- Try ClientService first (handles client differences)
    if Client and Client.useWith then
      local status, result = pcall(Client.useWith, item, target)
      if status then return result end
    end
    -- Fallback to original
    if originalUseWith then
      return originalUseWith(item, target, subType)
    end
    -- Last resort: direct call
    if g_game and g_game.useWith then
      return g_game.useWith(item, target, subType)
    end
  end
  
  -- Enhanced getCreatureByName using client spectator system
  function SafeCall.getCreatureByName(name, caseSensitive)
    if Client and Client.getCreatureByName then
      local status, result = pcall(Client.getCreatureByName, name, caseSensitive)
      if status then return result end
    end
    if originalGetCreatureByName then
      return originalGetCreatureByName(name, caseSensitive)
    end
    return nil
  end
  
  -- Add new SafeCall functions that use ClientService
  function SafeCall.global(funcName, ...)
    -- Handle common global functions through ClientService
    if funcName == "getSpectators" then
      return Client.getSpectators(...)
    elseif funcName == "getTile" then
      return Client.getTile(...)
    elseif funcName == "getLocalPlayer" then
      return Client.getLocalPlayer()
    end
    
    -- Fallback to actual global
    local fn = _G[funcName]
    if fn and type(fn) == "function" then
      return fn(...)
    end
    return nil
  end
end

--------------------------------------------------------------------------------
-- GAME WRAPPER FUNCTIONS
-- These wrap g_game calls to use ClientService
--------------------------------------------------------------------------------

-- Create game wrapper namespace
local GameWrapper = {}

-- Connection state
function GameWrapper.isOnline()
  return Client.isOnline()
end

function GameWrapper.isDead()
  return Client.isDead()
end

function GameWrapper.isAttacking()
  return Client.isAttacking()
end

function GameWrapper.isFollowing()
  return Client.isFollowing()
end

-- Player access
function GameWrapper.getLocalPlayer()
  return Client.getLocalPlayer()
end

-- Combat
function GameWrapper.attack(creature)
  return Client.attack(creature)
end

function GameWrapper.cancelAttack()
  return Client.cancelAttack()
end

function GameWrapper.follow(creature)
  return Client.follow(creature)
end

function GameWrapper.cancelFollow()
  return Client.cancelFollow()
end

function GameWrapper.cancelAttackAndFollow()
  return Client.cancelAttackAndFollow()
end

function GameWrapper.getAttackingCreature()
  return Client.getAttackingCreature()
end

function GameWrapper.getFollowingCreature()
  return Client.getFollowingCreature()
end

-- Movement
function GameWrapper.walk(direction)
  return Client.walk(direction)
end

function GameWrapper.turn(direction)
  return Client.turn(direction)
end

function GameWrapper.stop()
  return Client.stop()
end

-- Items
function GameWrapper.move(thing, toPosition, count)
  return Client.move(thing, toPosition, count)
end

function GameWrapper.use(thing)
  return Client.use(thing)
end

function GameWrapper.useWith(item, target)
  return Client.useWith(item, target)
end

function GameWrapper.useInventoryItem(itemId)
  return Client.useInventoryItem(itemId)
end

function GameWrapper.useInventoryItemWith(itemId, target)
  return Client.useInventoryItemWith(itemId, target)
end

function GameWrapper.look(thing)
  return Client.look(thing)
end

function GameWrapper.rotate(thing)
  return Client.rotate(thing)
end

function GameWrapper.equipItem(item)
  return Client.equipItem(item)
end

function GameWrapper.equipItemId(itemId, destSlot)
  return Client.equipItemId(itemId, destSlot)
end

function GameWrapper.findItemInContainers(itemId, subType)
  return Client.findItemInContainers(itemId, subType)
end

function GameWrapper.findPlayerItem(itemId, subType)
  return Client.findPlayerItem(itemId, subType)
end

-- Containers
function GameWrapper.open(item, previousContainer)
  return Client.open(item, previousContainer)
end

function GameWrapper.openParent(container)
  return Client.openParent(container)
end

function GameWrapper.close(container)
  return Client.close(container)
end

function GameWrapper.getContainer(id)
  return Client.getContainer(id)
end

function GameWrapper.getContainers()
  return Client.getContainers()
end

function GameWrapper.seekInContainer(container, index)
  return Client.seekInContainer(container, index)
end

-- Communication
function GameWrapper.talk(message)
  return Client.talk(message)
end

function GameWrapper.talkChannel(mode, channelId, message)
  return Client.talkChannel(mode, channelId, message)
end

function GameWrapper.talkPrivate(mode, receiver, message)
  return Client.talkPrivate(mode, receiver, message)
end

function GameWrapper.talkLocal(message)
  return Client.talkLocal(message)
end

function GameWrapper.requestChannels()
  if g_game and g_game.requestChannels then
    return g_game.requestChannels()
  end
end

function GameWrapper.joinChannel(channelId)
  if g_game and g_game.joinChannel then
    return g_game.joinChannel(channelId)
  end
end

function GameWrapper.leaveChannel(channelId)
  if g_game and g_game.leaveChannel then
    return g_game.leaveChannel(channelId)
  end
end

-- Protocol info
function GameWrapper.getClientVersion()
  return Client.getClientVersion()
end

function GameWrapper.getProtocolVersion()
  return Client.getProtocolVersion()
end

function GameWrapper.getFeature(feature)
  return Client.getFeature(feature)
end

function GameWrapper.enableFeature(feature)
  return Client.enableFeature(feature)
end

function GameWrapper.getPing()
  return Client.getPing()
end

function GameWrapper.getUnjustifiedPoints()
  return Client.getUnjustifiedPoints()
end

-- Combat settings
function GameWrapper.getChaseMode()
  return Client.getChaseMode()
end

function GameWrapper.getFightMode()
  return Client.getFightMode()
end

function GameWrapper.setChaseMode(mode)
  return Client.setChaseMode(mode)
end

function GameWrapper.setFightMode(mode)
  return Client.setFightMode(mode)
end

function GameWrapper.isSafeFight()
  return Client.isSafeFight()
end

function GameWrapper.setSafeFight(safe)
  return Client.setSafeFight(safe)
end

-- Mount operations
function GameWrapper.mount(mount)
  return Client.mount(mount)
end

function GameWrapper.dismount()
  return Client.dismount()
end

-- Party operations
function GameWrapper.partyInvite(creatureId)
  return Client.partyInvite(creatureId)
end

function GameWrapper.partyJoin(creatureId)
  return Client.partyJoin(creatureId)
end

function GameWrapper.partyLeave()
  return Client.partyLeave()
end

-- Logout
function GameWrapper.safeLogout()
  return Client.safeLogout()
end

function GameWrapper.forceLogout()
  return Client.forceLogout()
end

-- Trading
function GameWrapper.buyItem(item, count, ignoreEquipped, ignoreCap)
  if g_game and g_game.buyItem then
    return g_game.buyItem(item, count, ignoreEquipped, ignoreCap)
  end
end

function GameWrapper.sellItem(item, count)
  if g_game and g_game.sellItem then
    return g_game.sellItem(item, count)
  end
end

function GameWrapper.closeNpcTrade()
  if g_game and g_game.closeNpcTrade then
    return g_game.closeNpcTrade()
  end
end

-- Outfit
function GameWrapper.requestOutfit()
  return Client.requestOutfit()
end

function GameWrapper.changeOutfit(outfit)
  return Client.changeOutfit(outfit)
end

--------------------------------------------------------------------------------
-- MAP WRAPPER FUNCTIONS
--------------------------------------------------------------------------------

local MapWrapper = {}

function MapWrapper.getTile(pos)
  return Client.getTile(pos)
end

function MapWrapper.getTiles(floor)
  return Client.getTiles(floor)
end

function MapWrapper.getMinimapColor(pos)
  return Client.getMinimapColor(pos)
end

function MapWrapper.getSpectators(pos, multifloor)
  return Client.getSpectators(pos, multifloor)
end

function MapWrapper.getSpectatorsInRange(pos, xRange, yRange, multifloor)
  return Client.getSpectatorsInRange(pos, xRange, yRange, multifloor)
end

function MapWrapper.isSightClear(fromPos, toPos, floorCheck)
  return Client.isSightClear(fromPos, toPos, floorCheck)
end

function MapWrapper.isTileWalkable(pos)
  return Client.isTileWalkable(pos)
end

function MapWrapper.findPath(startPos, goalPos, maxSteps, options)
  if type(maxSteps) == "table" then
    options = maxSteps
    maxSteps = options.maxSteps
  end
  return Client.findPath(startPos, goalPos, options)
end

function MapWrapper.isLookPossible(pos)
  if g_map and g_map.isLookPossible then
    return g_map.isLookPossible(pos)
  end
  return false
end

function MapWrapper.cleanDynamicThings()
  if g_map and g_map.cleanDynamicThings then
    return g_map.cleanDynamicThings()
  end
end

--------------------------------------------------------------------------------
-- APPLY WRAPPERS (Optional - can be enabled for full replacement)
-- By default, we enhance existing objects rather than replace them
--------------------------------------------------------------------------------

-- Create enhanced g_game proxy that uses ClientService
local function createGameProxy()
  local proxy = {}
  local mt = {
    __index = function(t, k)
      -- First check our wrapper
      if GameWrapper[k] then
        return GameWrapper[k]
      end
      -- Fall back to original g_game
      if g_game and g_game[k] then
        return g_game[k]
      end
      return nil
    end,
    __newindex = function(t, k, v)
      rawset(g_game, k, v)
    end
  }
  setmetatable(proxy, mt)
  return proxy
end

-- Create enhanced g_map proxy that uses ClientService
local function createMapProxy()
  local proxy = {}
  local mt = {
    __index = function(t, k)
      -- First check our wrapper
      if MapWrapper[k] then
        return MapWrapper[k]
      end
      -- Fall back to original g_map
      if g_map and g_map[k] then
        return g_map[k]
      end
      return nil
    end,
    __newindex = function(t, k, v)
      rawset(g_map, k, v)
    end
  }
  setmetatable(proxy, mt)
  return proxy
end

--------------------------------------------------------------------------------
-- EXPORT
--------------------------------------------------------------------------------

local Compat = {
  GameWrapper = GameWrapper,
  MapWrapper = MapWrapper,
  createGameProxy = createGameProxy,
  createMapProxy = createMapProxy,
  
  -- Helper to enable full proxy mode (replaces g_game/g_map)
  enableProxyMode = function()
    _G.g_game_original = g_game
    _G.g_map_original = g_map
    _G.g_game = createGameProxy()
    _G.g_map = createMapProxy()
    return true
  end,
  
  -- Helper to disable proxy mode
  disableProxyMode = function()
    if _G.g_game_original then
      _G.g_game = _G.g_game_original
    end
    if _G.g_map_original then
      _G.g_map = _G.g_map_original
    end
    return true
  end
}

-- Export globally
_G.ACLCompat = Compat

return Compat
