local Harness = require("tests.helpers.widget_harness")

local function loadSupplies()
  Harness.reset()
  Harness.install()

  _G.SuppliesConfig = {
    supplies = {
      currentProfile = "Default",
      Default = {
        items = { ["268"] = { min = 50, max = 200, avg = 25 } },
        capSwitch = false,
        SoftBoots = false,
        imbues = false,
        staminaSwitch = false,
      },
    },
  }
  _G.nExBotConfigSave = function() end

  dofile("core/supplies.lua")
  return Supplies
end

describe("Supplies embedded API", function()
  it("preserves profiles, item values, conditions, and validation", function()
    local supplies = loadSupplies()

    assert.same({ "Default" }, supplies.listProfiles())
    assert.are_equal("Default", supplies.getCurrentProfile())
    assert.is_true(supplies.setItem(3155, 10, 100, 5))
    assert.same({ min = 10, max = 100, avg = 5 }, supplies.getItemsData()["3155"])
    assert.is_false(supplies.setItem(3155, -1, 100, 5))
    assert.is_true(supplies.setCondition("capacity", true, 120))
    assert.same({ enabled = true, value = 120 }, supplies.getAdditionalData().capacity)
    assert.is_true(supplies.removeItem(3155))
    assert.is_nil(supplies.getItemsData()["3155"])
  end)

  it("keeps profile switching and the retired show action safe", function()
    local supplies = loadSupplies()

    assert.is_false(supplies.setCurrentProfile("Missing"))
    SuppliesConfig.supplies["Alt"] = { items = {} }
    assert.is_true(supplies.setCurrentProfile("Alt"))
    assert.are_equal("Alt", supplies.getCurrentProfile())
    assert.is_nil(loadSupplies and supplies.show())

    assert.is_true(supplies.createProfile())
    assert.is_true(supplies.listProfiles()[3] == "Profile #3")
  end)
end)