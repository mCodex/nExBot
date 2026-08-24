local Harness = require("tests.helpers.widget_harness")

local function loadModule(name)
  Harness.reset()
  Harness.install()
  _G.nExBot = { UI = {} }
  dofile("ui/core/icon_registry.lua")
  dofile("ui/core/view_model.lua")
  dofile("ui/core/lifecycle.lua")
  dofile("ui/design_system/tokens.lua")
  dofile("ui/design_system/typography.lua")
  dofile("ui/design_system/density.lua")
  dofile("ui/design_system/status.lua")
  dofile("ui/components/components.lua")
  dofile("ui/modules/page.lua")
  local Module = dofile("ui/modules/" .. name .. ".lua")
  return Module
end

describe("module view models", function()
  local cases = {
    cavebot = { id = "cavebot", icon = "cavebot", order = 20 },
    targetbot = { id = "targetbot", icon = "targetbot", order = 30 },
    healing = { id = "healing", icon = "healing", order = 40 },
    looting = { id = "looting", icon = "looting", order = 50 },
    supplies = { id = "supplies", icon = "supplies", order = 60 },
    scripts = { id = "scripts", icon = "scripts", order = 70 },
    intelligence = { id = "intelligence", icon = "intelligence", order = 80 },
    profiles = { id = "profiles", icon = "profiles", order = 90 },
    settings = { id = "settings", icon = "settings", order = 100 },
    diagnostics = { id = "diagnostics", icon = "diagnostics", order = 110 },
  }

  for name, meta in pairs(cases) do
    describe(name, function()
      local Module

      before_each(function()
        Module = loadModule(name)
      end)

      it("builds a versioned READY view model", function()
        local vm = Module.viewModel({})
        assert.are_equal(meta.id, vm.snapshot.moduleId)
        assert.are_equal(1, vm.snapshot.schemaVersion)
        assert.are_equal("READY", vm.snapshot.state)
        assert.is_table(vm.snapshot.sections)
        assert.is_table(vm.snapshot.actions)
      end)

      it("header carries module id and status", function()
        local vm = Module.viewModel({})
        assert.are_equal(meta.id, vm.snapshot.header.module)
        assert.is_string(vm.snapshot.header.status)
      end)

      it("reports enabled state via header status (stateful modules)", function()
        local stateful = { cavebot = true, targetbot = true, healing = true, looting = true }
        if not stateful[meta.id] then
          local vmAny = Module.viewModel({})
          assert.is_string(vmAny.snapshot.header.status)
          return
        end
        local vm = Module.viewModel({ enabled = true })
        assert.are_equal("ACTIVE", vm.snapshot.header.status)
      end)

      it("sections render through the shared page renderer", function()
        local root = _G.g_ui.createWidget("Root", nil)
        local vm = Module.viewModel({ enabled = true })
        local content = _G.g_ui.createWidget("NexContent", root)
        local lifecycle = dofile("ui/core/lifecycle.lua").new("test")
        local ok = pcall(function()
          Module.render(nil, content, lifecycle, vm.snapshot)
        end)
        assert.is_true(ok, "render must not throw")
        assert.is_true(content:getChildCount() >= 1)
      end)

      it("statusProvider exists and is nil-safe", function()
        assert.is_function(Module.statusProvider)
        local ok, result = pcall(Module.statusProvider)
        assert.is_true(ok, "statusProvider must not throw")
        assert.is_table(result)
      end)
    end)
  end
end)
