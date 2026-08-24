--[[
  Supplies module page — thresholds, refills, consumables, alerts.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Page = (nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]) or (type(require) == "function" and require("ui.modules.page"))

local Supplies = {}

local SECTIONS = {
  "Thresholds", "Refills", "Consumables", "Alerts", "Budgets",
  "Route Integration", "Diagnostics",
}

function Supplies.viewModel(state)
  state = state or {}
  local vm = VM.new("supplies")

  vm:setState("READY")
  vm:setHeader({ module = "supplies", title = "Supplies", status = "INFO", statusText = state.profile or "default" })

  local sections = {}

  sections[#sections + 1] = {
    id = "overview",
    title = "Overview",
    rows = {
      { key = "Profile", value = state.profile or "-" },
      { key = "Capacity", value = tostring(state.capacity or "-") },
      { key = "Stamina", value = state.stamina and (state.stamina .. " h") or "-" },
      { key = "Soft boots", value = state.softBoots and "on" or "off", status = state.softBoots and "ACTIVE" or "DISABLED" },
    },
  }

  sections[#sections + 1] = {
    id = "items",
    title = "Supply Items",
    items = {},
  }
  for _, item in ipairs(state.items or {}) do
    sections[#sections + 1] = {
      id = "supply_" .. tostring(item.id),
      title = item.name or ("Item " .. tostring(item.id)),
      rows = {
        { key = "Min", value = tostring(item.min or 0) },
        { key = "Max", value = tostring(item.max or 0) },
        { key = "Avg", value = tostring(item.avg or 0) },
      },
    }
  end

  sections[#sections + 1] = {
    id = "diagnostics",
    title = "Diagnostics",
    rows = { { key = "Errors", value = state.errorCount or 0, status = state.errorCount and state.errorCount > 0 and "WARNING" or "OK" } },
  }

  vm:setSections(sections)
  vm:setActions({ { id = "open_config", label = "Supply settings" } })

  if state.errorCount and state.errorCount > 0 then vm:addError("SUPPLIES_ERRORS", state.errorCount .. " errors") end
  vm:commit()
  return vm
end

function Supplies.statusProvider()
  local S = Supplies
  return Supplies.viewModel({
    profile = S and S.getCurrentProfile and S.getCurrentProfile() or "-",
    capacity = S and S.getCapacity and S.getCapacity() or nil,
    stamina = S and S.getStamina and S.getStamina() or nil,
    softBoots = S and S.areSoftBootsEnabled and S.areSoftBootsEnabled() or false,
    items = S and S.getItemsData and S.getItemsData() or {},
  })
end

function Supplies.render(shell, content, lifecycle)
  Page.render(shell, content, lifecycle, Supplies.statusProvider().snapshot)
end

function Supplies.register()
  local Registry = nExBot.UI.ModuleRegistry
  return Registry.register({
    id = "supplies",
    label = "Supplies",
    icon = "supplies",
    order = 60,
    sections = SECTIONS,
    statusProvider = Supplies.statusProvider,
    render = Supplies.render,
  })
end

local reg = nExBot.UI.ModuleRegistry
if reg and reg.register then Supplies.register() end

return Supplies
