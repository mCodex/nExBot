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
  if type(fn) ~= "function" then return false, "Action unavailable" end
  local ok, err = pcall(fn, ...)
  if not ok then return false, tostring(err) end
  return true
end

local function toggle(moduleName)
  local M = get(moduleName)
  if not M then return false, "Action unavailable" end
  if M.isOn and M.isOn() then
    return invoke(M.setOff)
  elseif M.isOff and M.isOff() then
    return invoke(M.setOn)
  elseif M.setOn then
    return invoke(M.setOn)
  end
  return false, "Action unavailable"
end

local function navigate(pageId)
  local shell = get("nExBot", "UI", "Shell")
  return invoke(shell and shell.select, pageId)
end

Actions.handlers = {
  toggle_cavebot = function() return toggle("CaveBot") end,
  toggle_targetbot = function() return toggle("TargetBot") end,
  toggle_healing = function() return toggle("HealBot") end,
  toggle_looting = function()
    local T = get("TargetBot")
    if not T or not T.setLootingEnabled then return false, "Action unavailable" end
    return invoke(T.setLootingEnabled, not (T.isLootingEnabled and T.isLootingEnabled() or false))
  end,

  pause_all = function()
    local stopped = false
    for _, moduleName in ipairs({ "CaveBot", "TargetBot", "HealBot" }) do
      local M = get(moduleName)
      if M and M.setOff then
        local ok = invoke(M.setOff)
        stopped = ok or stopped
      end
    end
    local T = get("TargetBot")
    if T and T.setLootingEnabled then
      local ok = invoke(T.setLootingEnabled, false)
      stopped = ok or stopped
    end
    if not stopped then return false, "Hunt engines unavailable" end
    return true
  end,

  open_cave_editor = function()
    local E = get("CaveBot", "Editor")
    return invoke(E and E.show)
  end,
  open_target_editor = function()
    local T = get("TargetBot")
    return invoke(T and T.showCreatureEditor)
  end,
  open_heal_config = function()
    local H = get("HealBot")
    return invoke(H and H.show)
  end,
  open_loot_config = function()
    local C = get("Containers")
    return invoke(C and C.initSetupWindow)
  end,
  open_supply_config = function()
    local S = get("Supplies")
    return invoke(S and S.show)
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
  open_intelligence_window = function()
    local I = get("nExBot", "TacticalIntelligence")
    return invoke(I and I.showWindow)
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
    return invoke(E and E.show)
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
