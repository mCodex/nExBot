local TableModel = {}

local function rowKey(row, index, keyFn)
  if keyFn then return tostring(keyFn(row, index)) end
  return tostring(row.id or row.key or index)
end

local function rowRevision(row)
  return tostring(row.revision or row.fingerprint or 0)
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

  local pageSize = math.max(1, tonumber(options.pageSize) or 40)
  local pages = math.max(1, math.ceil(#filtered / pageSize))
  local page = math.max(1, math.min(tonumber(options.page) or 1, pages))
  local first = (page - 1) * pageSize + 1
  local visible = {}
  local fingerprint = { options.density or "standard", tostring(page), tostring(#filtered) }

  for index = first, math.min(#filtered, first + pageSize - 1) do
    local projected = filtered[index]
    visible[#visible + 1] = projected
    fingerprint[#fingerprint + 1] = projected.key .. ":" .. rowRevision(projected.data)
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
