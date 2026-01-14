-- Monster Insights UI

-- Toggleable debug for this module (set MONSTER_INSPECTOR_DEBUG = true in console to enable)
MONSTER_INSPECTOR_DEBUG = (type(MONSTER_INSPECTOR_DEBUG) == "boolean" and MONSTER_INSPECTOR_DEBUG) or false

-- Import the style first (try multiple paths to be robust across environments)
local function tryImportStyle()
  local candidates = {}
  -- Common relative paths
  candidates[1] = "/targetbot/monster_inspector.otui"
  candidates[2] = "targetbot/monster_inspector.otui"
  -- Try fully-qualified path using shared BotConfigName if available
  if BotConfigName then
    candidates[#candidates + 1] = "/bot/" .. BotConfigName .. "/targetbot/monster_inspector.otui"
  else
    -- fallback to resolving via modules table if present
    local ok, cfg = pcall(function() return modules.game_bot.contentsPanel.config:getCurrentOption().text end)
    if ok and cfg then
      candidates[#candidates + 1] = "/bot/" .. cfg .. "/targetbot/monster_inspector.otui"
    end
  end

  for i = 1, #candidates do
    local path = candidates[i]
    if g_resources and g_resources.fileExists and g_resources.fileExists(path) then
      pcall(function() g_ui.importStyle(path) end)
  
      return true
    end
  end

  -- Last resort: try the default import and let underlying API log the reason
  pcall(function() g_ui.importStyle("/targetbot/monster_inspector.otui") end)
  warn("[MonsterInspector] Failed to locate '/targetbot/monster_inspector.otui' via tested paths. UI may be missing or path differs from expected.")
  return false
end
tryImportStyle()
-- Create window from style and keep it hidden by default. Provide a helper to (re)create on demand.
local function createWindowIfMissing()
  if MonsterInspectorWindow and MonsterInspectorWindow:isVisible() then return MonsterInspectorWindow end

  -- Try import and create window
  tryImportStyle()
  local ok, win = pcall(function() return UI.createWindow("MonsterInspectorWindow") end)
  if not ok or not win then
    warn("[MonsterInspector] Failed to create MonsterInspectorWindow - style may be missing or invalid")
    MonsterInspectorWindow = nil
    return nil
  end

  MonsterInspectorWindow = win
  -- Ensure it's hidden initially
  pcall(function() MonsterInspectorWindow:hide() end)


  -- Rebind buttons and visibility handlers (same logic as below)
  local refreshBtn = SafeCall.globalWithFallback("getWidgetById", nil) -- noop placeholder
  -- Setup actual buttons if present
  local function bindButtons()
    local refreshBtn = MonsterInspectorWindow.buttons and MonsterInspectorWindow.buttons.refresh
    local exportBtn = MonsterInspectorWindow.buttons and MonsterInspectorWindow.buttons.export
    local clearBtn = MonsterInspectorWindow.buttons and MonsterInspectorWindow.buttons.clear
    local closeBtn = MonsterInspectorWindow.buttons and MonsterInspectorWindow.buttons.close

    if refreshBtn then refreshBtn.onClick = function() refreshPatterns() end end
    if exportBtn then exportBtn.onClick = function() exportPatterns() end end
    if clearBtn then clearBtn.onClick = function() clearPatterns() end end
    if closeBtn then closeBtn.onClick = function() MonsterInspectorWindow:hide() end end

    MonsterInspectorWindow.onVisibilityChange = function(widget, visible)
      if visible then
        updateWidgetRefs()
        refreshPatterns()
      end
    end
  end
  pcall(bindButtons)

  -- Initialize content
  pcall(function() updateWidgetRefs() end)
  pcall(function() refreshPatterns() end)

  return MonsterInspectorWindow
end

-- Ensure window exists at load time if possible
createWindowIfMissing()

-- Ensure global namespace for inspector exists to avoid nil indexing during early calls
nExBot = nExBot or {}
nExBot.MonsterInspector = nExBot.MonsterInspector or {}

local patternList, dmgLabel, waveLabel, areaLabel = nil, nil, nil, nil

-- Robust recursive lookup for widgets (tries direct property, getChildById, and recursive search)
local function findChildRecursive(parent, id)
  if not parent or not id then return nil end
  local ok, child = pcall(function() return parent[id] end)
  if ok and child then return child end
  ok, child = pcall(function() return parent:getChildById(id) end)
  if ok and child then return child end
  -- Depth-first search of children
  ok, child = pcall(function()
    local children = parent.getChildren and parent:getChildren() or {}
    for i = 1, #children do
      local found = findChildRecursive(children[i], id)
      if found then return found end
    end
    return nil
  end)
  if ok and child then return child end
  return nil
end

local function updateWidgetRefs()
  -- Robustly bind important widgets (content -> textContent) using recursive lookup
  if not MonsterInspectorWindow then
    patternList, dmgLabel, waveLabel, areaLabel = nil, nil, nil, nil
    -- MonsterInspectorWindow missing (silent)
    return
  end

  -- Try direct properties first (common when otui sets ids as fields)
  local content = nil
  local ok, cont = pcall(function() return MonsterInspectorWindow.content end)
  if ok and cont then content = cont end

  -- Fallback to recursive search
  if not content then content = findChildRecursive(MonsterInspectorWindow, 'content') end

  -- Find the textual content label
  local textContent = nil
  if content then
    local ok2, tc = pcall(function() return content.textContent end)
    if ok2 and tc then textContent = tc end
    if not textContent then textContent = findChildRecursive(content, 'textContent') end
  else
    -- As a last resort, search the entire window for the label
    textContent = findChildRecursive(MonsterInspectorWindow, 'textContent')
  end

  if textContent then
    patternList = textContent
    -- Ensure window references are set so other code can access them directly
    if content and (not MonsterInspectorWindow.content) then MonsterInspectorWindow.content = content end
    if MonsterInspectorWindow.content and (not MonsterInspectorWindow.content.textContent) then MonsterInspectorWindow.content.textContent = textContent end

  else
    patternList = nil
    warn("[MonsterInspector] Failed to bind textContent widget; UI may not be loaded or style import failed")
  end
end



-- Populate refs now (also called again on visibility change)
updateWidgetRefs()

local refreshTimerActive = false
local refreshInProgress = false
local lastPatternsChecksum = nil
local lastRefreshMs = 0
local MIN_REFRESH_MS = 2500 -- don't refresh more often than this (ms)
local lastLabelUpdateMs = 0
local MIN_LABEL_UPDATE_MS = 1000 -- don't update labels more often than this (ms)

-- Helper function to check if table is empty (since 'next' is not available)
local function isTableEmpty(tbl)
  if not tbl then return true end
  for _ in pairs(tbl) do
    return false
  end
  return true
end

local function fmtTime(ms)
  if not ms or (type(ms) == 'number' and ms <= 0) then return "-" end
  return os.date('%Y-%m-%d %H:%M:%S', math.floor(ms / 1000))
end

-- Build a compact human-friendly string for a single pattern
local function formatPatternLine(name, p)
  local cooldown = p and p.waveCooldown and string.format("%dms", math.floor(p.waveCooldown)) or "-"
  local variance = p and p.waveVariance and string.format("%.1f", p.waveVariance) or "-"
  local conf = p and p.confidence and string.format("%.2f", p.confidence) or "-"
  local last = p and p.lastSeen and fmtTime(p.lastSeen) or "-"
  return string.format("%s — cd:%s  var:%s  conf:%s  last:%s", name, cooldown, variance, conf, last)
end

-- Build a textual summary (smart_hunt style) for quick rendering in a scrollable content label
local function buildSummary()
  local lines = {}
  local stats = (MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.stats) or { waveAttacksObserved = 0, areaAttacksObserved = 0, totalDamageReceived = 0 }
  
  -- Header with version
  table.insert(lines, string.format("Monster AI v%s", MonsterAI and MonsterAI.VERSION or "?"))
  table.insert(lines, string.format("Stats: Damage=%s  Waves=%s  Area=%s", stats.totalDamageReceived or 0, stats.waveAttacksObserved or 0, stats.areaAttacksObserved or 0))
  
  -- Session stats (new in v2.0)
  if MonsterAI and MonsterAI.Telemetry and MonsterAI.Telemetry.session then
    local session = MonsterAI.Telemetry.session
    local sessionDuration = ((now or 0) - (session.startTime or 0)) / 1000
    table.insert(lines, string.format("Session: Kills=%d  Deaths=%d  Duration=%.0fs  Tracked=%d",
      session.killCount or 0,
      session.deathCount or 0,
      sessionDuration,
      session.totalMonstersTracked or 0
    ))
  end
  
  -- Real-time prediction stats
  if MonsterAI and MonsterAI.getPredictionStats then
    local predStats = MonsterAI.getPredictionStats()
    table.insert(lines, string.format("Predictions: Events=%d  Correct=%d  Missed=%d  Accuracy=%.1f%%",
      predStats.eventsProcessed or 0,
      predStats.predictionsCorrect or 0,
      predStats.predictionsMissed or 0,
      (predStats.accuracy or 0) * 100
    ))
    
    -- WavePredictor stats if available
    if predStats.wavePredictor then
      local wp = predStats.wavePredictor
      table.insert(lines, string.format("WavePredictor: Total=%d  Correct=%d  FalsePos=%d  Acc=%.1f%%",
        wp.total or 0,
        wp.correct or 0,
        wp.falsePositive or 0,
        (wp.accuracy or 0) * 100
      ))
    end
  end
  
  -- Real-time threat status
  if MonsterAI and MonsterAI.getImmediateThreat then
    local threat = MonsterAI.getImmediateThreat()
    local threatStatus = threat.immediateThreat and "DANGER!" or "Safe"
    table.insert(lines, string.format("Threat: %s  Level=%.1f  HighThreat=%d",
      threatStatus,
      threat.totalThreat or 0,
      threat.highThreatCount or 0
    ))
  end
  
  -- Auto-Tuner Status (new in v2.0)
  if MonsterAI and MonsterAI.AutoTuner then
    local autoTuneStatus = MonsterAI.AUTO_TUNE_ENABLED and "ON" or "OFF"
    local adjustments = MonsterAI.RealTime and MonsterAI.RealTime.metrics and MonsterAI.RealTime.metrics.autoTuneAdjustments or 0
    local pendingSuggestions = 0
    if MonsterAI.AutoTuner.suggestions then
      for _ in pairs(MonsterAI.AutoTuner.suggestions) do pendingSuggestions = pendingSuggestions + 1 end
    end
    table.insert(lines, string.format("AutoTuner: %s  Adjustments=%d  Pending=%d", 
      autoTuneStatus, adjustments, pendingSuggestions))
  end
  
  -- Classification Stats (new in v2.0)
  if MonsterAI and MonsterAI.Classifier and MonsterAI.Classifier.cache then
    local classifiedCount = 0
    for _ in pairs(MonsterAI.Classifier.cache) do classifiedCount = classifiedCount + 1 end
    table.insert(lines, string.format("Classifications: %d monster types analyzed", classifiedCount))
  end
  
  -- Telemetry Stats (new in v2.0)
  if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.metrics then
    local telemetrySamples = MonsterAI.RealTime.metrics.telemetrySamples or 0
    table.insert(lines, string.format("Telemetry: %d samples collected", telemetrySamples))
  end
  
  -- Combat Feedback Stats (NEW in v2.0 - 30% accuracy improvement)
  if MonsterAI and MonsterAI.CombatFeedback then
    local cf = MonsterAI.CombatFeedback
    if cf.getStats then
      local cfStats = cf.getStats()
      local accuracy = cfStats.accuracy or 0
      local predictions = cfStats.totalPredictions or 0
      local hits = cfStats.hits or 0
      local misses = cfStats.misses or 0
      local adaptiveWeights = cfStats.adaptiveWeightsCount or 0
      
      table.insert(lines, string.format("CombatFeedback: Predictions=%d  Hits=%d  Misses=%d  Acc=%.1f%%  Weights=%d",
        predictions, hits, misses, accuracy * 100, adaptiveWeights))
    end
  end
  
  -- Scenario Manager Stats (NEW in v2.1 - Anti-Zigzag)
  if MonsterAI and MonsterAI.Scenario then
    local scn = MonsterAI.Scenario
    local scnStats = scn.getStats and scn.getStats() or {}
    
    local scenarioType = scnStats.currentScenario or "unknown"
    local monsterCount = scnStats.monsterCount or 0
    local isZigzag = scnStats.isZigzagging and "YES!" or "No"
    local switches = scnStats.consecutiveSwitches or 0
    local clusterType = scnStats.clusterType or "none"
    
    -- Scenario type with description
    local scenarioDesc = ""
    if scnStats.config and scnStats.config.description then
      scenarioDesc = " (" .. scnStats.config.description .. ")"
    end
    
    table.insert(lines, string.format("Scenario: %s%s", scenarioType:upper(), scenarioDesc))
    table.insert(lines, string.format("  Monsters: %d  Cluster: %s  Zigzag: %s  Switches: %d",
      monsterCount, clusterType, isZigzag, switches))
    
    -- Target lock info
    if scnStats.targetLockId then
      local lockData = MonsterAI.Tracker and MonsterAI.Tracker.monsters[scnStats.targetLockId]
      local lockName = lockData and lockData.name or "Unknown"
      local lockHealth = lockData and lockData.creature and lockData.creature:getHealthPercent() or 0
      table.insert(lines, string.format("  Target Lock: %s (%d%% HP)", lockName, lockHealth))
    end
    
    -- Anti-zigzag status
    local cfg = scnStats.config or {}
    if cfg.switchCooldownMs then
      table.insert(lines, string.format("  Anti-Zigzag: Cooldown=%dms  Stickiness=%d  MaxSwitches/min=%s",
        cfg.switchCooldownMs,
        cfg.targetStickiness or 0,
        cfg.maxSwitchesPerMinute and tostring(cfg.maxSwitchesPerMinute) or "∞"))
    end
  end
  
  -- Reachability Stats (NEW in v2.1 - Prevents "Creature not reachable")
  if MonsterAI and MonsterAI.Reachability then
    local reach = MonsterAI.Reachability
    local reachStats = reach.getStats and reach.getStats() or {}
    
    local blockedCount = reachStats.blockedCount or 0
    local checksPerformed = reachStats.checksPerformed or 0
    local cacheHits = reachStats.cacheHits or 0
    local reachableCount = reachStats.reachable or 0
    local blockedTotal = reachStats.blocked or 0
    
    local hitRate = checksPerformed > 0 and (cacheHits / (checksPerformed + cacheHits)) * 100 or 0
    
    table.insert(lines, string.format("Reachability: Checks=%d  CacheHit=%.0f%%  Blocked=%d  Reachable=%d",
      checksPerformed, hitRate, blockedTotal, reachableCount))
    
    -- Show blocked reasons breakdown
    if reachStats.byReason then
      local reasons = reachStats.byReason
      if (reasons.no_path or 0) > 0 or (reasons.blocked_tile or 0) > 0 then
        table.insert(lines, string.format("  Blocked: NoPath=%d  Tile=%d  Elevation=%d  TooFar=%d",
          reasons.no_path or 0,
          reasons.blocked_tile or 0,
          reasons.elevation or 0,
          reasons.too_far or 0))
      end
    end
    
    -- Show currently blocked creatures
    if blockedCount > 0 then
      table.insert(lines, string.format("  Currently Blocked: %d creatures (cooldown active)", blockedCount))
    end
  end
  
  -- TargetBot Integration Stats (NEW in v2.0)
  if MonsterAI and MonsterAI.TargetBot then
    local tbi = MonsterAI.TargetBot
    local tbiStats = tbi.getStats and tbi.getStats() or {}
    
    local status = "Active"
    if tbiStats.feedbackActive and tbiStats.trackerActive and tbiStats.realTimeActive then
      status = "Full Integration"
    elseif tbiStats.trackerActive then
      status = "Partial Integration"
    end
    
    table.insert(lines, string.format("TargetBot Integration: %s", status))
    
    -- Show danger level
    if tbi.getDangerLevel then
      local dangerLevel, threats = tbi.getDangerLevel()
      local threatCount = #threats
      table.insert(lines, string.format("  Danger Level: %.1f/10  Active Threats: %d", dangerLevel, threatCount))
      
      -- List top 3 threats
      for i = 1, math.min(3, threatCount) do
        local t = threats[i]
        local imminentStr = t.imminent and " [IMMINENT]" or ""
        table.insert(lines, string.format("    %d. %s (level %.1f)%s", i, t.name, t.level, imminentStr))
      end
    end
  end
  
  table.insert(lines, "")
  
  -- Show Classifications section (new in v2.0)
  if MonsterAI and MonsterAI.Classifier and MonsterAI.Classifier.cache then
    local classCount = 0
    for _ in pairs(MonsterAI.Classifier.cache) do classCount = classCount + 1 end
    
    if classCount > 0 then
      table.insert(lines, "Classifications:")
      table.insert(lines, string.format("  %-18s %6s %6s %8s %6s %6s", "name", "danger", "conf", "type", "dist", "cd"))
      
      -- Sort by confidence
      local classItems = {}
      for name, c in pairs(MonsterAI.Classifier.cache) do
        table.insert(classItems, {name = name, class = c})
      end
      table.sort(classItems, function(a, b) return (a.class.confidence or 0) > (b.class.confidence or 0) end)
      
      for i = 1, math.min(#classItems, 10) do
        local item = classItems[i]
        local c = item.class
        local typeStr = ""
        if c.isRanged then typeStr = "Ranged"
        elseif c.isMelee then typeStr = "Melee" end
        if c.isWaveAttacker then typeStr = typeStr .. "+Wave" end
        if c.isFast then typeStr = typeStr .. "+Fast" end
        
        table.insert(lines, string.format("  %-18s %6d %6.2f %8s %6d %6s",
          item.name:sub(1, 18),
          c.estimatedDanger or 0,
          c.confidence or 0,
          typeStr:sub(1, 8),
          c.preferredDistance or 0,
          c.attackCooldown and string.format("%dms", math.floor(c.attackCooldown)) or "-"
        ))
      end
      table.insert(lines, "")
    end
  end
  
  -- Show Pending Suggestions (new in v2.0)
  if MonsterAI and MonsterAI.AutoTuner and MonsterAI.AutoTuner.suggestions then
    local hasSignificantSuggestions = false
    for name, s in pairs(MonsterAI.AutoTuner.suggestions) do
      if math.abs((s.suggestedDanger or 0) - (s.currentDanger or 0)) >= 1 then
        hasSignificantSuggestions = true
        break
      end
    end
    
    if hasSignificantSuggestions then
      table.insert(lines, "Danger Suggestions:")
      for name, s in pairs(MonsterAI.AutoTuner.suggestions) do
        local change = (s.suggestedDanger or 0) - (s.currentDanger or 0)
        if math.abs(change) >= 1 then
          local changeStr = change > 0 and "+" .. tostring(change) or tostring(change)
          table.insert(lines, string.format("  %s: %d -> %d (%s) [%.0f%% conf]",
            name,
            s.currentDanger or 0,
            s.suggestedDanger or 0,
            changeStr,
            (s.confidence or 0) * 100
          ))
          if s.reasons and #s.reasons > 0 then
            table.insert(lines, "    Reasons: " .. table.concat(s.reasons, ", "))
          end
        end
      end
      table.insert(lines, "")
    end
  end
  
  table.insert(lines, "Patterns:")
  local patterns = storage.monsterPatterns or {}

  if isTableEmpty(patterns) then
    -- If no persisted patterns, try to show live tracking info (useful while hunting)
    local live = (MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.monsters) or {}
    local liveCount = 0
    for _ in pairs(live) do liveCount = liveCount + 1 end

    if liveCount == 0 then
      table.insert(lines, "  None")
    else
      table.insert(lines, string.format("  (Live tracking: %d monsters)", liveCount))
      -- Header (columns) - added facing column
      table.insert(lines, string.format("  %-18s %6s %5s %6s %6s %7s %6s %6s", "name","samps","conf","cd","dps","missiles","spd","facing"))

      -- show up to 20 tracked monsters sorted by confidence (descending)
      local tbl = {}
      for id, d in pairs(live) do
        local name = d.name or "unknown"
        local samples = d.samples and #d.samples or 0
        local conf = d.confidence or 0
        local cooldown = d.ewmaCooldown or d.predictedWaveCooldown or "-"
        -- Check if facing player from RealTime data
        local facing = false
        if MonsterAI and MonsterAI.RealTime and MonsterAI.RealTime.directions[id] then
          local rt = MonsterAI.RealTime.directions[id]
          facing = rt.facingPlayerSince ~= nil
        end
        table.insert(tbl, { id = id, name = name, samples = samples, conf = conf, cooldown = cooldown, facing = facing })
      end
      table.sort(tbl, function(a, b) return (a.conf or 0) > (b.conf or 0) end)
      for i = 1, math.min(#tbl, 20) do
        local e = tbl[i]
        local confs = e.conf and string.format("%.2f", e.conf) or "-"
        local cd = (type(e.cooldown) == 'number' and string.format("%dms", math.floor(e.cooldown))) or tostring(e.cooldown)
        local d = MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.monsters and MonsterAI.Tracker.monsters[e.id] or {}
        local dps = MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.getDPS and MonsterAI.Tracker.getDPS(e.id) or 0
        local missiles = d.missileCount or 0
        local spd = d.avgSpeed or 0
        local facingStr = e.facing and "YES" or "no"
        table.insert(lines, string.format("  %-18s %6d %5s %6s %6.2f %7d %6.2f %6s", e.name, e.samples, confs, cd, (dps or 0), missiles, spd, facingStr))
      end
      table.insert(lines, "  (Note: live tracker data and patterns persist after observed attacks)")
    end
  else
    for name, p in pairs(patterns) do
      local cooldown = p and p.waveCooldown and string.format("%dms", math.floor(p.waveCooldown)) or "-"
      local variance = p and p.waveVariance and string.format("%.1f", p.waveVariance) or "-"
      local conf = p and p.confidence and string.format("%.2f", p.confidence) or "-"
      local last = p and p.lastSeen and fmtTime(p.lastSeen) or "-"
      table.insert(lines, string.format("  %s  cd:%s  var:%s  conf:%s  last:%s", name, cooldown, variance, conf, last))
    end
  end
  return table.concat(lines, "\n")
end

function refreshPatterns()
  if not MonsterInspectorWindow or not MonsterInspectorWindow:isVisible() then return end

  -- Ensure we have the latest widget refs; try again if not bound
  if not MonsterInspectorWindow.content or not MonsterInspectorWindow.content.textContent then
    updateWidgetRefs()
  end

  if not MonsterInspectorWindow.content or not MonsterInspectorWindow.content.textContent then
    warn("[MonsterInspector] refreshPatterns: textContent widget missing after updateWidgetRefs; aborting refresh.")
    -- Diagnostic dump to help root-cause: storage and tracker stats
    local count = 0
    local patterns = (UnifiedStorage and UnifiedStorage.get("targetbot.monsterPatterns")) or (storage and storage.monsterPatterns) or {}
    for _ in pairs(patterns) do count = count + 1 end
    print(string.format("[MonsterInspector][DIAG] monsterPatterns count=%d", count))
    if MonsterAI and MonsterAI.Tracker and MonsterAI.Tracker.stats then
      local s = MonsterAI.Tracker.stats
      print(string.format("[MonsterInspector][DIAG] MonsterAI stats: damage=%d waves=%d area=%d", s.totalDamageReceived or 0, s.waveAttacksObserved or 0, s.areaAttacksObserved or 0))
    end
    return
  end

  if refreshInProgress then return end

  -- Throttle frequent calls
  if now and (now - lastRefreshMs) < MIN_REFRESH_MS then
    return
  end

  refreshInProgress = true
  lastRefreshMs = now

  -- Set the content text (simplified like Hunt Analyzer)
  MonsterInspectorWindow.content.textContent:setText(buildSummary())

  refreshInProgress = false
end

-- Export all patterns to clipboard as CSV-like text
local function exportPatterns()
  local lines = {}
  table.insert(lines, "name,cooldown_ms,variance,confidence,last_seen")
  local patterns = (UnifiedStorage and UnifiedStorage.get("targetbot.monsterPatterns")) or storage.monsterPatterns or {}
  for name, p in pairs(patterns) do
    local cd = p.waveCooldown and tostring(math.floor(p.waveCooldown)) or ""
    local var = p.waveVariance and tostring(p.waveVariance) or ""
    local conf = p.confidence and tostring(p.confidence) or ""
    local last = p.lastSeen and tostring(math.floor(p.lastSeen / 1000)) or ""
    table.insert(lines, string.format('%s,%s,%s,%s,%s', name, cd, var, conf, last))
  end
  local out = table.concat(lines, "\n")
  if g_window and g_window.setClipboardText then
    g_window.setClipboardText(out)
    print("[MonsterInspector] Patterns exported to clipboard")
  end
end

-- Clear persisted patterns and in-memory knownMonsters
local function clearPatterns()
  if UnifiedStorage then
    UnifiedStorage.set("targetbot.monsterPatterns", {})
  end
  storage.monsterPatterns = {}
  MonsterAI.Patterns.knownMonsters = {}
  refreshPatterns()
  print("[MonsterInspector] Cleared stored monster patterns")
end

-- Buttons - use proper widget lookup via getChildById
local function bindInspectorButtons()
  if not MonsterInspectorWindow then return end
  
  -- Find buttons panel first
  local buttonsPanel = nil
  pcall(function() buttonsPanel = MonsterInspectorWindow:getChildById("buttons") end)
  if not buttonsPanel then
    pcall(function() buttonsPanel = MonsterInspectorWindow.buttons end)
  end
  
  if not buttonsPanel then
    warn("[MonsterInspector] Could not find buttons panel")
    return
  end
  
  -- Find individual buttons
  local refreshBtn, clearBtn, closeBtn = nil, nil, nil
  pcall(function() refreshBtn = buttonsPanel:getChildById("refresh") end)
  pcall(function() clearBtn = buttonsPanel:getChildById("clear") end)
  pcall(function() closeBtn = buttonsPanel:getChildById("close") end)
  
  if refreshBtn then
    refreshBtn.onClick = function() refreshPatterns() end
  end
  if clearBtn then
    clearBtn.onClick = function()
      clearPatterns()
    end
  end
  if closeBtn then
    closeBtn.onClick = function() MonsterInspectorWindow:hide() end
  end

  -- Auto-refresh while visible (guarded to avoid duplicate schedule chains)
  MonsterInspectorWindow.onVisibilityChange = function(widget, visible)
    if visible then
      -- re-resolve widgets in case UI was reloaded or nested
      updateWidgetRefs()
      refreshPatterns()
    end
  end
end

-- Bind buttons on load
bindInspectorButtons()

-- Initialize (load current data)
refreshPatterns()

nExBot.MonsterInspector = {
  refresh = refreshPatterns,
  clear = clearPatterns,
  rebindButtons = bindInspectorButtons
}

-- Convenience helpers to show/toggle the inspector from console or other modules
nExBot.MonsterInspector.showWindow = function()
  if not MonsterInspectorWindow then
    createWindowIfMissing()
  end
  if MonsterInspectorWindow then
    MonsterInspectorWindow:show()
    updateWidgetRefs()

    -- Ensure tracker runs to populate initial samples (no console required)
    if MonsterAI and MonsterAI.updateAll then pcall(function() MonsterAI.updateAll() end) end
    refreshPatterns()

    -- If storage is empty, retry after a short delay to let updater collect samples
    local patterns = (UnifiedStorage and UnifiedStorage.get("targetbot.monsterPatterns")) or (storage and storage.monsterPatterns)
    local hasPatterns = patterns and next(patterns) ~= nil
    if not hasPatterns then
      schedule(500, function()
        if MonsterAI and MonsterAI.updateAll then pcall(function() MonsterAI.updateAll() end) end
        refreshPatterns()
      end)
    end
  end
end

nExBot.MonsterInspector.toggleWindow = function()
  if not MonsterInspectorWindow then
    createWindowIfMissing()
  end
  if MonsterInspectorWindow then
    if MonsterInspectorWindow:isVisible() then
      MonsterInspectorWindow:hide()
    else
      MonsterInspectorWindow:show()
      updateWidgetRefs()
      if MonsterAI and MonsterAI.updateAll then pcall(function() MonsterAI.updateAll() end) end
      refreshPatterns()
      -- Retry shortly if no patterns yet
      local patterns2 = (UnifiedStorage and UnifiedStorage.get("targetbot.monsterPatterns")) or (storage and storage.monsterPatterns)
      if not (patterns2 and next(patterns2) ~= nil) then
        schedule(500, function() if MonsterAI and MonsterAI.updateAll then pcall(function() MonsterAI.updateAll() end) end; refreshPatterns() end)
      end
    end
  end
end

-- Expose refreshPatterns function
nExBot.MonsterInspector.refreshPatterns = refreshPatterns


