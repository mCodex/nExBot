--[[
  Dashboard — session summary module.

  Builds a bounded view model from session state and renders it through shared
  components. It deliberately does NOT load replay/model/monster data; it shows
  only high-value aggregate state.

  viewModel(state) is pure and testable. state is produced by the statusProvider
  from domain globals (nil-safe) or injected directly in tests.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Components = (nExBot and nExBot.UI and nExBot.UI["ui.components.components"]) or (type(require) == "function" and require("ui.components.components"))
local Tokens = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.tokens"]) or (type(require) == "function" and require("ui.design_system.tokens"))
local Status = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.status"]) or (type(require) == "function" and require("ui.design_system.status"))
local Actions = (nExBot and nExBot.UI and nExBot.UI["ui.core.actions"]) or (type(require) == "function" and require("ui.core.actions"))

local Dashboard = {}

local ACTION_DEFS = {
  { id = "toggle_cavebot", label = "CaveBot" },
  { id = "toggle_targetbot", label = "TargetBot" },
  { id = "open_cavebot", label = "Open CaveBot" },
  { id = "open_targetbot", label = "Open TargetBot" },
  { id = "open_supplies", label = "Open Supplies" },
  { id = "open_intelligence", label = "Open Intelligence" },
}

function Dashboard.viewModel(state)
  state = state or {}
  local vm = VM.new("dashboard")
  local issues = state.issues or {}

  local active = {
    cavebot = state.cavebotOn == true,
    targetbot = state.targetbotOn == true,
    healbot = state.healbotOn == true,
    attackbot = state.attackbotOn == true,
    supplies = state.suppliesOn == true,
    intelligence = state.intelligenceMode or "off",
  }

  vm:setState(#issues > 0 and "DEGRADED" or "READY")
  vm:setHeader({
    module = "dashboard",
    character = state.character or "-",
    profile = state.profile or "-",
    session = state.session or "DISCONNECTED",
    sessionStatus = state.session or "INFO",
    activeModules = active,
  })

  local sections = {}

  sections[#sections + 1] = {
    id = "session",
    title = "Session",
    rows = {
      { key = "Character", value = state.character or "-" },
      { key = "Profile", value = state.profile or "-" },
      { key = "Status", value = state.session or "DISCONNECTED", status = state.session or "INFO" },
      { key = "XP", value = state.xp or 0 },
      { key = "XP/h", value = state.xpHour or 0 },
      { key = "Kills", value = state.kills or 0 },
    },
  }

  sections[#sections + 1] = {
    id = "movement",
    title = "Movement",
    rows = {
      { key = "CaveBot", value = state.cavebotRoute and (state.cavebotRoute .. (state.cavebotWaypoint and " · " .. state.cavebotWaypoint or "")) or "off", status = state.cavebotOn and "ACTIVE" or "DISABLED" },
      { key = "Current target", value = state.currentTarget or "-" },
      { key = "Movement owner", value = state.movementOwner or "-" },
      { key = "Combat state", value = state.combatState or "-" },
    },
  }

  sections[#sections + 1] = {
    id = "resources",
    title = "Resources",
    rows = {
      { key = "HP", value = state.hp and (state.hp .. "%") or "-" },
      { key = "Mana", value = state.mana and (state.mana .. "%") or "-" },
      { key = "Supplies warning", value = state.supplyWarning or "none", status = state.supplyWarning and "WARNING" or nil },
    },
  }

  sections[#sections + 1] = {
    id = "intelligence",
    title = "Intelligence",
    rows = {
      { key = "Mode", value = state.intelligenceMode or "off" },
      { key = "Diagnostics", value = state.diagnosticCount or 0, status = state.diagnosticCount and state.diagnosticCount > 0 and "WARNING" or nil },
    },
  }

  if #issues > 0 then
    sections[#sections + 1] = {
      id = "issues",
      title = "Attention needed",
      rows = {},
    }
    for _, issue in ipairs(issues) do
      sections[#sections + 1] = {
        id = "issue_" .. tostring(issue.code),
        title = tostring(issue.code or "issue"),
        rows = { { key = issue.subsystem or "bot", value = issue.message or "" } },
      }
    end
  end

  vm:setSections(sections)

  local actions = {}
  for _, def in ipairs(ACTION_DEFS) do
    actions[#actions + 1] = {
      id = def.id,
      label = def.label,
      enabled = true,
    }
  end
  vm:setActions(actions)

  vm:commit()
  return vm
end

-- statusProvider reads domain globals nil-safely; called on each tick.
function Dashboard.statusProvider()
  local player = player
  local storage = storage
  local get = function(k) return storage and storage[k] end

  return Dashboard.viewModel({
    cavebotOn = CaveBot and CaveBot.isOn and CaveBot.isOn() or false,
    targetbotOn = TargetBot and TargetBot.isOn and TargetBot.isOn() or false,
    healbotOn = HealBot and HealBot.isOn and HealBot.isOn() or false,
    attackbotOn = AttackBot and AttackBot.isOn and AttackBot.isOn() or false,
    suppliesOn = Supplies and Supplies.isEnabled and Supplies.isEnabled() or false,
    character = player and player.getName and player.getName() or "-",
    profile = get("profileName") or "-",
    session = nExBot and nExBot.isOnline and nExBot.isOnline() and "ONLINE" or "DISCONNECTED",
    xp = nExBot and nExBot.CaveBotData and nExBot.CaveBotData.xp or nil,
    xpHour = nExBot and nExBot.CaveBotData and nExBot.CaveBotData.xpPerHour or nil,
    kills = KillTracker and KillTracker.getCount and KillTracker.getCount() or nil,
    cavebotRoute = get("cavebot") and get("cavebot").selectedConfig,
    cavebotWaypoint = nExBot and nExBot.lastLabel,
    movementOwner = MovementCoordinator and MovementCoordinator.getOwner and MovementCoordinator.getOwner() or "-",
    combatState = AttackFSM and AttackFSM.getState and AttackFSM.getState() or "-",
    currentTarget = TargetBot and TargetBot.getCurrentTarget and TargetBot.getCurrentTarget() or "-",
    intelligenceMode = nExBot and nExBot.TacticalIntelligence and nExBot.TacticalIntelligence.getMode and nExBot.TacticalIntelligence.getMode() or "off",
    issues = nExBot and nExBot.UI and nExBot.UI.Diagnostics and nExBot.UI.Diagnostics.currentIssues and nExBot.UI.Diagnostics.currentIssues() or {},
  })
end

function Dashboard.render(shell, content, lifecycle)
  local view = Dashboard.statusProvider().snapshot
  if not lifecycle or not lifecycle:isCurrent(lifecycle:current()) then return end

  Components.label(content, view.header.character .. " — " .. view.header.profile, { id = "title", textStyle = "moduleTitle", color = Tokens.colors.text.primary })

  local stateBadge = Components.statusBadge(content, {
    id = "sessionBadge",
    status = view.header.sessionStatus,
    text = view.header.session,
  })
  stateBadge:setColor(Status.color(view.header.sessionStatus))

  -- quick actions
  local actionsPanel = g_ui.createWidget("NexToolbar", content)
  actionsPanel:setId("quickActions")
  for _, action in ipairs(view.actions) do
    if action.label then
      Components.button(actionsPanel, {
        text = action.label,
        id = action.id,
        onClick = function() Actions.run(action.id) end,
      })
    end
  end

  for _, section in ipairs(view.sections) do
    Components.sectionHeader(content, { title = section.title })
    local card = Components.card(content, { title = section.title })
    for _, row in ipairs(section.rows or {}) do
      Components.keyValueRow(card, { key = row.key, value = row.value })
    end
  end

  if #view.errors > 0 then
    Components.inlineWarning(content, { message = view.errors[1].message })
  end
end

function Dashboard.register()
  local Registry = nExBot.UI.ModuleRegistry
  return Registry.register({
    id = "dashboard",
    label = "Dashboard",
    icon = "dashboard",
    order = 10,
    sections = { "Session", "Movement", "Resources", "Intelligence" },
    statusProvider = Dashboard.statusProvider,
    render = Dashboard.render,
  })
end

-- auto-register at load time (self-registration pattern for OTClient dofile)
local reg = nExBot.UI.ModuleRegistry
if reg and reg.register then Dashboard.register() end

return Dashboard
