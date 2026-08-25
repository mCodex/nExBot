local Components = nExBot.UI["ui.components.components"]
local DataTable = nExBot.UI.DataTable
local Resolver = nExBot.UI.VisualAssetResolver

local ConditionsPage = {}

local function rerender(shell)
  shell:defer(function() if shell and shell.renderCurrent then shell:renderCurrent() end end, 0)
end

function ConditionsPage.render(shell, content)
  if not Conditions or not Conditions.getRules then
    Components.errorState(content, { message = "Conditions are unavailable." })
    return
  end
  local enabled = Conditions.isOn()
  Components.pageHeader(content, {
    title = "Conditions", subtitle = "Cures, movement buffs and protection.",
    status = enabled and "ACTIVE" or "DISABLED", statusText = enabled and "Active" or "Disabled",
  })
  Components.toggleRow(content, {
    label = "Enabled", value = enabled,
    onChange = function(value) if value then Conditions.setOn() else Conditions.setOff() end; rerender(shell) end,
  })

  local rows = {}
  for _, source in ipairs(Conditions.getRules()) do
    local rule = source
    local visual = Resolver:spell(rule.spell)
    rows[#rows + 1] = {
      id = rule.id, revision = rule.id .. ":" .. tostring(rule.enabled) .. ":" .. tostring(rule.cost),
      imageSource = visual.source, title = rule.name,
      secondary = (rule.spell ~= "" and rule.spell or "Automatic") .. " · " .. tostring(rule.cost or 0) .. " mana",
      status = rule.enabled and "ACTIVE" or "DISABLED", statusText = rule.enabled and "On" or "Off",
      actions = { { id = "condition_" .. rule.id, text = rule.enabled and "Disable" or "Enable", onClick = function()
        Conditions.setRuleEnabled(rule.id, not rule.enabled)
        rerender(shell)
      end } },
    }
  end
  DataTable.create(content, { id = "conditionRules", title = "Rules", rows = rows, rowKey = function(row) return row.id end })
  Components.button(content, { id = "advancedConditions", text = "Advanced", onClick = Conditions.show })
end

nExBot.UI.ModuleRegistry.register({
  id = "conditions", label = "Conditions", order = 44,
  group = "healing", route = "healing/conditions", breadcrumb = "Healing / Conditions",
  render = ConditionsPage.render,
})
nExBot.UI.ConditionsPage = ConditionsPage
nExBot.UI["ui.modules.conditions"] = ConditionsPage

return ConditionsPage
