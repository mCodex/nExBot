-- Verify UI modules load when require is NOT a function.
-- This simulates the OTClient sandbox where require doesn't exist.
describe("UI modules load without require", function()
  local Harness = require("tests.helpers.widget_harness")

  local function sandboxLoad()
    Harness.reset()
    Harness.install()
    Harness.installHostPanel()
    _G.nExBot = { paths = { config = "nExBot" }, UI = {}, loadErrors = {}, Nav = {} }
    -- Override require to simulate "not a function"
    local origRequire = _G.require
    _G.require = nil  -- require is not a function in OTClient sandbox
    -- Override loadfile to resolve virtual paths
    local origLoadfile = loadfile
    _G.loadfile = function(path, ...)
      if type(path) == "string" and path:sub(1, 1) == "/" then path = "." .. path end
      return origLoadfile(path, ...)
    end

    local ok, err = pcall(function()
      local chunk = assert(loadfile("ui/init.lua"))
      chunk()
    end)

    _G.require = origRequire
    _G.loadfile = origLoadfile
    return ok, err
  end

  it("bootstrap completes even when require is nil", function()
    local ok, err = sandboxLoad()
    assert.is_true(ok, "bootstrap should not error: " .. tostring(err))
  end)

  it("registers all modules via self-registration", function()
    sandboxLoad()
    assert.is_truthy(nExBot.UI.ModuleRegistry, "ModuleRegistry must be registered")
    assert.is_truthy(nExBot.UI.IconRegistry, "IconRegistry must be registered")
    assert.is_truthy(nExBot.UI.Shell, "Shell must be registered")
    assert.is_truthy(nExBot.UI.Tokens, "Tokens must be registered")
    assert.is_truthy(nExBot.UI.Status, "Status must be registered")
    assert.are_equal(11, nExBot.UI.ModuleRegistry.count())
  end)

  it("icon catalog is registered", function()
    sandboxLoad()
    assert.is_true(nExBot.UI.IconRegistry.count() > 0, "icons must be registered")
    assert.is_true(nExBot.UI.IconRegistry.has("dashboard"))
    assert.is_true(nExBot.UI.IconRegistry.has("cavebot"))
  end)
end)
