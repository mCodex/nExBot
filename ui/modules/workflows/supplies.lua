-- Supplies workflow controls: profile, item table with editor, and refill conditions.

local Components = nExBot and nExBot.UI and nExBot.UI["ui.components.components"]
local DataTable = nExBot and nExBot.UI and nExBot.UI.DataTable
local Resolver = nExBot and nExBot.UI and nExBot.UI.VisualAssetResolver
local Shared = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.shared"]

local SuppliesPage = {}
local selectedSupplyId

function SuppliesPage.render(content, shell)
  if not Supplies then
    Components.emptyState(content, { message = "Supplies did not load. Check the startup log." })
    return
  end

  Components.sectionHeader(content, { title = "Profile" })
  Shared.profileSelect(content, {
    id = "supplyProfile",
    items = Supplies.listProfiles and Supplies.listProfiles() or {},
    value = Supplies.getCurrentProfile and Supplies.getCurrentProfile(),
    onChange = function(name)
      if Supplies.setCurrentProfile then Supplies.setCurrentProfile(name) end
      Shared.rerender(shell)
    end,
  })
  Shared.newProfileAction(content, {
    id = "newSupplyProfile", text = "New Profile", shell = shell,
    onCreate = function()
      if not Supplies.createProfile then return false, "Not available" end
      return Supplies.createProfile()
    end,
  })

  local items = Supplies.getItemsData and Supplies.getItemsData() or {}
  local ids = {}
  for id in pairs(items) do ids[#ids + 1] = tostring(id) end
  table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
  if not DataTable or not Resolver then
    Components.sectionHeader(content, { title = "Items" })
    if #ids == 0 then Components.emptyState(content, { message = "No supply items configured." }) end
    for _, id in ipairs(ids) do
      local values = items[id] or items[tonumber(id)]
      Components.itemRow(content, { id = "supplyItem_" .. id, itemId = id, title = "Item " .. id,
        subtitle = string.format("Min %s  Max %s  Avg %s", values.min or 0, values.max or 0, values.avg or 0) })
    end
  else
  local supplyRows = {}
  for _, id in ipairs(ids) do
    local values = items[id] or items[tonumber(id)]
    local visual = Resolver:item(id)
    supplyRows[#supplyRows + 1] = {
      id = id, itemId = id, title = visual.name,
      secondary = string.format("Min %s / Max %s / Avg %s", values.min or 0, values.max or 0, values.avg or 0),
      status = selectedSupplyId == id and "ACTIVE" or "INFO",
      statusText = selectedSupplyId == id and "Selected" or "Configured",
      onClick = function() selectedSupplyId = id; Shared.rerender(shell) end,
      actions = { { id = "removeSupply_" .. id, text = "Remove", variant = "danger", tooltip = "Remove item", onClick = function() Supplies.removeItem(id); selectedSupplyId = nil; Shared.rerender(shell) end } },
    }
  end
  DataTable.create(content, {
    id = "supplyItems", title = "Items", rows = supplyRows,
    rowKey = function(row) return row.id end, searchable = #supplyRows > 4,
    emptyMessage = "No supply items configured.",
  })

  local selected = selectedSupplyId and (items[selectedSupplyId] or items[tonumber(selectedSupplyId)])
  if selected then
    Components.sectionHeader(content, { title = "Edit selected item" })
    local draft = { min = selected.min or 0, max = selected.max or 0, avg = selected.avg or 0 }
    for _, field in ipairs({ "min", "max", "avg" }) do
      local key = field
      Components.inputRow(content, {
        id = "supply_" .. selectedSupplyId .. "_" .. key, label = key:upper(), value = draft[key],
        onChange = function(text)
          local number = tonumber(text)
          if not number then return end
          draft[key] = number
          Supplies.setItem(selectedSupplyId, draft.min, draft.max, draft.avg)
        end,
      })
    end
  end
  end

  local newItem = { id = "", min = "0", max = "0", avg = "0" }
  for _, field in ipairs({ "id", "min", "max", "avg" }) do
    local key = field
    Components.inputRow(content, {
      id = "newSupply_" .. key,
      label = key:upper(),
      value = newItem[key],
      onChange = function(text) newItem[key] = text end,
    })
  end
  Components.button(content, {
    id = "addSupply",
    text = "Add item",
    tooltip = "Add the item to this supplies profile",
    onClick = function()
      if Supplies.setItem(newItem.id, newItem.min, newItem.max, newItem.avg) then
        Shared.rerender(shell)
      end
    end,
  })

  local additional = Supplies.getAdditionalData and Supplies.getAdditionalData() or {}
  Components.sectionHeader(content, { title = "Refill conditions" })
  for _, condition in ipairs({
    { "softBoots", "No soft boots" },
    { "imbues", "No imbues" },
    { "capacity", "Low capacity" },
    { "stamina", "Low stamina" },
  }) do
    local key, label = condition[1], condition[2]
    local current = additional[key] or {}
    Components.toggleRow(content, {
      id = "supplyCondition_" .. key,
      label = label,
      value = current.enabled,
      onChange = function(enabled) Supplies.setCondition(key, enabled, current.value) end,
    })
    if current.value ~= nil then
      Components.inputRow(content, {
        id = "supplyConditionValue_" .. key,
        label = "Value",
        value = current.value,
        onChange = function(value) Supplies.setCondition(key, current.enabled, value) end,
      })
    end
  end
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI["ui.modules.workflows.supplies"] = SuppliesPage
end

return SuppliesPage
