local Harness = require("tests.helpers.widget_harness")

describe("auxiliary managers", function()
  it("shows truthful manager availability and actions", function()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {}, Equipper = { isEnabled = function() return true end, show = function() end } }
    _G.AttackBot = { show = function() end }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/core/actions.lua")
    dofile("ui/components/components.lua")
    local Registry = dofile("ui/core/module_registry.lua")
    dofile("ui/modules/auxiliary.lua")

    local root = g_ui.createWidget("Root", nil)
    Registry.get("equipment").render({}, root)
    local equipper = root:recursiveGetChildById("manager_open_equipper")
    assert.are_equal("On", equipper:recursiveGetChildById("status"):getText())
    assert.is_nil(root:recursiveGetChildById("manager_open_attack_config"):recursiveGetChildById("status"))
    assert.are_equal("Not loaded", root:recursiveGetChildById("manager_open_healing"):recursiveGetChildById("status"):getText())
  end)

  it("refreshes the page after changing a manager state", function()
    Harness.reset()
    Harness.install()
    local isEnabled = true
    _G.nExBot = { UI = {}, Equipper = {
      isEnabled = function() return isEnabled end,
      setEnabled = function(value) isEnabled = value end,
      show = function() end,
    } }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/core/actions.lua")
    dofile("ui/components/components.lua")
    local Registry = dofile("ui/core/module_registry.lua")
    dofile("ui/modules/auxiliary.lua")

    local refreshes = 0
    local shell = { renderCurrent = function() refreshes = refreshes + 1 end }
    local root = g_ui.createWidget("Root", nil)
    Registry.get("equipment").render(shell, root)
    root:recursiveGetChildById("toggle_equipper").onClick()

    assert.is_false(isEnabled)
    assert.are_equal(1, refreshes)
  end)

  it("toggles quiver through its existing BotDB owner", function()
    _G.nExBot = { UI = {} }
    local changed
    _G.BotDB = {
      getMacroState = function() return true end,
      setMacroState = function(key, value) changed = { key, value } end,
    }
    local Actions = dofile("ui/core/actions.lua")
    assert.is_true(Actions.run("toggle_quiver"))
    assert.same({ "quiverManager", false }, changed)
  end)
end)
