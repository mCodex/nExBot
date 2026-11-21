local Harness = require("tests.helpers.widget_harness")

describe("Equipment page", function()
  it("renders rules and slots summary from the domain projection", function()
    Harness.reset()
    Harness.install()
    local rules = {
      { index = 1, name = "Tank set", revision = "1:true:3029", itemId = 3029, enabled = true, mainCondition = 2, mainValue = 3 },
      { index = 2, name = "Resist", revision = "2:false:3358", itemId = 3358, enabled = false, mainCondition = 1 },
    }
    local toggled
    local moved
    local removed
    _G.nExBot = { UI = {}, Equipper = {
      getProjection = function() return { enabled = true, activeRule = nil, rows = rules } end,
      setEnabled = function() end,
      toggleRule = function(index) toggled = index end,
      moveRule = function(index, direction) moved = { index, direction } end,
      removeRule = function(index) removed = index end,
      getSlots = function()
        return {
          { index = 1, name = "Head", itemId = 3029 },
          { index = 2, name = "Body", itemId = 0 },
          { index = 3, name = "Legs", itemId = 0 },
          { index = 4, name = "Feet", itemId = 0 },
          { index = 5, name = "Neck", itemId = 0 },
          { index = 6, name = "Left hand", itemId = 0 },
          { index = 7, name = "Right hand", itemId = 0 },
          { index = 8, name = "Finger", itemId = 0 },
          { index = 9, name = "Ammo", itemId = 0 },
        }
      end,
      getBosses = function() return { "Orshabaal" } end,
      addBoss = function() return true end,
      removeBoss = function() return true end,
      addRule = function() return true end,
    } }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    dofile("ui/components/table_model.lua")
    nExBot.UI.VisualAssetResolver = { item = function() return { name = "Item" } end }
    dofile("ui/components/data_table.lua")
    local Registry = dofile("ui/core/module_registry.lua")
    dofile("ui/modules/equipment.lua")

    local root = g_ui.createWidget("Root", nil)
    local shell = {
      defer = function(_, callback) callback() end,
      renderCurrent = function(self)
        root:destroyChildren()
        Registry.get("equipment_rules").render(self, root)
      end,
    }
    shell:renderCurrent()

    assert.are_equal("3029", root:recursiveGetChildById("equipmentSlot_1"):recursiveGetChildById("value"):getText())
    assert.are_equal("Empty", root:recursiveGetChildById("equipmentSlot_2"):recursiveGetChildById("value"):getText())

    assert.are_equal("Tank set", root:recursiveGetChildById("equipmentRules_1"):recursiveGetChildById("title"):getText())
    root:recursiveGetChildById("equipmentToggle_1"):click()
    assert.are_equal(1, toggled)
    root:recursiveGetChildById("equipmentUp_1"):click()
    assert.same({ 1, "up" }, moved)
    root:recursiveGetChildById("equipmentDown_2"):click()
    assert.same({ 2, "down" }, moved)
    root:recursiveGetChildById("equipmentRemove_2"):click()
    assert.are_equal(2, removed)

    assert.are_equal("Orshabaal", root:recursiveGetChildById("equipmentBoss_Orshabaal"):recursiveGetChildById("title"):getText())
    root:recursiveGetChildById("equipmentBossRemove_Orshabaal"):click()
  end)

  it("adds a rule through the inline form", function()
    Harness.reset()
    Harness.install()
    local added
    _G.nExBot = { UI = {}, Equipper = {
      getProjection = function() return { enabled = false, activeRule = nil, rows = {} } end,
      setEnabled = function() end,
      toggleRule = function() end,
      moveRule = function() end,
      removeRule = function() end,
      getSlots = function()
        local slots = {}
        local names = { "Head", "Body", "Legs", "Feet", "Neck", "Left hand", "Right hand", "Finger", "Ammo" }
        for i = 1, 9 do slots[i] = { index = i, name = names[i], itemId = 0 } end
        return slots
      end,
      getBosses = function() return {} end,
      addBoss = function() return true end,
      removeBoss = function() return true end,
      addRule = function(rule) added = rule; return true end,
    } }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    dofile("ui/components/table_model.lua")
    nExBot.UI.VisualAssetResolver = { item = function() return { name = "Item" } end }
    dofile("ui/components/data_table.lua")
    local Registry = dofile("ui/core/module_registry.lua")
    dofile("ui/modules/equipment.lua")

    local root = g_ui.createWidget("Root", nil)
    local shell = {
      defer = function(_, callback) callback() end,
      renderCurrent = function(self)
        root:destroyChildren()
        Registry.get("equipment_rules").render(self, root)
      end,
    }
    shell:renderCurrent()

    root:recursiveGetChildById("equipmentRuleName"):recursiveGetChildById("input").onTextChange(nil, "Head tank")
    root:recursiveGetChildById("equipmentRuleAction"):recursiveGetChildById("combo").onOptionChange(nil, nil, "equip")
    root:recursiveGetChildById("equipmentRuleItem"):recursiveGetChildById("input").onTextChange(nil, "3029")
    root:recursiveGetChildById("addEquipmentRule"):click()

    assert.are_equal("Head tank", added.name)
    assert.are_equal(9, #added.data)
    assert.are_equal(3029, added.data[1])
    assert.is_false(added.data[2])
  end)
end)