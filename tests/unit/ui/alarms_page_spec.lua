local Harness = require("tests.helpers.widget_harness")

describe("Alarms page", function()
  it("renders alarm rows and toggles through setAlarm", function()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {} }
    local alarmRows = {
      { id = "lowHealth", title = "Low Health", parent = "alarms", enabled = true, value = 20 },
      { id = "ignoreFriends", title = "Ignore Friends", parent = "settings", enabled = false, value = nil },
      { id = "customMessage", title = "Custom Message", parent = "alarms", enabled = false, value = "loot" },
    }
    local setCalls = {}
    _G.Alarms = {
      isOn = function() return true end,
      setOn = function() end,
      setOff = function() end,
      getAlarms = function() return alarmRows end,
      setAlarm = function(id, key, value) setCalls[#setCalls + 1] = { id, key, value } end,
    }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    dofile("ui/components/table_model.lua")
    nExBot.UI.VisualAssetResolver = { item = function() return { name = "" } end }
    dofile("ui/components/data_table.lua")
    dofile("ui/core/module_registry.lua")
    dofile("ui/modules/alarms.lua")

    local root = g_ui.createWidget("Root", nil)
    local shell = {
      defer = function(_, callback) callback() end,
      renderCurrent = function(self)
        root:destroyChildren()
        nExBot.UI.ModuleRegistry.get("alarms").render(self, root)
      end,
    }
    shell:renderCurrent()

    assert.is_true(root:recursiveGetChildById("alarmsEnabled"):recursiveGetChildById("switch"):isChecked())
    assert.is_truthy(root:recursiveGetChildById("alarmTable_lowHealth"))
    assert.are_equal("Low Health", root:recursiveGetChildById("alarmTable_lowHealth"):recursiveGetChildById("title"):getText())
    assert.are_equal("Alarm: 20", root:recursiveGetChildById("alarmTable_lowHealth"):recursiveGetChildById("secondary"):getText())

    root:recursiveGetChildById("alarmToggle_customMessage"):click()
    assert.same({ "customMessage", "enabled", true }, setCalls[1])
  end)
end)