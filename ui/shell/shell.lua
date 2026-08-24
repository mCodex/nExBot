--[[
  BotShell — compact hunt cockpit rendered into the host client's left bot
  panel. Workflows navigate inside the shell; detailed editors stay modal.
  A floating-window fallback is used only when the host panel is unavailable.
  Exactly one controller instance per process; opening twice returns the same
  shell. All delayed callbacks are generation-guarded through UiLifecycle.
]]

local Lifecycle = (nExBot and nExBot.UI and nExBot.UI["ui.core.lifecycle"]) or (type(require) == "function" and require("ui.core.lifecycle"))
local Components = (nExBot and nExBot.UI and nExBot.UI["ui.components.components"]) or (type(require) == "function" and require("ui.components.components"))
local Tokens = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.tokens"]) or (type(require) == "function" and require("ui.design_system.tokens"))
local Perf = (nExBot and nExBot.UI and nExBot.UI["ui.core.perf"]) or (type(require) == "function" and require("ui.core.perf"))

local Shell = {}
local current = nil

local function registry()
  return nExBot.UI.ModuleRegistry
end

local function cockpit()
  return nExBot.UI.Cockpit
end

-- Locate the host's left bot panel. The legacy BotTabBar is replaced by the cockpit.
local function hostContentsPanel()
  local modulesTbl = modules
  if not modulesTbl or not modulesTbl.game_bot then return nil end
  local cp = modulesTbl.game_bot.contentsPanel
  if not cp then return nil end
  return cp
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
  return nil
end

-- Detach the legacy tab UI instead of destroying it. The module engines
-- (CaveBot, TargetBot, ...) hold direct references to widgets inside those
-- tab panels (e.g. CaveBot.actionList = ui.list) and write to them every
-- tick; destroying (:destroy()) them would dangle those references. Removing
-- them from the widget tree (:removeChild()) is safe -- it only unparents the
-- widget, it does not destroy it -- and keeps the engines running while the
-- shell becomes the visible surface.
--
-- This must be a real removal, not just setVisible(false): the host's
-- UITabBar:selectTab (corelib/ui/uitabbar.lua) swaps tabs by checking
-- contentWidget:getLastChild().isTab and only evicts that one panel. Once our
-- shell is added as botPanel's new last child (not .isTab), a merely-hidden
-- legacy tab panel is never evicted, so a later addChild for that same panel
-- collides ("attempt to add a child again into a UIWidget"). Removing the
-- children outright avoids the collision entirely and keeps this idempotent.
local function hideLegacyTabs(host)
  if not host or not host.botPanel then return false end
  local hidden = false
  -- getChildren() returns the panel's live children array; removeChild()
  -- mutates that same array in place, so removing while iterating it
  -- directly would skip every other entry. Snapshot first, then remove.
  local snapshot = {}
  for i, child in ipairs(host.botPanel:getChildren()) do
    snapshot[i] = child
  end
  for _, child in ipairs(snapshot) do
    if child ~= current and (not child:getId() or child:getId() ~= "NexBotShell") then
      if host.botPanel.removeChild then host.botPanel:removeChild(child) end
      hidden = true
    end
  end
  local tabs = findTabNavigation(host)
  if tabs then
    -- Belt-and-suspenders: OTClient's click-release path checks isEnabled()
    -- and containsPoint(), never isVisible() -- so a tab button pressed just
    -- before/while hiding can still fire onClick afterward. Disabling the
    -- tab bar (cascades to its tab buttons) blocks that independently of the
    -- removal above.
    if tabs.setVisible then tabs:setVisible(false) end
    if tabs.setEnabled then tabs:setEnabled(false) end
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
    header = nil,
    content = nil,
    footer = nil,
    selectedId = nil,
    history = {},
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
  function self:getHeader() return self.header end
  function self:getContent() return self.content end
  function self:getFooter() return self.footer end
  function self:selected() return self.selectedId end
  function self:current() return self.selectedId end
  function self:canGoBack() return #self.history > 1 end
  function self:density() return self.density end
  function self:isPanelMode() return self.panelMode end
  function self:raise()
    if self.window and self.window.raise then self.window:raise() end
    if self.window and self.window.show then self.window:show() end
  end

  local function buildShell(w)
    local header = g_ui.createWidget("NexShellHeader", w)
    header:setId("header")
    self.header = header
    Components.button(header, { text = "<", id = "shellBack", style = "NexHeaderButton", onClick = function() self:back() end })
    Components.label(header, { text = "Hunt", id = "shellTitle", style = "NexShellTitle", textStyle = "moduleTitle" })
    Components.button(header, { text = "Home", id = "shellHome", style = "NexHeaderHome", variant = "ghost", onClick = function() self:home() end })

    local content = g_ui.createWidget("NexContent", w)
    content:setId("content")
    self.content = content

    local footer = g_ui.createWidget("NexCockpitFooter", w)
    footer:setId("footer")
    self.footer = footer
    Components.button(footer, { text = "Profile", id = "footerProfile", style = "NexFooterButton", variant = "ghost", onClick = function() self:select("profiles") end })
    Components.button(footer, { text = "Pause", id = "pause_all", style = "NexFooterButton", variant = "danger", onClick = function()
      local ok, reason = nExBot.UI.Actions.run("pause_all")
      if not ok then
        local attention = self.content and self.content:recursiveGetChildById("attention")
        if attention then attention:setText(reason or "Could not pause") end
      end
    end })
    Components.button(footer, { text = "More", id = "footerMore", style = "NexFooterButton", variant = "ghost", onClick = function() self:select("more") end })
  end

  function self:open()
    if self.window and not (self.window.isDestroyed and self.window:isDestroyed()) then return self end
    local host = hostContentsPanel()
    if host and host.botPanel then
      -- Attach directly into the host left panel. The legacy tab UI is hidden
      -- (kept alive for the module engines) and the cockpit becomes the sole
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
    w:setWidth(Tokens.dimensions.minWidth)
    w:setHeight(600)
    self.window = w
    buildShell(w)
    w:show()
    return self
  end

  function self:select(id)
    return self:push(id)
  end

  local function canNavigate(id)
    return id == "cockpit" or id == "more" or registry().get(id) ~= nil
  end

  function self:push(id, params)
    if not self.active then return false end
    if not canNavigate(id) then return false end
    local currentEntry = self.history[#self.history]
    if not currentEntry or currentEntry.id ~= id then
      self.history[#self.history + 1] = { id = id, params = params }
    end
    self.selectedId = id
    self:renderCurrent()
    return true
  end

  function self:replace(id, params)
    if not self.active or not canNavigate(id) then return false end
    local index = #self.history > 0 and #self.history or 1
    self.history[index] = { id = id, params = params }
    self.selectedId = id
    self:renderCurrent()
    return true
  end

  function self:back()
    if not self:canGoBack() then return false end
    table.remove(self.history)
    self.selectedId = self.history[#self.history].id
    self:renderCurrent()
    return true
  end

  function self:home()
    if not self.active then return false end
    self.history = { { id = "cockpit" } }
    self.selectedId = "cockpit"
    self:renderCurrent()
    return true
  end

  local function renderMore(content)
    Components.label(content, { text = "More", id = "moreTitle", textStyle = "moduleTitle" })
    local destinations = {
      { id = "cavebot", label = "Cave" },
      { id = "targetbot", label = "Target" },
      { id = "healing", label = "Heal" },
      { id = "looting", label = "Loot" },
      { id = "supplies", label = "Supplies" },
      { id = "scripts", label = "Scripts", action = "open_script_editor" },
      { id = "intelligence", label = "AI Intelligence" },
      { id = "diagnostics", label = "Diagnostics" },
      { id = "settings", label = "Settings" },
    }
    for _, destination in ipairs(destinations) do
      local item = destination
      Components.button(content, {
        id = "more_" .. item.id,
        text = item.label,
        variant = "ghost",
        onClick = function()
          if item.action then
            local ok, reason = nExBot.UI.Actions.run(item.action)
            if not ok then
              Components.inlineWarning(content, { id = "moreError", message = reason or "Window unavailable" })
            end
          else
            self:select(item.id)
          end
        end,
      })
    end
  end

  function self:renderCurrent()
    if not self.active then return end
    if not self.content then return end
    Perf.begin("module_render")
    self.content:destroyChildren()
    local module = currentModule()
    local title = self.header and self.header:recursiveGetChildById("shellTitle")
    if title then title:setText(module and module.label or (self.selectedId == "more" and "More" or "Hunt")) end
    local back = self.header and self.header:recursiveGetChildById("shellBack")
    if back then back:setEnabled(self:canGoBack()) end
    if self.selectedId == "cockpit" then
      cockpit().render(self.content)
    elseif self.selectedId == "more" then
      renderMore(self.content)
    elseif module and module.render then
      module.render(self, self.content, self.lifecycle)
    elseif module then
      Components.emptyState(self.content, { message = module.label .. " has no page yet." })
    end
    Perf.end_("module_render")
  end

  -- Tick callback used by the unified scheduler. Unchanged state causes no writes.
  function self:onTick()
    return self.lifecycle:guard(function()
      if self.selectedId ~= "cockpit" then return end
      local view = cockpit().statusProvider().snapshot
      local parts = {
        tostring(view.character or ""), tostring(view.profile or ""), tostring(view.route or ""),
        tostring(view.waypoint or ""), tostring(view.targetName or ""), tostring(view.targetHp or ""), tostring(view.hp or ""),
        tostring(view.mana or ""), tostring(view.xpHour or ""), tostring(view.attention or ""),
      }
      for _, engine in ipairs(view.engines) do
        parts[#parts + 1] = tostring(engine.status or "")
        parts[#parts + 1] = tostring(engine.detail or "")
      end
      local revision = table.concat(parts, "|")
      if revision ~= self._statusRevision then
        self._statusRevision = revision
        self:renderCurrent()
      end
    end)
  end

  function self:tick()
    self._tickCallback = self._tickCallback or self:onTick()
    return self._tickCallback()
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
    self.content = nil
    self.header = nil
    self.footer = nil
    self.selectedId = nil
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
  if not shell:selected() then shell:select("cockpit") end
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
