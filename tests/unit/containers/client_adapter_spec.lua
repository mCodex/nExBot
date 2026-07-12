local ClientAdapter = dofile("core/containers/client_adapter.lua")

describe("ClientAdapter", function()
  before_each(function()
    _G.g_game = nil
    _G.Client = nil
  end)

  it("wraps g_game.open", function()
    local called = false
    _G.g_game = { open = function(item) called = item end }
    ClientAdapter.open("testItem")
    assert.equals("testItem", called)
  end)

  it("wraps g_game.close", function()
    local called = false
    _G.g_game = { close = function(container) called = container end }
    ClientAdapter.close("testContainer")
    assert.equals("testContainer", called)
  end)

  it("wraps g_game.getContainers", function()
    _G.g_game = { getContainers = function() return {1, 2, 3} end }
    local result = ClientAdapter.getContainers()
    assert.equals(3, #result)
  end)

  it("returns empty table when no client available", function()
    local result = ClientAdapter.getContainers()
    assert.equals(0, #result)
  end)

  it("prefers Client over g_game", function()
    local called = nil
    _G.Client = { open = function(item) called = "Client" end }
    _G.g_game = { open = function(item) called = "g_game" end }
    ClientAdapter.open("test")
    assert.equals("Client", called)
  end)
end)
