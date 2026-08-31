local Components = nExBot.UI["ui.components.components"]
local TableModel = nExBot.UI["ui.components.table_model"]
local Resolver = nExBot.UI.VisualAssetResolver

local DataTable = {}

local function densityFor(parent, requested)
  if requested then return requested end
  local width = parent and parent.getWidth and parent:getWidth() or 0
  if width > 0 and width < 310 then return "narrow" end
  if width >= 560 then return "wide" end
  return "standard"
end

local function renderRow(parent, projected, options, density, rowIndex, widget)
  local row = projected.data
  local isOdd = rowIndex % 2 == 1
  widget = widget or g_ui.createWidget(isOdd and "NexTableRowOdd" or "NexTableRow", parent)
  if widget.destroyChildren then widget:destroyChildren() end
  widget:setId((options.id or "table") .. "_" .. projected.key)
  widget._rowFingerprint = projected.revision

  if row.itemId then
    local item = g_ui.createWidget("NexTableItem", widget)
    item:setId("visual")
    item:setItemId(row.itemId)
    item:setTooltip((Resolver:item(row.itemId)).name)
  elseif row.imageSource then
    local icon = g_ui.createWidget("NexTableIcon", widget)
    icon:setId("visual")
    icon:setImageSource(row.imageSource)
  else
    local placeholder = g_ui.createWidget("NexTableIcon", widget)
    placeholder:setId("visual")
    placeholder:setTooltip(row.title or row.name or "")
  end

  local details = g_ui.createWidget("NexTableDetails", widget)
  details:setId("details")
  Components.label(details, { id = "title", text = row.title or row.name or projected.key, textStyle = "rowTitle", style = "NexTableTitle" })
  local secondary = row.secondary or row.subtitle
  if density == "narrow" and row.compactSecondary then secondary = row.compactSecondary end
  if secondary then
    Components.label(details, { id = "secondary", text = secondary, textStyle = "metadata", style = "NexTableSecondary" })
  end

  local actions = g_ui.createWidget("NexTableActions", widget)
  actions:setId("actions")
  if row.status then Components.statusBadge(actions, { id = "status", status = row.status, text = row.statusText or row.status }) end
  for _, action in ipairs(row.actions or {}) do
    Components.button(actions, {
      id = action.id, text = action.text, variant = action.variant or "ghost",
      tooltip = action.tooltip, onClick = action.onClick,
    })
  end
  if row.onClick then widget.onClick = row.onClick end
  return widget
end

function DataTable.create(parent, options)
  options = options or {}
  local root = g_ui.createWidget("NexDataTable", parent)
  root:setId(options.id or "dataTable")
  local header = g_ui.createWidget("NexTableHeader", root)
  header:setId("header")
  local search
  if options.searchable then
    search = g_ui.createWidget("NexTableSearch", header)
    search:setId("search")
    search:setTooltip("Filter this list")
  end
  Components.label(header, {
    id = "headerTitle", text = options.title or "", textStyle = "sectionTitle",
    style = options.searchable and "NexTableHeaderSearchTitle" or "NexTableHeaderTitle",
  })
  local body = g_ui.createWidget("NexTableBody", root)
  body:setId("body")
  local widgets = {}
  local fingerprint

  local handle = { widget = root }
  function handle:update(nextOptions)
    nextOptions = nextOptions or options
    local density = densityFor(parent, nextOptions.density)
    local model = TableModel.project({
      rows = nextOptions.rows,
      rowKey = nextOptions.rowKey,
      query = nextOptions.query,
      searchText = nextOptions.searchText,
      page = nextOptions.page,
      pageSize = nextOptions.pageSize,
      density = density,
    })
    if model.fingerprint == fingerprint then return false end

    local retained = {}
    for rowIndex, projected in ipairs(model.rows) do
      local key = projected.key
      local rowFingerprint = projected.revision
      local widget = widgets[key]
      if not widget then
        widget = renderRow(body, projected, nextOptions, density, rowIndex)
      elseif widget._rowFingerprint ~= rowFingerprint then
        renderRow(body, projected, nextOptions, density, rowIndex, widget)
      end
      retained[key] = widget
    end
    for key, widget in pairs(widgets) do
      if not retained[key] then widget:destroy() end
    end
    widgets = retained
    fingerprint = model.fingerprint

    local empty = body:recursiveGetChildById("empty")
    if model.total == 0 and not empty then
      local empty = Components.emptyState(body, { message = nextOptions.emptyMessage or "Nothing here yet." })
      empty:setId("empty")
    elseif model.total > 0 and empty then
      empty:destroy()
    end
    if body.moveChildToIndex then
      for index, projected in ipairs(model.rows) do body:moveChildToIndex(widgets[projected.key], index) end
    end
    return true, model
  end

  if search then
    search.onTextChange = function(_, query)
      options.query = query
      handle:update(options)
    end
  end

  handle:update(options)
  return handle
end

if nExBot then
  nExBot.UI.DataTable = DataTable
  nExBot.UI["ui.components.data_table"] = DataTable
end

return DataTable
