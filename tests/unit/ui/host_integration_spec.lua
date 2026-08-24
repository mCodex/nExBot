local Harness = require("tests.helpers.widget_harness")

local function fresh()
  Harness.reset()
  Harness.install()
  Harness.installHostPanel()
  _G.nExBot = { UI = {} }
  dofile("ui/core/icon_registry.lua")
  dofile("ui/core/view_model.lua")
  dofile("ui/core/lifecycle.lua")
  dofile("ui/design_system/tokens.lua")
  dofile("ui/design_system/typography.lua")
  dofile("ui/design_system/density.lua")
  dofile("ui/design_system/status.lua")
  dofile("ui/core/perf.lua")
  dofile("ui/core/actions.lua")
  dofile("ui/components/components.lua")
  dofile("ui/modules/page.lua")
  dofile("ui/modules/cockpit.lua")
  dofile("ui/core/module_registry.lua")
  for _, n in ipairs({
    "dashboard", "cavebot", "targetbot", "healing", "looting", "supplies",
    "scripts", "intelligence", "profiles", "settings", "diagnostics",
  }) do
    dofile("ui/modules/" .. n .. ".lua")
  end
  _G.nExBot.UI.Shell = nil
  return dofile("ui/shell/shell.lua")
end

describe("BotShell host integration", function()
  local Shell

  before_each(function()
    Shell = fresh()
  end)

  it("attaches into the host left panel instead of a floating window", function()
    local shell = Shell.show()
    assert.is_true(shell:isPanelMode(), "shell should render into the host left bar")
    assert.is_false(shell:getWindow():getStyle() == "MainWindow", "must not create a floating window")
    local cp = modules.game_bot.contentsPanel
    assert.are_equal("botPanel", shell:getWindow():getParent():getId())
    assert.are_equal("cockpit", shell:selected())
    assert.is_truthy(shell:getContent():recursiveGetChildById("cave"))
    shell:destroy()
  end)

  it("detaches legacy tab UI but keeps it alive for module engines", function()
    local cp = modules.game_bot.contentsPanel
    local legacy = g_ui.createWidget("BotPanel", cp.botPanel)
    legacy:setId("tabPanel")
    assert.are_equal(cp.botPanel, legacy:getParent())
    local shell = Shell.show()
    -- the legacy panel is removed from the tree (not destroyed) so
    -- CaveBot/TargetBot engines keep their widget references valid, and so
    -- UITabBar:selectTab can never find it still parented and collide on a
    -- later addChild ("attempt to add a child again into a UIWidget")
    assert.is_nil(legacy:getParent(), "legacy tab UI must be detached from botPanel")
    assert.is_false(legacy:isDestroyed(), "legacy tab UI must stay alive")
    assert.is_true(shell:getWindow():isVisible(), "shell layout must be visible")
    shell:destroy()
    -- after destroy, the legacy panel is still alive
    assert.is_false(legacy:isDestroyed())
  end)

  it("botPanel has no leftover legacy children once the shell attaches", function()
    local cp = modules.game_bot.contentsPanel
    local legacyA = g_ui.createWidget("BotPanel", cp.botPanel)
    legacyA:setId("tabPanelA")
    local legacyB = g_ui.createWidget("BotPanel", cp.botPanel)
    legacyB:setId("tabPanelB")
    local shell = Shell.show()
    local children = cp.botPanel:getChildren()
    assert.are_equal(1, #children, "botPanel must contain only the shell layout")
    assert.are_equal("NexBotShell", children[1]:getId())
    shell:destroy()
  end)

  it("disables the legacy tab bar so a stray click can't reach it", function()
    local cp = modules.game_bot.contentsPanel
    assert.is_true(cp.botTabs:isEnabled())
    local shell = Shell.show()
    assert.is_false(cp.botTabs:isEnabled(), "legacy tab bar must be disabled once the shell owns the panel")
    assert.is_false(cp.botTabs:isVisible())
    shell:destroy()
  end)

  it("re-hiding on setupHostHooks stays idempotent and does not re-add removed children", function()
    local cp = modules.game_bot.contentsPanel
    local shell = Shell.show()
    shell:setupHostHooks()
    local children = cp.botPanel:getChildren()
    assert.are_equal(1, #children, "repeated hide passes must not duplicate or re-add anything")
    assert.are_equal("NexBotShell", children[1]:getId())
    shell:destroy()
  end)

  it("single instance is shared between opens", function()
    local s1 = Shell.show()
    local s2 = Shell.show()
    assert.are_equal(1, Shell.count())
    assert.are_equal(s1, s2)
    s2:destroy()
  end)

  it("More opens advanced modules and returns to the cockpit", function()
    local shell = Shell.show()
    shell:select("more")
    assert.are_equal("more", shell:selected())
    assert.is_truthy(shell:getContent():recursiveGetChildById("more_diagnostics"))
    shell:getContent():recursiveGetChildById("backToCockpit"):click()
    assert.are_equal("cockpit", shell:selected())
    shell:destroy()
  end)

  it("setupHostHooks re-attaches when the host rebuilds the panel", function()
    local shell = Shell.show()
    local oldRoot = shell:getWindow()
    -- simulate the framework re-running refresh(): it destroys the panel and
    -- rebuilds a fresh botPanel + legacy content
    local cp = modules.game_bot.contentsPanel
    cp.botPanel:destroy()
    cp.botPanel = g_ui.createWidget("Panel", nil)
    cp.botPanel:setId("botPanel")
    g_ui.createWidget("BotPanel", cp.botPanel)
    shell:setupHostHooks()
    assert.is_true(shell:isPanelMode())
    assert.is_false(oldRoot == shell:getWindow(), "shell must rebuild into the fresh panel")
    assert.is_true(shell:getWindow():isVisible())
    shell:destroy()
  end)

  it("setupHostHooks is a no-op when already attached", function()
    local shell = Shell.show()
    local oldRoot = shell:getWindow()
    shell:setupHostHooks()
    assert.are_equal(oldRoot, shell:getWindow(), "no rebuild when still attached")
    shell:destroy()
  end)
end)
