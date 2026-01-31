--[[
  BotCore: Unified Analytics System
  
  Single analytics system for all bots (HealBot, AttackBot, etc.)
  Tracks spells, potions, runes with categorization.
  
  Principles: DRY, SRP
]]

local Analytics = {}

-- Safe function calls to prevent "attempt to call global function (a nil value)" errors
local SafeCall = SafeCall or require("core.safe_call")

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

-- Unified analytics structure
local _data = storage.botCoreAnalytics or {
  -- Session info
  session = {
    startTime = 0,
    startXp = 0,
    isActive = false
  },
  
  -- Healing analytics
  healing = {
    spells = {},      -- { ["spellName"] = count }
    potions = {},     -- { ["itemId"] = count } - string keys to avoid sparse arrays
    totalSpells = 0,
    totalPotions = 0,
    manaWaste = 0,    -- Mana wasted on unnecessary heals
    potionWaste = 0   -- Potions used when already healthy
  },
  
  -- Attack analytics
  attacks = {
    spells = {},      -- { ["spellName"] = count }
    runes = {},       -- { ["runeId"] = count } - string keys to avoid sparse arrays
    totalSpells = 0,
    totalRunes = 0,
    empowerments = 0
  },
  
  -- Support analytics
  support = {
    spells = {},      -- { ["spellName"] = count }
    totalSpells = 0
  },
  
  -- Unified action log (last N actions)
  log = {},
  logMaxSize = 100
}

-- Fix any existing numeric keys that may have been saved as sparse arrays
-- Convert them to string keys for proper JSON serialization
local function fixSparseTable(tbl)
  if not tbl or type(tbl) ~= "table" then return {} end
  local fixed = {}
  for k, v in pairs(tbl) do
    fixed[tostring(k)] = v
  end
  return fixed
end

-- Apply fixes to loaded data
if _data.healing then
  _data.healing.potions = fixSparseTable(_data.healing.potions)
  _data.healing.spells = fixSparseTable(_data.healing.spells)
end
if _data.attacks then
  _data.attacks.runes = fixSparseTable(_data.attacks.runes)
  _data.attacks.spells = fixSparseTable(_data.attacks.spells)
end
if _data.support then
  _data.support.spells = fixSparseTable(_data.support.spells)
end

-- Persist to storage
storage.botCoreAnalytics = _data

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

-- Append to log with rotation (using TrimArray for O(1) amortized)
local function appendLog(entry)
  local log = _data.log
  entry.timestamp = now or os.time() * 1000
  log[#log + 1] = entry
  TrimArray(log, _data.logMaxSize)
end

-- Increment counter in table
-- Always use string keys to prevent sparse array issues in JSON serialization
local function incrementCounter(tbl, key)
  local strKey = tostring(key)
  tbl[strKey] = (tbl[strKey] or 0) + 1
end

-- ============================================================================
-- PUBLIC API: Session Management
-- ============================================================================

function Analytics.startSession()
  _data.session.startTime = now or os.time() * 1000
  _data.session.startXp = SafeCall.exp() or 0
  _data.session.isActive = true
end

function Analytics.stopSession()
  _data.session.isActive = false
end

function Analytics.isSessionActive()
  return _data.session.isActive
end

function Analytics.getSessionDuration()
  if not _data.session.isActive then return 0 end
  local currentTime = now or os.time() * 1000
  return currentTime - _data.session.startTime
end

-- ============================================================================
-- PUBLIC API: Healing Analytics
-- ============================================================================

-- Record a healing spell cast
function Analytics.recordHealSpell(spellName, manaCost, hpBefore, hpAfter)
  incrementCounter(_data.healing.spells, spellName)
  _data.healing.totalSpells = _data.healing.totalSpells + 1
  
  -- Track waste if healed when already above threshold + 10%
  local wasted = hpBefore and hpAfter and (hpAfter - hpBefore < 5)
  if wasted and manaCost then
    _data.healing.manaWaste = _data.healing.manaWaste + manaCost
  end
  
  appendLog({
    type = "heal_spell",
    name = spellName,
    cost = manaCost,
    hpBefore = hpBefore,
    wasted = wasted
  })
end

-- Record a potion use
function Analytics.recordPotion(itemId, hpBefore, hpAfter)
  incrementCounter(_data.healing.potions, itemId)
  _data.healing.totalPotions = _data.healing.totalPotions + 1
  
  -- Track waste if used when already above 90% HP
  local wasted = hpBefore and hpBefore > 90
  if wasted then
    _data.healing.potionWaste = _data.healing.potionWaste + 1
  end
  
  appendLog({
    type = "potion",
    itemId = itemId,
    hpBefore = hpBefore,
    wasted = wasted
  })
end

-- ============================================================================
-- PUBLIC API: Attack Analytics
-- ============================================================================

-- Record an attack spell cast
function Analytics.recordAttackSpell(spellName, category)
  incrementCounter(_data.attacks.spells, spellName)
  _data.attacks.totalSpells = _data.attacks.totalSpells + 1
  
  -- Category 4 = empowerment
  if category == 4 then
    _data.attacks.empowerments = _data.attacks.empowerments + 1
  end
  
  appendLog({
    type = "attack_spell",
    name = spellName,
    category = category
  })
end

-- Record a rune use
function Analytics.recordRune(runeId, category)
  incrementCounter(_data.attacks.runes, runeId)
  _data.attacks.totalRunes = _data.attacks.totalRunes + 1
  
  appendLog({
    type = "rune",
    runeId = runeId,
    category = category
  })
end

-- Record any attack action (unified entry point)
-- category: 1=targeted spell, 2=area rune, 3=targeted rune, 4=empowerment, 5=absolute spell
function Analytics.recordAttack(category, idOrFormula)
  if category == 2 or category == 3 then
    -- Rune
    local runeId = tonumber(idOrFormula) or 0
    Analytics.recordRune(runeId, category)
  else
    -- Spell
    local spellName = tostring(idOrFormula)
    Analytics.recordAttackSpell(spellName, category)
  end
end

-- ============================================================================
-- PUBLIC API: Support Analytics
-- ============================================================================

function Analytics.recordSupportSpell(spellName)
  incrementCounter(_data.support.spells, spellName)
  _data.support.totalSpells = _data.support.totalSpells + 1
  
  appendLog({
    type = "support_spell",
    name = spellName
  })
end

-- ============================================================================
-- PUBLIC API: Data Getters
-- ============================================================================

function Analytics.getHealingData()
  return _data.healing
end

function Analytics.getAttackData()
  return _data.attacks
end

function Analytics.getSupportData()
  return _data.support
end

function Analytics.getLog()
  return _data.log
end

function Analytics.getAll()
  return _data
end

-- ============================================================================
-- PUBLIC API: Reset
-- ============================================================================

function Analytics.resetHealing()
  _data.healing = {
    spells = {}, potions = {},
    totalSpells = 0, totalPotions = 0,
    manaWaste = 0, potionWaste = 0
  }
end

function Analytics.resetAttacks()
  _data.attacks = {
    spells = {}, runes = {},
    totalSpells = 0, totalRunes = 0,
    empowerments = 0
  }
end

function Analytics.resetAll()
  Analytics.resetHealing()
  Analytics.resetAttacks()
  _data.support = { spells = {}, totalSpells = 0 }
  _data.log = {}
  _data.session = { startTime = 0, startXp = 0, isActive = false }
end

-- ============================================================================
-- COMPATIBILITY: Legacy API for existing bots
-- ============================================================================

-- HealBot compatibility
Analytics.HealBot = {
  getAnalytics = function()
    return {
      spellCasts = _data.healing.totalSpells,
      potionUses = _data.healing.totalPotions,
      potionWaste = _data.healing.potionWaste,
      manaWaste = _data.healing.manaWaste,
      spells = _data.healing.spells,
      potions = _data.healing.potions,
      log = _data.log
    }
  end,
  resetAnalytics = function()
    Analytics.resetHealing()
  end
}

-- AttackBot compatibility
Analytics.AttackBot = {
  getAnalytics = function()
    return {
      spells = _data.attacks.spells,
      runes = _data.attacks.runes,
      empowerments = _data.attacks.empowerments,
      totalAttacks = _data.attacks.totalSpells + _data.attacks.totalRunes,
      log = _data.log
    }
  end,
  resetAnalytics = function()
    Analytics.resetAttacks()
  end
}

-- Export for global access
BotCore = BotCore or {}
BotCore.Analytics = Analytics

return Analytics
