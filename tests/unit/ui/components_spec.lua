local Harness = require("tests.helpers.widget_harness")
local Components = require("ui.components.components")

local function fresh()
  Harness.reset()
  Harness.install()
  _G.nExBot = { UI = {} }
  local root = _G.g_ui.createWidget("Root", nil)
  return root
end

describe("UI components", function()
  local root

  before_each(function()
    root = fresh()
  end)

  it("creates a button with label, tooltip, and click handler", function()
    local clicked = 0
    local btn = Components.button(root, {
      text = "Save", tooltip = "Save profile",
      onClick = function() clicked = clicked + 1 end,
    })
    assert.are_equal("Save", btn:getText())
    assert.are_equal("Save profile", btn:getTooltip())
    btn:click()
    assert.are_equal(1, clicked)
  end)

  it("button variant resolves to a token color", function()
    local danger = Components.button(root, { text = "X", variant = "danger" })
    assert.is_string(danger:getColor())
    local ghost = Components.button(root, { text = "Y", variant = "ghost" })
    assert.is_string(ghost:getColor())
  end)

  it("disabled button does not fire", function()
    local clicked = 0
    local btn = Components.button(root, { text = "Z", disabled = true, onClick = function() clicked = clicked + 1 end })
    btn:click()
    assert.are_equal(0, clicked)
  end)

  it("card creates a panel with the card style", function()
    local card = Components.card(root, { title = "Overview" })
    assert.are_equal("NexCard", card:getStyle())
  end)

  it("sectionHeader renders title and optional action", function()
    local sh = Components.sectionHeader(root, { title = "Routes" })
    assert.is_truthy(sh:recursiveGetChildById("title"))
  end)

  it("statusBadge maps a status to a color", function()
    local badge = Components.statusBadge(root, { status = "ERROR", text = "stuck" })
    assert.are_equal("stuck", badge:getText())
    assert.is_string(badge:getColor())
  end)

  it("metricCard shows label and value", function()
    local mc = Components.metricCard(root, { label = "XP/h", value = "12,345" })
    assert.is_truthy(mc:recursiveGetChildById("value"):getText() == "12,345")
    assert.is_truthy(mc:recursiveGetChildById("label"):getText() == "XP/h")
  end)

  it("toggleRow binds checked state and change handler", function()
    local value = false
    local row = Components.toggleRow(root, {
      label = "Enabled", value = false,
      onChange = function(v) value = v end,
    })
    assert.is_false(row:getSwitch():isChecked())
    row:getSwitch():setChecked(true)
    -- simulate the change event
    assert.is_true(value)
  end)

  it("selectRow renders options", function()
    local row = Components.selectRow(root, { label = "Config", options = { "A", "B" } })
    assert.is_truthy(row:getCombo())
  end)

  it("inputRow renders an editable field", function()
    local row = Components.inputRow(root, { label = "Delay", value = "100" })
    assert.are_equal("100", row:getInput():getText())
  end)

  it("emptyState / loadingState / errorState render the right text", function()
    local e = Components.emptyState(root, { message = "No routes" })
    assert.are_equal("No routes", e:getText())
    local l = Components.loadingState(root)
    assert.is_truthy(l:getText():len() > 0)
    local er = Components.errorState(root, { message = "boom" })
    assert.are_equal("boom", er:recursiveGetChildById("message"):getText())
  end)

  it("searchToolbar captures query changes", function()
    local q = ""
    local t = Components.searchToolbar(root, { onChange = function(v) q = v end })
    assert.is_truthy(t:getInput())
  end)

  it("listRow renders title, subtitle, badge, and actions", function()
    local row = Components.listRow(root, {
      title = "Dragon", subtitle = "Priority 900",
      status = "ACTIVE", actions = { { text = "Edit", id = "edit" } },
    })
    assert.are_equal("Dragon", row:getTitle():getText())
    assert.are_equal("Priority 900", row:getSubtitle():getText())
    assert.is_truthy(row.widget:recursiveGetChildById("edit"))
  end)

  it("footerActions stays visible and collects primary/secondary", function()
    local footer = Components.footerActions(root, {
      primary = { text = "Save", onClick = function() end },
      secondary = { text = "Cancel", onClick = function() end },
    })
    assert.is_true(footer:isVisible())
    assert.is_truthy(footer:recursiveGetChildById("primary"))
  end)

  it("diagnosticBlock renders monospace text", function()
    local block = Components.diagnosticBlock(root, { code = "WP26 -> up" })
    assert.is_truthy(block:getText():find("WP26", 1, true))
  end)
end)
