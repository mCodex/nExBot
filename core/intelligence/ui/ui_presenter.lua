IntelligenceUiPresenter = {}
local Presenter = IntelligenceUiPresenter
Presenter.__index = Presenter

local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, item in pairs(value) do
    result[key] = item
  end
  return result
end

function Presenter.layout(viewport)
  viewport = viewport or {}
  local width = tonumber(viewport.width) or 0
  local touch = viewport.touch == true or viewport.platform == "mobile"
  if touch or width < 600 then
    return { mode = "single", columns = 1, touch = true }
  end
  if width < 900 then
    return { mode = "compact", columns = 1, touch = false }
  end
  return { mode = "wide", columns = 2, touch = false }
end

function Presenter.new(options)
  options = options or {}
  assert(type(options.state) == "table", "shared UI state is required")
  return setmetatable({
    state = options.state,
    commands = options.commands or {},
    nowMs = options.nowMs or function()
      return os.clock() * 1000
    end,
    refreshMs = math.max(0, tonumber(options.refreshMs) or 100),
    active = true,
  }, Presenter)
end

function Presenter:view(viewport)
  if not self.active then
    self.error = "terminated"
    return false
  end

  local now = self.nowMs()
  viewport = viewport or {}
  local viewportKey = table.concat({
    tostring(viewport.width or 0),
    tostring(viewport.platform),
    tostring(viewport.touch),
  }, ":")

  if self.cached and self.viewportKey == viewportKey and now - self.refreshedAt < self.refreshMs then
    return self.cached
  end

  local state = self.state or {}
  local result = copy(state)
  result.layout = Presenter.layout(viewport)

  self.cached = result
  self.refreshedAt = now
  self.viewportKey = viewportKey
  return result
end

function Presenter:execute(name, args, confirmed)
  if not self.active then
    self.error = "terminated"
    return false
  end

  local command = self.commands[name]
  if not command then
    self.error = "unknown_command"
    return false
  end
  if type(command) == "function" then
    local result = command(args or {})
    self.error = result == false and "command_failed" or nil
    return result ~= false
  end
  if command.destructive and confirmed ~= true then
    self.error = "confirmation_required"
    return false
  end
  local result = command.run and command.run(args or {})
  if result == false then
    self.error = "command_failed"
    return false
  end
  self.error = nil
  return true
end

function Presenter:lastError()
  return self.error
end

function Presenter:terminate()
  if not self.active then
    return false
  end
  self.active = false
  self.cached = nil
  self.state = nil
  self.commands = {}
  return true
end

return Presenter
