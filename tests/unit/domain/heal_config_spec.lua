local heal_config = require("core.heal.heal_config")

describe("heal_config", function()
  it("createDefaults returns 5 profiles", function()
    local defaults = heal_config.createDefaults()
    assert.equals(5, #defaults)
  end)

  it("each profile has required fields", function()
    local defaults = heal_config.createDefaults()
    for i = 1, 5 do
      assert.is_false(defaults[i].enabled)
      assert.is_table(defaults[i].spellTable)
      assert.is_table(defaults[i].itemTable)
      assert.equals("Profile #" .. i, defaults[i].name)
      assert.is_true(defaults[i].Visible)
      assert.is_true(defaults[i].Cooldown)
    end
  end)

  it("MessageDelay stays fixed at its old UI default (control was removed)", function()
    local defaults = heal_config.createDefaults()
    for i = 1, 5 do
      assert.is_false(defaults[i].MessageDelay)
    end
  end)

  it("validateProfile accepts valid profile", function()
    local profile = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Test",
      Visible = true,
      Cooldown = true,
    }
    assert.is_true(heal_config.validateProfile(profile))
  end)

  it("validateProfile rejects nil", function()
    assert.is_false(heal_config.validateProfile(nil))
  end)

  it("validateProfile rejects empty table", function()
    assert.is_false(heal_config.validateProfile({}))
  end)

  it("validateProfile rejects missing spellTable", function()
    local profile = { enabled = false, itemTable = {}, name = "Test", Visible = true, Cooldown = true }
    assert.is_false(heal_config.validateProfile(profile))
  end)

  it("ensureDefaults creates profiles when missing", function()
    local config = {}
    heal_config.ensureDefaults(config, "healbot")
    assert.is_table(config.healbot)
    assert.equals(5, #config.healbot)
  end)

  it("ensureDefaults preserves existing profiles", function()
    local config = {
      healbot = {
        [1] = { enabled = true, spellTable = {}, itemTable = {}, name = "Custom" },
      }
    }
    heal_config.ensureDefaults(config, "healbot")
    assert.equals("Custom", config.healbot[1].name)
  end)
end)
