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

  local slots = (equipper.getSlots and equipper.getSlots()) or {}
  local slotsCard = Components.card(content, { id = "equipmentSlots" })
  Components.sectionHeader(slotsCard, { title = "Slots" })
  for _, slot in ipairs(slots) do
    Components.keyValueRow(slotsCard, {
      id = "equipmentSlot_" .. slot.index, key = slot.name,
      value = slot.itemId and slot.itemId > 0 and tostring(slot.itemId) or "Empty",
    })
  end
  Components.label(slotsCard, {
    id = "slotsManageHint", text = "Slot targets are chosen per rule in the form below.",
    textStyle = "helper",
  })

  local rows = {}
  for _, source in ipairs(projection.rows) do
    local rule = source
    rows[#rows + 1] = {
      id = rule.index, revision = rule.revision, itemId = rule.itemId,
      title = rule.name,
      secondary = "Condition " .. tostring(rule.mainCondition or "-") .. (rule.mainValue ~= nil and (" / " .. tostring(rule.mainValue)) or ""),
      status = rule.index == projection.activeRule and "ACTIVE" or rule.enabled and "INFO" or "DISABLED",
      statusText = rule.index == projection.activeRule and "Equipped" or rule.enabled and "Ready" or "Disabled",
      actions = {
        { id = "equipmentToggle_" .. rule.index, text = rule.enabled and "Disable" or "Enable", tooltip = "Enable or disable this rule", onClick = function() equipper.toggleRule(rule.index); rerender(shell) end },
        { id = "equipmentUp_" .. rule.index, text = "Up", tooltip = "Raise rule priority", onClick = function() equipper.moveRule(rule.index, "up"); rerender(shell) end },
        { id = "equipmentDown_" .. rule.index, text = "Down", tooltip = "Lower rule priority", onClick = function() equipper.moveRule(rule.index, "down"); rerender(shell) end },
        { id = "equipmentRemove_" .. rule.index, text = "Remove", variant = "danger", tooltip = "Remove this rule", onClick = function() equipper.removeRule(rule.index); rerender(shell) end },
      },
    }
  end
  DataTable.create(content, {
    id = "equipmentRules", title = "Rules", rows = rows,
    rowKey = function(row) return row.id end, searchable = #rows > 4,
    emptyMessage = "No equipment rules yet. Add the first rule below.",
  })

  local slotOptions = {}
  for _, slot in ipairs(slots) do slotOptions[#slotOptions + 1] = { text = slot.name, value = slot.index } end
  Components.sectionHeader(content, { title = "Add rule" })
  local draft = { name = "", slot = 1, action = "unequip", itemId = "" }
  local nameInput = Components.inputRow(content, {
    id = "equipmentRuleName", label = "Rule name", value = draft.name,
    onChange = function(value) draft.name = value end,
  })
  local slotSelect = Components.selectRow(content, {
    id = "equipmentRuleSlot", label = "Slot", options = slotOptions,
    value = slotOptions[1] and slotOptions[1].text or "Head",
    onChange = function(_, value) draft.slot = value or draft.slot end,
  })
  local actionSelect = Components.selectRow(content, {
    id = "equipmentRuleAction", label = "Action",
    options = { { text = "Unequip", value = "unequip" }, { text = "Equip item", value = "equip" } },
    value = "Unequip",
    onChange = function(_, value) draft.action = value or draft.action end,
  })
  local itemInput = Components.inputRow(content, {
    id = "equipmentRuleItem", label = "Item ID", value = draft.itemId,
    onChange = function(value) draft.itemId = value end,
  })
  local feedback = Components.label(content, { id = "equipmentFormFeedback", text = "", textStyle = "helper" })
  Components.button(content, {
    id = "addEquipmentRule", text = "Add rule",
    onClick = function()
      local data = {}
      for i = 1, #slots do data[i] = false end
      if draft.action == "equip" then
        local itemId = tonumber(draft.itemId ~= "" and draft.itemId or itemInput:getInput():getText())
        if not itemId or itemId <= 100 then
          feedback:setText("Enter a valid item ID above 100.")
          return
        end
        data[draft.slot] = itemId
      else
        data[draft.slot] = true
      end
      local name = draft.name ~= "" and draft.name or nameInput:getInput():getText()
      local ok, err = equipper.addRule({ name = name, data = data })
      if not ok then
        feedback:setText(err or "Could not add the rule.")
        return
      end
      draft.name, draft.itemId = "", ""
      rerender(shell)
    end,
  })

  local bosses = (equipper.getBosses and equipper.getBosses()) or {}
  Components.sectionHeader(content, { title = "Boss list" })
  local bossCard = Components.card(content, { id = "equipmentBosses" })
  if #bosses == 0 then
    Components.emptyState(bossCard, { id = "equipmentBossEmpty", message = "No bosses configured." })
  end
  for _, boss in ipairs(bosses) do
    Components.listRow(bossCard, {
      id = "equipmentBoss_" .. boss, title = boss,
      actions = { { id = "equipmentBossRemove_" .. boss, text = "Remove", variant = "danger", tooltip = "Stop treating this creature as a boss", onClick = function() equipper.removeBoss(boss); rerender(shell) end } },
    })
  end
  local bossDraft = { name = "" }
  local bossInput = Components.inputRow(bossCard, {
    id = "equipmentBossName", label = "Boss name", value = bossDraft.name,
    onChange = function(value) bossDraft.name = value end,
  })
  local bossFeedback = Components.label(bossCard, { id = "equipmentBossFeedback", text = "", textStyle = "helper" })
  Components.button(bossCard, {
    id = "addEquipmentBoss", text = "Add boss",
    onClick = function()
      local name = bossDraft.name ~= "" and bossDraft.name or bossInput:getInput():getText()
      local ok, err = equipper.addBoss(name)
      if not ok then
        bossFeedback:setText(err or "Could not add the boss.")
        return
      end
      bossDraft.name = ""
      rerender(shell)
    end,
  })
end

nExBot.UI.ModuleRegistry.register({
  id = "equipment_rules", label = "Equipment", order = 46,
  group = "equipment", route = "equipment/rules", breadcrumb = "Equipment / Rules",
  render = EquipmentPage.render,
})
nExBot.UI.EquipmentPage = EquipmentPage
nExBot.UI["ui.modules.equipment"] = EquipmentPage

return EquipmentPage