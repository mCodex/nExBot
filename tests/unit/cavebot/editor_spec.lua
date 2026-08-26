local Harness = require("tests.helpers.widget_harness")

describe("CaveBot.Editor", function()
  local keyHandler

  local function addWaypoint(action, value)
    local wp = CaveBot.addAction(action, value)
    return wp
  end

  local function buttonByText(text)
    for _, button in ipairs(CaveBot.Editor.ui.buttons:getChildren()) do
      if button:getText() == text then return button end
    end
  end

  before_each(function()
    Harness.reset()
    Harness.install()
    _G.nExBot = {}
    dofile("core/ordered_model.lua")
    _G.CaveBot = {
      Route = nExBot.OrderedModel.new(),
      Actions = {},
      save = function() end,
      invalidateWaypointCache = function() end,
      invalidateGotoDistCache = function() end,
      addAction = function(action, value)
        local wp = CaveBot.Route:add({})
        wp:setText(action .. ":" .. value)
        wp.action = action
        wp.value = value
        return wp
      end,
    }
    _G.macro = function() end
    _G.posx = function() return 100 end
    _G.posy = function() return 200 end
    _G.posz = function() return 7 end
    _G.onPlayerPositionChange = function() end
    keyHandler = nil
    _G.onKeyPress = function(fn) keyHandler = fn end

    UI.createWindow = function(name, parent)
      local window = g_ui.createWidget("MainWindow", parent)
      window:setId(name)
      window.tableScroll = g_ui.createWidget("ScrollablePanel", window)
      window.message = g_ui.createWidget("Label", window)
      window.autoRecording = g_ui.createWidget("BotSwitch", window)
      window.pos = g_ui.createWidget("Label", window)
      window.buttons = g_ui.createWidget("Panel", window)
      window.close = g_ui.createWidget("UIButton", window)
      return window
    end

    dofile("cavebot/editor.lua")
    CaveBot.Editor.setup()
  end)

  it("selects a waypoint and keeps the route focus in sync", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    local wp2 = addWaypoint("delay", "500")

    CaveBot.Editor.select(wp1)

    assert.are_equal(wp1, CaveBot.Editor.selected)
    assert.are_equal(wp1, CaveBot.Route:getFocusedChild())
    assert.are_equal(2, CaveBot.Route:getChildCount())
  end)

  it("preserves the selection across a table refresh", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    local wp2 = addWaypoint("delay", "500")

    CaveBot.Editor.select(wp2)
    CaveBot.Editor.refreshTable()

    assert.are_equal(wp2, CaveBot.Editor.selected)
    assert.are_equal(2, #CaveBot.Editor.ui.tableScroll:getChildren())
  end)

  it("removes the selected waypoint and advances selection to its replacement", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    local wp2 = addWaypoint("delay", "500")
    local wp3 = addWaypoint("say", "hi")

    CaveBot.Editor.select(wp2)
    CaveBot.Editor.removeSelected()

    assert.are_equal(2, CaveBot.Route:getChildCount())
    assert.are_equal(wp1, CaveBot.Route:getChildren()[1])
    assert.are_equal(wp3, CaveBot.Route:getChildren()[2])
    assert.are_equal(wp3, CaveBot.Editor.selected)
  end)

  it("removing the last waypoint clears the selection and prompts", function()
    local wp1 = addWaypoint("goto", "100,200,7")

    CaveBot.Editor.select(wp1)
    CaveBot.Editor.removeSelected()

    assert.are_equal(0, CaveBot.Route:getChildCount())
    assert.is_nil(CaveBot.Editor.selected)
    assert.are_equal("Route is empty. Add a waypoint to start building.", CaveBot.Editor.ui.message:getText())
  end)

  it("deletes the selected waypoint via the Remove button", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    CaveBot.Editor.select(wp1)

    buttonByText("Remove").onClick()

    assert.are_equal(0, CaveBot.Route:getChildCount())
    assert.is_nil(CaveBot.Editor.selected)
  end)

  it("moves the selected waypoint via the Move Up button", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    local wp2 = addWaypoint("delay", "500")

    CaveBot.Editor.select(wp2)
    buttonByText("Move Up").onClick()

    assert.are_equal(wp2, CaveBot.Route:getChildren()[1])
    assert.are_equal(wp1, CaveBot.Route:getChildren()[2])
    assert.are_equal(wp2, CaveBot.Editor.selected)
  end)

  it("no-ops buttons without a selection and prompts the user", function()
    local ran = false
    CaveBot.Editor.withSelected(function() ran = true end)

    assert.is_false(ran)
    assert.are_equal("Select a waypoint first.", CaveBot.Editor.ui.message:getText())
  end)

  it("ignores a selection that is no longer in the route", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    CaveBot.Editor.select(wp1)
    wp1:destroy()

    local ran = false
    CaveBot.Editor.withSelected(function() ran = true end)

    assert.is_false(ran)
    assert.is_nil(CaveBot.Editor.selected)
  end)

  it("closes the window via its close button", function()
    CaveBot.Editor.ui:show()
    assert.is_true(CaveBot.Editor.ui:isVisible())

    CaveBot.Editor.ui.close.onClick()

    assert.is_false(CaveBot.Editor.ui:isVisible())
  end)

  it("deletes the selected waypoint on Delete only while the editor is visible", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    local wp2 = addWaypoint("delay", "500")
    CaveBot.Editor.select(wp1)

    keyHandler("Delete")
    assert.are_equal(2, CaveBot.Route:getChildCount())

    CaveBot.Editor.ui:show()
    keyHandler("Delete")
    assert.are_equal(1, CaveBot.Route:getChildCount())
    assert.are_equal(wp2, CaveBot.Route:getChildren()[1])
    assert.are_equal(wp2, CaveBot.Editor.selected)
  end)
end)