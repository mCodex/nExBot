local Harness = require("tests.helpers.widget_harness")

describe("CaveBot.Editor", function()
  local keyHandler
  local Components

  local function addWaypoint(action, value)
    return CaveBot.addAction(action, value)
  end

  local function buttonByText(text)
    for _, button in ipairs(CaveBot.Editor.ui.commands:getChildren()) do
      if button:getText() == text then return button end
    end
  end

  local function clickRow(item, mods)
    _G.g_keyboard = {
      isCtrlPressed = function() return not not (mods and mods.ctrl) end,
      isShiftPressed = function() return not not (mods and mods.shift) end,
    }
    for _, row in ipairs(CaveBot.Editor.ui.tableOptions.rows) do
      if row.__entry == item then
        row.onClick()
        return
      end
    end
    error("row not found for clicked item")
  end

  before_each(function()
    Harness.reset()
    Harness.install()
    _G.g_keyboard = nil
    _G.nExBot = { UI = {}, Nav = {} }

    dofile("core/ordered_model.lua")
    dofile("ui/design_system/tokens.lua")
    dofile("ui/design_system/typography.lua")
    dofile("ui/design_system/density.lua")
    dofile("ui/design_system/status.lua")
    dofile("ui/core/visual_asset_resolver.lua")
    dofile("ui/components/components.lua")
    dofile("ui/components/table_model.lua")
    dofile("ui/components/data_table.lua")
    dofile("cavebot/editor_selection.lua")
    dofile("cavebot/editor_history.lua")
    dofile("cavebot/editor_icons.lua")
    Components = nExBot.UI["ui.components.components"]

    _G.CaveBot = {
      Route = nExBot.OrderedModel.new(),
      -- Every registerAction table-mode call checks CaveBot.Actions[action]
      -- exists (in production, cavebot/actions.lua populates real handlers
      -- before editor.lua loads); the editor doesn't care about the handler
      -- itself, only that it's registered, so any truthy value works here.
      Actions = setmetatable({}, { __index = function() return true end }),
      save = function() end,
      invalidateWaypointCache = function() end,
      invalidateGotoDistCache = function() end,
      addAction = function(action, value)
        local wp = CaveBot.Route:add({})
        wp:setText(action .. ":" .. tostring(value))
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
      window.tableContainer = g_ui.createWidget("ScrollablePanel", window)
      window.palette = g_ui.createWidget("ScrollablePanel", window)
      window.commands = g_ui.createWidget("Panel", window)
      window.message = g_ui.createWidget("Label", window)
      window.autoRecording = g_ui.createWidget("BotSwitch", window)
      window.pos = g_ui.createWidget("Label", window)
      window.close = g_ui.createWidget("UIButton", window)
      return window
    end

    dofile("cavebot/editor.lua")
    CaveBot.Editor.setup()
  end)

  it("selects a waypoint and keeps the route focus in sync", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    addWaypoint("delay", "500")

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
    assert.are_equal(2, #CaveBot.Editor.ui.tableOptions.rows)
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

  it("populates the palette with every registered action exactly once", function()
    local seen = {}
    for _, row in ipairs(CaveBot.Editor.Palette) do
      assert.is_nil(seen[row.action])
      seen[row.action] = true
    end
    assert.is_true(seen["goto"])
    assert.is_true(seen["label"])
    assert.is_true(seen["function"])
  end)

  it("selects only the clicked waypoint on a plain click", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    local wp2 = addWaypoint("delay", "500")
    CaveBot.Editor.refreshTable()

    clickRow(wp1, { ctrl = true })
    clickRow(wp2, {})

    assert.are_equal(1, #CaveBot.Editor.Selection:all())
    assert.is_true(CaveBot.Editor.Selection:isSelected(wp2))
    assert.are_equal(wp2, CaveBot.Editor.selected)
  end)

  it("extends the selection with ctrl-click", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    local wp2 = addWaypoint("delay", "500")
    CaveBot.Editor.refreshTable()

    clickRow(wp1, { ctrl = true })
    clickRow(wp2, { ctrl = true })

    local all = CaveBot.Editor.Selection:all()
    assert.are_equal(2, #all)
    assert.is_true(CaveBot.Editor.Selection:isSelected(wp1))
    assert.is_true(CaveBot.Editor.Selection:isSelected(wp2))
  end)

  it("selects a contiguous range with shift-click", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    local wp2 = addWaypoint("delay", "500")
    local wp3 = addWaypoint("say", "hi")
    CaveBot.Editor.refreshTable()

    clickRow(wp1, {})
    clickRow(wp3, { shift = true })

    local all = CaveBot.Editor.Selection:all()
    assert.are_equal(3, #all)
    assert.are_equal(wp3, CaveBot.Editor.selected)
  end)

  it("deletes multiple selected waypoints only after confirmation", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    local wp2 = addWaypoint("delay", "500")
    local wp3 = addWaypoint("say", "hi")
    CaveBot.Editor.refreshTable()

    clickRow(wp1, { ctrl = true })
    clickRow(wp3, { ctrl = true })

    local captured
    Components.confirmDialog = function(parent, opts) captured = opts end

    CaveBot.Editor.deleteSelection()

    assert.are_equal(3, CaveBot.Route:getChildCount())
    assert.is_not_nil(captured)

    captured.onConfirm()

    assert.are_equal(1, CaveBot.Route:getChildCount())
    assert.are_equal(wp2, CaveBot.Route:getChildren()[1])
    assert.are_equal(wp2, CaveBot.Editor.selected)
  end)

  it("moves a block of selected waypoints down as a unit", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    local wp2 = addWaypoint("delay", "500")
    local wp3 = addWaypoint("say", "hi")
    CaveBot.Editor.refreshTable()

    clickRow(wp1, { ctrl = true })
    clickRow(wp2, { ctrl = true })
    CaveBot.Editor.ui:show()
    keyHandler("Ctrl+Down")

    assert.are_equal(wp3, CaveBot.Route:getChildren()[1])
    assert.are_equal(wp1, CaveBot.Route:getChildren()[2])
    assert.are_equal(wp2, CaveBot.Route:getChildren()[3])
  end)

  it("undoes a block reorder with Ctrl+Z", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    local wp2 = addWaypoint("delay", "500")
    local wp3 = addWaypoint("say", "hi")
    CaveBot.Editor.refreshTable()

    clickRow(wp1, { ctrl = true })
    clickRow(wp2, { ctrl = true })
    CaveBot.Editor.ui:show()
    keyHandler("Ctrl+Down")
    keyHandler("Ctrl+Z")

    assert.are_equal(wp1, CaveBot.Route:getChildren()[1])
    assert.are_equal(wp2, CaveBot.Route:getChildren()[2])
    assert.are_equal(wp3, CaveBot.Route:getChildren()[3])
  end)

  it("undoes a multi-delete with Ctrl+Z, restoring equivalent waypoints", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    local wp2 = addWaypoint("delay", "500")
    local wp3 = addWaypoint("say", "hi")
    CaveBot.Editor.refreshTable()

    clickRow(wp1, { ctrl = true })
    clickRow(wp3, { ctrl = true })

    local captured
    Components.confirmDialog = function(parent, opts) captured = opts end
    CaveBot.Editor.deleteSelection()
    captured.onConfirm()

    CaveBot.Editor.ui:show()
    keyHandler("Ctrl+Z")

    local children = CaveBot.Route:getChildren()
    assert.are_equal(3, #children)
    assert.are_equal("goto", children[1].action)
    assert.are_equal("delay", children[2].action)
    assert.are_equal("say", children[3].action)
  end)

  it("undoes a single delete (via the Remove button) with Ctrl+Z", function()
    local wp1 = addWaypoint("goto", "100,200,7")
    CaveBot.Editor.select(wp1)
    CaveBot.Editor.ui:show()

    buttonByText("Remove").onClick()
    assert.are_equal(0, CaveBot.Route:getChildCount())

    keyHandler("Ctrl+Z")

    assert.are_equal(1, CaveBot.Route:getChildCount())
    assert.are_equal("goto", CaveBot.Route:getChildren()[1].action)
  end)
end)
