-- tests/unit/domain/priorityEngine_spec.lua
-- Characterization tests for PriorityEngine

local mock = require("tests.helpers.mock_otclient")

describe("PriorityEngine", function()
  local PE

  before_each(function()
    mock.resetPlayer()
    mock.install()
    -- Set up required globals
    _G.nExBot = _G.nExBot or {}
    _G.nExBot.Shared = _G.nExBot.Shared or {}
    _G.nExBot.Shared.nowMs = function() return os.time() * 1000 end
    _G.nExBot.Shared.getClient = function() return _G.g_game end

    _G.CombatConstants = _G.CombatConstants or {}
    _G.AttackStateMachine = nil
    _G.TargetBot = nil

    -- SafeCreature mock with real creature methods
    _G.SafeCreature = {
      getId = function(c) return c and c._id end,
      getHealthPercent = function(c) return c and c._hp or 100 end,
      getName = function(c) return c and c._name or "?" end,
      getPosition = function(c) return c and c._pos end,
      isDead = function(c) return c and (c._hp or 100) <= 0 end,
      getSpeed = function(c) return c and c._speed or 220 end,
      isWalking = function(c) return false end,
      getStepTicksLeft = function(c) return 0 end,
      call = function(obj, method, default)
        if obj and obj[method] then
          local ok, r = pcall(obj[method], obj)
          return ok and r or default
        end
        return default
      end,
    }

    PE = dofile("targetbot/priority_engine.lua")
  end)

  -- Helper: create a mock creature
  local function makeCreature(id, hp, name, pos, speed)
    return {
      _id = id,
      _hp = hp or 100,
      _name = name or "Dragon",
      _pos = pos or { x = 103, y = 100, z = 7 },
      _speed = speed or 200,
      isMonster = function(self) return true end,
      isPlayer = function(self) return false end,
      isDead = function(self) return self._hp <= 0 end,
      getId = function(self) return self._id end,
      getName = function(self) return self._name end,
      getPosition = function(self) return self._pos end,
      getHealthPercent = function(self) return self._hp end,
      getSpeed = function(self) return self._speed end,
      isWalking = function(self) return false end,
      getStepTicksLeft = function(self) return 0 end,
    }
  end

  local defaultConfig = {
    priority = 5,
    maxDistance = 8,
    chase = false,
    danger = 0,
    rpSafe = false,
  }

  describe("SCORE constants", function()
    it("has expected structure", function()
      assert.is_table(PE.SCORE)
      assert.equals(1000, PE.SCORE.CONFIG_SCALE)
      assert.equals(135, PE.SCORE.HP_CRITICAL)
      assert.equals(200, PE.SCORE.ZIGZAG_PENALTY)
    end)
  end)

  describe("calculate()", function()
    it("returns 0 when creature is out of range", function()
      local creature = makeCreature(1, 80, "Dragon", { x = 200, y = 200, z = 7 })
      -- Path longer than maxDistance (8) means creature is out of range
      local path = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
      local score = PE.calculate(creature, defaultConfig, path)
      assert.equals(0, score)
    end)

    it("returns positive score for nearby creature", function()
      local creature = makeCreature(1, 80, "Dragon", { x = 103, y = 100, z = 7 })
      local path = { {}, {}, {} } -- path length 3
      local score = PE.calculate(creature, defaultConfig, path)
      assert.is_true(score > 0)
    end)

    it("higher config priority gives higher score", function()
      local creature = makeCreature(1, 80, "Dragon", { x = 103, y = 100, z = 7 })
      local path = { {}, {}, {} }
      local lowConfig = { priority = 1, maxDistance = 8 }
      local highConfig = { priority = 10, maxDistance = 8 }
      local lowScore = PE.calculate(creature, lowConfig, path)
      local highScore = PE.calculate(creature, highConfig, path)
      assert.is_true(highScore > lowScore)
    end)

    it("lower HP gives higher health score", function()
      local healthyCreature = makeCreature(1, 80, "Dragon")
      local woundedCreature = makeCreature(2, 15, "Dragon")
      local path = { {}, {}, {} }
      local s1 = PE.calculate(healthyCreature, defaultConfig, path)
      local s2 = PE.calculate(woundedCreature, defaultConfig, path)
      assert.is_true(s2 > s1)
    end)

    it("closer path gives higher distance score", function()
      local creature = makeCreature(1, 80, "Dragon")
      local shortPath = { {} } -- path length 1
      local longPath = { {}, {}, {}, {}, {}, {}, {} } -- path length 7
      local s1 = PE.calculate(creature, defaultConfig, shortPath)
      local s2 = PE.calculate(creature, defaultConfig, longPath)
      assert.is_true(s1 > s2)
    end)

    it("returns non-negative score", function()
      local creature = makeCreature(1, 100, "Dragon")
      local path = { {}, {}, {} }
      local score = PE.calculate(creature, defaultConfig, path)
      assert.is_true(score >= 0)
    end)

    it("returns reduced score when path exceeds maxDistance by 2 but HP low", function()
      local creature = makeCreature(1, 10, "Dragon")
      local config = { priority = 5, maxDistance = 5 }
      local path = { 1, 2, 3, 4, 5, 6, 7 } -- path length 7 > maxDistance 5
      local score = PE.calculate(creature, config, path)
      -- Should get reduced score (priority * 400) for low HP out-of-range
      assert.is_true(score > 0)
    end)
  end)

  describe("shouldAllowSwitch()", function()
    it("allows switch when no current target", function()
      local allowed, reason = PE.shouldAllowSwitch(1, 500, 80)
      assert.is_true(allowed)
    end)

    it("allows switch with high priority", function()
      local allowed, reason = PE.shouldAllowSwitch(1, 500, 80)
      assert.is_true(allowed)
    end)
  end)
end)
