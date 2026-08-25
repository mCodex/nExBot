--[[
  ModuleRegistry — single source of truth for the nExBot UI shell navigation.

  Drives advanced destinations, labels, ordering, availability, and
  tests. The primary hunt cockpit is intentionally fixed; secondary module
  pages register here for Shell.select and More navigation.

  Lookup is O(1) via a keyed map; ordering is derived from a sorted index.
]]

local Registry = {}
Registry.__index = Registry

local modules = {}   -- id -> descriptor
local order = {}     -- sorted array of ids
local dirty = false

local function sortIndex()
  if dirty then
    table.sort(order, function(a, b)
      local A, B = modules[a], modules[b]
      if A.order ~= B.order then return A.order < B.order end
      return A.id < B.id
    end)
    dirty = false
  end
  return order
end

function Registry.register(desc)
  if type(desc) ~= "table" then return false end
  local id = desc.id
  if type(id) ~= "string" or id == "" then return false end
  if type(desc.label) ~= "string" or desc.label == "" then return false end
  if type(desc.order) ~= "number" then return false end
  if modules[id] then return false end

  modules[id] = {
    id = id,
    label = desc.label,
    order = desc.order,
    sections = desc.sections or {},
    permissions = desc.permissions or {},
    statusProvider = desc.statusProvider,
    commandHandler = desc.commandHandler,
    render = desc.render,
    group = desc.group,
    route = desc.route or id,
    breadcrumb = desc.breadcrumb or desc.label,
    primaryAction = desc.primaryAction,
  }
  order[#order + 1] = id
  dirty = true
  return true
end

function Registry.get(id)
  return modules[id]
end

function Registry.ids()
  return sortIndex()
end

function Registry.list()
  local out = {}
  for _, id in ipairs(sortIndex()) do
    out[#out + 1] = modules[id]
  end
  return out
end

function Registry.count()
  return #order
end

function Registry.sections(id)
  local m = modules[id]
  return m and m.sections or {}
end

-- Returns a list of {message, id} errors. Empty list == valid.
function Registry.validate()
  local errors = {}
  local seen = {}
  for _, id in ipairs(sortIndex()) do
    local m = modules[id]
    if seen[id] then
      errors[#errors + 1] = { id = id, message = "duplicate registration" }
    else
      seen[id] = true
    end
    if type(m.sections) ~= "table" then
      errors[#errors + 1] = { id = id, message = "sections must be a table" }
    end
  end
  return errors
end

-- test/reset hook
function Registry.reset()
  modules = {}
  order = {}
  dirty = false
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.ModuleRegistry = Registry
end

return Registry
