-- Pure single-level undo stack for the waypoint editor. No g_ui dependency.
-- A snapshot is {kind = "delete" | "reorder", items = {{action, value, index}, ...}}.
local History = {}
History.__index = History

function History.new()
  return setmetatable({_snapshot = nil}, History)
end

function History:push(snapshot)
  self._snapshot = snapshot
end

-- Consumes and returns the pending snapshot, or nil if there is none.
function History:undo()
  local snapshot = self._snapshot
  self._snapshot = nil
  return snapshot
end

function History:clear()
  self._snapshot = nil
end

if nExBot then
  nExBot.Nav = nExBot.Nav or {}
  nExBot.Nav["cavebot.editor_history"] = History
end

return History
