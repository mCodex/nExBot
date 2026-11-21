local Components = nExBot.UI["ui.components.components"]
local DataTable = nExBot.UI.DataTable
local Resolver = nExBot.UI.VisualAssetResolver
local Shared = nExBot.UI["ui.modules.workflows.shared"] or (type(require) == "function" and require("ui.modules.workflows.shared"))

local DepositerPage = {}

local function rerender(shell)
  Shared.rerender(shell)
end

local function itemName(id)
  if Resolver and Resolver.item then
    local resolved = Resolver:item(id)
    if resolved and resolved.name then return resolved.name end
  end
  return "Item " .. id
end

local function rows(shell, depositer, items)
  local result = {}
  for _, entry in ipairs(items) do
    local id = entry.id
    if id and id > 0 then
      result[#result + 1] = {
        id = id,
        revision = tostring(entry.index or 3),
        itemId = id,
        title = itemName(id),
        secondary = "Stash to depot: " .. (entry.index or 3),
        status = "INFO",
        statusText = "Depot " .. (entry.index or 3),
        actions = {
          { id = "remove_" .. id, text = "Remove", variant = "danger", tooltip = "Remove this item from the stash list", onClick = function()
            if depositer.removeItem(id) then rerender(shell) end
          end },
        },
      }
    end
  end
  return result
end

function DepositerPage.render(shell, content)
  local depositer = nExBot.Depositer
  if not depositer or not depositer.getItems then
    Components.errorState(content, { message = "Depositer did not load. Check the startup log." })
    return
  end

  local items = depositer.getItems()
  Components.pageHeader(content, {
    id = "depositerHeader", textId = "depositerHeaderText",
    title = "Depositer", subtitle = "Items stashed to depot lockers at the end of a hunt.",
  })

  DataTable.create(content, {
    id = "depositerItems", title = "Stash list", rows = rows(shell, depositer, items),
    rowKey = function(row) return row.id end,
    searchable = #items > 4,
    searchText = function(row) return row.title end,
    emptyMessage = "No stash items configured. Add the first item below.",
  })

  Components.sectionHeader(content, { id = "depositerAdd", title = "Add item" })
  local draft = { id = "", index = "3" }
  Components.inputRow(content, {
    id = "depositerItemId", label = "Item ID", value = draft.id,
    onChange = function(value) draft.id = value end,
  })
  Components.inputRow(content, {
    id = "depositerIndex", label = "Stash to depot (3-17)", value = draft.index,
    onChange = function(value) draft.index = value end,
  })
  local feedback = Components.label(content, { id = "depositerFeedback", text = "", textStyle = "helper" })
  Components.button(content, {
    id = "addDepositerItem", text = "Add item",
    onClick = function()
      local id = tonumber(draft.id)
      local index = tonumber(draft.index)
      if not id or id <= 0 then
        feedback:setText("Enter a valid positive item ID.")
        return
      end
      if not index or index < 3 or index > 17 then
        feedback:setText("Depot must be between 3 and 17.")
        return
      end
      if not depositer.addItem(id, index) then
        feedback:setText("That item is already on the stash list.")
        return
      end
      draft.id = ""
      feedback:setText("")
      rerender(shell)
    end,
  })
end

nExBot.UI.ModuleRegistry.register({
  id = "depositer", label = "Depositer", order = 84,
  render = DepositerPage.render,
})
nExBot.UI.DepositerPage = DepositerPage
nExBot.UI["ui.modules.depositer"] = DepositerPage

return DepositerPage
