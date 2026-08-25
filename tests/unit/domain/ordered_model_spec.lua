describe("OrderedModel", function()
  local Model

  before_each(function()
    _G.nExBot = {}
    Model = dofile("core/ordered_model.lua")
  end)

  it("owns ordered entries and focus without UI widgets", function()
    local model = Model.new()
    local first = model:add({ action = "goto", value = "1,2,7" }, true)
    local second = model:add({ action = "label", value = "hunt" })
    local changed
    model:onFocusChange(function(current, previous) changed = { current, previous } end)

    assert.are_equal(first, model:getFocusedChild())
    assert.is_true(model:move(second, 1))
    assert.is_true(model:focus(second))
    assert.are_same({ second, first }, changed)
    assert.are_same({ second, first }, model:getChildren())
    assert.is_true(first:destroy())
    assert.are_same({ second }, model:getChildren())
  end)
end)
