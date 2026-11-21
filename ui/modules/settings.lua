--[[
  Settings module page — UI, theme, density, global bot defaults.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Page = (nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]) or (type(require) == "function" and require("ui.modules.page"))
local Settings = {}

local Components = (nExBot and nExBot.UI and nExBot.UI["ui.components.components"]) or (type(require) == "function" and require("ui.components.components"))

local SECTIONS = { "Interface" }

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
  })
end

function Settings.render(shell, content, lifecycle)
  Page.render(shell, content, lifecycle, Settings.statusProvider().snapshot)
  Components.selectRow(content, {
    id = "uiDensity", label = "Density",
    options = { "compact", "default", "comfortable", "touch" },
    value = shell and shell.density and shell:density() or "default",
    onChange = function(first, second)
      local value = type(second) == "string" and second or type(first) == "string" and first
      if value and shell and shell.setDensity then shell:setDensity(value) end
    end,
  })
  Components.label(content, {
    text = "Client compatibility and runtime tuning are detected automatically.",
    textStyle = "helper",
  })
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
