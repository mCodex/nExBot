_G.nExBot = { UI = {} }
local Lifecycle = dofile("ui/core/lifecycle.lua")

local function reset()
  nExBot.UI.Lifecycle = nil
  Lifecycle = dofile("ui/core/lifecycle.lua")
end

describe("UiLifecycle", function()
  before_each(reset)

  it("creates a session with a generation counter", function()
    local session = Lifecycle.new("shell")
    assert.are_equal(1, session.generation)
    assert.are_equal("shell", session.id)
  end)

  it("advance bumps the generation", function()
    local session = Lifecycle.new("shell")
    session:advance()
    session:advance()
    assert.are_equal(3, session.generation)
  end)

  it("guard produces a callback that no-ops when stale", function()
    local session = Lifecycle.new("shell")
    local ran = 0
    local cb = session:guard(function() ran = ran + 1 end)
    cb()
    assert.are_equal(1, ran)
    session:advance()
    cb()
    assert.are_equal(1, ran, "stale callback must be rejected")
  end)

  it("guard captures the generation at creation time", function()
    local session = Lifecycle.new("shell")
    local cb = session:guard(function() return "ok" end)
    assert.are_equal("ok", cb())
    session:advance()
    -- the previously captured callback is now stale and returns nil
    assert.is_nil(cb())
  end)

  it("guard with a generation argument checks against that generation", function()
    local session = Lifecycle.new("shell")
    local gen = session.generation
    local cb = session:guard(function() return "ok" end, gen)
    assert.are_equal("ok", cb())
    session:advance()
    assert.is_nil(cb())
  end)

  it("stale() reports whether a captured generation is current", function()
    local session = Lifecycle.new("shell")
    local gen = session.generation
    assert.is_false(session:stale(gen))
    session:advance()
    assert.is_true(session:stale(gen))
  end)

  it("isCurrent() reflects whether a generation matches", function()
    local session = Lifecycle.new("shell")
    local gen = session.generation
    assert.is_true(session:isCurrent(gen))
    assert.is_false(session:isCurrent(gen + 1))
  end)
end)
