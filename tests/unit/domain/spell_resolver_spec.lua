local spell_resolver = require("core.heal.spell_resolver")

describe("spell_resolver", function()
  describe("convertSpellsToEngineFormat", function()
    it("returns empty table for nil input", function()
      local result = spell_resolver.convertSpellsToEngineFormat(nil)
      assert.equals(0, #result)
    end)

    it("returns empty table for empty input", function()
      local result = spell_resolver.convertSpellsToEngineFormat({})
      assert.equals(0, #result)
    end)

    it("converts valid HP spell", function()
      local spells = {
        { enabled = true, spell = "exura vita", origin = "HP", value = 50, sign = "<", cost = 60 }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(1, #result)
      assert.equals("exura vita", result[1].name)
      assert.equals(50, result[1].hp)
      assert.equals(60, result[1].mana)
    end)

    it("converts valid MP spell", function()
      local spells = {
        { enabled = true, spell = "exura gran", origin = "MP", value = 40, sign = "<", cost = 100 }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(1, #result)
      assert.equals(40, result[1].mp)
    end)

    it("skips disabled spells", function()
      local spells = {
        { enabled = false, spell = "exura vita", origin = "HP", value = 50 }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(0, #result)
    end)

    it("skips spells without name", function()
      local spells = {
        { enabled = true, spell = "", origin = "HP", value = 50 }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(0, #result)
    end)

    it("skips spells with unknown origin", function()
      local spells = {
        { enabled = true, spell = "exura vita", origin = "UNKNOWN", value = 50 }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(0, #result)
    end)

    it("skips HP spells with above sign", function()
      local spells = {
        { enabled = true, spell = "exura vita", origin = "HP", value = 50, sign = ">" }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(0, #result)
    end)

    it("assigns priority based on order", function()
      local spells = {
        { enabled = true, spell = "exura", origin = "HP", value = 70 },
        { enabled = true, spell = "exura vita", origin = "HP", value = 50 },
        { enabled = true, spell = "exura gran", origin = "HP", value = 20 }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(1, result[1].prio)
      assert.equals(2, result[2].prio)
      assert.equals(3, result[3].prio)
    end)
  end)

  describe("convertPotionsToEngineFormat", function()
    it("returns empty table for nil input", function()
      local result = spell_resolver.convertPotionsToEngineFormat(nil)
      assert.equals(0, #result)
    end)

    it("converts valid HP potion", function()
      local potions = {
        { enabled = true, item = 3160, origin = "HP", value = 40, sign = "<" }
      }
      local result = spell_resolver.convertPotionsToEngineFormat(potions)
      assert.equals(1, #result)
      assert.equals(3160, result[1].id)
      assert.equals(40, result[1].hp)
    end)

    it("skips disabled potions", function()
      local potions = {
        { enabled = false, item = 3160, origin = "HP", value = 40 }
      }
      local result = spell_resolver.convertPotionsToEngineFormat(potions)
      assert.equals(0, #result)
    end)

    it("skips potions without item ID", function()
      local potions = {
        { enabled = true, item = 0, origin = "HP", value = 40 }
      }
      local result = spell_resolver.convertPotionsToEngineFormat(potions)
      assert.equals(0, #result)
    end)
  end)
end)
