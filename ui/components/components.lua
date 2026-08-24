--[[
  Components — the shared widget library consumed by every module.

  Each component is a factory: (parent, options) -> widget (or row handle).
  Components resolve colors/fonts/spacing through the design system and icons
  through the IconRegistry. They never read domain globals; they receive
  everything they need through options and callbacks.

  Styles referenced here (NexButton, NexCard, ...) are declared in
  ui/shell/styles.otui, imported by the shell.
]]

local Tokens = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.tokens"]) or (type(require) == "function" and require("ui.design_system.tokens"))
local Typography = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.typography"]) or (type(require) == "function" and require("ui.design_system.typography"))
local Density = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.density"]) or (type(require) == "function" and require("ui.design_system.density"))
local Status = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.status"]) or (type(require) == "function" and require("ui.design_system.status"))

local C = {}

local function resolveIcon(id, size)
  local R = nExBot and nExBot.UI and nExBot.UI.IconRegistry
  if R and R.resolve then return R.resolve(id or "", size or 16) end
  return ""
end

local function create(parent, style, opts)
  opts = opts or {}
  local widget = g_ui.createWidget(style, parent)
  if opts.id then widget:setId(opts.id) end
  if opts.tooltip then widget:setTooltip(opts.tooltip) end
  if opts.width then widget:setWidth(opts.width) end
  if opts.height then widget:setHeight(opts.height) end
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
  return label(parent, opts.text, "Label", opts)
end

function C.button(parent, opts)
  opts = opts or {}
  local colors = Tokens.colors
  local variantColor = {
    primary = colors.accent.primary,
    secondary = colors.border.default,
    ghost = colors.text.secondary,
    danger = colors.danger,
  }
  local w = create(parent, opts.style or "NexButton", opts)
  w:setText(opts.text or "")
  w:setColor(variantColor[opts.variant or "primary"] or colors.accent.primary)
  if opts.onClick then w:setOnClick(opts.onClick) end
  if opts.background then w:setBackgroundColor(opts.background) end
  return w
end

function C.iconButton(parent, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexIconButton", opts)
  w:setImageSource(resolveIcon(opts.icon, opts.size or 16))
  if opts.tooltip then w:setTooltip(opts.tooltip) end
  if opts.onClick then w:setOnClick(opts.onClick) end
  return w
end

function C.card(parent, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexCard", opts)
  if opts.title then
    label(w, opts.title, "Label", { id = "cardTitle", textStyle = "sectionTitle", color = Tokens.colors.text.primary })
  end
  return w
end

function C.sectionHeader(parent, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexSectionHeader", opts)
  label(w, opts.title or "", "Label", { id = "title", textStyle = "sectionTitle", color = Tokens.colors.text.secondary })
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

function C.metricCard(parent, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexMetricCard", opts)
  label(w, tostring(opts.value or "-"), "Label", { id = "value", textStyle = "displayMetric", color = Tokens.colors.text.primary })
  label(w, opts.label or "", "Label", { id = "label", textStyle = "metadata", color = Tokens.colors.text.muted })
  if opts.status then
    C.statusBadge(w, { id = "status", status = opts.status, text = opts.status })
  end
  return w
end

function C.keyValueRow(parent, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexRow", opts)
  label(w, opts.key or "", "Label", { id = "key", textStyle = "body", color = Tokens.colors.text.secondary })
  label(w, tostring(opts.value or ""), "Label", { id = "value", textStyle = "body", color = Tokens.colors.text.primary })
  return w
end

local function rowWithLabel(parent, labelText, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexRow", opts)
  if labelText then
    label(w, labelText, "Label", { id = "rowLabel", textStyle = "body", color = Tokens.colors.text.secondary })
  end
  return w
end

function C.toggleRow(parent, opts)
  opts = opts or {}
  local w = rowWithLabel(parent, opts.label, opts)
  local sw = create(w, "BotSwitch", { id = "switch" })
  sw:setChecked(opts.value == true)
  -- Wire change: a wrapper around setChecked that fires onChange.
  local origSet = sw.setChecked
  sw.setChecked = function(self, v)
    v = not not v
    origSet(self, v)
    if opts.onChange then opts.onChange(v) end
  end
  return {
    widget = w,
    getSwitch = function() return sw end,
    setValue = function(v) sw:setChecked(v) end,
    getValue = function() return sw:isChecked() end,
  }
end

function C.checkboxRow(parent, opts)
  opts = opts or {}
  local w = rowWithLabel(parent, opts.label, opts)
  local cb = create(w, "CheckBox", { id = "checkbox" })
  cb:setChecked(opts.value == true)
  local origSet = cb.setChecked
  cb.setChecked = function(self, v)
    v = not not v
    origSet(self, v)
    if opts.onChange then opts.onChange(v) end
  end
  return { widget = w, getCheckbox = function() return cb end, setValue = function(v) cb:setChecked(v) end }
end

function C.selectRow(parent, opts)
  opts = opts or {}
  local w = rowWithLabel(parent, opts.label, opts)
  local combo = create(w, "ComboBox", { id = "combo" })
  if opts.options then
    for _, o in ipairs(opts.options) do
      combo:addOption(type(o) == "table" and (o.text or o) or o, type(o) == "table" and o.value or nil)
    end
  end
  if opts.onChange then combo:setOnOptionChange(opts.onChange) end
  if opts.value then combo:setCurrentOption(opts.value) end
  return { widget = w, getCombo = function() return combo end, setValue = function(v) combo:setCurrentOption(v) end }
end

function C.inputRow(parent, opts)
  opts = opts or {}
  local w = rowWithLabel(parent, opts.label, opts)
  local input = create(w, "BotTextEdit", { id = "input" })
  if opts.value ~= nil then input:setText(opts.value) end
  if opts.onChange then input._onChange = opts.onChange end
  return { widget = w, getInput = function() return input end, setValue = function(v) input:setText(v) end }
end

function C.sliderRow(parent, opts)
  opts = opts or {}
  local w = rowWithLabel(parent, opts.label, opts)
  local slider = create(w, "HorizontalScrollBar", { id = "slider" })
  if opts.min then slider:setMinimum(opts.min) end
  if opts.max then slider:setMaximum(opts.max) end
  if opts.value then slider:setValue(opts.value) end
  return { widget = w, getSlider = function() return slider end }
end

function C.searchToolbar(parent, opts)
  opts = opts or {}
  local w = create(parent, "NexToolbar", opts)
  C.iconButton(w, { icon = "search", id = "searchIcon", size = 14 })
  local input = create(w, "BotTextEdit", { id = "search" })
  if opts.placeholder then input:setText(opts.placeholder) end
  input._onChange = opts.onChange
  return { widget = w, getInput = function() return input end }
end

function C.listRow(parent, opts)
  opts = opts or {}
  local w = create(parent, opts.style or "NexListRow", opts)
  local title = label(w, opts.title or "", "Label", { id = "title", textStyle = "rowTitle", color = Tokens.colors.text.primary })
  if opts.subtitle then
    label(w, opts.subtitle, "Label", { id = "subtitle", textStyle = "metadata", color = Tokens.colors.text.muted })
  end
  if opts.status then
    C.statusBadge(w, { id = "status", status = opts.status, text = opts.statusText or opts.status })
  end
  if opts.actions then
    for _, action in ipairs(opts.actions) do
      C.button(w, {
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
