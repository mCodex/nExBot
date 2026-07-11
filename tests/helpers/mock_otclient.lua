-- tests/helpers/mock_otclient.lua
-- Mock OTClient API for unit testing

local M = {}

-- Mock player
M.mockPlayer = {
  _health = 1000, _maxHealth = 1000,
  _mana = 500, _maxMana = 500,
  _level = 100, _soul = 100, _stamina = 2400, _speed = 220,
  _position = {x = 100, y = 100, z = 7},
  _direction = 2, _wearing = {},

  getHealth = function(self) return self._health end,
  getMaxHealth = function(self) return self._maxHealth end,
  getMana = function(self) return self._mana end,
  getMaxMana = function(self) return self._maxMana end,
  getLevel = function(self) return self._level end,
  getSoul = function(self) return self._soul end,
  getStamina = function(self) return self._stamina end,
  getSpeed = function(self) return self._speed end,
  getPosition = function(self) return self._position end,
  getDirection = function(self) return self._direction end,
  getHealthPercent = function(self)
    return math.floor(self._health / self._maxHealth * 100)
  end,
  getManaPercent = function(self)
    return math.floor(self._mana / self._maxMana * 100)
  end,
  getName = function(self) return "TestPlayer" end,
  isDead = function(self) return self._health <= 0 end,
  isLocalPlayer = function(self) return true end,
  isMonster = function(self) return false end,
  isPlayer = function(self) return true end,
  isNpc = function(self) return false end,
  getInventoryItem = function(self, slotId) return self._wearing[slotId] end,
}

-- Mock g_game
M.g_game = {
  _localPlayer = nil,
  getLocalPlayer = function()
    if not M.g_game._localPlayer then
      M.g_game._localPlayer = M.mockPlayer
    end
    return M.g_game._localPlayer
  end,
  getClientVersion = function() return 1200 end,
  getChaseMode = function() return 1 end,
  setChaseMode = function() end,
  getAttackingCreature = function() return nil end,
  attack = function() return true end,
  useInventoryItemWith = function() return true end,
  useInventoryItem = function() return true end,
  useWith = function() return true end,
  walk = function() return true end,
  forceWalk = function() return true end,
  move = function() return true end,
  look = function() return true end,
  talk = function() return true end,
  say = function() return true end,
  castSpell = function() return true end,
  attackCreature = function() return true end,
  followingCreature = function() return false end,
  setFollowing = function() end,
  setAttacking = function() end,
  isAttackable = function() return true end,
  isPartyMember = function() return false end,
  isOnline = function() return true end,
  getTradeState = function() return 0 end,
  getNpcTradeState = function() return 0 end,
  getBuyCatalogId = function() return 0 end,
  getSellCatalogId = function() return 0 end,
  tradeWithNpc = function() return true end,
  acceptTrade = function() return true end,
  cancelTrade = function() return true end,
  openItemOnYou = function() return true end,
  openItemOnGround = function() return true end,
  useItemWithCreature = function() return true end,
  useItemWithItem = function() return true end,
  equipItem = function() return true end,
  unequipItem = function() return true end,
  parseTextMessage = function() return true end,
  reportBug = function() return true end,
  reportBugWithScreenshot = function() return true end,
  cancelAttackAndFollow = function() return true end,
  startTrade = function() return true end,
  requestTrade = function() return true end,
  joinChannel = function() return true end,
  leaveChannel = function() return true end,
  openChannel = function() return true end,
  sendOpenContainer = function() return true end,
  sendCloseContainer = function() return true end,
  moveContainer = function() return true end,
  sortContainer = function() return true end,
  openContainer = function() return true end,
  closeContainer = function() return true end,
  lootContainer = function() return true end,
  setChaseMode = function() end,
  setFightMode = function() end,
  setSafeMode = function() end,
  setDontStop = function() end,
  setSmart = function() end,
  setStable = function() end,
  setAuto = function() end,
  getFightMode = function() return 1 end,
  getSafeMode = function() return false end,
  isDontStop = function() return false end,
  isSmart = function() return false end,
  isStable = function() return false end,
  isAuto = function() return false end,
}

-- Mock g_map
M.g_map = {
  getTile = function() return nil end,
  getMinimapColor = function() return 0 end,
  getFieldSize = function() return 0 end,
  isCovered = function() return false end,
}

-- Mock g_clock
M.g_clock = {
  millis = function() return os.time() * 1000 end,
}

-- Mock g_things
M.g_things = {
  getThingType = function() return nil end,
}

-- Mock g_ui
M.g_ui = {
  displayUI = function() end,
  hideUI = function() end,
  loadUI = function() end,
  getUI = function() return nil end,
  displayPopup = function() end,
  displayError = function() end,
  displayInfo = function() end,
  displayWarning = function() end,
  displaySuccess = function() end,
}

-- Mock SafeCreature
M.SafeCreature = {}

-- Mock ClientService
M.ClientService = {
  getLocalPlayer = function() return M.mockPlayer end,
}

-- Mock SafeCall
M.SafeCall = {
  call = function(fn, ...)
    return true, fn(...)
  end,
  useWith = function(item, target)
    return true
  end,
}

-- Mock nExBot
M.nExBot = {
  Shared = {
    nowMs = function() return os.time() * 1000 end,
    getClient = function() return M.g_game end,
  },
  zChanging = function() return false end,
  tileThrottled = function() return false end,
}

-- Mock modules
M.modules = {
  game_cooldown = {
    isGroupCooldownIconActive = function() return false end,
    isCooldownIconActive = function() return false end,
  },
}

-- Mock UnifiedTick
M.UnifiedTick = {
  Priority = {
    IDLE = 0,
    LOW = 1,
    NORMAL = 2,
    HIGH = 3,
    CRITICAL = 4,
  },
  register = function() end,
}

-- Mock UnifiedStorage
M.UnifiedStorage = {
  get = function() return nil end,
  set = function() end,
  save = function() end,
}

-- Mock MonsterAI (minimal)
M.MonsterAI = {
  COLLECT_ENABLED = false,
  Tracker = { monsters = {} },
  Predictor = { isFacingPosition = function() return false end },
  CONSTANTS = {
    DAMAGE = {
      CORRELATION_RADIUS = 7,
      CORRELATION_THRESHOLD = 0.4,
    },
  },
}

-- Mock EventBus (lightweight, no OTClient callbacks)
-- Modules call EventBus.on(event, cb, priority) with dot syntax
M.EventBus = {}
M.EventBus._listeners = {}
M.EventBus._queue = {}

function M.EventBus.on(event, callback, priority)
  if not M.EventBus._listeners[event] then
    M.EventBus._listeners[event] = {}
  end
  table.insert(M.EventBus._listeners[event], {
    callback = callback,
    priority = priority or 0,
  })
  table.sort(M.EventBus._listeners[event], function(a, b)
    return a.priority > b.priority
  end)
  return function()
    for i, e in ipairs(M.EventBus._listeners[event]) do
      if e.callback == callback then
        table.remove(M.EventBus._listeners[event], i)
        break
      end
    end
  end
end

function M.EventBus.emit(event, ...)
  local handlers = M.EventBus._listeners[event]
  if not handlers then return end
  for i = 1, #handlers do
    local status, err = pcall(handlers[i].callback, ...)
    if not status then
      -- Silently swallow in mock (real EventBus warns)
    end
  end
end

function M.EventBus.queue(event, ...)
  table.insert(M.EventBus._queue, {event = event, args = {...}})
end

function M.EventBus.flush()
  local items = M.EventBus._queue
  M.EventBus._queue = {}
  for _, item in ipairs(items) do
    M.EventBus.emit(item.event, table.unpack(item.args))
  end
end

function M.EventBus.reset()
  M.EventBus._listeners = {}
  M.EventBus._queue = {}
end

-- Install all mocks into global environment
function M.install()
  _G.g_game = M.g_game
  _G.g_map = M.g_map
  _G.g_clock = M.g_clock
  _G.g_things = M.g_things
  _G.g_ui = M.g_ui
  _G.SafeCreature = M.SafeCreature
  _G.ClientService = M.ClientService
  _G.SafeCall = M.SafeCall
  _G.nExBot = M.nExBot
  _G.modules = M.modules
  _G.UnifiedTick = M.UnifiedTick
  _G.UnifiedStorage = M.UnifiedStorage
  _G.MonsterAI = M.MonsterAI
  _G.EventBus = M.EventBus

  _G.now = os.time() * 1000
  _G.hppercent = function() return M.mockPlayer:getHealthPercent() end
  _G.manapercent = function() return M.mockPlayer:getManaPercent() end
  _G.mana = function() return M.mockPlayer:getMana() end
  _G.pos = function() return M.mockPlayer:getPosition() end
  _G.player = M.mockPlayer
  _G.isInPz = function() return false end
  _G.isParalyzed = function() return false end
  _G.isBurning = function() return false end
  _G.isPoisoned = function() return false end
  _G.cast = function() return true end
  _G.say = function() return true end
  _G.turn = function() return true end
  _G.useWith = function() return true end
  _G.findItem = function() return nil end
  _G.findPath = function() return {} end
  _G.getSpectators = function() return {} end
  _G.getMonsters = function() return 0 end
  _G.getPlayers = function() return 0 end
  _G.distanceFromPlayer = function() return 0 end
  _G.burstDamageValue = function() return 0 end
  _G.schedule = function() end
  _G.macro = function() return { setOn = function() end } end
  _G.warn = function() end
  _G.info = function() end
  _G.storage = _G.storage or {}
end

-- Reset mock player to defaults
function M.resetPlayer()
  M.mockPlayer._health = 1000
  M.mockPlayer._maxHealth = 1000
  M.mockPlayer._mana = 500
  M.mockPlayer._maxMana = 500
  M.mockPlayer._level = 100
  M.mockPlayer._soul = 100
  M.mockPlayer._stamina = 2400
  M.mockPlayer._speed = 220
  M.mockPlayer._position = {x = 100, y = 100, z = 7}
end

return M
