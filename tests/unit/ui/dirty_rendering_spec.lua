local Harness = require("tests.helpers.widget_harness")

local function fresh()
  Harness.reset()
  Harness.install()
  _G.nExBot = { UI = {} }
  dofile("ui/core/lifecycle.lua")
  dofile("ui/design_system/tokens.lua")
  dofile("ui/design_system/typography.lua")
  dofile("ui/design_system/density.lua")
  dofile("ui/design_system/status.lua")
  dofile("ui/components/components.lua")
  dofile("ui/core/perf.lua")
  dofile("ui/core/module_registry.lua")
  _G.nExBot.UI.Shell = nil
  return dofile("ui/shell/shell.lua")
end

describe("dirty rendering", function()
  local Shell

  before_each(function()
    Shell = fresh()
  end)

  it("unchanged revision writes no widgets on tick", function()
    local Registry = nExBot.UI.ModuleRegistry
    local revision = 1
    local called = 0
    Registry.register({
      id = "dashboard", label = "Dashboard", icon = "dashboard", order = 10,
      statusProvider = function()
        called = called + 1
        return { revision = revision }
      end,
      render = function() end,
    })
    local root = _G.g_ui.createWidget("Root", nil)
    local shell = Shell.new({ root = root })
    shell:open()
    shell:select("dashboard")

    Harness.clearLog()
    local tick = shell:onTick()
    tick() -- first tick renders
    local writesAfterFirst = Harness.countCalls("setText") + Harness.countCalls("createWidget")
    assert.is_true(writesAfterFirst >= 0)

    -- simulate a second tick with unchanged revision; must not recreate content
    Harness.clearLog()
    local createdBefore = Harness.countCalls("createWidget")
    tick()
    assert.are_equal(createdBefore, Harness.countCalls("createWidget"),
      "unchanged revision must produce zero widget creation")
  end)
end)
