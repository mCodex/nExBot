local Components = nExBot.UI["ui.components.components"]

local PushMaxPage = {}

local DELAYS = { 1000, 1060, 1200, 1500, 2000 }

local function rerender(shell)
  if not shell or not shell.renderCurrent then return end
  shell:defer(function()
    if shell.renderCurrent then shell:renderCurrent() end
  end, 0)
end

function PushMaxPage.render(shell, content)
  if not PushMax or not PushMax.getConfig then
    Components.errorState(content, { message = "Push did not load. Check the startup log." })
    return
  end

  local config = PushMax.getConfig()
  local enabled = PushMax.isOn()
  Components.pageHeader(content, {
    id = "pushHeader", textId = "pushHeaderText",
    title = "Push", subtitle = "Push creatures out of the way.",
    badgeId = "pushStatus",
    status = enabled and "ACTIVE" or "DISABLED",
    statusText = enabled and "Active" or "Disabled",
  })
  Components.toggleRow(content, {
    id = "pushEnabled", label = "Enabled", value = enabled,
    onChange = function(value)
      if value then PushMax.setOn() else PushMax.setOff() end
      rerender(shell)
    end,
  })
  Components.inputRow(content, {
    id = "pushKey", label = "Hotkey", value = config.pushMaxKey,
    onChange = function(text) PushMax.setConfig("pushMaxKey", text) end,
  })

  local delayOptions = {}
  local found = false
  for _, delay in ipairs(DELAYS) do
    delayOptions[#delayOptions + 1] = { text = tostring(delay), value = delay }
    if delay == config.pushDelay then found = true end
  end
  if not found then
    delayOptions[#delayOptions + 1] = { text = tostring(config.pushDelay), value = config.pushDelay }
    table.sort(delayOptions, function(a, b) return a.value < b.value end)
  end
  Components.selectRow(content, {
    id = "pushDelay", label = "Push delay (ms)", options = delayOptions,
    value = tostring(config.pushDelay),
    onChange = function(_, value) PushMax.setConfig("pushDelay", tonumber(value) or config.pushDelay) end,
  })
end

nExBot.UI.ModuleRegistry.register({
  id = "pushmax", label = "Push", order = 82,
  group = "hunting", route = "hunting/pushmax", breadcrumb = "Hunting / Push",
  render = PushMaxPage.render,
})
nExBot.UI.PushMaxPage = PushMaxPage
nExBot.UI["ui.modules.pushmax"] = PushMaxPage

return PushMaxPage