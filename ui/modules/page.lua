--[[
  Page — shared module-page renderer.

  Most modules follow the same shape: header title + session badge, then a list
  of sections rendered as cards of key/value rows, with a footer action area
  and an inline warning for diagnostics. This helper renders that shape so
  modules only supply a view model + actions. Module-specific layouts can still
  build custom widgets directly.
]]

local Components = (nExBot and nExBot.UI and nExBot.UI["ui.components.components"]) or (type(require) == "function" and require("ui.components.components"))
local Tokens = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.tokens"]) or (type(require) == "function" and require("ui.design_system.tokens"))
local Status = (nExBot and nExBot.UI and nExBot.UI["ui.design_system.status"]) or (type(require) == "function" and require("ui.design_system.status"))
local Actions = (nExBot and nExBot.UI and nExBot.UI["ui.core.actions"]) or (type(require) == "function" and require("ui.core.actions"))

-- Resolve the shared dispatcher through the namespace so runtime (loadfile) and
-- tests (require) always share one instance.
local function actionsDispatcher()
  local ns = nExBot and nExBot.UI
  if ns and ns.Actions then return ns.Actions end
  return Actions
end

local function resolveAction(action)
  return {
    id = action.id,
    label = action.label,
    variant = action.variant,
    onClick = (type(action.onClick) == "function") and action.onClick
      or function() actionsDispatcher().run(action.id) end,
  }
end

local Page = {}

function Page.render(shell, content, lifecycle, view)
  if not lifecycle or not lifecycle:isCurrent(lifecycle:current()) then return end
  if not view then
    Components.errorState(content, { message = "No view model available." })
    return
  end

  if view.state == "LOADING" then
    Components.loadingState(content)
    return
  end

  local header = view.header or {}

  Components.label(content, header.title or header.module or "", { id = "pageTitle", textStyle = "moduleTitle", color = Tokens.colors.text.primary })

  if header.subtitle then
    Components.label(content, header.subtitle, { id = "pageSubtitle", textStyle = "helper", color = Tokens.colors.text.muted })
  end

  if header.status then
    local badge = Components.statusBadge(content, { id = "pageBadge", status = header.status, text = header.statusText or header.status })
    badge:setColor(Status.color(header.status))
  end

  if view.state == "EMPTY" then
    Components.emptyState(content, { message = view.errors[1] and view.errors[1].message or "No data." })
    return
  end

  for _, section in ipairs(view.sections or {}) do
    if section.id then
      Components.sectionHeader(content, { title = section.title or section.id })
    end
    local card = Components.card(content, { title = section.title })
    for _, row in ipairs(section.rows or {}) do
      Components.keyValueRow(card, { key = row.key, value = row.value })
    end
    for _, item in ipairs(section.items or {}) do
      if item.title then
        Components.listRow(card, item)
      end
    end
  end

  if view.actions and #view.actions > 0 then
    local footer = Components.footerActions(content, {
      primary = view.primaryAction and resolveAction(view.primaryAction),
      secondary = view.secondaryAction and resolveAction(view.secondaryAction),
    })
    -- remaining actions as ghost buttons
    for _, action in ipairs(view.actions) do
      if action ~= view.primaryAction and action ~= view.secondaryAction then
        local a = resolveAction(action)
        Components.button(footer, {
          text = a.label, id = a.id, variant = "ghost", onClick = a.onClick,
        })
      end
    end
  end

  for _, err in ipairs(view.errors or {}) do
    Components.inlineWarning(content, { message = err.message or err.code })
  end
end

return Page
