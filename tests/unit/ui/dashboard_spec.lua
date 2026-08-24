_G.nExBot = { UI = {} }

local function freshEnv()
  _G.g_ui = _G.g_ui or require("tests.helpers.widget_harness").g_ui
  dofile("ui/core/icon_registry.lua")
  dofile("ui/core/view_model.lua")
  dofile("ui/design_system/tokens.lua")
  dofile("ui/design_system/typography.lua")
  dofile("ui/design_system/density.lua")
  dofile("ui/design_system/status.lua")
  dofile("ui/components/components.lua")
  _G.nExBot.UI.Dashboard = nil
  return dofile("ui/modules/dashboard.lua")
end

describe("Dashboard module", function()
  local Dashboard

  before_each(function()
    Dashboard = freshEnv()
  end)

  it("builds a bounded READY view model from empty domain state", function()
    local vm = Dashboard.viewModel({})
    local snap = vm.snapshot
    assert.are_equal("dashboard", snap.moduleId)
    assert.are_equal(1, snap.schemaVersion)
    assert.are_equal("READY", snap.state)
    assert.are_equal("dashboard", snap.header.module)
    assert.is_table(snap.sections)
    assert.are_equal(0, #snap.errors)
  end)

  it("reports active modules from the domain flags", function()
    local vm = Dashboard.viewModel({ cavebotOn = true, targetbotOn = false, healbotOn = true })
    local snap = vm.snapshot
    local active = snap.header.activeModules
    assert.is_table(active)
    assert.is_true(active.cavebot)
    assert.is_false(active.targetbot)
    assert.is_true(active.healbot)
  end)

  it("shows character and profile from session state", function()
    local vm = Dashboard.viewModel({ character = "Rookgaard", profile = "Main" })
    assert.are_equal("Rookgaard", vm.snapshot.header.character)
    assert.are_equal("Main", vm.snapshot.header.profile)
  end)

  it("exposes quick actions as typed commands", function()
    local vm = Dashboard.viewModel({})
    assert.is_table(vm.snapshot.actions)
    local names = {}
    for _, a in ipairs(vm.snapshot.actions) do
      names[#names + 1] = a.id
    end
    assert.is_true(#names >= 5)
  end)

  it("degraded state when diagnostics are present", function()
    local vm = Dashboard.viewModel({ issues = { { code = "X" } } })
    assert.are_equal("DEGRADED", vm.snapshot.state)
  end)

  it("render is a function", function()
    assert.is_function(Dashboard.render)
  end)
end)
