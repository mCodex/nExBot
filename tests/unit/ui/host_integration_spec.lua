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
  dofile("ui/components/components.lua")
  dofile("ui/modules/page.lua")
  dofile("ui/modules/cockpit.lua")
  dofile("ui/core/module_registry.lua")
  dofile("ui/modules/workflows.lua")
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

    assert.is_truthy(styles:match("NexShellLayout < Panel.-anchors%.fill: parent"))
    assert.is_truthy(styles:match("NexContent < ScrollablePanel.-anchors%.top: header%.bottom.-anchors%.bottom: footer%.top"))
    assert.is_truthy(styles:match("vertical%-scrollbar: contentScroll"))
    local headerStyle = styles:match("NexShellHeader < Panel(.-)NexHeaderButton")
    assert.is_truthy(headerStyle:match("anchors%.top: parent%.top"), "anchor-layout header must own the top edge")
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

  it("destroys the replaced host surface", function()
    local cp = modules.game_bot.contentsPanel
    local legacy = g_ui.createWidget("BotPanel", cp.botPanel)
    legacy:setId("tabPanel")
    assert.are_equal(cp.botPanel, legacy:getParent())
    local shell = Shell.show()
    assert.is_nil(legacy:getParent(), "replaced UI must leave botPanel")
    assert.is_true(legacy:isDestroyed(), "replaced UI must not remain alive")
    assert.is_true(shell:getWindow():isVisible(), "shell layout must be visible")
    shell:destroy()
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

  it("hides the host profile toolbar without destroying its controls", function()
    local cp = modules.game_bot.contentsPanel
    local toolbar = g_ui.createWidget("Panel", nil)
    cp.config = g_ui.createWidget("ComboBox", toolbar)
    cp.edit = g_ui.createWidget("Button", toolbar)
    cp.enabled = g_ui.createWidget("Button", toolbar)

    local shell = Shell.show()

    assert.is_false(toolbar:isVisible())
    assert.is_false(toolbar:isEnabled())
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

  it("does not hide a shared ancestor containing the shell panel", function()
    local cp = modules.game_bot.contentsPanel
    local ancestor = g_ui.createWidget("Panel", nil)
    ancestor:addChild(cp.botPanel)
    cp.edit = g_ui.createWidget("Button", ancestor)

    local shell = Shell.show()

    assert.is_true(ancestor:isVisible())
    assert.is_false(cp.edit:isVisible())
    assert.is_true(shell:getWindow():isVisible())
    shell:destroy()
  end)

  it("removes alternate host tab navigation names", function()
    local cp = modules.game_bot.contentsPanel
    cp.tabBar = cp.botTabs
    cp.botTabs = nil

    local shell = Shell.show()

    assert.is_false(cp.tabBar:isEnabled())
    assert.is_false(cp.tabBar:isVisible())
    shell:destroy()
  end)

  it("renders narrow engine rails without duplicate Edit buttons or unsafe text", function()
    local shell = Shell.show()
    local content = shell:getContent()
    local editorActions = {
      cave = "open_cave_editor",
      target = "open_target_editor",
      heal = "open_heal_config",
      loot = "open_loot_config",
    }

    for _, id in ipairs({ "cave", "target", "heal", "loot" }) do
      local row = assert(content:recursiveGetChildById(id))
      assert.is_truthy(row:recursiveGetChildById(id .. "Info"))
      assert.is_nil(row:recursiveGetChildById(editorActions[id]))
    end

    local function assertAscii(widget)
      assert.is_nil(widget:getText():find("[^\1-\127]"), "unsafe text in " .. tostring(widget:getId()))
      for _, child in ipairs(widget:getChildren()) do assertAscii(child) end
    end
    assertAscii(content)
    shell:destroy()
  end)

  it("opens engine settings from the rail instead of a second button", function()
    local shell = Shell.show()
    local action
    nExBot.UI.Actions.run = function(id) action = id; return true end

    shell:getContent():recursiveGetChildById("caveInfo"):click()

    assert.are_equal("open_cavebot", action)
    shell:destroy()
  end)

  it("host cleanup stays idempotent and does not re-add removed children", function()
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
    assert.are_equal(1, #modules.game_bot.contentsPanel.botPanel:getChildren())
    s2:destroy()
  end)

  it("More opens advanced modules and returns through header history", function()
    local shell = Shell.show()
    shell:select("more")
    assert.are_equal("more", shell:selected())
    assert.are_equal("More", shell:getWindow():recursiveGetChildById("shellTitle"):getText())
    assert.is_nil(shell:getContent():recursiveGetChildById("moreTitle"))
    assert.is_truthy(shell:getContent():recursiveGetChildById("more_analytics"))
    shell:getWindow():recursiveGetChildById("shellBack"):click()
    assert.are_equal("cockpit", shell:selected())
    shell:destroy()
  end)

  it("groups auxiliary controls into compact workflow pages", function()
    local shell = Shell.show()
    shell:select("more")
    shell:getContent():recursiveGetChildById("more_tools"):click()

    assert.are_equal("tools", shell:selected())
    assert.is_truthy(shell:getContent():recursiveGetChildById("tools_looting"))
    assert.is_truthy(shell:getContent():recursiveGetChildById("tools_toggle_dropper"))
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
