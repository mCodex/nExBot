--[[
  Status — consistent status semantics across every module.

  One canonical meaning per status name, mapped to a token color. Modules must
  not invent their own status colors.
]]

local Tokens = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.tokens"]) or (type(require) == "function" and require("ui.design_system.tokens"))
local Colors = Tokens.colors

local map = {
  OK       = Colors.success,
  ACTIVE   = Colors.success,
  RUNNING  = Colors.success,
  PAUSED   = Colors.paused,
  WARNING  = Colors.warning,
  DEGRADED = Colors.degraded,
  ERROR    = Colors.danger,
  DANGER   = Colors.danger,
  DISABLED = Colors.disabled,
  INFO     = Colors.info,
}

local Status = {}

function Status.color(name, fallback)
  local color = map[name or ""]
  if not color then return fallback or Colors.text.muted end
  return color
end

Status.map = map

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.Status = Status
end

return Status
