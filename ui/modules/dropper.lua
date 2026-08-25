local Components = nExBot.UI["ui.components.components"]
local DataTable = nExBot.UI.DataTable
local Resolver = nExBot.UI.VisualAssetResolver

local DropperPage = {}
local selectedItemId

local LABELS = { trash = "Drop", use = "Use", lowCap = "Low capacity" }

local function rerender(shell)
  if not shell or not shell.renderCurrent then return end
  shell:defer(function()
    if shell.renderCurrent then shell:renderCurrent() end
  end, 0)
end

local function rows(shell, projection)
  local result = {}
  for _, source in ipairs(projection.rows) do
    local row = source
    local visual = Resolver:item(row.id)
    result[#result + 1] = {
      id = row.id,
      revision = projection.revision .. ":" .. row.behavior,
      itemId = row.id,
      title = visual.name,
      secondary = LABELS[row.behavior] .. (row.behavior == "lowCap" and " when capacity is below 150" or " when found"),
      compactSecondary = LABELS[row.behavior],
      status = projection.enabled and "ACTIVE" or "DISABLED",
      statusText = projection.enabled and "Ready" or "Disabled",
      actions = {
        { id = "edit_" .. row.id, text = "Edit", tooltip = "Edit item", onClick = function()
          selectedItemId = row.id
          rerender(shell)
        end },
        { id = "remove_" .. row.id, text = "Remove", variant = "danger", onClick = function()
          nExBot.Dropper.removeItem(row.id)
          if selectedItemId == row.id then selectedItemId = nil end
          rerender(shell)
        end },
      },
    }
  end
  return result
end

function DropperPage.render(shell, content)
  local dropper = nExBot.Dropper
  if not dropper or not dropper.getProjection then
    Components.errorState(content, { message = "Dropper did not load. Check the startup log." })
    return
  end

  local projection = dropper.getProjection()
  Components.pageHeader(content, {
    id = "dropperHeader", textId = "dropperHeaderText",
    title = "Dropper", subtitle = "Handles configured inventory items automatically.",
    badgeId = "dropperStatus",
    status = projection.enabled and "ACTIVE" or "DISABLED",
    statusText = projection.enabled and "Active" or "Disabled",
  })
  Components.toggleRow(content, {
    id = "dropperEnabled", label = "Enabled", value = projection.enabled,
    onChange = function(enabled) dropper.setEnabled(enabled); rerender(shell) end,
  })

  local counts = { trash = 0, use = 0, lowCap = 0 }
  for _, row in ipairs(projection.rows) do counts[row.behavior] = counts[row.behavior] + 1 end
  local summary = Components.card(content, { id = "dropperSummary" })
  Components.keyValueRow(summary, { key = "Trash / Use", value = counts.trash .. " / " .. counts.use })
  Components.keyValueRow(summary, { key = "Low capacity", value = counts.lowCap .. " items · below " .. projection.lowCap })

  DataTable.create(content, {
    id = "dropperItems", title = "Configured items", rows = rows(shell, projection),
    rowKey = function(row) return row.id end, searchable = #projection.rows > 4,
    searchText = function(row) return row.title .. " " .. row.id end,
    emptyMessage = "No items configured. Add the first item below.",
  })

  local selected
  for _, row in ipairs(projection.rows) do
    if row.id == selectedItemId then
      selected = row
      break
    end
  end
  if selectedItemId and not selected then selectedItemId = nil end

  Components.sectionHeader(content, { title = selected and "Edit item" or "Add item" })
  local draft = { id = selected and tostring(selected.id) or "", behavior = selected and selected.behavior or "trash" }
  local idInput = Components.inputRow(content, {
    id = "dropperItemId", label = "Item ID", value = draft.id,
    onChange = function(value) draft.id = value end,
  })
  Components.selectRow(content, {
    id = "dropperBehavior", label = "Behavior",
    options = { { text = "Drop", value = "trash" }, { text = "Use", value = "use" }, { text = "Low capacity", value = "lowCap" } },
    value = LABELS[draft.behavior],
    onChange = function(_, value) draft.behavior = value or draft.behavior end,
  })
  local feedback = Components.label(content, { id = "dropperFeedback", text = "", textStyle = "helper" })
  Components.button(content, {
    id = selected and "saveDropperItem" or "addDropperItem", text = selected and "Save changes" or "Add item",
    onClick = function()
      local itemId = tonumber(draft.id ~= "" and draft.id or idInput:getInput():getText())
      if not itemId or itemId <= 0 or itemId ~= math.floor(itemId) then
        feedback:setText("Enter a valid positive item ID.")
        return
      end
      local ok
      if selected then
        ok = dropper.updateItem(selected.id, itemId, draft.behavior)
      else
        ok = dropper.addItem(itemId, draft.behavior)
      end
      if not ok then
        feedback:setText("That item is already configured.")
        return
      end
      selectedItemId = nil
      rerender(shell)
    end,
  })
  if selected then
    Components.button(content, {
      id = "cancelDropperEdit", text = "Cancel", variant = "ghost",
      onClick = function() selectedItemId = nil; rerender(shell) end,
    })
    Components.button(content, {
      id = "deleteDropperItem", text = "Delete", variant = "danger",
      onClick = function()
        if dropper.removeItem(selected.id) then selectedItemId = nil; rerender(shell) end
      end,
    })
  end
end

nExBot.UI.ModuleRegistry.register({
  id = "dropper", label = "Dropper", order = 52,
  group = "looting", route = "looting/dropper", breadcrumb = "Looting / Dropper",
  render = DropperPage.render,
})
nExBot.UI.DropperPage = DropperPage
nExBot.UI["ui.modules.dropper"] = DropperPage

return DropperPage
