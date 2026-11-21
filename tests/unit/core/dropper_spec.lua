describe("Dropper commands", function()
  before_each(function()
    package.loaded["core.Dropper"] = nil
    _G.now = 0
    _G.nExBot = {
      SharedHelpers = {
        getProfileSetting = function()
          return { enabled = false, trashItems = { 100, { id = 101 } }, useItems = {}, capItems = {} }
        end,
        setProfileSetting = function(_, value) _G.savedDropper = value end,
      },
    }
    _G.UnifiedTick = { Priority = { LOW = 1 }, register = function() end }
  end)

  it("normalizes legacy items and prevents duplicates across behaviors", function()
    dofile("core/Dropper.lua")
    local dropper = nExBot.Dropper

    assert.are_equal(2, #dropper.getProjection().rows)
    assert.is_false(dropper.addItem(101, "use"))
    assert.is_true(dropper.addItem(102, "use"))
    assert.are_equal("use", dropper.getProjection().rows[3].behavior)
  end)

  it("moves and removes items through the owner interface", function()
    dofile("core/Dropper.lua")
    local dropper = nExBot.Dropper

    assert.is_true(dropper.setBehavior(100, "lowCap"))
    local moved
    for _, row in ipairs(dropper.getProjection().rows) do
      if row.id == 100 then moved = row end
    end
    assert.are_equal("lowCap", moved.behavior)
    assert.is_true(dropper.removeItem(100))
    assert.are_equal(1, #dropper.getProjection().rows)
  end)

  it("edits an item atomically and rejects duplicate IDs", function()
    dofile("core/Dropper.lua")
    local dropper = nExBot.Dropper

    assert.is_true(dropper.updateItem(100, 200, "use"))
    assert.same({ 101, 200 }, { dropper.getProjection().rows[1].id, dropper.getProjection().rows[2].id })
    assert.are_equal("use", dropper.getProjection().rows[2].behavior)

    assert.is_false(dropper.updateItem(200, 101, "trash"))
    assert.same({ 101, 200 }, { dropper.getProjection().rows[1].id, dropper.getProjection().rows[2].id })
  end)
end)
