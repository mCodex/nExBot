local Components = nExBot.UI["ui.components.components"]
local DataTable = nExBot.UI.DataTable
local Resolver = nExBot.UI.VisualAssetResolver
local Shared = nExBot.UI["ui.modules.workflows.shared"] or (type(require) == "function" and require("ui.modules.workflows.shared"))

local ConditionsPage = {}

local function rerender(shell)
  Shared.rerender(shell)
end

local CURE_CONDITIONS = {
  { key = "curePoison", label = "Cure poison" },
  { key = "cureCurse", label = "Cure curse" },
  { key = "cureBleed", label = "Cure bleeding" },
  { key = "cureBurn", label = "Cure burning" },
  { key = "cureElectrify", label = "Cure electrify" },
  { key = "cureParalyse", label = "Cure paralysis" },
}

local HOLD_CONDITIONS = {
  { key = "holdHaste", label = "Haste" },
  { key = "holdUtamo", label = "Magic shield" },
  { key = "holdUtana", label = "Invisibility" },
  { key = "holdUtura", label = "Regeneration" },
}

local function renderToggles(content, shell, conditions)
  for _, condition in ipairs(conditions) do
    Components.toggleRow(content, {
      id = condition.key, label = condition.label, value = Conditions.getCondition(condition.key),
      onChange = function(value) Conditions.setCondition(condition.key, value); rerender(shell) end,
    })
  end
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
    id = "conditionsEnabled", label = "Enabled", value = enabled,
    onChange = function(value) if value then Conditions.setOn() else Conditions.setOff() end; rerender(shell) end,
  })

  Components.sectionHeader(content, { title = "Cure" })
  renderToggles(content, shell, CURE_CONDITIONS)

  Components.sectionHeader(content, { title = "Hold" })
  renderToggles(content, shell, HOLD_CONDITIONS)

  local rows = {}
  for _, source in ipairs(Conditions.getRules()) do
    local rule = source
    local visual = Resolver:spell(rule.spell)
    rows[#rows + 1] = {
      id = rule.id, revision = rule.id .. ":" .. tostring(rule.enabled) .. ":" .. tostring(rule.cost),
      imageSource = visual.source, title = rule.name,
      secondary = (rule.spell ~= "" and rule.spell or "Automatic") .. " / " .. tostring(rule.cost or 0) .. " mana",
      status = rule.enabled and "ACTIVE" or "DISABLED", statusText = rule.enabled and "On" or "Off",
      actions = { { id = "condition_" .. rule.id, text = rule.enabled and "Disable" or "Enable", onClick = function()
        Conditions.setRuleEnabled(rule.id, not rule.enabled)
        rerender(shell)
      end } },
    }
  end
  DataTable.create(content, { id = "conditionRules", title = "Rules", rows = rows, rowKey = function(row) return row.id end })
end

nExBot.UI.ModuleRegistry.register({
  id = "conditions", label = "Conditions", order = 44,
  group = "healing", route = "healing/conditions", breadcrumb = "Healing / Conditions",
  render = ConditionsPage.render,
})
nExBot.UI.ConditionsPage = ConditionsPage
nExBot.UI["ui.modules.conditions"] = ConditionsPage

return ConditionsPage
