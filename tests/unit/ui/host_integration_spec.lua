local Harness = require("tests.helpers.widget_harness")

local function fresh()
  Harness.reset()
  Harness.install()
  Harness.installHostPanel()
  _G.nExBot = { UI = {} }
  dofile("ui/core/view_model.lua")
  dofile("ui/core/lifecycle.lua")
  dofile("ui/design_system/tokens.lua")
  dofile("ui/design_system/typography.lua")
  dofile("ui/design_system/density.lua")
  dofile("ui/design_system/status.lua")
  dofile("ui/core/perf.lua")
  dofile("ui/core/actions.lua")
  dofile("ui/core/visual_asset_resolver.lua")
  dofile("ui/components/components.lua")
  dofile("ui/components/table_model.lua")
  dofile("ui/components/data_table.lua")
  dofile("ui/modules/page.lua")
  dofile("ui/modules/cockpit.lua")
  dofile("ui/core/module_registry.lua")
  dofile("ui/modules/workflows/shared.lua")
  dofile("ui/modules/workflows/cave.lua")
  dofile("ui/modules/workflows/target.lua")
  dofile("ui/modules/workflows/healing.lua")
  dofile("ui/modules/workflows/looting.lua")
  dofile("ui/modules/workflows/supplies.lua")
  dofile("ui/modules/workflows.lua")
  _G.nExBot.Dropper = {
    getProjection = function() return { revision = 0, enabled = false, lowCap = 150, rows = {} } end,
    setEnabled = function() end,
  }
  dofile("ui/modules/dropper.lua")
  dofile("ui/modules/auxiliary.lua")
  for _, n in ipairs({ "profiles", "settings", "diagnostics" }) do
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

  it("gives the attached shell and its content real layout geometry", function()
    local file = assert(io.open("ui/shell/styles.otui", "r"))
    local styles = file:read("*a")
    file:close()

    assert.is_truthy(styles:match("NexControllerLayout < Panel.-anchors%.fill: parent"))
    local controller = styles:match("NexControllerContent < Panel(.-)NexControllerEngine")
    assert.is_nil(controller:match("fit%-children"), "a fill-anchored controller must not size itself from its children")
    assert.is_truthy(styles:match("NexWorkspace < MainWindow.-size: 440 400"))
    local workspace = styles:match("NexWorkspaceContent < ScrollablePanel(.-)NexPageLandmark")
    assert.is_truthy(workspace:match("vertical%-scrollbar: workspaceScroll"))
    assert.is_nil(workspace:match("fit%-children"), "anchored workspace content must not size itself from its children")
    assert.is_truthy(styles:match("NexFooterButton < NexButton"))
    assert.is_truthy(styles:match("NexTableActionButton < NexButton"))
    assert.is_truthy(styles:match("NexTabButton < Button.-text%-auto%-resize: false"))
  end)

  it("attaches into the host left panel instead of a floating window", function()
    local shell = Shell.show()
    assert.is_true(shell:isPanelMode(), "shell should render into the host left bar")
    assert.is_false(shell:getWindow():getStyle() == "MainWindow", "must not create a floating window")
    local cp = modules.game_bot.contentsPanel
    assert.are_equal("botPanel", shell:getWindow():getParent():getId())
    assert.are_equal("cockpit", shell:selected())
    assert.is_truthy(shell:getWindow():recursiveGetChildById("cave"))
    shell:destroy()
  end)

  it("leaves other tabs' content in botPanel untouched", function()
    local cp = modules.game_bot.contentsPanel
    local legacy = g_ui.createWidget("BotPanel", cp.botPanel)
    legacy:setId("tabPanel")
    assert.are_equal(cp.botPanel, legacy:getParent())
    local shell = Shell.show()
    assert.are_equal(cp.botPanel, legacy:getParent(), "another tab's content must not be reparented")
    assert.is_false(legacy:isDestroyed(), "another tab's content must not be destroyed")
    assert.is_true(shell:getWindow():isVisible(), "shell layout must be visible")
    shell:destroy()
  end)

  it("mounts alongside pre-existing botPanel children instead of replacing them", function()
    local cp = modules.game_bot.contentsPanel
    local legacyA = g_ui.createWidget("BotPanel", cp.botPanel)
    legacyA:setId("tabPanelA")
    local legacyB = g_ui.createWidget("BotPanel", cp.botPanel)
    legacyB:setId("tabPanelB")
    local shell = Shell.show()
    local children = cp.botPanel:getChildren()
    assert.are_equal(3, #children, "shell must add its tab content, not clear the panel")
    assert.is_false(legacyA:isDestroyed())
    assert.is_false(legacyB:isDestroyed())
    shell:destroy()
  end)

  it("mounts via botTabs:addTab and leaves the native tab bar enabled", function()
    local cp = modules.game_bot.contentsPanel
    assert.is_true(cp.botTabs:isEnabled())
    assert.is_true(cp.botTabs:isVisible())
    local shell = Shell.show()
    assert.is_true(cp.botTabs:isEnabled(), "native tab bar must stay usable for other scripts/tabs")
    assert.is_true(cp.botTabs:isVisible())
    assert.are_equal(1, #cp.botTabs._tabs, "shell must register itself as exactly one native tab")
    assert.are_equal("nExBot", cp.botTabs._tabs[1].name)
    assert.are_equal(shell:getWindow(), cp.botTabs._tabs[1].content)
    shell:destroy()
  end)

  it("the framework's clearTabs() (fired on a config-combo switch) reclaims the shell's tab, and setupHostHooks remounts a fresh one", function()
    local cp = modules.game_bot.contentsPanel
    local shell = Shell.show()
    local oldWindow = shell:getWindow()

    -- Mirrors mehah/otclient's bot.lua clear(), called by refresh() every
    -- time the user picks a different entry in the config combo.
    cp.botTabs:clearTabs()
    assert.is_true(oldWindow:isDestroyed(), "the native framework must be able to reclaim the shell's tab")

    shell:setupHostHooks()
    assert.is_false(shell:getWindow():isDestroyed())
    assert.is_false(oldWindow == shell:getWindow(), "shell must remount into a fresh tab")
    assert.is_true(shell:getWindow():isVisible())
    shell:destroy()
  end)

  it("keeps the host profile selector visible and authoritative", function()
    local cp = modules.game_bot.contentsPanel
    local toolbar = g_ui.createWidget("Panel", nil)
    cp.config = g_ui.createWidget("ComboBox", toolbar)
    cp.edit = g_ui.createWidget("Button", toolbar)
    cp.enabled = g_ui.createWidget("Button", toolbar)

    local shell = Shell.show()

    assert.is_true(toolbar:isVisible())
    assert.is_true(toolbar:isEnabled())
    assert.is_false(cp.config:isDestroyed(), "storage still reads the profile control")
    shell:destroy()
  end)

  it("ignores host toolbar fields that are functions", function()
    local cp = modules.game_bot.contentsPanel
    cp.edit = function() end
    cp.enabled = function() return true end

    local shell = Shell.show()

    assert.is_true(shell:isPanelMode())
    assert.are_equal("cockpit", shell:selected())
    shell:destroy()
  end)

  it("does not modify a shared host ancestor", function()
    local cp = modules.game_bot.contentsPanel
    local ancestor = g_ui.createWidget("Panel", nil)
    ancestor:addChild(cp.botPanel)
    cp.edit = g_ui.createWidget("Button", ancestor)

    local shell = Shell.show()

    assert.is_true(ancestor:isVisible())
    assert.is_true(cp.edit:isVisible())
    assert.is_true(shell:getWindow():isVisible())
    shell:destroy()
  end)

  it("falls back to a floating window when the host has no botTabs", function()
    local cp = modules.game_bot.contentsPanel
    cp.botTabs = nil

    local shell = Shell.show()

    assert.is_false(shell:isPanelMode(), "without botTabs there is no native tab to mount into")
    assert.are_equal("MainWindow", shell:getWindow():getStyle())
    shell:destroy()
  end)

  it("renders narrow engine rails with exactly one Configure button per row and no unsafe text", function()
    local shell = Shell.show()
    local content = shell:getWindow():recursiveGetChildById("controller")

    for _, id in ipairs({ "cave", "target", "heal", "attack" }) do
      local row = assert(content:recursiveGetChildById(id))
      local configure = assert(row:recursiveGetChildById("configure_" .. id))
      assert.are_equal("", configure:getText())
      local tooltip = configure.getTooltip and configure:getTooltip()
      assert.is_true(tooltip ~= nil and #tooltip > 0)
    end

    local function assertAscii(widget)
      assert.is_nil(widget:getText():find("[^\1-\127]"), "unsafe text in " .. tostring(widget:getId()))
      for _, child in ipairs(widget:getChildren()) do assertAscii(child) end
    end
    assertAscii(content)
    shell:destroy()
  end)

  it("opens the single configuration workspace from the controller", function()
    local shell = Shell.show()
    shell:getWindow():recursiveGetChildById("openWorkspace"):click()
    assert.are_equal("cockpit", shell:selected())
    assert.is_truthy(shell:getWorkspace():recursiveGetChildById("nav_hunt"))
    shell:destroy()
  end)

  it("host cleanup stays idempotent and does not re-add removed children", function()
    local cp = modules.game_bot.contentsPanel
    local shell = Shell.show()
    shell:setupHostHooks()
    local children = cp.botPanel:getChildren()
    assert.are_equal(1, #children, "repeated hide passes must not duplicate or re-add anything")
    assert.are_equal("NexBotController", children[1]:getId())
    shell:destroy()
  end)

  it("single instance is shared between opens", function()
    local s1 = Shell.show()
    local s2 = Shell.show()
    assert.are_equal(1, Shell.count())
    assert.are_equal(s1, s2)
    assert.are_equal(1, #modules.game_bot.contentsPanel.botPanel:getChildren())
    s2:destroy()
  end)

  it("maps the removed More route to Overview", function()
    local shell = Shell.show()
    shell:select("more")
    assert.are_equal("cockpit", shell:selected())
    assert.is_truthy(shell:getWorkspace():recursiveGetChildById("tab_intelligence"))
    shell:destroy()
  end)

  it("routes Dropper to its dedicated workflow page", function()
    local shell = Shell.show()
    shell:select("dropper")

    assert.are_equal("dropper", shell:selected())
    assert.is_truthy(shell:getWorkspace():recursiveGetChildById("pageSelect"))
    assert.is_truthy(shell:getContent():recursiveGetChildById("dropperItems"))
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
