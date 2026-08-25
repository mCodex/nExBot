local Harness = require("tests.helpers.widget_harness")

local function spinBox(parent, id)
  local widget = g_ui.createWidget("SpinBox", parent)
  widget:setId(id)
  local setText = widget.setText
  widget.setText = function(self, value)
    self:setValue(tonumber(value) or 0)
    return setText(self, value)
  end
  return widget
end

local function loadSupplies()
  Harness.reset()
  Harness.install()

  local window = g_ui.createWidget("MainWindow")
  for _, id in ipairs({ "items", "profiles" }) do
    window[id] = g_ui.createWidget("Panel", window)
    window[id]:setId(id)
  end
  for _, id in ipairs({ "capSwitch", "SoftBoots", "imbues", "staminaSwitch", "newProfile", "increment", "decrement" }) do
    window[id] = g_ui.createWidget("BotSwitch", window)
    window[id]:setId(id)
  end
  window.capValue = spinBox(window, "capValue")
  window.staminaValue = spinBox(window, "staminaValue")

  UI.createWindow = function() return window end
  UI.createWidget = function(style, parent)
    local widget = g_ui.createWidget(style, parent)
    if style == "ItemPanel" then
      widget.id = g_ui.createWidget("UIItem", widget)
      widget.id.setShowCount = function() end
      widget.min = spinBox(widget, "min")
      widget.max = spinBox(widget, "max")
      widget.avg = spinBox(widget, "avg")
    elseif style == "ProfileLabel" then
      widget.remove = g_ui.createWidget("Button", widget)
    end
    return widget
  end

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
end)
