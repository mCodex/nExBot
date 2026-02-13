--[[
  nExBot ACL — OpenTibiaBR Adapter v2.0

  Extends BaseAdapter via setmetatable(__index) — one-line inheritance.
  Only declares methods that DIFFER from base or are OTBR-exclusive.

  Domain split:
  - game.*       — OTBR-specific game ops (forceWalk, quickLoot, stash, etc.)
  - map.*        — Extended spectator/path APIs
  - callbacks.*  — Inherits all from base (generated loop)
  - cooldown.*   — Module-based cooldown queries
  - bot.*        — Config access
  - stash.*      — Stash/depot operations
  - imbuement.*  — Imbuement management
  - prey.*       — Prey system
  - forge.*      — Forge system
  - market.*     — Market operations
  - bestiary.*   — Bestiary + Bosstiary
  - gameConfig.* — g_gameConfig access
  - paperdolls.* — Paperdoll system

  All domains are in this single file (no sub-directory split needed since
  metatable inheritance eliminated the boilerplate — file is now ~450 lines
  vs the original 1138).
]]

-- =========================================================================
-- LOAD BASE
-- =========================================================================

local BaseAdapter
do
  local ok, res = pcall(dofile, "/core/acl/adapters/base.lua")
  BaseAdapter = (ok and type(res) == "table" and res) or ACL_BaseAdapter or {}
end

-- =========================================================================
-- ADAPTER TABLE — inherits everything from Base via metatable
-- =========================================================================

local A = {}

local function inheritDomain(baseDomain)
  local child = {}
  if baseDomain then setmetatable(child, { __index = baseDomain }) end
  return child
end

A.game      = inheritDomain(BaseAdapter.game)
A.map       = inheritDomain(BaseAdapter.map)
A.ui        = inheritDomain(BaseAdapter.ui)
A.modules   = inheritDomain(BaseAdapter.modules)
A.utils     = inheritDomain(BaseAdapter.utils)
A.callbacks = inheritDomain(BaseAdapter.callbacks)
A.cooldown  = {}
A.bot       = {}
A.stash     = {}
A.imbuement = {}
A.prey      = {}
A.forge     = {}
A.market    = {}
A.bestiary  = {}
A.bosstiary = {}
A.gameConfig = {}
A.paperdolls = {}

A._registeredCallbacks = BaseAdapter._registeredCallbacks or {}

A.NAME    = "OpenTibiaBR"
A.VERSION = "2.0.0"

-- Sandbox global export
ACL_LoadedAdapter = A

-- =========================================================================
-- HELPER: Generate a thin wrapper for a g_game method
-- =========================================================================

local function gameMethod(name, ...)
  if g_game and type(g_game[name]) == "function" then
    return g_game[name](...)
  end
end

-- =========================================================================
-- GAME OVERRIDES
-- =========================================================================

function A.game.forceWalk(direction)
  if g_game and g_game.forceWalk then return g_game.forceWalk(direction) end
  if g_game and g_game.walk      then return g_game.walk(direction) end
end

function A.game.autoWalk(destination, options)
  return g_game and g_game.autoWalk and g_game.autoWalk(destination, options) or false
end

function A.game.setScheduleLastWalk(s)     return gameMethod("setScheduleLastWalk", s) end
function A.game.wrap(thing)                return gameMethod("wrap", thing) end
function A.game.equipItemId(id)            return gameMethod("equipItemId", id) end
function A.game.sendQuickLoot(pos)         return gameMethod("sendQuickLoot", pos) end
function A.game.quickLootCorpse(tile)      return gameMethod("quickLootCorpse", tile) end
function A.game.setQuickLootFallback(e)    return gameMethod("setQuickLootFallback", e) end
function A.game.browseField(pos)           return gameMethod("browseField", pos) end
function A.game.answerModalDialog(d,b,c)   return gameMethod("answerModalDialog", d, b, c or 0) end
function A.game.requestContainerQueue()    return gameMethod("requestContainerQueue") end
function A.game.openContainerAt(t, pos)    return gameMethod("openContainerAt", t, pos) end
function A.game.requestOutfitChange()      return gameMethod("requestOutfitChange") end
function A.game.mountCreature(m)           return gameMethod("mountCreature", m) end
function A.game.requestMounts()            return gameMethod("requestMounts") end
function A.game.requestBless()             return gameMethod("requestBless") end
function A.game.isUsingProtobuf()          return g_game and g_game.isUsingProtobuf and g_game.isUsingProtobuf() or false end
function A.game.enableTileThingLuaCallback(e) return gameMethod("enableTileThingLuaCallback", e) end
function A.game.setWalkFirstStepDelay(d)   return gameMethod("setWalkFirstStepDelay", d) end
function A.game.setWalkTurnDelay(d)        return gameMethod("setWalkTurnDelay", d) end
function A.game.setWalkSpeedMultiplier(m)  return gameMethod("setWalkSpeedMultiplier", m) end
function A.game.getWalkSpeedMultiplier()   return g_game and g_game.getWalkSpeedMultiplier and g_game.getWalkSpeedMultiplier() or 1.0 end
function A.game.getWalkMaxSteps()          return g_game and g_game.getWalkMaxSteps and g_game.getWalkMaxSteps() or 10 end
function A.game.setWalkMaxSteps(s)         return gameMethod("setWalkMaxSteps", s) end
function A.game.findItemInContainers(id, sub) return g_game and g_game.findItemInContainers and g_game.findItemInContainers(id, sub) or nil end
function A.game.imbuementDurations()       return g_game and g_game.imbuementDurations and g_game.imbuementDurations() or {} end
function A.game.requestPartySharedExperience(e) return gameMethod("requestPartySharedExperience", e) end
function A.game.passPartyLeadership(c)     return gameMethod("passPartyLeadership", c) end
function A.game.requestCyclopediaMapData(p,z)   return gameMethod("requestCyclopediaMapData", p, z or 0) end
function A.game.requestCharacterInfo(t)    return gameMethod("requestCharacterInfo", t or 0) end

-- NPC Trade (OTBR signature differs from OTCv8)
function A.game.buyItem(item, amount, ignoreCap, buyWithBackpack)
  return gameMethod("buyItem", item, amount or 1, ignoreCap or false, buyWithBackpack or false)
end
function A.game.sellItem(item, amount, ignoreEquipped)
  return gameMethod("sellItem", item, amount or 1, ignoreEquipped or false)
end
function A.game.requestNPCTrade(creature)  return gameMethod("requestNPCTrade", creature) end
function A.game.closeNPCTrade()            return gameMethod("closeNPCTrade") end

-- Inspection
function A.game.inspectionNormalObject(thing) return gameMethod("inspectionNormalObject", thing) end
function A.game.inspectionObject(iType, id, count) return gameMethod("inspectionObject", iType, id, count or 1) end

-- =========================================================================
-- STASH
-- =========================================================================

function A.stash.withdraw(itemId, count)   return gameMethod("stashWithdraw", itemId, count) end
function A.stash.stowItem(item, count)     return gameMethod("stashStowItem", item, count) end
function A.stash.stowAll(item)             return gameMethod("stashStowAll", item) end
function A.stash.open()                    return gameMethod("openStash") end
function A.stash.search(itemId)            return gameMethod("requestStashSearch", itemId) end

-- =========================================================================
-- IMBUEMENT
-- =========================================================================

function A.imbuement.apply(slotId, imbuId, protection) return gameMethod("applyImbuement", slotId, imbuId, protection or false) end
function A.imbuement.clear(slotId)         return gameMethod("clearImbuement", slotId) end
function A.imbuement.requestWindow(item)   return gameMethod("requestImbuingWindow", item) end
function A.imbuement.closeWindow()         return gameMethod("closeImbuingWindow") end

-- =========================================================================
-- PREY
-- =========================================================================

function A.prey.action(slotId, actionType, bonusType, monsterIdx)
  return gameMethod("preyAction", slotId, actionType, bonusType or 0, monsterIdx or 0)
end
function A.prey.requestData()              return gameMethod("requestPreyData") end
function A.prey.selectCreature(slot, idx)  return gameMethod("selectPreyCreature", slot, idx) end
function A.prey.refreshMonsters(slot)      return gameMethod("refreshPreyMonsters", slot) end

-- =========================================================================
-- FORGE
-- =========================================================================

function A.forge.request(action, ...)      return gameMethod("forgeRequest", action, ...) end
function A.forge.fuse(a, b, core)          return gameMethod("forgeFuse", a, b, core or false) end
function A.forge.transfer(donor, recv, core) return gameMethod("forgeTransfer", donor, recv, core or false) end
function A.forge.open()                    return gameMethod("openForge") end

-- =========================================================================
-- MARKET
-- =========================================================================

function A.market.browse(cat, voc)         return gameMethod("browseMarket", cat or 0, voc or 0) end
function A.market.createOffer(t, id, amt, price, anon) return gameMethod("createMarketOffer", t, id, amt, price, anon or false) end
function A.market.cancelOffer(offerId)     return gameMethod("cancelMarketOffer", offerId) end
function A.market.acceptOffer(offerId, amt)return gameMethod("acceptMarketOffer", offerId, amt) end
function A.market.requestInfo(itemId)      return gameMethod("requestMarketInfo", itemId) end

-- =========================================================================
-- BESTIARY / BOSSTIARY
-- =========================================================================

function A.bestiary.request()              return gameMethod("requestBestiary") end
function A.bestiary.requestOverview(race)  return gameMethod("requestBestiaryOverview", race) end
function A.bestiary.search(text)           return gameMethod("requestBestiarySearch", text) end
function A.bosstiary.requestInfo()         return gameMethod("requestBosstiaryInfo") end
function A.bosstiary.requestSlotInfo()     return gameMethod("requestBossSlootInfo") end

-- =========================================================================
-- GAME CONFIG
-- =========================================================================

function A.gameConfig.get() return g_gameConfig or nil end
function A.gameConfig.loadFonts(path) return g_gameConfig and g_gameConfig.loadFonts and g_gameConfig.loadFonts(path) end

-- =========================================================================
-- PAPERDOLLS
-- =========================================================================

function A.paperdolls.isAvailable() return g_paperdolls ~= nil end
function A.paperdolls.get(id) return g_paperdolls and g_paperdolls.get and g_paperdolls.get(id) end
function A.paperdolls.getAll() return g_paperdolls and g_paperdolls.getAll and g_paperdolls.getAll() or {} end
function A.paperdolls.clear() return g_paperdolls and g_paperdolls.clear and g_paperdolls.clear() end

-- =========================================================================
-- MAP OVERRIDES
-- =========================================================================

function A.map.getSpectators(pos, multifloor)
  if not g_map then return {} end
  if G and G.botContext and G.botContext.getSpectators then
    return G.botContext.getSpectators(pos, multifloor) or {}
  end
  return g_map.getSpectators and g_map.getSpectators(pos, multifloor or false) or {}
end

function A.map.getSpectatorsInRange(pos, multifloor, rangeX, rangeY)
  if g_map and g_map.getSpectatorsInRange then
    return g_map.getSpectatorsInRange(pos, multifloor, rangeX, rangeY) or {}
  end
  return A.map.getSpectators(pos, multifloor)
end

function A.map.getSpectatorsInRangeEx(pos, multifloor, minRX, maxRX, minRY, maxRY)
  if g_map and g_map.getSpectatorsInRangeEx then
    return g_map.getSpectatorsInRangeEx(pos, multifloor, minRX, maxRX, minRY, maxRY) or {}
  end
  return A.map.getSpectators(pos, multifloor)
end

function A.map.getSightSpectators(pos, multifloor)
  if g_map and g_map.getSightSpectators then
    return g_map.getSightSpectators(pos, multifloor) or {}
  end
  return A.map.getSpectators(pos, multifloor)
end

function A.map.findPath(startPos, goalPos, options)
  if g_map and g_map.findPath then
    options = options or {}
    return g_map.findPath(startPos, goalPos, options.maxSteps or 50, options.flags or 0)
  end
  return nil
end

function A.map.findEveryPath(startPos, destinations, maxSteps, flags)
  if g_map and g_map.findEveryPath then
    return g_map.findEveryPath(startPos, destinations, maxSteps or 50, flags or 0)
  end
  return {}
end

function A.map.getCreatureById(cid)
  return g_map and g_map.getCreatureById and g_map.getCreatureById(cid) or nil
end

function A.map.isAwareOfPosition(pos)
  return g_map and g_map.isAwareOfPosition and g_map.isAwareOfPosition(pos) or false
end

function A.map.findItemsById(itemId, multifloor)
  return g_map and g_map.findItemsById and g_map.findItemsById(itemId, multifloor or false) or {}
end

function A.map.getSpectatorsByPattern(pos, pattern, w, h, ff, lf)
  return g_map and g_map.getSpectatorsByPattern and g_map.getSpectatorsByPattern(pos, pattern, w, h, ff, lf) or {}
end

function A.map.getTilesInRange(pos, rangeX, rangeY, multifloor)
  if g_map and g_map.getTilesInRange then
    return g_map.getTilesInRange(pos, rangeX, rangeY, multifloor or false) or {}
  end
  local tiles = {}
  for x = pos.x - rangeX, pos.x + rangeX do
    for y = pos.y - rangeY, pos.y + rangeY do
      local t = g_map.getTile({x = x, y = y, z = pos.z})
      if t then tiles[#tiles + 1] = t end
    end
  end
  return tiles
end

function A.map.setMinimapColor(pos, color, desc)
  return g_map and g_map.setMinimapColor and g_map.setMinimapColor(pos, color, desc)
end

function A.map.cleanTile(pos)
  return g_map and g_map.cleanTile and g_map.cleanTile(pos)
end

-- =========================================================================
-- COOLDOWN
-- =========================================================================

function A.cooldown.isCooldownIconActive(iconId)
  local m = modules.game_cooldown
  return m and m.isCooldownIconActive and m.isCooldownIconActive(iconId) or false
end

function A.cooldown.isGroupCooldownIconActive(groupId)
  local m = modules.game_cooldown
  return m and m.isGroupCooldownIconActive and m.isGroupCooldownIconActive(groupId) or false
end

-- =========================================================================
-- BOT
-- =========================================================================

function A.bot.getConfigName()
  local bm = modules.game_bot
  if bm then
    if bm.contentsPanel and bm.contentsPanel.config then
      local o = bm.contentsPanel.config:getCurrentOption()
      return o and o.text or nil
    end
    if bm.getCurrentConfig then return bm.getCurrentConfig() end
  end
  return nil
end

function A.bot.getConfigPath()
  local name = A.bot.getConfigName()
  return name and ("/bot/" .. name) or nil
end

-- =========================================================================
-- UTILS (inherits base, adds OTBR specifics)
-- =========================================================================

function A.utils.getCreatureByName(name, caseSensitive)
  local p = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer()
  if not p then return nil end
  local specs = A.map.getSpectators(p:getPosition(), true)
  for _, c in ipairs(specs) do
    local cn = c:getName()
    if caseSensitive then
      if cn == name then return c end
    else
      if cn:lower() == name:lower() then return c end
    end
  end
  return nil
end

function A.utils.findItem(itemId, subType)
  -- Native first
  local native = A.game.findItemInContainers(itemId, subType)
  if native then return native end
  -- Manual scan
  local p = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer()
  if p then
    for slot = 1, 10 do
      local item = p:getInventoryItem(slot)
      if item and item:getId() == itemId and (not subType or item:getSubType() == subType) then
        return item
      end
    end
  end
  for _, container in pairs(g_game.getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId and (not subType or item:getSubType() == subType) then
        return item
      end
    end
  end
  return nil
end

function A.utils.itemAmount(itemId, subType)
  local count = 0
  local p = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer()
  if p then
    for slot = 1, 10 do
      local item = p:getInventoryItem(slot)
      if item and item:getId() == itemId and (not subType or item:getSubType() == subType) then
        count = count + item:getCount()
      end
    end
  end
  for _, container in pairs(g_game.getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId and (not subType or item:getSubType() == subType) then
        count = count + item:getCount()
      end
    end
  end
  return count
end

-- =========================================================================
-- INIT / TERMINATE
-- =========================================================================

function A.init()
  if nExBot and nExBot.showDebug then
    print("[OpenTibiaBRAdapter] Initialized v" .. A.VERSION)
    if A.game.isUsingProtobuf() then print("[OpenTibiaBRAdapter] Protobuf active") end
    if A.paperdolls.isAvailable() then print("[OpenTibiaBRAdapter] Paperdolls available") end
  end
  return true
end

function A.terminate() end

return A
