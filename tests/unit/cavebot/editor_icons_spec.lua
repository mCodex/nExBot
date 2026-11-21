local Icons = require("cavebot.editor_icons")

describe("CaveBot editor icons", function()
  it("parses the item id out of a usewith value", function()
    assert.are_equal(2160, Icons.iconFor("usewith", "2160,100,200,7"))
  end)

  it("treats a bare-number use value as an inventory item id", function()
    assert.are_equal(2160, Icons.iconFor("use", "2160"))
  end)

  it("returns no icon for a use value that is a position, not an item id", function()
    assert.is_nil(Icons.iconFor("use", "100,200,7"))
  end)

  it("maps goto/gotolabel/label to the shared waypoint sprite", function()
    assert.are_equal(3003, Icons.iconFor("goto", "100,200,7"))
    assert.are_equal(3003, Icons.iconFor("gotolabel", "start"))
    assert.are_equal(3003, Icons.iconFor("label", "start"))
  end)

  it("maps follow to the shared target sprite", function()
    assert.are_equal(3155, Icons.iconFor("follow", "Rat"))
  end)

  it("returns nil for action types with no verified sprite mapping", function()
    assert.is_nil(Icons.iconFor("delay", "500"))
    assert.is_nil(Icons.iconFor("say", "hello"))
    assert.is_nil(Icons.iconFor("npcsay", "hi"))
    assert.is_nil(Icons.iconFor("function", "return true"))
  end)

  it("returns nil for an unrecognized action or a malformed value", function()
    assert.is_nil(Icons.iconFor("usewith", "not-a-number,100,200,7"))
    assert.is_nil(Icons.iconFor(nil, "100,200,7"))
  end)

  it("maps goto/gotolabel/label/follow regardless of value, since their icon is action-driven", function()
    assert.are_equal(3003, Icons.iconFor("goto", nil))
  end)
end)
