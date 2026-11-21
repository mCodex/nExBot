local Harness = require("tests.helpers.widget_harness")

describe("Push page", function()
  it("renders config and writes through setConfig", function()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {} }
    local config = { enabled = true, pushDelay = 1060, pushMaxRuneId = 3188, mwallBlockId = 2128, pushMaxKey = "PageUp" }
    local setCalls = {}
    _G.PushMax = {
      isOn = function() return config.enabled end,
      setOn = function() config.enabled = true end,
      setOff = function() config.enabled = false end,
      getConfig = function() return config end,
      setConfig = function(key, value)
        config[key] = value
        setCalls[#setCalls + 1] = { key, value }
      end,
    }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    dofile("ui/core/module_registry.lua")
    dofile("ui/modules/pushmax.lua")

    local root = g_ui.createWidget("Root", nil)
    local shell = {
      defer = function(_, callback) callback() end,
      renderCurrent = function(self)
        root:destroyChildren()
        nExBot.UI.ModuleRegistry.get("pushmax").render(self, root)
      end,
    }
    shell:renderCurrent()

    assert.is_true(root:recursiveGetChildById("pushEnabled"):recursiveGetChildById("switch"):isChecked())
    assert.are_equal("PageUp", root:recursiveGetChildById("pushKey"):recursiveGetChildById("input"):getText())

    root:recursiveGetChildById("pushKey"):recursiveGetChildById("input").onTextChange(nil, "F1")
    assert.same({ "pushMaxKey", "F1" }, setCalls[1])

    root:recursiveGetChildById("pushDelay"):recursiveGetChildById("combo").onOptionChange(nil, "1200", 1200)
    assert.same({ "pushDelay", 1200 }, setCalls[2])
  end)
end)