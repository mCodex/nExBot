--[[
  WidgetHarness: a fake OTUI widget tree for testing nExBot UI components.

  Mirrors the subset of OTClient OTUI widget semantics that the nExBot UI
  layer uses:
    * widget creation via g_ui.createWidget(style, parent)
    * widget creation via UI.createWindow / UI.createWidget / UI.Button /
      UI.Label / UI.Separator / UI.TextEdit / UI.DualLabel
    * hierarchy: parent/children, recursiveGetChildById
    * text/font/color/tooltip/size/margin/visibility setters
    * click / option change handlers
    * checkbox (BotSwitch) and spinbox values
    * destroy + destroyChildren
    * a mutation log so tests can assert "zero widget writes" on unchanged
      revisions and "no leaked widgets" after close/reopen cycles.

  The harness installs fake g_ui / UI / setDefaultTab globals (falling back to
  real ones if already present). It is intentionally small: it does NOT model
  layout/anchoring or rendering.
]]

local M = {}

local function newWidget(style, parent, kind)
  local children = {}
  local self = {
    _id = nil,
    _style = style,
    _kind = kind,
    _parent = parent,
    _text = "",
    _font = nil,
    _color = nil,
    _tooltip = nil,
    _width = 0,
    _height = 0,
    _visible = true,
    _destroyed = false,
    _checked = false,
    _value = 0,
    _max = 100,
    _min = 0,
    _currentOption = nil,
    _options = {},
    _onClick = nil,
    _onOptionChange = nil,
    _imageSource = nil,
    _itemId = 0,
  }

  self.children = children

  function self:addChild(child)
    if child._parent and child._parent ~= self then
      child._parent:removeChild(child)
    end
    child._parent = self
    children[#children + 1] = child
    return child
  end

  function self:removeChild(child)
    for i = #children, 1, -1 do
      if children[i] == child then
        table.remove(children, i)
        child._parent = nil
        return child
      end
    end
  end

  function self:destroy()
    if self._destroyed then return end
    M.record("destroy", self)
    self._destroyed = true
    -- destroy children first (top-down like OTUI)
    for i = #children, 1, -1 do
      children[i]:destroy()
    end
    children = {}
    if self._parent then
      self._parent:removeChild(self)
    end
  end

  function self:isDestroyed() return self._destroyed end

  function self:getChildren() return children end
  function self:getChildCount() return #children end

  function self:destroyChildren()
    for i = #children, 1, -1 do
      children[i]:destroy()
    end
  end

  function self:recursiveGetChildById(id)
    if self._id == id then return self end
    for i = 1, #children do
      local found = children[i]:recursiveGetChildById(id)
      if found then return found end
    end
    return nil
  end

  function self:getChildById(id)
    for i = 1, #children do
      if children[i]._id == id then return children[i] end
    end
    return nil
  end

  function self:getParent() return self._parent end
  function self:getStyle() return self._style end
  function self:getKind() return self._kind end

  -- setters record mutations
  function self:setId(id) self._id = id; M.record("setId", self, id) return self end
  function self:getId() return self._id end

  function self:setText(text)
    text = tostring(text or "")
    if self._text ~= text then
      M.record("setText", self, text)
      self._text = text
    end
    return self
  end
  function self:getText() return self._text end

  function self:setFont(font) self._font = font; M.record("setFont", self, font) return self end
  function self:getFont() return self._font end

  function self:setColor(color) self._color = color; M.record("setColor", self, color) return self end
  function self:getColor() return self._color end

  function self:setTooltip(tip) self._tooltip = tip; M.record("setTooltip", self, tip) return self end
  function self:getTooltip() return self._tooltip end

  function self:setEnabled(enabled)
    enabled = not not enabled
    if self._enabled ~= enabled then
      M.record("setEnabled", self, enabled)
      self._enabled = enabled
    end
    return self
  end
  function self:isEnabled() return self._enabled ~= false end

  function self:setWidth(w) self._width = w; M.record("setWidth", self, w) return self end
  function self:getWidth() return self._width end
  function self:setHeight(h) self._height = h; M.record("setHeight", self, h) return self end
  function self:getHeight() return self._height end

  function self:setVisible(v) self._visible = v; M.record("setVisible", self, v) return self end
  function self:isVisible() return self._visible end
  function self:hide() self:setVisible(false) end
  function self:show() self:setVisible(true) end
  function self:raise() return self end
  function self:focus() return self end

  function self:setMarginTop(v) self._marginTop = v; return self end
  function self:setMarginBottom(v) self._marginBottom = v; return self end
  function self:setMarginLeft(v) self._marginLeft = v; return self end
  function self:setMarginRight(v) self._marginRight = v; return self end
  function self:setMargin(v) self:setMarginTop(v):setMarginBottom(v):setMarginLeft(v):setMarginRight(v) end

  -- checkbox (BotSwitch)
  function self:setChecked(checked)
    checked = not not checked
    if self._checked ~= checked then
      M.record("setChecked", self, checked)
      self._checked = checked
    end
    return self
  end
  function self:isChecked() return self._checked end
  function self:setOn(on) return self:setChecked(on) end
  function self:isOn() return self._checked end

  -- spinbox
  function self:setValue(v) self._value = v; M.record("setValue", self, v) return self end
  function self:getValue() return self._value end
  function self:setMaximum(m) self._max = m; return self end
  function self:setMinimum(m) self._min = m; return self end

  -- combobox
  function self:setOptions(options) self._options = options or {}; self._currentOption = self._options[1]; return self end
  function self:addOption(text, value)
    self._options[#self._options + 1] = { text = text, value = value }
    if not self._currentOption then self._currentOption = self._options[#self._options] end
    return self
  end
  function self:getCurrentOption() return self._currentOption end
  function self:setCurrentOption(option)
    self._currentOption = option
    if self._onOptionChange then
      M.record("onOptionChange", self)
      self._onOptionChange(option)
    end
    return self
  end
  function self:setOnOptionChange(fn) self._onOptionChange = fn; return self end

  -- image (icon)
  function self:setImageSource(src) self._imageSource = src; M.record("setImageSource", self, src) return self end
  function self:getImageSource() return self._imageSource end
  function self:setItemId(id) self._itemId = id; M.record("setItemId", self, id) return self end
  function self:getItemId() return self._itemId end

  -- click: the real client wires this via direct field assignment
  -- (widget.onClick = fn), never a setOnClick()/onClick() method call --
  -- see uiwidget.cpp's callLuaField("onClick", ...). Deliberately no
  -- setOnClick/onClick method is defined here, so production code that
  -- calls one (instead of assigning the field) fails the same way it
  -- would against the real client.
  function self:setOnRelease(fn) self._onRelease = fn; return self end
  function self:click()
    M.record("click", self)
    if self._enabled == false then return end
    if self.onClick then self.onClick(self) end
  end

  return self
end

local function defaultStyleFor(kind)
  if kind == "window" then return "MainWindow" end
  return "Button"
end

-- Mutation log --------------------------------------------------------------

M.log = {}

function M.record(action, widget, value)
  M.log[#M.log + 1] = {
    action = action,
    style = widget and widget.getStyle and widget:getStyle(),
    id = widget and widget.getId and widget:getId(),
    value = value,
  }
end

function M.clearLog()
  M.log = {}
end

function M.logTextCalls()
  local out = {}
  for i = 1, #M.log do
    if M.log[i].action == "setText" then
      out[#out + 1] = { id = M.log[i].id, text = M.log[i].value }
    end
  end
  return out
end

function M.countCalls(action)
  local n = 0
  for i = 1, #M.log do
    if M.log[i].action == action then n = n + 1 end
  end
  return n
end

-- Global installation --------------------------------------------------------

M.widgets = {}        -- every live widget
M.windows = {}        -- windows created via UI.createWindow
M.currentTab = "Main"
M.tabContents = {}    -- tab -> list of widgets
M.styleNames = {}     -- set of styles created

function M.reset()
  for i = 1, #M.widgets do
    local w = M.widgets[i]
    if w and not w:isDestroyed() then w:destroy() end
  end
  M.widgets = {}
  M.windows = {}
  M.tabContents = {}
  M.currentTab = "Main"
  M.styleNames = {}
  M.clearLog()
  -- installHostPanel() early-returns if modules.game_bot.contentsPanel already
  -- exists, so leaving it set would leak mutated widget state (e.g. botTabs'
  -- enabled/visible flags) across tests; clear it so each reset() +
  -- installHostPanel() pair rebuilds a fresh host panel.
  if _G.modules then _G.modules.game_bot = nil end
end

local g_ui_fake = {}
g_ui_fake.createWidget = function(style, parent)
  M.styleNames[style] = true
  local widget = newWidget(style, parent)
  M.widgets[#M.widgets + 1] = widget
  M.record("createWidget", widget)
  if parent then parent:addChild(widget) end
  return widget
end
g_ui_fake.importStyle = function() return true end
g_ui_fake.loadUIFromString = function() return nil end
g_ui_fake.loadUI = function() return nil end
g_ui_fake.getRootWidget = function() return M.root or g_ui_fake.createWidget("Root", nil) end
g_ui_fake.getWidget = function() return nil end
g_ui_fake.displayUI = function() end
g_ui_fake.hideUI = function() end
g_ui_fake.displayPopup = function() end
g_ui_fake.displayError = function(msg) M.record("displayError", nil, msg) end
g_ui_fake.displayInfo = function() end
g_ui_fake.displayWarning = function() end
g_ui_fake.displaySuccess = function() end

local UI_fake = {
  createWidget = function(style, parent)
    return g_ui_fake.createWidget(style, parent)
  end,
  createWindow = function(name, parent)
    local win = g_ui_fake.createWidget("MainWindow", parent)
    win._kind = "window"
    win:setId(name)
    M.windows[name] = win
    M.record("createWindow", win, name)
    return win
  end,
  createMiniWindow = function(name, parent)
    local win = g_ui_fake.createWidget("MiniWindow", parent)
    win._kind = "window"
    win:setId(name)
    M.windows[name] = win
    M.record("createMiniWindow", win, name)
    return win
  end,
  Button = function(text, onClick, style)
    local btn = g_ui_fake.createWidget(style or "Button", nil)
    if text then btn:setText(text) end
    if onClick then btn.onClick = onClick end
    local contents = M.tabContents[M.currentTab]
    contents[#contents + 1] = btn
    return btn
  end,
  Label = function(text, style)
    local label = g_ui_fake.createWidget(style or "Label", nil)
    if text then label:setText(text) end
    local contents = M.tabContents[M.currentTab]
    contents[#contents + 1] = label
    return label
  end,
  Separator = function()
    local sep = g_ui_fake.createWidget("Separator", nil)
    M.tabContents[M.currentTab][#M.tabContents[M.currentTab] + 1] = sep
    return sep
  end,
  TextEdit = function(text, onChange, style)
    local edit = g_ui_fake.createWidget(style or "TextEdit", nil)
    if text then edit:setText(text) end
    edit._onChange = onChange
    M.tabContents[M.currentTab][#M.tabContents[M.currentTab] + 1] = edit
    return edit
  end,
  DualLabel = function(title, value, style)
    local pair = {
      title = g_ui_fake.createWidget("Label", nil),
      value = g_ui_fake.createWidget("Label", nil),
      setTitle = function(t) pair.title:setText(t) end,
      setValue = function(v) pair.value:setText(v) end,
      getTitle = function() return pair.title:getText() end,
      getValue = function() return pair.value:getText() end,
    }
    pair.title:setText(title or "")
    pair.value:setText(value or "")
    M.tabContents[M.currentTab][#M.tabContents[M.currentTab] + 1] = pair
    return pair
  end,
  Config = function() return {} end,
}

local function setDefaultTab_fake(name)
  M.currentTab = name or "Main"
  M.tabContents[M.currentTab] = M.tabContents[M.currentTab] or {}
end

-- Host left-bar simulation: modules.game_bot.contentsPanel with a tab bar and
-- a botPanel content area (mirrors OTCv8 game_bot/bot.otui + bot.lua).
function M.installHostPanel()
  if not _G.modules then _G.modules = {} end
  _G.modules.game_bot = _G.modules.game_bot or {}
  if _G.modules.game_bot.contentsPanel then return M end

  local botPanel = g_ui_fake.createWidget("Panel", nil)
  botPanel:setId("botPanel")
  local tabs = g_ui_fake.createWidget("BotTabBar", nil)
  tabs:setId("botTabs")
  tabs._hostPanel = botPanel
  tabs.getPanel = function() return botPanel end

  local contentsPanel = {
    botPanel = botPanel,
    botTabs = tabs,
    config = { getCurrentOption = function() return { text = "nExBot" } end },
  }
  _G.modules.game_bot.contentsPanel = contentsPanel
  return M
end

function M.install()
  _G.g_ui = g_ui_fake
  _G.UI = UI_fake
  _G.setDefaultTab = setDefaultTab_fake
  _G.info = function() end
  _G.warn = function() end
  setDefaultTab_fake("Main")
  return M
end

function M.widgetCount()
  local n = 0
  for i = 1, #M.widgets do
    if not M.widgets[i]:isDestroyed() then n = n + 1 end
  end
  return n
end

function M.liveWidgets()
  local out = {}
  for i = 1, #M.widgets do
    if not M.widgets[i]:isDestroyed() then out[#out + 1] = M.widgets[i] end
  end
  return out
end

return M
