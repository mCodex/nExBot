--[[
  nExBot ACL - OpenTibiaBR Adapter
  
  Implements the ACL interfaces for OpenTibiaBR/OTClient Redemption.
  
  OpenTibiaBR Specific Features:
  - Controller:new() pattern for module events
  - g_gameConfig for game configuration
  - Paperdoll system support
  - Protobuf support for modern protocols
  - forceWalk function
  - Enhanced walk system with prewalk
]]

-- Load base adapter
local BaseAdapter = dofile("/core/acl/adapters/base.lua")

-- Create OpenTibiaBR adapter extending base
local OpenTibiaBRAdapter = {}

-- Copy all base adapter properties
for k, v in pairs(BaseAdapter) do
  if type(v) == "table" then
    OpenTibiaBRAdapter[k] = {}
    for k2, v2 in pairs(v) do
      OpenTibiaBRAdapter[k][k2] = v2
    end
  else
    OpenTibiaBRAdapter[k] = v
  end
end

-- Adapter metadata
OpenTibiaBRAdapter.NAME = "OpenTibiaBR"
OpenTibiaBRAdapter.VERSION = "1.0.0"

--------------------------------------------------------------------------------
-- OPENTIBIABR SPECIFIC GAME OPERATIONS
--------------------------------------------------------------------------------

-- OpenTibiaBR has forceWalk for more control
function OpenTibiaBRAdapter.game.forceWalk(direction)
  if g_game and g_game.forceWalk then
    return g_game.forceWalk(direction)
  else
    return BaseAdapter.game.walk(direction)
  end
end

-- OpenTibiaBR autoWalk implementation
function OpenTibiaBRAdapter.game.autoWalk(destination, options)
  if g_game and g_game.autoWalk then
    return g_game.autoWalk(destination, options)
  end
  return false
end

-- OpenTibiaBR setScheduleLastWalk for smooth walking
function OpenTibiaBRAdapter.game.setScheduleLastWalk(schedule)
  if g_game and g_game.setScheduleLastWalk then
    return g_game.setScheduleLastWalk(schedule)
  end
end

-- OpenTibiaBR wrap function
function OpenTibiaBRAdapter.game.wrap(thing)
  if g_game and g_game.wrap then
    return g_game.wrap(thing)
  end
end

-- OpenTibiaBR equipment by ID
function OpenTibiaBRAdapter.game.equipItemId(itemId)
  if g_game and g_game.equipItemId then
    return g_game.equipItemId(itemId)
  end
end

-- OpenTibiaBR quick loot
function OpenTibiaBRAdapter.game.sendQuickLoot(pos)
  if g_game and g_game.sendQuickLoot then
    return g_game.sendQuickLoot(pos)
  end
end

function OpenTibiaBRAdapter.game.quickLootCorpse(tile)
  if g_game and g_game.quickLootCorpse then
    return g_game.quickLootCorpse(tile)
  end
end

function OpenTibiaBRAdapter.game.setQuickLootFallback(enabled)
  if g_game and g_game.setQuickLootFallback then
    return g_game.setQuickLootFallback(enabled)
  end
end

-- OpenTibiaBR stash operations
function OpenTibiaBRAdapter.game.stashWithdraw(itemId, count)
  if g_game and g_game.stashWithdraw then
    return g_game.stashWithdraw(itemId, count)
  end
end

function OpenTibiaBRAdapter.game.stashStowItem(item, count)
  if g_game and g_game.stashStowItem then
    return g_game.stashStowItem(item, count)
  end
end

function OpenTibiaBRAdapter.game.stashStowAll(item)
  if g_game and g_game.stashStowAll then
    return g_game.stashStowAll(item)
  end
end

function OpenTibiaBRAdapter.game.openStash()
  if g_game and g_game.openStash then
    return g_game.openStash()
  end
end

function OpenTibiaBRAdapter.game.requestStashSearch(itemId)
  if g_game and g_game.requestStashSearch then
    return g_game.requestStashSearch(itemId)
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR IMBUEMENT OPERATIONS
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.game.applyImbuement(slotId, imbuementId, usedProtection)
  if g_game and g_game.applyImbuement then
    return g_game.applyImbuement(slotId, imbuementId, usedProtection or false)
  end
end

function OpenTibiaBRAdapter.game.clearImbuement(slotId)
  if g_game and g_game.clearImbuement then
    return g_game.clearImbuement(slotId)
  end
end

function OpenTibiaBRAdapter.game.requestImbuingWindow(item)
  if g_game and g_game.requestImbuingWindow then
    return g_game.requestImbuingWindow(item)
  end
end

function OpenTibiaBRAdapter.game.closeImbuingWindow()
  if g_game and g_game.closeImbuingWindow then
    return g_game.closeImbuingWindow()
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR PREY OPERATIONS
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.game.preyAction(slotId, actionType, bonusType, monsterIndex)
  if g_game and g_game.preyAction then
    return g_game.preyAction(slotId, actionType, bonusType or 0, monsterIndex or 0)
  end
end

function OpenTibiaBRAdapter.game.requestPreyData()
  if g_game and g_game.requestPreyData then
    return g_game.requestPreyData()
  end
end

function OpenTibiaBRAdapter.game.selectPreyCreature(slotId, creatureIndex)
  if g_game and g_game.selectPreyCreature then
    return g_game.selectPreyCreature(slotId, creatureIndex)
  end
end

function OpenTibiaBRAdapter.game.refreshPreyMonsters(slotId)
  if g_game and g_game.refreshPreyMonsters then
    return g_game.refreshPreyMonsters(slotId)
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR FORGE OPERATIONS
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.game.forgeRequest(action, ...)
  if g_game and g_game.forgeRequest then
    return g_game.forgeRequest(action, ...)
  end
end

function OpenTibiaBRAdapter.game.forgeFuse(firstItem, secondItem, usedCore)
  if g_game and g_game.forgeFuse then
    return g_game.forgeFuse(firstItem, secondItem, usedCore or false)
  end
end

function OpenTibiaBRAdapter.game.forgeTransfer(donorItem, receiverItem, usedCore)
  if g_game and g_game.forgeTransfer then
    return g_game.forgeTransfer(donorItem, receiverItem, usedCore or false)
  end
end

function OpenTibiaBRAdapter.game.openForge()
  if g_game and g_game.openForge then
    return g_game.openForge()
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR MARKET OPERATIONS
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.game.browseMarket(category, vocation)
  if g_game and g_game.browseMarket then
    return g_game.browseMarket(category or 0, vocation or 0)
  end
end

function OpenTibiaBRAdapter.game.createMarketOffer(offerType, itemId, amount, price, anonymous)
  if g_game and g_game.createMarketOffer then
    return g_game.createMarketOffer(offerType, itemId, amount, price, anonymous or false)
  end
end

function OpenTibiaBRAdapter.game.cancelMarketOffer(offerId)
  if g_game and g_game.cancelMarketOffer then
    return g_game.cancelMarketOffer(offerId)
  end
end

function OpenTibiaBRAdapter.game.acceptMarketOffer(offerId, amount)
  if g_game and g_game.acceptMarketOffer then
    return g_game.acceptMarketOffer(offerId, amount)
  end
end

function OpenTibiaBRAdapter.game.requestMarketInfo(itemId)
  if g_game and g_game.requestMarketInfo then
    return g_game.requestMarketInfo(itemId)
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR MODAL DIALOG OPERATIONS
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.game.answerModalDialog(dialogId, buttonId, choiceId)
  if g_game and g_game.answerModalDialog then
    return g_game.answerModalDialog(dialogId, buttonId, choiceId or 0)
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR BROWSE/INSPECTION OPERATIONS
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.game.browseField(pos)
  if g_game and g_game.browseField then
    return g_game.browseField(pos)
  end
end

function OpenTibiaBRAdapter.game.inspectionNormalObject(thing)
  if g_game and g_game.inspectionNormalObject then
    return g_game.inspectionNormalObject(thing)
  end
end

function OpenTibiaBRAdapter.game.inspectionObject(inspectionType, id, count)
  if g_game and g_game.inspectionObject then
    return g_game.inspectionObject(inspectionType, id, count or 1)
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR CONTAINER OPERATIONS
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.game.refreshContainer(container)
  if g_game and g_game.refreshContainer then
    return g_game.refreshContainer(container)
  end
end

function OpenTibiaBRAdapter.game.requestContainerQueue()
  if g_game and g_game.requestContainerQueue then
    return g_game.requestContainerQueue()
  end
end

function OpenTibiaBRAdapter.game.openContainerAt(thing, pos)
  if g_game and g_game.openContainerAt then
    return g_game.openContainerAt(thing, pos)
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR OUTFIT OPERATIONS
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.game.requestOutfitChange()
  if g_game and g_game.requestOutfitChange then
    return g_game.requestOutfitChange()
  end
end

function OpenTibiaBRAdapter.game.changeOutfit(outfit)
  if g_game and g_game.changeOutfit then
    return g_game.changeOutfit(outfit)
  end
end

function OpenTibiaBRAdapter.game.mountCreature(mount)
  if g_game and g_game.mountCreature then
    return g_game.mountCreature(mount)
  end
end

function OpenTibiaBRAdapter.game.requestMounts()
  if g_game and g_game.requestMounts then
    return g_game.requestMounts()
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR NPC TRADE OPERATIONS
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.game.buyItem(item, amount, ignoreCapacity, buyWithBackpack)
  if g_game and g_game.buyItem then
    return g_game.buyItem(item, amount or 1, ignoreCapacity or false, buyWithBackpack or false)
  end
end

function OpenTibiaBRAdapter.game.sellItem(item, amount, ignoreEquipped)
  if g_game and g_game.sellItem then
    return g_game.sellItem(item, amount or 1, ignoreEquipped or false)
  end
end

function OpenTibiaBRAdapter.game.requestNPCTrade(creature)
  if g_game and g_game.requestNPCTrade then
    return g_game.requestNPCTrade(creature)
  end
end

function OpenTibiaBRAdapter.game.closeNPCTrade()
  if g_game and g_game.closeNPCTrade then
    return g_game.closeNPCTrade()
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR CYCLOPEDIA OPERATIONS
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.game.requestCyclopediaMapData(pos, zoomLevel)
  if g_game and g_game.requestCyclopediaMapData then
    return g_game.requestCyclopediaMapData(pos, zoomLevel or 0)
  end
end

function OpenTibiaBRAdapter.game.requestCharacterInfo(type)
  if g_game and g_game.requestCharacterInfo then
    return g_game.requestCharacterInfo(type or 0)
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR PARTY OPERATIONS
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.game.requestPartySharedExperience(enable)
  if g_game and g_game.requestPartySharedExperience then
    return g_game.requestPartySharedExperience(enable)
  end
end

function OpenTibiaBRAdapter.game.passPartyLeadership(creature)
  if g_game and g_game.passPartyLeadership then
    return g_game.passPartyLeadership(creature)
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR WALK OPERATIONS (Enhanced)
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.game.enableTileThingLuaCallback(enable)
  if g_game and g_game.enableTileThingLuaCallback then
    return g_game.enableTileThingLuaCallback(enable)
  end
end

function OpenTibiaBRAdapter.game.setWalkFirstStepDelay(delay)
  if g_game and g_game.setWalkFirstStepDelay then
    return g_game.setWalkFirstStepDelay(delay)
  end
end

function OpenTibiaBRAdapter.game.setWalkTurnDelay(delay)
  if g_game and g_game.setWalkTurnDelay then
    return g_game.setWalkTurnDelay(delay)
  end
end

function OpenTibiaBRAdapter.game.setWalkSpeedMultiplier(multiplier)
  if g_game and g_game.setWalkSpeedMultiplier then
    return g_game.setWalkSpeedMultiplier(multiplier)
  end
end

function OpenTibiaBRAdapter.game.getWalkSpeedMultiplier()
  if g_game and g_game.getWalkSpeedMultiplier then
    return g_game.getWalkSpeedMultiplier()
  end
  return 1.0
end

-- OpenTibiaBR blessing request
function OpenTibiaBRAdapter.game.requestBless()
  if g_game and g_game.requestBless then
    return g_game.requestBless()
  end
end

-- OpenTibiaBR imbuement durations
function OpenTibiaBRAdapter.game.imbuementDurations()
  if g_game and g_game.imbuementDurations then
    return g_game.imbuementDurations()
  end
  return {}
end

-- OpenTibiaBR protobuf check
function OpenTibiaBRAdapter.game.isUsingProtobuf()
  if g_game and g_game.isUsingProtobuf then
    return g_game.isUsingProtobuf()
  end
  return false
end

-- OpenTibiaBR walk max steps
function OpenTibiaBRAdapter.game.getWalkMaxSteps()
  if g_game and g_game.getWalkMaxSteps then
    return g_game.getWalkMaxSteps()
  end
  return 10
end

function OpenTibiaBRAdapter.game.setWalkMaxSteps(steps)
  if g_game and g_game.setWalkMaxSteps then
    return g_game.setWalkMaxSteps(steps)
  end
end

-- OpenTibiaBR find item in containers (native function)
function OpenTibiaBRAdapter.game.findItemInContainers(itemId, subType)
  if g_game and g_game.findItemInContainers then
    return g_game.findItemInContainers(itemId, subType)
  end
  return nil
end

--------------------------------------------------------------------------------
-- OPENTIBIABR SPECIFIC MAP OPERATIONS
--------------------------------------------------------------------------------

-- OpenTibiaBR getSpectators
function OpenTibiaBRAdapter.map.getSpectators(pos, multifloor)
  if not g_map then return {} end
  
  -- Use the bot context's getSpectators if available
  if G and G.botContext and G.botContext.getSpectators then
    return G.botContext.getSpectators(pos, multifloor)
  end
  
  -- Fallback to g_map.getSpectators
  if g_map.getSpectators then
    local specs = g_map.getSpectators(pos, multifloor or false)
    return specs or {}
  end
  
  return {}
end

-- OpenTibiaBR getSpectatorsInRange (more precise)
function OpenTibiaBRAdapter.map.getSpectatorsInRange(pos, multifloor, rangeX, rangeY)
  if g_map and g_map.getSpectatorsInRange then
    return g_map.getSpectatorsInRange(pos, multifloor, rangeX, rangeY) or {}
  end
  return OpenTibiaBRAdapter.map.getSpectators(pos, multifloor)
end

-- OpenTibiaBR path finding with more options
function OpenTibiaBRAdapter.map.findPath(startPos, goalPos, options)
  if g_map and g_map.findPath then
    options = options or {}
    return g_map.findPath(startPos, goalPos, options.maxSteps or 50, options.flags or 0)
  end
  return nil
end

-- OpenTibiaBR findEveryPath for multiple destinations
function OpenTibiaBRAdapter.map.findEveryPath(startPos, destinations, maxSteps, flags)
  if g_map and g_map.findEveryPath then
    return g_map.findEveryPath(startPos, destinations, maxSteps or 50, flags or 0)
  end
  return {}
end

-- OpenTibiaBR getSpectatorsInRangeEx (extended version)
function OpenTibiaBRAdapter.map.getSpectatorsInRangeEx(pos, multifloor, minRangeX, maxRangeX, minRangeY, maxRangeY)
  if g_map and g_map.getSpectatorsInRangeEx then
    return g_map.getSpectatorsInRangeEx(pos, multifloor, minRangeX, maxRangeX, minRangeY, maxRangeY) or {}
  end
  return OpenTibiaBRAdapter.map.getSpectators(pos, multifloor)
end

-- OpenTibiaBR getSightSpectators
function OpenTibiaBRAdapter.map.getSightSpectators(pos, multifloor)
  if g_map and g_map.getSightSpectators then
    return g_map.getSightSpectators(pos, multifloor) or {}
  end
  return OpenTibiaBRAdapter.map.getSpectators(pos, multifloor)
end

-- OpenTibiaBR getSpectatorsByPattern
function OpenTibiaBRAdapter.map.getSpectatorsByPattern(pos, pattern, width, height, firstFloor, lastFloor)
  if g_map and g_map.getSpectatorsByPattern then
    return g_map.getSpectatorsByPattern(pos, pattern, width, height, firstFloor, lastFloor) or {}
  end
  return {}
end

-- OpenTibiaBR getCreatureById
function OpenTibiaBRAdapter.map.getCreatureById(creatureId)
  if g_map and g_map.getCreatureById then
    return g_map.getCreatureById(creatureId)
  end
  return nil
end

-- OpenTibiaBR isAwareOfPosition
function OpenTibiaBRAdapter.map.isAwareOfPosition(pos)
  if g_map and g_map.isAwareOfPosition then
    return g_map.isAwareOfPosition(pos)
  end
  return false
end

-- OpenTibiaBR findItemsById
function OpenTibiaBRAdapter.map.findItemsById(itemId, multifloor)
  if g_map and g_map.findItemsById then
    return g_map.findItemsById(itemId, multifloor or false) or {}
  end
  return {}
end

-- OpenTibiaBR getTiles in range
function OpenTibiaBRAdapter.map.getTilesInRange(pos, rangeX, rangeY, multifloor)
  if g_map and g_map.getTilesInRange then
    return g_map.getTilesInRange(pos, rangeX, rangeY, multifloor or false) or {}
  end
  -- Fallback implementation
  local tiles = {}
  for x = pos.x - rangeX, pos.x + rangeX do
    for y = pos.y - rangeY, pos.y + rangeY do
      local tile = g_map.getTile({x = x, y = y, z = pos.z})
      if tile then
        table.insert(tiles, tile)
      end
    end
  end
  return tiles
end

-- OpenTibiaBR cleanTile
function OpenTibiaBRAdapter.map.cleanTile(pos)
  if g_map and g_map.cleanTile then
    return g_map.cleanTile(pos)
  end
end

-- OpenTibiaBR minimapColor
function OpenTibiaBRAdapter.map.getMinimapColor(pos)
  if g_map and g_map.getMinimapColor then
    return g_map.getMinimapColor(pos)
  end
  return 0
end

-- OpenTibiaBR setMinimapColor
function OpenTibiaBRAdapter.map.setMinimapColor(pos, color, description)
  if g_map and g_map.setMinimapColor then
    return g_map.setMinimapColor(pos, color, description)
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR SPECIFIC COOLDOWN OPERATIONS
--------------------------------------------------------------------------------

OpenTibiaBRAdapter.cooldown = {}

function OpenTibiaBRAdapter.cooldown.isCooldownIconActive(iconId)
  local cooldownModule = modules.game_cooldown
  if cooldownModule and cooldownModule.isCooldownIconActive then
    return cooldownModule.isCooldownIconActive(iconId)
  end
  return false
end

function OpenTibiaBRAdapter.cooldown.isGroupCooldownIconActive(groupId)
  local cooldownModule = modules.game_cooldown
  if cooldownModule and cooldownModule.isGroupCooldownIconActive then
    return cooldownModule.isGroupCooldownIconActive(groupId)
  end
  return false
end

--------------------------------------------------------------------------------
-- OPENTIBIABR SPECIFIC BOT OPERATIONS
--------------------------------------------------------------------------------

OpenTibiaBRAdapter.bot = {}

function OpenTibiaBRAdapter.bot.getConfigName()
  -- OpenTibiaBR may use different bot module structure
  local botModule = modules.game_bot
  if botModule then
    -- Try contentsPanel.config pattern first (compatibility)
    if botModule.contentsPanel and botModule.contentsPanel.config then
      local option = botModule.contentsPanel.config:getCurrentOption()
      return option and option.text or nil
    end
    -- Try alternative patterns
    if botModule.getCurrentConfig then
      return botModule.getCurrentConfig()
    end
  end
  return nil
end

function OpenTibiaBRAdapter.bot.getConfigPath()
  local configName = OpenTibiaBRAdapter.bot.getConfigName()
  if configName then
    return "/bot/" .. configName
  end
  return nil
end

--------------------------------------------------------------------------------
-- OPENTIBIABR GAME CONFIG
--------------------------------------------------------------------------------

OpenTibiaBRAdapter.gameConfig = {}

function OpenTibiaBRAdapter.gameConfig.get()
  return g_gameConfig or nil
end

function OpenTibiaBRAdapter.gameConfig.loadFonts(path)
  if g_gameConfig and g_gameConfig.loadFonts then
    return g_gameConfig.loadFonts(path)
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR PAPERDOLL SYSTEM
--------------------------------------------------------------------------------

OpenTibiaBRAdapter.paperdolls = {}

function OpenTibiaBRAdapter.paperdolls.isAvailable()
  return g_paperdolls ~= nil
end

function OpenTibiaBRAdapter.paperdolls.get(id)
  if g_paperdolls and g_paperdolls.get then
    return g_paperdolls.get(id)
  end
  return nil
end

function OpenTibiaBRAdapter.paperdolls.getAll()
  if g_paperdolls and g_paperdolls.getAll then
    return g_paperdolls.getAll()
  end
  return {}
end

function OpenTibiaBRAdapter.paperdolls.clear()
  if g_paperdolls and g_paperdolls.clear then
    return g_paperdolls.clear()
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR CALLBACK WRAPPERS
-- Uses Controller pattern when available
--------------------------------------------------------------------------------

-- Store controller instance for cleanup
local _controller = nil

local function getOrCreateController()
  if _controller then
    return _controller
  end
  
  -- Check if Controller exists (OpenTibiaBR pattern)
  if Controller and Controller.new then
    _controller = Controller:new()
    return _controller
  end
  
  return nil
end

-- These are the native callback registration functions for OpenTibiaBR
function OpenTibiaBRAdapter.callbacks.onCreatureAppear(callback)
  if onCreatureAppear then
    return onCreatureAppear(callback)
  end
  return BaseAdapter.callbacks.register("onCreatureAppear", callback)
end

function OpenTibiaBRAdapter.callbacks.onCreatureDisappear(callback)
  if onCreatureDisappear then
    return onCreatureDisappear(callback)
  end
  return BaseAdapter.callbacks.register("onCreatureDisappear", callback)
end

function OpenTibiaBRAdapter.callbacks.onCreaturePositionChange(callback)
  if onCreaturePositionChange then
    return onCreaturePositionChange(callback)
  end
  return BaseAdapter.callbacks.register("onCreaturePositionChange", callback)
end

function OpenTibiaBRAdapter.callbacks.onCreatureHealthPercentChange(callback)
  if onCreatureHealthPercentChange then
    return onCreatureHealthPercentChange(callback)
  end
  return BaseAdapter.callbacks.register("onCreatureHealthPercentChange", callback)
end

function OpenTibiaBRAdapter.callbacks.onPlayerPositionChange(callback)
  if onPlayerPositionChange then
    return onPlayerPositionChange(callback)
  end
  return BaseAdapter.callbacks.register("onPlayerPositionChange", callback)
end

function OpenTibiaBRAdapter.callbacks.onTalk(callback)
  if onTalk then
    return onTalk(callback)
  end
  return BaseAdapter.callbacks.register("onTalk", callback)
end

function OpenTibiaBRAdapter.callbacks.onTextMessage(callback)
  if onTextMessage then
    return onTextMessage(callback)
  end
  return BaseAdapter.callbacks.register("onTextMessage", callback)
end

function OpenTibiaBRAdapter.callbacks.onContainerOpen(callback)
  if onContainerOpen then
    return onContainerOpen(callback)
  end
  return BaseAdapter.callbacks.register("onContainerOpen", callback)
end

function OpenTibiaBRAdapter.callbacks.onContainerClose(callback)
  if onContainerClose then
    return onContainerClose(callback)
  end
  return BaseAdapter.callbacks.register("onContainerClose", callback)
end

function OpenTibiaBRAdapter.callbacks.onContainerUpdateItem(callback)
  if onContainerUpdateItem then
    return onContainerUpdateItem(callback)
  end
  return BaseAdapter.callbacks.register("onContainerUpdateItem", callback)
end

function OpenTibiaBRAdapter.callbacks.onAddItem(callback)
  if onAddItem then
    return onAddItem(callback)
  end
  return BaseAdapter.callbacks.register("onAddItem", callback)
end

function OpenTibiaBRAdapter.callbacks.onRemoveItem(callback)
  if onRemoveItem then
    return onRemoveItem(callback)
  end
  return BaseAdapter.callbacks.register("onRemoveItem", callback)
end

function OpenTibiaBRAdapter.callbacks.onTurn(callback)
  if onTurn then
    return onTurn(callback)
  end
  return BaseAdapter.callbacks.register("onTurn", callback)
end

function OpenTibiaBRAdapter.callbacks.onWalk(callback)
  if onWalk then
    return onWalk(callback)
  end
  return BaseAdapter.callbacks.register("onWalk", callback)
end

function OpenTibiaBRAdapter.callbacks.onUse(callback)
  if onUse then
    return onUse(callback)
  end
  return BaseAdapter.callbacks.register("onUse", callback)
end

function OpenTibiaBRAdapter.callbacks.onUseWith(callback)
  if onUseWith then
    return onUseWith(callback)
  end
  return BaseAdapter.callbacks.register("onUseWith", callback)
end

function OpenTibiaBRAdapter.callbacks.onManaChange(callback)
  if onManaChange then
    return onManaChange(callback)
  end
  return BaseAdapter.callbacks.register("onManaChange", callback)
end

function OpenTibiaBRAdapter.callbacks.onStatesChange(callback)
  if onStatesChange then
    return onStatesChange(callback)
  end
  return BaseAdapter.callbacks.register("onStatesChange", callback)
end

function OpenTibiaBRAdapter.callbacks.onInventoryChange(callback)
  if onInventoryChange then
    return onInventoryChange(callback)
  end
  return BaseAdapter.callbacks.register("onInventoryChange", callback)
end

function OpenTibiaBRAdapter.callbacks.onSpellCooldown(callback)
  if onSpellCooldown then
    return onSpellCooldown(callback)
  end
  return BaseAdapter.callbacks.register("onSpellCooldown", callback)
end

function OpenTibiaBRAdapter.callbacks.onGroupSpellCooldown(callback)
  if onGroupSpellCooldown then
    return onGroupSpellCooldown(callback)
  end
  return BaseAdapter.callbacks.register("onGroupSpellCooldown", callback)
end

function OpenTibiaBRAdapter.callbacks.onAttackingCreatureChange(callback)
  if onAttackingCreatureChange then
    return onAttackingCreatureChange(callback)
  end
  return BaseAdapter.callbacks.register("onAttackingCreatureChange", callback)
end

function OpenTibiaBRAdapter.callbacks.onModalDialog(callback)
  if onModalDialog then
    return onModalDialog(callback)
  end
  return BaseAdapter.callbacks.register("onModalDialog", callback)
end

function OpenTibiaBRAdapter.callbacks.onImbuementWindow(callback)
  if onImbuementWindow then
    return onImbuementWindow(callback)
  end
  return BaseAdapter.callbacks.register("onImbuementWindow", callback)
end

function OpenTibiaBRAdapter.callbacks.onForgeResult(callback)
  if onForgeResult then
    return onForgeResult(callback)
  end
  return BaseAdapter.callbacks.register("onForgeResult", callback)
end

function OpenTibiaBRAdapter.callbacks.onPreyData(callback)
  if onPreyData then
    return onPreyData(callback)
  end
  return BaseAdapter.callbacks.register("onPreyData", callback)
end

function OpenTibiaBRAdapter.callbacks.onMarketBrowse(callback)
  if onMarketBrowse then
    return onMarketBrowse(callback)
  end
  return BaseAdapter.callbacks.register("onMarketBrowse", callback)
end

function OpenTibiaBRAdapter.callbacks.onMarketOffer(callback)
  if onMarketOffer then
    return onMarketOffer(callback)
  end
  return BaseAdapter.callbacks.register("onMarketOffer", callback)
end

function OpenTibiaBRAdapter.callbacks.onStashAction(callback)
  if onStashAction then
    return onStashAction(callback)
  end
  return BaseAdapter.callbacks.register("onStashAction", callback)
end

function OpenTibiaBRAdapter.callbacks.onBestiaryData(callback)
  if onBestiaryData then
    return onBestiaryData(callback)
  end
  return BaseAdapter.callbacks.register("onBestiaryData", callback)
end

function OpenTibiaBRAdapter.callbacks.onAddThing(callback)
  if onAddThing then
    return onAddThing(callback)
  end
  return BaseAdapter.callbacks.register("onAddThing", callback)
end

function OpenTibiaBRAdapter.callbacks.onRemoveThing(callback)
  if onRemoveThing then
    return onRemoveThing(callback)
  end
  return BaseAdapter.callbacks.register("onRemoveThing", callback)
end

--------------------------------------------------------------------------------
-- OPENTIBIABR SPECIFIC UTILITIES
--------------------------------------------------------------------------------

-- Get creature by name
function OpenTibiaBRAdapter.utils.getCreatureByName(name, caseSensitive)
  local player = g_game.getLocalPlayer()
  if not player then return nil end
  
  local spectators = OpenTibiaBRAdapter.map.getSpectators(player:getPosition(), true)
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

-- Find item in containers (uses native if available)
function OpenTibiaBRAdapter.utils.findItem(itemId, subType)
  -- Use native function if available
  local item = OpenTibiaBRAdapter.game.findItemInContainers(itemId, subType)
  if item then return item end
  
  -- First check inventory
  local player = g_game.getLocalPlayer()
  if player then
    for slot = 1, 10 do
      local inventoryItem = player:getInventoryItem(slot)
      if inventoryItem and inventoryItem:getId() == itemId then
        if not subType or inventoryItem:getSubType() == subType then
          return inventoryItem
        end
      end
    end
  end
  
  -- Then check containers
  for _, container in pairs(g_game.getContainers()) do
    for _, containerItem in ipairs(container:getItems()) do
      if containerItem:getId() == itemId then
        if not subType or containerItem:getSubType() == subType then
          return containerItem
        end
      end
    end
  end
  
  return nil
end

-- Count items in containers
function OpenTibiaBRAdapter.utils.itemAmount(itemId, subType)
  local count = 0
  
  -- Count in inventory
  local player = g_game.getLocalPlayer()
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
  
  -- Count in containers
  for _, container in pairs(g_game.getContainers()) do
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
-- OPENTIBIABR BESTIARY (NEW FEATURE)
--------------------------------------------------------------------------------

OpenTibiaBRAdapter.bestiary = {}

function OpenTibiaBRAdapter.bestiary.request()
  if g_game and g_game.requestBestiary then
    return g_game.requestBestiary()
  end
end

function OpenTibiaBRAdapter.bestiary.requestOverview(raceName)
  if g_game and g_game.requestBestiaryOverview then
    return g_game.requestBestiaryOverview(raceName)
  end
end

function OpenTibiaBRAdapter.bestiary.search(text)
  if g_game and g_game.requestBestiarySearch then
    return g_game.requestBestiarySearch(text)
  end
end

--------------------------------------------------------------------------------
-- OPENTIBIABR BOSSTIARY (NEW FEATURE)
--------------------------------------------------------------------------------

OpenTibiaBRAdapter.bosstiary = {}

function OpenTibiaBRAdapter.bosstiary.requestInfo()
  if g_game and g_game.requestBosstiaryInfo then
    return g_game.requestBosstiaryInfo()
  end
end

function OpenTibiaBRAdapter.bosstiary.requestSlotInfo()
  if g_game and g_game.requestBossSlootInfo then
    return g_game.requestBossSlootInfo()
  end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function OpenTibiaBRAdapter.init()
  if nExBot and nExBot.showDebug then
    print("[OpenTibiaBRAdapter] Initialized")
    if OpenTibiaBRAdapter.game.isUsingProtobuf() then
      print("[OpenTibiaBRAdapter] Using Protobuf protocol")
    end
    if OpenTibiaBRAdapter.paperdolls.isAvailable() then
      print("[OpenTibiaBRAdapter] Paperdoll system available")
    end
  end
  return true
end

-- Cleanup function
function OpenTibiaBRAdapter.terminate()
  if _controller then
    -- Clean up controller if needed
    _controller = nil
  end
end

return OpenTibiaBRAdapter
