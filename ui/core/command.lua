--[[
  CommandDispatcher — explicit, typed command dispatch for UI actions.

  Widgets never mutate domain globals directly. They call
  dispatcher:execute(name, args, confirmed) and receive a typed result:
    { ok = true, data = ... }
    { ok = false, error = "CODE" }

  Commands validate prerequisites before running. Destructive commands require
  explicit confirmation. Exceptions are contained and reported as COMMAND_ERROR.
]]

local Dispatcher = {}
Dispatcher.__index = Dispatcher

function Dispatcher.new()
  return setmetatable({ commands = {} }, Dispatcher)
end

function Dispatcher:register(name, spec)
  assert(type(name) == "string" and name ~= "", "command name required")
  assert(type(spec) == "table", "command spec required")
  assert(type(spec.run) == "function", "command run handler required")
  self.commands[name] = {
    prerequisite = spec.prerequisite,
    destructive = spec.destructive == true,
    run = spec.run,
  }
  return self
end

local function okResult(data)
  return { ok = true, data = data }
end

local function failResult(error, detail)
  return { ok = false, error = error, detail = detail }
end

function Dispatcher:execute(name, args, confirmed)
  local spec = self.commands[name]
  if not spec then return failResult("UNKNOWN_COMMAND") end

  if spec.prerequisite then
    local pass, reason = spec.prerequisite(args or {})
    if pass == false then return failResult(reason or "PREREQUISITE_FAILED") end
  end

  if spec.destructive and confirmed ~= true then
    return failResult("CONFIRMATION_REQUIRED")
  end

  local callOk, res, resDetail = pcall(spec.run, args or {})
  if not callOk then return failResult("COMMAND_ERROR", res) end
  if res == false then return failResult(resDetail or "COMMAND_FAILED") end
  if type(res) ~= "table" or res.ok == nil then return failResult("BAD_RESULT") end
  if res.ok == false then return failResult(res.error or "COMMAND_FAILED", res.detail) end
  return res
end

function Dispatcher:list()
  local out = {}
  for name in pairs(self.commands) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

return Dispatcher
