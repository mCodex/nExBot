-- Compact hunt controller plus one shallow configuration workspace.

local Lifecycle = (nExBot and nExBot.UI and nExBot.UI["ui.core.lifecycle"]) or (type(require) == "function" and require("ui.core.lifecycle"))
local Components = (nExBot and nExBot.UI and nExBot.UI["ui.components.components"]) or (type(require) == "function" and require("ui.components.components"))
local Tokens = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.tokens"]) or (type(require) == "function" and require("ui.design_system.tokens"))
local Perf = (nExBot and nExBot.UI and nExBot.UI["ui.core.perf"]) or (type(require) == "function" and require("ui.core.perf"))

local Shell = {}
local current

local CATEGORIES = {
  { id = "overview", label = "Overview", tabs = {
    { id = "cockpit", label = "Status" }, { id = "intelligence", label = "AI" }, { id = "analytics", label = "Analyzer" },
  } },
  { id = "hunt", label = "Hunt", tabs = {
    { id = "cavebot", label = "Route" }, { id = "targetbot", label = "Target" },
    { id = "looting", label = "Loot" }, { id = "supplies", label = "Supplies" },
  } },
  { id = "character", label = "Character", tabs = {
    { id = "healing", label = "Healing" }, { id = "safety", label = "Conditions" },
    { id = "equipment", label = "Equipment" },
  } },
  { id = "automation", label = "Automation", tabs = {
    { id = "tools", label = "Tools" }, { id = "utilities", label = "Scripts" },
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
    density = "default", active = true, panelMode = false,
  }

  function self:getWindow() return self.window end
  function self:getWorkspace() return self.workspace end
  function self:getHeader() return self.tabs end
  function self:getContent() return self.content end
  function self:getFooter() return nil end
  function self:selected() return self.selectedId end
  function self:current() return self.selectedId end
  function self:canGoBack() return false end
  function self:density() return self.density end
  function self:isPanelMode() return self.panelMode end

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
      Components.button(row, {
        id = engineRow.toggleAction, text = engineRow.statusText, style = "NexControllerToggle",
        variant = engineRow.status == "ACTIVE" and "active" or "inactive",
        onClick = function() run(engineRow.toggleAction, self.controller) end,
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
    local tabWidth = math.floor((292 - math.max(0, #tabs - 1) * 2) / math.max(1, #tabs))
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
    self.nav = g_ui.createWidget("NexWorkspaceNav", self.workspace)
    self.nav:setId("workspaceNav")
    self.tabs = g_ui.createWidget("NexWorkspaceTabs", self.workspace)
    self.tabs:setId("workspaceTabs")
    local scroll = g_ui.createWidget("NexWorkspaceScrollBar", self.workspace)
    scroll:setId("workspaceScroll")
    self.content = g_ui.createWidget("NexWorkspaceContent", self.workspace)
    self.content:setId("workspaceContent")
    local close = g_ui.createWidget("NexCloseButton", self.workspace)
    close:setId("closeButton")
    close.onClick = function() self.workspace:hide() end
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

  function self:push(id) return self:select(id) end
  function self:replace(id) return self:select(id) end
  function self:back() return false end
  function self:home() return self:select("cockpit") end

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
    self.content, self.tabs, self.nav, self.selectedId, self.selectedCategory = nil, nil, nil, nil, nil
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
