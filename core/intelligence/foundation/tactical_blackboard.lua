TacticalBlackboard = {}
TacticalBlackboard.__index = TacticalBlackboard
local nowMs = nExBot and nExBot.Shared and nExBot.Shared.nowMs or function() return os.time() * 1000 end

function TacticalBlackboard.new(options)
  options = options or {}
  return setmetatable({
    now = options.now or nowMs,
    keys = options.keys or {},
    facts = {},
    generations = { lifecycle = 0, snapshot = 0, route = 0, combat = 0 },
  }, TacticalBlackboard)
end

function TacticalBlackboard:setGenerations(generations)
  for name, value in pairs(generations) do
    assert(self.generations[name] ~= nil, "unknown generation: " .. tostring(name))
    self.generations[name] = value
  end
end

function TacticalBlackboard:write(key, value, metadata)
  local declaration = self.keys[key]
  if not declaration then return nil, "unknown_key" end
  metadata = metadata or {}
  if metadata.owner ~= declaration.owner then return nil, "wrong_owner" end
  if declaration.validate and not declaration.validate(value) then return nil, "invalid_value" end
  local generations = {}
  for _, name in ipairs({ "lifecycle", "snapshot", "route", "combat" }) do
    local value = metadata[name .. "Generation"] or self.generations[name]
    if value < self.generations[name] then return nil, "stale_" .. name .. "_generation" end
    generations[name] = value
  end
  self.facts[key] = {
    value = value,
    generations = generations,
    expiresAt = metadata.ttl and self.now() + metadata.ttl or metadata.expiresAt,
  }
  return true
end

function TacticalBlackboard:read(key)
  local fact = self.facts[key]
  if not fact then return nil end
  if fact.expiresAt and self.now() >= fact.expiresAt then self.facts[key] = nil; return nil end
  for name, value in pairs(fact.generations) do
    if value < self.generations[name] then self.facts[key] = nil; return nil end
  end
  return fact and fact.value or nil
end

return TacticalBlackboard
