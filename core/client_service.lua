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
  local aclPath = opts.aclPath or source or "game"
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
      if type(globalFn) == "function" then
        return globalFn(...)
      end
    end
    if source == "callback_acl" then
      -- Callbacks use acl.callbacks first, then global
      if acl then
        local cb = acl.callbacks and acl.callbacks[methodName]
        if type(cb) == "function" then return cb(...) end
      end
      local globalFn = rawget(_G, methodName)
      if type(globalFn) == "function" then return globalFn(...) end
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

function ClientService.isOpenTibiaBR()
  local acl = loadACL()
  if acl then return acl.isOpenTibiaBR() end
  if nExBot and nExBot.clientDetection and nExBot.clientDetection.type then
    return nExBot.clientDetection.type == 2
  end
end

-- MODULE ACCESS
--------------------------------------------------------------------------------

function ClientService.getModule(name)
  if modules and modules[name] then return modules[name] end
  return nil
end

--------------------------------------------------------------------------------
-- EXPORT
--------------------------------------------------------------------------------

ClientService = ClientService

function getClient() return ClientService end

return ClientService
