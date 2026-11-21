local RingBuffer = nExBot and nExBot.RingBuffer or dofile("utils/ring_buffer.lua")

IntelligenceReplay = {}
local Replay = IntelligenceReplay
Replay.__index = Replay
Replay.SCHEMA_VERSION = 1

local function copy(value, seen)
  local kind = type(value)
  if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then return value end
  if kind ~= "table" then return nil end
  seen = seen or {}
  if seen[value] then return nil end
  local result = {}
  seen[value] = true
  for key, item in pairs(value) do
    local safeKey, safeItem = copy(key, seen), copy(item, seen)
    if safeKey ~= nil and safeItem ~= nil then result[safeKey] = safeItem end
  end
  seen[value] = nil
  return result
end

function Replay.new(maxRecords)
  return setmetatable({ records = RingBuffer.new(maxRecords or 500) }, Replay)
end

function Replay:record(record)
  assert(type(record) == "table", "replay record must be a table")
  local stored = {}
  for _, field in ipairs({ "events", "snapshotRef", "features", "proposals", "selected", "rejected", "outcome", "reward" }) do
    stored[field] = copy(record[field])
  end
  self.records:push(stored)
end

function Replay:export()
  return copy(self.records:toArray())
end

function Replay:exportDocument()
  return { schemaVersion = Replay.SCHEMA_VERSION, records = self:export() }
end

function Replay:import(document)
  if type(document) ~= "table" or document.schemaVersion ~= Replay.SCHEMA_VERSION
      or type(document.records) ~= "table" then return false, "invalid replay document" end
  self.records:clear()
  for _, record in ipairs(document.records) do
    if type(record) == "table" then self:record(record) end
  end
  return true
end

function Replay:exportFile(path, resources, codec)
  if type(path) ~= "string" or path == "" or not resources or not resources.writeFileContents
      or not codec or not codec.encode then return false, "replay export unavailable" end
  local encoded, content = pcall(codec.encode, self:exportDocument(), 2)
  if not encoded or type(content) ~= "string" then return false, "replay encoding failed" end
  local written, err = pcall(resources.writeFileContents, path, content)
  return written, written and path or tostring(err)
end

function Replay:run(callback)
  assert(type(callback) == "function", "replay callback is required")
  local results = {}
  for index, record in ipairs(self:export()) do results[index] = callback(record, index) end
  return results
end

return Replay
