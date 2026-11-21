-- Loot workflow controls: preferences plus item/container tables and editor.

local Components = nExBot and nExBot.UI and nExBot.UI["ui.components.components"]
local DataTable = nExBot and nExBot.UI and nExBot.UI.DataTable
local Resolver = nExBot and nExBot.UI and nExBot.UI.VisualAssetResolver
local Shared = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.shared"]

local LootingPage = {}
local selectedLootEntry

function LootingPage.render(content, shell)
  local looting = TargetBot and TargetBot.Looting
  if not looting or not looting.getConfig or not DataTable or not Resolver then return end
  local config = looting.getConfig()
  Components.toggleRow(content, { label = "Loot every item", value = config.everyItem, onChange = function(value) looting.setPreference("everyItem", value) end })
  Components.toggleRow(content, { label = "Eat corpse food", value = config.eatFromCorpses, onChange = function(value) looting.setPreference("eatFromCorpses", value) end })

  local function collectionRows(collection, kind)
    local rows = {}
    for _, entry in ipairs(collection or {}) do
      local id = tonumber(type(entry) == "table" and entry.id or entry)
      if id then
        local visual = Resolver:item(id)
        rows[#rows + 1] = {
          id = kind .. "_" .. id, itemId = id, title = visual.name,
          secondary = kind == "item" and "Loot item" or "Loot container",
          status = "INFO", statusText = "Configured",
          actions = {
            { id = "editLoot_" .. kind .. "_" .. id, text = "Edit", onClick = function()
              selectedLootEntry = { id = id, kind = kind }
              Shared.rerender(shell)
            end },
            { id = "removeLoot_" .. kind .. "_" .. id, text = "Remove", variant = "danger", onClick = function()
              if kind == "item" then looting.removeItem(id) else looting.removeContainer(id) end
              if selectedLootEntry and selectedLootEntry.id == id and selectedLootEntry.kind == kind then
                selectedLootEntry = nil
              end
              Shared.rerender(shell)
            end },
          },
        }
      end
    end
    return rows
  end

  local lootItems = collectionRows(config.items, "item")
  local lootContainers = collectionRows(config.containers, "container")
  DataTable.create(content, { id = "lootItems", title = "Loot items", rows = lootItems, searchable = #lootItems > 4, rowKey = function(row) return row.id end, emptyMessage = "No loot items configured." })
  DataTable.create(content, { id = "lootContainers", title = "Containers", rows = lootContainers, searchable = #lootContainers > 4, rowKey = function(row) return row.id end, emptyMessage = "No loot containers configured." })

  local selected = selectedLootEntry
  local draft = { id = selected and tostring(selected.id) or "", kind = selected and selected.kind or "item" }
  Components.sectionHeader(content, { title = selected and "Edit selected item" or "Add item" })
  local input = Components.inputRow(content, { label = "Item ID", value = draft.id, onChange = function(value) draft.id = value end })
  Components.selectRow(content, {
    label = "Type", value = draft.kind == "item" and "Loot item" or "Container",
    options = { { text = "Loot item", value = "item" }, { text = "Container", value = "container" } },
    onChange = function(_, value) if value then draft.kind = value end end,
  })
  local feedback = Components.label(content, { id = "lootFeedback", text = "", textStyle = "helper" })
  Components.button(content, { id = selected and "saveLootItem" or "addLootItem", text = selected and "Save changes" or "Add item", onClick = function()
    local id = tonumber(draft.id ~= "" and draft.id or input:getInput():getText())
    local ok
    if selected then
      ok = looting.updateEntry(selected.id, selected.kind, id, draft.kind)
    elseif draft.kind == "item" then
      ok = looting.addItem(id)
    else
      ok = looting.addContainer(id)
    end
    if not ok then
      feedback:setText("Enter a valid item ID that is not already configured.")
      return
    end
    selectedLootEntry = nil
    Shared.rerender(shell)
  end })
  if selected then
    Components.button(content, {
      id = "cancelLootEdit", text = "Cancel", variant = "ghost",
      onClick = function() selectedLootEntry = nil; Shared.rerender(shell) end,
    })
    Components.button(content, {
      id = "deleteLootItem", text = "Delete", variant = "danger",
      onClick = function()
        local ok
        if selected.kind == "item" then
          ok = looting.removeItem(selected.id)
        else
          ok = looting.removeContainer(selected.id)
        end
        if ok then selectedLootEntry = nil; Shared.rerender(shell) end
      end,
    })
  end
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI["ui.modules.workflows.looting"] = LootingPage
end

return LootingPage
