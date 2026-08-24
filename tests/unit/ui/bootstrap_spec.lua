local Harness = require("tests.helpers.widget_harness")

describe("ui bootstrap", function()
  it("registers 11 modules and attaches the shell to the host left bar", function()
    Harness.reset()
    Harness.install()
    Harness.installHostPanel()
    _G.nExBot = { paths = { config = "nExBot" }, UI = {}, loadErrors = {}, Nav = {} }

    -- emulate OTClient virtual-FS loadfile + require shim
    local origLoadfile = loadfile
    local origRequire = _G.require
    _G.loadfile = function(path, ...)
      if type(path) == "string" and path:sub(1, 1) == "/" then path = "." .. path end
      return origLoadfile(path, ...)
    end
    local function navLoad(path)
      if path:sub(1, 1) == "/" then path = "." .. path end
      local chunk, err = loadfile(path)
      if not chunk then error(tostring(err), 2) end
      return chunk()
    end
    _G.require = function(name)
      if _G.nExBot.Nav[name] then return _G.nExBot.Nav[name] end
      local ns = _G.nExBot.UI
      if ns then
        local c = ns[name]
        if c ~= nil then _G.nExBot.Nav[name] = c; return c end
      end
      local sub = name:gsub("%.", "/")
      for _, p in ipairs({ "/", "" }) do
        local ok, mod = pcall(navLoad, p .. sub .. ".lua")
        if ok and mod then _G.nExBot.Nav[name] = mod; return mod end
      end
      error("module '" .. name .. "' not found", 2)
    end
    _G.warn = function() end
    _G.info = function() end
    _G.schedule = function(_, fn) fn() end

    local ok, err = pcall(function()
      local chunk = assert(loadfile("ui/init.lua"))
      chunk()
    end)
    _G.require = origRequire
    assert.is_true(ok, tostring(err))

    local R = _G.nExBot.UI.ModuleRegistry
    assert.are_equal(11, R.count())
    assert.are_equal(0, #R.validate())

    -- Auto-open: the shell is attached to the host left bar after bootstrap.
    local Shell = _G.nExBot.UI.Shell
    assert.are_equal(1, Shell.count(), "shell should auto-open after bootstrap")
    assert.is_true(Shell.instance():isPanelMode(), "shell must attach to the host left bar")
    assert.are_equal("botPanel", Shell.instance():getWindow():getParent():getId())
    assert.are_equal(11, Shell.instance():getSidebar():getChildCount())

    -- Re-opening does not duplicate the shell.
    Shell.show()
    assert.are_equal(1, Shell.count(), "re-open must not duplicate the shell")
    Shell.instance():destroy()
  end)
end)
