local Harness = require("tests.helpers.widget_harness")

describe("embedded workflow pages", function()
  before_each(function()
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
    dofile("ui/core/module_registry.lua")
    dofile("ui/modules/workflows.lua")
  end)

  it("registers every primary workflow as a shell page", function()
    assert.same({ "cavebot", "targetbot", "healing", "looting", "supplies", "intelligence" }, nExBot.UI.ModuleRegistry.ids())
  end)

  it("keeps detailed editing behind explicit modal actions", function()
    local cave = nExBot.UI.ModuleRegistry.get("cavebot").statusProvider().snapshot
    local target = nExBot.UI.ModuleRegistry.get("targetbot").statusProvider().snapshot

    assert.are_equal("open_cave_editor", cave.actions[2].id)
    assert.are_equal("open_target_editor", target.actions[2].id)
  end)

  it("leaves page titling to the shell header", function()
    local root = g_ui.createWidget("Root", nil)
    local content = g_ui.createWidget("NexContent", root)
    local lifecycle = nExBot.UI["ui.core.lifecycle"].new("workflow")

    nExBot.UI.ModuleRegistry.get("cavebot").render(nil, content, lifecycle)

    assert.is_nil(content:recursiveGetChildById("pageTitle"))
  end)
end)
