--[[
  Diagnostics module page — Bot Doctor, warnings, errors, subscriptions,
  performance, replay export.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Page = (nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]) or (type(require) == "function" and require("ui.modules.page"))

local Diagnostics = {}
local ISSUE_CACHE_MS = 5000
local issueCache = { value = {} }

local SECTIONS = {
  "Bot Doctor", "Warnings", "Recent Errors", "Module Health",
  "Persistence", "Subscriptions", "Performance", "Replay Export",
}

function Diagnostics.viewModel(state)
  state = state or {}
  local vm = VM.new("diagnostics")
  local issueCount = state.issueCount or 0

  vm:setState(issueCount > 0 and "DEGRADED" or "READY")
  vm:setHeader({
    module = "diagnostics",
    title = "Diagnostics",
    status = issueCount > 0 and "WARNING" or "OK",
    statusText = issueCount > 0 and (issueCount .. " issues") or "All systems nominal",
  })

  local sections = {}

  sections[#sections + 1] = {
    id = "doctor",
    title = "Bot Doctor",
    items = {},
  }
  for _, issue in ipairs(state.issues or {}) do
    sections[#sections + 1] = {
      id = "issue_" .. tostring(issue.code),
      title = tostring(issue.code or "issue"),
      rows = {
        { key = "Subsystem", value = issue.subsystem or "-" },
        { key = "Severity", value = issue.severity or "info", status = issue.severity or "INFO" },
        { key = "Message", value = issue.message or "" },
        { key = "Action", value = issue.action or "-" },
        { key = "Timestamp", value = issue.timestamp or "-" },
      },
    }
  end

  sections[#sections + 1] = {
    id = "subscriptions",
    title = "Subscriptions",
    rows = {
      { key = "UnifiedTick handlers", value = state.tickHandlers or 0 },
      { key = "EventBus listeners", value = state.listenerCount or 0 },
    },
  }

  sections[#sections + 1] = {
    id = "performance",
    title = "Performance",
    rows = {
      { key = "UI p95", value = state.uiP95 and (state.uiP95 .. " ms") or "-" },
      { key = "UI p99", value = state.uiP99 and (state.uiP99 .. " ms") or "-" },
      { key = "Slow ticks", value = state.slowTickCount or 0 },
    },
  }

  sections[#sections + 1] = {
    id = "persistence",
    title = "Persistence",
    rows = {
      { key = "Schema version", value = state.schemaVersion or "-" },
      { key = "Backups", value = state.backupCount or 0 },
    },
  }

  vm:setSections(sections)
  vm:setActions({
    { id = "run_doctor", label = "Run Bot Doctor" },
    { id = "export_diagnostics", label = "Export diagnostics" },
    { id = "export_replay", label = "Export replay" },
  })

  for _, issue in ipairs(state.issues or {}) do
    vm:addError(issue.code or "DIAGNOSTIC", issue.message or "")
  end
  vm:commit()
  return vm
end

local function nowMs()
  if nExBot and nExBot.Shared and nExBot.Shared.nowMs then
    return nExBot.Shared.nowMs()
  end
  return math.floor(os.clock() * 1000)
end

function Diagnostics.currentIssues(force)
  local now = nowMs()
  if not force and issueCache.at and now - issueCache.at < ISSUE_CACHE_MS then
    return issueCache.value
  end

  local issues = {}
  local Doctor = IntelligenceBotDoctor or (nExBot and nExBot.BotDoctor)
  if Doctor and Doctor.inspect then
    local runtime = nExBot and nExBot.TacticalIntelligence and nExBot.TacticalIntelligence.runtime
    if not runtime and Doctor.capture then
      runtime = Doctor.capture(nExBot and nExBot.Intelligence)
    end
    local ok, result = pcall(Doctor.inspect, runtime)
    if ok and type(result) == "table" then
      for _, issue in ipairs(result) do
        issues[#issues + 1] = {
          code = issue.code,
          subsystem = issue.subsystem,
          severity = issue.severity,
          message = issue.message,
          action = issue.action,
        }
      end
    end
  end
  issueCache.at = now
  issueCache.value = issues
  return issues
end

function Diagnostics.refreshIssues()
  return Diagnostics.currentIssues(true)
end

function Diagnostics.statusProvider()
  local issues = Diagnostics.currentIssues()
  local ut = UnifiedTick
  local eb = EventBus
  return Diagnostics.viewModel({
    issues = issues,
    issueCount = #issues,
    tickHandlers = ut and ut.getDiagnostics and ut.getDiagnostics().registered or 0,
    listenerCount = eb and eb.listenerCount and eb.listenerCount() or 0,
    uiP95 = nExBot and nExBot.UI and nExBot.UI.Perf and nExBot.UI.Perf.p95 and nExBot.UI.Perf.p95() or nil,
    uiP99 = nExBot and nExBot.UI and nExBot.UI.Perf and nExBot.UI.Perf.p99 and nExBot.UI.Perf.p99() or nil,
    schemaVersion = UnifiedStorage and UnifiedStorage.getSchemaVersion and UnifiedStorage.getSchemaVersion() or nil,
    backupCount = UnifiedStorage and UnifiedStorage.getStats and UnifiedStorage.getStats().backupCount or 0,
  })
end

function Diagnostics.render(shell, content, lifecycle)
  Page.render(shell, content, lifecycle, Diagnostics.statusProvider().snapshot)
end

function Diagnostics.register()
  local Registry = nExBot.UI.ModuleRegistry
  return Registry.register({
    id = "diagnostics",
    label = "Diagnostics",
    order = 110,
    sections = SECTIONS,
    statusProvider = Diagnostics.statusProvider,
    render = Diagnostics.render,
  })
end

local reg = nExBot.UI.ModuleRegistry
if reg and reg.register then Diagnostics.register() end

return Diagnostics
