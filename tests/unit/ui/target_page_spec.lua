local Harness = require("tests.helpers.widget_harness")

describe("Target page creature editing", function()
  local TargetPage

  local function install()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {} }
    dofile("core/ordered_model.lua")
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    dofile("ui/components/table_model.lua")
    dofile("ui/components/data_table.lua")
    dofile("ui/modules/workflows/shared.lua")
    TargetPage = dofile("ui/modules/workflows/target.lua")
  end

  local function render()
    local root = g_ui.createWidget("Root", nil)
    local shell = {
      defer = function(_, callback) callback() end,
      renderCurrent = function(self)
        root:destroyChildren()
        TargetPage.render(root, self)
      end,
    }
    shell:renderCurrent()
    return root, shell
  end

  it("renders the creature table and inline form", function()
    install()
    _G.TargetBot = { Creatures = nExBot.OrderedModel.new() }
    TargetBot.Creatures:add({ value = { name = "Dragon", pattern = "dragon" } }, true)

    local root = render()

    assert.is_truthy(root:recursiveGetChildById("targetRules"))
    assert.is_truthy(root:recursiveGetChildById("creatureName"))
    assert.is_truthy(root:recursiveGetChildById("creatureEnabled"))
    assert.is_truthy(root:recursiveGetChildById("saveCreature"))
    assert.is_truthy(root:recursiveGetChildById("removeTarget"))
  end)

  it("saves an edited creature through TargetBot.saveCreature", function()
    install()
    local saved
    _G.TargetBot = {
      Creatures = nExBot.OrderedModel.new(),
      saveCreature = function(data) saved = data end,
    }
    local entry = TargetBot.Creatures:add({ value = { name = "Dragon", pattern = "dragon" } }, true)

    local root = render()
    root:recursiveGetChildById("editTarget"):click()
    root:recursiveGetChildById("creatureName"):recursiveGetChildById("input"):setText("Demon")
    root:recursiveGetChildById("saveCreature"):click()

    assert.is_truthy(saved)
    assert.are_equal("Demon", saved.name)
    assert.are_equal(entry, saved.entry)
  end)

  it("adds a new creature through TargetBot.addCreature", function()
    install()
    local added
    _G.TargetBot = {
      Creatures = nExBot.OrderedModel.new(),
      saveCreature = function(data) added = data end,
      addCreature = function(data) return TargetBot.saveCreature(data) end,
    }

    local root = render()
    root:recursiveGetChildById("addTarget"):click()
    root:recursiveGetChildById("creatureName"):recursiveGetChildById("input"):setText("Rat")
    root:recursiveGetChildById("saveCreature"):click()

    assert.is_truthy(added)
    assert.are_equal("Rat", added.name)
  end)

  it("removes the selected creature through removeSelectedCreature", function()
    install()
    local removed
    _G.TargetBot = {
      Creatures = nExBot.OrderedModel.new(),
      removeSelectedCreature = function() removed = true; return true end,
    }
    TargetBot.Creatures:add({ value = { name = "Dragon", pattern = "dragon" } }, true)

    local root = render()
    root:recursiveGetChildById("removeTarget"):click()

    assert.is_true(removed)
  end)
end)