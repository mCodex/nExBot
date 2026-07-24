local TacticalIntelligence = nExBot.TacticalIntelligence or dofile("core/intelligence/tactical_intelligence.lua")

local sections = {
  "Overview",
  "Hunt Analytics",
  "Monster Intelligence",
  "ML Models",
  "Targeting Decisions",
  "Resources",
  "Routes & Navigation",
  "Replay",
  "Data Pipeline",
  "Diagnostics",
  "Advanced",
}

local function formatNumber(value)
  value = tonumber(value) or 0
  return tostring(math.floor(value + 0.5))
end

local function formatDuration(ms)
  ms = math.max(0, tonumber(ms) or 0)
  local totalSeconds = math.floor(ms / 1000)
  local hours = math.floor(totalSeconds / 3600)
  local minutes = math.floor((totalSeconds % 3600) / 60)
  local seconds = totalSeconds % 60
  if hours > 0 then
    return string.format("%dh %02dm %02ds", hours, minutes, seconds)
  end
  return string.format("%dm %02ds", minutes, seconds)
end

local function linesToText(lines)
  return table.concat(lines, "\n")
end

local function limited(items, limit)
  local result = {}
  limit = math.max(0, tonumber(limit) or 0)
  for index = 1, math.min(limit, #items) do
    result[#result + 1] = items[index]
  end
  return result
end

local function renderOverview(view)
  local overview = view.overview or {}
  local hunt = view.hunt and view.hunt.summary or {}
  local session = view.session or {}
  local pipeline = view.pipeline or {}
  local lines = {
    "Session state: " .. tostring(overview.lifecycle or "stopped"),
    "Session elapsed: " .. formatDuration(session.elapsedMs or hunt.elapsedMs or 0),
    "XP gained: " .. formatNumber(hunt.xpGained or overview.xpGained),
    "XP/hour: " .. formatNumber(hunt.xpPerHour or overview.xpPerHour),
    "Kills: " .. formatNumber(hunt.kills or overview.kills),
    "Kills/hour: " .. formatNumber(hunt.killsPerHour or overview.killsPerHour),
    "Combat uptime: " .. formatNumber(hunt.combatUptime or overview.combatUptime) .. "%",
    "Current target: " .. tostring((view.targeting and view.targeting.currentTarget and view.targeting.currentTarget.name) or "none"),
    "Current monster context: " .. tostring((view.targeting and view.targeting.currentRouteObjective and view.targeting.currentRouteObjective.name) or "none"),
    "Current route/waypoint: " .. tostring(overview.routeState or "idle") .. " / " .. tostring(overview.waypointIndex or 0),
    "Resource rate: " .. formatNumber((hunt.potionsPerHour or 0) + (hunt.runesPerHour or 0)),
    "Monsters learned: " .. formatNumber((view.monsters and view.monsters.summary and view.monsters.summary.persistedProfiles) or 0),
    "Model observations: " .. formatNumber((view.models and view.models.summary and view.models.summary.samples) or 0),
    "Models learning: " .. formatNumber((view.models and view.models.summary and (view.models.summary.shadow or 0) + (view.models.summary.observing or 0)) or 0),
    "Models actionable: " .. formatNumber((view.models and view.models.summary and view.models.summary.actionable) or 0),
    "Last intelligence event: " .. tostring(overview.lastEvent or "none"),
    "Pipeline health: " .. tostring(overview.pipelineHealth or pipeline.health or "unknown"),
    "Last persistence save: " .. tostring(overview.lastPersistenceSave or "unknown"),
  }
  return linesToText(lines)
end

local function renderHunt(view)
  local hunt = view.hunt and view.hunt.summary or {}
  local trends = view.hunt and view.hunt.trends or {}
  local lines = {
    "Current session",
    "Elapsed: " .. formatDuration(hunt.elapsedMs or 0),
    "XP gained: " .. formatNumber(hunt.xpGained or 0),
    "XP/hour: " .. formatNumber(hunt.xpPerHour or 0),
    "Kills: " .. formatNumber(hunt.kills or 0),
    "Kills/hour: " .. formatNumber(hunt.killsPerHour or 0),
    "Combat uptime: " .. formatNumber(hunt.combatUptime or 0) .. "%",
    "Tiles walked: " .. formatNumber(hunt.tilesWalked or 0),
    "Tiles/kill: " .. formatNumber(hunt.tilesPerKill or 0),
    "Damage taken: " .. formatNumber(hunt.damageTaken or 0),
    "Healing done: " .. formatNumber(hunt.healingDone or 0),
    "Survivability index: " .. formatNumber(hunt.survivabilityIndex or 0),
    "Near-death count: " .. formatNumber(hunt.nearDeathCount or 0),
    "HP potions: " .. formatNumber(hunt.hpPotions or 0),
    "Mana potions: " .. formatNumber(hunt.manaPotions or 0),
    "Runes: " .. formatNumber(hunt.runes or 0),
    "Healing spells: " .. formatNumber(hunt.healingSpells or 0),
    "Attack spells: " .. formatNumber(hunt.attackSpells or 0),
    "Mana spent: " .. formatNumber(hunt.manaSpent or 0),
    "Potions/hour: " .. formatNumber(hunt.potionsPerHour or 0),
    "Runes/hour: " .. formatNumber(hunt.runesPerHour or 0),
    "Mana/hour: " .. formatNumber(hunt.manaPerHour or 0),
    "Resources/kill: " .. formatNumber(hunt.resourcesPerKill or 0),
    "Resources/1k XP: " .. formatNumber(hunt.resourcesPer1000Xp or 0),
    "",
    "Trends",
    "XP trend: " .. tostring(trends.xpPerHour and #trends.xpPerHour or 0) .. " samples",
    "Kill trend: " .. tostring(trends.killsPerHour and #trends.killsPerHour or 0) .. " samples",
    "Resource trend: " .. tostring(trends.potionsPerHour and #trends.potionsPerHour or 0) .. " samples",
  }
  return linesToText(lines)
end

local function renderMonsters(view)
  local monsters = view.monsters or {}
  local lines = {
    "Live monsters: " .. formatNumber(monsters.liveMonsters or 0),
    "Profiles: " .. formatNumber(monsters.summary and monsters.summary.persistedProfiles or 0),
    "Prediction accuracy: " .. formatNumber((monsters.summary and monsters.summary.predictionAccuracy or 0) * 100) .. "%",
    "Wave accuracy: " .. formatNumber((monsters.summary and monsters.summary.waveAccuracy or 0) * 100) .. "%",
    "",
    string.format("%-20s %-10s %-8s %-8s %-8s", "Monster", "State", "Samples", "Conf", "Last seen"),
  }
  for _, profile in ipairs(limited(monsters.profiles or {}, 12)) do
    lines[#lines + 1] = string.format(
      "%-20s %-10s %-8s %-8s %-8s",
      tostring(profile.displayName or profile.monsterKey or "unknown"):sub(1, 20),
      tostring(profile.state or "NO_DATA"):sub(1, 10),
      formatNumber(profile.samples or 0),
      string.format("%.2f", tonumber(profile.confidence) or 0),
      formatDuration(profile.lastSeenAt or 0)
    )
  end
  return linesToText(lines)
end

local function renderModels(view)
  local models = view.models or {}
  local lines = {
    string.format("%-22s %-12s %-8s %-8s %-8s %-8s", "Name", "Capability", "Mode", "Samples", "Conf", "Pending"),
  }
  for _, model in ipairs(models.items or {}) do
    lines[#lines + 1] = string.format(
      "%-22s %-12s %-8s %-8s %-8s %-8s",
      tostring(model.name or "unknown"):sub(1, 22),
      tostring(model.capability or "-"):sub(1, 12),
      tostring(model.mode or "OFF"):sub(1, 8),
      formatNumber(model.samples or 0),
      string.format("%.2f", tonumber(model.confidence) or 0),
      formatNumber(model.pending or 0)
    )
    lines[#lines + 1] = "  Accuracy: " .. tostring(model.accuracy ~= nil and string.format("%.2f", model.accuracy) or "n/a")
    lines[#lines + 1] = "  Why not actionable: " .. tostring(model.whyNotActionable or "actionable")
  end
  return linesToText(lines)
end

local function renderTargeting(view)
  local targeting = view.targeting or {}
  local lines = {
    "Current target: " .. tostring((targeting.currentTarget and targeting.currentTarget.name) or "none"),
    "Current route objective: " .. tostring((targeting.currentRouteObjective and targeting.currentRouteObjective.name) or "none"),
    "Current movement intent: " .. tostring(targeting.currentMovementIntent and targeting.currentMovementIntent.action or "none"),
    "Current attack intent: " .. tostring(targeting.currentAttackIntent and targeting.currentAttackIntent.action or "none"),
    "",
    "Recent decisions",
  }
  for _, item in ipairs(limited(targeting.recentDecisions or {}, 10)) do
    lines[#lines + 1] = string.format("%s | %s <- %s", tostring(item.type or "event"), tostring(item.source or "source"), formatDuration(item.timestamp or 0))
  end
  return linesToText(lines)
end

local function renderResources(view)
  local resources = view.resources or {}
  local totals = resources.totals or {}
  local lines = {
    "Totals",
    "HP potions: " .. formatNumber(totals.hpPotions or 0),
    "Mana potions: " .. formatNumber(totals.manaPotions or 0),
    "Runes: " .. formatNumber(totals.runes or 0),
    "Ammunition: " .. formatNumber(totals.ammunition or 0),
    "Healing casts: " .. formatNumber(totals.healingCasts or 0),
    "Damage taken: " .. formatNumber(totals.damageTaken or 0),
    "",
    "Recent resource observations: " .. formatNumber(#(resources.recent or {})),
    "Recent loot observations: " .. formatNumber(#(resources.loot or {})),
  }
  return linesToText(lines)
end

local function renderRoutes(view)
  local route = view.routes or {}
  return linesToText({
    "Selected route: " .. tostring(route.currentObjective and route.currentObjective.name or "none"),
    "Route state: " .. tostring(route.state or "idle"),
    "Generation: " .. formatNumber(route.generation or 0),
    "Waypoint index: " .. formatNumber(route.waypointIndex or 0),
  })
end

local function renderReplay(view)
  local replay = view.replay or {}
  local lines = {
    "Replay records: " .. formatNumber(replay.recordCount or 0),
  }
  for _, record in ipairs(limited(replay.records or {}, 8)) do
    local outcome = record.outcome or {}
    lines[#lines + 1] = string.format("%s | %s", tostring(outcome.type or "event"), tostring(outcome.reason or ""))
  end
  return linesToText(lines)
end

local function renderPipeline(view)
  local pipeline = view.pipeline or {}
  local lines = {
    "Event count: " .. formatNumber(pipeline.eventCount or 0),
    "Model count: " .. formatNumber(pipeline.modelCount or 0),
    "Health: " .. tostring(pipeline.health or "unknown"),
  }
  for eventType, count in pairs(pipeline.eventCounts or {}) do
    lines[#lines + 1] = eventType .. ": " .. formatNumber(count)
  end
  return linesToText(lines)
end

local function renderDiagnostics(view)
  local diagnostics = view.diagnostics or {}
  local issues = diagnostics.issues or {}
  local lines = {
    "Issue count: " .. formatNumber(diagnostics.issueCount or 0),
  }
  if #issues == 0 then
    lines[#lines + 1] = "No reported issues"
  else
    for _, issue in ipairs(limited(issues, 12)) do
      lines[#lines + 1] = string.format("%s | %s | %s", tostring(issue.code or "unknown"), tostring(issue.message or ""), tostring(issue.action or ""))
    end
  end
  return linesToText(lines)
end

local function renderAdvanced(view)
  return linesToText({
    "Revision: " .. formatNumber(view.revision or 0),
    "Session ID: " .. tostring(view.sessionId or "unknown"),
    "Updated at: " .. tostring(view.updatedAt or view.generatedAt or 0),
  })
end

local function renderSection(view, section)
  if section == "Overview" then
    return renderOverview(view)
  elseif section == "Hunt Analytics" then
    return renderHunt(view)
  elseif section == "Monster Intelligence" then
    return renderMonsters(view)
  elseif section == "ML Models" then
    return renderModels(view)
  elseif section == "Targeting Decisions" then
    return renderTargeting(view)
  elseif section == "Resources" then
    return renderResources(view)
  elseif section == "Routes & Navigation" then
    return renderRoutes(view)
  elseif section == "Replay" then
    return renderReplay(view)
  elseif section == "Data Pipeline" then
    return renderPipeline(view)
  elseif section == "Diagnostics" then
    return renderDiagnostics(view)
  end
  return renderAdvanced(view)
end

local path = nExBot.paths.base .. "/core/intelligence/ui/ui_bridge.otui"
local content = g_resources and g_resources.readFileContents and g_resources.readFileContents(path)
if not content then
  return
end

g_ui.loadUIFromString(content)

local window = UI.createWindow("IntelligenceConsoleWindow")
window:hide()
window.section.onOptionChange = nil
for _, section in ipairs(sections) do
  window.section:addOption(section)
end

local contentText = assert(window:recursiveGetChildById("contentText"), "Tactical Intelligence content widget is missing")

local selected = sections[1]

local function resolveSectionName(option)
  if type(option) == "string" and option ~= "" then
    return option
  end
  return selected
end

local lastRendered = ""

local function render()
  local ok, text = pcall(function()
    local ti = TacticalIntelligence or nExBot.TacticalIntelligence
    if not ti then
      return "Tactical Intelligence is not available."
    end
    local view = ti:view({
      width = window:getWidth(),
      platform = "desktop",
      touch = false,
    }) or {}
    return renderSection(view, resolveSectionName(selected))
  end)
  text = ok and (text or "") or "Tactical Intelligence render failed:\n" .. tostring(text)
  if text ~= lastRendered then
    lastRendered = text
    contentText:setText(text)
  end
end

local function showWindow()
  local root = g_ui.getRootWidget()
  if root then
    window:setWidth(math.max(260, math.min(640, root:getWidth() - 20)))
    window:setHeight(math.max(280, math.min(640, root:getHeight() - 40)))
  end
  window:show()
  window:raise()
  window:focus()
  render()
end

window.section.onOptionChange = function(_, option)
  selected = resolveSectionName(option)
  render()
end

if window.buttons and window.buttons.refresh then
  window.buttons.refresh.onClick = render
end

if window.buttons and window.buttons.close then
  window.buttons.close.onClick = function()
    window:hide()
  end
end

nExBot.TacticalIntelligence.showWindow = showWindow
nExBot.TacticalIntelligence.hideWindow = function()
  window:hide()
end
nExBot.TacticalIntelligence.renderWindow = render

setDefaultTab("Main")
UI.Separator()
UI.Label("AI")
UI.Button("Tactical Intelligence", showWindow):setTooltip("Open Tactical Intelligence")

UnifiedTick.register("tactical_intelligence_ui", {
  interval = 500,
  priority = UnifiedTick.Priority.LOW,
  group = "tactical_intelligence",
  handler = function()
    if window:isVisible() then
      render()
    end
  end,
})
