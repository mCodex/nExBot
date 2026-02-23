--[[
  nExBot ACL — OTCv8 Adapter v2.0

  Extends BaseAdapter via setmetatable(__index) — one-line inheritance.
  Only declares methods that DIFFER from base.

  OTCv8-specific:
  - moveRaw (raw item movement)
  - getSpectators / getSpectatorsByPattern
  - findPath via g_map.findPath(start, goal, maxSteps, maxComplexity)
]]

-- =========================================================================
-- LOAD BASE (pcall-guarded — sandbox dofile may not propagate returns)
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

-- Domain sub-tables: create fresh tables that inherit from Base's sub-tables
local function inheritDomain(baseDomain)
  local child = {}
  if baseDomain then
    setmetatable(child, { __index = baseDomain })
  end
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

A._registeredCallbacks = BaseAdapter._registeredCallbacks or {}

-- Metadata
A.NAME    = "OTCv8"
A.VERSION = "2.0.0"

-- =========================================================================
-- OTCv8-SPECIFIC GAME OVERRIDES
-- =========================================================================

function A.game.moveRaw(thing, toPosition, count)
  if g_game and g_game.moveRaw then
    return g_game.moveRaw(thing, toPosition, count or 1)
  end
  -- Fallback to normal move via base proxy
  if g_game and g_game.move then
    return g_game.move(thing, toPosition, count or 1)
  end
end

function A.game.autoWalk(destination, maxSteps, options)
  if g_game and g_game.autoWalk then
    return g_game.autoWalk(destination, maxSteps, options)
  end
  return false
end

-- =========================================================================
-- OTCv8-SPECIFIC MAP OVERRIDES
-- =========================================================================

function A.map.getSpectators(pos, multifloor)
  if not g_map then return {} end
  if G and G.botContext and G.botContext.getSpectators then
    return G.botContext.getSpectators(pos, multifloor) or {}
  end
  if g_map.getSpectators then
    return g_map.getSpectators(pos, multifloor or false) or {}
  end
  return {}
end

function A.map.getSpectatorsByPattern(pos, pattern)
  if g_map and g_map.getSpectatorsByPattern then
    return g_map.getSpectatorsByPattern(pos, pattern) or {}
  end
  return A.map.getSpectators(pos, false)
end

function A.map.findPath(startPos, goalPos, options)
  if g_map and g_map.findPath then
    options = options or {}
    local maxComplexity = options.maxComplexity or 10000
    local maxSteps      = options.maxSteps or 50
    return g_map.findPath(startPos, goalPos, maxSteps, maxComplexity)
  end
  return nil
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
  if bm and bm.contentsPanel and bm.contentsPanel.config then
    local o = bm.contentsPanel.config:getCurrentOption()
    return o and o.text or nil
  end
  return nil
end

function A.bot.getConfigPath()
  if nExBot and nExBot.paths then return nExBot.paths.base end
  local name = A.bot.getConfigName()
  return name and ("/bot/" .. name) or nil
end

-- =========================================================================
-- UTILS (inherits base, adds OTCv8 specifics)
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
-- INIT
-- =========================================================================

function A.init()
  if nExBot and nExBot.showDebug then
    print("[OTCv8Adapter] Initialized v" .. A.VERSION)
  end
  return true
end

-- Sandbox global export
ACL_LoadedAdapter = A

return A
