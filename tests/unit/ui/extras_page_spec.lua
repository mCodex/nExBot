local Harness = require("tests.helpers.widget_harness")

describe("Extras page toggles and inputs", function()
  it("renders domain values and writes changes back through setSetting", function()
    Harness.reset()
    Harness.install()

    local settings = {
      pathfinding = true,
      joinBot = false,
      talkDelay = 1000,
      useAll = "space",
      rope = 9596,
    }
    local written = {}
    _G.nExBot = { UI = {}, Extras = {
      getSetting = function(id) return settings[id] end,
      setSetting = function(id, value)
        settings[id] = value
        written[#written + 1] = { id, value }
      end,
    } }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    local Registry = dofile("ui/core/module_registry.lua")
    dofile("ui/modules/extras.lua")

    assert.same({ "extras" }, Registry.ids())

    local root = g_ui.createWidget("Root", nil)
    local shell = { defer = function(_, cb) cb() end }
    Registry.get("extras").render(shell, root)

    -- Toggles mirror the current domain values.
    assert.is_true(root:recursiveGetChildById("extras_pathfinding"):recursiveGetChildById("switch"):isChecked())
    assert.is_false(root:recursiveGetChildById("extras_joinBot"):recursiveGetChildById("switch"):isChecked())

    -- Inputs render the current domain values.
    assert.are_equal("1000", root:recursiveGetChildById("extras_talkDelay"):recursiveGetChildById("input"):getText())
    assert.are_equal("space", root:recursiveGetChildById("extras_useAll"):recursiveGetChildById("input"):getText())

    -- Flipping a toggle writes the new value to the domain.
    root:recursiveGetChildById("extras_pathfinding"):recursiveGetChildById("switch"):click()
    assert.is_false(settings.pathfinding)
    assert.same({ { "pathfinding", false } }, written)

    -- Editing a numeric input coerces to a number before writing.
    root:recursiveGetChildById("extras_talkDelay"):recursiveGetChildById("input").onTextChange(nil, "1500")
    assert.are_equal(1500, settings.talkDelay)

    -- Editing a text input writes the raw string.
    root:recursiveGetChildById("extras_useAll"):recursiveGetChildById("input").onTextChange(nil, "z")
    assert.are_equal("z", settings.useAll)
  end)
end)