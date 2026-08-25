local Components = nExBot.UI["ui.components.components"]
local DataTable = nExBot.UI.DataTable
local EquipmentPage = {}

local function rerender(shell)
  shell:defer(function() if shell and shell.renderCurrent then shell:renderCurrent() end end, 0)
end

function EquipmentPage.render(shell, content)
  local equipper = nExBot.Equipper
  if not equipper or not equipper.getProjection then
    Components.errorState(content, { message = "Equipment automation is unavailable." })
    return
  end
  local projection = equipper.getProjection()
  Components.pageHeader(content, {
    title = "Equipment", subtitle = "Automatic equipment rules and current state.",
    status = projection.enabled and "ACTIVE" or "DISABLED", statusText = projection.enabled and "Active" or "Disabled",
  })
  Components.toggleRow(content, { label = "Enabled", value = projection.enabled, onChange = function(value) equipper.setEnabled(value); rerender(shell) end })

  local rows = {}
  for _, source in ipairs(projection.rows) do
    local rule = source
    rows[#rows + 1] = {
      id = rule.index, revision = rule.revision, itemId = rule.itemId,
      title = rule.name,
      secondary = "Condition " .. tostring(rule.mainCondition or "-") .. (rule.mainValue ~= nil and (" · " .. tostring(rule.mainValue)) or ""),
      status = rule.index == projection.activeRule and "ACTIVE" or rule.enabled and "INFO" or "DISABLED",
      statusText = rule.index == projection.activeRule and "Equipped" or rule.enabled and "Ready" or "Disabled",
      actions = {
        { id = "equipmentToggle_" .. rule.index, text = rule.enabled and "Disable" or "Enable", onClick = function() equipper.toggleRule(rule.index); rerender(shell) end },
        { id = "equipmentUp_" .. rule.index, text = "Up", onClick = function() equipper.moveRule(rule.index, "up"); rerender(shell) end },
        { id = "equipmentDown_" .. rule.index, text = "Down", onClick = function() equipper.moveRule(rule.index, "down"); rerender(shell) end },
        { id = "equipmentRemove_" .. rule.index, text = "Remove", variant = "danger", onClick = function() equipper.removeRule(rule.index); rerender(shell) end },
      },
    }
  end
  DataTable.create(content, {
    id = "equipmentRules", title = "Rules", rows = rows,
    rowKey = function(row) return row.id end, searchable = #rows > 4,
    emptyMessage = "No equipment rules yet. Add the first rule.",
  })
  Components.button(content, { id = "manageEquipment", text = "Add or edit rule", onClick = equipper.show })
end

nExBot.UI.ModuleRegistry.register({
  id = "equipment_rules", label = "Equipment", order = 46,
  group = "equipment", route = "equipment/rules", breadcrumb = "Equipment / Rules",
  render = EquipmentPage.render,
})
nExBot.UI.EquipmentPage = EquipmentPage
nExBot.UI["ui.modules.equipment"] = EquipmentPage

return EquipmentPage
