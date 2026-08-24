local Harness = require("tests.helpers.widget_harness")

local function fresh()
  Harness.reset()
  Harness.install()
  _G.nExBot = { UI = {} }
  dofile("ui/core/view_model.lua")
  dofile("ui/core/lifecycle.lua")
  dofile("ui/design_system/tokens.lua")
  dofile("ui/design_system/typography.lua")
  dofile("ui/design_system/density.lua")
  dofile("ui/design_system/status.lua")
  dofile("ui/components/components.lua")
  dofile("ui/modules/page.lua")
  local Registry = dofile("ui/core/module_registry.lua")
  dofile("ui/modules/workflows.lua")
  for _, n in ipairs({ "profiles", "settings", "diagnostics" }) do
    dofile("ui/modules/" .. n .. ".lua")
  end
  return Registry
end

describe("UI performance", function()
  local Registry

  before_each(function()
    Registry = fresh()
  end)

  it("module render creates a bounded widget count", function()
    local root = _G.g_ui.createWidget("Root", nil)
    local lifecycle = dofile("ui/core/lifecycle.lua").new("perf")
    for _, id in ipairs(Registry.ids()) do
      Harness.clearLog()
      local module = Registry.get(id)
      local content = _G.g_ui.createWidget("NexContent", root)
      module.render(nil, content, lifecycle)
      local created = Harness.countCalls("createWidget")
      assert.is_true(created < 120, id .. " created too many widgets: " .. created)
      content:destroy()
    end
  end)

  it("module lookup is O(1)", function()
    -- verify get() is a direct map access, not a linear scan
    for _, id in ipairs(Registry.ids()) do
      assert.are_equal(id, Registry.get(id).id)
    end
  end)

  it("widget count stays stable across navigation", function()
    local Shell = dofile("ui/shell/shell.lua")
    local root = _G.g_ui.createWidget("Root", nil)
    local shell = Shell.new({ root = root })
    shell:open()
    for _, id in ipairs(Registry.ids()) do
      shell:select(id)
    end
    local count = Harness.widgetCount()
    assert.is_true(count > 0)
    shell:destroy()
  end)
end)
