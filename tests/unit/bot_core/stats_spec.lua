-- tests/unit/bot_core/stats_spec.lua
-- Characterization tests for BotCore.Stats

local mock = require("tests.helpers.mock_otclient")

describe("BotCore.Stats", function()
  local Stats

  before_each(function()
    mock.resetPlayer()
    mock.install()
    -- Load the module fresh
    Stats = dofile("core/bot_core/stats.lua")
    Stats.invalidate()
  end)

  describe("update()", function()
    it("returns cache with default values when no player", function()
      _G.ClientService = { getLocalPlayer = function() return nil end }
      local result = Stats.update()
      assert.is_table(result)
      assert.equals(0, result.hp)
    end)

    it("reads player health on update", function()
      mock.mockPlayer._health = 750
      mock.mockPlayer._maxHealth = 1000
      local result = Stats.update()
      assert.equals(750, result.hp)
      assert.equals(1000, result.maxHp)
      assert.equals(75, result.hpPercent)
    end)

    it("reads player mana on update", function()
      mock.mockPlayer._mana = 300
      mock.mockPlayer._maxMana = 600
      local result = Stats.update()
      assert.equals(300, result.mp)
      assert.equals(600, result.maxMp)
      assert.equals(50, result.mpPercent)
    end)

    it("skips update if already updated this tick", function()
      mock.mockPlayer._health = 800
      local r1 = Stats.update()
      local hp1 = r1.hp
      mock.mockPlayer._health = 200
      local r2 = Stats.update()
      -- Should still be 800 because same tick
      assert.equals(800, r2.hp)
    end)

    it("updates when now changes", function()
      mock.mockPlayer._health = 800
      Stats.update()
      _G.now = _G.now + 1
      mock.mockPlayer._health = 500
      local result = Stats.update()
      assert.equals(500, result.hp)
    end)
  end)

  describe("getters", function()
    it("getHp returns cached hp", function()
      mock.mockPlayer._health = 999
      Stats.update()
      assert.equals(999, Stats.getHp())
    end)

    it("getMaxHp returns cached maxHp", function()
      mock.mockPlayer._maxHealth = 2000
      Stats.update()
      assert.equals(2000, Stats.getMaxHp())
    end)

    it("getMp returns cached mp", function()
      mock.mockPlayer._mana = 150
      Stats.update()
      assert.equals(150, Stats.getMp())
    end)

    it("getMpPercent returns percentage", function()
      mock.mockPlayer._mana = 250
      mock.mockPlayer._maxMana = 500
      Stats.update()
      assert.equals(50, Stats.getMpPercent())
    end)

    it("getLevel returns cached level", function()
      mock.mockPlayer._level = 200
      Stats.update()
      assert.equals(200, Stats.getLevel())
    end)

    it("getSoul returns cached soul", function()
      mock.mockPlayer._soul = 80
      Stats.update()
      assert.equals(80, Stats.getSoul())
    end)

    it("getSpeed returns cached speed", function()
      mock.mockPlayer._speed = 350
      Stats.update()
      assert.equals(350, Stats.getSpeed())
    end)
  end)

  describe("get(statName)", function()
    it("returns hpPercent for 'HP%'", function()
      mock.mockPlayer._health = 500
      mock.mockPlayer._maxHealth = 1000
      Stats.update()
      assert.equals(50, Stats.get("HP%"))
    end)

    it("returns mpPercent for 'MP%'", function()
      mock.mockPlayer._mana = 200
      mock.mockPlayer._maxMana = 400
      Stats.update()
      assert.equals(50, Stats.get("MP%"))
    end)

    it("returns hp for 'HP'", function()
      mock.mockPlayer._health = 777
      Stats.update()
      assert.equals(777, Stats.get("HP"))
    end)

    it("returns mp for 'MP'", function()
      mock.mockPlayer._mana = 333
      Stats.update()
      assert.equals(333, Stats.get("MP"))
    end)

    it("returns level for 'level'", function()
      mock.mockPlayer._level = 150
      Stats.update()
      assert.equals(150, Stats.get("level"))
    end)

    it("returns nil for unknown stat", function()
      assert.is_nil(Stats.get("unknown"))
    end)
  end)

  describe("getAll()", function()
    it("returns full cache table", function()
      mock.mockPlayer._health = 600
      mock.mockPlayer._maxHealth = 1000
      mock.mockPlayer._mana = 300
      mock.mockPlayer._maxMana = 600
      Stats.update()
      local all = Stats.getAll()
      assert.equals(600, all.hp)
      assert.equals(1000, all.maxHp)
      assert.equals(60, all.hpPercent)
      assert.equals(300, all.mp)
      assert.equals(600, all.maxMp)
      assert.equals(50, all.mpPercent)
    end)
  end)

  describe("setHealth()", function()
    it("updates hp and hpPercent directly", function()
      Stats.setHealth(800, 1000)
      assert.equals(800, Stats.getHp())
      assert.equals(1000, Stats.getMaxHp())
      assert.equals(80, Stats.getHpPercent())
    end)

    it("handles zero maxHp safely", function()
      Stats.setHealth(100, 0)
      assert.equals(100, Stats.getHp())
      assert.equals(0, Stats.getHpPercent())
    end)
  end)

  describe("setMana()", function()
    it("updates mp and mpPercent directly", function()
      Stats.setMana(250, 500)
      assert.equals(250, Stats.getMp())
      assert.equals(500, Stats.getMaxMp())
      assert.equals(50, Stats.getMpPercent())
    end)
  end)

  describe("invalidate()", function()
    it("forces next update to refresh", function()
      mock.mockPlayer._health = 900
      Stats.update()
      assert.equals(900, Stats.getHp())
      Stats.invalidate()
      _G.now = _G.now + 1
      mock.mockPlayer._health = 100
      Stats.update()
      assert.equals(100, Stats.getHp())
    end)
  end)

  describe("safePercent()", function()
    it("returns 0 for nil max", function()
      Stats.setHealth(100, 0)
      assert.equals(0, Stats.getHpPercent())
    end)

    it("returns 0 for zero max", function()
      Stats.setHealth(100, 0)
      assert.equals(0, Stats.getHpPercent())
    end)

    it("calculates correct percentage", function()
      Stats.setHealth(333, 1000)
      assert.equals(33, Stats.getHpPercent())
    end)
  end)

  describe("isFresh()", function()
    it("returns true immediately after update", function()
      Stats.update()
      assert.is_true(Stats.isFresh(1000))
    end)

    it("returns false after long time", function()
      Stats.update()
      _G.now = _G.now + 5000
      assert.is_false(Stats.isFresh(100))
    end)
  end)
end)
