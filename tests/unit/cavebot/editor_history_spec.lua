local History = require("cavebot.editor_history")

describe("CaveBot editor history", function()
  local hist

  before_each(function()
    hist = History.new()
  end)

  it("starts with nothing to undo", function()
    assert.is_nil(hist:undo())
  end)

  it("undo returns the last pushed snapshot", function()
    local snapshot = {kind = "delete", items = {{action = "goto", value = "1,2,3", index = 1}}}
    hist:push(snapshot)

    assert.are_same(snapshot, hist:undo())
  end)

  it("is fixed at depth 1 - pushing again replaces the previous snapshot", function()
    hist:push({kind = "delete", items = {{action = "say", value = "hi", index = 1}}})
    hist:push({kind = "reorder", items = {{action = "delay", value = "500", index = 2}}})

    local snapshot = hist:undo()
    assert.are_equal("reorder", snapshot.kind)
  end)

  it("undo consumes the snapshot - a second undo returns nil", function()
    hist:push({kind = "delete", items = {{action = "goto", value = "1,2,3", index = 1}}})

    hist:undo()
    assert.is_nil(hist:undo())
  end)

  it("clear removes any pending snapshot", function()
    hist:push({kind = "delete", items = {{action = "goto", value = "1,2,3", index = 1}}})
    hist:clear()

    assert.is_nil(hist:undo())
  end)
end)
