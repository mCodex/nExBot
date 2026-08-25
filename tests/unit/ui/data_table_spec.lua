local Harness = require("tests.helpers.widget_harness")

describe("DataTable", function()
  before_each(function()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {} }
    dofile("ui/design_system/tokens.lua")
    dofile("ui/design_system/typography.lua")
    dofile("ui/design_system/density.lua")
    dofile("ui/design_system/status.lua")
    dofile("ui/core/visual_asset_resolver.lua")
    dofile("ui/components/components.lua")
    dofile("ui/components/table_model.lua")
    dofile("ui/components/data_table.lua")
  end)

  it("reuses unchanged rows and replaces only a changed row", function()
    local root = g_ui.createWidget("Root", nil)
    local rows = { { id = "a", title = "A", revision = 1 }, { id = "b", title = "B", revision = 1 } }
    local tableView = nExBot.UI.DataTable.create(root, { id = "rules", rows = rows })
    local firstA = root:recursiveGetChildById("rules_a")
    local firstB = root:recursiveGetChildById("rules_b")
    Harness.clearLog()

    assert.is_false(tableView:update({ id = "rules", rows = rows }))
    assert.are_equal(0, Harness.countCalls("createWidget"))

    rows[2].revision = 2
    assert.is_true(tableView:update({ id = "rules", rows = rows }))
    assert.are_equal(firstA, root:recursiveGetChildById("rules_a"))
    assert.is_not_equal(firstB, root:recursiveGetChildById("rules_b"))
  end)

  it("keeps widgets while applying changed source order", function()
    local root = g_ui.createWidget("Root", nil)
    local rows = { { id = "a", title = "A" }, { id = "b", title = "B" } }
    local tableView = nExBot.UI.DataTable.create(root, { id = "rules", rows = rows })
    local body = root:recursiveGetChildById("body")
    local rowB = root:recursiveGetChildById("rules_b")

    tableView:update({ id = "rules", rows = { rows[2], rows[1] } })

    assert.are_equal(rowB, body:getChildren()[1])
  end)
end)
