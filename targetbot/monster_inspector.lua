-- Monster Insights UI — v3.0 (Tabbed)
-- Tabs: 1=Live Monsters  2=Patterns  3=Combat Stats  4=Scenario

MONSTER_INSPECTOR_DEBUG = (type(MONSTER_INSPECTOR_DEBUG) == "boolean" and MONSTER_INSPECTOR_DEBUG) or false

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function safeUnifiedGet(key, default)
  if not UnifiedStorage or not UnifiedStorage.get then return default end
  if not UnifiedStorage.isReady or not UnifiedStorage.isReady() then return default end
  local val = UnifiedStorage.get(key)
  if val ~= nil then return val end
  return default
end

-- Merge in-memory patterns (primary) with stored patterns (secondary/cross-session)
local function getPatterns()
  local mem    = (MonsterAI and MonsterAI.Patterns and MonsterAI.Patterns.knownMonsters) or {}
  local stored = safeUnifiedGet("targetbot.monsterPatterns", {})
  local merged = {}
  for k, v in pairs(stored) do merged[k] = v end
  for k, v in pairs(mem)    do merged[k] = v end  -- memory wins on conflict
  return merged
end

local function isTableEmpty(tbl)
  if not tbl then return true end
  for _ in pairs(tbl) do return false end
  return true
end

local function fmtTime(ms)
  if not ms or (type(ms) == "number" and ms <= 0) then return "-" end
  return os.date("%Y-%m-%d %H:%M:%S", math.floor(ms / 1000))
end

-- ── Style constants ───────────────────────────────────────────────────────────

local COLOR_ACTIVE    = "#3be4d0"
local COLOR_INACTIVE  = "#a4aece"
local BG_ACTIVE       = "#3be4d01a"
local BG_INACTIVE     = "#1b2235"
local BORDER_ACTIVE   = "#3be4d088"
local BORDER_INACTIVE = "#050712"

-- ── Module state ──────────────────────────────────────────────────────────────

nExBot = nExBot or {}
nExBot.MonsterInspector = nExBot.MonsterInspector or {}

local activeTab         = 1
local tabPanels         = {}   -- [1..4] ScrollablePanel widgets
local tabBtns           = {}   -- [1..4] NxButton widgets
local refreshInProgress = false
local lastRefreshMs     = 0
local MIN_REFRESH_MS    = 2500
local liveUpdateActive  = false

-- ── Style import ──────────────────────────────────────────────────────────────

local function tryImportStyle()
  local candidates = {
    "/targetbot/monster_inspector.otui",
    "targetbot/monster_inspector.otui",
  }
  if nExBot and nExBot.paths then
    candidates[#candidates + 1] = nExBot.paths.base .. "/targetbot/monster_inspector.otui"
  elseif BotConfigName then
    candidates[#candidates + 1] = "/bot/" .. BotConfigName .. "/targetbot/monster_inspector.otui"
  end
  for i = 1, #candidates do
    local path = candidates[i]
    if g_resources and g_resources.fileExists and g_resources.fileExists(path) then
      pcall(function() g_ui.importStyle(path) end)
      return true
    end
  end
  pcall(function() g_ui.importStyle("/targetbot/monster_inspector.otui") end)
  return false
end
tryImportStyle()

-- ── Widget binding ────────────────────────────────────────────────────────────

local function findChild(parent, id)
  if not parent or not id then return nil end
  local ok, w = pcall(function() return parent[id] end)
  if ok and w then return w end
  ok, w = pcall(function() return parent:getChildById(id) end)
  if ok and w then return w end
  return nil
end

local function updateWidgetRefs()
  if not MonsterInspectorWindow then
    tabPanels = {}; tabBtns = {}; return
  end
  local tabBar = findChild(MonsterInspectorWindow, "tabBar")
  for i = 1, 4 do
    tabBtns[i]   = tabBar and findChild(tabBar, "tab" .. i .. "btn") or nil
    tabPanels[i] = findChild(MonsterInspectorWindow, "tab" .. i) or nil
  end
end

-- ── Tab switching ─────────────────────────────────────────────────────────────

local function applyTabStyle(idx, isActive)
  local btn = tabBtns[idx]
  if not btn then return end
  pcall(function()
    btn:setColor(isActive and COLOR_ACTIVE or COLOR_INACTIVE)
    btn:setBackgroundColor(isActive and BG_ACTIVE or BG_INACTIVE)
    btn:setBorderColor(isActive and BORDER_ACTIVE or BORDER_INACTIVE)
  end)
end

local function switchTab(idx)
  activeTab = idx
  for i = 1, 4 do
    local panel = tabPanels[i]
    if panel then
      pcall(function()
        if i == idx then panel:show() else panel:hide() end
      end)
    end
    applyTabStyle(i, i == idx)
    -- Show/hide matching scrollbar
    if MonsterInspectorWindow then
      local sb = findChild(MonsterInspectorWindow, "tab" .. i .. "Scroll")
      if sb then
        pcall(function()
          if i == idx then sb:show() else sb:hide() end
        end)
      end
    end
  end
end

-- ── Tab content builders ──────────────────────────────────────────────────────

local function buildLiveTab()
  local lines = {}
  local live  = (MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.monsters) or {}
  local count = 0
  for _ in pairs(live) do count = count + 1 end

  table.insert(lines, string.format("Live Tracker — %d creature(s)", count))
  table.insert(lines, "")

  if count == 0 then
    -- Fallback: enumerate spectators directly so the tab is never blank
    local nearby = {}
    local p = player and player:getPosition()
    if p then
      pcall(function()
        local specs = (g_map and g_map.getSpectatorsInRange
          and g_map.getSpectatorsInRange(p, false, 8, 8)) or {}
        for _, c in ipairs(specs) do
          local ok2, valid = pcall(function()
            return c:isMonster() and not c:isDead() and not c:isRemoved()
          end)
          if ok2 and valid then
            local name = "?"
            pcall(function() name = c:getName() end)
            table.insert(nearby, name)
          end
        end
      end)
    end
    if #nearby > 0 then
      table.insert(lines, string.format("  %d nearby (TargetBot off — enable for full tracking):", #nearby))
      table.insert(lines, "")
      local seen = {}
      for _, name in ipairs(nearby) do
        seen[name] = (seen[name] or 0) + 1
      end
      local sorted = {}
      for name, cnt in pairs(seen) do sorted[#sorted+1] = {name=name, cnt=cnt} end
      table.sort(sorted, function(a,b) return a.cnt > b.cnt end)
      for _, e in ipairs(sorted) do
        table.insert(lines, string.format("  %dx %s", e.cnt, e.name))
      end
    else
      table.insert(lines, "  No creatures currently tracked.")
      table.insert(lines, "  Enable TargetBot for live tracking data.")
    end
    return table.concat(lines, "\n")
  end

  table.insert(lines, string.format("  %-18s %6s %5s %7s %6s %7s %5s %6s",
    "Name", "Samps", "Conf", "CD(ms)", "DPS", "Missiles", "Speed", "Facing"))
  table.insert(lines, string.rep("-", 76))

  local tbl = {}
  for id, d in pairs(live) do
    local facing = false
    if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.directions then
      local rt = MonsterAI.RealTime.directions[id]
      facing = rt and rt.facingPlayerSince ~= nil
    end
    local dps = 0
    if MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.getDPS then
      local ok, val = pcall(MonsterAI.Tracker.getDPS, id)
      if ok and val then dps = val end
    end
    table.insert(tbl, {
      name     = d.name or "unknown",
      samples  = d.samples and #d.samples or 0,
      conf     = d.confidence or 0,
      cd       = d.ewmaCooldown or d.predictedWaveCooldown,
      dps      = dps,
      missiles = d.missileCount or 0,
      speed    = d.avgSpeed or 0,
      facing   = facing,
    })
  end
  table.sort(tbl, function(a, b) return (a.conf or 0) > (b.conf or 0) end)

  for i = 1, math.min(#tbl, 20) do
    local e    = tbl[i]
    local confs  = string.format("%.2f", e.conf)
    local cdStr  = (type(e.cd) == "number" and string.format("%d", math.floor(e.cd))) or "-"
    local faceStr= e.facing and "YES" or "no"
    table.insert(lines, string.format("  %-18s %6d %5s %7s %6.1f %7d %5.2f %6s",
      e.name:sub(1, 18), e.samples, confs, cdStr, e.dps or 0, e.missiles, e.speed, faceStr))
  end

  if #tbl > 20 then
    table.insert(lines, string.format("  ... and %d more", #tbl - 20))
  end
  return table.concat(lines, "\n")
end

local function buildPatternsTab()
  local lines    = {}
  local patterns = getPatterns()
  local count    = 0
  for _ in pairs(patterns) do count = count + 1 end

  table.insert(lines, string.format("Learned Patterns — %d monster type(s)", count))
  table.insert(lines, "")

  if count == 0 then
    table.insert(lines, "  No patterns yet.")
    table.insert(lines, "  Patterns are learned after observing 2+ wave attacks")
    table.insert(lines, "  from the same monster type.")
    return table.concat(lines, "\n")
  end

  table.insert(lines, string.format("  %-20s %8s %6s %5s  %s",
    "Name", "CD(ms)", "Var", "Conf", "Last Seen"))
  table.insert(lines, string.rep("-", 68))

  local sorted = {}
  for name, p in pairs(patterns) do
    table.insert(sorted, { name = name, p = p })
  end
  table.sort(sorted, function(a, b)
    return (a.p.confidence or 0) > (b.p.confidence or 0)
  end)

  for _, item in ipairs(sorted) do
    local p    = item.p
    local cd   = p.waveCooldown and string.format("%d", math.floor(p.waveCooldown)) or "-"
    local var  = p.waveVariance and string.format("%.1f", p.waveVariance) or "-"
    local conf = p.confidence   and string.format("%.2f", p.confidence)   or "-"
    local last = p.lastSeen     and fmtTime(p.lastSeen) or "-"
    table.insert(lines, string.format("  %-20s %8s %6s %5s  %s",
      item.name:sub(1, 20), cd, var, conf, last))
  end

  return table.concat(lines, "\n")
end

local function buildStatsTab()
  local lines = {}
  local stats = (MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.stats)
    or { waveAttacksObserved = 0, areaAttacksObserved = 0, totalDamageReceived = 0 }

  table.insert(lines, string.format("Monster AI  v%s", MonsterAI and MonsterAI.VERSION or "?"))
  table.insert(lines, "")

  if MonsterAI and MonsterAI.Telemetry and MonsterAI.Telemetry.session then
    local s   = MonsterAI.Telemetry.session
    local dur = ((now or 0) - (s.startTime or 0)) / 1000
    table.insert(lines, "── Session ─────────────────────────────────────")
    table.insert(lines, string.format("  Kills: %d   Deaths: %d   Duration: %.0fs   Tracked: %d",
      s.killCount or 0, s.deathCount or 0, dur, s.totalMonstersTracked or 0))
  end

  table.insert(lines, "")
  table.insert(lines, "── Combat ──────────────────────────────────────")
  table.insert(lines, string.format("  Damage Received: %d   Waves: %d   Area: %d",
    stats.totalDamageReceived or 0, stats.waveAttacksObserved or 0, stats.areaAttacksObserved or 0))

  if MonsterAI and MonsterAI.Metrics and MonsterAI.Metrics.getSummary then
    local ok, s = pcall(MonsterAI.Metrics.getSummary)
    if ok and s and s.combat then
      table.insert(lines, string.format("  DPS Received: %.1f   KDR: %.2f",
        s.combat.dpsReceived or 0, s.combat.kdr or 0))
    end
  end

  if MonsterAI and MonsterAI.getPredictionStats then
    local ok, ps = pcall(MonsterAI.getPredictionStats)
    if ok and ps then
      table.insert(lines, "")
      table.insert(lines, "── Predictions ─────────────────────────────────")
      table.insert(lines, string.format("  Events: %d   Correct: %d   Missed: %d   Acc: %.1f%%",
        ps.eventsProcessed or 0, ps.predictionsCorrect or 0,
        ps.predictionsMissed or 0, (ps.accuracy or 0) * 100))
      if ps.wavePredictor then
        local wp = ps.wavePredictor
        table.insert(lines, string.format("  WavePredictor: Total=%d  Correct=%d  FalsePos=%d  Acc=%.1f%%",
          wp.total or 0, wp.correct or 0, wp.falsePositive or 0, (wp.accuracy or 0) * 100))
      end
    end
  end

  if MonsterAI and MonsterAI.SpellTracker then
    local st  = MonsterAI.SpellTracker
    local ok, sts = pcall(function() return st.getStats and st.getStats() or {} end)
    sts = ok and sts or {}
    table.insert(lines, "")
    table.insert(lines, "── SpellTracker ─────────────────────────────────")
    table.insert(lines, string.format("  Total: %d   /min: %.1f   Types: %d",
      sts.totalSpellsCast or 0, sts.spellsPerMinute or 0, sts.uniqueMissileTypes or 0))

    local casters = {}
    if st.monsterSpells then
      for _, d in pairs(st.monsterSpells) do
        if (d.totalSpellsCast or 0) > 0 then
          table.insert(casters, { name = d.name or "?", spells = d.totalSpellsCast,
            cd = d.ewmaSpellCooldown })
        end
      end
      table.sort(casters, function(a, b) return a.spells > b.spells end)
    end
    if #casters > 0 then
      table.insert(lines, "  Top casters:")
      for i = 1, math.min(5, #casters) do
        local c   = casters[i]
        local cdStr = c.cd and string.format("%dms", math.floor(c.cd)) or "-"
        table.insert(lines, string.format("    %-18s %d spells   cd=%s",
          c.name:sub(1, 18), c.spells, cdStr))
      end
    end
  end

  if MonsterAI and MonsterAI.getImmediateThreat then
    local ok, t = pcall(MonsterAI.getImmediateThreat)
    if ok and t then
      table.insert(lines, "")
      table.insert(lines, "── Threat ───────────────────────────────────────")
      table.insert(lines, string.format("  Status: %s   Level: %.1f   High-Threat: %d",
        t.immediateThreat and "DANGER!" or "Safe",
        t.totalThreat or 0, t.highThreatCount or 0))
    end
  end

  return table.concat(lines, "\n")
end

local function buildScenarioTab()
  local lines = {}

  if MonsterAI and MonsterAI.Scenario then
    local ok, sc = pcall(function()
      return MonsterAI.Scenario.getStats and MonsterAI.Scenario.getStats() or {}
    end)
    sc = ok and sc or {}
    local cfg = sc.config or {}
    table.insert(lines, "── Scenario ─────────────────────────────────────")
    local desc = cfg.description and (" (" .. cfg.description .. ")") or ""
    table.insert(lines, string.format("  Type: %s%s",
      (sc.currentScenario or "unknown"):upper(), desc))
    table.insert(lines, string.format("  Monsters: %d   Cluster: %s   Zigzag: %s   Switches: %d",
      sc.monsterCount or 0,
      sc.clusterType or "none",
      sc.isZigzagging and "YES!" or "No",
      sc.consecutiveSwitches or 0))
    if sc.targetLockId then
      local ld    = MonsterAI.Tracker and MonsterAI.Tracker.monsters and MonsterAI.Tracker.monsters[sc.targetLockId]
      local lname = ld and ld.name or "Unknown"
      table.insert(lines, string.format("  Target Lock: %s", lname))
    end
    if cfg.switchCooldownMs then
      table.insert(lines, string.format("  Anti-Zigzag: Cooldown=%dms   Stickiness=%d",
        cfg.switchCooldownMs, cfg.targetStickiness or 0))
    end
  end

  if MonsterAI and MonsterAI.Reachability then
    local ok, rs = pcall(function()
      return MonsterAI.Reachability.getStats and MonsterAI.Reachability.getStats() or {}
    end)
    rs = ok and rs or {}
    table.insert(lines, "")
    table.insert(lines, "── Reachability ─────────────────────────────────")
    local hitRate = (rs.checksPerformed or 0) > 0
      and (rs.cacheHits or 0) / ((rs.checksPerformed or 0) + (rs.cacheHits or 0)) * 100 or 0
    table.insert(lines, string.format("  Checks: %d   Cache Hit: %.0f%%   Blocked: %d   Reachable: %d",
      rs.checksPerformed or 0, hitRate, rs.blocked or 0, rs.reachable or 0))
    if rs.byReason then
      local r = rs.byReason
      if (r.no_path or 0) > 0 or (r.blocked_tile or 0) > 0 then
        table.insert(lines, string.format("  NoPath: %d   Tile: %d   Elevation: %d   TooFar: %d",
          r.no_path or 0, r.blocked_tile or 0, r.elevation or 0, r.too_far or 0))
      end
    end
  end

  if MonsterAI and MonsterAI.TargetBot and MonsterAI.TargetBot.getDangerLevel then
    local ok, danger, threats = pcall(MonsterAI.TargetBot.getDangerLevel)
    if ok and danger then
      threats = threats or {}
      table.insert(lines, "")
      table.insert(lines, "── Danger ───────────────────────────────────────")
      table.insert(lines, string.format("  Level: %.1f/10   Active Threats: %d", danger, #threats))
      for i = 1, math.min(5, #threats) do
        local t = threats[i]
        table.insert(lines, string.format("    %d. %s (%.1f)%s",
          i, t.name, t.level, t.imminent and " [IMMINENT]" or ""))
      end
    end
  end

  if isTableEmpty(lines) then
    table.insert(lines, "  No scenario data available.")
  end

  return table.concat(lines, "\n")
end

-- ── Builders dispatch ─────────────────────────────────────────────────────────

local BUILDERS = {
  buildLiveTab,
  buildPatternsTab,
  buildStatsTab,
  buildScenarioTab,
}

-- ── Live update loop ──────────────────────────────────────────────────────────

local function doLiveUpdate()
  if not liveUpdateActive then return end
  if not MonsterInspectorWindow or not MonsterInspectorWindow:isVisible() then
    liveUpdateActive = false
    return
  end
  refreshInProgress = false
  refreshActiveTab()
  schedule(3000, doLiveUpdate)
end

local function startLiveUpdate()
  if liveUpdateActive then return end
  liveUpdateActive = true
  schedule(3000, doLiveUpdate)
end

local function stopLiveUpdate()
  liveUpdateActive = false
end

-- ── Refresh ───────────────────────────────────────────────────────────────────

local function refreshActiveTab()
  if not MonsterInspectorWindow or not MonsterInspectorWindow:isVisible() then return end
  if refreshInProgress then return end
  if now and (now - lastRefreshMs) < MIN_REFRESH_MS then return end

  refreshInProgress = true
  if now then lastRefreshMs = now end

  local panel = tabPanels[activeTab]
  if panel then
    local textLabel = findChild(panel, "text")
    if textLabel then
      local ok, txt = pcall(BUILDERS[activeTab])
      pcall(function() textLabel:setText(ok and txt or ("Error: " .. tostring(txt))) end)
    end
  end

  refreshInProgress = false
end

-- Public alias kept for backward compatibility with external callers
function refreshPatterns()
  refreshActiveTab()
end

-- ── Window lifecycle ──────────────────────────────────────────────────────────

local function bindButtons(win)
  if not win then return end
  local buttons = findChild(win, "buttons")
  if not buttons then return end

  local refreshBtn = findChild(buttons, "refresh")
  local clearBtn   = findChild(buttons, "clear")
  local closeBtn   = findChild(buttons, "close")

  if refreshBtn then
    refreshBtn.onClick = function()
      refreshInProgress = false
      lastRefreshMs = 0   -- bypass throttle on manual refresh
      refreshActiveTab()
    end
  end

  if clearBtn then
    clearBtn.onClick = function()
      if UnifiedStorage then UnifiedStorage.set("targetbot.monsterPatterns", {}) end
      if MonsterAI and MonsterAI.Patterns then MonsterAI.Patterns.knownMonsters = {} end
      refreshInProgress = false
      refreshActiveTab()
      print("[MonsterInspector] Cleared stored monster patterns")
    end
  end

  if closeBtn then
    closeBtn.onClick = function() win:hide() end
  end

  local tabBar = findChild(win, "tabBar")
  if tabBar then
    for i = 1, 4 do
      local btn = findChild(tabBar, "tab" .. i .. "btn")
      if btn then
        local idx = i
        btn.onClick = function()
          switchTab(idx)
          refreshInProgress = false
          refreshActiveTab()
        end
      end
    end
  end

  win.onVisibilityChange = function(widget, visible)
    if visible then
      updateWidgetRefs()
      switchTab(activeTab)
      refreshInProgress = false
      lastRefreshMs = 0
      refreshActiveTab()
      startLiveUpdate()
    else
      stopLiveUpdate()
    end
  end
end

local function createWindowIfMissing()
  if MonsterInspectorWindow and MonsterInspectorWindow:isVisible() then
    return MonsterInspectorWindow
  end
  tryImportStyle()
  local ok, win = pcall(function() return UI.createWindow("MonsterInspectorWindow") end)
  if not ok or not win then
    warn("[MonsterInspector] Failed to create MonsterInspectorWindow")
    MonsterInspectorWindow = nil
    return nil
  end
  MonsterInspectorWindow = win
  pcall(function() MonsterInspectorWindow:hide() end)
  pcall(function() updateWidgetRefs() end)
  pcall(function() bindButtons(win) end)
  pcall(function() switchTab(1) end)
  return MonsterInspectorWindow
end

createWindowIfMissing()
updateWidgetRefs()
if MonsterInspectorWindow then
  pcall(function() bindButtons(MonsterInspectorWindow) end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

nExBot.MonsterInspector.refresh         = refreshActiveTab
nExBot.MonsterInspector.rebindButtons   = function() bindButtons(MonsterInspectorWindow) end
nExBot.MonsterInspector.refreshPatterns = refreshPatterns

nExBot.MonsterInspector.clear = function()
  if UnifiedStorage then UnifiedStorage.set("targetbot.monsterPatterns", {}) end
  if MonsterAI and MonsterAI.Patterns then MonsterAI.Patterns.knownMonsters = {} end
  refreshInProgress = false
  refreshActiveTab()
end

nExBot.MonsterInspector.showWindow = function()
  if not MonsterInspectorWindow then createWindowIfMissing() end
  if MonsterInspectorWindow then
    MonsterInspectorWindow:show()
    updateWidgetRefs()
    switchTab(activeTab)
    if MonsterAI and MonsterAI.updateAll then pcall(MonsterAI.updateAll) end
    refreshInProgress = false
    refreshActiveTab()
  end
end

nExBot.MonsterInspector.toggleWindow = function()
  if not MonsterInspectorWindow then createWindowIfMissing() end
  if MonsterInspectorWindow then
    if MonsterInspectorWindow:isVisible() then
      MonsterInspectorWindow:hide()
    else
      nExBot.MonsterInspector.showWindow()
    end
  end
end

-- EventBus: auto-refresh on MonsterAI state changes
if EventBus and EventBus.on then
  EventBus.on("monsterai:state_updated", function()
    if MonsterInspectorWindow and MonsterInspectorWindow:isVisible() then
      refreshActiveTab()
    end
  end, 0)
end
