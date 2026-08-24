--[[
  Settings module page — UI, theme, density, global bot defaults.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Page = (nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]) or (type(require) == "function" and require("ui.modules.page"))
local Density = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.density"]) or (type(require) == "function" and require("ui.design_system.density"))

local Settings = {}

local SECTIONS = {
  "UI", "Theme", "Density", "Global Defaults", "Hotkeys", "Storage",
  "Compatibility",
}

function Settings.viewModel(state)
  state = state or {}
  local vm = VM.new("settings")

  vm:setState("READY")
  vm:setHeader({ module = "settings", title = "Settings", status = "INFO", statusText = "nExBot" })

  local sections = {}

  sections[#sections + 1] = {
    id = "ui",
    title = "UI",
    rows = {
      { key = "Density", value = state.density or "default" },
      { key = "UI scale", value = state.uiScale or "1.00x" },
      { key = "Theme", value = state.theme or "dark" },
    },
  }

  sections[#sections + 1] = {
    id = "compatibility",
    title = "Compatibility",
    rows = {
      { key = "Client", value = state.clientName or "unknown" },
      { key = "Version", value = state.version or "-" },
    },
  }

  vm:setSections(sections)
  vm:setActions({})
  vm:commit()
  return vm
end

function Settings.statusProvider()
  return Settings.viewModel({
    density = nExBot and nExBot.UI and nExBot.UI.Shell and nExBot.UI.Shell.instance and nExBot.UI.Shell.instance() and nExBot.UI.Shell.instance():density() or "default",
    uiScale = storage and storage.uiScale or "1.00x",
    theme = "dark",
    clientName = nExBot and nExBot.clientName or "unknown",
    version = nExBot and nExBot.version or "-",
  })
end

function Settings.render(shell, content, lifecycle)
  Page.render(shell, content, lifecycle, Settings.statusProvider().snapshot)
end

function Settings.register()
  local Registry = nExBot.UI.ModuleRegistry
  return Registry.register({
    id = "settings",
    label = "Settings",
    order = 100,
    sections = SECTIONS,
    statusProvider = Settings.statusProvider,
    render = Settings.render,
  })
end

local reg = nExBot.UI.ModuleRegistry
if reg and reg.register then Settings.register() end

return Settings
