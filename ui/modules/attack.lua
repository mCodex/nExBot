local Components = nExBot.UI["ui.components.components"]
local DataTable = nExBot.UI.DataTable
local Presenter = nExBot.UI.RulePresenter
local Resolver = nExBot.UI.VisualAssetResolver
local Shared = nExBot.UI["ui.modules.workflows.shared"] or (type(require) == "function" and require("ui.modules.workflows.shared"))

local AttackPage = {}

local CATEGORIES = {
  { text = "Targeted Spell", value = 1 },
  { text = "Area Rune", value = 2 },
  { text = "Targeted Rune", value = 3 },
  { text = "Empowerment", value = 4 },
  { text = "Absolute Spell", value = 5 },
}

local SETTINGS = {
  { key = "ignoreMana", label = "Check RL Tibia conditions" },
  { key = "Kills", label = "Don't use area attacks if less than kills to red skull" },
  { key = "Cooldown", label = "Check spell cooldowns" },
  { key = "Visible", label = "Items must be visible (recommended)" },
  { key = "pvpMode", label = "PVP mode" },
  { key = "PvpSafe", label = "PVP safe" },
  { key = "Training", label = "Stop when attacking trainers" },
  { key = "BlackListSafe", label = "Stop if Anti-RS player in range" },
}

local function rerender(shell)
  Shared.rerender(shell)
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
    subtitle = "Profile " .. tostring(AttackBot.getActiveProfile and AttackBot.getActiveProfile() or "-") .. " / Target " .. targetName(),
    status = enabled and "ACTIVE" or "DISABLED", statusText = enabled and "Active" or "Disabled",
  })

  Components.toggleRow(content, {
    id = "attackEnabled", label = "Enabled", value = enabled,
    onChange = function(on)
      if on then AttackBot.setOn() else AttackBot.setOff() end
      rerender(shell)
    end,
  })

  local rows = {}
  for _, rule in ipairs(rules) do
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
        { id = "toggleAttack_" .. rule.index, text = rule.enabled and "Disable" or "Enable", tooltip = rule.enabled and "Disable this rule" or "Enable this rule", onClick = function() AttackBot.toggleRule(rule.index); rerender(shell) end },
        { id = "attackUp_" .. rule.index, text = "Up", tooltip = "Move rule up", onClick = function() AttackBot.moveRule(rule.index, "up"); rerender(shell) end },
        { id = "attackDown_" .. rule.index, text = "Down", tooltip = "Move rule down", onClick = function() AttackBot.moveRule(rule.index, "down"); rerender(shell) end },
        { id = "removeAttack_" .. rule.index, text = "Remove", variant = "danger", tooltip = "Remove this rule", onClick = function() AttackBot.removeRule(rule.index); rerender(shell) end },
      },
    }
  end

  DataTable.create(content, {
    id = "attackRules", title = "Rotation", rows = rows,
    rowKey = function(row) return row.id end, searchable = #rows > 4,
    searchText = function(row) return row.title .. " " .. row.secondary end,
    emptyMessage = "No attack rules yet. Add the first spell or rune.",
  })

  Components.sectionHeader(content, { title = "Settings" })
  for _, setting in ipairs(SETTINGS) do
    Components.toggleRow(content, {
      id = "setting_" .. setting.key, label = setting.label,
      value = AttackBot.getSetting(setting.key) == true,
      onChange = function(on) AttackBot.setSetting(setting.key, on); rerender(shell) end,
    })
  end
  Components.inputRow(content, {
    id = "setting_KillsAmount", label = "Kills to red skull",
    value = tostring(AttackBot.getSetting("KillsAmount") or 1),
    onChange = function(v) AttackBot.setSetting("KillsAmount", tonumber(v) or 1) end,
  })
  Components.inputRow(content, {
    id = "setting_AntiRsRange", label = "Anti-RS range",
    value = tostring(AttackBot.getSetting("AntiRsRange") or 5),
    onChange = function(v) AttackBot.setSetting("AntiRsRange", tonumber(v) or 5) end,
  })

  Components.sectionHeader(content, { title = "Add rule" })
  local draft = {}
  Components.inputRow(content, {
    id = "attackSpell", label = "Spell or rune item ID",
    onChange = function(value) draft.spell = value end,
  })
  Components.selectRow(content, {
    id = "attackCategory", label = "Category",
    options = CATEGORIES, value = "Targeted Spell",
    onChange = function(_, value) draft.category = value or 1 end,
  })
  Components.inputRow(content, {
    id = "attackCount", label = "Creature count", value = "1",
    onChange = function(value) draft.count = value end,
  })
  Components.toggleRow(content, {
    id = "attackOrMore", label = "Or more creatures", value = false,
    onChange = function(on) draft.orMore = on end,
  })
  local feedback = Components.label(content, { id = "attackFeedback", text = "", textStyle = "helper" })
  Components.button(content, {
    id = "addAttackRule", text = "Add rule",
    onClick = function()
      local value = tostring(draft.spell or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if value == "" then
        feedback:setText("Enter a spell name or rune item ID.")
        return
      end
      local itemId = tonumber(value)
      local ok = AttackBot.addRule and AttackBot.addRule({
        spell = itemId and nil or value,
        itemId = itemId,
        category = draft.category or 1,
        count = tonumber(draft.count) or 1,
        orMore = draft.orMore == true,
      })
      if not ok then
        feedback:setText("Could not add the rule.")
        return
      end
      rerender(shell)
    end,
  })
end

nExBot.UI.ModuleRegistry.register({
  id = "attack", label = "Attack", order = 35,
  group = "hunting", route = "hunting/attack", breadcrumb = "Hunting / Attack",
  render = AttackPage.render,
})
nExBot.UI.AttackPage = AttackPage
nExBot.UI["ui.modules.attack"] = AttackPage

return AttackPage
