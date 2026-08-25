local TacticalIntelligence = nExBot.TacticalIntelligence or dofile("core/intelligence/tactical_intelligence.lua")

local sections = {
  "Overview", "Live Decisions", "Monsters", "Hunt Performance", "Learning", "Diagnostics",
}

local nowMs = (nExBot.Shared and nExBot.Shared.nowMs) or function() return os.time() * 1000 end

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

local function timeAgo(ms)
  if not ms or ms <= 0 then return "never" end
  local elapsed = math.max(0, nowMs() - ms)
  local sec = math.floor(elapsed / 1000)
  if sec < 5 then return "just now" end
  if sec < 60 then return sec .. "s ago" end
  local min = math.floor(sec / 60)
  if min < 60 then return min .. "m ago" end
  return formatDuration(elapsed) .. " ago"
end

local function limited(items, limit)
  local result = {}
  limit = math.max(0, tonumber(limit) or 0)
  for index = 1, math.min(limit, #items) do
    result[#result + 1] = items[index]
  end
  return result
end

local widgetsById = {}

local function label(panel, id, text, style)
  local widget = widgetsById[id]
  if not widget then
    widget = g_ui.createWidget(style or "NexAiMetric", panel)
    widget:setId(id)
    widgetsById[id] = widget
  end
  if widget:getText() ~= text then
    widget:setText(text)
  end
  return widget
end

local function heading(panel, id, text)
  return label(panel, id, text, "NexAiHeading")
end

local function clearPanel(panel)
  local children = panel:getChildren()
  for i = #children, 1, -1 do
    children[i]:destroy()
  end
  widgetsById = {}
end

local function hasData(view)
  return view and view.overview and (view.overview.xpGained or 0) + (view.overview.kills or 0) > 0
end

local function renderOverview(view, panel)
  if not hasData(view) then
    label(panel, "coldstart", "No data yet — start hunting to populate.")
    return
  end
  local o = view.overview or {}
  local s = view.session or {}
  local p = view.pipeline or {}
  heading(panel, "h_overview", "Session Overview")
  label(panel, "r_lifecycle", "Session: " .. tostring(o.lifecycle or "stopped"))
  label(panel, "r_elapsed", "Elapsed: " .. formatDuration(s.elapsedMs or 0))
  label(panel, "r_xp", "XP: " .. formatNumber(o.xpGained or 0) .. " (" .. formatNumber(o.xpPerHour or 0) .. "/h)")
  label(panel, "r_kills", "Kills: " .. formatNumber(o.kills or 0) .. " (" .. formatNumber(o.killsPerHour or 0) .. "/h)")
  label(panel, "r_target", "Target: " .. tostring(view.targeting and view.targeting.currentTarget and view.targeting.currentTarget.name or "none"))
  label(panel, "r_route", "Route: " .. tostring(o.routeState or "idle") .. " / wp " .. formatNumber(o.waypointIndex or 0))
  label(panel, "r_combat", "Combat uptime: " .. formatNumber(o.combatUptime or 0) .. "%")
  label(panel, "r_models", "Models: " .. formatNumber(o.actionableModels or 0) .. " actionable of " .. formatNumber(o.modelCount or 0))
  label(panel, "r_pipeline", "Pipeline: " .. tostring(o.pipelineHealth or p.health or "unknown"))
  label(panel, "r_save", "Last save: " .. timeAgo(o.lastPersistenceSave))
end

local function renderDecisions(view, panel)
  local t = view.targeting or {}
  heading(panel, "h_decisions", "Live Decisions")
  label(panel, "r_target", "Current target: " .. tostring((t.currentTarget and t.currentTarget.name) or "none"))
  label(panel, "r_movement", "Movement: " .. tostring(t.currentMovementIntent and t.currentMovementIntent.action or "none"))
  label(panel, "r_attack", "Attack: " .. tostring(t.currentAttackIntent and t.currentAttackIntent.action or "none"))
  label(panel, "r_lure", "Lure: " .. tostring(t.currentLureState or "inactive"))
  label(panel, "r_pull", "Pull: " .. tostring(t.currentPullState or "inactive"))
  label(panel, "r_wave", "Wave prediction: " .. tostring(t.currentWavePrediction or "none"))
  if t.recentDecisions and #t.recentDecisions > 0 then
    label(panel, "h_recent", "Recent decisions")
    for i, item in ipairs(limited(t.recentDecisions, 5)) do
      label(panel, "rd_" .. i, "  " .. tostring(item.type or "event"))
    end
  end
end

local function renderMonsters(view, panel)
  local m = view.monsters or {}
  local summary = m.summary or {}
  heading(panel, "h_monsters", "Monsters")
  label(panel, "r_live", "Live: " .. formatNumber(summary.liveMonsters or m.liveMonsters or 0))
  label(panel, "r_profiles", "Profiles: " .. formatNumber(summary.persistedProfiles or 0))
  if m.profiles and #m.profiles > 0 then
    for i, profile in ipairs(limited(m.profiles, 10)) do
      label(panel, "mp_" .. i, tostring(profile.displayName or profile.monsterKey or "?") .. " — " .. tostring(profile.state or "NO_DATA") .. " (" .. formatNumber(profile.samples or 0) .. " samples, conf " .. string.format("%.2f", tonumber(profile.confidence) or 0) .. ", seen " .. timeAgo(profile.lastSeenAt) .. ")")
    end
  end
end

local function renderHunt(view, panel)
  local h = view.hunt and view.hunt.summary or {}
  local trends = view.hunt and view.hunt.trends or {}
  heading(panel, "h_hunt", "Hunt Performance")
  label(panel, "r_elapsed", "Elapsed: " .. formatDuration(h.elapsedMs or 0))
  label(panel, "r_xp", "XP: " .. formatNumber(h.xpGained or 0) .. " (" .. formatNumber(h.xpPerHour or 0) .. "/h)")
  label(panel, "r_kills", "Kills: " .. formatNumber(h.kills or 0) .. " (" .. formatNumber(h.killsPerHour or 0) .. "/h)")
  label(panel, "r_combat", "Combat uptime: " .. formatNumber(h.combatUptime or 0) .. "%")
  label(panel, "r_tiles", "Tiles walked: " .. formatNumber(h.tilesWalked or 0) .. " (" .. formatNumber(h.tilesPerKill or 0) .. "/kill)")
  label(panel, "r_damage", "Damage taken: " .. formatNumber(h.damageTaken or 0))
  label(panel, "r_healing", "Healing done: " .. formatNumber(h.healingDone or 0))
  label(panel, "r_survivability", "Survivability: " .. formatNumber(h.survivabilityIndex or 0) .. "%")
  label(panel, "r_near_death", "Near-death events: " .. formatNumber(h.nearDeathCount or 0))
  label(panel, "r_hp_pots", "HP potions: " .. formatNumber(h.hpPotions or 0))
  label(panel, "r_mana_pots", "Mana potions: " .. formatNumber(h.manaPotions or 0))
  label(panel, "r_runes", "Runes: " .. formatNumber(h.runes or 0))
  label(panel, "r_heal_spells", "Healing spells: " .. formatNumber(h.healingSpells or 0))
  label(panel, "r_mana", "Mana spent: " .. formatNumber(h.manaSpent or 0))
  if trends.xpPerHour and #trends.xpPerHour > 0 then
    label(panel, "h_trends", "Trends")
    label(panel, "r_xp_trend", "  XP samples: " .. #trends.xpPerHour)
    label(panel, "r_kill_trend", "  Kill samples: " .. #trends.killsPerHour)
  end
end

local function renderLearning(view, panel)
  local models = view.models or {}
  heading(panel, "h_learning", "Learning")
  label(panel, "r_model_count", "Models: " .. formatNumber(models.summary and models.summary.total or 0) .. " total, " .. formatNumber(models.summary and models.summary.actionable or 0) .. " actionable")
  label(panel, "r_obs", "Total observations: " .. formatNumber(models.summary and models.summary.samples or 0))
  if models.items and #models.items > 0 then
    for i, model in ipairs(limited(models.items, 15)) do
      local line = tostring(model.name or "?") .. " [" .. tostring(model.mode or "OFF") .. "] " .. formatNumber(model.samples or 0) .. " obs, conf " .. string.format("%.2f", tonumber(model.confidence) or 0)
      if model.accuracy ~= nil then
        line = line .. ", acc " .. string.format("%.2f", model.accuracy)
      end
      label(panel, "md_" .. i, line)
    end
  end
end

local function renderDiagnostics(view, panel)
  local d = view.diagnostics or {}
  local p = view.pipeline or {}
  heading(panel, "h_diag", "Diagnostics")
  label(panel, "r_events", "Event count: " .. formatNumber(p.eventCount or 0))
  label(panel, "r_health", "Health: " .. tostring(p.health or "unknown"))
  if p.eventCounts then
    for eventType, count in pairs(p.eventCounts) do
      if count > 0 then
        label(panel, "evt_" .. eventType, "  " .. tostring(eventType) .. ": " .. formatNumber(count))
      end
    end
  end
  label(panel, "r_issues", "Issues: " .. formatNumber(d.issueCount or 0))
  if d.issues and #d.issues > 0 then
    for i, issue in ipairs(limited(d.issues, 5)) do
      label(panel, "iss_" .. i, "  " .. tostring(issue.code or "?") .. ": " .. tostring(issue.message or ""))
    end
  end
end

local renderers = {
  Overview = renderOverview,
  ["Live Decisions"] = renderDecisions,
  Monsters = renderMonsters,
  ["Hunt Performance"] = renderHunt,
  Learning = renderLearning,
  Diagnostics = renderDiagnostics,
}

local path = nExBot.paths.base .. "/core/intelligence/ui/ui_bridge.otui"
local content = g_resources and g_resources.readFileContents and g_resources.readFileContents(path)
if not content then
  return
end

local window, contentPanel, statusMode, statusHealth, statusTarget, lastSection, selected = nil, nil, nil, nil, nil, nil, sections[1]
local ready = false

local function init()
  local ok, err = pcall(function()
    g_ui.loadUIFromString(content)
    local w = UI.createWindow("IntelligenceDashboardWindow")
    w:hide()
    w.section.onOptionChange = nil
    for _, s in ipairs(sections) do
      w.section:addOption(s)
    end
    window = w
    contentPanel = window:recursiveGetChildById("contentPanel")
    statusMode = window:recursiveGetChildById("statusMode")
    statusHealth = window:recursiveGetChildById("statusHealth")
    statusTarget = window:recursiveGetChildById("statusTarget")
  end)

  if not ok then
    if nExBot.warn then nExBot.warn("Intelligence dashboard window not available: " .. tostring(err)) end
    return false
  end
  return true
end

ready = init()

local function resolveSectionName(option)
  if type(option) == "string" and option ~= "" then
    return option
  end
  return selected
end

local function render()
  if not ready or not window or not contentPanel then return end
  local currentSection = resolveSectionName(selected)
  if currentSection ~= lastSection then
    clearPanel(contentPanel)
    lastSection = currentSection
  end
  local ok, err = pcall(function()
    local ti = TacticalIntelligence or nExBot.TacticalIntelligence
    if not ti then
      clearPanel(contentPanel)
      label(contentPanel, "err", "Tactical Intelligence is not available.")
      return
    end
    local view = ti:view({
      width = window:getWidth(),
      platform = "desktop",
      touch = false,
    }) or {}
    local overview = view.overview or {}
    local pipeline = view.pipeline or {}
    local targeting = view.targeting or {}
    statusMode:setText("AI  " .. tostring(overview.lifecycle or "idle"))
    statusHealth:setText("Pipeline  " .. tostring(overview.pipelineHealth or pipeline.health or "unknown"))
    statusTarget:setText("Target  " .. tostring(targeting.currentTarget and targeting.currentTarget.name or "none"))
    local renderer = renderers[currentSection]
    if renderer then
      renderer(view, contentPanel)
    end
  end)
  if not ok then
    clearPanel(contentPanel)
    label(contentPanel, "err", "Render failed: " .. tostring(err))
  end
end

local function showWindow()
  if not ready or not window then return end
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

if ready then
  window.section.onOptionChange = function(_, option)
    if not ready then return end
    selected = resolveSectionName(option)
    clearPanel(contentPanel)
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
end

nExBot.TacticalIntelligence.showWindow = showWindow
nExBot.TacticalIntelligence.hideWindow = function()
  if not ready or not window then return end
  window:hide()
end
nExBot.TacticalIntelligence.renderWindow = render

UnifiedTick.register("tactical_intelligence_ui", {
  interval = 500,
  priority = UnifiedTick.Priority.LOW,
  group = "tactical_intelligence",
  handler = function()
    if ready and window and window:isVisible() then
      render()
    end
  end,
})
