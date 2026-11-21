--[[
  UiLifecycle — generation-token session guard for UI lifecycle ownership.

  Every delayed callback / event handler created for a UI session must verify
  the session generation before touching widgets, so stale callbacks from a
  destroyed or recreated shell can never write to dead widgets.
]]

local Lifecycle = {}
Lifecycle.__index = Lifecycle

function Lifecycle.new(id)
  return setmetatable({
    id = id or "session",
    generation = 1,
  }, Lifecycle)
end

function Lifecycle:advance()
  self.generation = self.generation + 1
  return self.generation
end

function Lifecycle:current()
  return self.generation
end

function Lifecycle:isCurrent(gen)
  return gen == self.generation
end

function Lifecycle:stale(gen)
  return gen ~= self.generation
end

-- Returns a callback that runs `fn` only if the captured generation is still
-- current. Capture the generation at creation time, not at call time.
function Lifecycle:guard(fn, generation)
  assert(type(fn) == "function", "guard requires a function")
  local gen = generation or self.generation
  return function(...)
    if self:stale(gen) then return nil end
    return fn(...)
  end
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI["ui.core.lifecycle"] = Lifecycle
end

return Lifecycle
