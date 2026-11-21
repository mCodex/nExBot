-- Healing workflow controls: profile picker, spell/item rule tables, inline
-- rule adding, and the persisted engine settings.

local Components = nExBot and nExBot.UI and nExBot.UI["ui.components.components"]
local DataTable = nExBot and nExBot.UI and nExBot.UI.DataTable
local Presenter = nExBot and nExBot.UI and nExBot.UI.RulePresenter
local Resolver = nExBot and nExBot.UI and nExBot.UI.VisualAssetResolver
local Shared = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.shared"]

local HealingPage = {}
local healPage = { spell = 1, item = 1 }
local draft = { kind = "spell", value = "", spell = "", cost = "", item = "" }

local SETTINGS = {
  { key = "Cooldown", label = "Check spell cooldowns" },
  { key = "Visible", label = "Items must be visible (recommended)" },
  { key = "Delay", label = "Don't use items when interacting" },
  { key = "Interval", label = "Additional delay when looting corpses" },
  { key = "Conditions", label = "Also check conditions from RL Tibia" },
}

local function renderHealRuleList(content, shell, kind, title)
  if not HealBot.getRules then return end
  local rules = HealBot.getRules(kind)
  local pages, first, last
  healPage[kind], pages, first, last = Shared.pageBounds(healPage[kind], #rules)
  if DataTable and Presenter and Resolver then
    local tableRows = {}
    for index = first, last do
      local source = rules[index]
      local rule = source
      local visual = rule.itemId and Resolver:item(rule.itemId) or Resolver:spell(rule.spell)
      tableRows[#tableRows + 1] = {
        id = kind .. "_" .. rule.index,
        revision = rule.revision or (rule.index .. ":" .. tostring(rule.enabled)),
        itemId = rule.itemId,
        imageSource = not rule.itemId and visual.source or nil,
        title = rule.spell or (rule.itemId and visual.name) or rule.label,
        secondary = Presenter.healTrigger(rule),
        status = rule.enabled and "ACTIVE" or "DISABLED",
        statusText = rule.enabled and "Ready" or "Disabled",
        actions = {
          { id = "healRuleToggle_" .. kind .. "_" .. rule.index, text = rule.enabled and "Disable" or "Enable", onClick = function() HealBot.toggleRule(kind, rule.index); Shared.rerender(shell) end },
          { id = "healRuleUp_" .. kind .. "_" .. rule.index, text = "Up", onClick = function() if HealBot.moveRule then HealBot.moveRule(kind, rule.index, "up"); Shared.rerender(shell) end end },
          { id = "healRuleDown_" .. kind .. "_" .. rule.index, text = "Down", onClick = function() if HealBot.moveRule then HealBot.moveRule(kind, rule.index, "down"); Shared.rerender(shell) end end },
          { id = "healRuleRemove_" .. kind .. "_" .. rule.index, text = "Remove", variant = "danger", onClick = function() HealBot.removeRule(kind, rule.index); Shared.rerender(shell) end },
        },
      }
    end
    DataTable.create(content, {
      id = "healRules_" .. kind, title = title, rows = tableRows,
      rowKey = function(row) return row.id end,
      emptyMessage = kind == "spell" and "No healing spells yet." or "No healing items yet.",
    })
    return
  end
  Components.sectionHeader(content, { title = title })
  if #rules == 0 then
    Components.emptyState(content, { message = "No rules configured." })
  else
    Components.label(content, { text = string.format("Showing %d-%d of %d", first, last, #rules), textStyle = "metadata" })
    for index = first, last do
      local rule = rules[index]
      Components.listRow(content, {
        id = "healRule_" .. kind .. "_" .. rule.index,
        title = rule.label,
        subtitle = rule.enabled and "Enabled" or "Disabled",
        status = rule.enabled and "ACTIVE" or "DISABLED",
        actions = {
          { id = "healRuleToggle_" .. kind .. "_" .. rule.index, text = rule.enabled and "Disable" or "Enable", onClick = function()
            HealBot.toggleRule(kind, rule.index); Shared.rerender(shell)
          end },
          { id = "healRuleRemove_" .. kind .. "_" .. rule.index, text = "Remove", variant = "danger", onClick = function()
            HealBot.removeRule(kind, rule.index); Shared.rerender(shell)
          end },
        },
      })
    end
  end

  local paging = Shared.actionBar(content)
  Shared.actionButton(paging, { id = "heal" .. kind .. "Previous", text = "Previous", disabled = healPage[kind] == 1, onClick = function()
    healPage[kind] = healPage[kind] - 1; Shared.rerender(shell)
  end })
  Shared.actionButton(paging, { id = "heal" .. kind .. "Next", text = "Next", disabled = healPage[kind] == pages, onClick = function()
    healPage[kind] = healPage[kind] + 1; Shared.rerender(shell)
  end })
end

local function renderHealAddForm(content, shell)
  if not HealBot.addRule then return end
  Components.sectionHeader(content, { title = "Add rule" })
  Components.selectRow(content, {
    id = "healAddKind",
    label = "Type",
    options = { { text = "Spell", value = "spell" }, { text = "Item", value = "item" } },
    value = draft.kind == "item" and "Item" or "Spell",
    onChange = function(_, value)
      draft.kind = value or draft.kind
      Shared.rerender(shell)
    end,
  })
  Components.inputRow(content, {
    id = "healAddValue",
    label = "Heal below (HP%)",
    value = draft.value,
    onChange = function(value) draft.value = value end,
  })
  if draft.kind == "item" then
    Components.inputRow(content, {
      id = "healAddItem",
      label = "Item ID",
      value = draft.item,
      onChange = function(value) draft.item = value end,
    })
  else
    Components.inputRow(content, {
      id = "healAddSpell",
      label = "Spell name",
      value = draft.spell,
      onChange = function(value) draft.spell = value end,
    })
    Components.inputRow(content, {
      id = "healAddCost",
      label = "Mana cost",
      value = draft.cost,
      onChange = function(value) draft.cost = value end,
    })
  end
  local feedback = Components.label(content, { id = "healAddFeedback", text = "", textStyle = "helper" })
  Components.button(content, {
    id = "healAddRule",
    text = "Add rule",
    onClick = function()
      local ok
      if draft.kind == "item" then
        ok = HealBot.addRule("item", { value = draft.value, item = draft.item })
      else
        ok = HealBot.addRule("spell", { value = draft.value, spell = draft.spell, cost = draft.cost })
      end
      if not ok then
        feedback:setText("Enter a valid trigger and " .. (draft.kind == "item" and "item ID" or "spell name") .. ".")
        return
      end
      draft.value, draft.spell, draft.cost, draft.item = "", "", "", ""
      Shared.rerender(shell)
    end,
  })
end

local function renderHealSettings(content, shell)
  if not HealBot.getSetting then return end
  Components.sectionHeader(content, { title = "Settings" })
  for _, setting in ipairs(SETTINGS) do
    Components.toggleRow(content, {
      id = "healSetting_" .. setting.key,
      label = setting.label,
      value = HealBot.getSetting(setting.key) == true,
      onChange = function(value)
        HealBot.setSetting(setting.key, value)
        Shared.rerender(shell)
      end,
    })
  end
end

function HealingPage.render(content, shell)
  if not HealBot then return end
  Components.sectionHeader(content, { title = "Healing profile" })
  Shared.profileSelect(content, {
    id = "healProfile",
    items = { "1", "2", "3", "4", "5" },
    value = tostring(HealBot.getActiveProfile and HealBot.getActiveProfile() or 1),
    onChange = function(profile)
      if HealBot.setActiveProfile then HealBot.setActiveProfile(tonumber(profile)) end
      Shared.rerender(shell)
    end,
  })

  Components.toggleRow(content, {
    id = "healEnabled",
    label = "Enabled",
    value = HealBot.isOn and HealBot.isOn() or false,
    onChange = function(value)
      if value then HealBot.setOn() else HealBot.setOff() end
      Shared.rerender(shell)
    end,
  })

  renderHealRuleList(content, shell, "spell", "Healing Spells")
  renderHealRuleList(content, shell, "item", "Healing Items")
  renderHealAddForm(content, shell)
  renderHealSettings(content, shell)
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI["ui.modules.workflows.healing"] = HealingPage
end

return HealingPage