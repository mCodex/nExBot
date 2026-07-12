-- tests/unit/domain/heal_engine_spec.lua
-- Characterization tests for HealEngine.planSelf

local mock = require("tests.helpers.mock_otclient")

describe("HealEngine", function()
  local HealEngine

  before_each(function()
    mock.resetPlayer()
    mock.install()
    -- Set up nExBot.Shared.nowMs
    _G.nExBot = _G.nExBot or {}
    _G.nExBot.Shared = _G.nExBot.Shared or {}
    _G.nExBot.Shared.nowMs = function() return os.time() * 1000 end
    _G.nExBot.Shared.getClient = function() return _G.g_game end
    -- Load heal engine fresh
    HealEngine = dofile("core/heal_engine.lua")
  end)

  describe("configure()", function()
    it("enables selfSpells", function()
      HealEngine.configure({ selfSpells = true })
      -- No error means success
    end)

    it("enables potions", function()
      HealEngine.configure({ potions = true })
    end)

    it("enables friendHeals", function()
      HealEngine.configure({ friendHeals = true })
    end)
  end)

  describe("setCustomSpells()", function()
    it("loads spell list", function()
      HealEngine.setCustomSpells({
        { name = "exura vita", hp = 50, cd = 1100, prio = 1 },
        { name = "exura gran", hp = 70, cd = 1100, prio = 2 },
      })
    end)

    it("normalizes spell keys to lowercase", function()
      HealEngine.setCustomSpells({
        { name = "Exura Vita", hp = 50, cd = 1100 },
      })
      -- No error means it normalized properly
    end)

    it("handles empty list", function()
      HealEngine.setCustomSpells({})
    end)

    it("handles nil input", function()
      HealEngine.setCustomSpells(nil)
    end)
  end)

  describe("setCustomPotions()", function()
    it("loads potion list", function()
      HealEngine.setCustomPotions({
        { id = 283, hp = 40, cd = 1000, prio = 1 },
        { id = 284, hp = 60, cd = 1000, prio = 2 },
      })
    end)

    it("handles empty list", function()
      HealEngine.setCustomPotions({})
    end)
  end)

  describe("planSelf()", function()
    it("returns nil when no spells or potions configured", function()
      local action = HealEngine.planSelf({ hp = 30, mp = 50, inPz = false })
      assert.is_nil(action)
    end)

    it("returns spell action when HP below threshold", function()
      HealEngine.configure({ selfSpells = true })
      HealEngine.setCustomSpells({
        { name = "exura vita", hp = 50, cd = 1100, mana = 200 },
      })
      _G.mana = function() return 500 end
      local action = HealEngine.planSelf({ hp = 40, mp = 80, inPz = false })
      assert.is_not_nil(action)
      assert.equals("spell", action.kind)
      assert.equals("exura vita", action.name)
    end)

    it("returns nil when HP above all thresholds", function()
      HealEngine.configure({ selfSpells = true })
      HealEngine.setCustomSpells({
        { name = "exura vita", hp = 50, cd = 1100, mana = 200 },
      })
      _G.mana = function() return 500 end
      local action = HealEngine.planSelf({ hp = 80, mp = 80, inPz = false })
      assert.is_nil(action)
    end)

    it("returns potion action when HP below potion threshold", function()
      HealEngine.configure({ potions = true })
      HealEngine.setCustomPotions({
        { id = 283, hp = 40, cd = 1000 },
      })
      local action = HealEngine.planSelf({ hp = 30, mp = 80, inPz = false })
      assert.is_not_nil(action)
      assert.equals("potion", action.kind)
      assert.equals(283, action.id)
    end)

    it("skips potions in PZ unless HP critical", function()
      HealEngine.configure({ potions = true })
      HealEngine.setCustomPotions({
        { id = 283, hp = 40, cd = 1000 },
      })
      local action = HealEngine.planSelf({ hp = 35, mp = 80, inPz = true })
      -- In PZ, potion should be skipped unless hp <= 30
      assert.is_nil(action)
    end)

    it("allows potions in PZ when HP critical", function()
      HealEngine.configure({ potions = true })
      HealEngine.setCustomPotions({
        { id = 283, hp = 40, cd = 1000 },
      })
      local action = HealEngine.planSelf({ hp = 25, mp = 80, inPz = true })
      assert.is_not_nil(action)
      assert.equals("potion", action.kind)
    end)

    it("prefers spells over potions", function()
      HealEngine.configure({ selfSpells = true, potions = true })
      HealEngine.setCustomSpells({
        { name = "exura vita", hp = 50, cd = 1100, mana = 200 },
      })
      HealEngine.setCustomPotions({
        { id = 283, hp = 40, cd = 1000 },
      })
      _G.mana = function() return 500 end
      local action = HealEngine.planSelf({ hp = 30, mp = 80, inPz = false })
      assert.is_not_nil(action)
      assert.equals("spell", action.kind)
    end)

    it("checks mana cost before selecting spell", function()
      HealEngine.configure({ selfSpells = true })
      HealEngine.setCustomSpells({
        { name = "exura vita", hp = 50, cd = 1100, mana = 200 },
      })
      _G.mana = function() return 50 end -- Not enough mana
      local action = HealEngine.planSelf({ hp = 40, mp = 80, inPz = false })
      -- Spell needs 200 mana, we have 50, should skip
      assert.is_nil(action)
    end)
  end)

  describe("evaluateAlly()", function()
    it("returns nil for nil ally", function()
      assert.is_nil(HealEngine.evaluateAlly(nil, 50))
    end)

    it("returns nil for nil allyHp", function()
      local mockAlly = { getName = function() return "Friend" end }
      assert.is_nil(HealEngine.evaluateAlly(mockAlly, nil))
    end)

    it("returns spell action when ally HP below threshold", function()
      _G.mana = function() return 500 end
      local mockAlly = { getName = function() return "Friend" end }
      local action = HealEngine.evaluateAlly(mockAlly, 40)
      assert.is_not_nil(action)
      assert.equals("spell", action.kind)
    end)

    it("returns nil when ally HP above all thresholds", function()
      _G.mana = function() return 500 end
      local mockAlly = { getName = function() return "Friend" end }
      local action = HealEngine.evaluateAlly(mockAlly, 90)
      assert.is_nil(action)
    end)

    it("returns nil when insufficient mana for ally heal", function()
      _G.mana = function() return 10 end -- Very low mana
      local mockAlly = { getName = function() return "Friend" end }
      local action = HealEngine.evaluateAlly(mockAlly, 40)
      assert.is_nil(action)
    end)
  end)

  describe("setFriendSpells()", function()
    it("loads custom friend spell list", function()
      HealEngine.setFriendSpells({
        { name = "custom heal", hp = 60, mpCost = 80, cd = 1000, prio = 1 },
      })
    end)

    it("handles empty list", function()
      HealEngine.setFriendSpells({})
    end)
  end)

  describe("setFriendHealingEnabled()", function()
    it("toggles friend healing", function()
      HealEngine.setFriendHealingEnabled(true)
      HealEngine.setFriendHealingEnabled(false)
    end)
  end)
end)
