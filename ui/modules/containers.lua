local Components = nExBot.UI["ui.components.components"]
local DataTable = nExBot.UI.DataTable
local Resolver = nExBot.UI.VisualAssetResolver

local ContainersPage = {}

local function rerender(shell)
  if not shell or not shell.renderCurrent then return end
  shell:defer(function()
    if shell.renderCurrent then shell:renderCurrent() end
  end, 0)
end

local function containerRows(shell, domain)
  local rows = {}
  for index, entry in ipairs(domain.getContainerList()) do
    local visual = Resolver:item(entry.itemId or 0)
    rows[#rows + 1] = {
      id = index,
      revision = tostring(index) .. ":" .. tostring(entry.enabled) .. ":" .. tostring(entry.itemId),
      itemId = entry.itemId,
      title = entry.name or visual.name,
      secondary = visual.name .. " / " .. tostring(#(entry.items or {})) .. " items",
      status = entry.enabled and "ACTIVE" or "DISABLED",
      statusText = entry.enabled and "On" or "Off",
      actions = {
        { id = "containerToggle_" .. index, text = entry.enabled and "Disable" or "Enable",
          tooltip = entry.enabled and "Disable this container" or "Enable this container",
          onClick = function() domain.setContainerEnabled(index, not entry.enabled); rerender(shell) end },
        { id = "containerRemove_" .. index, text = "Remove", variant = "danger",
          tooltip = "Remove this container",
          onClick = function() domain.removeContainer(index); rerender(shell) end },
      },
    }
  end
  return rows
end

function ContainersPage.render(shell, content)
  local domain = Containers
  if not domain or not domain.getContainerList then
    Components.errorState(content, { message = "Containers did not load. Check the startup log." })
    return
  end

  Components.pageHeader(content, {
    id = "containersHeader", textId = "containersHeaderText",
    title = "Containers", subtitle = "Backpack setup, sorting and auto-open behavior.",
  })

  DataTable.create(content, {
    id = "containerTable", title = "Configured containers", rows = containerRows(shell, domain),
    rowKey = function(row) return row.id end, searchable = #domain.getContainerList() > 4,
    emptyMessage = "No containers configured. Add the first container below.",
  })

  Components.sectionHeader(content, { title = "Behavior" })
  local behavior = domain.getBehavior()
  for _, toggle in ipairs({
    { key = "sortEnabled", label = "Sort items", value = behavior.sortEnabled,
      onChange = function(value) domain.setSortEnabled(value); rerender(shell) end },
    { key = "forceOpen", label = "Keep open", value = behavior.forceOpen,
      onChange = function(value) domain.setForceOpen(value); rerender(shell) end },
    { key = "renameEnabled", label = "Rename windows", value = behavior.renameEnabled,
      onChange = function(value) domain.setRenameEnabled(value); rerender(shell) end },
    { key = "lootBag", label = "Manage loot bag", value = behavior.lootBag,
      onChange = function(value) domain.setLootBag(value); rerender(shell) end },
  }) do
    Components.toggleRow(content, {
      id = "behavior_" .. toggle.key, label = toggle.label, value = toggle.value, onChange = toggle.onChange,
    })
  end

  Components.sectionHeader(content, { title = "Add container" })
  local draft = { name = "", itemId = "" }
  local nameInput = Components.inputRow(content, {
    id = "containerName", label = "Name", onChange = function(value) draft.name = value end,
  })
  local idInput = Components.inputRow(content, {
    id = "containerItemId", label = "Item ID", onChange = function(value) draft.itemId = value end,
  })
  local feedback = Components.label(content, { id = "containerFeedback", text = "", textStyle = "helper" })
  Components.button(content, {
    id = "addContainer", text = "Add container",
    onClick = function()
      local name = draft.name ~= "" and draft.name or nameInput:getInput():getText()
      local itemId = draft.itemId ~= "" and draft.itemId or idInput:getInput():getText()
      if not domain.addContainer(name, itemId) then
        feedback:setText("Enter a name and a valid item ID (>= 100).")
        return
      end
      draft.name, draft.itemId = "", ""
      feedback:setText("")
      rerender(shell)
    end,
  })
end

nExBot.UI.ModuleRegistry.register({
  id = "containers", label = "Containers", order = 85,
  group = "looting", route = "looting/containers", breadcrumb = "Looting / Containers",
  render = ContainersPage.render,
})
nExBot.UI.ContainersPage = ContainersPage
nExBot.UI["ui.modules.containers"] = ContainersPage

return ContainersPage