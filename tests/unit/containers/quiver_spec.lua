local Quiver = dofile("core/containers/quiver.lua")

describe("Quiver", function()
  before_each(function()
    _G.player = nil
    _G.g_game = nil
  end)

  it("detects paladin vocation", function()
    _G.player = { getVocation = function() return 2 end }
    assert.is_true(Quiver.isPaladin())
  end)

  it("detects royal paladin vocation", function()
    _G.player = { getVocation = function() return 12 end }
    assert.is_true(Quiver.isPaladin())
  end)

  it("rejects non-paladin", function()
    _G.player = { getVocation = function() return 1 end }
    assert.is_false(Quiver.isPaladin())
  end)

  it("rejects knight", function()
    _G.player = { getVocation = function() return 3 end }
    assert.is_false(Quiver.isPaladin())
  end)

  it("returns nil for non-paladin quiver discovery", function()
    _G.player = { getVocation = function() return 1 end }
    assert.is_nil(Quiver.discoverRoot())
  end)

  it("returns nil when no player", function()
    assert.is_false(Quiver.isPaladin())
    assert.is_nil(Quiver.discoverRoot())
  end)
end)
