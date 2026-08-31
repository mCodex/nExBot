local Components = nExBot.UI["ui.components.components"]
local DataTable = nExBot.UI.DataTable
local Shared = nExBot.UI["ui.modules.workflows.shared"] or (type(require) == "function" and require("ui.modules.workflows.shared"))

local AlarmsPage = {}

local TYPE_LABEL = { settings = "Setting", alarms = "Alarm" }

local function rerender(shell)
  Shared.rerender(shell)
end

function AlarmsPage.render(shell, content)
  if not Alarms or not Alarms.getAlarms then
    Components.errorState(content, { message = "Alarms did not load. Check the startup log." })
    return
  end

  local enabled = Alarms.isOn()
  Components.pageHeader(content, {
    id = "alarmsHeader", textId = "alarmsHeaderText",
    title = "Alarms", subtitle = "Alerts for chat, combat, and nearby creatures.",
    badgeId = "alarmsStatus",
    status = enabled and "ACTIVE" or "DISABLED",
    statusText = enabled and "Active" or "Disabled",
  })
  Components.toggleRow(content, {
    id = "alarmsEnabled", label = "Enabled", value = enabled,
    onChange = function(value)
      if value then Alarms.setOn() else Alarms.setOff() end
      rerender(shell)
    end,
  })

  local rows = {}
  for _, alarm in ipairs(Alarms.getAlarms()) do
    local secondary = TYPE_LABEL[alarm.parent]
    if alarm.value ~= nil then secondary = secondary .. ": " .. tostring(alarm.value) end
    rows[#rows + 1] = {
      id = alarm.id,
      revision = alarm.enabled and "on" or "off",
      title = alarm.title,
      secondary = secondary,
      compactSecondary = TYPE_LABEL[alarm.parent],
      status = alarm.enabled and "ACTIVE" or "DISABLED",
      statusText = alarm.enabled and "On" or "Off",
      actions = {
        { id = "alarmToggle_" .. alarm.id, text = alarm.enabled and "Disable" or "Enable", onClick = function()
          Alarms.setAlarm(alarm.id, "enabled", not alarm.enabled)
          rerender(shell)
        end },
      },
    }
  end

  DataTable.create(content, {
    id = "alarmTable", title = "Alarms", rows = rows,
    rowKey = function(row) return row.id end, searchable = #rows > 6,
    searchText = function(row) return row.title .. " " .. row.secondary end,
    emptyMessage = "No alarms configured.",
  })
end

nExBot.UI.ModuleRegistry.register({
  id = "alarms", label = "Alarms", order = 81,
  group = "hunting", route = "hunting/alarms", breadcrumb = "Hunting / Alarms",
  render = AlarmsPage.render,
})
nExBot.UI.AlarmsPage = AlarmsPage
nExBot.UI["ui.modules.alarms"] = AlarmsPage

return AlarmsPage
