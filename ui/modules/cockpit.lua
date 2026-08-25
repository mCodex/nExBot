-- Compact, truthful read model for the primary hunt controls.

local Components = nExBot and nExBot.UI and nExBot.UI["ui.components.components"]
local Tokens = nExBot and nExBot.UI and nExBot.UI["ui.design_system.tokens"]
local Actions = nExBot and nExBot.UI and nExBot.UI.Actions

local Cockpit = {}

local STATUS_VARIANT = {
  ACTIVE = "active",
  DISABLED = "inactive",
  UNKNOWN = "warning",
}

local ENGINE_DEFS = {
  { key = "cave", label = "Cave", itemId = 3003, toggleAction = "toggle_cavebot", editorAction = "open_cavebot" },
  { key = "target", label = "Target", itemId = 3155, toggleAction = "toggle_targetbot", editorAction = "open_targetbot" },
  { key = "heal", label = "Heal", itemId = 23375, toggleAction = "toggle_healing", editorAction = "open_healing" },
  { key = "loot", label = "Loot", itemId = 2854, toggleAction = "toggle_looting", editorAction = "open_looting" },
}

local function engineStatus(value)
  if value == nil then return "UNKNOWN", "Unavailable" end
  if value then return "ACTIVE", "On" end
  return "DISABLED", "Off"
end

function Cockpit.viewModel(state)
  state = state or {}
  local engines = {}

  for _, def in ipairs(ENGINE_DEFS) do
    local status, statusText = engineStatus(state[def.key])
    engines[#engines + 1] = {
      id = def.key,
      label = def.label,
      itemId = def.itemId,
      status = status,
      statusText = statusText,
      detail = state[def.key .. "Detail"] or "-",
      toggleAction = def.toggleAction,
      editorAction = def.editorAction,
    }
  end

  local issues = state.issues or {}
  return {
    snapshot = {
      revision = state.revision or 0,
      character = state.character or "-",
      profile = state.profile or "-",
      engines = engines,
      route = state.route or "-",
      waypoint = state.waypoint or "-",
      targetName = state.targetName or "-",
      targetHp = state.targetHp,
      hp = state.hp,
      mana = state.mana,
      xpHour = state.xpHour,
      aiState = state.aiState or "Unavailable",
      aiDecision = state.aiDecision or "-",
      aiConfidence = state.aiConfidence or "-",
      aiOutcome = state.aiOutcome or "-",
      issues = issues,
      attention = issues[1] and (issues[1].message or tostring(issues[1])) or "No issues",
    },
  }
end

local function availableState(module, method)
  if not module or type(module[method]) ~= "function" then return nil end
  local ok, value = pcall(module[method])
  if not ok then return nil end
  return value == true
end

local function call(object, method, ...)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, value = pcall(object[method], object, ...)
  if ok then return value end
  return nil
end

local function value(helper)
  if type(helper) ~= "function" then return helper end
  local ok, result = pcall(helper)
  if ok then return result end
  return nil
end

local function intelligencePulse()
  local intelligence = nExBot and nExBot.Intelligence
  if not intelligence then
    return "Unavailable", "-", "-", "-"
  end

  local lifecycle = intelligence.lifecycle
  local aiState = lifecycle and (lifecycle.active and "Active" or "Idle") or "Unavailable"
  local blackboard = intelligence.blackboard
  local attackIntent = call(blackboard, "read", "currentAttackIntent")
  local movementIntent = call(blackboard, "read", "currentMovementIntent")
  local decision = attackIntent or movementIntent
  local decisionText = decision and (decision.action or decision.type or decision.name or decision.decisionType) or "-"
  local confidence = decision and (decision.confidence or (decision.prediction and decision.prediction.confidence))
  local confidenceText = type(confidence) == "number" and math.floor(confidence * 100 + 0.5) .. "%" or "-"
  local metrics = nExBot.HuntMetrics and nExBot.HuntMetrics.metrics
  local outcome = metrics and type(metrics.kills) == "number" and metrics.kills .. " kills" or "-"

  return aiState, decisionText, confidenceText, outcome
end

function Cockpit.statusProvider()
  local player = player
  local storage = storage
  local caveConfig = storage and storage.cavebot
  local targetConfig = storage and storage.targetbot
  local target = TargetBot and value(TargetBot.getCurrentTarget)
  local targetName = call(target, "getName") or (type(target) == "string" and target or nil)
  local aiState, aiDecision, aiConfidence, aiOutcome = intelligencePulse()

  return Cockpit.viewModel({
    cave = availableState(CaveBot, "isOn"),
    target = availableState(TargetBot, "isOn"),
    heal = availableState(HealBot, "isOn"),
    loot = availableState(TargetBot, "isLootingEnabled"),
    caveDetail = caveConfig and caveConfig.selectedConfig,
    targetDetail = targetConfig and targetConfig.selectedConfig,
    healDetail = HealBot and HealBot.getActiveProfile and HealBot.getActiveProfile(),
    lootDetail = "Containers",
    character = call(player, "getName"),
    profile = storage and storage.profileName,
    route = caveConfig and caveConfig.selectedConfig,
    waypoint = nExBot and nExBot.lastLabel,
    targetName = targetName,
    targetHp = call(target, "getHealthPercent"),
    hp = call(player, "getHealthPercent") or value(hppercent),
    mana = call(player, "getManaPercent") or value(manapercent),
    xpHour = nExBot and nExBot.CaveBotData and nExBot.CaveBotData.xpPerHour,
    aiState = aiState,
    aiDecision = aiDecision,
    aiConfidence = aiConfidence,
    aiOutcome = aiOutcome,
    issues = nExBot and nExBot.UI and nExBot.UI.Diagnostics and nExBot.UI.Diagnostics.currentIssues and nExBot.UI.Diagnostics.currentIssues() or {},
  })
end

local function run(actionId, attention)
  local ok, reason = Actions.run(actionId)
  if not ok and attention then attention:setText(Actions.userMessage(actionId, reason)) end
end

function Cockpit.render(content)
  local view = Cockpit.statusProvider().snapshot
  Components.label(content, { id = "cockpitCharacter", text = view.character, textStyle = "windowTitle" })
  Components.label(content, { id = "cockpitProfile", text = "Profile: " .. view.profile, textStyle = "metadata" })
  Components.sectionHeader(content, { title = "Hunt systems" })

  local attention
  for _, engine in ipairs(view.engines) do
    local engineRow = engine
    local row = g_ui.createWidget("NexEngineRow", content)
    row:setId(engineRow.id)
    local item = g_ui.createWidget("NexEngineItem", row)
    item:setId(engineRow.id .. "Item")
    item:setItemId(engineRow.itemId)
    item:setTooltip(engineRow.label)
    item.onClick = function() run(engineRow.editorAction, attention) end
    local info = g_ui.createWidget("NexEngineInfo", row)
    info:setId(engineRow.id .. "Info")
    info:setTooltip("Open " .. engineRow.label .. " settings")
    info.onClick = function() run(engineRow.editorAction, attention) end
    Components.label(info, { id = engineRow.id .. "Label", text = engineRow.label })
    Components.label(info, { id = engineRow.id .. "Detail", text = engineRow.detail, textStyle = "metadata" })
    Components.button(row, {
      id = engineRow.toggleAction,
      style = "NexEngineToggle",
      text = engineRow.statusText,
      variant = STATUS_VARIANT[engineRow.status],
      onClick = function() run(engineRow.toggleAction, attention) end,
    })
  end

  Components.sectionHeader(content, { title = "Now" })
  local now = Components.card(content, { id = "now" })
  Components.keyValueRow(now, { key = "Route", value = view.route .. " / " .. view.waypoint })
  Components.keyValueRow(now, { key = "Target", value = view.targetName .. (view.targetHp and " " .. view.targetHp .. "%" or "") })
  Components.keyValueRow(now, { key = "HP / MP", value = (view.hp or "-") .. "% / " .. (view.mana or "-") .. "%" })
  Components.keyValueRow(now, { key = "XP/h", value = view.xpHour or "-" })

  Components.sectionHeader(content, { title = "AI pulse" })
  local ai = Components.card(content, { id = "aiPulse" })
  Components.keyValueRow(ai, { key = "State", value = view.aiState })
  Components.keyValueRow(ai, { key = "Decision", value = view.aiDecision })
  Components.keyValueRow(ai, { key = "Confidence", value = view.aiConfidence })
  Components.keyValueRow(ai, { key = "Outcome", value = view.aiOutcome })

  Components.sectionHeader(content, { title = "Attention" })
  attention = Components.label(content, {
    id = "attention",
    text = Actions.userMessage(nil, view.attention),
    textStyle = "helper",
    color = #view.issues > 0 and Tokens.colors.warning or Tokens.colors.text.muted,
  })
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.Cockpit = Cockpit
  nExBot.UI["ui.modules.cockpit"] = Cockpit
end

return Cockpit
