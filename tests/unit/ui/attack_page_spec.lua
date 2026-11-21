local Harness = require("tests.helpers.widget_harness")

local function setup(initialEnabled)
  Harness.reset()
  Harness.install()
  local state = {
    enabled = initialEnabled == nil and true or initialEnabled,
    toggledRule = nil,
    movedRule = nil,
    removedRule = nil,
    setting = nil,
    added = nil,
    settings = {
      ignoreMana = false, Kills = false, Cooldown = true, Visible = true,
      pvpMode = false, PvpSafe = true, Training = false, BlackListSafe = false,
      KillsAmount = 1, AntiRsRange = 5,
    },
  }
  _G.AttackBot = {
    isOn = function() return state.enabled end,
    setOn = function() state.enabled = true end,
    setOff = function() state.enabled = false end,
    getActiveProfile = function() return 1 end,
    getRules = function()
      return {
        { index = 1, revision = "1:true", enabled = true, spell = "exori gran",
          count = 3, orMore = false, mana = 1, minHp = 0, maxHp = 100,
          category = 1, patternCategory = 1, pattern = 3, description = "[Spell] 3 Creatures: exori gran" },
      }
    end,
    toggleRule = function(index) state.toggledRule = index end,
    moveRule = function(index, direction) state.movedRule = { index, direction } end,
    removeRule = function(index) state.removedRule = index end,
    getSetting = function(key) return state.settings[key] end,
    setSetting = function(key, value) state.setting = { key, value }; state.settings[key] = value end,
    addRule = function(params) state.added = params; return true end,
  }
  _G.nExBot = { UI = {} }
  for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
    dofile("ui/design_system/" .. file .. ".lua")
  end
  dofile("ui/components/components.lua")
  dofile("ui/components/table_model.lua")
  nExBot.UI.VisualAssetResolver = {
    item = function(_, id) return { name = "Item " .. id } end,
    spell = function(_, spell) return { kind = "text", text = spell } end,
  }
  dofile("ui/components/data_table.lua")
  dofile("ui/core/rule_presenter.lua")
  local Registry = dofile("ui/core/module_registry.lua")
  dofile("ui/modules/attack.lua")

  local root = g_ui.createWidget("Root", nil)
  local shell = {
    defer = function(_, callback) callback() end,
    renderCurrent = function(self)
      root:destroyChildren()
      Registry.get("attack").render(self, root)
    end,
  }
  shell:renderCurrent()
  return state, root
end

describe("Attack page", function()
  it("renders the rule table, settings toggles and add form", function()
    local _, root = setup()
    assert.is_truthy(root:recursiveGetChildById("attackEnabled"))
    assert.is_truthy(root:recursiveGetChildById("toggleAttack_1"))
    assert.is_truthy(root:recursiveGetChildById("attackUp_1"))
    assert.is_truthy(root:recursiveGetChildById("attackDown_1"))
    assert.is_truthy(root:recursiveGetChildById("removeAttack_1"))
    assert.is_truthy(root:recursiveGetChildById("setting_ignoreMana"))
    assert.is_truthy(root:recursiveGetChildById("setting_Cooldown"))
    assert.is_truthy(root:recursiveGetChildById("setting_PvpSafe"))
    assert.is_truthy(root:recursiveGetChildById("setting_BlackListSafe"))
    assert.is_truthy(root:recursiveGetChildById("addAttackRule"))
  end)

  it("toggling a setting writes through the settings API", function()
    local state, root = setup()
    root:recursiveGetChildById("setting_ignoreMana"):recursiveGetChildById("switch"):click()
    assert.same({ "ignoreMana", true }, state.setting)
  end)

  it("toggling the bot switch calls setOn", function()
    local state, root = setup(false)
    root:recursiveGetChildById("attackEnabled"):recursiveGetChildById("switch"):click()
    assert.is_true(state.enabled)
  end)

  it("rule Enable calls toggleRule", function()
    local state, root = setup()
    root:recursiveGetChildById("toggleAttack_1"):click()
    assert.are_equal(1, state.toggledRule)
  end)

  it("rule Remove calls removeRule", function()
    local state, root = setup()
    root:recursiveGetChildById("removeAttack_1"):click()
    assert.are_equal(1, state.removedRule)
  end)

  it("the add form submits a rule through addRule", function()
    local state, root = setup()
    root:recursiveGetChildById("attackSpell"):recursiveGetChildById("input").onTextChange(nil, "exori gran")
    root:recursiveGetChildById("attackOrMore"):recursiveGetChildById("switch"):click()
    root:recursiveGetChildById("addAttackRule"):click()
    assert.are_equal("exori gran", state.added.spell)
    assert.are_equal(1, state.added.category)
    assert.are_equal(true, state.added.orMore)
  end)
end)