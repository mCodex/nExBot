local Harness = require("tests.helpers.widget_harness")

describe("embedded workflow pages", function()
  before_each(function()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {} }
    dofile("core/ordered_model.lua")
    _G.CaveBot = {
      isOn = function() return false end,
      listProfiles = function() return { "Default" } end,
      getCurrentProfile = function() return "Default" end,
      setCurrentProfile = function() end,
      Route = nExBot.OrderedModel.new(),
      Config = { get = function() return false end, set = function() end },
    }
    _G.TargetBot = {
      isOn = function() return false end,
      Looting = { getConfig = function() return { items = {}, containers = {} } end },
      Creatures = nExBot.OrderedModel.new(),
    }
    local healRules = { spell = {}, item = {} }
    _G.HealBot = {
      isOn = function() return false end,
      getActiveProfile = function() return 1 end,
      setActiveProfile = function() end,
      getRules = function(kind) return healRules[kind] end,
      toggleRule = function(kind, index) healRules[kind][index].enabled = not healRules[kind][index].enabled end,
      removeRule = function(kind, index) table.remove(healRules[kind], index) end,
      show = function() end,
      _rules = healRules,
    }
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
    dofile("ui/modules/workflows/shared.lua")
    dofile("ui/modules/workflows/cave.lua")
    dofile("ui/modules/workflows/target.lua")
    dofile("ui/modules/workflows/healing.lua")
    dofile("ui/modules/workflows/looting.lua")
    dofile("ui/modules/workflows/supplies.lua")
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

  it("uses the existing TargetBot looting owner without inventing a second toggle", function()
    local loot = nExBot.UI.ModuleRegistry.get("looting").statusProvider().snapshot

    assert.are_equal("Ready", loot.header.statusText)
    assert.are_equal("Runs with Target", loot.sections[1].rows[2].value)
    assert.are_equal(0, #loot.actions)
  end)

  it("renders a consistent page header", function()
    local root = g_ui.createWidget("Root", nil)
    local content = g_ui.createWidget("NexContent", root)
    local lifecycle = nExBot.UI["ui.core.lifecycle"].new("workflow")

    nExBot.UI.ModuleRegistry.get("cavebot").render(nil, content, lifecycle)

    assert.are_equal("Cave", content:recursiveGetChildById("pageTitle"):getText())
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

  it("restores waypoint and target management without duplicating domain state", function()
    local waypoint = CaveBot.Route:add({ action = "goto", value = "1,2,3" }, true)
    waypoint:setText("goto:1,2,3")
    local target = TargetBot.Creatures:add({ value = { name = "Dragon", pattern = "dragon" } }, true)
    target:setText("Dragon")
    local root = g_ui.createWidget("Root", nil)
    local lifecycle = nExBot.UI["ui.core.lifecycle"].new("workflow")

    local cave = g_ui.createWidget("NexContent", root)
    nExBot.UI.ModuleRegistry.get("cavebot").render({}, cave, lifecycle)
    assert.is_truthy(cave:recursiveGetChildById("openWaypointEditor"))

    local targets = g_ui.createWidget("NexContent", root)
    nExBot.UI.ModuleRegistry.get("targetbot").render({}, targets, lifecycle)
    assert.is_truthy(targets:recursiveGetChildById("targetRule_1"))
    assert.is_truthy(targets:recursiveGetChildById("addTarget"))
    assert.is_truthy(targets:recursiveGetChildById("removeTarget"))
  end)

  it("projects target rules with readable names and stable fallback keys", function()
    local widget = {
      value = { name = "Dragon", pattern = "dragon" },
      getId = function() return "" end,
      getText = function() return "" end,
    }

    local row = nExBot.UI.Workflows.projectTargetRule(widget, 2, false)

    assert.are_equal("targetRule_2", row.id)
    assert.are_equal("Dragon", row.title)
    assert.are_equal("dragon", row.secondary)
    assert.are_equal("Configured", row.statusText)
  end)

  it("restores healing rule management without duplicating domain state", function()
    HealBot._rules.spell[1] = { kind = "spell", index = 1, enabled = true, label = "(MP>0) HP<50%: exura" }
    HealBot._rules.item[1] = { kind = "item", index = 1, enabled = false, label = "HP<50%: item 266" }
    local root = g_ui.createWidget("Root", nil)
    local content = g_ui.createWidget("NexContent", root)
    local lifecycle = nExBot.UI["ui.core.lifecycle"].new("workflow")

    nExBot.UI.ModuleRegistry.get("healing").render({}, content, lifecycle)

    assert.is_truthy(content:recursiveGetChildById("healRule_spell_1"))
    assert.is_truthy(content:recursiveGetChildById("healRule_item_1"))
    assert.is_truthy(content:recursiveGetChildById("manageHealRules"))

    content:recursiveGetChildById("healRuleToggle_item_1"):click()
    assert.is_true(HealBot._rules.item[1].enabled)

    content:recursiveGetChildById("healRuleRemove_spell_1"):click()
    assert.are_equal(0, #HealBot._rules.spell)
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
