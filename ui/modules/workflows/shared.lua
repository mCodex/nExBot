-- Shared helpers for the per-workflow control renderers: profile pickers,
-- pagination, and the deferred-rerender pattern that avoids corrupting
-- OTC's mouse-grab state when triggered from inside a widget's own click
-- handler.

local Components = nExBot and nExBot.UI and nExBot.UI["ui.components.components"]

local Shared = {}
Shared.PAGE_SIZE = 40

function Shared.invoke(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, result = pcall(fn, ...)
  if ok then return result end
  return nil
end

function Shared.call(object, method)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, result = pcall(object[method], object)
  if ok then return result end
  return nil
end

function Shared.present(value, fallback)
  if value == nil or tostring(value) == "" then return fallback end
  return tostring(value)
end

function Shared.pageBounds(page, count)
  local pages = math.max(1, math.ceil(count / Shared.PAGE_SIZE))
  page = math.max(1, math.min(page, pages))
  local first = (page - 1) * Shared.PAGE_SIZE + 1
  return page, pages, first, math.min(count, first + Shared.PAGE_SIZE - 1)
end

function Shared.rerender(shell)
  if not shell or not shell.renderCurrent then return end
  -- Destroying the workspace content synchronously (e.g. from inside a
  -- ComboBox option-click, which is still unwinding its own popup-menu
  -- close logic) corrupts OTC's mouse-grab state and breaks all further
  -- clicks. Defer to the next tick so the triggering widget's own click
  -- handling finishes first.
  shell:defer(function()
    if shell.renderCurrent then shell:renderCurrent() end
  end, 0)
end

function Shared.actionBar(content)
  return g_ui.createWidget("NexWorkflowActions", content)
end

function Shared.actionButton(parent, options)
  options.style = "NexWorkflowButton"
  return Components.button(parent, options)
end

function Shared.newProfileAction(content, options)
  local bar = Shared.actionBar(content)
  Shared.actionButton(bar, {
    id = options.id,
    text = options.text or "New Profile",
    onClick = function()
      local function create(name)
        local ok, reason = options.onCreate(name)
        if not ok then return warn(reason or "Could not create profile") end
        Shared.rerender(options.shell)
      end
      if options.prompt then
        UI.EditorWindow("", { title = options.prompt.title, description = options.prompt.label }, create)
      else
        create()
      end
    end,
  })
end

local function optionName(first, second)
  if type(second) == "string" then return second end
  if type(second) == "table" then return second.text or second.value end
  if type(first) == "string" then return first end
  if type(first) == "table" then return first.text or first.value end
end
Shared.optionName = optionName

function Shared.profileSelect(content, options)
  Components.selectRow(content, {
    id = options.id,
    label = "Profile",
    options = options.items or {},
    value = options.value,
    onChange = function(first, second)
      local name = optionName(first, second)
      if name then options.onChange(name) end
    end,
  })
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI["ui.modules.workflows.shared"] = Shared
end

return Shared
