--[[
  nExBot ACL — Base Adapter v2.0

  Metatable-proxy approach replaces 50+ hand-written method wrappers.
  A single __index handler on each domain table (game, map, ui, modules)
  does nil-safe dispatch to the underlying OTClient global.

  Principles applied:
  - DRY:   One proxy factory generates all domain tables.
  - KISS:  ~80 lines vs 595.  No copy-paste wrappers.
  - SRP:   Thin passthrough only — no callback management, no utils.
  - OCP:   Derived adapters add overrides without touching base.

  Derived adapters use setmetatable(Child, {__index = Base}) — one line.
]]

local BaseAdapter = {}

-- =========================================================================
-- PROXY FACTORY
-- Creates a table whose __index transparently calls `backend.method(...)`
-- with a nil-safe guard (returns `defaultRet` when the backend or method
-- is absent).
-- =========================================================================

local function createProxy(backend, defaultRet)
  local proxy = {}
  local mt = {
    __index = function(_, method)
      -- Resolve the backend (it might be nil at load time, available later)
      local b = type(backend) == "function" and backend() or backend
      if not b then return nil end
      local fn = b[method]
      if type(fn) ~= "function" then return nil end
      -- Return a stable closure so callers can cache it
      local wrapper = function(...)
        local realB = type(backend) == "function" and backend() or backend
        if not realB then return defaultRet end
        local realFn = realB[method]
        if type(realFn) ~= "function" then return defaultRet end
        return realFn(...)
      end
      -- Cache in the proxy so __index fires only once per method
      rawset(proxy, method, wrapper)
      return wrapper
    end,
  }
  setmetatable(proxy, mt)
  return proxy
end

-- =========================================================================
-- DOMAIN TABLES
-- Each resolves lazily against the corresponding OTClient global.
-- =========================================================================

BaseAdapter.game    = createProxy(function() return g_game end, nil)
BaseAdapter.map     = createProxy(function() return g_map end, nil)
BaseAdapter.ui      = createProxy(function() return g_ui end, nil)

-- Modules are a normal table (g_modules doesn't exist in OTClient bot env)
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

-- =========================================================================
-- UTILS (pure functions — no state, no globals dependency)
-- =========================================================================

BaseAdapter.utils = {}

function BaseAdapter.utils.getDistanceBetween(pos1, pos2)
  if not pos1 or not pos2 then return 999 end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

function BaseAdapter.utils.isSamePosition(pos1, pos2)
  if not pos1 or not pos2 then return false end
  return pos1.x == pos2.x and pos1.y == pos2.y and pos1.z == pos2.z
end

function BaseAdapter.utils.isInRange(pos1, pos2, rangeX, rangeY)
  if not pos1 or not pos2 then return false end
  rangeY = rangeY or rangeX
  return math.abs(pos1.x - pos2.x) <= rangeX
     and math.abs(pos1.y - pos2.y) <= rangeY
     and pos1.z == pos2.z
end

-- =========================================================================
-- CALLBACKS (base registration — adapters override individual events)
-- =========================================================================

BaseAdapter.callbacks = {}
BaseAdapter._registeredCallbacks = {}

function BaseAdapter.callbacks.register(eventType, callback, priority)
  local list = BaseAdapter._registeredCallbacks[eventType]
  if not list then
    list = {}
    BaseAdapter._registeredCallbacks[eventType] = list
  end
  local entry = { callback = callback, priority = priority or 0 }
  list[#list + 1] = entry
  table.sort(list, function(a, b) return a.priority > b.priority end)
  -- Return unsubscribe handle
  return function()
    for i, e in ipairs(BaseAdapter._registeredCallbacks[eventType] or {}) do
      if e == entry then table.remove(BaseAdapter._registeredCallbacks[eventType], i); break end
    end
  end
end

function BaseAdapter.callbacks.emit(eventType, ...)
  local handlers = BaseAdapter._registeredCallbacks[eventType]
  if not handlers then return end
  for _, h in ipairs(handlers) do
    pcall(h.callback, ...)
  end
end

-- =========================================================================
-- CALLBACK WRAPPERS (generated from ICallbacks interface list)
-- Each wraps the bot-sandbox native `onXxx` global if present, else
-- falls back to internal registration.
-- =========================================================================

local CALLBACK_NAMES = {
  "onTalk", "onTextMessage", "onLoginAdvice",
  "onCreatureAppear", "onCreatureDisappear",
  "onCreaturePositionChange", "onCreatureHealthPercentChange",
  "onTurn", "onWalk",
  "onPlayerPositionChange", "onManaChange", "onStatesChange", "onInventoryChange",
  "onAddThing", "onRemoveThing",
  "onContainerOpen", "onContainerClose", "onContainerUpdateItem",
  "onAddItem", "onRemoveItem",
  "onAttackingCreatureChange",
  "onUse", "onUseWith", "onKeyDown", "onKeyUp", "onKeyPress",
  "onChannelList", "onOpenChannel", "onCloseChannel", "onChannelEvent",
  "onSpellCooldown", "onGroupSpellCooldown",
  "onModalDialog", "onImbuementWindow",
  "onMissle", "onAnimatedText", "onStaticText", "onGameEditText",
}

for _, name in ipairs(CALLBACK_NAMES) do
  BaseAdapter.callbacks[name] = function(callback)
    -- Prefer native bot-sandbox global (the `onXxx` function injected by OTClient)
    local native = _G and _G[name]
    if not native then
      -- In the OTClient sandbox, globals are directly visible without _G
      local ok, fn = pcall(function() return loadstring("return " .. name)() end)
      if ok and type(fn) == "function" then native = fn end
    end
    if type(native) == "function" then
      return native(callback)
    end
    return BaseAdapter.callbacks.register(name, callback)
  end
end

-- =========================================================================
-- ADAPTER METADATA
-- =========================================================================

BaseAdapter.NAME    = "Base"
BaseAdapter.VERSION = "2.0.0"

-- =========================================================================
-- GLOBAL EXPORT (sandbox workaround — dofile may not propagate return)
-- =========================================================================

ACL_BaseAdapter = BaseAdapter

return BaseAdapter
