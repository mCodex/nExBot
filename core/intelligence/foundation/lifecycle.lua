IntelligenceLifecycle = {}
IntelligenceLifecycle.__index = IntelligenceLifecycle

function IntelligenceLifecycle.new(options)
  options = options or {}
  return setmetatable({
    active = false,
    register = options.register or function() end,
    generations = { lifecycle = 0, snapshot = 0, route = 0, combat = 0 },
  }, IntelligenceLifecycle)
end

function IntelligenceLifecycle:initialize()
  if self.active then return false end
  self.active = true
  self.generations.lifecycle = self.generations.lifecycle + 1
  self.unregister = self.register()
  return true
end

function IntelligenceLifecycle:terminate()
  if not self.active then return false end
  self.active = false
  for name, value in pairs(self.generations) do self.generations[name] = value + 1 end
  if self.unregister then self.unregister(); self.unregister = nil end
  return true
end

function IntelligenceLifecycle:generation(name)
  assert(self.generations[name] ~= nil, "unknown generation: " .. tostring(name))
  return self.generations[name]
end

function IntelligenceLifecycle:advance(name)
  local value = self:generation(name) + 1
  self.generations[name] = value
  return value
end

function IntelligenceLifecycle:guard(name, callback)
  local generation = self:generation(name)
  return function(...)
    if not self.active or generation ~= self.generations[name] then return nil end
    callback(...)
    return generation
  end
end

return IntelligenceLifecycle
