--[[
  Scripts module page — script manager, macros, hotkeys, execution status.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Page = (nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]) or (type(require) == "function" and require("ui.modules.page"))

local Scripts = {}

local SECTIONS = { "Scripts", "Macros", "Hotkeys", "Private Scripts", "Runtime" }

function Scripts.viewModel(state)
  state = state or {}
  local vm = VM.new("scripts")

  vm:setState(state.error and "ERROR" or "READY")
  vm:setHeader({
    module = "scripts",
    title = "Scripts",
    status = state.error and "ERROR" or "INFO",
    statusText = state.error and "Script error" or "OK",
  })

  local sections = {}

  sections[#sections + 1] = {
    id = "runtime",
    title = "Runtime",
    rows = {
      { key = "Scripts", value = tostring(#(state.scripts or {})) },
      { key = "Enabled", value = tostring(state.enabledCount or 0) },
      { key = "Errors", value = tostring(state.errorCount or 0), status = state.errorCount and state.errorCount > 0 and "ERROR" or "OK" },
    },
  }

  for _, script in ipairs(state.scripts or {}) do
    sections[#sections + 1] = {
      id = "script_" .. tostring(script.name),
      title = script.name or "script",
      rows = {
        { key = "Enabled", value = script.enabled and "yes" or "no", status = script.enabled and "ACTIVE" or "DISABLED" },
        { key = "Status", value = script.status or "idle", status = script.status or nil },
      },
    }
  end

  vm:setSections(sections)
  vm:setActions({
    { id = "open_script_editor", label = "Open script editor" },
    { id = "open_macros", label = "Macros" },
  })

  if state.error then vm:addError("SCRIPT_ERROR", state.error) end
  vm:commit()
  return vm
end

function Scripts.statusProvider()
  local storage = storage
  local scripts = {}
  if BotDB and BotDB.getMacros then
    for _, m in ipairs(BotDB.getMacros() or {}) do
      scripts[#scripts + 1] = { name = m.name or m, enabled = m.enabled or false, status = "idle" }
    end
  end
  return Scripts.viewModel({
    scripts = scripts,
    enabledCount = (function()
      local n = 0
      for _, s in ipairs(scripts) do if s.enabled then n = n + 1 end end
      return n
    end)(),
    errorCount = nExBot and nExBot.loadErrors and (function()
      local n = 0
      for _ in pairs(nExBot.loadErrors) do n = n + 1 end
      return n
    end)() or 0,
  })
end

function Scripts.render(shell, content, lifecycle)
  Page.render(shell, content, lifecycle, Scripts.statusProvider().snapshot)
end

function Scripts.register()
  local Registry = nExBot.UI.ModuleRegistry
  return Registry.register({
    id = "scripts",
    label = "Scripts",
    icon = "scripts",
    order = 70,
    sections = SECTIONS,
    statusProvider = Scripts.statusProvider,
    render = Scripts.render,
  })
end

local reg = nExBot.UI.ModuleRegistry
if reg and reg.register then Scripts.register() end

return Scripts
