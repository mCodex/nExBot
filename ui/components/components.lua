--[[
  Components — the shared widget library consumed by every module.

  Each component is a factory: (parent, options) -> widget (or row handle).
  Components resolve colors, fonts, and spacing through the design system.
  They never read domain globals; they receive everything they need through
  options and callbacks.

  Styles referenced here (NexButton, NexCard, ...) are declared in
  ui/shell/styles.otui, imported by the shell.
]]

local Tokens = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.tokens"]) or (type(require) == "function" and require("ui.design_system.tokens"))
local Typography = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.typography"]) or (type(require) == "function" and require("ui.design_system.typography"))
local Density = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.density"]) or (type(require) == "function" and require("ui.design_system.density"))
local Status = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.status"]) or (type(require) == "function" and require("ui.design_system.status"))

local C = {}

-- Current density name, applied to every "row" or "control" role widget at
-- creation time. Set by the shell so the whole tree (nav, tabs, module
-- content) tracks the user's density/touch preference without each module
-- having to know about it.
local currentDensity = "default"

function C.setDensity(name)
  currentDensity = Density.presets[name] and name or "default"
  return currentDensity
end

function C.getDensity()
  return currentDensity
end

local function create(parent, style, opts, role)
  opts = opts or {}
  local widget = g_ui.createWidget(style, parent)
  if opts.id then widget:setId(opts.id) end
  if opts.tooltip then widget:setTooltip(opts.tooltip) end
  if opts.width then widget:setWidth(opts.width) end
  if opts.height then
    widget:setHeight(opts.height)
  elseif role then
    local preset = Density.get(currentDensity)
    widget:setHeight(role == "row" and preset.rowHeight or preset.controlHeight)
  end
  if opts.disabled then widget:setEnabled(false) end
  return widget
end

local function label(parent, text, style, opts)
  opts = opts or {}
  local w = create(parent, style or "Label", opts)
  w:setFont(Typography.get(opts.textStyle or "body").font)
  if opts.color then w:setColor(opts.color) end
  if text then w:setText(text) end
  return w
end

function C.label(parent, opts)
  return label(parent, opts.text, opts.style or "Label", opts)
end

function C.button(parent, opts)
  opts = opts or {}
  local colors = Tokens.colors
  local variantColor = {
    active = colors.active,
    inactive = colors.disabled,
    warning = colors.warning,
    danger = colors.danger,
  }
  local w = create(parent, opts.style or "NexButton", opts, "control")
  w:setText(opts.text or "")
  local color = opts.color or variantColor[opts.variant or "primary"]
  if color then w:setColor(color) end
  if opts.onClick then w.onClick = opts.onClick end
  return w
end

function C.card(parent, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexCard", opts)
  if opts.title then
    label(w, opts.title, "Label", { id = "cardTitle", textStyle = "sectionTitle" })
  end
  return w
end

function C.sectionHeader(parent, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexSectionHeader", opts)
  label(w, opts.title or "", "NexSectionTitle", { id = "title", textStyle = "sectionTitle" })
  if opts.action and opts.action.text then
    C.button(w, { text = opts.action.text, id = "action", variant = "ghost", onClick = opts.action.onClick })
  end
  return w
end

function C.statusBadge(parent, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexBadge", opts)
  w:setText(opts.text or opts.status or "")
  w:setColor(Status.color(opts.status, opts.color))
  if opts.id then w:setId(opts.id) end
  return w
end

-- Shared page-header shell: title + optional subtitle/landmark icon/status
-- badge. Every module page (Page.render's generic flow and the DataTable-
-- driven module pages) built this exact widget tree by hand; centralizing it
-- here removes that duplication and keeps header markup consistent.
function C.pageHeader(parent, opts)
  opts = opts or {}
  local header = create(parent, "NexPageHeader", { id = opts.id })
  if opts.itemId ~= nil then
    local landmark = g_ui.createWidget("NexPageLandmark", header)
    landmark:setId(opts.landmarkId or "pageLandmark")
    landmark:setItemId(opts.itemId)
  end
  local text = create(header, "NexPageHeaderText", { id = opts.textId })
  label(text, opts.title or "nExBot", "NexPageTitle", { id = opts.titleId, textStyle = opts.titleStyle or "windowTitle" })
  if opts.subtitle then
    label(text, opts.subtitle, "NexPageSubtitle", { id = opts.subtitleId, textStyle = opts.subtitleStyle or "metadata" })
  end
  if opts.status then
    C.statusBadge(header, { id = opts.badgeId, style = "NexPageHeaderBadge", status = opts.status, text = opts.statusText or opts.status })
  end
  return header
end

function C.metricCard(parent, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexMetricCard", opts)
  label(w, tostring(opts.value or "-"), "NexMetricValue", { id = "value", textStyle = "displayMetric", color = Tokens.colors.text.primary })
  label(w, opts.label or "", "NexMetricLabel", { id = "label", textStyle = "metadata", color = Tokens.colors.text.muted })
  C.statusBadge(w, { id = "status", style = "NexMetricStatus", status = opts.status, text = opts.status or "" })
  return w
end

function C.keyValueRow(parent, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexRow", opts, "row")
  label(w, opts.key or "", "NexKeyLabel", { id = "key", textStyle = "body" })
  label(w, tostring(opts.value or ""), "NexValueLabel", { id = "value", textStyle = "body" })
  return w
end

local function rowWithLabel(parent, labelText, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexRow", opts, "row")
  if labelText then
    label(w, labelText, "NexControlLabel", { id = "rowLabel", textStyle = "body", color = Tokens.colors.text.secondary })
  end
  return w
end

-- Standalone NexToggle widget. Use inside custom layouts where toggleRow's
-- row wrapper is not wanted (e.g. cockpit engine rows, controller sidebar).
function C.toggle(parent, opts)
  opts = opts or {}
  local sw = g_ui.createWidget("NexToggle", parent)
  if opts.id then sw:setId(opts.id) end
  if opts.tooltip then sw:setTooltip(opts.tooltip) end
  sw:setChecked(opts.value == true)
  local track = sw:getChildById("track")
  local thumb = sw:getChildById("thumb")
  local function updateVisual(checked)
    if track then track:setText(checked and "ON" or "OFF") end
  end
  updateVisual(opts.value == true)
  local origSet = sw.setChecked
  sw.setChecked = function(self, v)
    v = not not v
    origSet(self, v)
    updateVisual(v)
    if opts.onChange then opts.onChange(v) end
  end
  sw.onClick = function()
    sw:setChecked(not sw:isChecked())
  end
  return sw
end

function C.toggleRow(parent, opts)
  opts = opts or {}
  local w = rowWithLabel(parent, opts.label, opts)
  local sw = C.toggle(w, { id = "switch", value = opts.value, tooltip = opts.tooltip or ("Toggle " .. (opts.label or "")), onChange = opts.onChange })
  return {
    widget = w,
    getSwitch = function() return sw end,
    setValue = function(v) sw:setChecked(v) end,
    getValue = function() return sw:isChecked() end,
  }
end

function C.checkboxRow(parent, opts)
  return C.toggleRow(parent, opts)
end

function C.selectRow(parent, opts)
  opts = opts or {}
  local w = rowWithLabel(parent, opts.label, opts)
  local combo = create(w, "NexControlCombo", { id = "combo", tooltip = opts.tooltip or ("Select " .. (opts.label or "")) })
  if opts.options then
    for _, o in ipairs(opts.options) do
      combo:addOption(type(o) == "table" and (o.text or o) or o, type(o) == "table" and o.value or nil)
    end
  end
  if opts.value then combo:setCurrentOption(opts.value) end
  if opts.onChange then combo.onOptionChange = function(_, text, data) opts.onChange(text, data) end end
  return { widget = w, getCombo = function() return combo end, setValue = function(v) combo:setCurrentOption(v) end }
end

function C.inputRow(parent, opts)
  opts = opts or {}
  local w = rowWithLabel(parent, opts.label, opts)
  local input = create(w, "NexControlInput", { id = "input", tooltip = opts.tooltip or (opts.label or "") })
  if opts.value ~= nil then input:setText(opts.value) end
  if opts.onChange then
    input.onTextChange = function(_, text) opts.onChange(text) end
  end
  return { widget = w, getInput = function() return input end, setValue = function(v) input:setText(v) end }
end

function C.itemRow(parent, opts)
  opts = opts or {}
  local row = create(parent, "NexItemRow", opts)
  local item = create(row, "NexItemSprite", { id = "item", tooltip = opts.tooltip })
  item:setItemId(tonumber(opts.itemId) or 0)
  if opts.count then item:setItemCount(opts.count) end

  local details = create(row, "NexItemDetails", { id = "details" })
  label(details, opts.title or ("Item " .. tostring(opts.itemId or "")), "NexItemTitle", {
    id = "title", textStyle = "rowTitle", color = Tokens.colors.text.primary,
  })
  if opts.subtitle then
    label(details, opts.subtitle, "NexItemSubtitle", {
      id = "subtitle", textStyle = "metadata", color = Tokens.colors.text.muted,
    })
  end
  if opts.onClick then row.onClick = opts.onClick end
  return row
end

function C.sliderRow(parent, opts)
  opts = opts or {}
  local w = rowWithLabel(parent, opts.label, opts)
  local slider = create(w, "NexControlSlider", { id = "slider" })
  if opts.min then slider:setMinimum(opts.min) end
  if opts.max then slider:setMaximum(opts.max) end
  if opts.value then slider:setValue(opts.value) end
  return { widget = w, getSlider = function() return slider end }
end

function C.searchToolbar(parent, opts)
  opts = opts or {}
  local w = create(parent, "NexToolbar", opts)
  local input = create(w, "BotTextEdit", { id = "search" })
  if opts.placeholder then input:setText(opts.placeholder) end
  input._onChange = opts.onChange
  return { widget = w, getInput = function() return input end }
end

function C.listRow(parent, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexListRow", opts)
  local title = label(w, opts.title or "", "NexListTitle", { id = "title", textStyle = "rowTitle", color = Tokens.colors.text.primary })
  if opts.subtitle then
    label(w, opts.subtitle, "NexListSubtitle", { id = "subtitle", textStyle = "metadata", color = Tokens.colors.text.muted })
  end
  local actions = create(w, "NexListActions", { id = "listActions" })
  if opts.status then
    C.statusBadge(actions, { id = "status", status = opts.status, text = opts.statusText or opts.status })
  end
  if opts.actions then
    for _, action in ipairs(opts.actions) do
      C.button(actions, {
        text = action.text, id = action.id,
        variant = action.variant or "ghost",
        onClick = action.onClick,
        tooltip = action.tooltip,
      })
    end
  end
  return {
    widget = w,
    getTitle = function() return title end,
    getSubtitle = function() return w:getChildById("subtitle") end,
  }
end

function C.emptyState(parent, opts)
  opts = opts or {}
  return label(parent, opts.message or "Nothing here yet.", "Label", { textStyle = "helper", color = Tokens.colors.text.muted })
end

function C.loadingState(parent)
  return label(parent, "Loading...", "Label", { textStyle = "helper", color = Tokens.colors.text.muted })
end

function C.errorState(parent, opts)
  opts = opts or {}
  local w = create(parent, "NexCard", opts)
  w:setColor(Tokens.colors.danger)
  label(w, opts.message or "Something went wrong.", "Label", { id = "message", textStyle = "body", color = Tokens.colors.danger })
  return w
end

function C.inlineWarning(parent, opts)
  opts = opts or {}
  return label(parent, opts.message or "", "Label", { textStyle = "helper", color = Tokens.colors.warning })
end

-- Close button (top-right X) for standalone windows. Single source for every
-- window's close affordance so it looks and behaves identically everywhere.
function C.closeButton(parent, opts)
  opts = opts or {}
  local w = create(parent, "NexCloseButton", { id = opts.id or "close", tooltip = opts.tooltip or "Close" })
  if opts.onClose then w.onClick = opts.onClose end
  return w
end

function C.footerActions(parent, opts)
  opts = opts or {}
  local w = create(parent, "NexFooter", opts)
  if opts.primary then
    C.button(w, { text = opts.primary.text, id = "primary", variant = "primary", onClick = opts.primary.onClick })
  end
  if opts.secondary then
    C.button(w, { text = opts.secondary.text, id = "secondary", variant = "ghost", onClick = opts.secondary.onClick })
  end
  if opts.danger then
    C.button(w, { text = opts.danger.text, id = "danger", variant = "danger", onClick = opts.danger.onClick })
  end
  return w
end

function C.diagnosticBlock(parent, opts)
  opts = opts or {}
  return label(parent, opts.code or "", "Label", { textStyle = "mono", color = Tokens.colors.text.secondary })
end

function C.helpTooltip(parent, opts)
  opts = opts or {}
  local w = create(parent, "Label", { id = opts.id, tooltip = opts.text })
  w:setText("?")
  w:setColor(Tokens.colors.info)
  return w
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI["ui.components.components"] = C
end

return C
