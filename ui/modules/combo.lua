local Components = nExBot.UI["ui.components.components"]

local ComboPage = {}

local TRIGGERS = {
  { id = "onSayEnabled", label = "On Say" },
  { id = "onShootEnabled", label = "On Shoot" },
  { id = "onCastEnabled", label = "On Cast" },
}

local ACTIONS = {
  { id = "followLeaderEnabled", label = "Follow Leader" },
  { id = "attackLeaderTargetEnabled", label = "Attack Leader Target" },
  { id = "attackSpellEnabled", label = "Attack Spell" },
  { id = "attackItemEnabled", label = "Attack Item" },
}

local function rerender(shell)
  if not shell or not shell.renderCurrent then return end
  shell:defer(function()
    if shell.renderCurrent then shell:renderCurrent() end
  end, 0)
end

local function settingToggle(shell, content, widgetId, key, label)
  Components.toggleRow(content, {
    id = widgetId, label = label, value = ComboBot.getSetting(key),
    onChange = function(value) ComboBot.setSetting(key, value); rerender(shell) end,
  })
end

function ComboPage.render(shell, content)
  if not ComboBot or not ComboBot.getSetting then
    Components.errorState(content, { message = "Combo did not load. Check the startup log." })
    return
  end

  local enabled = ComboBot.isOn()
  Components.pageHeader(content, {
    id = "comboHeader", textId = "comboHeaderText",
    title = "Combo", subtitle = "Combos and commands off leader actions.",
    badgeId = "comboStatus",
    status = enabled and "ACTIVE" or "DISABLED",
    statusText = enabled and "Active" or "Disabled",
  })
  Components.toggleRow(content, {
    id = "comboEnabled", label = "Enabled", value = enabled,
    onChange = function(value)
      if value then ComboBot.setOn() else ComboBot.setOff() end
      rerender(shell)
    end,
  })

  Components.sectionHeader(content, { title = "Triggers" })
  for _, trigger in ipairs(TRIGGERS) do
    settingToggle(shell, content, "comboTrigger_" .. trigger.id, trigger.id, trigger.label)
  end
  Components.sectionHeader(content, { title = "Actions" })
  for _, action in ipairs(ACTIONS) do
    settingToggle(shell, content, "comboAction_" .. action.id, action.id, action.label)
  end
  settingToggle(shell, content, "comboCommands", "commandsEnabled", "Leader Commands")
end

nExBot.UI.ModuleRegistry.register({
  id = "combo", label = "Combo", order = 80,
  group = "hunting", route = "hunting/combo", breadcrumb = "Hunting / Combo",
  render = ComboPage.render,
})
nExBot.UI.ComboPage = ComboPage
nExBot.UI["ui.modules.combo"] = ComboPage

return ComboPage