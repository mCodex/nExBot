--[[
  Looting module page — loot lists, containers, corpse behavior.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Page = (nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]) or (type(require) == "function" and require("ui.modules.page"))

local Looting = {}

local SECTIONS = {
  "Loot List", "Corpse", "Containers", "Item Movement", "Sorting",
  "Nested Backpacks", "Diagnostics",
}

function Looting.viewModel(state)
  state = state or {}
  local vm = VM.new("looting")
  local enabled = state.enabled == true

  vm:setState("READY")
  vm:setHeader({
    module = "looting",
    title = "Looting",
    status = enabled and "ACTIVE" or "DISABLED",
    statusText = enabled and "Enabled" or "Disabled",
  })

  local sections = {}

  sections[#sections + 1] = {
    id = "overview",
    title = "Overview",
    rows = {
      { key = "Loot every item", value = state.everyItem and "yes" or "no" },
      { key = "Eat from corpses", value = state.eatFromCorpses and "yes" or "no" },
      { key = "Max danger", value = state.maxDanger or "-" },
      { key = "Min capacity", value = state.minCapacity or "-" },
    },
  }

  sections[#sections + 1] = {
    id = "loot",
    title = "Loot Items",
    items = {},
  }
  for _, item in ipairs(state.lootItems or {}) do
    sections[#sections + 1] = {
      id = "loot_" .. tostring(item.id),
      title = item.name or ("Item " .. tostring(item.id)),
      rows = { { key = "Count", value = item.count or item.amount or "-" } },
    }
  end

  sections[#sections + 1] = {
    id = "containers",
    title = "Containers",
    rows = { { key = "Loot destinations", value = tostring(#(state.containers or {})) } },
  }

  sections[#sections + 1] = {
    id = "diagnostics",
    title = "Diagnostics",
    rows = {
      { key = "Corpse queue", value = state.corpseQueue or 0 },
      { key = "Errors", value = state.errorCount or 0, status = state.errorCount and state.errorCount > 0 and "WARNING" or "OK" },
    },
  }

  vm:setSections(sections)
  vm:setActions({
    { id = "toggle_looting", label = enabled and "Disable" or "Enable" },
    { id = "open_containers", label = "Containers" },
    { id = "open_depositor", label = "Depositor" },
  })

  if state.errorCount and state.errorCount > 0 then vm:addError("LOOTING_ERRORS", state.errorCount .. " errors") end
  vm:commit()
  return vm
end

function Looting.statusProvider()
  local L = TargetBot and TargetBot.Looting
  return Looting.viewModel({
    enabled = TargetBot and TargetBot.isLootingEnabled and TargetBot.isLootingEnabled() or false,
    everyItem = L and L.isEveryItemEnabled and L.isEveryItemEnabled() or false,
    eatFromCorpses = TargetBot and TargetBot.EatFood and TargetBot.EatFood.isEnabled and TargetBot.EatFood.isEnabled() or false,
    maxDanger = L and L.getMaxDanger and L.getMaxDanger() or nil,
    minCapacity = L and L.getMinCapacity and L.getMinCapacity() or nil,
    lootItems = L and L.getItems and L.getItems() or {},
    containers = L and L.getContainers and L.getContainers() or {},
    corpseQueue = L and L.getQueueLength and L.getQueueLength() or 0,
  })
end

function Looting.render(shell, content, lifecycle)
  Page.render(shell, content, lifecycle, Looting.statusProvider().snapshot)
end

function Looting.register()
  local Registry = nExBot.UI.ModuleRegistry
  return Registry.register({
    id = "looting",
    label = "Looting",
    icon = "looting",
    order = 50,
    sections = SECTIONS,
    statusProvider = Looting.statusProvider,
    render = Looting.render,
  })
end

local reg = nExBot.UI.ModuleRegistry
if reg and reg.register then Looting.register() end

return Looting
