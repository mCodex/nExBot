local Harness = require("tests.helpers.widget_harness")

describe("embedded workflow pages", function()
  before_each(function()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {} }
    _G.CaveBot = {
      isOn = function() return false end,
      listProfiles = function() return { "Default" } end,
      getCurrentProfile = function() return "Default" end,
      setCurrentProfile = function() end,
    }
    _G.TargetBot = { isOn = function() return false end, isLootingEnabled = function() return false end }
    _G.HealBot = { isOn = function() return false end }
    _G.Supplies = {
      getCurrentProfile = function() return "Default" end,
      listProfiles = function() return { "Default" } end,
      getItemsData = function() return { [268] = { min = 50, max = 200, avg = 25 } } end,
      getAdditionalData = function()
        return { softBoots = { enabled = true }, capacity = { enabled = true, value = 100 } }
      end,
      setCurrentProfile = function() end,
      setCondition = function() end,
      setItem = function() return true end,
      removeItem = function() return true end,
    }
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

  it("keeps primary editing inside the workflow page", function()
    local cave = nExBot.UI.ModuleRegistry.get("cavebot").statusProvider().snapshot
    assert.are_equal(1, #cave.actions)
    assert.are_equal("toggle_cavebot", cave.actions[1].id)

    local root = g_ui.createWidget("Root", nil)
    local content = g_ui.createWidget("NexContent", root)
    local lifecycle = nExBot.UI["ui.core.lifecycle"].new("workflow")
    nExBot.UI.ModuleRegistry.get("cavebot").render(nil, content, lifecycle)

    assert.is_truthy(content:recursiveGetChildById("caveProfile"))
    assert.is_nil(content:recursiveGetChildById("open_cave_editor"))
  end)

  it("leaves page titling to the shell header", function()
    local root = g_ui.createWidget("Root", nil)
    local content = g_ui.createWidget("NexContent", root)
    local lifecycle = nExBot.UI["ui.core.lifecycle"].new("workflow")

    nExBot.UI.ModuleRegistry.get("cavebot").render(nil, content, lifecycle)

    assert.is_nil(content:recursiveGetChildById("pageTitle"))
  end)

  it("renders one native Tibia item landmark for each workflow", function()
    local root = g_ui.createWidget("Root", nil)
    local content = g_ui.createWidget("NexContent", root)
    local lifecycle = nExBot.UI["ui.core.lifecycle"].new("workflow")

    nExBot.UI.ModuleRegistry.get("cavebot").render(nil, content, lifecycle)

    local landmark = assert(content:recursiveGetChildById("pageLandmark"))
    assert.are_equal("NexPageLandmark", landmark:getStyle())
    assert.are_equal(3003, landmark:getItemId())
  end)

  it("renders supply editing in the scrollable workflow", function()
    local root = g_ui.createWidget("Root", nil)
    local content = g_ui.createWidget("NexContent", root)
    local lifecycle = nExBot.UI["ui.core.lifecycle"].new("workflow")

    nExBot.UI.ModuleRegistry.get("supplies").render(nil, content, lifecycle)

    assert.is_truthy(content:recursiveGetChildById("supplyProfile"))
    assert.are_equal(268, content:recursiveGetChildById("supplyItem_268"):recursiveGetChildById("item"):getItemId())
    assert.is_truthy(content:recursiveGetChildById("addSupply"))
    assert.is_truthy(content:recursiveGetChildById("supplyCondition_capacity"))
  end)

  it("shows one sanitized action error and removes it after success", function()
    local root = g_ui.createWidget("Root", nil)
    local content = g_ui.createWidget("NexContent", root)
    local lifecycle = nExBot.UI["ui.core.lifecycle"].new("workflow")
    local actions = nExBot.UI.Actions
    local calls = 0
    local original = actions.handlers.toggle_cavebot
    actions.handlers.toggle_cavebot = function()
      calls = calls + 1
      return false, '[string "/ui/core/actions.lua"]:35: boom'
    end

    nExBot.UI.ModuleRegistry.get("cavebot").render(nil, content, lifecycle)
    content:recursiveGetChildById("toggle_cavebot"):click()
    content:recursiveGetChildById("toggle_cavebot"):click()

    local warning = assert(content:recursiveGetChildById("workflowActionError"))
    assert.are_equal("Cave unavailable", warning:getText())
    assert.is_nil(warning:getText():find(".lua", 1, true))
    assert.are_equal(2, calls)

    actions.handlers.toggle_cavebot = function() return true end
    content:recursiveGetChildById("toggle_cavebot"):click()
    assert.is_nil(content:recursiveGetChildById("workflowActionError"))
    actions.handlers.toggle_cavebot = original
  end)
end)
