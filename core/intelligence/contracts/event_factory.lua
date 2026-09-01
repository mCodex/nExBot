local IntelligenceEventFactory = {}
IntelligenceEventFactory.__index = IntelligenceEventFactory

function IntelligenceEventFactory.new(config)
  assert(config and config.schema, "config.schema required")
  local self = setmetatable({}, IntelligenceEventFactory)
  self._schema = config.schema
  self._counter = 0
  self._errors = {}
  return self
end

local function check_numeric_fields(tbl, errors)
  if type(tbl) ~= "table" then return end
  for k, v in pairs(tbl) do
    if type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then
      table.insert(errors, "field '" .. k .. "' contains NaN or Infinity")
    elseif type(v) == "table" then
      check_numeric_fields(v, errors)
    end
  end
end

function IntelligenceEventFactory:create(typeName, data, context)
  self._errors = {}

  if not self._schema.isValidType(typeName) then
    table.insert(self._errors, "invalid type: " .. tostring(typeName))
    return nil
  end

  if not context or not context.source or not context.sessionId or not context.characterKey then
    table.insert(self._errors, "missing context field (source, sessionId, characterKey required)")
    return nil
  end

  local required = self._schema.requiredFieldsFor(typeName)
  local auto = { eventId = true, timestamp = true, schemaVersion = true, idempotencyKey = true }
  local contextFields = { source = true, sessionId = true, characterKey = true }

  -- check data has required fields (skip auto-generated and context)
  for _, f in ipairs(required) do
    if not auto[f] and not contextFields[f] then
      local found = data and data[f] ~= nil
      if not found then
        table.insert(self._errors, "missing required field: " .. f)
      end
    end
  end
  if #self._errors > 0 then return nil end

  -- reject NaN/Infinity in data
  if data then check_numeric_fields(data, self._errors) end
  check_numeric_fields(context, self._errors)
  if #self._errors > 0 then return nil end

  self._counter = self._counter + 1
  local ts = os.time()

  local event = {
    eventId = "evt:" .. ts .. ":" .. self._counter,
    type = typeName,
    timestamp = ts,
    schemaVersion = self._schema.SCHEMA_VERSION,
    source = context.source,
    sessionId = context.sessionId,
    characterKey = context.characterKey,
    idempotencyKey = "idem:" .. ts .. ":" .. self._counter,
  }

  if data then
    for k, v in pairs(data) do event[k] = v end
  end

  return event
end

function IntelligenceEventFactory:validate(event)
  if type(event) ~= "table" then return false end
  if type(event.eventId) ~= "string" then return false end
  if type(event.type) ~= "string" then return false end
  if type(event.timestamp) ~= "number" then return false end
  if not self._schema.isValidType(event.type) then return false end
  return true
end

function IntelligenceEventFactory:getErrors()
  return self._errors
end

nExBot = nExBot or {}
nExBot.IntelligenceEventFactory = IntelligenceEventFactory

return IntelligenceEventFactory
