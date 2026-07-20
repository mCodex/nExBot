local ClientLifecycle = {}
ClientLifecycle.__index = ClientLifecycle

local EventBus = EventBus

function ClientLifecycle.new()
  local self = setmetatable({}, ClientLifecycle)
  self.listeners = {}
  self.initialized = false
  return self
end

function ClientLifecycle:initialize()
  if self.initialized then return end
  self.initialized = true

  if onGameStart then
    onGameStart(function()
      self:emit("gameStart")
    end)
  end

  if onGameEnd then
    onGameEnd(function()
      self:emit("gameEnd")
    end)
  end

  if EventBus then
    EventBus.on("player:login", function()
      self:emit("login")
    end)
    EventBus.on("player:logout", function()
      self:emit("logout")
    end)
    EventBus.on("player:z_change_settled", function()
      self:emit("gameStart")
    end)
  end
end

function ClientLifecycle:on(event, callback)
  self.listeners[event] = self.listeners[event] or {}
  table.insert(self.listeners[event], callback)
  return function()
    for i, cb in ipairs(self.listeners[event] or {}) do
      if cb == callback then
        table.remove(self.listeners[event], i)
        break
      end
    end
  end
end

function ClientLifecycle:emit(event, ...)
  for _, cb in ipairs(self.listeners[event] or {}) do
    pcall(cb, ...)
  end
end

nExBot = nExBot or {}
nExBot.ClientLifecycle = ClientLifecycle.new()
nExBot.ClientLifecycle:initialize()

return ClientLifecycle