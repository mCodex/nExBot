local TableModel = {}
local MAX_VISIBLE_ROWS = 40

local function rowKey(row, index, keyFn)
  if keyFn then return tostring(keyFn(row, index)) end
  return tostring(row.id or row.key or index)
end

local function displayedFingerprint(row, density)
  local secondary = density == "narrow" and row.compactSecondary or (row.secondary or row.subtitle)
  local fields = {
    row.title or row.name or "", secondary or "", row.status or "", row.statusText or "",
    row.itemId or "", row.imageSource or "",
  }
  local hash = 5381
  for _, field in ipairs(fields) do
    for index = 1, #tostring(field) do
      hash = (hash * 33 + string.byte(tostring(field), index)) % 2147483647
    end
    hash = (hash * 33 + 124) % 2147483647
  end
  return tostring(hash)
end

local function rowRevision(row, density)
  if row.revision ~= nil then return tostring(row.revision):sub(1, 64) end
  if row.fingerprint ~= nil then return tostring(row.fingerprint):sub(1, 64) end
  return displayedFingerprint(row, density)
end

function TableModel.project(options)
  options = options or {}
  local source = options.rows or {}
  local query = tostring(options.query or ""):lower()
  local filtered = {}

  for index, row in ipairs(source) do
    local searchable = options.searchText and options.searchText(row) or row.name or row.title or ""
    if query == "" or tostring(searchable):lower():find(query, 1, true) then
      filtered[#filtered + 1] = { key = rowKey(row, index, options.rowKey), data = row }
    end
  end

  local pageSize = math.min(MAX_VISIBLE_ROWS, math.max(1, tonumber(options.pageSize) or MAX_VISIBLE_ROWS))
  local pages = math.max(1, math.ceil(#filtered / pageSize))
  local page = math.max(1, math.min(tonumber(options.page) or 1, pages))
  local first = (page - 1) * pageSize + 1
  local visible = {}
  local fingerprint = { options.density or "standard", tostring(page), tostring(#filtered) }

  for index = first, math.min(#filtered, first + pageSize - 1) do
    local projected = filtered[index]
    visible[#visible + 1] = projected
    projected.revision = rowRevision(projected.data, options.density)
    fingerprint[#fingerprint + 1] = projected.key .. ":" .. projected.revision
  end

  return {
    rows = visible,
    total = #filtered,
    page = page,
    pages = pages,
    density = options.density or "standard",
    fingerprint = table.concat(fingerprint, "|"),
  }
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI["ui.components.table_model"] = TableModel
end

return TableModel
