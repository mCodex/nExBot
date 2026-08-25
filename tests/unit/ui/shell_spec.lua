local Harness = require("tests.helpers.widget_harness")

local function freshEnv()
  Harness.reset()
  Harness.install()
  _G.nExBot = { UI = {} }
  dofile("ui/core/lifecycle.lua")
  dofile("ui/core/perf.lua")
  dofile("ui/core/actions.lua")
  dofile("ui/design_system/tokens.lua")
  dofile("ui/design_system/typography.lua")
  dofile("ui/design_system/density.lua")
  dofile("ui/design_system/status.lua")
  dofile("ui/components/components.lua")
  dofile("ui/modules/cockpit.lua")
  dofile("ui/core/module_registry.lua")
  _G.nExBot.UI.Shell = nil
  return dofile("ui/shell/shell.lua")
end

describe("BotShell", function()
  local Shell

  before_each(function()
    Shell = freshEnv()
  end)

  it("exposes a single-instance factory", function()
    assert.is_function(Shell.new)
    assert.is_function(Shell.instance)
  end)

  it("opening twice creates one shell", function()
    local s1 = Shell.new({ root = _G.g_ui.createWidget("Root", nil) })
    local s2 = Shell.new({ root = _G.g_ui.createWidget("Root", nil) })
    assert.is_true(s1 == s2 or s1.id ~= nil)
    assert.is_equal(s1, Shell.instance())
    assert.are_equal(1, Shell.count())
  end)

  it("builds the compact cockpit without a permanent sidebar", function()
    local root = _G.g_ui.createWidget("Root", nil)
    local shell = Shell.new({ root = root })
    shell:open()
    shell:select("cockpit")
    assert.is_nil(shell:getWindow():recursiveGetChildById("sidebar"))
    assert.is_truthy(shell:getContent():recursiveGetChildById("cave"))
  end)

  it("navigates with browser-style history and home", function()
    local Registry = nExBot.UI.ModuleRegistry
    Registry.register({ id = "profiles", label = "Profiles", order = 10, render = function() end })
    Registry.register({ id = "diagnostics", label = "Diagnostics", order = 20, render = function() end })
    local shell = Shell.new({ root = _G.g_ui.createWidget("Root", nil) })
    shell:open()

    shell:home()
    shell:push("profiles")
    shell:push("diagnostics")
    assert.are_equal("diagnostics", shell:current())
    assert.is_true(shell:canGoBack())

    assert.is_true(shell:back())
    assert.are_equal("profiles", shell:current())
    shell:home()
    assert.are_equal("cockpit", shell:current())
    assert.is_false(shell:canGoBack())
  end)

  it("renders native header controls and updates the page title", function()
    local Registry = nExBot.UI.ModuleRegistry
    Registry.register({ id = "profiles", label = "Profiles", order = 10, render = function() end })
    local shell = Shell.new({ root = _G.g_ui.createWidget("Root", nil) })
    shell:open()
    shell:home()
    shell:push("profiles")

    assert.are_equal("Profiles", shell:getWindow():recursiveGetChildById("shellTitle"):getText())
    assert.is_truthy(shell:getWindow():recursiveGetChildById("shellBack"))
    assert.is_truthy(shell:getWindow():recursiveGetChildById("shellHome"))
  end)

  it("selecting a module updates the selected state and calls its render", function()
    local Registry = nExBot.UI.ModuleRegistry
    local rendered = 0
    Registry.register({
      id = "cavebot", label = "CaveBot", icon = "cavebot", order = 10,
      render = function() rendered = rendered + 1 end,
    })
    local root = _G.g_ui.createWidget("Root", nil)
    local shell = Shell.new({ root = root })
    shell:open()
    assert.is_true(shell:select("cavebot"))
    assert.are_equal(1, rendered)
    assert.are_equal("cavebot", shell:selected())
  end)

  it("rerenders an active workflow only when its snapshot changes", function()
    local Registry = nExBot.UI.ModuleRegistry
    local status = "Unavailable"
    local rendered = 0
    Registry.register({
      id = "cavebot", label = "CaveBot", order = 10,
      statusProvider = function()
        return { snapshot = { header = { statusText = status }, sections = {}, actions = {}, errors = {} } }
      end,
      render = function() rendered = rendered + 1 end,
    })
    local shell = Shell.new({ root = _G.g_ui.createWidget("Root", nil) })
    shell:open()
    shell:select("cavebot")
    shell:tick()
    local stableCount = rendered

    shell:tick()
    assert.are_equal(stableCount, rendered)

    status = "On"
    shell:tick()
    assert.are_equal(stableCount + 1, rendered)
  end)

  it("builds floating fallback content inside a shell layout", function()
    local shell = Shell.new({ root = _G.g_ui.createWidget("Root", nil) })
    shell:open()

    local layout = shell:getWindow():recursiveGetChildById("NexBotShellLayout")
    assert.is_truthy(layout)
    assert.are_equal("NexShellLayout", layout:getStyle())
    assert.are_equal(layout, shell:getHeader():getParent())
  end)

  it("destroying the shell rejects later callbacks (generation guard)", function()
    local Registry = nExBot.UI.ModuleRegistry
    local ran = 0
    Registry.register({
      id = "dashboard", label = "Dashboard", icon = "dashboard", order = 10,
      render = function() ran = ran + 1 end,
    })
    local root = _G.g_ui.createWidget("Root", nil)
    local shell = Shell.new({ root = root })
    shell:open()
    local cb = shell:onTick()
    shell:destroy()
    cb()
    assert.are_equal(0, ran)
    -- stale select is rejected too
    assert.is_false(shell:select("dashboard"))
  end)

  it("performs zero widget writes when cockpit state is unchanged", function()
    local root = _G.g_ui.createWidget("Root", nil)
    local shell = Shell.new({ root = root })
    shell:open()
    shell:select("cockpit")
    shell:tick()
    Harness.clearLog()

    shell:tick()
    assert.are_equal(0, #Harness.log)
    shell:destroy()
  end)

  it("destroy removes the shell so a new one can be created", function()
    local root = _G.g_ui.createWidget("Root", nil)
    local shell = Shell.new({ root = root })
    shell:open()
    shell:destroy()
    assert.are_equal(0, Shell.count())
  end)

  it("module switching does not destroy shared shell state", function()
    local Registry = nExBot.UI.ModuleRegistry
    Registry.register({ id = "dashboard", label = "Dashboard", icon = "dashboard", order = 10, render = function() end })
    Registry.register({ id = "cavebot", label = "CaveBot", icon = "cavebot", order = 20, render = function() end })
    local root = _G.g_ui.createWidget("Root", nil)
    local shell = Shell.new({ root = root })
    shell:open()
    shell:select("dashboard")
    shell:select("cavebot")
    assert.is_truthy(shell:getContent())
    assert.are_equal("cavebot", shell:selected())
  end)

  it("repeated open/close does not leak widgets", function()
    local root = _G.g_ui.createWidget("Root", nil)
    local before = Harness.widgetCount()
    for i = 1, 3 do
      local shell = Shell.new({ root = root })
      shell:open()
      shell:destroy()
    end
    assert.are_equal(before, Harness.widgetCount())
  end)
end)
