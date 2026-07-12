local attack_data = require("core.attack.attack_data")

describe("attack_data", function()
  describe("categories", function()
    it("has 5 categories", function()
      assert.equals(5, #attack_data.categories)
    end)

    it("category 1 is Targeted Spell", function()
      assert.truthy(attack_data.categories[1]:find("Targeted Spell"))
    end)

    it("category 2 is Area Rune", function()
      assert.truthy(attack_data.categories[2]:find("Area Rune"))
    end)
  end)

  describe("patterns", function()
    it("has 4 pattern groups", function()
      assert.equals(4, #attack_data.patterns)
    end)

    it("targeted spells has 10 range patterns", function()
      assert.equals(10, #attack_data.patterns[1])
    end)

    it("area runes has 3 patterns", function()
      assert.equals(3, #attack_data.patterns[2])
    end)

    it("absolute has 11 patterns", function()
      assert.equals(11, #attack_data.patterns[4])
    end)
  end)

  describe("spellShapes", function()
    it("has shape data for area runes", function()
      assert.is_table(attack_data.spellShapes[2])
    end)

    it("cross pattern has normal and safe variants", function()
      local cross = attack_data.spellShapes[2][1]
      assert.equals(2, #cross)
      assert.truthy(cross[1]:find("010"))
      assert.truthy(cross[2]:find("01110"))
    end)

    it("bomb pattern has normal and safe variants", function()
      local bomb = attack_data.spellShapes[2][2]
      assert.equals(2, #bomb)
      assert.truthy(bomb[1]:find("111"))
    end)
  end)
end)
