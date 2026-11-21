local Writer = {}
Writer.__index = Writer

function Writer.new(config)
  local self = setmetatable({}, Writer)
  config = config or {}
  self.resources = config.resources
  self.codec = config.codec
  return self
end

function Writer:ensureDir(path)
  local resources = self.resources
  if type(path) ~= "string" or path == "" then return false, "invalid_arguments" end
  if not resources or not resources.directoryExists or not resources.makeDir then
    return false, "resources_unavailable"
  end

  local segment = path:match("^/") or ""
  for part in path:gmatch("[^/]+/") do
    segment = segment .. part
    local exists, existsErr = pcall(resources.directoryExists, segment)
    if not exists then return false, tostring(existsErr) end
    if not existsErr then
      local created, createErr = pcall(resources.makeDir, segment)
      if not created then return false, tostring(createErr) end
    end
  end

  return true, nil
end

function Writer:writeChunk(dir, chunkIndex, events)
  if type(dir) ~= "string" or dir == "" then return false, "invalid_arguments" end
  if type(chunkIndex) ~= "number" or chunkIndex < 1 or chunkIndex ~= math.floor(chunkIndex) then
    return false, "invalid_arguments"
  end
  if type(events) ~= "table" then return false, "invalid_arguments" end

  local dirOk, dirErr = self:ensureDir(dir)
  if not dirOk then return false, dirErr end

  local path = dir .. string.format("events-%04d.json", chunkIndex)
  local document = { schemaVersion = 1, chunkIndex = chunkIndex, count = #events, events = events }
  return self:_writeDocument(path, document)
end

-- manifest.json is expected to be overwritten repeatedly across a session; cheap, small file
function Writer:writeManifest(dir, manifest)
  if type(dir) ~= "string" or dir == "" then return false, "invalid_arguments" end
  if type(manifest) ~= "table" then return false, "invalid_arguments" end

  local dirOk, dirErr = self:ensureDir(dir)
  if not dirOk then return false, dirErr end

  local path = dir .. "manifest.json"
  return self:_writeDocument(path, manifest)
end

function Writer:_writeDocument(path, document)
  local codec = self.codec
  local resources = self.resources
  if not codec or not codec.encode then return false, "resources_unavailable" end
  if not resources or not resources.writeFileContents then return false, "resources_unavailable" end

  local encoded, content = pcall(codec.encode, document, nil)
  if not encoded or type(content) ~= "string" then return false, "encode_failed" end

  local written, err = pcall(resources.writeFileContents, path, content)
  if not written then return false, tostring(err) end

  return true, path
end

nExBot = nExBot or {}
nExBot.IntelligenceTelemetryWriter = Writer

return Writer
