local Harness = require("tests.helpers.widget_harness")

describe("Healing page rule and settings controls", function()
  local calls
  local healRules
  local settings

  local function freshEnv()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {} }
    calls = { setOn = 0, setOff = 0, toggle = 0, removed = 0, setting = nil, addRule = nil }
    healRules = {
      spell = { { index = 1, spell = "exura", sign = "<", origin = "HP%", value = 50, cost = 30, enabled = true } },
      item = {},
    }
    settings = { Cooldown = true, Visible = true, Delay = true, Interval = true, Conditions = true }
    _G.HealBot = {
      isOn = function() return false end,
      setOn = function() calls.setOn = calls.setOn + 1 end,
      setOff = function() calls.setOff = calls.setOff + 1 end,
      getActiveProfile = function() return 1 end,
      setActiveProfile = function() end,
      getRules = function(kind) return healRules[kind] end,
      addRule = function(kind, params) calls.addRule = { kind = kind, params = params } return true end,
      getSetting = function(key) return settings[key] end,
      setSetting = function(key, value) settings[key] = value; calls.setting = { key = key, value = value } end,
      toggleRule = function(kind, index)
        healRules[kind][index].enabled = not healRules[kind][index].enabled
        calls.toggle = calls.toggle + 1
      end,
      removeRule = function(kind, index) table.remove(healRules[kind], index); calls.removed = calls.removed + 1 end,
      moveRule = function() return false end,
      show = function() end,
      showAlly = function() return false end,
    }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/core/visual_asset_resolver.lua")
    dofile("ui/core/rule_presenter.lua")
    dofile("ui/components/components.lua")
    dofile("ui/components/table_model.lua")
    dofile("ui/components/data_table.lua")
    dofile("ui/core/module_registry.lua")
    dofile("ui/modules/workflows/shared.lua")
    dofile("ui/modules/workflows/healing.lua")
  end

  local function render()
    local root = g_ui.createWidget("Root", nil)
    local content = g_ui.createWidget("NexContent", root)
    local shell = {
      defer = function(_, callback) callback() end,
      renderCurrent = function(self)
        root:destroyChildren()
        local content = g_ui.createWidget("NexContent", root)
        nExBot.UI["ui.modules.workflows.healing"].render(content, self)
      end,
    }
    shell:renderCurrent()
    return root, shell
  end

  it("renders rule tables, the enabled toggle, and the settings section", function()
    freshEnv()
    local root = render()
    assert.is_truthy(root:recursiveGetChildById("healRuleToggle_spell_1"))
    assert.is_truthy(root:recursiveGetChildById("healEnabled"))
    assert.is_truthy(root:recursiveGetChildById("healAddRule"))
    assert.is_truthy(root:recursiveGetChildById("healSetting_Cooldown"))
    assert.is_truthy(root:recursiveGetChildById("healSetting_Conditions"))
  end)

  it("toggles the enabled switch through the domain API", function()
    freshEnv()
    local root = render()
    root:recursiveGetChildById("healEnabled"):recursiveGetChildById("switch"):click()
    assert.are_equal(1, calls.setOn)
  end)

  it("toggling a setting writes it back through the domain API", function()
    freshEnv()
    local root = render()
    root:recursiveGetChildById("healSetting_Cooldown"):recursiveGetChildById("switch"):click()
    assert.are_equal("Cooldown", calls.setting.key)
    assert.is_false(calls.setting.value)
    assert.is_false(settings.Cooldown)
  end)

  it("Enable and Remove actions call domain functions", function()
    freshEnv()
    local root = render()
    root:recursiveGetChildById("healRuleToggle_spell_1"):click()
    assert.are_equal(1, calls.toggle)
    assert.is_false(healRules.spell[1].enabled)

    root:recursiveGetChildById("healRuleRemove_spell_1"):click()
    assert.are_equal(1, calls.removed)
    assert.are_equal(0, #healRules.spell)
  end)

  it("the add form submits a new rule through the domain API", function()
    freshEnv()
    local root = render()
    root:recursiveGetChildById("healAddValue"):recursiveGetChildById("input").onTextChange(nil, "40")
    root:recursiveGetChildById("healAddSpell"):recursiveGetChildById("input").onTextChange(nil, "exura vita")
    root:recursiveGetChildById("healAddCost"):recursiveGetChildById("input").onTextChange(nil, "45")
    root:recursiveGetChildById("healAddRule"):click()

    assert.are_equal("spell", calls.addRule.kind)
    assert.are_equal("40", calls.addRule.params.value)
    assert.are_equal("exura vita", calls.addRule.params.spell)
    assert.are_equal("45", calls.addRule.params.cost)
  end)
end)