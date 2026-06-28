--[[
  nExBot Client Service

  Provides a unified interface for client operations using the ACL.
  Bot modules should use this instead of directly accessing g_game, g_map, etc.

  Usage:
    local Client = require("client_service")
    Client.attack(creature)
    Client.getLocalPlayer()
    Client.getSpectators()
]]

local ACL = nil
local aclLoaded = false

local function loadACL()
  if aclLoaded then return ACL end
  local status, result = pcall(function() return dofile("/core/acl/init.lua") end)
  if status and result then
    ACL = result
    ACL.init()
  else
    warn("[ClientService] Failed to load ACL, using direct client access")
  end
  aclLoaded = true
  return ACL
end

ClientService = {}
ClientService.NAME = "ClientService"
ClientService.VERSION = "2.0.0"

function ClientService.init()
  loadACL()
  return true
end

--------------------------------------------------------------------------------
-- GENERIC DISPATCH
--------------------------------------------------------------------------------

local function makeDelegate(methodName, source, default, opts)
  opts = opts or {}
  local aclPath = opts.aclPath or "game"
  local aclKey = opts.aclKey or methodName
  return function(...)
    local acl = loadACL()
    if acl then
      local aclSection = acl[aclPath]
      if aclSection and aclSection[aclKey] then
        return aclSection[aclKey](...)
      end
    end
    if source == "game" or source == "both" then
      if g_game and g_game[methodName] then
        return g_game[methodName](...)
      end
    end
    if source == "map" or source == "both" then
      if g_map and g_map[methodName] then
        return g_map[methodName](...)
      end
    end
    if source == "ui" then
      if g_ui and g_ui[methodName] then
        return g_ui[methodName](...)
      end
    end
    if source == "resources" then
      if g_resources and g_resources[methodName] then
        return g_resources[methodName](...)
      end
    end
    if source == "window" then
      if g_window and g_window[methodName] then
        return g_window[methodName](...)
      end
    end
    if source == "platform" then
      if g_platform and g_platform[methodName] then
        return g_platform[methodName](...)
      end
    end
    if source == "keyboard" then
      if g_keyboard and g_keyboard[methodName] then
        return g_keyboard[methodName](...)
      end
    end
    if source == "settings" then
      if g_settings and g_settings[methodName] then
        return g_settings[methodName](...)
      end
    end
    if source == "callback" then
      local globalFn = rawget(_G, methodName)
      if globalFn then
        return globalFn(...)
      end
    end
    if source == "callback_acl" then
      -- Callbacks use acl.callbacks first, then global
      if acl then
        local cb = acl.callbacks and acl.callbacks[methodName]
        if cb then return cb(...) end
      end
      local globalFn = rawget(_G, methodName)
      if globalFn then return globalFn(...) end
    end
    return default
  end
end

--------------------------------------------------------------------------------
-- METHODS TABLE
-- { name, source, default, opts }
-- source: "game"|"map"|"ui"|"resources"|"window"|"platform"|"keyboard"|"settings"|"callback"|"callback_acl"|"both"
-- opts: { aclPath, aclKey } for ACL overrides
--------------------------------------------------------------------------------

local methods = {
  -- Client detection
  { "getClientType", "custom" },
  { "getClientName", "custom" },
  { "isOTCv8", "custom" },
  { "isOpenTibiaBR", "custom" },

  -- Connection state
  { "isOnline", "game", false },
  { "isDead", "game", false },
  { "isAttacking", "game", false },
  { "isFollowing", "game", false },

  -- Player
  { "getLocalPlayer", "game", nil },

  -- Combat
  { "attack", "game" },
  { "cancelAttack", "game" },
  { "follow", "game" },
  { "cancelFollow", "game" },
  { "cancelAttackAndFollow", "game" },
  { "getAttackingCreature", "game", nil },
  { "getFollowingCreature", "game", nil },

  -- Movement
  { "walk", "game", false },
  { "autoWalk", "game", false },
  { "turn", "game" },
  { "stop", "game" },

  -- Items
  { "move", "game" },
  { "use", "game" },
  { "useWith", "game" },
  { "useInventoryItem", "game" },
  { "look", "game" },
  { "rotate", "game" },
  { "equipItem", "game" },

  -- Containers
  { "open", "game" },
  { "openParent", "game" },
  { "close", "game" },
  { "getContainer", "game", nil },
  { "getContainers", "game", {} },
  { "seekInContainer", "game" },

  -- Communication
  { "talk", "game" },
  { "talkChannel", "game" },
  { "talkPrivate", "game" },

  -- Protocol
  { "getClientVersion", "game", 0 },
  { "getProtocolVersion", "game", 0 },
  { "getFeature", "game", false },
  { "enableFeature", "game" },
  { "getPing", "game", 0 },
  { "getUnjustifiedPoints", "game", {} },

  -- Combat settings
  { "getChaseMode", "game", 0 },
  { "getFightMode", "game", 0 },
  { "setChaseMode", "game" },
  { "setFightMode", "game" },
  { "isSafeFight", "game", false },
  { "setSafeFight", "game" },

  -- Outfit
  { "requestOutfit", "game" },
  { "changeOutfit", "game" },
  { "requestOutfitChange", "game" },
  { "mountCreature", "game" },
  { "requestMounts", "game" },

  -- Mount
  { "mount", "game" },
  { "dismount", "game" },

  -- Party
  { "partyInvite", "game" },
  { "partyJoin", "game" },
  { "partyLeave", "game" },
  { "requestPartySharedExperience", "game" },
  { "passPartyLeadership", "game" },

  -- Logout
  { "safeLogout", "game" },
  { "forceLogout", "game" },

  -- Inventory
  { "useInventoryItemWith", "game" },
  { "findPlayerItem", "game" },
  { "findItemInContainers", "game" },
  { "equipItemId", "game" },

  -- Stash
  { "stashWithdraw", "game" },
  { "stashStowItem", "game" },
  { "stashStowAll", "game" },
  { "openStash", "game" },
  { "requestStashSearch", "game" },

  -- Quick loot
  { "sendQuickLoot", "game" },
  { "quickLootCorpse", "game" },
  { "setQuickLootFallback", "game" },

  -- Imbuement
  { "imbuementDurations", "game", {} },
  { "applyImbuement", "game" },
  { "clearImbuement", "game" },
  { "requestImbuingWindow", "game" },
  { "closeImbuingWindow", "game" },

  -- Prey
  { "preyAction", "game" },
  { "requestPreyData", "game" },
  { "selectPreyCreature", "game" },
  { "refreshPreyMonsters", "game" },

  -- Forge
  { "forgeRequest", "game" },
  { "forgeFuse", "game" },
  { "forgeTransfer", "game" },
  { "openForge", "game" },

  -- Market
  { "browseMarket", "game" },
  { "createMarketOffer", "game" },
  { "cancelMarketOffer", "game" },
  { "acceptMarketOffer", "game" },
  { "requestMarketInfo", "game" },

  -- Modal / Browse / Inspection
  { "answerModalDialog", "game" },
  { "browseField", "game" },
  { "inspectionNormalObject", "game" },
  { "inspectionObject", "game" },

  -- Container enhanced
  { "refreshContainer", "game" },
  { "requestContainerQueue", "game" },
  { "openContainerAt", "game" },

  -- NPC Trade
  { "buyItem", "game" },
  { "sellItem", "game" },
  { "requestNPCTrade", "game" },
  { "closeNPCTrade", "game" },

  -- Blessings
  { "requestBless", "game" },

  -- Cyclopedia
  { "requestCyclopediaMapData", "game" },
  { "requestCharacterInfo", "game" },

  -- Walk config
  { "forceWalk", "game" },
  { "setScheduleLastWalk", "game" },
  { "setWalkFirstStepDelay", "game" },
  { "setWalkTurnDelay", "game" },
  { "setWalkSpeedMultiplier", "game" },
  { "getWalkSpeedMultiplier", "game", 1.0 },
  { "getWalkMaxSteps", "game", 10 },
  { "setWalkMaxSteps", "game" },

  -- Map
  { "getTile", "map", nil },
  { "isSightClear", "map", false },
  { "getTiles", "map", {} },
  { "getMinimapColor", "map", 0 },
  { "getSpectatorsInRange", "map", {} },
  { "isTileWalkable", "map" },
  { "getCreatureById", "map", nil },
  { "isAwareOfPosition", "map", false },
  { "findItemsById", "map", {} },
  { "getTilesInRange", "map", {} },
  { "cleanTile", "map" },
  { "setMinimapColor", "map" },
  { "findEveryPath", "map", {} },
  { "getSpectatorsInRangeEx", "map", {} },
  { "getSightSpectators", "map", {} },
  { "getSpectatorsByPattern", "map", {} },

  -- Cooldown (acl.cooldown)
  { "isCooldownActive", "custom", false, { aclPath = "cooldown" } },
  { "isGroupCooldownActive", "custom", false, { aclPath = "cooldown" } },

  -- UI
  { "importStyle", "ui" },
  { "createWidget", "ui" },
  { "getRootWidget", "ui", nil },
  { "loadUI", "ui" },
  { "loadUIFromString", "ui" },

  -- Resources
  { "fileExists", "resources", false },
  { "directoryExists", "resources", false },
  { "makeDir", "resources" },
  { "readFileContents", "resources", nil },
  { "writeFileContents", "resources" },
  { "listDirectoryFiles", "resources", {} },
  { "deleteFile", "resources" },

  -- Window
  { "setWindowTitle", "window" },
  { "flashWindow", "window" },
  { "setClipboardText", "window" },

  -- Platform
  { "openUrl", "platform" },

  -- Keyboard
  { "isKeyPressed", "keyboard", false },

  -- Settings
  { "getSettingNumber", "settings" },
  { "setSettingNumber", "settings" },

  -- Callbacks (acl.callbacks → global)
  { "onCreatureAppear", "callback_acl" },
  { "onCreatureDisappear", "callback_acl" },
  { "onPlayerPositionChange", "callback_acl" },
  { "onTalk", "callback_acl" },
  { "onTextMessage", "callback_acl" },
  { "onContainerOpen", "callback_acl" },
  { "onSpellCooldown", "callback_acl" },
  { "onGroupSpellCooldown", "callback_acl" },
  { "onUse", "callback_acl" },
  { "onUseWith", "callback_acl" },
  { "onCreatureHealthPercentChange", "callback_acl" },
  { "onContainerClose", "callback_acl" },
  { "onContainerUpdateItem", "callback_acl" },
  { "onAddItem", "callback_acl" },
  { "onRemoveItem", "callback_acl" },
  { "onImbuementWindow", "callback_acl" },
  { "onForgeResult", "callback_acl" },
  { "onPreyData", "callback_acl" },
  { "onMarketBrowse", "callback_acl" },
  { "onMarketOffer", "callback_acl" },
  { "onStashAction", "callback_acl" },
  { "onBestiaryData", "callback_acl" },
  { "onModalDialog", "callback_acl" },
  { "onAttackingCreatureChange", "callback_acl" },
  { "onInventoryChange", "callback_acl" },
  { "onManaChange", "callback_acl" },
  { "onStatesChange", "callback_acl" },
  { "onWalk", "callback_acl" },
  { "onAddThing", "callback_acl" },
  { "onRemoveThing", "callback_acl" },

  -- Bestiary (acl.bestiary → g_game)
  { "requestBestiary", "game", nil, { aclPath = "bestiary", aclKey = "request" } },
  { "requestBestiaryOverview", "game", nil, { aclPath = "bestiary", aclKey = "requestOverview" } },
  { "requestBestiarySearch", "game", nil, { aclPath = "bestiary", aclKey = "search" } },

  -- Bosstiary (acl.bosstiary → g_game)
  { "requestBosstiaryInfo", "game", nil, { aclPath = "bosstiary", aclKey = "requestInfo" } },
  { "requestBossSlootInfo", "game", nil, { aclPath = "bosstiary", aclKey = "requestSlotInfo" } },
}

-- Register all table-driven methods
for _, def in ipairs(methods) do
  local name, source, default, opts = def[1], def[2], def[3], def[4]
  if source ~= "custom" then
    ClientService[name] = makeDelegate(name, source, default, opts)
  end
end

--------------------------------------------------------------------------------
-- CUSTOM METHODS (special logic that doesn't fit generic dispatch)
--------------------------------------------------------------------------------

function ClientService.getClientType()
  local acl = loadACL()
  if acl then return acl.getClientType() end
  if nExBot and nExBot.clientDetection and nExBot.clientDetection.type then
    return nExBot.clientDetection.type
  end
  return 0
end

function ClientService.getClientName()
  local acl = loadACL()
  if acl then return acl.getClientName() end
  if nExBot and nExBot.clientDetection and nExBot.clientDetection.name then
    return nExBot.clientDetection.name
  end
  return "Unknown"
end

function ClientService.isOTCv8()
  local acl = loadACL()
  if acl then return acl.isOTCv8() end
  if nExBot and nExBot.clientDetection and nExBot.clientDetection.type then
    return nExBot.clientDetection.type == 1
  end
  return true
end

function ClientService.isOpenTibiaBR()
  local acl = loadACL()
  if acl then return acl.isOpenTibiaBR() end
  if nExBot and nExBot.clientDetection and nExBot.clientDetection.type then
    return nExBot.clientDetection.type == 2
  end
  return false
end

function ClientService.isCooldownActive(iconId)
  local acl = loadACL()
  if acl and acl.cooldown and acl.cooldown.isCooldownIconActive then
    return acl.cooldown.isCooldownIconActive(iconId)
  end
  local mod = modules and modules.game_cooldown
  if mod and mod.isCooldownIconActive then
    return mod.isCooldownIconActive(iconId)
  end
  return false
end

function ClientService.isGroupCooldownActive(groupId)
  local acl = loadACL()
  if acl and acl.cooldown and acl.cooldown.isGroupCooldownIconActive then
    return acl.cooldown.isGroupCooldownIconActive(groupId)
  end
  local mod = modules and modules.game_cooldown
  if mod and mod.isGroupCooldownIconActive then
    return mod.isGroupCooldownIconActive(groupId)
  end
  return false
end

function ClientService.getSpectators(pos, multifloor)
  local acl = loadACL()
  if acl and acl.map and acl.map.getSpectators then
    return acl.map.getSpectators(pos, multifloor)
  end
  if getSpectators then return getSpectators(pos, multifloor) or {} end
  if g_map and g_map.getSpectators then
    return g_map.getSpectators(pos, multifloor) or {}
  end
  return {}
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

function ClientService.isTileWalkable(pos)
  local acl = loadACL()
  if acl and acl.map and acl.map.isTileWalkable then
    return acl.map.isTileWalkable(pos)
  end
  if g_map and g_map.isTileWalkable then
    return g_map.isTileWalkable(pos)
  end
  local tile = ClientService.getTile(pos)
  return tile and tile:isWalkable() or false
end

function ClientService.forceWalk(direction)
  local acl = loadACL()
  if acl and acl.game and acl.game.forceWalk then
    return acl.game.forceWalk(direction)
  end
  if g_game and g_game.forceWalk then
    return g_game.forceWalk(direction)
  end
  return ClientService.walk(direction)
end

function ClientService.talkLocal(message)
  local acl = loadACL()
  if acl and acl.game and acl.game.talkLocal then
    return acl.game.talkLocal(message)
  end
  if g_game and g_game.talkLocal then
    return g_game.talkLocal(message)
  end
  return ClientService.talk(message)
end

function ClientService.say(message)
  return ClientService.talk(message)
end

function ClientService.getPos(x, y, z)
  local acl = loadACL()
  if acl and acl.utils then return acl.utils.getPos(x, y, z) end
  local player = ClientService.getLocalPlayer()
  if player then
    local pos = player:getPosition()
    pos.x = x or pos.x
    pos.y = y or pos.y
    pos.z = z or pos.z
    return pos
  end
  return { x = x or 0, y = y or 0, z = z or 0 }
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

function ClientService.getCreatureByName(name, caseSensitive)
  local acl = loadACL()
  if acl and acl.utils and acl.utils.getCreatureByName then
    return acl.utils.getCreatureByName(name, caseSensitive)
  end
  local player = ClientService.getLocalPlayer()
  if not player then return nil end
  local spectators = ClientService.getSpectators(player:getPosition(), true)
  for _, creature in ipairs(spectators) do
    if caseSensitive then
      if creature:getName() == name then return creature end
    else
      if creature:getName():lower() == name:lower() then return creature end
    end
  end
  return nil
end

function ClientService.findItem(itemId, subType)
  local acl = loadACL()
  if acl and acl.utils and acl.utils.findItem then
    return acl.utils.findItem(itemId, subType)
  end
  if findItem then return findItem(itemId, subType) end
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

function ClientService.itemAmount(itemId, subType)
  local acl = loadACL()
  if acl and acl.utils and acl.utils.itemAmount then
    return acl.utils.itemAmount(itemId, subType)
  end
  if itemAmount then return itemAmount(itemId, subType) end
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

function ClientService.findPlayerItem(itemId, subType)
  local acl = loadACL()
  if acl and acl.game and acl.game.findPlayerItem then
    return acl.game.findPlayerItem(itemId, subType)
  end
  if g_game and g_game.findPlayerItem then
    return g_game.findPlayerItem(itemId, subType)
  end
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

function ClientService.getTilesInRange(pos, rangeX, rangeY, multifloor)
  local acl = loadACL()
  if acl and acl.map and acl.map.getTilesInRange then
    return acl.map.getTilesInRange(pos, rangeX, rangeY, multifloor)
  end
  if g_map and g_map.getTilesInRange then
    return g_map.getTilesInRange(pos, rangeX, rangeY, multifloor or false) or {}
  end
  local tiles = {}
  for x = pos.x - rangeX, pos.x + rangeX do
    for y = pos.y - rangeY, pos.y + rangeY do
      local tile = ClientService.getTile({ x = x, y = y, z = pos.z })
      if tile then table.insert(tiles, tile) end
    end
  end
  return tiles
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
-- MODULE ACCESS
--------------------------------------------------------------------------------

function ClientService.getModule(name)
  if modules and modules[name] then return modules[name] end
  return nil
end

function ClientService.getGameInterface() return ClientService.getModule("game_interface") end
function ClientService.getConsole() return ClientService.getModule("game_console") end
function ClientService.getCooldown() return ClientService.getModule("game_cooldown") end
function ClientService.getBot() return ClientService.getModule("game_bot") end
function ClientService.getTerminal() return ClientService.getModule("client_terminal") end
function ClientService.getTextMessage() return ClientService.getModule("game_textmessage") end
function ClientService.getWalking() return ClientService.getModule("game_walking") end
function ClientService.getInventory() return ClientService.getModule("game_inventory") end
function ClientService.getContainersModule() return ClientService.getModule("game_containers") end
function ClientService.getSkills() return ClientService.getModule("game_skills") end

--------------------------------------------------------------------------------
-- EXPORT
--------------------------------------------------------------------------------

ClientService = ClientService

function getClient() return ClientService end

return ClientService
