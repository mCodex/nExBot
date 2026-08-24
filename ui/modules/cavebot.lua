--[[
  CaveBot module page — routes, waypoints, recorder, navigation/recovery.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Page = (nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]) or (type(require) == "function" and require("ui.modules.page"))

local CaveBot = {}

local SECTIONS = {
  "Routes", "Waypoints", "Auto Recorder", "Navigation",
  "Recovery", "Obstacles", "Advanced", "Diagnostics",
}

function CaveBot.viewModel(state)
  state = state or {}
  local vm = VM.new("cavebot")
  local enabled = state.enabled == true

  vm:setState(state.state or (enabled and "READY" or "READY"))
  vm:setHeader({
    module = "cavebot",
    title = "CaveBot",
    status = enabled and "ACTIVE" or "DISABLED",
    statusText = enabled and "Running" or "Stopped",
  })

  local sections = {}

  sections[#sections + 1] = {
    id = "routes",
    title = "Route",
    rows = {
      { key = "Config", value = state.config or "-" },
      { key = "Status", value = state.status or "off" },
    },
  }

  sections[#sections + 1] = {
    id = "waypoints",
    title = "Waypoints",
    items = {},
  }
  for _, wp in ipairs(state.waypoints or {}) do
    sections[#sections + 1] = {
      id = "waypoint_" .. tostring(wp.index or #(sections)),
      title = wp.label or ("WP" .. tostring(wp.index or "?")),
      rows = { { key = "Action", value = wp.action or "-" }, { key = "Position", value = wp.pos or "-" } },
    }
  end

  sections[#sections + 1] = {
    id = "recorder",
    title = "Auto Recorder",
    rows = { { key = "Recording", value = state.recording and "yes" or "no", status = state.recording and "ACTIVE" or "DISABLED" } },
  }

  sections[#sections + 1] = {
    id = "navigation",
    title = "Navigation",
    rows = {
      { key = "Last label", value = state.lastLabel or "-" },
      { key = "Recovery", value = state.recovering and "active" or "idle", status = state.recovering and "WARNING" or "OK" },
      { key = "Stuck waypoints", value = state.stuckCount or 0 },
    },
  }

  sections[#sections + 1] = {
    id = "diagnostics",
    title = "Diagnostics",
    rows = {
      { key = "Waypoint count", value = #(state.waypoints or {}) },
      { key = "Errors", value = state.errorCount or 0, status = state.errorCount and state.errorCount > 0 and "WARNING" or "OK" },
    },
  }

  vm:setSections(sections)
  vm:setActions({
    { id = "toggle_cavebot", label = enabled and "Stop" or "Start" },
    { id = "open_editor", label = "Edit" },
    { id = "open_config", label = "Config" },
  })

  if state.errorCount and state.errorCount > 0 then vm:addError("CAVEBOT_ERRORS", state.errorCount .. " errors") end
  vm:commit()
  return vm
end

function CaveBot.statusProvider()
  local storage = storage
  local get = function(k) return storage and storage[k] end
  return CaveBot.viewModel({
    enabled = CaveBot and CaveBot.isOn and CaveBot.isOn() or false,
    config = get("cavebot") and get("cavebot").selectedConfig or nil,
    status = CaveBot and CaveBot.getStatus and CaveBot.getStatus() or "off",
    lastLabel = nExBot and nExBot.lastLabel,
    waypoints = CaveBot and CaveBot.List and CaveBot.List() or {},
    recording = CaveBot and CaveBot.Recorder and CaveBot.Recorder.isEnabled and CaveBot.Recorder.isEnabled() or false,
    recovering = CaveBot and CaveBot.isRecovering and CaveBot.isRecovering() or false,
    stuckCount = WaypointEngine and WaypointEngine.getStuckCount and WaypointEngine.getStuckCount() or 0,
  })
end

function CaveBot.render(shell, content, lifecycle)
  Page.render(shell, content, lifecycle, CaveBot.statusProvider().snapshot)
end

function CaveBot.register()
  local Registry = nExBot.UI.ModuleRegistry
  return Registry.register({
    id = "cavebot",
    label = "CaveBot",
    icon = "cavebot",
    order = 20,
    sections = SECTIONS,
    statusProvider = CaveBot.statusProvider,
    render = CaveBot.render,
  })
end

local reg = nExBot.UI.ModuleRegistry
if reg and reg.register then CaveBot.register() end

return CaveBot
