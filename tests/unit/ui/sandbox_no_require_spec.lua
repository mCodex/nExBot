-- Verify UI modules load in the real OTClient sandbox: no require, no
-- loadfile, no package -- only dofile, and dofile discards return values
-- (modules must self-register into nExBot.UI as a side effect of running).
describe("UI modules load without require", function()
  local Harness = require("tests.helpers.widget_harness")

  local function sandboxLoad()
    Harness.reset()
    Harness.install()
    Harness.installHostPanel()
    _G.nExBot = { paths = { config = "nExBot" }, UI = {}, loadErrors = {}, Nav = {} }
    local origRequire = _G.require
    local origLoadfile = _G.loadfile
    local origDofile = _G.dofile
    _G.require = nil  -- require does not exist in the OTClient sandbox
    _G.loadfile = nil  -- loadfile does not exist in the OTClient sandbox
    _G.dofile = function(path, ...)
      if type(path) == "string" and path:sub(1, 1) == "/" then path = "." .. path end
      origDofile(path, ...)
      return nil  -- OTClient's dofile discards chunk return values
    end

    local ok, err = pcall(function()
      _G.dofile("/ui/init.lua")
    end)

    _G.require = origRequire
    _G.loadfile = origLoadfile
    _G.dofile = origDofile
    return ok, err
  end

  it("bootstrap completes even when require is nil", function()
    local ok, err = sandboxLoad()
    assert.is_true(ok, "bootstrap should not error: " .. tostring(err))
  end)

  it("registers all modules via self-registration", function()
    sandboxLoad()
    assert.is_truthy(nExBot.UI.ModuleRegistry, "ModuleRegistry must be registered")
    assert.is_truthy(nExBot.UI.Shell, "Shell must be registered")
    assert.is_truthy(nExBot.UI.Tokens, "Tokens must be registered")
    assert.is_truthy(nExBot.UI.Status, "Status must be registered")
    assert.are_equal(9, nExBot.UI.ModuleRegistry.count())
  end)
end)
