--[[
  Intelligence module page — Tactical Intelligence summary, sections.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Page = (nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]) or (type(require) == "function" and require("ui.modules.page"))

local Intelligence = {}

local SECTIONS = {
  "Overview", "Live Decisions", "Monsters", "Hunt Performance",
  "Learning", "Navigation Intelligence", "Resources", "Replay", "Diagnostics",
}

function Intelligence.viewModel(state)
  state = state or {}
  local vm = VM.new("intelligence")
  local mode = state.mode or "off"

  vm:setState("READY")
  vm:setHeader({
    module = "intelligence",
    title = "Intelligence",
    status = mode ~= "off" and "ACTIVE" or "DISABLED",
    statusText = mode ~= "off" and ("Mode: " .. mode) or "off",
  })

  local sections = {}

  sections[#sections + 1] = {
    id = "overview",
    title = "Overview",
    rows = {
      { key = "Mode", value = mode },
      { key = "State", value = state.state or "idle" },
      { key = "Events", value = state.eventCount or 0 },
    },
  }

  sections[#sections + 1] = {
    id = "monsters",
    title = "Monsters",
    rows = {
      { key = "Tracked", value = state.monsterCount or 0 },
      { key = "Insights", value = state.insightCount or 0 },
    },
  }

  sections[#sections + 1] = {
    id = "hunt",
    title = "Hunt Performance",
    rows = {
      { key = "XP/h", value = state.xpHour or 0 },
      { key = "Hunt score", value = state.huntScore or "-" },
    },
  }

  sections[#sections + 1] = {
    id = "learning",
    title = "Learning",
    rows = {
      { key = "Models", value = state.modelCount or 0 },
      { key = "Samples", value = state.sampleCount or 0 },
      { key = "Promoted", value = state.promotedCount or 0 },
    },
  }

  sections[#sections + 1] = {
    id = "diagnostics",
    title = "Diagnostics",
    rows = {
      { key = "Issues", value = state.issueCount or 0, status = state.issueCount and state.issueCount > 0 and "WARNING" or "OK" },
    },
  }

  vm:setSections(sections)
  vm:setActions({
    { id = "open_dashboard", label = "Open dashboard" },
    { id = "export_replay", label = "Export replay" },
    { id = "clear_replay", label = "Clear replay" },
  })

  if state.issueCount and state.issueCount > 0 then
    for _, issue in ipairs(state.issues or {}) do
      vm:addError(issue.code or "INTELLIGENCE_ISSUE", issue.message or "")
    end
  end
  vm:commit()
  return vm
end

function Intelligence.statusProvider()
  local TI = nExBot and nExBot.TacticalIntelligence
  local view = TI and TI.view and TI.view({ width = 800, platform = "desktop", touch = false }) or {}
  return Intelligence.viewModel({
    mode = TI and TI.getMode and TI.getMode() or "off",
    state = view.state or "idle",
    eventCount = view.overview and view.overview.eventCount or nil,
    monsterCount = view.monsters and view.monsters.summary and view.monsters.summary.count or nil,
    insightCount = view.monsters and view.monsters.insightCount or nil,
    xpHour = view.hunt and view.hunt.summary and view.hunt.summary.xpPerHour or nil,
    huntScore = view.hunt and view.hunt.summary and view.hunt.summary.score or nil,
    modelCount = view.models and view.models.summary and view.models.summary.total or nil,
    sampleCount = view.models and view.models.summary and view.models.summary.samples or nil,
    promotedCount = view.models and view.models.summary and view.models.summary.promoted or nil,
    issueCount = view.diagnostics and view.diagnostics.issueCount or 0,
    issues = view.diagnostics and view.diagnostics.issues or {},
  })
end

function Intelligence.render(shell, content, lifecycle)
  Page.render(shell, content, lifecycle, Intelligence.statusProvider().snapshot)
end

function Intelligence.register()
  local Registry = nExBot.UI.ModuleRegistry
  return Registry.register({
    id = "intelligence",
    label = "Intelligence",
    icon = "intelligence",
    order = 80,
    sections = SECTIONS,
    statusProvider = Intelligence.statusProvider,
    render = Intelligence.render,
  })
end

local reg = nExBot.UI.ModuleRegistry
if reg and reg.register then Intelligence.register() end

return Intelligence
