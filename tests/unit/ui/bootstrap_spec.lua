local Harness = require("tests.helpers.widget_harness")

describe("ui bootstrap", function()
  it("registers secondary modules and attaches the cockpit to the host left bar", function()
    Harness.reset()
    Harness.install()
    Harness.installHostPanel()
    _G.nExBot = { paths = { config = "nExBot" }, UI = {}, loadErrors = {}, Nav = {} }

    -- emulate the real OTClient sandbox: no require, no loadfile, no
    -- package -- only dofile, which discards chunk return values (modules
    -- self-register into nExBot.UI as a side effect of running).
    local origRequire = _G.require
    local origLoadfile = _G.loadfile
    local origDofile = _G.dofile
    _G.require = nil
    _G.loadfile = nil
    _G.dofile = function(path, ...)
      if type(path) == "string" and path:sub(1, 1) == "/" then path = "." .. path end
      origDofile(path, ...)
      return nil
    end
    _G.warn = function() end
    _G.info = function() end
    _G.schedule = function(_, fn) fn() end

    local ok, err = pcall(function()
      _G.dofile("/ui/init.lua")
    end)
    _G.require = origRequire
    _G.loadfile = origLoadfile
    _G.dofile = origDofile
    assert.is_true(ok, tostring(err))

    local R = _G.nExBot.UI.ModuleRegistry
    assert.are_equal(14, R.count())
    assert.are_equal(0, #R.validate())

    -- Auto-open: the shell is attached to the host left bar after bootstrap.
    local Shell = _G.nExBot.UI.Shell
    assert.are_equal(1, Shell.count(), "shell should auto-open after bootstrap")
    assert.is_true(Shell.instance():isPanelMode(), "shell must attach to the host left bar")
    assert.are_equal("botPanel", Shell.instance():getWindow():getParent():getId())
    assert.is_nil(Shell.instance():getWindow():recursiveGetChildById("sidebar"))
    assert.are_equal("cockpit", Shell.instance():selected())
    assert.is_truthy(Shell.instance():getContent():recursiveGetChildById("cave"))

    -- Re-opening does not duplicate the shell.
    Shell.show()
    assert.are_equal(1, Shell.count(), "re-open must not duplicate the shell")
    Shell.instance():destroy()
  end)
end)
