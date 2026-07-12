local M = {}

local analytics = {
  spells = {},
  runes = {},
  empowerments = 0,
  totalAttacks = 0,
  log = {}
}

function M.recordSpellUse(name)
  analytics.totalAttacks = analytics.totalAttacks + 1
  local key = tostring(name)
  analytics.spells[key] = (analytics.spells[key] or 0) + 1
end

function M.recordRuneUse(runeId)
  analytics.totalAttacks = analytics.totalAttacks + 1
  local key = tostring(tonumber(runeId) or 0)
  analytics.runes[key] = (analytics.runes[key] or 0) + 1
end

function M.recordBuffUse()
  analytics.empowerments = analytics.empowerments + 1
end

function M.getAnalytics()
  return analytics
end

function M.resetAnalytics()
  analytics.spells = {}
  analytics.runes = {}
  analytics.empowerments = 0
  analytics.totalAttacks = 0
  analytics.log = {}
end

AttackAnalytics = M
return M
