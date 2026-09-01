local Harness = require("tests.helpers.widget_harness")

describe("Friend Healer page controls", function()
  local calls
  local state

  local function freshEnv()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {} }
    calls = { enabled = 0, condition = nil, priorityToggle = 0 }
    state = { enabled = false, conditions = { knights = true, party = false } }
    _G.HealBot = {
      getFriendHealerProjection = function()
        return {
          enabled = state.enabled,
          source = "list",
          threshold = 80,
          conditions = state.conditions,
          priorities = {
            { index = 1, name = "Exura Sio", enabled = true, revision = "1:true" },
            { index = 2, name = "Exura Gran Sio", enabled = false, revision = "2:false" },
          },
          players = {
            { id = "tester", name = "Tester", hp = 45, distance = 2, reason = "READY", revision = "1:45" },
          },
        }
      end,
      setFriendHealerEnabled = function(value) state.enabled = value; calls.enabled = calls.enabled + 1 end,
      setFriendSource = function() end,
      setFriendThreshold = function() end,
      toggleFriendPriority = function(index) calls.priorityToggle = calls.priorityToggle + 1 end,
      moveFriendPriority = function() end,
      setFriendCondition = function(key, value) state.conditions[key] = value; calls.condition = { key = key, value = value } end,
    }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    dofile("ui/components/table_model.lua")
    dofile("ui/components/data_table.lua")
    dofile("ui/core/module_registry.lua")
    dofile("ui/modules/friend_healer.lua")
  end

  local function render()
    local root = g_ui.createWidget("Root", nil)
    local content = g_ui.createWidget("NexContent", root)
    local shell = {
      defer = function(_, callback) callback() end,
      renderCurrent = function(self)
        root:destroyChildren()
        local content = g_ui.createWidget("NexContent", root)
        nExBot.UI["ui.modules.friend_healer"].render(self, content)
      end,
    }
    shell:renderCurrent()
    return root, shell
  end

  it("renders priority and player tables plus condition checkboxes", function()
    freshEnv()
    local root = render()
    assert.is_truthy(root:recursiveGetChildById("friendToggle_1"))
    assert.is_truthy(root:recursiveGetChildById("friendPlayers"))
    assert.is_truthy(root:recursiveGetChildById("friendCondition_knights"))
    assert.is_truthy(root:recursiveGetChildById("friendCondition_party"))
  end)

  it("toggling the enabled switch calls the domain API", function()
    freshEnv()
    local root = render()
    root:recursiveGetChildById("friendEnabled"):recursiveGetChildById("switch"):click()
    assert.are_equal(1, calls.enabled)
    assert.is_true(state.enabled)
  end)

  it("toggling a condition switch writes through the domain API", function()
    freshEnv()
    local root = render()
    root:recursiveGetChildById("friendCondition_knights"):recursiveGetChildById("switch"):click()
    assert.are_equal("knights", calls.condition.key)
    assert.is_false(calls.condition.value)
    assert.is_false(state.conditions.knights)
  end)

  it("Enable / Disable actions call the domain function", function()
    freshEnv()
    local root = render()
    root:recursiveGetChildById("friendToggle_2"):click()
    assert.are_equal(1, calls.priorityToggle)
  end)
end)