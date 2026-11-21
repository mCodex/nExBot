local Harness = require("tests.helpers.widget_harness")

describe("ui bootstrap", function()
  it("retries host attachment until the host panel becomes available", function()
    Harness.reset()
    Harness.install()
    _G.nExBot = { paths = { config = "nExBot" }, UI = {}, loadErrors = {}, Nav = {} }

    local pending = {}
    local origSchedule = _G.schedule
    _G.schedule = function(delay, callback)
      pending[#pending + 1] = { delay = delay, callback = callback }
    end
    local origDofile = _G.dofile
    _G.dofile = function(path, ...)
      if type(path) == "string" and path:sub(1, 1) == "/" then path = "." .. path end
      origDofile(path, ...)
    end

    local ok, err = pcall(function() _G.dofile("/ui/init.lua") end)
    _G.dofile = origDofile
    assert.is_true(ok, tostring(err))
    assert.is_true(#pending > 0)

    pending[1].callback()
    assert.is_nil(_G.nExBot.UI.Shell.instance())

    Harness.installHostPanel()
    for i = 2, #pending do pending[i].callback() end
    _G.schedule = origSchedule

    local shell = _G.nExBot.UI.Shell.instance()
    assert.is_true(shell:isPanelMode())
    assert.are_equal("botPanel", shell:getWindow():getParent():getId())
    shell:destroy()
  end)

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
    local sandboxDofile = function(path, ...)
      if type(path) == "string" and path:sub(1, 1) == "/" then path = "." .. path end
      origDofile(path, ...)
      return nil
    end
    _G.dofile = sandboxDofile
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
    assert.are_equal(25, R.count())
    assert.are_equal(0, #R.validate())

    for _, id in ipairs({ "cavebot", "targetbot", "attack", "looting", "dropper", "supplies", "containers",
      "healing", "friend_healer", "conditions", "equipment_rules", "extras", "combo", "alarms", "pushmax",
      "depositer", "profiles", "settings", "diagnostics", "intelligence", "analytics" }) do
      assert.is_truthy(R.get(id), "missing registered shortcut: " .. id)
    end

    -- Auto-open: the shell is attached to the host left bar after bootstrap.
    local Shell = _G.nExBot.UI.Shell
    assert.are_equal(1, Shell.count(), "shell should auto-open after bootstrap")
    assert.is_true(Shell.instance():isPanelMode(), "shell must attach to the host left bar")
    assert.are_equal("botPanel", Shell.instance():getWindow():getParent():getId())
    assert.is_nil(Shell.instance():getWorkspace(), "configuration stays lazy at startup")
    assert.are_equal("cockpit", Shell.instance():selected())
    assert.is_truthy(Shell.instance():getWindow():recursiveGetChildById("cave"))

    -- A full bot off/on reload replaces the old shell instead of appending it.
    local oldWindow = Shell.instance():getWindow()
    _G.require, _G.loadfile, _G.dofile = nil, nil, sandboxDofile
    local reloadOk, reloadErr = pcall(function() _G.dofile("/ui/init.lua") end)
    _G.require, _G.loadfile, _G.dofile = origRequire, origLoadfile, origDofile
    assert.is_true(reloadOk, tostring(reloadErr))
    local reloadedShell = _G.nExBot.UI.Shell
    assert.is_true(oldWindow:isDestroyed(), "reload must destroy the previous controller")
    assert.are_equal(1, reloadedShell.count(), "reload must keep one shell")
    assert.are_equal(1, #modules.game_bot.contentsPanel.botPanel:getChildren(), "reload must keep one controller")
    reloadedShell.instance():destroy()
  end)
end)
