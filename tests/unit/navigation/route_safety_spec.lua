local D = require("navigation.domain")

describe("route safety", function()
  it("validates every returned direction before accepting a path", function()
    _G.Directions = D
    _G.PathUtils = {
      isTileWalkable = function() return true end,
      isFloorChangeTile = function() return false end,
    }
    _G.nExBot = { Shared = { getClient = function() return {} end } }
    _G.nExBot.ACL = {
      map = {
        findPath = function() return { D.DIR.EAST, 99 } end,
      },
    }
    package.loaded["utils.path_strategy"] = nil
    local strategy = require("utils.path_strategy")
    local path = strategy.findPath({ x = 10, y = 10, z = 7 }, { x = 12, y = 10, z = 7 }, {})
    assert.is_nil(path)
  end)

  it("rejects a native path that crosses a wall", function()
    _G.Directions = D
    _G.PathUtils = {
      isTileWalkable = function(pos) return pos.x ~= 11 end,
      isFloorChangeTile = function() return false end,
    }
    _G.nExBot = { Shared = { getClient = function() return {} end }, ACL = {
      map = { findPath = function() return { D.DIR.EAST, D.DIR.EAST } end },
    } }
    package.loaded["utils.path_strategy"] = nil
    local strategy = require("utils.path_strategy")
    local path = strategy.findPath({ x = 10, y = 10, z = 7 }, { x = 12, y = 10, z = 7 }, {})
    assert.is_nil(path)
  end)

  it("does not allow the cavebot field loop to bypass PathStrategy", function()
    local source = assert(io.open("cavebot/walking.lua", "r")):read("*a")
    assert.is_nil(source:find("walk%(d%)"))
    assert.is_nil(source:find("return tryKeyboardNudge"))
  end)

  it("passes OTBR autoWalk max steps and options separately", function()
    local calls = {}
    _G.g_game = {
      autoWalk = function(...) calls = { ... }; return true end,
    }
    _G.nExBot = nil
    _G.ACL_BaseAdapter = {}
    local adapter = dofile("core/acl/adapters/opentibiabr.lua")
    local destination = { x = 11, y = 10, z = 7 }
    local options = { precision = 1 }
    assert.is_true(adapter.game.autoWalk(destination, 12, options))
    assert.equals(destination, calls[1])
    assert.equals(12, calls[2])
    assert.equals(options, calls[3])
  end)
end)
