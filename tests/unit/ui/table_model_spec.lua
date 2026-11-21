local TableModel = require("ui.components.table_model")

describe("DataTable model", function()
  local rows = {
    { id = "a", name = "Exori Gran", revision = 1 },
    { id = "b", name = "SD Rune", revision = 3 },
    { id = "c", name = "Ultimate Healing Rune", revision = 2 },
  }

  it("keeps stable keys and filters without changing source order", function()
    local model = TableModel.project({
      rows = rows,
      rowKey = function(row) return row.id end,
      query = "rune",
      searchText = function(row) return row.name end,
      pageSize = 1,
      page = 2,
    })

    assert.are_equal(2, model.total)
    assert.are_equal(2, model.pages)
    assert.are_equal("c", model.rows[1].key)
  end)

  it("projects one compact record in narrow density", function()
    local model = TableModel.project({ rows = { rows[1] }, density = "narrow" })

    assert.are_equal("narrow", model.density)
    assert.are_equal("a", model.rows[1].key)
  end)

  it("fingerprints unchanged rows and detects changed revisions", function()
    local first = TableModel.project({ rows = rows })
    local second = TableModel.project({ rows = rows })
    rows[2].revision = 4
    local changed = TableModel.project({ rows = rows })

    assert.are_equal(first.fingerprint, second.fingerprint)
    assert.is_not_equal(first.fingerprint, changed.fingerprint)
    rows[2].revision = 3
  end)
end)
