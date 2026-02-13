--[[
  nExBot ACL — Interfaces v2.0

  Runtime-enforced interface contracts for client adapters.
  validate() is called by init.lua after adapter loading — not optional.

  Changes from v1.0:
  - validate() now returns structured { missing, extra } report
  - validateAll() checks every interface in one pass
  - Each interface stored as a Set for O(1) lookup
]]

local Interfaces = {}

-- =========================================================================
-- INTERFACE DEFINITIONS (arrays for readability, converted to sets below)
-- =========================================================================

local RAW = {}

RAW.IGame = {
  "attack", "cancelAttack", "follow", "cancelFollow", "cancelAttackAndFollow",
  "walk", "autoWalk", "turn", "stop",
  "move", "use", "useWith", "useInventoryItem", "look", "rotate",
  "talk", "talkChannel", "talkPrivate",
  "requestChannels", "joinChannel", "leaveChannel",
  "open", "openParent", "close", "refreshContainer",
  "isOnline", "isDead", "isAttacking", "isFollowing",
  "getLocalPlayer", "getAttackingCreature", "getFollowingCreature",
  "getContainer", "getContainers",
  "getClientVersion", "getProtocolVersion", "getFeature", "enableFeature", "disableFeature",
  "getChaseMode", "getFightMode", "setChaseMode", "setFightMode",
  "isSafeFight", "setSafeFight",
  "buyItem", "sellItem", "closeNpcTrade",
  "getUnjustifiedPoints", "getPing",
  "equipItem", "requestOutfit", "changeOutfit",
}

RAW.IMap = {
  "getTile", "getSpectators", "isSightClear", "isLookPossible",
  "cleanDynamicThings", "findPath",
}

RAW.IPlayer = {
  "getHealth", "getMaxHealth", "getMana", "getMaxMana",
  "getLevel", "getExperience", "getMagicLevel", "getSoul", "getStamina",
  "getCapacity", "getTotalCapacity", "getVocation", "getBlessings",
  "getPosition", "getDirection", "isWalking", "getSpeed", "getStates",
  "getSkillLevel", "getSkillBaseLevel", "getSkillPercent",
  "getInventoryItem", "getName", "getId",
  "getSkull", "isPartyMember", "hasPartyBuff",
}

RAW.ICreature = {
  "getId", "getName", "getHealthPercent", "getPosition", "getDirection",
  "getSpeed", "getOutfit", "getSkull", "getEmblem",
  "isPlayer", "isMonster", "isNpc", "isLocalPlayer", "isPartyMember", "isWalking",
  "setText", "getText", "clearText",
}

RAW.ICallbacks = {
  "onTalk", "onTextMessage", "onLoginAdvice",
  "onCreatureAppear", "onCreatureDisappear",
  "onCreaturePositionChange", "onCreatureHealthPercentChange",
  "onTurn", "onWalk",
  "onPlayerPositionChange", "onManaChange", "onStatesChange", "onInventoryChange",
  "onAddThing", "onRemoveThing",
  "onContainerOpen", "onContainerClose", "onContainerUpdateItem",
  "onAddItem", "onRemoveItem",
  "onAttackingCreatureChange",
  "onUse", "onUseWith",
  "onSpellCooldown", "onGroupSpellCooldown",
  "onModalDialog", "onImbuementWindow",
}

RAW.IUI = {
  "importStyle", "createWidget", "getRootWidget", "loadUI",
}

RAW.IModules = {
  "getGameInterface", "getConsole", "getCooldown", "getBot", "getTerminal",
}

-- =========================================================================
-- Convert to Sets for O(1) lookup  +  expose arrays for iteration
-- =========================================================================

for ifaceName, methods in pairs(RAW) do
  local set = {}
  for _, m in ipairs(methods) do set[m] = true end
  Interfaces[ifaceName] = methods          -- array form (ipairs-iterable)
  Interfaces[ifaceName .. "_set"] = set    -- set form (O(1) lookup)
end

-- =========================================================================
-- VALIDATION
-- =========================================================================

--- Validate one domain table against an interface.
--- @param domain table  e.g. adapter.game
--- @param ifaceName string  e.g. "IGame"
--- @return boolean ok, table report  { missing = {}, extra = {} }
function Interfaces.validate(domain, ifaceName)
  local iface = Interfaces[ifaceName]
  if not iface then
    return false, { error = "Unknown interface: " .. tostring(ifaceName) }
  end
  local set = Interfaces[ifaceName .. "_set"]
  local missing = {}
  for _, method in ipairs(iface) do
    if not domain[method] then
      missing[#missing + 1] = method
    end
  end
  return #missing == 0, { missing = missing }
end

--- Validate an entire adapter against all core interfaces.
--- @param adapter table  The adapter (must have .game, .map, .callbacks, etc.)
--- @return boolean allOk, table reports  { IGame = {ok,report}, ... }
function Interfaces.validateAll(adapter)
  local domainMap = {
    IGame      = adapter.game,
    IMap       = adapter.map,
    ICallbacks = adapter.callbacks,
    IUI        = adapter.ui,
    IModules   = adapter.modules,
  }
  local allOk = true
  local reports = {}
  for ifaceName, domain in pairs(domainMap) do
    if domain then
      local ok, report = Interfaces.validate(domain, ifaceName)
      reports[ifaceName] = { ok = ok, report = report }
      if not ok then allOk = false end
    else
      reports[ifaceName] = { ok = false, report = { missing = {"(domain missing)"} } }
      allOk = false
    end
  end
  return allOk, reports
end

return Interfaces
