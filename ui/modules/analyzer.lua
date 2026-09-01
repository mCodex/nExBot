--[[
  Analyzer module page — session hunting statistics (XP, loot, supplies,
  impact, party, drop/boss trackers). Reads everything through the Analyzer
  namespace accessors; nil-safe so the page renders even with partial data.
]]

local Components = nExBot.UI["ui.components.components"]
local DataTable = nExBot.UI.DataTable
local Resolver = nExBot.UI.VisualAssetResolver

local AnalyzerPage = {}

local function fmt(v)
  v = tonumber(v) or 0
  local s = string.format("%d", math.floor(v))
  local pos = #s % 3
  if pos == 0 then pos = 3 end
  return s:sub(1, pos) .. s:sub(pos + 1):gsub("(%d%d%d)", ",%1")
end

local function fmtTime(v)
  v = tonumber(v) or 0
  local hours = math.floor(v / 3600)
  local mins = math.floor((v - hours * 3600) / 60)
  return string.format("%02dh %02dm", hours, mins)
end

local function itemName(id)
  if not Resolver or not Resolver.item then return "Item " .. tostring(id or "?") end
  local r = Resolver:item(id)
  return r and r.name or ("Item " .. tostring(id or "?"))
end

local function killCount(hunt)
  local kills = 0
  for _, k in ipairs(hunt.kills or {}) do
    kills = kills + (k.count or 0)
  end
  return kills
end

local function lootRows(loot)
  local rows = {}
  for _, item in ipairs(loot.items or {}) do
    rows[#rows + 1] = {
      id = "loot_" .. tostring(item.id),
      itemId = item.id,
      title = item.name or itemName(item.id),
      secondary = tostring(item.count or 0) .. "x",
    }
  end
  return rows
end

local function impactRows(impact)
  local rows = {}
  for i, d in ipairs(impact.distribution or {}) do
    if d.name and d.name ~= "-" then
      rows[#rows + 1] = {
        id = "impact_" .. i,
        title = d.name,
        secondary = tostring(d.value or "0"),
      }
    end
  end
  return rows
end

local function dropRows(drops)
  local rows = {}
  for _, item in ipairs(drops or {}) do
    rows[#rows + 1] = {
      id = "drop_" .. tostring(item.id),
      itemId = item.id,
      title = itemName(item.id),
      secondary = tostring(item.count or 0) .. " drops",
    }
  end
  return rows
end

local function bossRows(bosses)
  local rows = {}
  for _, boss in ipairs(bosses or {}) do
    local status, statusText
    if (boss.timeLeft or 0) > 0 then
      status, statusText = "ACTIVE", fmtTime(boss.timeLeft) .. " remaining"
    else
      status, statusText = "OK", "No cooldown"
    end
    rows[#rows + 1] = {
      id = "boss_" .. tostring(boss.name),
      title = boss.name,
      secondary = "Due " .. os.date("%Y-%m-%d %H:%M", boss.dueTime or 0),
      status = status,
      statusText = statusText,
    }
  end
  return rows
end

function AnalyzerPage.render(shell, content)
  local Analyzer = _G.Analyzer
  if not Analyzer or not Analyzer.getHuntStats then
    Components.errorState(content, { message = "Analyzer did not load. Check the startup log." })
    return
  end

  local hunt = Analyzer.getHuntStats() or {}
  local loot = Analyzer.getLootStats() or {}
  local supply = Analyzer.getSupplyStats() or {}
  local impact = Analyzer.getImpactStats() or {}
  local xp = Analyzer.getXpStats() or {}
  local cave = Analyzer.getCaveBotStats() or {}
  local party = Analyzer.getPartyStats() or {}
  local drops = Analyzer.getDropTracker() or {}
  local bosses = Analyzer.getBossTracker() or {}

  Components.pageHeader(content, {
    id = "analyzerHeader", textId = "analyzerHeaderText",
    title = "Analyzer", subtitle = "Session hunting statistics.",
  })

  for _, m in ipairs({
    { id = "metricKills", label = "Kills", value = fmt(killCount(hunt)) },
    { id = "metricLoot", label = "Loot", value = fmt(hunt.loot) },
    { id = "metricSupplies", label = "Supplies", value = fmt(hunt.supplies) },
    { id = "metricXpHour", label = "XP/h", value = tostring(xp.xpHour or hunt.xpHour or "-") },
    { id = "metricDamage", label = "Damage", value = fmt(hunt.damage) },
  }) do
    Components.metricCard(content, { id = m.id, label = m.label, value = m.value })
  end

  Components.sectionHeader(content, { title = "Hunt loot" })
  DataTable.create(content, {
    id = "analyzerLoot", title = "Looted items",
    rows = lootRows(loot), rowKey = function(r) return r.id end,
    emptyMessage = "No loot recorded this session.",
  })

  Components.sectionHeader(content, { title = "Supplies by round" })
  Components.keyValueRow(content, { id = "kvSuppliesTotal", key = "Total supplies", value = fmt(supply.supplies) })
  Components.keyValueRow(content, { id = "kvRounds", key = "Rounds", value = tostring(cave.totalRounds or 0) })
  Components.keyValueRow(content, { id = "kvAvgRound", key = "Avg round time", value = tostring(cave.avRoundTime or "-") })
  Components.keyValueRow(content, { id = "kvRefills", key = "Refills", value = tostring(cave.totalRefills or 0) })
  Components.keyValueRow(content, { id = "kvAvgRefill", key = "Avg refill time", value = tostring(cave.avRefillTime or "-") })
  Components.keyValueRow(content, { id = "kvLastRefill", key = "Time since refill", value = tostring(cave.lastRefill or "-") })

  Components.sectionHeader(content, { title = "Impact by creature" })
  DataTable.create(content, {
    id = "analyzerImpact", title = "Damage distribution",
    rows = impactRows(impact), rowKey = function(r) return r.id end,
    emptyMessage = "No damage recorded this session.",
  })

  Components.sectionHeader(content, { title = "XP per hour" })
  Components.keyValueRow(content, { id = "kvXpGained", key = "XP gained", value = fmt(xp.xpGained) })
  Components.keyValueRow(content, { id = "kvXpHour", key = "XP/h", value = tostring(xp.xpHour or "-") })
  Components.keyValueRow(content, { id = "kvNextLevel", key = "Next level", value = tostring(xp.nextLevel or "-") })

  Components.sectionHeader(content, { title = "Party" })
  Components.keyValueRow(content, { id = "kvPartySession", key = "Session", value = tostring(party.sessionTime or "-") })
  Components.keyValueRow(content, { id = "kvPartyLoot", key = "Loot", value = fmt(party.loot) })
  Components.keyValueRow(content, { id = "kvPartySupplies", key = "Supplies", value = fmt(party.supplies) })
  Components.keyValueRow(content, { id = "kvPartyBalance", key = "Balance", value = fmt(party.balance) })
  Components.toggleRow(content, {
    id = "analyzerSendParty", label = "Send analyzer data to party",
    value = party.sendData == true,
    onChange = function(enabled)
      if Analyzer.setSendPartyData then Analyzer.setSendPartyData(enabled) end
    end,
  })

  Components.sectionHeader(content, { title = "Drop tracker" })
  DataTable.create(content, {
    id = "analyzerDrops", title = "Tracked drops",
    rows = dropRows(drops), rowKey = function(r) return r.id end,
    emptyMessage = "No items tracked.",
  })

  Components.sectionHeader(content, { title = "Boss tracker" })
  DataTable.create(content, {
    id = "analyzerBosses", title = "Boss cooldowns",
    rows = bossRows(bosses), rowKey = function(r) return r.id end,
    emptyMessage = "No boss cooldowns tracked.",
  })
end

nExBot.UI.ModuleRegistry.register({
  id = "analytics", label = "Analyzer", order = 75,
  group = "analytics", route = "analytics", breadcrumb = "Analytics / Analyzer",
  render = AnalyzerPage.render,
})
nExBot.UI.AnalyzerPage = AnalyzerPage
nExBot.UI["ui.modules.analyzer"] = AnalyzerPage

return AnalyzerPage