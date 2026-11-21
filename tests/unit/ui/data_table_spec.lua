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

  it("reuses unchanged rows and updates only a changed row", function()
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
    assert.are_equal(firstB, root:recursiveGetChildById("rules_b"))
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

  it("updates changed row data without replacing its widget", function()
    local root = g_ui.createWidget("Root", nil)
    local rows = { { id = "a", title = "A", revision = 1 } }
    local tableView = nExBot.UI.DataTable.create(root, { id = "rules", rows = rows })
    local rowWidget = root:recursiveGetChildById("rules_a")

    rows[1].title = "Updated"
    rows[1].revision = 2
    assert.is_true(tableView:update({ id = "rules", rows = rows }))

    assert.are_equal(rowWidget, root:recursiveGetChildById("rules_a"))
    assert.are_equal("Updated", rowWidget:recursiveGetChildById("title"):getText())
  end)

  it("uses a bounded displayed-field fingerprint when revisions are absent", function()
    local TableModel = nExBot.UI["ui.components.table_model"]
    local first = TableModel.project({
      rows = { { id = "a", title = "A", secondary = "one" } },
    })
    local second = TableModel.project({
      rows = { { id = "a", title = "A", secondary = "two" } },
    })

    assert.is_true(#first.fingerprint <= 256)
    assert.is_not_equal(first.fingerprint, second.fingerprint)
  end)
end)
