--[[
  Actions — maps module action ids to real domain calls.

  Widgets never mutate domain globals directly; they dispatch through typed
  action handlers. This module centralizes the nil-safe bridges from UI action
  ids to the existing domain globals (CaveBot, TargetBot, HealBot, Supplies,
  Tactical Intelligence windows, etc.). Every handler is pcall-guarded and
  returns nothing (fire-and-forget UI intent).
]]

local Actions = {}

-- Resolve a dotted path from the environment. OTClient's sandbox has no `_G`,
-- so prefer _G when present, then _ENV (5.2+), then getfenv (5.1/LuaJIT).
local function env()
  if _G ~= nil then return _G end
  if _ENV ~= nil then return _ENV end
  if getfenv then return getfenv(2) end
  return nil
end

local function get(...)
  local v = env()
  for i = 1, select("#", ...) do
    v = v and v[select(i, ...)]
  end
  return v
end

local function invoke(fn, ...)
  if type(fn) == "function" then
    pcall(fn, ...)
  end
end

local function toggle(moduleName)
  local M = get(moduleName)
  if not M then return end
  if M.isOn and M.isOn() then
    invoke(M.setOff)
  elseif M.isOff and M.isOff() then
    invoke(M.setOn)
  elseif M.setOn then
    invoke(M.setOn)
  end
end

Actions.handlers = {
  toggle_cavebot = function() toggle("CaveBot") end,
  toggle_targetbot = function() toggle("TargetBot") end,
  toggle_healing = function() toggle("HealBot") end,
  toggle_looting = function()
    local T = get("TargetBot")
    if T and T.setLootingEnabled then invoke(T.setLootingEnabled, not (T.isLootingEnabled and T.isLootingEnabled() or false)) end
  end,

  open_looting = function()
    local s = get("nExBot", "UI", "Shell")
    if s and s.select then s.select("looting") end
  end,
  open_script_editor = function()
    local E = get("IngameEditor")
    if E and E.show then invoke(E.show) end
  end,

  open_cavebot = function()
    local s = get("nExBot", "UI", "Shell")
    if s and s.select then s.select("cavebot") end
  end,
  open_targetbot = function()
    local s = get("nExBot", "UI", "Shell")
    if s and s.select then s.select("targetbot") end
  end,
  open_supplies = function()
    local s = get("nExBot", "UI", "Shell")
    if s and s.select then s.select("supplies") end
  end,
  open_intelligence = function()
    local s = get("nExBot", "UI", "Shell")
    if s and s.select then s.select("intelligence") end
  end,
  open_editor = function()
    local T = get("TargetBot")
    if T and T.showCreatureEditor then invoke(T.showCreatureEditor) end
    local C = get("CaveBot")
    if C and C.Editor and C.Editor.show then invoke(C.Editor.show) end
  end,
  open_config = function()
    local H = get("HealBot")
    if H and H.show then invoke(H.show) end
    local S = get("Supplies")
    if S and S.show then invoke(S.show) end
  end,
  open_conditions = function()
    local C = get("Conditions")
    if C and C.show then invoke(C.show) end
  end,
  open_containers = function()
    local C = get("Containers")
    if C and C.showSetup then invoke(C.showSetup) end
  end,
  open_depositor = function()
    local D = get("DepositerConfig")
    if D and D.show then invoke(D.show) end
  end,
  open_macros = function()
    local T = get("Tools")
    if T and T.showMacros then invoke(T.showMacros) end
  end,
  open_dashboard = function()
    local s = get("nExBot", "UI", "Shell")
    if s and s.select then s.select("intelligence") end
  end,
  run_doctor = function()
    local D = get("IntelligenceBotDoctor")
    if D and D.runNow then invoke(D.runNow) end
  end,
  export_diagnostics = function()
    local R = get("nExBot", "TacticalIntelligence")
    if R and R.exportDiagnostics then invoke(R.exportDiagnostics) end
  end,
  export_replay = function()
    local R = get("nExBot", "TacticalIntelligence")
    if R and R.exportReplay then invoke(R.exportReplay) end
  end,
  clear_replay = function()
    local R = get("nExBot", "TacticalIntelligence")
    if R and R.clearReplay then invoke(R.clearReplay) end
  end,
  save_profile = function()
    local P = get("ProfileStorage")
    if P and P.save then invoke(P.save) end
  end,
  import = function()
    local S = get("nExBot", "UI", "Shell")
    if S and S.instance then
      local shell = S.instance()
      if shell and shell.select then shell:select("profiles") end
    end
  end,
  export = function()
    local U = get("UnifiedStorage")
    if U and U.backup then invoke(U.backup) end
  end,
  open_script_editor = function()
    local E = get("IngameEditor")
    if E and E.show then invoke(E.show) end
  end,
}

function Actions.run(id)
  local handler = Actions.handlers[id]
  if handler then handler() end
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.Actions = Actions
  nExBot.UI["ui.core.actions"] = Actions
end

return Actions
