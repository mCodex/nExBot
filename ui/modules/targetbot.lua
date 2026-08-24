--[[
  TargetBot module page — creatures, priorities, tactics, live decisions.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Page = (nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]) or (type(require) == "function" and require("ui.modules.page"))

local TargetBot = {}

local SECTIONS = {
  "Creatures", "Priorities", "Strategy", "Lure", "Dynamic Lure",
  "Pull", "Reposition", "Wave Avoidance", "Keep Distance", "Advanced",
  "Live Decisions", "Diagnostics",
}

function TargetBot.viewModel(state)
  state = state or {}
  local vm = VM.new("targetbot")
  local enabled = state.enabled == true

  vm:setState("READY")
  vm:setHeader({
    module = "targetbot",
    title = "TargetBot",
    status = enabled and "ACTIVE" or "DISABLED",
    statusText = enabled and "Hunting" or "Stopped",
  })

  local sections = {}

  sections[#sections + 1] = {
    id = "target",
    title = "Live Target",
    rows = {
      { key = "Target", value = state.currentTarget or "-" },
      { key = "Combat state", value = state.combatState or "-" },
      { key = "Movement owner", value = state.movementOwner or "-" },
    },
  }

  sections[#sections + 1] = {
    id = "creatures",
    title = "Creatures",
    items = {},
  }
  for _, c in ipairs(state.creatures or {}) do
    sections[#sections + 1] = {
      id = "creature_" .. tostring(c.name),
      title = c.name or "?",
      rows = {
        { key = "Priority", value = tostring(c.priority or 0) },
        { key = "Status", value = c.status or "idle", status = c.status or nil },
      },
    }
  end

  sections[#sections + 1] = {
    id = "tactics",
    title = "Tactics",
    rows = {
      { key = "Lure", value = state.lure and "on" or "off", status = state.lure and "ACTIVE" or "DISABLED" },
      { key = "Dynamic Lure", value = state.dynamicLure and "on" or "off", status = state.dynamicLure and "ACTIVE" or "DISABLED" },
      { key = "Pull", value = state.pull and "on" or "off", status = state.pull and "ACTIVE" or "DISABLED" },
      { key = "Reposition", value = state.reposition and "on" or "off", status = state.reposition and "ACTIVE" or "DISABLED" },
      { key = "Wave avoidance", value = state.waveAvoidance and "on" or "off", status = state.waveAvoidance and "ACTIVE" or "DISABLED" },
      { key = "Keep distance", value = state.keepDistance and "on" or "off", status = state.keepDistance and "ACTIVE" or "DISABLED" },
    },
  }

  sections[#sections + 1] = {
    id = "diagnostics",
    title = "Diagnostics",
    rows = {
      { key = "Targetable monsters", value = state.targetableCount or 0 },
      { key = "Errors", value = state.errorCount or 0, status = state.errorCount and state.errorCount > 0 and "WARNING" or "OK" },
    },
  }

  vm:setSections(sections)
  vm:setActions({
    { id = "toggle_targetbot", label = enabled and "Stop" or "Start" },
    { id = "open_editor", label = "Creature editor" },
    { id = "open_looting", label = "Looting" },
  })

  if state.errorCount and state.errorCount > 0 then vm:addError("TARGETBOT_ERRORS", state.errorCount .. " errors") end
  vm:commit()
  return vm
end

function TargetBot.statusProvider()
  local storage = storage
  local get = function(k) return storage and storage[k] end
  local creatures = {}
  if TargetBot and TargetBot.getConfigs then
    for _, cfg in ipairs(TargetBot.getConfigs() or {}) do
      creatures[#creatures + 1] = { name = cfg.name, priority = cfg.priority, status = "idle" }
    end
  end
  return TargetBot.viewModel({
    enabled = TargetBot and TargetBot.isOn and TargetBot.isOn() or false,
    currentTarget = TargetBot and TargetBot.getCurrentTarget and TargetBot.getCurrentTarget() or "-",
    combatState = AttackFSM and AttackFSM.getState and AttackFSM.getState() or "-",
    movementOwner = MovementCoordinator and MovementCoordinator.getOwner and MovementCoordinator.getOwner() or "-",
    creatures = creatures,
    lure = TargetBot and TargetBot.canLure and TargetBot.canLure() or false,
    dynamicLure = TargetBot and TargetBot.isDynamicLureEnabled and TargetBot.isDynamicLureEnabled() or false,
    pull = TargetBot and TargetBot.isPullEnabled and TargetBot.isPullEnabled() or false,
    reposition = TargetBot and TargetBot.isRepositionEnabled and TargetBot.isRepositionEnabled() or false,
    waveAvoidance = TargetBot and TargetBot.isWaveAvoidanceEnabled and TargetBot.isWaveAvoidanceEnabled() or false,
    keepDistance = TargetBot and TargetBot.isKeepDistanceEnabled and TargetBot.isKeepDistanceEnabled() or false,
    targetableCount = TargetBot and TargetBot.getTargetableMonsterCount and TargetBot.getTargetableMonsterCount() or 0,
  })
end

function TargetBot.render(shell, content, lifecycle)
  Page.render(shell, content, lifecycle, TargetBot.statusProvider().snapshot)
end

function TargetBot.register()
  local Registry = nExBot.UI.ModuleRegistry
  return Registry.register({
    id = "targetbot",
    label = "TargetBot",
    icon = "targetbot",
    order = 30,
    sections = SECTIONS,
    statusProvider = TargetBot.statusProvider,
    render = TargetBot.render,
  })
end

local reg = nExBot.UI.ModuleRegistry
if reg and reg.register then TargetBot.register() end

return TargetBot
