local attack_config = require("core.attack.attack_config")

describe("attack_config", function()
  it("createDefaults returns 5 profiles", function()
    local defaults = attack_config.createDefaults()
    assert.equals(5, #defaults)
  end)

  it("each profile has required fields", function()
    local defaults = attack_config.createDefaults()
    for i = 1, 5 do
      assert.is_table(defaults[i].attackTable)
      assert.equals("Profile #" .. i, defaults[i].name)
      assert.is_true(defaults[i].Cooldown)
      assert.is_true(defaults[i].Visible)
      assert.equals(5, defaults[i].AntiRsRange)
    end
  end)

  it("first profile is enabled by default", function()
    local defaults = attack_config.createDefaults()
    assert.is_true(defaults[1].enabled)
  end)

  it("profiles 2-5 are disabled by default", function()
    local defaults = attack_config.createDefaults()
    for i = 2, 5 do
      assert.is_false(defaults[i].enabled)
    end
  end)

  it("validateProfile accepts valid profile", function()
    local profile = {
      enabled = false,
      attackTable = {},
      name = "Test",
      Cooldown = true,
      Visible = true,
      AntiRsRange = 5,
    }
    assert.is_true(attack_config.validateProfile(profile))
  end)

  it("validateProfile rejects nil", function()
    assert.is_false(attack_config.validateProfile(nil))
  end)

  it("validateProfile rejects missing attackTable", function()
    local profile = { enabled = false, name = "Test" }
    assert.is_false(attack_config.validateProfile(profile))
  end)

  it("ensureDefaults creates profiles when missing", function()
    local config = {}
    attack_config.ensureDefaults(config, "attackbot")
    assert.is_table(config.attackbot)
    assert.equals(5, #config.attackbot)
  end)

  it("ensureDefaults preserves existing profiles", function()
    local config = {
      attackbot = {
        [1] = { enabled = true, attackTable = {}, name = "Custom" },
      }
    }
    attack_config.ensureDefaults(config, "attackbot")
    assert.equals("Custom", config.attackbot[1].name)
  end)

  it("getActiveProfile returns current profile", function()
    local config = {
      currentBotProfile = 2,
      attackbot = {
        [1] = { name = "Profile #1" },
        [2] = { name = "Profile #2" },
      }
    }
    local settings = attack_config.getActiveProfile(config, "attackbot")
    assert.equals("Profile #2", settings.name)
  end)

  it("getActiveProfile falls back to profile 1", function()
    local config = {
      currentBotProfile = 99,
      attackbot = {
        [1] = { name = "Profile #1" },
      }
    }
    local settings = attack_config.getActiveProfile(config, "attackbot")
    assert.equals("Profile #1", settings.name)
  end)
end)
