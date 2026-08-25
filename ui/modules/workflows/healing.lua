-- Healing workflow controls: profile picker and spell/item rule tables.

local Components = nExBot and nExBot.UI and nExBot.UI["ui.components.components"]
local DataTable = nExBot and nExBot.UI and nExBot.UI.DataTable
local Presenter = nExBot and nExBot.UI and nExBot.UI.RulePresenter
local Resolver = nExBot and nExBot.UI and nExBot.UI.VisualAssetResolver
local Shared = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.shared"]

local HealingPage = {}
local healPage = { spell = 1, item = 1 }

local function renderHealRuleList(content, shell, kind, title)
  if not HealBot.getRules then return end
  local rules = HealBot.getRules(kind)
  local pages, first, last
  healPage[kind], pages, first, last = Shared.pageBounds(healPage[kind], #rules)
  Components.sectionHeader(content, { title = title })
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

  renderHealRuleList(content, shell, "spell", "Healing Spells")
  renderHealRuleList(content, shell, "item", "Healing Items")

  local actions = Shared.actionBar(content)
  Shared.actionButton(actions, { id = "manageHealRules", text = "Add / Manage Rules", onClick = function()
    if HealBot.show then HealBot.show() end
  end })
  if HealBot.showAlly then
    Shared.actionButton(actions, { id = "healFriend", text = "Heal Friend", onClick = function()
      HealBot.showAlly()
    end })
  end
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI["ui.modules.workflows.healing"] = HealingPage
end

return HealingPage
