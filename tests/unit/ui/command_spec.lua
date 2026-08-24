_G.nExBot = { UI = {} }
local Commands = dofile("ui/core/command.lua")

local function reset()
  nExBot.UI.CommandDispatcher = nil
  Commands = dofile("ui/core/command.lua")
end

describe("CommandDispatcher", function()
  before_each(reset)

  it("dispatches a registered command and returns a typed result", function()
    local dispatcher = Commands.new()
    dispatcher:register("EnableModule", {
      prerequisite = function() return true end,
      run = function() return { ok = true, data = "enabled" } end,
    })
    local result = dispatcher:execute("EnableModule", {})
    assert.is_true(result.ok)
    assert.are_equal("enabled", result.data)
  end)

  it("returns failure for an unknown command", function()
    local dispatcher = Commands.new()
    local result = dispatcher:execute("DoesNotExist", {})
    assert.is_false(result.ok)
    assert.are_equal("UNKNOWN_COMMAND", result.error)
  end)

  it("fails when the prerequisite is not met", function()
    local dispatcher = Commands.new()
    dispatcher:register("SaveProfile", {
      prerequisite = function() return false, "profile_locked" end,
      run = function() return { ok = true } end,
    })
    local result = dispatcher:execute("SaveProfile", {})
    assert.is_false(result.ok)
    assert.are_equal("profile_locked", result.error)
  end)

  it("fails when run returns an error tuple", function()
    local dispatcher = Commands.new()
    dispatcher:register("AddWaypoint", {
      run = function() return false, "no_active_route" end,
    })
    local result = dispatcher:execute("AddWaypoint", {})
    assert.is_false(result.ok)
    assert.are_equal("no_active_route", result.error)
  end)

  it("catches exceptions in run and reports them as typed errors", function()
    local dispatcher = Commands.new()
    dispatcher:register("Bad", {
      run = function() error("boom") end,
    })
    local result = dispatcher:execute("Bad", {})
    assert.is_false(result.ok)
    assert.are_equal("COMMAND_ERROR", result.error)
  end)

  it("requires run to return a typed result table", function()
    local dispatcher = Commands.new()
    dispatcher:register("Weird", {
      run = function() return 42 end,
    })
    local result = dispatcher:execute("Weird", {})
    assert.is_false(result.ok)
    assert.are_equal("BAD_RESULT", result.error)
  end)

  it("supports destructive commands requiring confirmation", function()
    local dispatcher = Commands.new()
    local ran = false
    dispatcher:register("ResetModel", {
      destructive = true,
      run = function() ran = true return { ok = true } end,
    })
    local blocked = dispatcher:execute("ResetModel", {}, false)
    assert.is_false(blocked.ok)
    assert.are_equal("CONFIRMATION_REQUIRED", blocked.error)
    assert.is_false(ran)

    local confirmed = dispatcher:execute("ResetModel", {}, true)
    assert.is_true(confirmed.ok)
    assert.is_true(ran)
  end)

  it("lists available commands", function()
    local dispatcher = Commands.new()
    dispatcher:register("A", { run = function() return { ok = true } end })
    dispatcher:register("B", { run = function() return { ok = true } end })
    local names = dispatcher:list()
    assert.are_equal(2, #names)
  end)
end)
