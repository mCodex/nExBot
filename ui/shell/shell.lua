--[[
  BotShell — the nExBot product shell. Renders INTO the host client's left
  bot panel (modules.game_bot.contentsPanel.botPanel), replacing the old
  tab-fill navigation with a module sidebar. A floating-window fallback is
  used only when the host panel is unavailable (e.g. tests).

  Layout inside the left panel:
    sidebar (module rail from ModuleRegistry) | header (profile/session) + content
  Exactly one controller instance per process; opening twice returns the same
  shell. All delayed callbacks are generation-guarded through UiLifecycle.
]]

local Lifecycle = (nExBot and nExBot.UI and nExBot.UI["ui.core.lifecycle"]) or (type(require) == "function" and require("ui.core.lifecycle"))
local Components = (nExBot and nExBot.UI and nExBot.UI["ui.components.components"]) or (type(require) == "function" and require("ui.components.components"))
local Tokens = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.tokens"]) or (type(require) == "function" and require("ui.design_system.tokens"))
local Status = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.status"]) or (type(require) == "function" and require("ui.design_system.status"))
local Density = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.density"]) or (type(require) == "function" and require("ui.design_system.density"))
local Typography = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.typography"]) or (type(require) == "function" and require("ui.design_system.typography"))
local Perf = (nExBot and nExBot.UI and nExBot.UI["ui.core.perf"]) or (type(require) == "function" and require("ui.core.perf"))

local Shell = {}
local current = nil

local function registry()
  return nExBot.UI.ModuleRegistry
end

local function icons()
  return nExBot.UI.IconRegistry
end

-- Locate the host's left bot panel (contentsPanel.botPanel). The BotTabBar is
-- hidden because the module sidebar replaces it.
local function hostContentsPanel()
  local modulesTbl = modules
  if not modulesTbl or not modulesTbl.game_bot then return nil end
  local cp = modulesTbl.game_bot.contentsPanel
  if not cp then return nil end
  return cp
end

-- Hide the legacy tab UI instead of destroying it. The module engines (CaveBot,
-- TargetBot, ...) hold direct references to widgets inside those tab panels
-- (e.g. CaveBot.actionList = ui.list) and write to them every tick; destroying
-- them would dangle those references. Hiding keeps the engines running while
-- the shell becomes the visible surface. Returns true if any panel was hidden.
local function hideLegacyTabs(host)
  if not host or not host.botPanel then return false end
  local hidden = false
  for _, child in ipairs(host.botPanel:getChildren()) do
    if child ~= current and (not child:getId() or child:getId() ~= "NexBotShell") then
      if child.setVisible then child:setVisible(false) end
      hidden = true
    end
  end
  if host.botTabs and host.botTabs.setVisible then
    host.botTabs:setVisible(false)
  end
  return hidden
end

local function createShell(opts)
  local self = {
    id = "botshell",
    lifecycle = Lifecycle.new("botshell"),
    root = opts.root,
    host = nil,        -- host contentsPanel when attached to the left bar
    window = nil,      -- floating window (fallback) or the root layout panel
    sidebar = nil,
    header = nil,
    content = nil,
    footer = nil,
    selectedId = nil,
    density = "default",
    active = true,
    panelMode = false,
  }

  local function currentModule()
    local id = self.selectedId
    if not id then return nil end
    return registry().get(id)
  end

  function self:getWindow() return self.window end
  function self:getSidebar() return self.sidebar end
  function self:getHeader() return self.header end
  function self:getContent() return self.content end
  function self:getFooter() return self.footer end
  function self:selected() return self.selectedId end
  function self:density() return self.density end
  function self:isPanelMode() return self.panelMode end
  function self:raise()
    if self.window and self.window.raise then self.window:raise() end
    if self.window and self.window.show then self.window:show() end
  end

  local function buildShell(w)
    -- Sidebar (left rail)
    local sidebar = g_ui.createWidget("NexSidebar", w)
    sidebar:setId("sidebar")
    self.sidebar = sidebar
    for _, module in ipairs(registry().list()) do
      local item = g_ui.createWidget("NexSidebarItem", sidebar)
      item:setId(module.id)
      item:setText(module.label)
      item:setColor(Tokens.colors.text.secondary)
      item:setImageSource(icons().resolve(module.icon, 16))
      item:setOnClick(function()
        self:select(module.id)
      end)
    end

    -- Right column: header / content / footer
    local right = g_ui.createWidget("NexShellRight", w)
    right:setId("right")

    local header = g_ui.createWidget("NexHeader", right)
    header:setId("header")
    self.header = header
    Components.label(header, "nExBot", { id = "brand", textStyle = "windowTitle", color = Tokens.colors.text.primary })
    Components.label(header, "", { id = "profile", textStyle = "metadata", color = Tokens.colors.text.muted })
    Components.statusBadge(header, { id = "session", status = "INFO", text = "…" })

    local content = g_ui.createWidget("NexContent", right)
    content:setId("content")
    self.content = content

    local footer = g_ui.createWidget("NexFooter", right)
    footer:setId("footer")
    self.footer = footer
    Components.button(footer, { text = "Settings", id = "footerSettings", variant = "ghost" })
    Components.button(footer, { text = "Close", id = "footerClose", variant = "ghost", onClick = function()
      self:destroy()
    end })
  end

  function self:open()
    local host = hostContentsPanel()
    if host and host.botPanel then
      -- Attach directly into the host left panel. The legacy tab UI is hidden
      -- (kept alive for the module engines) and the sidebar becomes the sole
      -- visible navigation surface.
      self.host = host
      self.panelMode = true
      hideLegacyTabs(host)
      local root = g_ui.createWidget("NexShellLayout", host.botPanel)
      root:setId("NexBotShell")
      self.window = root
      buildShell(root)
      root:show()
      return self
    end

    -- Fallback: floating window (tests / host unavailable).
    local w = UI.createWindow("NexBotShell", self.root)
    w:setId("NexBotShell")
    w:setWidth(Tokens.dimensions.sidebarWidth + 420)
    w:setHeight(600)
    self.window = w
    buildShell(w)
    w:show()
    return self
  end

  function self:select(id)
    if not self.active then return false end
    local module = registry().get(id)
    if not module then return false end
    self.selectedId = id
    -- highlight selected item, clear others
    if self.sidebar then
      for _, child in ipairs(self.sidebar:getChildren()) do
        if child.getId then
          child:setColor(child:getId() == id and Tokens.colors.accent.primary or Tokens.colors.text.secondary)
        end
      end
    end
    self:renderCurrent()
    return true
  end

  function self:renderCurrent()
    local module = currentModule()
    if not module then return end
    if not self.active then return end
    if not self.content then return end
    Perf.begin("module_render")
    -- clear previous module content
    self.content:destroyChildren()
    if module.render then
      module.render(self, self.content, self.lifecycle)
    else
      Components.emptyState(self.content, { message = module.label .. " has no page yet." })
    end
    Perf.end_("module_render")
  end

  -- Tick callback used by the unified scheduler; generation-guarded.
  -- Updates only the header status badge when the module's revision changed;
  -- content is rebuilt only on select(). Unchanged state -> zero widget writes.
  function self:onTick()
    return self.lifecycle:guard(function()
      local module = currentModule()
      if not module then return end
      if not self.active then return end
      if not module.statusProvider then return end
      local status = module.statusProvider()
      local revision = type(status) == "table" and status.revision or 0
      if revision ~= self._statusRevision then
        self._statusRevision = revision
        local header = status and status.header
        if header then
          self:setSession(header.status, header.statusText)
        end
      end
    end)
  end

  function self:setSession(status, text)
    if not self.header then return end
    local badge = self.header:recursiveGetChildById("session")
    if badge then
      badge:setText(text or status or "")
      badge:setColor(Status.color(status))
    end
  end

  function self:setProfile(name)
    if not self.header then return end
    local p = self.header:recursiveGetChildById("profile")
    if p then p:setText(name or "") end
  end

  -- Re-attach hook for when the host framework re-runs (reload/game start):
  -- if the host rebuilt its botPanel, re-create the shell layout inside it.
  -- Idempotent: if already attached to the current botPanel, this is a no-op.
  function self:setupHostHooks()
    if not self.active then return end
    if not self.panelMode then return end
    local host = hostContentsPanel()
    if not host or not host.botPanel then return end
    if self.window and self.window:getParent() == host.botPanel then
      -- already attached: just re-hide any legacy panels the framework added
      hideLegacyTabs(host)
      return
    end
    -- host rebuilt the panel: re-create our layout into it
    hideLegacyTabs(host)
    local root = g_ui.createWidget("NexShellLayout", host.botPanel)
    root:setId("NexBotShell")
    if self.window and self.window.destroy then self.window:destroy() end
    self.window = root
    buildShell(root)
    root:show()
    if self.selectedId then self:select(self.selectedId) end
  end

  function self:destroy()
    if not self.active then return end
    self.active = false
    self.lifecycle:advance()
    if self.window then
      self.window:destroy()
    end
    self.host = nil
    self.window = nil
    self.sidebar = nil
    self.header = nil
    self.content = nil
    self.footer = nil
    self.selectedId = nil
    if current == self then current = nil end
  end

  return self
end

function Shell.new(opts)
  if current then return current end
  current = createShell(opts or {})
  return current
end

function Shell.instance()
  return current
end

function Shell.count()
  return current and 1 or 0
end

-- Open (or raise) the shell and select a module. Renders into the host left
-- panel when available; otherwise falls back to a floating window.
function Shell.show(moduleId)
  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget()
  local shell = Shell.new({ root = root })
  shell:open()
  shell:raise()
  if moduleId then shell:select(moduleId) end
  -- default to the first registered module so the shell never opens blank
  if not shell:selected() then
    local ids = nExBot.UI.ModuleRegistry.ids()
    if ids and #ids > 0 then shell:select(ids[1]) end
  end
  return shell
end

function Shell.select(moduleId)
  local shell = Shell.instance()
  if shell and shell:select(moduleId) then return shell end
  return Shell.show(moduleId)
end

-- test hook
function Shell.reset()
  if current then current:destroy() end
  current = nil
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.Shell = Shell
end

return Shell
