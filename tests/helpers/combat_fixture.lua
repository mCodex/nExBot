local M = {}

local function pos(x, y, z) return { x = x, y = y, z = z or 7 } end

local function makeCreature(id, name, hp, x, y, z)
  local c = {
    _id = id, _name = name, _hp = hp or 100,
    _position = pos(x or 100, y or 100, z or 7),
    _dead = false, _removed = false, _direction = 0,
    _speed = 200, _isWalking = false,
  }
  function c:getId() return self._id end
  function c:getName() return self._name end
  function c:getPosition() return self._position end
  function c:getHealthPercent() return self._dead and 0 or self._hp end
  function c:isDead() return self._dead or self._hp <= 0 end
  function c:isRemoved() return self._removed end
  function c:isMonster() return true end
  function c:isPlayer() return false end
  function c:isNpc() return false end
  function c:getSpeed() return self._speed end
  function c:isWalking() return self._isWalking end
  function c:getDirection() return self._direction end
  function c:getStepTicksLeft() return 0 end
  function c:setHp(hp) self._hp = hp end
  function c:setPosition(x, y, z) self._position = pos(x, y, z) end
  function c:kill() self._dead = true; self._hp = 0 end
  function c:remove() self._removed = true end
  return c
end

local function makePlayer(x, y, z)
  local p = {
    _position = pos(x or 100, y or 100, z or 7),
    _health = 1000, _maxHealth = 1000, _speed = 220,
    _dead = false, _direction = 2,
  }
  function p:getId() return 99999 end
  function p:getName() return "TestPlayer" end
  function p:getPosition() return self._position end
  function p:getHealth() return self._health end
  function p:getMaxHealth() return self._maxHealth end
  function p:getHealthPercent() return math.floor(self._health / self._maxHealth * 100) end
  function p:getSpeed() return self._speed end
  function p:getDirection() return self._direction end
  function p:isDead() return self._dead end
  function p:isMonster() return false end
  function p:isPlayer() return true end
  function p:isLocalPlayer() return true end
  function p:isWalking() return false end
  function p:setPosition(x, y, z) self._position = pos(x, y, z) end
  return p
end

function M.new()
  local fixture = {
    clock = 1000,
    player = makePlayer(100, 100, 7),
    monsters = {},
    _attackLog = {},
    _cancelLog = {},
    _currentAttackTarget = nil,
    _reachabilityOverrides = {},
    _pathResults = {},
    _losResults = {},
    _mapGeneration = 1,
    _eventLog = {},
  }

  function fixture:addMonster(id, name, hp, x, y, z)
    local c = makeCreature(id, name, hp, x, y, z)
    self.monsters[id] = c
    return c
  end

  function fixture:setReachability(id, attackable, reason)
    self._reachabilityOverrides[id] = { attackable = attackable, reason = reason or "test_override" }
  end

  function fixture:setPathResult(destKey, path)
    self._pathResults[destKey] = path
  end

  function fixture:setLOS(from, to, clear)
    local fk = tostring(from.x) .. "," .. tostring(from.y) .. "," .. tostring(from.z)
    local tk = tostring(to.x) .. "," .. tostring(to.y) .. "," .. tostring(to.z)
    self._losResults[fk .. ">" .. tk] = clear
  end

  function fixture:advanceClock(ms)
    self.clock = self.clock + ms
  end

  function fixture:tick(n)
    n = n or 1
    for _ = 1, n do
      self.clock = self.clock + 100
    end
  end

  function fixture:getAttackLog() return self._attackLog end
  function fixture:getCancelLog() return self._cancelLog end
  function fixture:clearLogs() self._attackLog = {}; self._cancelLog = {} end

  function fixture:checkAttacking(id)
    assert(self._currentAttackTarget == id,
      "Expected attacking creature " .. tostring(id) .. " but got " .. tostring(self._currentAttackTarget))
  end

  function fixture:checkNotCancelled()
    assert(#self._cancelLog == 0,
      "Expected no cancelAttack calls but got " .. #self._cancelLog)
  end

  function fixture:checkCancelledCount(n)
    assert(#self._cancelLog == n,
      "Expected " .. n .. " cancelAttack calls but got " .. #self._cancelLog)
  end

  function fixture:installGlobals()
    local self = self

    _G.now = self.clock
    _G.player = self.player
    _G.nExBot = _G.nExBot or {}
    _G.nExBot.Shared = _G.nExBot.Shared or {}
    _G.nExBot.Shared.nowMs = function() return self.clock end
    _G.nExBot.Shared.getClient = function() return _G.g_game end
    _G.nExBot.zChanging = function() return false end

    _G.SafeCreature = {
      getId = function(c) return c and c.getId and c:getId() or nil end,
      getName = function(c) return c and c.getName and c:getName() or "?" end,
      getPosition = function(c) return c and c.getPosition and c:getPosition() or nil end,
      getHealthPercent = function(c) return c and c.getHealthPercent and c:getHealthPercent() or 100 end,
      isDead = function(c) return not c or (c.isDead and c:isDead()) or false end,
      isRemoved = function(c) return c and c.isRemoved and c:isRemoved() or false end,
      isMonster = function(c) return c and c.isMonster and c:isMonster() or false end,
    }

    _G.g_game = _G.g_game or {}
    _G.g_game.getLocalPlayer = function() return self.player end
    _G.g_game.getAttackingCreature = function()
      if self._currentAttackTarget then
        return self.monsters[self._currentAttackTarget]
      end
      return nil
    end
    _G.g_game.attack = function(creature)
      local id = creature and creature:getId()
      self._attackLog[#self._attackLog + 1] = { id = id, at = self.clock }
      self._currentAttackTarget = id
      return true
    end
    _G.g_game.cancelAttackAndFollow = function()
      self._cancelLog[#self._cancelLog + 1] = { at = self.clock }
      self._currentAttackTarget = nil
    end
    _G.g_game.isAttacking = function() return self._currentAttackTarget ~= nil end
    _G.g_game.getChaseMode = function() return 0 end
    _G.g_game.setChaseMode = function() end

    local pathOverrides = self._pathResults
    local reachOverrides = self._reachabilityOverrides

    _G.findPath = function(startPos, destPos, maxSteps, profile)
      local key = tostring(destPos.x) .. "," .. tostring(destPos.y) .. "," .. tostring(destPos.z)
      if pathOverrides[key] ~= nil then return pathOverrides[key] end
      local dist = math.max(math.abs(startPos.x - destPos.x), math.abs(startPos.y - destPos.y))
      if dist <= (profile and profile.marginMax or 1) and dist >= (profile and profile.marginMin or 1) then
        return {}
      end
      if dist <= maxSteps then
        local path = {}
        for _ = 1, math.ceil(dist) do path[#path + 1] = 1 end
        return path
      end
      return nil
    end

    _G.g_map = _G.g_map or {}
    _G.g_map.isSightClear = function(from, to)
      local key = tostring(from.x) .. "," .. tostring(from.y) .. "," .. tostring(from.z)
        .. ">" .. tostring(to.x) .. "," .. tostring(to.y) .. "," .. tostring(to.z)
      if self._losResults[key] ~= nil then return self._losResults[key] end
      return true
    end
    _G.g_map.getTile = function() return nil end
    _G.g_map.getMinimapColor = function() return 0 end

    local _eventHandlers = {}
    _G.EventBus = {
      on = function(event, handler, priority)
        _eventHandlers[event] = _eventHandlers[event] or {}
        _eventHandlers[event][#_eventHandlers[event] + 1] = handler
      end,
      emit = function(event, ...)
        local handlers = _eventHandlers[event]
        if handlers then
          for _, handler in ipairs(handlers) do
            pcall(handler, ...)
          end
        end
      end,
    }
    _G.UnifiedTick = nil
    _G.macro = function() end
    _G.TargetBot = _G.TargetBot or {}
    _G.TargetBot.isOn = function() return true end
    _G.MonsterAI = { _helpers = {} }
    _G.BotCore = {
      Creatures = {
        getNearby = function() return {} end,
      },
    }

    return self
  end

  return fixture
end

return M
