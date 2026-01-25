--[[
  nExBot ACL - Base Adapter
  
  Provides the base implementation that all client adapters extend.
  Contains shared logic and default implementations.
  
  Principles:
  - DRY: Common logic shared across adapters
  - Liskov Substitution: Derived adapters can replace base
]]

local BaseAdapter = {}

--------------------------------------------------------------------------------
-- GAME OPERATIONS
--------------------------------------------------------------------------------

BaseAdapter.game = {}

-- Default implementations that work for most clients
function BaseAdapter.game.isOnline()
  return g_game and g_game.isOnline and g_game.isOnline() or false
end

function BaseAdapter.game.isDead()
  return g_game and g_game.isDead and g_game.isDead() or false
end

function BaseAdapter.game.isAttacking()
  return g_game and g_game.isAttacking and g_game.isAttacking() or false
end

function BaseAdapter.game.isFollowing()
  return g_game and g_game.isFollowing and g_game.isFollowing() or false
end

function BaseAdapter.game.getLocalPlayer()
  return g_game and g_game.getLocalPlayer and g_game.getLocalPlayer() or nil
end

function BaseAdapter.game.attack(creature)
  if g_game and g_game.attack then
    return g_game.attack(creature)
  end
end

function BaseAdapter.game.cancelAttack()
  if g_game and g_game.cancelAttack then
    return g_game.cancelAttack()
  end
end

function BaseAdapter.game.follow(creature)
  if g_game and g_game.follow then
    return g_game.follow(creature)
  end
end

function BaseAdapter.game.cancelFollow()
  if g_game and g_game.cancelFollow then
    return g_game.cancelFollow()
  end
end

function BaseAdapter.game.cancelAttackAndFollow()
  if g_game and g_game.cancelAttackAndFollow then
    return g_game.cancelAttackAndFollow()
  end
end

function BaseAdapter.game.walk(direction)
  if g_game and g_game.walk then
    return g_game.walk(direction)
  end
  return false
end

function BaseAdapter.game.turn(direction)
  if g_game and g_game.turn then
    return g_game.turn(direction)
  end
end

function BaseAdapter.game.stop()
  if g_game and g_game.stop then
    return g_game.stop()
  end
end

function BaseAdapter.game.look(thing)
  if g_game and g_game.look then
    return g_game.look(thing)
  end
end

function BaseAdapter.game.move(thing, toPosition, count)
  if g_game and g_game.move then
    return g_game.move(thing, toPosition, count or 1)
  end
end

function BaseAdapter.game.use(thing)
  if g_game and g_game.use then
    return g_game.use(thing)
  end
end

function BaseAdapter.game.useWith(item, target)
  if g_game and g_game.useWith then
    return g_game.useWith(item, target)
  end
end

function BaseAdapter.game.useInventoryItem(itemId)
  if g_game and g_game.useInventoryItem then
    return g_game.useInventoryItem(itemId)
  end
end

function BaseAdapter.game.rotate(thing)
  if g_game and g_game.rotate then
    return g_game.rotate(thing)
  end
end

function BaseAdapter.game.talk(message)
  if g_game and g_game.talk then
    return g_game.talk(message)
  end
end

function BaseAdapter.game.talkChannel(mode, channelId, message)
  if g_game and g_game.talkChannel then
    return g_game.talkChannel(mode, channelId, message)
  end
end

function BaseAdapter.game.talkPrivate(mode, receiver, message)
  if g_game and g_game.talkPrivate then
    return g_game.talkPrivate(mode, receiver, message)
  end
end

function BaseAdapter.game.requestChannels()
  if g_game and g_game.requestChannels then
    return g_game.requestChannels()
  end
end

function BaseAdapter.game.joinChannel(channelId)
  if g_game and g_game.joinChannel then
    return g_game.joinChannel(channelId)
  end
end

function BaseAdapter.game.leaveChannel(channelId)
  if g_game and g_game.leaveChannel then
    return g_game.leaveChannel(channelId)
  end
end

function BaseAdapter.game.open(item, previousContainer)
  if g_game and g_game.open then
    return g_game.open(item, previousContainer)
  end
end

function BaseAdapter.game.openParent(container)
  if g_game and g_game.openParent then
    return g_game.openParent(container)
  end
end

function BaseAdapter.game.close(container)
  if g_game and g_game.close then
    return g_game.close(container)
  end
end

function BaseAdapter.game.refreshContainer(container)
  if g_game and g_game.refreshContainer then
    return g_game.refreshContainer(container)
  end
end

function BaseAdapter.game.getAttackingCreature()
  return g_game and g_game.getAttackingCreature and g_game.getAttackingCreature() or nil
end

function BaseAdapter.game.getFollowingCreature()
  return g_game and g_game.getFollowingCreature and g_game.getFollowingCreature() or nil
end

function BaseAdapter.game.getContainer(id)
  return g_game and g_game.getContainer and g_game.getContainer(id) or nil
end

function BaseAdapter.game.getContainers()
  return g_game and g_game.getContainers and g_game.getContainers() or {}
end

function BaseAdapter.game.getClientVersion()
  return g_game and g_game.getClientVersion and g_game.getClientVersion() or 0
end

function BaseAdapter.game.getProtocolVersion()
  return g_game and g_game.getProtocolVersion and g_game.getProtocolVersion() or 0
end

function BaseAdapter.game.getFeature(feature)
  return g_game and g_game.getFeature and g_game.getFeature(feature) or false
end

function BaseAdapter.game.enableFeature(feature)
  if g_game and g_game.enableFeature then
    return g_game.enableFeature(feature)
  end
end

function BaseAdapter.game.disableFeature(feature)
  if g_game and g_game.disableFeature then
    return g_game.disableFeature(feature)
  end
end

function BaseAdapter.game.getChaseMode()
  return g_game and g_game.getChaseMode and g_game.getChaseMode() or 0
end

function BaseAdapter.game.getFightMode()
  return g_game and g_game.getFightMode and g_game.getFightMode() or 0
end

function BaseAdapter.game.setChaseMode(mode)
  if g_game and g_game.setChaseMode then
    return g_game.setChaseMode(mode)
  end
end

function BaseAdapter.game.setFightMode(mode)
  if g_game and g_game.setFightMode then
    return g_game.setFightMode(mode)
  end
end

function BaseAdapter.game.isSafeFight()
  return g_game and g_game.isSafeFight and g_game.isSafeFight() or false
end

function BaseAdapter.game.setSafeFight(safe)
  if g_game and g_game.setSafeFight then
    return g_game.setSafeFight(safe)
  end
end

function BaseAdapter.game.buyItem(item, count, ignoreEquipped, ignoreCap)
  if g_game and g_game.buyItem then
    return g_game.buyItem(item, count, ignoreEquipped, ignoreCap)
  end
end

function BaseAdapter.game.sellItem(item, count)
  if g_game and g_game.sellItem then
    return g_game.sellItem(item, count)
  end
end

function BaseAdapter.game.closeNpcTrade()
  if g_game and g_game.closeNpcTrade then
    return g_game.closeNpcTrade()
  end
end

function BaseAdapter.game.getUnjustifiedPoints()
  return g_game and g_game.getUnjustifiedPoints and g_game.getUnjustifiedPoints() or {}
end

function BaseAdapter.game.getPing()
  return g_game and g_game.getPing and g_game.getPing() or 0
end

function BaseAdapter.game.equipItem(item)
  if g_game and g_game.equipItem then
    return g_game.equipItem(item)
  end
end

function BaseAdapter.game.requestOutfit()
  if g_game and g_game.requestOutfit then
    return g_game.requestOutfit()
  end
end

function BaseAdapter.game.changeOutfit(outfit)
  if g_game and g_game.changeOutfit then
    return g_game.changeOutfit(outfit)
  end
end

-- Extended inventory operations
function BaseAdapter.game.useInventoryItemWith(itemId, target)
  if g_game and g_game.useInventoryItemWith then
    return g_game.useInventoryItemWith(itemId, target)
  end
end

function BaseAdapter.game.findPlayerItem(itemId, subType)
  if g_game and g_game.findPlayerItem then
    return g_game.findPlayerItem(itemId, subType)
  end
  return nil
end

function BaseAdapter.game.findItemInContainers(itemId, subType)
  if g_game and g_game.findItemInContainers then
    return g_game.findItemInContainers(itemId, subType)
  end
  return nil
end

function BaseAdapter.game.equipItemId(itemId, destSlot)
  if g_game and g_game.equipItemId then
    return g_game.equipItemId(itemId, destSlot)
  end
end

-- Mount operations
function BaseAdapter.game.mount(mount)
  if g_game and g_game.mount then
    return g_game.mount(mount)
  end
end

function BaseAdapter.game.dismount()
  if g_game and g_game.dismount then
    return g_game.dismount()
  end
end

-- Party operations
function BaseAdapter.game.partyInvite(creatureId)
  if g_game and g_game.partyInvite then
    return g_game.partyInvite(creatureId)
  end
end

function BaseAdapter.game.partyJoin(creatureId)
  if g_game and g_game.partyJoin then
    return g_game.partyJoin(creatureId)
  end
end

function BaseAdapter.game.partyLeave()
  if g_game and g_game.partyLeave then
    return g_game.partyLeave()
  end
end

-- Seek in container
function BaseAdapter.game.seekInContainer(container, index)
  if g_game and g_game.seekInContainer then
    return g_game.seekInContainer(container, index)
  end
end

-- Logout operations
function BaseAdapter.game.safeLogout()
  if g_game and g_game.safeLogout then
    return g_game.safeLogout()
  end
end

function BaseAdapter.game.forceLogout()
  if g_game and g_game.forceLogout then
    return g_game.forceLogout()
  end
end

-- Talk local
function BaseAdapter.game.talkLocal(message)
  if g_game and g_game.talkLocal then
    return g_game.talkLocal(message)
  end
  -- Fallback to talk
  return BaseAdapter.game.talk(message)
end

--------------------------------------------------------------------------------
-- MAP OPERATIONS
--------------------------------------------------------------------------------

BaseAdapter.map = {}

function BaseAdapter.map.getTile(pos)
  return g_map and g_map.getTile and g_map.getTile(pos) or nil
end

function BaseAdapter.map.getTiles(floor)
  return g_map and g_map.getTiles and g_map.getTiles(floor) or {}
end

function BaseAdapter.map.getMinimapColor(pos)
  return g_map and g_map.getMinimapColor and g_map.getMinimapColor(pos) or 0
end

function BaseAdapter.map.getSpectatorsInRange(pos, xRange, yRange, multifloor)
  if g_map and g_map.getSpectatorsInRange then
    return g_map.getSpectatorsInRange(pos, xRange, yRange, multifloor) or {}
  end
  return {}
end

function BaseAdapter.map.isTileWalkable(pos)
  if g_map and g_map.isTileWalkable then
    return g_map.isTileWalkable(pos)
  end
  local tile = BaseAdapter.map.getTile(pos)
  return tile and tile:isWalkable() or false
end

function BaseAdapter.map.isSightClear(fromPos, toPos, floorCheck)
  return g_map and g_map.isSightClear and g_map.isSightClear(fromPos, toPos, floorCheck) or false
end

function BaseAdapter.map.isLookPossible(pos)
  return g_map and g_map.isLookPossible and g_map.isLookPossible(pos) or false
end

function BaseAdapter.map.cleanDynamicThings()
  if g_map and g_map.cleanDynamicThings then
    return g_map.cleanDynamicThings()
  end
end

-- Abstract: Must be implemented by specific adapters
function BaseAdapter.map.getSpectators(pos, multifloor)
  error("getSpectators must be implemented by specific adapter")
end

function BaseAdapter.map.findPath(startPos, goalPos, options)
  error("findPath must be implemented by specific adapter")
end

--------------------------------------------------------------------------------
-- UI OPERATIONS
--------------------------------------------------------------------------------

BaseAdapter.ui = {}

function BaseAdapter.ui.importStyle(path)
  if g_ui and g_ui.importStyle then
    return g_ui.importStyle(path)
  end
end

function BaseAdapter.ui.createWidget(widgetType, parent)
  if g_ui and g_ui.createWidget then
    return g_ui.createWidget(widgetType, parent)
  end
end

function BaseAdapter.ui.getRootWidget()
  return g_ui and g_ui.getRootWidget and g_ui.getRootWidget() or nil
end

function BaseAdapter.ui.loadUI(path, parent)
  if g_ui and g_ui.loadUI then
    return g_ui.loadUI(path, parent)
  end
end

--------------------------------------------------------------------------------
-- MODULE ACCESS
--------------------------------------------------------------------------------

BaseAdapter.modules = {}

function BaseAdapter.modules.getGameInterface()
  return modules and modules.game_interface or nil
end

function BaseAdapter.modules.getConsole()
  return modules and modules.game_console or nil
end

function BaseAdapter.modules.getCooldown()
  return modules and modules.game_cooldown or nil
end

function BaseAdapter.modules.getBot()
  return modules and modules.game_bot or nil
end

function BaseAdapter.modules.getTerminal()
  return modules and modules.client_terminal or nil
end

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

BaseAdapter.utils = {}

-- Position helper
function BaseAdapter.utils.getPos(x, y, z)
  local p = BaseAdapter.game.getLocalPlayer()
  if p then
    local pos = p:getPosition()
    pos.x = x or pos.x
    pos.y = y or pos.y
    pos.z = z or pos.z
    return pos
  end
  return {x = x or 0, y = y or 0, z = z or 0}
end

-- Distance calculation
function BaseAdapter.utils.getDistanceBetween(pos1, pos2)
  if not pos1 or not pos2 then return 999 end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

-- Same position check
function BaseAdapter.utils.isSamePosition(pos1, pos2)
  if not pos1 or not pos2 then return false end
  return pos1.x == pos2.x and pos1.y == pos2.y and pos1.z == pos2.z
end

-- Check if position is in range
function BaseAdapter.utils.isInRange(pos1, pos2, rangeX, rangeY)
  if not pos1 or not pos2 then return false end
  rangeY = rangeY or rangeX
  return math.abs(pos1.x - pos2.x) <= rangeX and 
         math.abs(pos1.y - pos2.y) <= rangeY and 
         pos1.z == pos2.z
end

--------------------------------------------------------------------------------
-- CALLBACK REGISTRATION
-- Provides unified callback registration that adapters can extend
--------------------------------------------------------------------------------

BaseAdapter.callbacks = {}

-- Stores registered callbacks
BaseAdapter._registeredCallbacks = {}

-- Register a callback
function BaseAdapter.callbacks.register(eventType, callback, priority)
  if not BaseAdapter._registeredCallbacks[eventType] then
    BaseAdapter._registeredCallbacks[eventType] = {}
  end
  
  local entry = {
    callback = callback,
    priority = priority or 0
  }
  
  table.insert(BaseAdapter._registeredCallbacks[eventType], entry)
  
  -- Sort by priority
  table.sort(BaseAdapter._registeredCallbacks[eventType], function(a, b)
    return a.priority > b.priority
  end)
  
  -- Return unsubscribe function
  return function()
    for i, e in ipairs(BaseAdapter._registeredCallbacks[eventType] or {}) do
      if e == entry then
        table.remove(BaseAdapter._registeredCallbacks[eventType], i)
        break
      end
    end
  end
end

-- Emit an event to all registered callbacks
function BaseAdapter.callbacks.emit(eventType, ...)
  local handlers = BaseAdapter._registeredCallbacks[eventType]
  if not handlers then return end
  
  for _, handler in ipairs(handlers) do
    local status, err = pcall(handler.callback, ...)
    if not status then
      warn("[ACL] Callback error in " .. eventType .. ": " .. tostring(err))
    end
  end
end

return BaseAdapter
