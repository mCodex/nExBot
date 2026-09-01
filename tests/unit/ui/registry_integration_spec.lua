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
  dofile("ui/modules/workflows/shared.lua")
  dofile("ui/modules/workflows/cave.lua")
  dofile("ui/modules/workflows/target.lua")
  dofile("ui/modules/workflows/healing.lua")
  dofile("ui/modules/workflows/looting.lua")
  dofile("ui/modules/workflows/supplies.lua")
  dofile("ui/modules/workflows.lua")
  local names = { "profiles", "settings", "diagnostics" }
  for _, n in ipairs(names) do
    dofile("ui/modules/" .. n .. ".lua")
  end
  return Registry
end

describe("module registry integration", function()
  local Registry

  before_each(function()
    Registry = fresh()
  end)

  it("registers all modules exactly once", function()
    assert.are_equal(9, Registry.count())
    local errors = Registry.validate()
    assert.are_equal(0, #errors)
  end)

  it("every module id is unique", function()
    local ids = Registry.ids()
    local seen = {}
    for _, id in ipairs(ids) do
      assert.is_nil(seen[id], "duplicate id " .. id)
      seen[id] = true
    end
    assert.are_equal(9, #ids)
  end)

  it("module order is deterministic", function()
    local ids = Registry.ids()
    assert.same({
      "cavebot", "targetbot", "healing", "looting", "supplies",
      "intelligence", "profiles", "settings", "diagnostics",
    }, ids)
  end)

  it("duplicate navigation declarations are rejected", function()
    local before = Registry.count()
    local ok = Registry.register({ id = "profiles", label = "Profiles dup", order = 99 })
    assert.is_false(ok)
    assert.are_equal(before, Registry.count())
  end)

  it("each module exposes required navigation fields", function()
    for _, m in ipairs(Registry.list()) do
      assert.is_string(m.id)
      assert.is_string(m.label)
      assert.is_number(m.order)
      assert.is_table(m.sections)
      assert.is_function(m.render)
      assert.is_function(m.statusProvider)
    end
  end)

  it("shell can select every registered module", function()
    local Shell = dofile("ui/shell/shell.lua")
    local root = _G.g_ui.createWidget("Root", nil)
    local shell = Shell.new({ root = root })
    shell:open()
    for _, id in ipairs(Registry.ids()) do
      assert.is_true(shell:select(id), "cannot select " .. id)
    end
    shell:destroy()
  end)
end)
