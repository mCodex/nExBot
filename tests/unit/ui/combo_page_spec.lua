local Harness = require("tests.helpers.widget_harness")

describe("Combo page", function()
  it("renders toggles from settings and writes through setSetting", function()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {} }
    local settings = {
      enabled = true,
      onSayEnabled = true,
      onShootEnabled = false,
      onCastEnabled = true,
      followLeaderEnabled = false,
      attackLeaderTargetEnabled = true,
      attackSpellEnabled = false,
      attackItemEnabled = false,
      commandsEnabled = true,
    }
    local setCalls = {}
    _G.ComboBot = {
      isOn = function() return settings.enabled end,
      setOn = function() settings.enabled = true end,
      setOff = function() settings.enabled = false end,
      getSetting = function(key) return settings[key] end,
      setSetting = function(key, value)
        settings[key] = value
        setCalls[#setCalls + 1] = { key, value }
      end,
    }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    dofile("ui/core/module_registry.lua")
    dofile("ui/modules/combo.lua")

    local root = g_ui.createWidget("Root", nil)
    local shell = {
      defer = function(_, callback) callback() end,
      renderCurrent = function(self)
        root:destroyChildren()
        nExBot.UI.ModuleRegistry.get("combo").render(self, root)
      end,
    }
    shell:renderCurrent()

    assert.is_true(root:recursiveGetChildById("comboEnabled"):recursiveGetChildById("switch"):isChecked())
    assert.is_true(root:recursiveGetChildById("comboTrigger_onSayEnabled"):recursiveGetChildById("switch"):isChecked())
    assert.is_false(root:recursiveGetChildById("comboTrigger_onShootEnabled"):recursiveGetChildById("switch"):isChecked())
    assert.is_true(root:recursiveGetChildById("comboAction_attackLeaderTargetEnabled"):recursiveGetChildById("switch"):isChecked())

    root:recursiveGetChildById("comboAction_attackSpellEnabled"):recursiveGetChildById("switch"):click()
    assert.same({ "attackSpellEnabled", true }, setCalls[1])

    root:recursiveGetChildById("comboEnabled"):recursiveGetChildById("switch"):click()
    assert.is_false(settings.enabled)
  end)
end)