-- Target workflow controls: creature profile, target rule table, paging.

local Components = nExBot and nExBot.UI and nExBot.UI["ui.components.components"]
local DataTable = nExBot and nExBot.UI and nExBot.UI.DataTable
local Shared = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.shared"]

local TargetPage = {}
local targetPage = 1

function TargetPage.projectTargetRule(widget, index, selected)
  local value = widget.value or {}
  local name = Shared.present(widget.getText and widget:getText(), value.name)
  return {
    id = Shared.present(widget.getId and widget:getId(), "targetRule_" .. index),
    revision = table.concat({ index, name or "", value.pattern or "" }, ":"),
    title = Shared.present(name, "Target " .. index),
    secondary = Shared.present(value.pattern, Shared.present(value.name, "Creature rule")),
    status = selected and "ACTIVE" or "INFO",
    statusText = selected and "Selected" or "Configured",
  }
end

function TargetPage.render(content, shell)
  if not TargetBot then return end
  Components.sectionHeader(content, { title = "Creature profile" })
  Shared.profileSelect(content, {
    id = "targetProfile",
    items = TargetBot.listProfiles and TargetBot.listProfiles() or {},
    value = TargetBot.getCurrentProfile and TargetBot.getCurrentProfile(),
    onChange = function(name)
      if TargetBot.setCurrentProfile then TargetBot.setCurrentProfile(name) end
      Shared.rerender(shell)
    end,
  })
  Shared.newProfileAction(content, {
    id = "newTargetProfile", text = "New Profile", shell = shell,
    prompt = { title = "New Target Profile", label = "Enter a name for the new profile" },
    onCreate = function(name)
      if not TargetBot.createProfile then return false, "Not available" end
      return TargetBot.createProfile(name)
    end,
  })

  local creatures = TargetBot.Creatures
  if not creatures or not creatures.getChildren then return end
  local rules = creatures:getChildren()
  local pages, first, last
  targetPage, pages, first, last = Shared.pageBounds(targetPage, #rules)
  Components.sectionHeader(content, { title = "Targets" })
  if #rules == 0 then
    Components.emptyState(content, { message = "No target rules. Add the first target." })
  elseif DataTable then
    local tableRows = {}
    local selected = creatures:getFocusedChild()
    for index = first, last do
      local widget = rules[index]
      local row = TargetPage.projectTargetRule(widget, index, widget == selected)
      row.onClick = function() creatures:focus(widget); Shared.rerender(shell) end
      tableRows[#tableRows + 1] = row
    end
    DataTable.create(content, {
      id = "targetRules", title = "Creature rules", rows = tableRows,
      rowKey = function(row) return row.id end, searchable = #tableRows > 4,
      searchText = function(row) return row.title .. " " .. row.secondary end,
      emptyMessage = "No target rules. Add the first target.",
    })
  else
    Components.label(content, { text = string.format("Showing %d-%d of %d", first, last, #rules), textStyle = "metadata" })
    local selected = creatures:getFocusedChild()
    for index = first, last do
      local rule = rules[index]
      local projected = TargetPage.projectTargetRule(rule, index, rule == selected)
      local row = Components.listRow(content, {
        id = "targetRule_" .. index,
        title = projected.title,
        subtitle = projected.secondary,
        status = rule == selected and "ACTIVE" or nil,
        statusText = rule == selected and "Selected" or nil,
      }).widget
      row.onClick = function()
        creatures:focus(rule)
        Shared.rerender(shell)
      end
    end
  end

  local paging = Shared.actionBar(content)
  Shared.actionButton(paging, { id = "targetPrevious", text = "Previous", disabled = targetPage == 1, onClick = function()
    targetPage = targetPage - 1; Shared.rerender(shell)
  end })
  Shared.actionButton(paging, { id = "targetNext", text = "Next", disabled = targetPage == pages, onClick = function()
    targetPage = targetPage + 1; Shared.rerender(shell)
  end })

  local actions = Shared.actionBar(content)
  Shared.actionButton(actions, { id = "addTarget", text = "Add Target", onClick = function()
    if TargetBot.addCreature then TargetBot.addCreature() end
  end })
  Shared.actionButton(actions, { id = "editTarget", text = "Edit", onClick = function()
    if creatures:getFocusedChild() and TargetBot.showCreatureEditor then TargetBot.showCreatureEditor() end
  end })
  Shared.actionButton(actions, { id = "removeTarget", text = "Remove", variant = "danger", onClick = function()
    if creatures:getFocusedChild() and TargetBot.removeSelectedCreature then TargetBot.removeSelectedCreature(); Shared.rerender(shell) end
  end })
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI["ui.modules.workflows.target"] = TargetPage
end

return TargetPage
