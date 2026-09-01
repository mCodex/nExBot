_G.nExBot = { UI = {} }
local VM = dofile("ui/core/view_model.lua")

describe("ViewModel", function()
  before_each(function()
    nExBot.UI.ViewModel = nil
    VM = dofile("ui/core/view_model.lua")
  end)

  it("creates a snapshot with schema version and revision 0", function()
    local vm = VM.new("cavebot")
    assert.are_equal(1, vm.schemaVersion)
    assert.are_equal(0, vm.revision)
    assert.are_equal("cavebot", vm.moduleId)
    assert.are_equal("LOADING", vm.state)
  end)

  it("valid states are LOADING EMPTY READY DEGRADED ERROR", function()
    for _, s in ipairs({ "LOADING", "EMPTY", "READY", "DEGRADED", "ERROR" }) do
      local vm = VM.new("x")
      assert.is_true(vm:setState(s))
      assert.are_equal(s, vm.state)
    end
  end)

  it("rejects unknown states", function()
    local vm = VM.new("x")
    assert.is_false(vm:setState("ON_FIRE"))
    assert.are_equal("LOADING", vm.state)
  end)

  it("bumps revision on every commit", function()
    local vm = VM.new("x")
    vm:setHeader({ title = "CaveBot" })
    vm:commit()
    assert.are_equal(1, vm.revision)
    vm:commit()
    assert.are_equal(2, vm.revision)
  end)

  it("commit captures generatedAt and freezes the snapshot", function()
    local vm = VM.new("x")
    local fixed = 123456
    _G.nExBot.nowMs = function() return fixed end
    vm:setHeader({ title = "T" })
    vm:commit()
    assert.are_equal(fixed, vm.snapshot.generatedAt)
    assert.are_equal("T", vm.snapshot.header.title)
    -- mutate after commit; snapshot must not see the new header
    vm:setHeader({ title = "U" })
    assert.are_equal("T", vm.snapshot.header.title)
  end)

  it("collects errors without breaking the snapshot", function()
    local vm = VM.new("x")
    vm:addError("E1")
    vm:addError("E2")
    vm:commit()
    assert.are_equal(2, #vm.snapshot.errors)
  end)

  it("setHeader/setSections/setActions are validated", function()
    local vm = VM.new("x")
    assert.is_false(vm:setHeader(nil))
    assert.is_false(vm:setSections("not-a-table"))
    assert.is_false(vm:setActions("also-not-a-table"))
    assert.is_true(vm:setActions({}))
    assert.is_true(vm:setSections({ { id = "s1", title = "S1" } }))
  end)
end)
