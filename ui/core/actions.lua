--[[
  Actions — maps module action ids to real domain calls.

  Widgets never mutate domain globals directly; they dispatch through typed
  action handlers. This module centralizes the nil-safe bridges from UI action
  ids to the existing domain globals (CaveBot, TargetBot, HealBot, Supplies,
  Tactical Intelligence windows, etc.). Every handler is pcall-guarded and
  returns nothing (fire-and-forget UI intent).
]]

local Actions = {}

local USER_FAILURES = {
  open_cavebot = "Cave page unavailable",
  open_targetbot = "Target page unavailable",
  open_healing = "Heal page unavailable",
  open_looting = "Loot page unavailable",
  open_attack_config = "Attack settings unavailable",
  toggle_cavebot = "Cave unavailable",
  toggle_targetbot = "Target unavailable",
  toggle_healing = "Heal unavailable",
  pause_all = "Could not pause hunt",
}

function Actions.userMessage(actionId, reason)
  local message = tostring(reason or "Action unavailable")
  if message == "Action unavailable" or message == "Action failed"
    or message:find("[string", 1, true) or message:find("/ui/", 1, true) or message:find(".lua:", 1, true) then
    return USER_FAILURES[actionId] or "Action unavailable"
  end
  return message
end

local function invoke(fn, ...)
  if type(fn) ~= "function" then return false, "Action unavailable" end
  local ok, err = pcall(fn, ...)
  if not ok then return false, tostring(err) end
  return true
end

local function toggle(module)
  if not module then return false, "Action unavailable" end
  if module.isOn and module.isOn() then
    return invoke(module.setOff)
  elseif module.isOff and module.isOff() then
    return invoke(module.setOn, true, true)
  elseif module.setOn then
    return invoke(module.setOn, true, true)
  end
  return false, "Action unavailable"
end

local function navigate(pageId)
  local ShellModule = nExBot and nExBot.UI and nExBot.UI.Shell
  local shell = ShellModule and ShellModule.instance and ShellModule.instance()
  if not shell or not shell.select then return false, "Action unavailable" end
  return invoke(function() return shell:select(pageId) end)
end

local function toggleEnabled(module)
  if not module or not module.isEnabled or not module.setEnabled then return false, "Action unavailable" end
  local ok, enabled = pcall(module.isEnabled)
  if not ok then return false, tostring(enabled) end
  return invoke(module.setEnabled, not enabled)
end

Actions.handlers = {
  toggle_cavebot = function() return toggle(CaveBot) end,
  toggle_targetbot = function() return toggle(TargetBot) end,
  toggle_healing = function() return toggle(HealBot) end,

  pause_all = function()
    local stopped = false
    local modules = {}
    if CaveBot then modules[#modules + 1] = CaveBot end
    if TargetBot then modules[#modules + 1] = TargetBot end
    if HealBot then modules[#modules + 1] = HealBot end
    for _, M in ipairs(modules) do
      if M and M.setOff then
        local ok = invoke(M.setOff)
        stopped = ok or stopped
      end
    end
    if not stopped then return false, "Hunt engines unavailable" end
    return true
  end,

  open_looting = function()
    return navigate("looting")
  end,
  open_cavebot = function()
    return navigate("cavebot")
  end,
  open_targetbot = function()
    return navigate("targetbot")
  end,
  open_healing = function()
    return navigate("healing")
  end,
  run_doctor = function()
    local D = IntelligenceBotDoctor
    if D and D.runNow then invoke(D.runNow) end
  end,
  export_diagnostics = function()
    local R = nExBot and nExBot.TacticalIntelligence
    if R and R.exportDiagnostics then invoke(R.exportDiagnostics) end
  end,
  export_replay = function()
    local R = nExBot and nExBot.TacticalIntelligence
    if R and R.exportReplay then invoke(R.exportReplay) end
  end,
  save_profile = function()
    local P = ProfileStorage
    if P and P.save then invoke(P.save) end
  end,
  import = function()
    local S = nExBot and nExBot.UI and nExBot.UI.Shell
    if S and S.instance then
      local shell = S.instance()
      if shell and shell.select then shell:select("profiles") end
    end
  end,
  export = function()
    local U = UnifiedStorage
    if U and U.backup then invoke(U.backup) end
  end,
  open_script_editor = function()
    local E = IngameEditor
    return invoke(E and E.show)
  end,
  open_friend_healer = function() return invoke(HealBot and HealBot.showAlly) end,
  open_containers = function() return invoke(Containers and Containers.initSetupWindow) end,
  cave_force_refill = function()
    local C = CaveBot and CaveBot.Control
    return invoke(C and C.forceRefill)
  end,
  cave_back_stop = function()
    local C = CaveBot and CaveBot.Control
    return invoke(C and C.backStop)
  end,
  cave_back_trainers = function()
    local C = CaveBot and CaveBot.Control
    return invoke(C and C.backTrainers)
  end,
  cave_back_offline = function()
    local C = CaveBot and CaveBot.Control
    return invoke(C and C.backOffline)
  end,
  toggle_alarms = function() return toggle(Alarms) end,
  toggle_conditions = function() return toggle(Conditions) end,
  toggle_antirs = function() return toggle(AntiRs) end,
  toggle_pushmax = function() return toggle(PushMax) end,
  toggle_combo = function() return toggle(ComboBot) end,
  open_alarms = function() return invoke(Alarms and Alarms.show) end,
  show_conditions = function() return invoke(Conditions and Conditions.show) end,
  open_pushmax = function() return invoke(PushMax and PushMax.show) end,
  open_combo = function() return invoke(ComboBot and ComboBot.show) end,
  open_equipper = function() return invoke(nExBot and nExBot.Equipper and nExBot.Equipper.show) end,
  toggle_equipper = function() return toggleEnabled(nExBot and nExBot.Equipper) end,
  open_attack_config = function() return invoke(AttackBot and AttackBot.show) end,
  toggle_attack = function() return toggle(AttackBot) end,
  toggle_dropper = function() return toggleEnabled(nExBot and nExBot.Dropper) end,
  toggle_depot_withdraw = function() return toggleEnabled(nExBot and nExBot.DepotWithdraw) end,
  toggle_hold_target = function() return toggleEnabled(nExBot and nExBot.HoldTarget) end,
  toggle_spy_level = function() return toggleEnabled(nExBot and nExBot.SpyLevel) end,
  open_extras = function() return invoke(nExBot and nExBot.Extras and nExBot.Extras.showWindow) end,
  open_depositer = function() return invoke(nExBot and nExBot.Depositer and nExBot.Depositer.showWindow) end,
  open_analyzer = function() return invoke(Analyzer and Analyzer.showWindow) end,
  toggle_quiver = function()
    local db = BotDB
    if not db or not db.getMacroState or not db.setMacroState then return false, "Action unavailable" end
    local ok, enabled = pcall(db.getMacroState, "quiverManager")
    if not ok then return false, tostring(enabled) end
    return invoke(db.setMacroState, "quiverManager", not enabled)
  end,
}

function Actions.run(id)
  local handler = Actions.handlers[id]
  if not handler then return false, "Action unavailable" end
  local ok, result, reason = pcall(handler)
  if not ok then return false, tostring(result) end
  if result == false then return false, reason or "Action failed" end
  return true
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.Actions = Actions
  nExBot.UI["ui.core.actions"] = Actions
end

return Actions
