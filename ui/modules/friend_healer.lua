local Components = nExBot.UI["ui.components.components"]
local DataTable = nExBot.UI.DataTable

local FriendPage = {}

local REASONS = {
  READY = { "Ready", "ACTIVE" }, HEALTHY = { "Healthy", "INFO" },
  OUT_OF_RANGE = { "Out of range", "WARNING" }, NOT_VISIBLE = { "Not visible", "WARNING" },
  UNAVAILABLE = { "Unavailable", "DISABLED" },
}

local function rerender(shell)
  shell:defer(function() if shell and shell.renderCurrent then shell:renderCurrent() end end, 0)
end

local VOCATIONS = { { "knights", "Knights" }, { "paladins", "Paladins" }, { "druids", "Druids" }, { "sorcerers", "Sorcerers" }, { "monks", "Monks" } }
local GROUPS = { { "friends", "Friends" }, { "party", "Party Members" }, { "guild", "Guild Members" } }

local function renderConditionList(content, shell, conditions, title, items)
  if not HealBot.setFriendCondition then return end
  Components.sectionHeader(content, { title = title })
  for _, item in ipairs(items) do
    Components.toggleRow(content, {
      id = "friendCondition_" .. item[1],
      label = item[2],
      value = (conditions or {})[item[1]] == true,
      onChange = function(value)
        HealBot.setFriendCondition(item[1], value)
        rerender(shell)
      end,
    })
  end
end

function FriendPage.render(shell, content)
  if not HealBot or not HealBot.getFriendHealerProjection then
    Components.errorState(content, { message = "Friend Healer is unavailable." })
    return
  end
  local projection = HealBot.getFriendHealerProjection()
  Components.pageHeader(content, {
    title = "Friend Healer", subtitle = "Protects selected nearby players.",
    status = projection.enabled and "ACTIVE" or "DISABLED", statusText = projection.enabled and "Active" or "Disabled",
  })

  Components.toggleRow(content, { id = "friendEnabled", label = "Enabled", value = projection.enabled, onChange = function(value) HealBot.setFriendHealerEnabled(value); rerender(shell) end })
  Components.selectRow(content, {
    id = "friendSource", label = "Source", value = projection.source,
    options = { { text = "Party", value = "party" }, { text = "Guild", value = "guild" }, { text = "Friends", value = "friends" }, { text = "List", value = "list" } },
    onChange = function(_, value) if value then HealBot.setFriendSource(value); rerender(shell) end end,
  })
  Components.inputRow(content, {
    id = "friendThreshold", label = "Heal below", value = tostring(projection.threshold),
    onChange = function(value) HealBot.setFriendThreshold(value) end,
  })

  local priorityRows = {}
  for _, source in ipairs(projection.priorities) do
    local rule = source
    priorityRows[#priorityRows + 1] = {
      id = rule.index, revision = rule.revision, title = rule.name,
      secondary = "Priority " .. rule.index,
      status = rule.enabled and "ACTIVE" or "DISABLED",
      statusText = rule.enabled and "On" or "Off",
      actions = {
        { id = "friendToggle_" .. rule.index, text = rule.enabled and "Disable" or "Enable", onClick = function() HealBot.toggleFriendPriority(rule.index); rerender(shell) end },
        { id = "friendUp_" .. rule.index, text = "Up", onClick = function() HealBot.moveFriendPriority(rule.index, "up"); rerender(shell) end },
        { id = "friendDown_" .. rule.index, text = "Down", onClick = function() HealBot.moveFriendPriority(rule.index, "down"); rerender(shell) end },
      },
    }
  end
  DataTable.create(content, { id = "friendPriorities", title = "Healing priority", rows = priorityRows, rowKey = function(row) return row.id end })

  renderConditionList(content, shell, projection.conditions, "Vocations", VOCATIONS)
  renderConditionList(content, shell, projection.conditions, "Groups", GROUPS)

  local playerRows = {}
  for _, source in ipairs(projection.players) do
    local person = source
    local reason = REASONS[person.reason] or { person.reason, "WARNING" }
    playerRows[#playerRows + 1] = {
      id = person.id, revision = person.revision, title = person.name,
      secondary = person.hp .. "% HP / " .. person.distance .. " sqm",
      status = reason[2], statusText = reason[1],
    }
  end
  DataTable.create(content, {
    id = "friendPlayers", title = "Nearby players", rows = playerRows,
    rowKey = function(row) return row.id end,
    emptyMessage = "No selected players are currently visible.",
  })
end

nExBot.UI.ModuleRegistry.register({
  id = "friend_healer", label = "Friend", order = 42,
  group = "healing", route = "healing/friend", breadcrumb = "Healing / Friend Healer",
  render = FriendPage.render,
})
nExBot.UI.FriendHealerPage = FriendPage
nExBot.UI["ui.modules.friend_healer"] = FriendPage

return FriendPage
