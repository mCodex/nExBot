local Harness = require("tests.helpers.widget_harness")

describe("Dropper page item CRUD", function()
  it("edits and deletes a selected item through Dropper commands", function()
    Harness.reset()
    Harness.install()
    local rows = { { id = 100, behavior = "trash" } }
    local updated
    local removed
    _G.nExBot = { UI = {}, Dropper = {
      getProjection = function() return { revision = 1, enabled = true, lowCap = 150, rows = rows } end,
      setEnabled = function() end,
      updateItem = function(oldId, newId, behavior)
        updated = { oldId, newId, behavior }
        return true
      end,
      removeItem = function(id) removed = id; return true end,
      addItem = function() return true end,
    } }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    dofile("ui/components/table_model.lua")
    nExBot.UI.VisualAssetResolver = { item = function(_, id) return { name = "Item " .. id } end }
    dofile("ui/components/data_table.lua")
    local Registry = dofile("ui/core/module_registry.lua")
    dofile("ui/modules/dropper.lua")

    local root = g_ui.createWidget("Root", nil)
    local shell = {
      defer = function(_, callback) callback() end,
      renderCurrent = function(self)
        root:destroyChildren()
        Registry.get("dropper").render(self, root)
      end,
    }
    shell:renderCurrent()
    root:recursiveGetChildById("edit_100"):click()
    root:recursiveGetChildById("dropperItemId"):recursiveGetChildById("input").onTextChange(nil, "200")
    root:recursiveGetChildById("dropperBehavior"):recursiveGetChildById("combo").onOptionChange(nil, nil, "use")
    root:recursiveGetChildById("saveDropperItem"):click()

    assert.same({ 100, 200, "use" }, updated)

    shell:renderCurrent()
    root:recursiveGetChildById("remove_100"):click()
    assert.are_equal(100, removed)
  end)
end)
