local Harness = require("tests.helpers.widget_harness")

local function freshEnv()
  Harness.reset()
  Harness.install()
  _G.nExBot = { UI = {} }
  dofile("ui/core/icon_registry.lua")
  dofile("ui/core/lifecycle.lua")
  dofile("ui/design_system/tokens.lua")
  dofile("ui/design_system/typography.lua")
  dofile("ui/design_system/density.lua")
  dofile("ui/design_system/status.lua")
  dofile("ui/components/components.lua")
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

  it("builds sidebar items from the module registry", function()
    local Registry = nExBot.UI.ModuleRegistry
    Registry.register({ id = "dashboard", label = "Dashboard", icon = "dashboard", order = 10 })
    Registry.register({ id = "cavebot", label = "CaveBot", icon = "cavebot", order = 20 })
    local root = _G.g_ui.createWidget("Root", nil)
    local shell = Shell.new({ root = root })
    shell:open()
    local sidebar = shell:getSidebar()
    assert.is_truthy(sidebar:recursiveGetChildById("dashboard"))
    assert.is_truthy(sidebar:recursiveGetChildById("cavebot"))
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
    local header = shell:getHeader()
    assert.is_truthy(header)
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
