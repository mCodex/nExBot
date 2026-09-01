local Harness = require("tests.helpers.widget_harness")

local function boot(state, registry)
  Harness.reset()
  Harness.install()
  _G.nExBot = { UI = {} }
  _G.Conditions = {
    isOn = function() return state.enabled end,
    setOn = function() state.enabled = true end,
    setOff = function() state.enabled = false end,
    getRules = function()
      return {
        { id = "poison", name = "Cure poison", spell = "exana pox", enabled = state.curePoison, cost = 20 },
        { id = "haste", name = "Movement haste", spell = "utani hur", enabled = state.holdHaste, cost = 40 },
      }
    end,
    setRuleEnabled = function(id, enabled) registry.setRule[id] = enabled end,
    getCondition = function(key) return state[key] == true end,
    setCondition = function(key, enabled) state[key] = enabled == true end,
  }
  for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
    dofile("ui/design_system/" .. file .. ".lua")
  end
  dofile("ui/components/components.lua")
  dofile("ui/components/table_model.lua")
  nExBot.UI.VisualAssetResolver = { spell = function() return { source = "spell/icon" } end }
  dofile("ui/components/data_table.lua")
  local Registry = dofile("ui/core/module_registry.lua")
  dofile("ui/modules/conditions.lua")
  return Registry
end

local function renderPage()
  local root = g_ui.createWidget("Root", nil)
  local shell = {
    defer = function(_, callback) callback() end,
    renderCurrent = function(self)
      root:destroyChildren()
      nExBot.UI.ModuleRegistry.get("conditions").render(self, root)
    end,
  }
  shell:renderCurrent()
  return root
end

describe("Conditions page", function()
  it("renders condition toggles with the current values", function()
    local state = {
      enabled = true, curePoison = true, cureCurse = false, cureBleed = false, cureBurn = true,
      cureElectrify = false, cureParalyse = false, holdHaste = true, holdUtamo = false,
      holdUtana = false, holdUtura = false,
    }
    boot(state, { setRule = {} })
    local root = renderPage()

    local expected = {
      curePoison = true, cureCurse = false, cureBleed = false, cureBurn = true,
      cureElectrify = false, cureParalyse = false, holdHaste = true, holdUtamo = false,
      holdUtana = false, holdUtura = false,
    }
    for key, value in pairs(expected) do
      local switch = assert(root:recursiveGetChildById(key), key):recursiveGetChildById("switch")
      assert.are_equal(value, switch:isChecked(), key)
    end
  end)

  it("toggles call the domain setter", function()
    local state = {
      enabled = true, curePoison = false, cureCurse = false, cureBleed = false, cureBurn = false,
      cureElectrify = false, cureParalyse = false, holdHaste = false, holdUtamo = false,
      holdUtana = false, holdUtura = false,
    }
    boot(state, { setRule = {} })
    local root = renderPage()

    local poison = root:recursiveGetChildById("curePoison"):recursiveGetChildById("switch")
    poison:click()
    assert.is_true(state.curePoison)
    assert.is_true(root:recursiveGetChildById("curePoison"):recursiveGetChildById("switch"):isChecked())

    local utura = root:recursiveGetChildById("holdUtura"):recursiveGetChildById("switch")
    utura:click()
    assert.is_true(state.holdUtura)
  end)

  it("keeps the master toggle working", function()
    local state = { enabled = false, curePoison = false, cureCurse = false, cureBleed = false, cureBurn = false,
      cureElectrify = false, cureParalyse = false, holdHaste = false, holdUtamo = false,
      holdUtana = false, holdUtura = false }
    boot(state, { setRule = {} })
    local root = renderPage()

    local enabled = root:recursiveGetChildById("conditionsEnabled"):recursiveGetChildById("switch")
    assert.is_false(enabled:isChecked())
    enabled:click()
    assert.is_true(state.enabled)
    enabled:click()
    assert.is_false(state.enabled)
  end)

  it("keeps the rule table and its enable/disable action working", function()
    local state = { enabled = true, curePoison = true, cureCurse = false, cureBleed = false, cureBurn = false,
      cureElectrify = false, cureParalyse = false, holdHaste = false, holdUtamo = false,
      holdUtana = false, holdUtura = false }
    local registry = { setRule = {} }
    boot(state, registry)
    local root = renderPage()

    assert.is_truthy(root:recursiveGetChildById("conditionRules"))
    assert.are_equal("Disable", root:recursiveGetChildById("condition_poison"):getText())
    root:recursiveGetChildById("condition_poison"):click()
    assert.is_false(registry.setRule.poison)
  end)
end)