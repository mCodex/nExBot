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
  dofile("ui/core/actions.lua")
  dofile("ui/components/components.lua")
  dofile("ui/modules/page.lua")
  dofile("ui/modules/cockpit.lua")
  local Registry = dofile("ui/core/module_registry.lua")
  dofile("ui/modules/workflows.lua")
  for _, n in ipairs({ "profiles", "settings", "diagnostics" }) do
    dofile("ui/modules/" .. n .. ".lua")
  end
  return Registry
end

describe("shell as primary surface", function()
  local Registry

  before_each(function()
    Registry = fresh()
  end)

  it("Shell.show opens exactly one shell and raises it", function()
    local Shell = dofile("ui/shell/shell.lua")
    local s1 = Shell.show()
    assert.are_equal(1, Shell.count())
    local s2 = Shell.show()
    assert.are_equal(1, Shell.count(), "second show must not duplicate")
    assert.are_equal(s1, s2)
    s2:destroy()
  end)

  it("Shell.show selects the cockpit by default and advanced modules on request", function()
    local Shell = dofile("ui/shell/shell.lua")
    local shell = Shell.show()
    assert.are_equal("cockpit", shell:selected())
    Shell.select("diagnostics")
    assert.are_equal("diagnostics", shell:selected())
    shell:destroy()
  end)

  it("uses explicit buttons to navigate without a permanent sidebar", function()
    local Shell = dofile("ui/shell/shell.lua")
    local shell = Shell.show()
    assert.is_nil(shell:getWindow():recursiveGetChildById("sidebar"))
    shell:getFooter():recursiveGetChildById("footerMore"):click()
    assert.are_equal("more", shell:selected())
    shell:destroy()
  end)

  it("opens embedded workflows from the hunt rail and returns with Back", function()
    local Shell = dofile("ui/shell/shell.lua")
    local shell = Shell.show()

    shell:getContent():recursiveGetChildById("caveInfo"):click()
    assert.are_equal("cavebot", shell:current())
    assert.is_truthy(shell:getContent():recursiveGetChildById("pageTitle"))

    shell:getWindow():recursiveGetChildById("shellBack"):click()
    assert.are_equal("cockpit", shell:current())
    shell:destroy()
  end)

  it("Shell.select routes to an existing instance or opens a new one", function()
    local Shell = dofile("ui/shell/shell.lua")
    local shell = Shell.select("diagnostics")
    assert.are_equal(1, Shell.count())
    assert.are_equal("diagnostics", shell:selected())
    Shell.select("settings")
    assert.are_equal(1, Shell.count(), "select on existing shell reuses it")
    shell:destroy()
  end)

  it("page renderer wires actions to the Actions dispatcher", function()
    local shell = dofile("ui/shell/shell.lua").show()
    local ran = false
    local handler = _G.nExBot.UI.Actions.handlers.toggle_cavebot
    _G.nExBot.UI.Actions.handlers.toggle_cavebot = function() ran = true end
    local root = _G.g_ui.createWidget("Root", nil)
    local content = _G.g_ui.createWidget("NexContent", root)
    local Page = dofile("ui/modules/page.lua")
    Page.render(shell, content, dofile("ui/core/lifecycle.lua").new("t"), {
      state = "READY",
      header = { title = "X", status = "INFO" },
      sections = {},
      actions = { { id = "toggle_cavebot", label = "Toggle" } },
      errors = {},
    })
    local btn = content:recursiveGetChildById("toggle_cavebot")
    assert.is_truthy(btn)
    btn:click()
    assert.is_true(ran)
    _G.nExBot.UI.Actions.handlers.toggle_cavebot = handler
    shell:destroy()
  end)

  it("every module action id resolves to a handler", function()
    for _, id in ipairs(Registry.ids()) do
      local provider = Registry.get(id).viewModelProvider
      if provider then
        local vm = provider({ enabled = true })
        for _, action in ipairs(vm.snapshot.actions or {}) do
          local handler = _G.nExBot.UI.Actions.handlers[action.id]
          assert.is_truthy(handler, id .. " action " .. action.id .. " has no handler")
        end
      end
    end
  end)
end)
