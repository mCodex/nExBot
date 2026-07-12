local M = {}

local analytics = {
  spellCasts = 0,
  potionUses = 0,
  potionWaste = 0,
  manaWaste = 0,
  spells = {},
  potions = {},
  log = {}
}

function M.getAnalytics()
  return analytics
end

function M.resetAnalytics()
  analytics.spellCasts = 0
  analytics.potionUses = 0
  analytics.potionWaste = 0
  analytics.manaWaste = 0
  analytics.spells = {}
  analytics.potions = {}
  analytics.log = {}
end

HealAnalytics = M
return M
