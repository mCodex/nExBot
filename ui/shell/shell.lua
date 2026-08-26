-- Compact hunt controller plus one shallow configuration workspace.

local Lifecycle = (nExBot and nExBot.UI and nExBot.UI["ui.core.lifecycle"]) or (type(require) == "function" and require("ui.core.lifecycle"))
local Components = (nExBot and nExBot.UI and nExBot.UI["ui.components.components"]) or (type(require) == "function" and require("ui.components.components"))
local Tokens = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.tokens"]) or (type(require) == "function" and require("ui.design_system.tokens"))
local Perf = (nExBot and nExBot.UI and nExBot.UI["ui.core.perf"]) or (type(require) == "function" and require("ui.core.perf"))

local DENSITIES = { compact = true, default = true, comfortable = true, touch = true }

local Shell = {}
local current

local CATEGORIES = {
  { id = "overview", label = "Overview", tabs = {
    { id = "cockpit", label = "Status" }, { id = "intelligence", label = "AI" }, { id = "analytics", label = "Analyzer" },
  } },
  { id = "hunt", label = "Hunt", tabs = {
    { id = "cavebot", label = "Route" }, { id = "targetbot", label = "Target" }, { id = "attack", label = "Attack" },
    { id = "looting", label = "Loot" }, { id = "dropper", label = "Dropper" },
    { id = "supplies", label = "Supplies" }, { id = "containers", label = "Containers" },
  } },
  { id = "character", label = "Character", tabs = {
    { id = "healing", label = "Healing" }, { id = "friend_healer", label = "Friend" }, { id = "conditions", label = "Conditions" }, { id = "safety", label = "Safety" },
    { id = "equipment_rules", label = "Equipment" }, { id = "extras", label = "Extras" },
  } },
  { id = "automation", label = "Automation", tabs = {
    { id = "tools", label = "Tools" }, { id = "utilities", label = "Scripts" },
    { id = "combo", label = "Combo" }, { id = "alarms", label = "Alarms" },
    { id = "pushmax", label = "Push" }, { id = "depositer", label = "Depositer" },
  } },
  { id = "settings_category", label = "Settings", tabs = {
    { id = "profiles", label = "Profiles" }, { id = "settings", label = "Interface" },
    { id = "diagnostics", label = "Diagnostics" },
  } },
}

local ROUTE_OWNER = { more = "overview" }
for _, category in ipairs(CATEGORIES) do
  ROUTE_OWNER[category.id] = category.id
  for _, tab in ipairs(category.tabs) do ROUTE_OWNER[tab.id] = category.id end
end

local function registry() return nExBot.UI.ModuleRegistry end
local function cockpit() return nExBot.UI.Cockpit end

local function categoryById(id)
  for _, category in ipairs(CATEGORIES) do
    if category.id == id then return category end
  end
end

local function hostContentsPanel()
  return modules and modules.game_bot and modules.game_bot.contentsPanel or nil
end

local function findTabNavigation(host)
  for _, key in ipairs({ "botTabs", "tabBar", "tabs" }) do
    if host[key] then return host[key] end
  end
  if host.recursiveGetChildById then
    for _, id in ipairs({ "botTabs", "tabBar", "tabs" }) do
      local tabs = host:recursiveGetChildById(id)
      if tabs then return tabs end
    end
  end
end

local function hideHostToolbar(host)
  local controls = {}
  for _, key in ipairs({ "config", "edit", "enabled", "enable", "onOff" }) do
    local control = host[key]
    local controlType = type(control)
    if (controlType == "table" or controlType == "userdata") and type(control.getParent) == "function" then
      controls[#controls + 1] = control
    end
  end
  if #controls == 0 then return end

  local parent = controls[1]:getParent()
  local ownsBotPanel = parent and parent.recursiveGetChildById
    and parent:recursiveGetChildById("botPanel") == host.botPanel
  if parent and parent ~= host and parent ~= host.botPanel and not ownsBotPanel then
    if parent.setVisible then parent:setVisible(false) end
    if parent.setEnabled then parent:setEnabled(false) end
    return
  end
  for _, control in ipairs(controls) do
    if control.setVisible then control:setVisible(false) end
    if control.setEnabled then control:setEnabled(false) end
  end
end

local function clearHostSurface(host, ownedController)
  if not host or not host.botPanel then return false end
  hideHostToolbar(host)
  local removed = false
  local children = {}
  for i, child in ipairs(host.botPanel:getChildren()) do children[i] = child end
  for _, child in ipairs(children) do
    if child ~= ownedController then
      child:destroy()
      removed = true
    end
  end
  local tabs = findTabNavigation(host)
  if tabs then
    if tabs.setVisible then tabs:setVisible(false) end
    if tabs.setEnabled then tabs:setEnabled(false) end
  end
  return removed
end

local function controllerRevision(view)
  local parts = { view.character, view.profile }
  for _, engine in ipairs(view.engines or {}) do
    parts[#parts + 1] = engine.id
    parts[#parts + 1] = engine.statusText
  end
  for i, value in ipairs(parts) do parts[i] = tostring(value or "-") end
  return table.concat(parts, "|")
end

local function createShell(opts)
  local self = {
    id = "botshell", lifecycle = Lifecycle.new("botshell"), root = opts.root,
    host = nil, window = nil, workspace = nil, controller = nil, content = nil,
    tabs = nil, nav = nil, selectedId = "cockpit", selectedCategory = "overview",
    _density = storage and storage.uiDensity or "default", active = true, panelMode = false, history = {},
  }
  Components.setDensity(self._density)

  function self:getWindow() return self.window end
  function self:getWorkspace() return self.workspace end
  function self:getHeader() return self.tabs end
  function self:getContent() return self.content end
  function self:getFooter() return nil end
  function self:selected() return self.selectedId end
  function self:current() return self.selectedId end
  function self:canGoBack() return #self.history > 0 end
  function self:density() return self._density end
  function self:setDensity(value)
    if not DENSITIES[value] then return false end
    self._density = value
    Components.setDensity(value)
    if storage then storage.uiDensity = value end
    -- Re-select the current tab so nav/tab chrome (built at density-dependent
    -- heights) and the content pane all pick up the new density immediately,
    -- not just on the next navigation.
    if self.workspace and self.workspace:isVisible() then self:select(self.selectedId) end
    return true
  end
  function self:isPanelMode() return self.panelMode end
  function self:defer(callback, delay)
    if not self.active or type(callback) ~= "function" then return false end
    local guarded = self.lifecycle:guard(callback)
    if scheduleEvent then scheduleEvent(guarded, delay or 0) else guarded() end
    return true
  end

  local function run(actionId, parent)
    local ok, reason = nExBot.UI.Actions.run(actionId)
    if ok or not parent then return end
    local warning = parent:recursiveGetChildById("controllerError")
    local message = nExBot.UI.Actions.userMessage(actionId, reason)
    if warning then warning:setText(message) else
      warning = Components.inlineWarning(parent, { message = message })
      warning:setId("controllerError")
    end
  end

  function self:renderController(view)
    if not self.controller then return end
    self.controller:destroyChildren()
    Components.label(self.controller, { id = "controllerTitle", text = "nExBot", textStyle = "windowTitle" })
    Components.label(self.controller, {
      id = "controllerProfile", text = (view.character or "-") .. " / " .. (view.profile or "-"), textStyle = "metadata",
    })
    for _, engine in ipairs(view.engines or {}) do
      local engineRow = engine
      local row = g_ui.createWidget("NexControllerEngine", self.controller)
      row:setId(engineRow.id)
      local item = g_ui.createWidget("NexControllerItem", row)
      item:setId(engineRow.id .. "Item")
      item:setItemId(engineRow.itemId)
      Components.label(row, { id = engineRow.id .. "Label", text = engineRow.label, style = "NexControllerLabel" })
      Components.toggle(row, {
        id = engineRow.toggleAction,
        value = engineRow.status == "ACTIVE",
        tooltip = "Toggle " .. engineRow.label,
        onChange = function() run(engineRow.toggleAction, self.controller) end,
      })
      Components.button(row, {
        id = "configure_" .. engineRow.id, text = "", style = "NexControllerConfigure",
        tooltip = "Configure " .. engineRow.label,
        onClick = function() run(engineRow.editorAction, self.controller) end,
      })
    end
    Components.button(self.controller, {
      id = "openWorkspace", text = "Open nExBot", style = "NexControllerOpen",
      onClick = function() self:select(self.selectedId or "cockpit") end,
    })
  end

  local function buildController(root)
    self.controller = g_ui.createWidget("NexControllerContent", root)
    self.controller:setId("controller")
    local module = cockpit()
    local view = module and module.statusProvider and module.statusProvider().snapshot
      or { character = "-", profile = "-", engines = {} }
    self:renderController(view)
    self._controllerRevision = controllerRevision(view)
  end

  local function renderNavigation()
    self.nav:destroyChildren()
    for _, category in ipairs(CATEGORIES) do
      local definition = category
      local button = Components.button(self.nav, {
        id = "nav_" .. definition.id, text = definition.label, style = "NexNavButton",
        onClick = function() self:select(definition.tabs[1].id) end,
      })
      button:setChecked(definition.id == self.selectedCategory)
    end
  end

  local function renderTabs()
    self.tabs:destroyChildren()
    local category = categoryById(self.selectedCategory)
    local tabs = category and category.tabs or {}
    local selectedModule = registry().get(self.selectedId)
    if self.breadcrumb then
      self.breadcrumb:setText(selectedModule and selectedModule.breadcrumb or ((category and category.label or "nExBot") .. " / Dashboard"))
    end
    if self.backButton then self.backButton:setEnabled(self:canGoBack()) end
    if self.compactNavigation then
      local select = g_ui.createWidget("NexTabSelect", self.tabs)
      select:setId("pageSelect")
      local selectedLabel
      for _, tab in ipairs(tabs) do
        select:addOption(tab.label, tab.id)
        if tab.id == self.selectedId then selectedLabel = tab.label end
      end
      if selectedLabel then select:setCurrentOption(selectedLabel) end
      select.onOptionChange = function(_, text, id)
        if not id then
          for _, tab in ipairs(tabs) do
            if tab.label == text then
              id = tab.id
              break
            end
          end
        end
        if id and id ~= self.selectedId then self:push(id) end
      end
      return
    end
    local tabsWidth = self.workspace and self.workspace.getWidth and self.workspace:getWidth() - 120 or 292
    local tabWidth = math.max(44, math.floor((tabsWidth - math.max(0, #tabs - 1) * 2) / math.max(1, #tabs)))
    for _, tab in ipairs(tabs) do
      local definition = tab
      local button = Components.button(self.tabs, {
        id = "tab_" .. definition.id, text = definition.label, style = "NexTabButton",
        onClick = function() self:select(definition.id) end,
      })
      button:setWidth(tabWidth)
      button:setChecked(definition.id == self.selectedId)
    end
  end

  local function buildWorkspace()
    if self.workspace and not (self.workspace.isDestroyed and self.workspace:isDestroyed()) then return end
    self.workspace = UI.createWindow("NexWorkspace", self.root)
    self.workspace:setId("NexWorkspace")
    local rootWidth = self.root and self.root.getWidth and self.root:getWidth() or 0
    local rootHeight = self.root and self.root.getHeight and self.root:getHeight() or 0
    local workspaceWidth = rootWidth > 0 and math.min(620, math.max(320, rootWidth - 16)) or 440
    local workspaceHeight = rootHeight > 0 and math.min(520, math.max(240, rootHeight - 16)) or 400
    self.workspace:setWidth(workspaceWidth)
    self.workspace:setHeight(workspaceHeight)
    self._lastCompactState = rootWidth > 0 and workspaceWidth < 520
    self.compactNavigation = self._lastCompactState
    self.nav = g_ui.createWidget("NexWorkspaceNav", self.workspace)
    self.nav:setId("workspaceNav")
    if self.compactNavigation then self.nav:setWidth(82) end
    self.topbar = g_ui.createWidget("NexWorkspaceTopbar", self.workspace)
    self.topbar:setId("workspaceTopbar")
    self.breadcrumb = g_ui.createWidget("NexBreadcrumb", self.topbar)
    self.breadcrumb:setId("breadcrumb")
    self.tabs = g_ui.createWidget("NexWorkspaceTabs", self.workspace)
    self.tabs:setId("workspaceTabs")
    local scroll = g_ui.createWidget("NexWorkspaceScrollBar", self.workspace)
    scroll:setId("workspaceScroll")
    self.content = g_ui.createWidget("NexWorkspaceContent", self.workspace)
    self.content:setId("workspaceContent")
    local back = g_ui.createWidget("NexBackButton", self.topbar)
    back:setId("shellBack")
    back:setTooltip("Back")
    back.onClick = function() self:back() end
    self.backButton = back
    local close = g_ui.createWidget("NexCloseButton", self.workspace)
    close:setId("closeButton")
    close:setTooltip("Close")
    close.onClick = function() self.workspace:hide() end

    -- Responsive resize: recalculate layout when the parent window changes size.
    self.workspace.onResize = function(_, width, height)
      if not width or not height or not self.nav or not self.tabs then return end
      local w = math.min(620, math.max(320, width - 16))
      local h = math.min(520, math.max(240, height - 16))
      self.workspace:setWidth(w)
      self.workspace:setHeight(h)
      local compact = w < 520
      if compact ~= self._lastCompactState then
        self._lastCompactState = compact
        self.compactNavigation = compact
        if self.nav then self.nav:setWidth(compact and 82 or 104) end
        renderNavigation()
        renderTabs()
      end
    end

    -- Keyboard navigation: Tab cycles focus, Escape closes workspace.
    self.workspace.onKeyPress = function(_, code)
      if code == KeyEscape then
        self.workspace:hide()
        return true
      end
      if code == KeyTab then
        local children = self.workspace:getChildren()
        if #children == 0 then return false end
        local focused = self.workspace:getFocusedChild()
        local startIndex = 1
        if focused then
          for i, child in ipairs(children) do
            if child == focused then startIndex = (i % #children) + 1 break end
          end
        end
        for offset = 0, #children - 1 do
          local candidate = children[((startIndex - 1 + offset) % #children) + 1]
          if candidate.focusable then
            candidate:setFocus()
            return true
          end
        end
        return false
      end
      return false
    end

    -- Touch auto-detection: switch to touch density on first open if no user override.
    if not self._touchChecked and g_platform and g_platform.getSystemInfo then
      self._touchChecked = true
      local ok, info = pcall(g_platform.getSystemInfo)
      if ok and info and info.touchable and self._density == "default" then
        self:setDensity("touch")
      end
    end
  end

  function self:open()
    if self.window and not (self.window.isDestroyed and self.window:isDestroyed()) then return self end
    local host = hostContentsPanel()
    if host and host.botPanel then
      self.host, self.panelMode = host, true
      clearHostSurface(host)
      self.window = g_ui.createWidget("NexControllerLayout", host.botPanel)
    else
      self.window = UI.createWindow("NexControllerWindow", self.root)
      self.window:setWidth(Tokens.dimensions.minWidth)
      self.window:setHeight(240)
      local close = g_ui.createWidget("NexCloseButton", self.window)
      close:setId("closeButton")
      close:setTooltip("Close")
      close.onClick = function() self.window:hide() end
    end
    self.window:setId("NexBotController")
    buildController(self.window)
    self.window:show()
    return self
  end

  function self:raise()
    if self.workspace and self.workspace.show then self.workspace:show() end
    if self.workspace and self.workspace.raise then self.workspace:raise() end
  end

  function self:renderCurrent()
    if not self.active or not self.content then return end
    Perf.begin("module_render")
    self.content:destroyChildren()
    if self.selectedId == "cockpit" then
      cockpit().render(self.content)
    else
      local module = registry().get(self.selectedId)
      if module and module.render then module.render(self, self.content, self.lifecycle)
      else Components.emptyState(self.content, { message = "This feature is not available." }) end
    end
    Perf.end_("module_render")
  end

  function self:select(id)
    if not self.active then return false end
    local owner = ROUTE_OWNER[id]
    if not owner then return false end
    local category = categoryById(owner)
    if id == owner or id == "more" then id = category.tabs[1].id end
    buildWorkspace()
    self.selectedCategory, self.selectedId = owner, id
    renderNavigation()
    renderTabs()
    self:renderCurrent()
    self.workspace:show()
    self.workspace:raise()
    return true
  end

  function self:push(id)
    if self.selectedId and self.selectedId ~= id then
      self.history[#self.history + 1] = self.selectedId
      if #self.history > 32 then table.remove(self.history, 1) end
    end
    return self:select(id)
  end
  function self:replace(id) return self:select(id) end
  function self:back()
    local id = table.remove(self.history)
    if not id then return false end
    return self:select(id)
  end
  function self:home() return self:push("cockpit") end

  function self:onTick()
    return self.lifecycle:guard(function()
      local module = cockpit()
      if not module or not module.statusProvider then return end
      local view = module.statusProvider().snapshot
      local revision = controllerRevision(view)
      if revision == self._controllerRevision then return end
      self._controllerRevision = revision
      self:renderController(view)
      if self.selectedId == "cockpit" and self.workspace and self.workspace:isVisible() then self:renderCurrent() end
    end)
  end

  function self:tick()
    self._tickCallback = self._tickCallback or self:onTick()
    return self._tickCallback()
  end

  function self:setupHostHooks()
    if not self.active or not self.panelMode then return end
    local host = hostContentsPanel()
    if not host or not host.botPanel then return end
    if self.window and self.window:getParent() == host.botPanel then clearHostSurface(host, self.window); return end
    clearHostSurface(host)
    if self.window then self.window:destroy() end
    self.window = g_ui.createWidget("NexControllerLayout", host.botPanel)
    self.window:setId("NexBotController")
    buildController(self.window)
    self.window:show()
  end

  function self:destroy()
    if not self.active then return end
    self.active = false
    self.lifecycle:advance()
    if self.workspace then self.workspace:destroy() end
    if self.window then self.window:destroy() end
    self.host, self.window, self.workspace, self.controller = nil, nil, nil, nil
    self.topbar, self.breadcrumb, self.backButton = nil, nil, nil
    self.content, self.tabs, self.nav, self.selectedId, self.selectedCategory = nil, nil, nil, nil, nil
    self.history = {}
    if current == self then current = nil end
  end

  return self
end

function Shell.new(opts)
  if current then return current end
  current = createShell(opts or {})
  return current
end

function Shell.instance() return current end
function Shell.count() return current and 1 or 0 end

function Shell.show(moduleId)
  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget()
  local shell = Shell.new({ root = root })
  shell:open()
  if moduleId then shell:select(moduleId) end
  return shell
end

function Shell.select(moduleId)
  local shell = Shell.instance() or Shell.show()
  if shell:select(moduleId) then return shell end
end

function Shell.reset()
  if current then current:destroy() end
  current = nil
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.Shell = Shell
end

return Shell
