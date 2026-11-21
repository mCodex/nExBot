--[[
  ViewModel — versioned, immutable snapshot builder for module presenters.

  Every module exposes one versioned snapshot:
    { schemaVersion, revision, moduleId, generatedAt, state, header,
      sections, actions, errors }

  State transitions are deterministic; revisions only advance through commit().
  Once committed, the snapshot is frozen (decoupled from the builder) so
  presenters render a stable read model.
]]

local VM = {}
VM.__index = VM

local VALID_STATES = { LOADING = true, EMPTY = true, READY = true, DEGRADED = true, ERROR = true }
local SCHEMA_VERSION = 1

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do
    out[k] = deepCopy(v)
  end
  return out
end

local function nowMs()
  if nExBot and nExBot.nowMs then return nExBot.nowMs() end
  return 0
end

function VM.new(moduleId)
  assert(type(moduleId) == "string" and moduleId ~= "", "moduleId is required")
  return setmetatable({
    schemaVersion = SCHEMA_VERSION,
    revision = 0,
    moduleId = moduleId,
    state = "LOADING",
    header = {},
    sections = {},
    actions = {},
    errors = {},
    snapshot = nil,
  }, VM)
end

function VM:setState(state)
  if not VALID_STATES[state] then return false end
  self.state = state
  return true
end

function VM:setHeader(header)
  if type(header) ~= "table" then return false end
  self.header = header
  return true
end

function VM:setSections(sections)
  if type(sections) ~= "table" then return false end
  self.sections = sections
  return true
end

function VM:setActions(actions)
  if type(actions) ~= "table" then return false end
  self.actions = actions
  return true
end

function VM:addError(code, message)
  self.errors[#self.errors + 1] = {
    code = code or "ERROR",
    message = message or "",
  }
end

function VM:commit()
  self.revision = self.revision + 1
  self.snapshot = {
    schemaVersion = self.schemaVersion,
    revision = self.revision,
    moduleId = self.moduleId,
    generatedAt = nowMs(),
    state = self.state,
    header = deepCopy(self.header),
    sections = deepCopy(self.sections),
    actions = deepCopy(self.actions),
    errors = deepCopy(self.errors),
  }
  return self.snapshot
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI["ui.core.view_model"] = VM
end

return VM
