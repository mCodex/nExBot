--[[
  nExBot Client Service
  
  Provides a unified interface for client operations using the ACL.
  This is the primary service that bot modules should use instead
  of directly accessing g_game, g_map, etc.
  
  Principles Applied:
  - SRP: Single responsibility - client abstraction
  - DIP: Depends on ACL abstraction, not concrete clients
  - DRY: Centralizes all client access
  - KISS: Simple, intuitive API
  
  Usage:
    local Client = require("client_service")
    Client.attack(creature)
    Client.getLocalPlayer()
    Client.getSpectators()
]]

-- Try to load ACL
local ACL = nil
local aclLoaded = false

local function loadACL()
  if aclLoaded then return ACL end
  
  local status, result = pcall(function()
    return dofile("/core/acl/init.lua")
  end)
  
  if status and result then
    ACL = result
    ACL.init()
  else
    warn("[ClientService] Failed to load ACL, using direct client access")
  end
  
  aclLoaded = true
  return ACL
end

-- Client Service
local ClientService = {}

-- Service metadata
ClientService.NAME = "ClientService"
ClientService.VERSION = "1.0.0"

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function ClientService.init()
  loadACL()
  return true
end

function ClientService.getClientType()
  local acl = loadACL()
  if acl then
    return acl.getClientType()
  end
  return 0 -- UNKNOWN
end

function ClientService.getClientName()
  local acl = loadACL()
  if acl then
    return acl.getClientName()
  end
  return "Unknown"
end

function ClientService.isOTCv8()
  local acl = loadACL()
  return acl and acl.isOTCv8() or true -- Default to OTCv8
end

function ClientService.isOpenTibiaBR()
  local acl = loadACL()
  return acl and acl.isOpenTibiaBR() or false
end

--------------------------------------------------------------------------------
-- GAME OPERATIONS (delegated to ACL or direct)
--------------------------------------------------------------------------------

-- Connection state
function ClientService.isOnline()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.isOnline()
  end
  return g_game and g_game.isOnline and g_game.isOnline() or false
end

function ClientService.isDead()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.isDead()
  end
  return g_game and g_game.isDead and g_game.isDead() or false
end

function ClientService.isAttacking()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.isAttacking()
  end
  return g_game and g_game.isAttacking and g_game.isAttacking() or false
end

function ClientService.isFollowing()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.isFollowing()
  end
  return g_game and g_game.isFollowing and g_game.isFollowing() or false
end

-- Player access
function ClientService.getLocalPlayer()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.getLocalPlayer()
  end
  return g_game and g_game.getLocalPlayer and g_game.getLocalPlayer() or nil
end

-- Combat
function ClientService.attack(creature)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.attack(creature)
  end
  if g_game and g_game.attack then
    return g_game.attack(creature)
  end
end

function ClientService.cancelAttack()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.cancelAttack()
  end
  if g_game and g_game.cancelAttack then
    return g_game.cancelAttack()
  end
end

function ClientService.follow(creature)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.follow(creature)
  end
  if g_game and g_game.follow then
    return g_game.follow(creature)
  end
end

function ClientService.cancelFollow()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.cancelFollow()
  end
  if g_game and g_game.cancelFollow then
    return g_game.cancelFollow()
  end
end

function ClientService.cancelAttackAndFollow()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.cancelAttackAndFollow()
  end
  if g_game and g_game.cancelAttackAndFollow then
    return g_game.cancelAttackAndFollow()
  end
end

function ClientService.getAttackingCreature()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.getAttackingCreature()
  end
  return g_game and g_game.getAttackingCreature and g_game.getAttackingCreature() or nil
end

function ClientService.getFollowingCreature()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.getFollowingCreature()
  end
  return g_game and g_game.getFollowingCreature and g_game.getFollowingCreature() or nil
end

-- Movement
function ClientService.walk(direction)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.walk(direction)
  end
  if g_game and g_game.walk then
    return g_game.walk(direction)
  end
  return false
end

function ClientService.autoWalk(destination, maxSteps, options)
  local acl = loadACL()
  if acl and acl.game and acl.game.autoWalk then
    return acl.game.autoWalk(destination, maxSteps, options)
  end
  if g_game and g_game.autoWalk then
    return g_game.autoWalk(destination, maxSteps, options)
  end
  return false
end

function ClientService.turn(direction)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.turn(direction)
  end
  if g_game and g_game.turn then
    return g_game.turn(direction)
  end
end

function ClientService.stop()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.stop()
  end
  if g_game and g_game.stop then
    return g_game.stop()
  end
end

-- Items
function ClientService.move(thing, toPosition, count)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.move(thing, toPosition, count)
  end
  if g_game and g_game.move then
    return g_game.move(thing, toPosition, count or 1)
  end
end

function ClientService.use(thing)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.use(thing)
  end
  if g_game and g_game.use then
    return g_game.use(thing)
  end
end

function ClientService.useWith(item, target)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.useWith(item, target)
  end
  if g_game and g_game.useWith then
    return g_game.useWith(item, target)
  end
end

function ClientService.useInventoryItem(itemId)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.useInventoryItem(itemId)
  end
  if g_game and g_game.useInventoryItem then
    return g_game.useInventoryItem(itemId)
  end
end

function ClientService.look(thing)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.look(thing)
  end
  if g_game and g_game.look then
    return g_game.look(thing)
  end
end

function ClientService.rotate(thing)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.rotate(thing)
  end
  if g_game and g_game.rotate then
    return g_game.rotate(thing)
  end
end

function ClientService.equipItem(item)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.equipItem(item)
  end
  if g_game and g_game.equipItem then
    return g_game.equipItem(item)
  end
end

-- Containers
function ClientService.open(item, previousContainer)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.open(item, previousContainer)
  end
  if g_game and g_game.open then
    return g_game.open(item, previousContainer)
  end
end

function ClientService.openParent(container)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.openParent(container)
  end
  if g_game and g_game.openParent then
    return g_game.openParent(container)
  end
end

function ClientService.close(container)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.close(container)
  end
  if g_game and g_game.close then
    return g_game.close(container)
  end
end

function ClientService.getContainer(id)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.getContainer(id)
  end
  return g_game and g_game.getContainer and g_game.getContainer(id) or nil
end

function ClientService.getContainers()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.getContainers()
  end
  return g_game and g_game.getContainers and g_game.getContainers() or {}
end

-- Communication
function ClientService.talk(message)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.talk(message)
  end
  if g_game and g_game.talk then
    return g_game.talk(message)
  end
end

function ClientService.talkChannel(mode, channelId, message)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.talkChannel(mode, channelId, message)
  end
  if g_game and g_game.talkChannel then
    return g_game.talkChannel(mode, channelId, message)
  end
end

function ClientService.talkPrivate(mode, receiver, message)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.talkPrivate(mode, receiver, message)
  end
  if g_game and g_game.talkPrivate then
    return g_game.talkPrivate(mode, receiver, message)
  end
end

-- Protocol info
function ClientService.getClientVersion()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.getClientVersion()
  end
  return g_game and g_game.getClientVersion and g_game.getClientVersion() or 0
end

function ClientService.getProtocolVersion()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.getProtocolVersion()
  end
  return g_game and g_game.getProtocolVersion and g_game.getProtocolVersion() or 0
end

function ClientService.getFeature(feature)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.getFeature(feature)
  end
  return g_game and g_game.getFeature and g_game.getFeature(feature) or false
end

function ClientService.enableFeature(feature)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.enableFeature(feature)
  end
  if g_game and g_game.enableFeature then
    return g_game.enableFeature(feature)
  end
end

function ClientService.getPing()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.getPing()
  end
  return g_game and g_game.getPing and g_game.getPing() or 0
end

function ClientService.getUnjustifiedPoints()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.getUnjustifiedPoints()
  end
  return g_game and g_game.getUnjustifiedPoints and g_game.getUnjustifiedPoints() or {}
end

-- Combat settings
function ClientService.getChaseMode()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.getChaseMode()
  end
  return g_game and g_game.getChaseMode and g_game.getChaseMode() or 0
end

function ClientService.getFightMode()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.getFightMode()
  end
  return g_game and g_game.getFightMode and g_game.getFightMode() or 0
end

function ClientService.setChaseMode(mode)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.setChaseMode(mode)
  end
  if g_game and g_game.setChaseMode then
    return g_game.setChaseMode(mode)
  end
end

function ClientService.setFightMode(mode)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.setFightMode(mode)
  end
  if g_game and g_game.setFightMode then
    return g_game.setFightMode(mode)
  end
end

function ClientService.isSafeFight()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.isSafeFight()
  end
  return g_game and g_game.isSafeFight and g_game.isSafeFight() or false
end

function ClientService.setSafeFight(safe)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.setSafeFight(safe)
  end
  if g_game and g_game.setSafeFight then
    return g_game.setSafeFight(safe)
  end
end

-- Outfit
function ClientService.requestOutfit()
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.requestOutfit()
  end
  if g_game and g_game.requestOutfit then
    return g_game.requestOutfit()
  end
end

function ClientService.changeOutfit(outfit)
  local acl = loadACL()
  if acl and acl.game then
    return acl.game.changeOutfit(outfit)
  end
  if g_game and g_game.changeOutfit then
    return g_game.changeOutfit(outfit)
  end
end

--------------------------------------------------------------------------------
-- MAP OPERATIONS
--------------------------------------------------------------------------------

function ClientService.getTile(pos)
  local acl = loadACL()
  if acl and acl.map then
    return acl.map.getTile(pos)
  end
  return g_map and g_map.getTile and g_map.getTile(pos) or nil
end

function ClientService.getSpectators(pos, multifloor)
  local acl = loadACL()
  if acl and acl.map and acl.map.getSpectators then
    return acl.map.getSpectators(pos, multifloor)
  end
  
  -- Fallback to bot context
  if getSpectators then
    return getSpectators(pos, multifloor) or {}
  end
  
  -- Last resort: g_map
  if g_map and g_map.getSpectators then
    return g_map.getSpectators(pos, multifloor) or {}
  end
  
  return {}
end

function ClientService.isSightClear(fromPos, toPos, floorCheck)
  local acl = loadACL()
  if acl and acl.map then
    return acl.map.isSightClear(fromPos, toPos, floorCheck)
  end
  return g_map and g_map.isSightClear and g_map.isSightClear(fromPos, toPos, floorCheck) or false
end

function ClientService.findPath(startPos, goalPos, options)
  local acl = loadACL()
  if acl and acl.map and acl.map.findPath then
    return acl.map.findPath(startPos, goalPos, options)
  end
  if g_map and g_map.findPath then
    return g_map.findPath(startPos, goalPos, options and options.maxSteps or 50)
  end
  return nil
end

--------------------------------------------------------------------------------
-- COOLDOWN OPERATIONS
--------------------------------------------------------------------------------

function ClientService.isCooldownActive(iconId)
  local acl = loadACL()
  if acl and acl.cooldown and acl.cooldown.isCooldownIconActive then
    return acl.cooldown.isCooldownIconActive(iconId)
  end
  
  local cooldownModule = modules and modules.game_cooldown
  if cooldownModule and cooldownModule.isCooldownIconActive then
    return cooldownModule.isCooldownIconActive(iconId)
  end
  
  return false
end

function ClientService.isGroupCooldownActive(groupId)
  local acl = loadACL()
  if acl and acl.cooldown and acl.cooldown.isGroupCooldownIconActive then
    return acl.cooldown.isGroupCooldownIconActive(groupId)
  end
  
  local cooldownModule = modules and modules.game_cooldown
  if cooldownModule and cooldownModule.isGroupCooldownIconActive then
    return cooldownModule.isGroupCooldownIconActive(groupId)
  end
  
  return false
end

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

function ClientService.getPos(x, y, z)
  local acl = loadACL()
  if acl and acl.utils then
    return acl.utils.getPos(x, y, z)
  end
  
  local player = ClientService.getLocalPlayer()
  if player then
    local pos = player:getPosition()
    pos.x = x or pos.x
    pos.y = y or pos.y
    pos.z = z or pos.z
    return pos
  end
  return {x = x or 0, y = y or 0, z = z or 0}
end

function ClientService.getDistanceBetween(pos1, pos2)
  if not pos1 or not pos2 then return 999 end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

function ClientService.isSamePosition(pos1, pos2)
  if not pos1 or not pos2 then return false end
  return pos1.x == pos2.x and pos1.y == pos2.y and pos1.z == pos2.z
end

function ClientService.isInRange(pos1, pos2, rangeX, rangeY)
  if not pos1 or not pos2 then return false end
  rangeY = rangeY or rangeX
  return math.abs(pos1.x - pos2.x) <= rangeX and 
         math.abs(pos1.y - pos2.y) <= rangeY and 
         pos1.z == pos2.z
end

-- Find creature by name
function ClientService.getCreatureByName(name, caseSensitive)
  local acl = loadACL()
  if acl and acl.utils and acl.utils.getCreatureByName then
    return acl.utils.getCreatureByName(name, caseSensitive)
  end
  
  -- Fallback implementation
  local player = ClientService.getLocalPlayer()
  if not player then return nil end
  
  local spectators = ClientService.getSpectators(player:getPosition(), true)
  for _, creature in ipairs(spectators) do
    if caseSensitive then
      if creature:getName() == name then
        return creature
      end
    else
      if creature:getName():lower() == name:lower() then
        return creature
      end
    end
  end
  
  return nil
end

-- Find item
function ClientService.findItem(itemId, subType)
  local acl = loadACL()
  if acl and acl.utils and acl.utils.findItem then
    return acl.utils.findItem(itemId, subType)
  end
  
  -- Fallback to global findItem if available
  if findItem then
    return findItem(itemId, subType)
  end
  
  -- Manual search
  local player = ClientService.getLocalPlayer()
  if player then
    for slot = 1, 10 do
      local item = player:getInventoryItem(slot)
      if item and item:getId() == itemId then
        if not subType or item:getSubType() == subType then
          return item
        end
      end
    end
  end
  
  for _, container in pairs(ClientService.getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId then
        if not subType or item:getSubType() == subType then
          return item
        end
      end
    end
  end
  
  return nil
end

-- Count items
function ClientService.itemAmount(itemId, subType)
  local acl = loadACL()
  if acl and acl.utils and acl.utils.itemAmount then
    return acl.utils.itemAmount(itemId, subType)
  end
  
  -- Fallback to global itemAmount if available
  if itemAmount then
    return itemAmount(itemId, subType)
  end
  
  local count = 0
  local player = ClientService.getLocalPlayer()
  if player then
    for slot = 1, 10 do
      local item = player:getInventoryItem(slot)
      if item and item:getId() == itemId then
        if not subType or item:getSubType() == subType then
          count = count + item:getCount()
        end
      end
    end
  end
  
  for _, container in pairs(ClientService.getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId then
        if not subType or item:getSubType() == subType then
          count = count + item:getCount()
        end
      end
    end
  end
  
  return count
end

--------------------------------------------------------------------------------
-- CALLBACK REGISTRATION
--------------------------------------------------------------------------------

function ClientService.onCreatureAppear(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onCreatureAppear then
    return acl.callbacks.onCreatureAppear(callback)
  end
  if onCreatureAppear then
    return onCreatureAppear(callback)
  end
end

function ClientService.onCreatureDisappear(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onCreatureDisappear then
    return acl.callbacks.onCreatureDisappear(callback)
  end
  if onCreatureDisappear then
    return onCreatureDisappear(callback)
  end
end

function ClientService.onPlayerPositionChange(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onPlayerPositionChange then
    return acl.callbacks.onPlayerPositionChange(callback)
  end
  if onPlayerPositionChange then
    return onPlayerPositionChange(callback)
  end
end

function ClientService.onTalk(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onTalk then
    return acl.callbacks.onTalk(callback)
  end
  if onTalk then
    return onTalk(callback)
  end
end

function ClientService.onTextMessage(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onTextMessage then
    return acl.callbacks.onTextMessage(callback)
  end
  if onTextMessage then
    return onTextMessage(callback)
  end
end

function ClientService.onContainerOpen(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onContainerOpen then
    return acl.callbacks.onContainerOpen(callback)
  end
  if onContainerOpen then
    return onContainerOpen(callback)
  end
end

function ClientService.onSpellCooldown(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onSpellCooldown then
    return acl.callbacks.onSpellCooldown(callback)
  end
  if onSpellCooldown then
    return onSpellCooldown(callback)
  end
end

function ClientService.onGroupSpellCooldown(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onGroupSpellCooldown then
    return acl.callbacks.onGroupSpellCooldown(callback)
  end
  if onGroupSpellCooldown then
    return onGroupSpellCooldown(callback)
  end
end

--------------------------------------------------------------------------------
-- EXTENDED GAME OPERATIONS (Added for full module compatibility)
--------------------------------------------------------------------------------

-- Inventory operations
function ClientService.useInventoryItemWith(itemId, target)
  local acl = loadACL()
  if acl and acl.game and acl.game.useInventoryItemWith then
    return acl.game.useInventoryItemWith(itemId, target)
  end
  if g_game and g_game.useInventoryItemWith then
    return g_game.useInventoryItemWith(itemId, target)
  end
end

function ClientService.findPlayerItem(itemId, subType)
  local acl = loadACL()
  if acl and acl.game and acl.game.findPlayerItem then
    return acl.game.findPlayerItem(itemId, subType)
  end
  if g_game and g_game.findPlayerItem then
    return g_game.findPlayerItem(itemId, subType)
  end
  -- Fallback implementation
  return ClientService.findItem(itemId, subType)
end

function ClientService.findItemInContainers(itemId, subType)
  local acl = loadACL()
  if acl and acl.game and acl.game.findItemInContainers then
    return acl.game.findItemInContainers(itemId, subType)
  end
  if g_game and g_game.findItemInContainers then
    return g_game.findItemInContainers(itemId, subType)
  end
  -- Fallback: search containers manually
  for _, container in pairs(ClientService.getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId then
        if not subType or item:getSubType() == subType then
          return item
        end
      end
    end
  end
  return nil
end

function ClientService.equipItemId(itemId, destSlot)
  local acl = loadACL()
  if acl and acl.game and acl.game.equipItemId then
    return acl.game.equipItemId(itemId, destSlot)
  end
  if g_game and g_game.equipItemId then
    return g_game.equipItemId(itemId, destSlot)
  end
end

-- Mount operations
function ClientService.mount(mount)
  local acl = loadACL()
  if acl and acl.game and acl.game.mount then
    return acl.game.mount(mount)
  end
  if g_game and g_game.mount then
    return g_game.mount(mount)
  end
end

function ClientService.dismount()
  local acl = loadACL()
  if acl and acl.game and acl.game.dismount then
    return acl.game.dismount()
  end
  if g_game and g_game.dismount then
    return g_game.dismount()
  end
end

-- Party operations
function ClientService.partyInvite(creatureId)
  local acl = loadACL()
  if acl and acl.game and acl.game.partyInvite then
    return acl.game.partyInvite(creatureId)
  end
  if g_game and g_game.partyInvite then
    return g_game.partyInvite(creatureId)
  end
end

function ClientService.partyJoin(creatureId)
  local acl = loadACL()
  if acl and acl.game and acl.game.partyJoin then
    return acl.game.partyJoin(creatureId)
  end
  if g_game and g_game.partyJoin then
    return g_game.partyJoin(creatureId)
  end
end

function ClientService.partyLeave()
  local acl = loadACL()
  if acl and acl.game and acl.game.partyLeave then
    return acl.game.partyLeave()
  end
  if g_game and g_game.partyLeave then
    return g_game.partyLeave()
  end
end

-- Seek in container
function ClientService.seekInContainer(container, index)
  local acl = loadACL()
  if acl and acl.game and acl.game.seekInContainer then
    return acl.game.seekInContainer(container, index)
  end
  if g_game and g_game.seekInContainer then
    return g_game.seekInContainer(container, index)
  end
end

-- Logout
function ClientService.safeLogout()
  local acl = loadACL()
  if acl and acl.game and acl.game.safeLogout then
    return acl.game.safeLogout()
  end
  if g_game and g_game.safeLogout then
    return g_game.safeLogout()
  end
end

function ClientService.forceLogout()
  local acl = loadACL()
  if acl and acl.game and acl.game.forceLogout then
    return acl.game.forceLogout()
  end
  if g_game and g_game.forceLogout then
    return g_game.forceLogout()
  end
end

-- Say (alias for talk)
function ClientService.say(message)
  return ClientService.talk(message)
end

-- Talk local (OTCv8 specific)
function ClientService.talkLocal(message)
  local acl = loadACL()
  if acl and acl.game and acl.game.talkLocal then
    return acl.game.talkLocal(message)
  end
  if g_game and g_game.talkLocal then
    return g_game.talkLocal(message)
  end
  -- Fallback to regular talk
  return ClientService.talk(message)
end

--------------------------------------------------------------------------------
-- EXTENDED MAP OPERATIONS
--------------------------------------------------------------------------------

function ClientService.getTiles(floor)
  local acl = loadACL()
  if acl and acl.map and acl.map.getTiles then
    return acl.map.getTiles(floor)
  end
  return g_map and g_map.getTiles and g_map.getTiles(floor) or {}
end

function ClientService.getMinimapColor(pos)
  local acl = loadACL()
  if acl and acl.map and acl.map.getMinimapColor then
    return acl.map.getMinimapColor(pos)
  end
  return g_map and g_map.getMinimapColor and g_map.getMinimapColor(pos) or 0
end

function ClientService.getSpectatorsInRange(pos, xRange, yRange, multifloor)
  local acl = loadACL()
  if acl and acl.map and acl.map.getSpectatorsInRange then
    return acl.map.getSpectatorsInRange(pos, xRange, yRange, multifloor)
  end
  if g_map and g_map.getSpectatorsInRange then
    return g_map.getSpectatorsInRange(pos, xRange, yRange, multifloor) or {}
  end
  -- Fallback to getSpectators
  return ClientService.getSpectators(pos, multifloor)
end

function ClientService.isTileWalkable(pos)
  local acl = loadACL()
  if acl and acl.map and acl.map.isTileWalkable then
    return acl.map.isTileWalkable(pos)
  end
  if g_map and g_map.isTileWalkable then
    return g_map.isTileWalkable(pos)
  end
  -- Fallback: check tile directly
  local tile = ClientService.getTile(pos)
  return tile and tile:isWalkable() or false
end

--------------------------------------------------------------------------------
-- UI OPERATIONS
--------------------------------------------------------------------------------

function ClientService.importStyle(path)
  local acl = loadACL()
  if acl and acl.ui and acl.ui.importStyle then
    return acl.ui.importStyle(path)
  end
  if g_ui and g_ui.importStyle then
    return g_ui.importStyle(path)
  end
end

function ClientService.createWidget(widgetType, parent)
  local acl = loadACL()
  if acl and acl.ui and acl.ui.createWidget then
    return acl.ui.createWidget(widgetType, parent)
  end
  if g_ui and g_ui.createWidget then
    return g_ui.createWidget(widgetType, parent)
  end
end

function ClientService.getRootWidget()
  local acl = loadACL()
  if acl and acl.ui and acl.ui.getRootWidget then
    return acl.ui.getRootWidget()
  end
  return g_ui and g_ui.getRootWidget and g_ui.getRootWidget() or nil
end

function ClientService.loadUI(path, parent)
  local acl = loadACL()
  if acl and acl.ui and acl.ui.loadUI then
    return acl.ui.loadUI(path, parent)
  end
  if g_ui and g_ui.loadUI then
    return g_ui.loadUI(path, parent)
  end
end

function ClientService.loadUIFromString(str, parent)
  local acl = loadACL()
  if acl and acl.ui and acl.ui.loadUIFromString then
    return acl.ui.loadUIFromString(str, parent)
  end
  if g_ui and g_ui.loadUIFromString then
    return g_ui.loadUIFromString(str, parent)
  end
end

--------------------------------------------------------------------------------
-- RESOURCE OPERATIONS
--------------------------------------------------------------------------------

function ClientService.fileExists(path)
  if g_resources and g_resources.fileExists then
    return g_resources.fileExists(path)
  end
  return false
end

function ClientService.directoryExists(path)
  if g_resources and g_resources.directoryExists then
    return g_resources.directoryExists(path)
  end
  return false
end

function ClientService.makeDir(path)
  if g_resources and g_resources.makeDir then
    return g_resources.makeDir(path)
  end
end

function ClientService.readFileContents(path)
  if g_resources and g_resources.readFileContents then
    return g_resources.readFileContents(path)
  end
  return nil
end

function ClientService.writeFileContents(path, contents)
  if g_resources and g_resources.writeFileContents then
    return g_resources.writeFileContents(path, contents)
  end
end

function ClientService.listDirectoryFiles(path, recursive, showHidden)
  if g_resources and g_resources.listDirectoryFiles then
    return g_resources.listDirectoryFiles(path, recursive, showHidden) or {}
  end
  return {}
end

function ClientService.deleteFile(path)
  if g_resources and g_resources.deleteFile then
    return g_resources.deleteFile(path)
  end
end

--------------------------------------------------------------------------------
-- WINDOW OPERATIONS
--------------------------------------------------------------------------------

function ClientService.setWindowTitle(title)
  if g_window and g_window.setTitle then
    return g_window.setTitle(title)
  end
end

function ClientService.flashWindow()
  if g_window and g_window.flash then
    return g_window.flash()
  end
end

function ClientService.setClipboardText(text)
  if g_window and g_window.setClipboardText then
    return g_window.setClipboardText(text)
  end
end

--------------------------------------------------------------------------------
-- PLATFORM OPERATIONS
--------------------------------------------------------------------------------

function ClientService.openUrl(url)
  if g_platform and g_platform.openUrl then
    return g_platform.openUrl(url)
  end
end

--------------------------------------------------------------------------------
-- KEYBOARD OPERATIONS
--------------------------------------------------------------------------------

function ClientService.isKeyPressed(key)
  if g_keyboard and g_keyboard.isKeyPressed then
    return g_keyboard.isKeyPressed(key)
  end
  return false
end

--------------------------------------------------------------------------------
-- SETTINGS OPERATIONS
--------------------------------------------------------------------------------

function ClientService.getSettingNumber(key, default)
  if g_settings and g_settings.getNumber then
    return g_settings.getNumber(key) or default
  end
  return default
end

function ClientService.setSettingNumber(key, value)
  if g_settings and g_settings.setNumber then
    return g_settings.setNumber(key, value)
  end
end

--------------------------------------------------------------------------------
-- MODULE ACCESS
--------------------------------------------------------------------------------

function ClientService.getModule(name)
  if modules and modules[name] then
    return modules[name]
  end
  return nil
end

function ClientService.getGameInterface()
  return ClientService.getModule("game_interface")
end

function ClientService.getConsole()
  return ClientService.getModule("game_console")
end

function ClientService.getCooldown()
  return ClientService.getModule("game_cooldown")
end

function ClientService.getBot()
  return ClientService.getModule("game_bot")
end

function ClientService.getTerminal()
  return ClientService.getModule("client_terminal")
end

function ClientService.getTextMessage()
  return ClientService.getModule("game_textmessage")
end

function ClientService.getWalking()
  return ClientService.getModule("game_walking")
end

function ClientService.getInventory()
  return ClientService.getModule("game_inventory")
end

function ClientService.getContainersModule()
  return ClientService.getModule("game_containers")
end

function ClientService.getSkills()
  return ClientService.getModule("game_skills")
end

--------------------------------------------------------------------------------
-- ADDITIONAL CALLBACKS
--------------------------------------------------------------------------------

function ClientService.onUse(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onUse then
    return acl.callbacks.onUse(callback)
  end
  if onUse then
    return onUse(callback)
  end
end

function ClientService.onUseWith(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onUseWith then
    return acl.callbacks.onUseWith(callback)
  end
  if onUseWith then
    return onUseWith(callback)
  end
end

function ClientService.onCreatureHealthPercentChange(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onCreatureHealthPercentChange then
    return acl.callbacks.onCreatureHealthPercentChange(callback)
  end
  if onCreatureHealthPercentChange then
    return onCreatureHealthPercentChange(callback)
  end
end

function ClientService.onContainerClose(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onContainerClose then
    return acl.callbacks.onContainerClose(callback)
  end
  if onContainerClose then
    return onContainerClose(callback)
  end
end

function ClientService.onContainerUpdateItem(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onContainerUpdateItem then
    return acl.callbacks.onContainerUpdateItem(callback)
  end
  if onContainerUpdateItem then
    return onContainerUpdateItem(callback)
  end
end

function ClientService.onAddItem(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onAddItem then
    return acl.callbacks.onAddItem(callback)
  end
  if onAddItem then
    return onAddItem(callback)
  end
end

function ClientService.onRemoveItem(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onRemoveItem then
    return acl.callbacks.onRemoveItem(callback)
  end
  if onRemoveItem then
    return onRemoveItem(callback)
  end
end

-- Make it globally accessible
_G.ClientService = ClientService

return ClientService
