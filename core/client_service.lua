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

--------------------------------------------------------------------------------
-- OPENTIBIABR ENHANCED OPERATIONS
-- These functions expose OpenTibiaBR-specific features through the ACL
--------------------------------------------------------------------------------

-- Force walk (more reliable walking)
function ClientService.forceWalk(direction)
  local acl = loadACL()
  if acl and acl.game and acl.game.forceWalk then
    return acl.game.forceWalk(direction)
  end
  if g_game and g_game.forceWalk then
    return g_game.forceWalk(direction)
  end
  -- Fallback to normal walk
  return ClientService.walk(direction)
end

-- Schedule last walk
function ClientService.setScheduleLastWalk(schedule)
  local acl = loadACL()
  if acl and acl.game and acl.game.setScheduleLastWalk then
    return acl.game.setScheduleLastWalk(schedule)
  end
  if g_game and g_game.setScheduleLastWalk then
    return g_game.setScheduleLastWalk(schedule)
  end
end

-- Walk speed configuration
function ClientService.setWalkFirstStepDelay(delay)
  local acl = loadACL()
  if acl and acl.game and acl.game.setWalkFirstStepDelay then
    return acl.game.setWalkFirstStepDelay(delay)
  end
  if g_game and g_game.setWalkFirstStepDelay then
    return g_game.setWalkFirstStepDelay(delay)
  end
end

function ClientService.setWalkTurnDelay(delay)
  local acl = loadACL()
  if acl and acl.game and acl.game.setWalkTurnDelay then
    return acl.game.setWalkTurnDelay(delay)
  end
  if g_game and g_game.setWalkTurnDelay then
    return g_game.setWalkTurnDelay(delay)
  end
end

function ClientService.setWalkSpeedMultiplier(multiplier)
  local acl = loadACL()
  if acl and acl.game and acl.game.setWalkSpeedMultiplier then
    return acl.game.setWalkSpeedMultiplier(multiplier)
  end
  if g_game and g_game.setWalkSpeedMultiplier then
    return g_game.setWalkSpeedMultiplier(multiplier)
  end
end

function ClientService.getWalkSpeedMultiplier()
  local acl = loadACL()
  if acl and acl.game and acl.game.getWalkSpeedMultiplier then
    return acl.game.getWalkSpeedMultiplier()
  end
  if g_game and g_game.getWalkSpeedMultiplier then
    return g_game.getWalkSpeedMultiplier()
  end
  return 1.0
end

function ClientService.getWalkMaxSteps()
  local acl = loadACL()
  if acl and acl.game and acl.game.getWalkMaxSteps then
    return acl.game.getWalkMaxSteps()
  end
  if g_game and g_game.getWalkMaxSteps then
    return g_game.getWalkMaxSteps()
  end
  return 10
end

function ClientService.setWalkMaxSteps(steps)
  local acl = loadACL()
  if acl and acl.game and acl.game.setWalkMaxSteps then
    return acl.game.setWalkMaxSteps(steps)
  end
  if g_game and g_game.setWalkMaxSteps then
    return g_game.setWalkMaxSteps(steps)
  end
end

--------------------------------------------------------------------------------
-- STASH OPERATIONS
--------------------------------------------------------------------------------

function ClientService.stashWithdraw(itemId, count)
  local acl = loadACL()
  if acl and acl.game and acl.game.stashWithdraw then
    return acl.game.stashWithdraw(itemId, count)
  end
  if g_game and g_game.stashWithdraw then
    return g_game.stashWithdraw(itemId, count)
  end
end

function ClientService.stashStowItem(item, count)
  local acl = loadACL()
  if acl and acl.game and acl.game.stashStowItem then
    return acl.game.stashStowItem(item, count)
  end
  if g_game and g_game.stashStowItem then
    return g_game.stashStowItem(item, count)
  end
end

function ClientService.stashStowAll(item)
  local acl = loadACL()
  if acl and acl.game and acl.game.stashStowAll then
    return acl.game.stashStowAll(item)
  end
  if g_game and g_game.stashStowAll then
    return g_game.stashStowAll(item)
  end
end

function ClientService.openStash()
  local acl = loadACL()
  if acl and acl.game and acl.game.openStash then
    return acl.game.openStash()
  end
  if g_game and g_game.openStash then
    return g_game.openStash()
  end
end

function ClientService.requestStashSearch(itemId)
  local acl = loadACL()
  if acl and acl.game and acl.game.requestStashSearch then
    return acl.game.requestStashSearch(itemId)
  end
  if g_game and g_game.requestStashSearch then
    return g_game.requestStashSearch(itemId)
  end
end

--------------------------------------------------------------------------------
-- QUICK LOOT OPERATIONS
--------------------------------------------------------------------------------

function ClientService.sendQuickLoot(pos)
  local acl = loadACL()
  if acl and acl.game and acl.game.sendQuickLoot then
    return acl.game.sendQuickLoot(pos)
  end
  if g_game and g_game.sendQuickLoot then
    return g_game.sendQuickLoot(pos)
  end
end

function ClientService.quickLootCorpse(tile)
  local acl = loadACL()
  if acl and acl.game and acl.game.quickLootCorpse then
    return acl.game.quickLootCorpse(tile)
  end
  if g_game and g_game.quickLootCorpse then
    return g_game.quickLootCorpse(tile)
  end
end

function ClientService.setQuickLootFallback(enabled)
  local acl = loadACL()
  if acl and acl.game and acl.game.setQuickLootFallback then
    return acl.game.setQuickLootFallback(enabled)
  end
  if g_game and g_game.setQuickLootFallback then
    return g_game.setQuickLootFallback(enabled)
  end
end

--------------------------------------------------------------------------------
-- IMBUEMENT OPERATIONS
--------------------------------------------------------------------------------

function ClientService.imbuementDurations()
  local acl = loadACL()
  if acl and acl.game and acl.game.imbuementDurations then
    return acl.game.imbuementDurations()
  end
  if g_game and g_game.imbuementDurations then
    return g_game.imbuementDurations()
  end
  return {}
end

function ClientService.applyImbuement(slotId, imbuementId, usedProtection)
  local acl = loadACL()
  if acl and acl.game and acl.game.applyImbuement then
    return acl.game.applyImbuement(slotId, imbuementId, usedProtection)
  end
  if g_game and g_game.applyImbuement then
    return g_game.applyImbuement(slotId, imbuementId, usedProtection or false)
  end
end

function ClientService.clearImbuement(slotId)
  local acl = loadACL()
  if acl and acl.game and acl.game.clearImbuement then
    return acl.game.clearImbuement(slotId)
  end
  if g_game and g_game.clearImbuement then
    return g_game.clearImbuement(slotId)
  end
end

function ClientService.requestImbuingWindow(item)
  local acl = loadACL()
  if acl and acl.game and acl.game.requestImbuingWindow then
    return acl.game.requestImbuingWindow(item)
  end
  if g_game and g_game.requestImbuingWindow then
    return g_game.requestImbuingWindow(item)
  end
end

function ClientService.closeImbuingWindow()
  local acl = loadACL()
  if acl and acl.game and acl.game.closeImbuingWindow then
    return acl.game.closeImbuingWindow()
  end
  if g_game and g_game.closeImbuingWindow then
    return g_game.closeImbuingWindow()
  end
end

--------------------------------------------------------------------------------
-- PREY OPERATIONS
--------------------------------------------------------------------------------

function ClientService.preyAction(slotId, actionType, bonusType, monsterIndex)
  local acl = loadACL()
  if acl and acl.game and acl.game.preyAction then
    return acl.game.preyAction(slotId, actionType, bonusType, monsterIndex)
  end
  if g_game and g_game.preyAction then
    return g_game.preyAction(slotId, actionType, bonusType or 0, monsterIndex or 0)
  end
end

function ClientService.requestPreyData()
  local acl = loadACL()
  if acl and acl.game and acl.game.requestPreyData then
    return acl.game.requestPreyData()
  end
  if g_game and g_game.requestPreyData then
    return g_game.requestPreyData()
  end
end

function ClientService.selectPreyCreature(slotId, creatureIndex)
  local acl = loadACL()
  if acl and acl.game and acl.game.selectPreyCreature then
    return acl.game.selectPreyCreature(slotId, creatureIndex)
  end
  if g_game and g_game.selectPreyCreature then
    return g_game.selectPreyCreature(slotId, creatureIndex)
  end
end

function ClientService.refreshPreyMonsters(slotId)
  local acl = loadACL()
  if acl and acl.game and acl.game.refreshPreyMonsters then
    return acl.game.refreshPreyMonsters(slotId)
  end
  if g_game and g_game.refreshPreyMonsters then
    return g_game.refreshPreyMonsters(slotId)
  end
end

--------------------------------------------------------------------------------
-- FORGE OPERATIONS
--------------------------------------------------------------------------------

function ClientService.forgeRequest(action, ...)
  local acl = loadACL()
  if acl and acl.game and acl.game.forgeRequest then
    return acl.game.forgeRequest(action, ...)
  end
  if g_game and g_game.forgeRequest then
    return g_game.forgeRequest(action, ...)
  end
end

function ClientService.forgeFuse(firstItem, secondItem, usedCore)
  local acl = loadACL()
  if acl and acl.game and acl.game.forgeFuse then
    return acl.game.forgeFuse(firstItem, secondItem, usedCore)
  end
  if g_game and g_game.forgeFuse then
    return g_game.forgeFuse(firstItem, secondItem, usedCore or false)
  end
end

function ClientService.forgeTransfer(donorItem, receiverItem, usedCore)
  local acl = loadACL()
  if acl and acl.game and acl.game.forgeTransfer then
    return acl.game.forgeTransfer(donorItem, receiverItem, usedCore)
  end
  if g_game and g_game.forgeTransfer then
    return g_game.forgeTransfer(donorItem, receiverItem, usedCore or false)
  end
end

function ClientService.openForge()
  local acl = loadACL()
  if acl and acl.game and acl.game.openForge then
    return acl.game.openForge()
  end
  if g_game and g_game.openForge then
    return g_game.openForge()
  end
end

--------------------------------------------------------------------------------
-- MARKET OPERATIONS
--------------------------------------------------------------------------------

function ClientService.browseMarket(category, vocation)
  local acl = loadACL()
  if acl and acl.game and acl.game.browseMarket then
    return acl.game.browseMarket(category, vocation)
  end
  if g_game and g_game.browseMarket then
    return g_game.browseMarket(category or 0, vocation or 0)
  end
end

function ClientService.createMarketOffer(offerType, itemId, amount, price, anonymous)
  local acl = loadACL()
  if acl and acl.game and acl.game.createMarketOffer then
    return acl.game.createMarketOffer(offerType, itemId, amount, price, anonymous)
  end
  if g_game and g_game.createMarketOffer then
    return g_game.createMarketOffer(offerType, itemId, amount, price, anonymous or false)
  end
end

function ClientService.cancelMarketOffer(offerId)
  local acl = loadACL()
  if acl and acl.game and acl.game.cancelMarketOffer then
    return acl.game.cancelMarketOffer(offerId)
  end
  if g_game and g_game.cancelMarketOffer then
    return g_game.cancelMarketOffer(offerId)
  end
end

function ClientService.acceptMarketOffer(offerId, amount)
  local acl = loadACL()
  if acl and acl.game and acl.game.acceptMarketOffer then
    return acl.game.acceptMarketOffer(offerId, amount)
  end
  if g_game and g_game.acceptMarketOffer then
    return g_game.acceptMarketOffer(offerId, amount)
  end
end

function ClientService.requestMarketInfo(itemId)
  local acl = loadACL()
  if acl and acl.game and acl.game.requestMarketInfo then
    return acl.game.requestMarketInfo(itemId)
  end
  if g_game and g_game.requestMarketInfo then
    return g_game.requestMarketInfo(itemId)
  end
end

--------------------------------------------------------------------------------
-- MODAL DIALOG OPERATIONS
--------------------------------------------------------------------------------

function ClientService.answerModalDialog(dialogId, buttonId, choiceId)
  local acl = loadACL()
  if acl and acl.game and acl.game.answerModalDialog then
    return acl.game.answerModalDialog(dialogId, buttonId, choiceId)
  end
  if g_game and g_game.answerModalDialog then
    return g_game.answerModalDialog(dialogId, buttonId, choiceId or 0)
  end
end

--------------------------------------------------------------------------------
-- BROWSE/INSPECTION OPERATIONS
--------------------------------------------------------------------------------

function ClientService.browseField(pos)
  local acl = loadACL()
  if acl and acl.game and acl.game.browseField then
    return acl.game.browseField(pos)
  end
  if g_game and g_game.browseField then
    return g_game.browseField(pos)
  end
end

function ClientService.inspectionNormalObject(thing)
  local acl = loadACL()
  if acl and acl.game and acl.game.inspectionNormalObject then
    return acl.game.inspectionNormalObject(thing)
  end
  if g_game and g_game.inspectionNormalObject then
    return g_game.inspectionNormalObject(thing)
  end
end

function ClientService.inspectionObject(inspectionType, id, count)
  local acl = loadACL()
  if acl and acl.game and acl.game.inspectionObject then
    return acl.game.inspectionObject(inspectionType, id, count)
  end
  if g_game and g_game.inspectionObject then
    return g_game.inspectionObject(inspectionType, id, count or 1)
  end
end

--------------------------------------------------------------------------------
-- CONTAINER OPERATIONS (Enhanced)
--------------------------------------------------------------------------------

function ClientService.refreshContainer(container)
  local acl = loadACL()
  if acl and acl.game and acl.game.refreshContainer then
    return acl.game.refreshContainer(container)
  end
  if g_game and g_game.refreshContainer then
    return g_game.refreshContainer(container)
  end
end

function ClientService.requestContainerQueue()
  local acl = loadACL()
  if acl and acl.game and acl.game.requestContainerQueue then
    return acl.game.requestContainerQueue()
  end
  if g_game and g_game.requestContainerQueue then
    return g_game.requestContainerQueue()
  end
end

function ClientService.openContainerAt(thing, pos)
  local acl = loadACL()
  if acl and acl.game and acl.game.openContainerAt then
    return acl.game.openContainerAt(thing, pos)
  end
  if g_game and g_game.openContainerAt then
    return g_game.openContainerAt(thing, pos)
  end
end

--------------------------------------------------------------------------------
-- NPC TRADE OPERATIONS (Enhanced)
--------------------------------------------------------------------------------

function ClientService.buyItem(item, amount, ignoreCapacity, buyWithBackpack)
  local acl = loadACL()
  if acl and acl.game and acl.game.buyItem then
    return acl.game.buyItem(item, amount, ignoreCapacity, buyWithBackpack)
  end
  if g_game and g_game.buyItem then
    return g_game.buyItem(item, amount or 1, ignoreCapacity or false, buyWithBackpack or false)
  end
end

function ClientService.sellItem(item, amount, ignoreEquipped)
  local acl = loadACL()
  if acl and acl.game and acl.game.sellItem then
    return acl.game.sellItem(item, amount, ignoreEquipped)
  end
  if g_game and g_game.sellItem then
    return g_game.sellItem(item, amount or 1, ignoreEquipped or false)
  end
end

function ClientService.requestNPCTrade(creature)
  local acl = loadACL()
  if acl and acl.game and acl.game.requestNPCTrade then
    return acl.game.requestNPCTrade(creature)
  end
  if g_game and g_game.requestNPCTrade then
    return g_game.requestNPCTrade(creature)
  end
end

function ClientService.closeNPCTrade()
  local acl = loadACL()
  if acl and acl.game and acl.game.closeNPCTrade then
    return acl.game.closeNPCTrade()
  end
  if g_game and g_game.closeNPCTrade then
    return g_game.closeNPCTrade()
  end
end

--------------------------------------------------------------------------------
-- BLESSINGS
--------------------------------------------------------------------------------

function ClientService.requestBless()
  local acl = loadACL()
  if acl and acl.game and acl.game.requestBless then
    return acl.game.requestBless()
  end
  if g_game and g_game.requestBless then
    return g_game.requestBless()
  end
end

--------------------------------------------------------------------------------
-- OUTFIT OPERATIONS (Enhanced)
--------------------------------------------------------------------------------

function ClientService.requestOutfitChange()
  local acl = loadACL()
  if acl and acl.game and acl.game.requestOutfitChange then
    return acl.game.requestOutfitChange()
  end
  if g_game and g_game.requestOutfitChange then
    return g_game.requestOutfitChange()
  end
end

function ClientService.mountCreature(mount)
  local acl = loadACL()
  if acl and acl.game and acl.game.mountCreature then
    return acl.game.mountCreature(mount)
  end
  if g_game and g_game.mountCreature then
    return g_game.mountCreature(mount)
  end
end

function ClientService.requestMounts()
  local acl = loadACL()
  if acl and acl.game and acl.game.requestMounts then
    return acl.game.requestMounts()
  end
  if g_game and g_game.requestMounts then
    return g_game.requestMounts()
  end
end

--------------------------------------------------------------------------------
-- CYCLOPEDIA OPERATIONS
--------------------------------------------------------------------------------

function ClientService.requestCyclopediaMapData(pos, zoomLevel)
  local acl = loadACL()
  if acl and acl.game and acl.game.requestCyclopediaMapData then
    return acl.game.requestCyclopediaMapData(pos, zoomLevel)
  end
  if g_game and g_game.requestCyclopediaMapData then
    return g_game.requestCyclopediaMapData(pos, zoomLevel or 0)
  end
end

function ClientService.requestCharacterInfo(type)
  local acl = loadACL()
  if acl and acl.game and acl.game.requestCharacterInfo then
    return acl.game.requestCharacterInfo(type)
  end
  if g_game and g_game.requestCharacterInfo then
    return g_game.requestCharacterInfo(type or 0)
  end
end

--------------------------------------------------------------------------------
-- PARTY OPERATIONS (Enhanced)
--------------------------------------------------------------------------------

function ClientService.requestPartySharedExperience(enable)
  local acl = loadACL()
  if acl and acl.game and acl.game.requestPartySharedExperience then
    return acl.game.requestPartySharedExperience(enable)
  end
  if g_game and g_game.requestPartySharedExperience then
    return g_game.requestPartySharedExperience(enable)
  end
end

function ClientService.passPartyLeadership(creature)
  local acl = loadACL()
  if acl and acl.game and acl.game.passPartyLeadership then
    return acl.game.passPartyLeadership(creature)
  end
  if g_game and g_game.passPartyLeadership then
    return g_game.passPartyLeadership(creature)
  end
end

--------------------------------------------------------------------------------
-- ENHANCED MAP OPERATIONS
--------------------------------------------------------------------------------

function ClientService.findEveryPath(startPos, destinations, maxSteps, flags)
  local acl = loadACL()
  if acl and acl.map and acl.map.findEveryPath then
    return acl.map.findEveryPath(startPos, destinations, maxSteps, flags)
  end
  if g_map and g_map.findEveryPath then
    return g_map.findEveryPath(startPos, destinations, maxSteps or 50, flags or 0)
  end
  return {}
end

function ClientService.getSpectatorsInRangeEx(pos, multifloor, minRangeX, maxRangeX, minRangeY, maxRangeY)
  local acl = loadACL()
  if acl and acl.map and acl.map.getSpectatorsInRangeEx then
    return acl.map.getSpectatorsInRangeEx(pos, multifloor, minRangeX, maxRangeX, minRangeY, maxRangeY)
  end
  if g_map and g_map.getSpectatorsInRangeEx then
    return g_map.getSpectatorsInRangeEx(pos, multifloor, minRangeX, maxRangeX, minRangeY, maxRangeY) or {}
  end
  return ClientService.getSpectators(pos, multifloor)
end

function ClientService.getSightSpectators(pos, multifloor)
  local acl = loadACL()
  if acl and acl.map and acl.map.getSightSpectators then
    return acl.map.getSightSpectators(pos, multifloor)
  end
  if g_map and g_map.getSightSpectators then
    return g_map.getSightSpectators(pos, multifloor) or {}
  end
  return ClientService.getSpectators(pos, multifloor)
end

function ClientService.getSpectatorsByPattern(pos, pattern, width, height, firstFloor, lastFloor)
  local acl = loadACL()
  if acl and acl.map and acl.map.getSpectatorsByPattern then
    return acl.map.getSpectatorsByPattern(pos, pattern, width, height, firstFloor, lastFloor)
  end
  if g_map and g_map.getSpectatorsByPattern then
    return g_map.getSpectatorsByPattern(pos, pattern, width, height, firstFloor, lastFloor) or {}
  end
  return {}
end

function ClientService.getCreatureById(creatureId)
  local acl = loadACL()
  if acl and acl.map and acl.map.getCreatureById then
    return acl.map.getCreatureById(creatureId)
  end
  if g_map and g_map.getCreatureById then
    return g_map.getCreatureById(creatureId)
  end
  return nil
end

function ClientService.isAwareOfPosition(pos)
  local acl = loadACL()
  if acl and acl.map and acl.map.isAwareOfPosition then
    return acl.map.isAwareOfPosition(pos)
  end
  if g_map and g_map.isAwareOfPosition then
    return g_map.isAwareOfPosition(pos)
  end
  return false
end

function ClientService.findItemsById(itemId, multifloor)
  local acl = loadACL()
  if acl and acl.map and acl.map.findItemsById then
    return acl.map.findItemsById(itemId, multifloor)
  end
  if g_map and g_map.findItemsById then
    return g_map.findItemsById(itemId, multifloor or false) or {}
  end
  return {}
end

function ClientService.getTilesInRange(pos, rangeX, rangeY, multifloor)
  local acl = loadACL()
  if acl and acl.map and acl.map.getTilesInRange then
    return acl.map.getTilesInRange(pos, rangeX, rangeY, multifloor)
  end
  if g_map and g_map.getTilesInRange then
    return g_map.getTilesInRange(pos, rangeX, rangeY, multifloor or false) or {}
  end
  -- Fallback implementation
  local tiles = {}
  for x = pos.x - rangeX, pos.x + rangeX do
    for y = pos.y - rangeY, pos.y + rangeY do
      local tile = ClientService.getTile({x = x, y = y, z = pos.z})
      if tile then
        table.insert(tiles, tile)
      end
    end
  end
  return tiles
end

function ClientService.cleanTile(pos)
  local acl = loadACL()
  if acl and acl.map and acl.map.cleanTile then
    return acl.map.cleanTile(pos)
  end
  if g_map and g_map.cleanTile then
    return g_map.cleanTile(pos)
  end
end

function ClientService.setMinimapColor(pos, color, description)
  local acl = loadACL()
  if acl and acl.map and acl.map.setMinimapColor then
    return acl.map.setMinimapColor(pos, color, description)
  end
  if g_map and g_map.setMinimapColor then
    return g_map.setMinimapColor(pos, color, description)
  end
end

--------------------------------------------------------------------------------
-- BESTIARY OPERATIONS
--------------------------------------------------------------------------------

function ClientService.requestBestiary()
  local acl = loadACL()
  if acl and acl.bestiary and acl.bestiary.request then
    return acl.bestiary.request()
  end
  if g_game and g_game.requestBestiary then
    return g_game.requestBestiary()
  end
end

function ClientService.requestBestiaryOverview(raceName)
  local acl = loadACL()
  if acl and acl.bestiary and acl.bestiary.requestOverview then
    return acl.bestiary.requestOverview(raceName)
  end
  if g_game and g_game.requestBestiaryOverview then
    return g_game.requestBestiaryOverview(raceName)
  end
end

function ClientService.requestBestiarySearch(text)
  local acl = loadACL()
  if acl and acl.bestiary and acl.bestiary.search then
    return acl.bestiary.search(text)
  end
  if g_game and g_game.requestBestiarySearch then
    return g_game.requestBestiarySearch(text)
  end
end

--------------------------------------------------------------------------------
-- BOSSTIARY OPERATIONS
--------------------------------------------------------------------------------

function ClientService.requestBosstiaryInfo()
  local acl = loadACL()
  if acl and acl.bosstiary and acl.bosstiary.requestInfo then
    return acl.bosstiary.requestInfo()
  end
  if g_game and g_game.requestBosstiaryInfo then
    return g_game.requestBosstiaryInfo()
  end
end

function ClientService.requestBossSlootInfo()
  local acl = loadACL()
  if acl and acl.bosstiary and acl.bosstiary.requestSlotInfo then
    return acl.bosstiary.requestSlotInfo()
  end
  if g_game and g_game.requestBossSlootInfo then
    return g_game.requestBossSlootInfo()
  end
end

--------------------------------------------------------------------------------
-- ADDITIONAL CALLBACKS FOR OPENTIBIABR
--------------------------------------------------------------------------------

function ClientService.onImbuementWindow(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onImbuementWindow then
    return acl.callbacks.onImbuementWindow(callback)
  end
  if onImbuementWindow then
    return onImbuementWindow(callback)
  end
end

function ClientService.onForgeResult(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onForgeResult then
    return acl.callbacks.onForgeResult(callback)
  end
  if onForgeResult then
    return onForgeResult(callback)
  end
end

function ClientService.onPreyData(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onPreyData then
    return acl.callbacks.onPreyData(callback)
  end
  if onPreyData then
    return onPreyData(callback)
  end
end

function ClientService.onMarketBrowse(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onMarketBrowse then
    return acl.callbacks.onMarketBrowse(callback)
  end
  if onMarketBrowse then
    return onMarketBrowse(callback)
  end
end

function ClientService.onMarketOffer(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onMarketOffer then
    return acl.callbacks.onMarketOffer(callback)
  end
  if onMarketOffer then
    return onMarketOffer(callback)
  end
end

function ClientService.onStashAction(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onStashAction then
    return acl.callbacks.onStashAction(callback)
  end
  if onStashAction then
    return onStashAction(callback)
  end
end

function ClientService.onBestiaryData(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onBestiaryData then
    return acl.callbacks.onBestiaryData(callback)
  end
  if onBestiaryData then
    return onBestiaryData(callback)
  end
end

function ClientService.onModalDialog(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onModalDialog then
    return acl.callbacks.onModalDialog(callback)
  end
  if onModalDialog then
    return onModalDialog(callback)
  end
end

function ClientService.onAttackingCreatureChange(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onAttackingCreatureChange then
    return acl.callbacks.onAttackingCreatureChange(callback)
  end
  if onAttackingCreatureChange then
    return onAttackingCreatureChange(callback)
  end
end

function ClientService.onInventoryChange(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onInventoryChange then
    return acl.callbacks.onInventoryChange(callback)
  end
  if onInventoryChange then
    return onInventoryChange(callback)
  end
end

function ClientService.onManaChange(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onManaChange then
    return acl.callbacks.onManaChange(callback)
  end
  if onManaChange then
    return onManaChange(callback)
  end
end

function ClientService.onStatesChange(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onStatesChange then
    return acl.callbacks.onStatesChange(callback)
  end
  if onStatesChange then
    return onStatesChange(callback)
  end
end

function ClientService.onWalk(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onWalk then
    return acl.callbacks.onWalk(callback)
  end
  if onWalk then
    return onWalk(callback)
  end
end

function ClientService.onAddThing(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onAddThing then
    return acl.callbacks.onAddThing(callback)
  end
  if onAddThing then
    return onAddThing(callback)
  end
end

function ClientService.onRemoveThing(callback)
  local acl = loadACL()
  if acl and acl.callbacks and acl.callbacks.onRemoveThing then
    return acl.callbacks.onRemoveThing(callback)
  end
  if onRemoveThing then
    return onRemoveThing(callback)
  end
end

-- Make it globally accessible (use rawset to avoid errors if _G doesn't exist)
if rawset then
  pcall(function() rawset(_G, 'ClientService', ClientService) end)
end

-- Also export as global in bot environment
ClientService = ClientService

-- Global helper function for easy access (DRY pattern)
-- This replaces the duplicated local getClient() in each file
function getClient()
  return ClientService
end

-- Make getClient globally accessible too
if rawset then
  pcall(function() rawset(_G, 'getClient', getClient) end)
end

return ClientService
