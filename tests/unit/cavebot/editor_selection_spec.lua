local Selection = require("cavebot.editor_selection")

describe("CaveBot editor selection", function()
  local sel
  local items

  before_each(function()
    sel = Selection.new()
    items = {{id = 1}, {id = 2}, {id = 3}, {id = 4}, {id = 5}}
  end)

  it("starts empty", function()
    assert.are_equal(0, #sel:all())
    assert.is_false(sel:isSelected(items[1]))
  end)

  it("selectOnly replaces the whole set with a single item", function()
    sel:toggle(items[1])
    sel:toggle(items[2])
    sel:selectOnly(items[3])

    assert.are_same({items[3]}, sel:all())
    assert.is_true(sel:isSelected(items[3]))
    assert.is_false(sel:isSelected(items[1]))
  end)

  it("toggle adds an unselected item and removes a selected one", function()
    sel:toggle(items[1])
    assert.is_true(sel:isSelected(items[1]))

    sel:toggle(items[2])
    assert.is_true(sel:isSelected(items[2]))
    assert.are_equal(2, #sel:all())

    sel:toggle(items[1])
    assert.is_false(sel:isSelected(items[1]))
    assert.are_equal(1, #sel:all())
  end)

  it("selectRange selects every item between anchor and target inclusive, in list order", function()
    sel:selectRange(items[2], items[4], items)

    assert.is_false(sel:isSelected(items[1]))
    assert.is_true(sel:isSelected(items[2]))
    assert.is_true(sel:isSelected(items[3]))
    assert.is_true(sel:isSelected(items[4]))
    assert.is_false(sel:isSelected(items[5]))
  end)

  it("selectRange works when the target comes before the anchor in list order", function()
    sel:selectRange(items[4], items[2], items)

    assert.is_true(sel:isSelected(items[2]))
    assert.is_true(sel:isSelected(items[3]))
    assert.is_true(sel:isSelected(items[4]))
    assert.is_false(sel:isSelected(items[1]))
    assert.is_false(sel:isSelected(items[5]))
  end)

  it("selectRange with an anchor not present in the list just selects the target", function()
    sel:selectRange({id = "gone"}, items[2], items)

    assert.is_true(sel:isSelected(items[2]))
    assert.are_equal(1, #sel:all())
  end)

  it("clear empties the set", function()
    sel:toggle(items[1])
    sel:toggle(items[2])
    sel:clear()

    assert.are_equal(0, #sel:all())
  end)

  it("prune drops selected items no longer present in the live list", function()
    sel:toggle(items[1])
    sel:toggle(items[2])
    sel:toggle(items[3])

    sel:prune({items[1], items[3]})

    assert.is_true(sel:isSelected(items[1]))
    assert.is_false(sel:isSelected(items[2]))
    assert.is_true(sel:isSelected(items[3]))
    assert.are_equal(2, #sel:all())
  end)

  it("all() returns items in a stable insertion order", function()
    sel:toggle(items[3])
    sel:toggle(items[1])
    sel:toggle(items[2])

    assert.are_same({items[3], items[1], items[2]}, sel:all())
  end)
end)
