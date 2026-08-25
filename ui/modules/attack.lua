local Components = nExBot.UI["ui.components.components"]
local DataTable = nExBot.UI.DataTable
local Presenter = nExBot.UI.RulePresenter
local Resolver = nExBot.UI.VisualAssetResolver

local AttackPage = {}

local function rerender(shell)
  shell:defer(function()
    if shell and shell.renderCurrent then shell:renderCurrent() end
  end, 0)
end

local function targetName()
  if not TargetBot or type(TargetBot.getCurrentTarget) ~= "function" then return "-" end
  local target = TargetBot.getCurrentTarget()
  if not target or type(target.getName) ~= "function" then return "-" end
  local ok, name = pcall(target.getName, target)
  return ok and name or "-"
end

function AttackPage.render(shell, content)
  if not AttackBot or not AttackBot.getRules then
    Components.errorState(content, { message = "Attack rotation is unavailable." })
    return
  end

  local enabled = AttackBot.isOn and AttackBot.isOn()
  local rules = AttackBot.getRules()
  Components.pageHeader(content, {
    title = "Attack Rotation",
    subtitle = "Profile " .. tostring(AttackBot.getActiveProfile and AttackBot.getActiveProfile() or "-") .. " · Target " .. targetName(),
    status = enabled and "ACTIVE" or "DISABLED", statusText = enabled and "Active" or "Disabled",
  })

  local rows = {}
  for _, source in ipairs(rules) do
    local rule = source
    local spellVisual = not rule.itemId and Resolver:spell(rule.spell)
    rows[#rows + 1] = {
      id = rule.index, revision = rule.revision,
      itemId = rule.itemId,
      imageSource = spellVisual and spellVisual.source,
      title = rule.spell or (rule.itemId and Resolver:item(rule.itemId).name) or "Attack",
      secondary = Presenter.attackTrigger(rule),
      compactSecondary = Presenter.attackTrigger(rule),
      status = rule.enabled and "ACTIVE" or "DISABLED",
      statusText = rule.enabled and "Ready" or "Disabled",
      actions = {
        { id = "toggleAttack_" .. rule.index, text = rule.enabled and "Disable" or "Enable", onClick = function() AttackBot.toggleRule(rule.index); rerender(shell) end },
        { id = "attackUp_" .. rule.index, text = "Up", onClick = function() AttackBot.moveRule(rule.index, "up"); rerender(shell) end },
        { id = "attackDown_" .. rule.index, text = "Down", onClick = function() AttackBot.moveRule(rule.index, "down"); rerender(shell) end },
        { id = "removeAttack_" .. rule.index, text = "Remove", variant = "danger", onClick = function() AttackBot.removeRule(rule.index); rerender(shell) end },
      },
    }
  end

  DataTable.create(content, {
    id = "attackRules", title = "Rotation", rows = rows,
    rowKey = function(row) return row.id end, searchable = #rows > 4,
    searchText = function(row) return row.title .. " " .. row.secondary end,
    emptyMessage = "No attack rules yet. Add the first spell or rune.",
  })
  Components.button(content, { id = "manageAttackRules", text = "Add or edit rule", onClick = AttackBot.show })
end

nExBot.UI.ModuleRegistry.register({
  id = "attack", label = "Attack", order = 35,
  group = "hunting", route = "hunting/attack", breadcrumb = "Hunting / Attack",
  render = AttackPage.render,
})
nExBot.UI.AttackPage = AttackPage
nExBot.UI["ui.modules.attack"] = AttackPage

return AttackPage
