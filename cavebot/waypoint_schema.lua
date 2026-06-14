-- waypoint_schema.lua
-- Canonical parser for CaveBot waypoint lines.

CaveBot = CaveBot or {}

local WaypointSchema = {}

local function trim(s)
  if not s then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitCsv(raw)
  local out = {}
  if not raw or raw == "" then return out end
  for token in raw:gmatch("[^,]+") do
    out[#out + 1] = trim(token)
  end
  return out
end

local function toNumber(v)
  if v == nil then return nil end
  return tonumber(trim(tostring(v)))
end

local function parsePosition(tokens, startAt)
  local x = toNumber(tokens[startAt])
  local y = toNumber(tokens[startAt + 1])
  local z = toNumber(tokens[startAt + 2])
  if not x or not y or not z then
    return nil
  end
  return { x = x, y = y, z = z }
end

function WaypointSchema.parseLine(text, index)
  local line = trim(text)
  local node = {
    index = index,
    text = line,
    action = nil,
    value = nil,
    parseError = nil,
    pos = nil,
    isGoto = false,
    precision = nil,
  }

  if line == "" then
    node.parseError = "empty-line"
    return node
  end

  local action, rawValue = line:match("^(%w+)%s*:%s*(.*)$")
  if not action then
    node.parseError = "missing-action-prefix"
    return node
  end

  action = action:lower()
  rawValue = trim(rawValue)
  node.action = action
  node.value = rawValue

  if action == "goto" then
    local tokens = splitCsv(rawValue)
    node.pos = parsePosition(tokens, 1)
    if not node.pos then
      node.parseError = "goto-invalid-position"
      return node
    end
    node.isGoto = true
    node.precision = toNumber(tokens[4])
    if node.precision and node.precision < 0 then
      node.parseError = "goto-invalid-precision"
      return node
    end
    return node
  end

  if action == "usewith" then
    local tokens = splitCsv(rawValue)
    node.itemId = toNumber(tokens[1])
    node.pos = parsePosition(tokens, 2)
    if not node.itemId or not node.pos then
      node.parseError = "usewith-invalid-payload"
    end
    return node
  end

  if action == "use" then
    local tokens = splitCsv(rawValue)
    if #tokens == 1 then
      node.itemId = toNumber(tokens[1])
      if not node.itemId then
        node.parseError = "use-invalid-itemid"
      end
      return node
    end

    node.pos = parsePosition(tokens, 1)
    if not node.pos then
      node.parseError = "use-invalid-position"
    end
    return node
  end

  if action == "stand" then
    local tokens = splitCsv(rawValue)
    node.pos = parsePosition(tokens, 1)
    if not node.pos then
      node.parseError = "stand-invalid-position"
    end
    return node
  end

  if action == "lure" or action == "standlure" then
    local tokens = splitCsv(rawValue)
    if action == "standlure" then
      node.action = "rushlure"
      node.pos = parsePosition(tokens, 1)
      node.delay = toNumber(tokens[4])
      node.option = tokens[5]
      if not node.pos then
        node.parseError = "rushlure-invalid-position"
      end
      return node
    end
    local mode = tokens[1] and string.lower(tokens[1])
    if mode and (mode == "start" or mode == "stop" or mode == "toggle") then
      node.mode = mode
    else
      node.parseError = action .. "-invalid-mode"
    end
    return node
  end

  return node
end

function WaypointSchema.parsePositionFromText(text)
  local node = WaypointSchema.parseLine(text, 0)
  if node and node.pos then
    return { x = node.pos.x, y = node.pos.y, z = node.pos.z }
  end
  return nil
end

CaveBot.WaypointSchema = WaypointSchema
return WaypointSchema
