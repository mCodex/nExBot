-- ============================================================================
-- SIMPLIFIED ATTACKBOT - HIGH PERFORMANCE & ACCURACY
-- ============================================================================

local HealContext = dofile("/core/heal_context.lua")
local SafeCall = SafeCall or require("core.safe_call")

setDefaultTab("Main")
local panelName = "AttackBot"
local currentSettings
local showSettings = false
local showItem = false
local category = 1
local patternCategory = 1
local pattern = 1
local mainWindow

-- ============================================================================
-- BOTCORE INTEGRATION
-- ============================================================================

local attackAnalytics = storage.attackAnalytics or {
  spells = {},
  runes = {},
  empowerments = 0,
  totalAttacks = 0,
  log = {}
}
storage.attackAnalytics = attackAnalytics

local function recordAttackAction(cat, idOrFormula)
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.recordAttack(cat, idOrFormula)
    return
  end
  
  attackAnalytics.totalAttacks = attackAnalytics.totalAttacks + 1
  
  if cat == 1 or cat == 4 or cat == 5 then
    local spellName = tostring(idOrFormula)
    attackAnalytics.spells[spellName] = (attackAnalytics.spells[spellName] or 0) + 1
    if cat == 4 then
      attackAnalytics.empowerments = attackAnalytics.empowerments + 1
    end
  elseif cat == 2 or cat == 3 then
    local runeKey = tostring(tonumber(idOrFormula) or 0)
    attackAnalytics.runes[runeKey] = (attackAnalytics.runes[runeKey] or 0) + 1
  end
  
  local log = attackAnalytics.log
  if #log >= 50 then table.remove(log, 1) end
  table.insert(log, { t = now, cat = cat, action = tostring(idOrFormula) })
end

AttackBot = AttackBot or {}
AttackBot.getAnalytics = function()
  if BotCore and BotCore.Analytics then
    return BotCore.Analytics.AttackBot.getAnalytics()
  end
  return attackAnalytics
end
AttackBot.resetAnalytics = function()
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.AttackBot.resetAnalytics()
    return
  end
  attackAnalytics.spells = {}
  attackAnalytics.runes = {}
  attackAnalytics.empowerments = 0
  attackAnalytics.totalAttacks = 0
  attackAnalytics.log = {}
end

-- ============================================================================
-- PURE FUNCTIONS FOR HIGH ACCURACY
-- ============================================================================

-- Pure function: Check if attack entry should execute
local function shouldExecuteEntry(entry, context)
  if not entry.enabled then return false end
  
  -- Mana check
  if context.mana < entry.mana then return false end
  
  -- Cooldown check
  if not ready(entry.key or tostring(entry.itemId or entry.spell), entry.cooldown or 1000) then return false end
  
  -- Target checks
  if not context.target then return false end
  local targetHp = context.target:getHealthPercent()
  local targetDist = distanceFromPlayer(context.target:getPosition())
  
  -- HP condition
  if entry.orMore then
    if targetHp > entry.count then return false end
  else
    if targetHp ~= entry.count then return false end
  end
  
  -- Distance check for targeted attacks
  if entry.category == 1 or entry.category == 3 then
    if targetDist > entry.pattern then return false end
  end
  
  -- Safety checks
  if context.settings.BlackListSafe and isBlackListedPlayerInRange(context.settings.AntiRsRange) then return false end
  if context.settings.Kills and killsToRs() <= context.settings.KillsAmount then return false end
  
  -- PVP mode check for area runes
  if context.settings.pvpMode and entry.category == 2 and targetHp >= entry.minHp and targetHp <= entry.maxHp and context.target:canShoot() then
    return false
  end
  
  return true
end

-- Pure function: Execute attack action
local function executeAttack(entry, context)
  recordAttackAction(entry.category, entry.itemId > 100 and entry.itemId or entry.spell)
  
  if entry.category == 1 or entry.category == 4 or entry.category == 5 then
    -- Spells
    cast(entry.spell, entry.cooldown)
  elseif entry.category == 3 then
    -- Targeted runes
    useWith(entry.itemId, context.target)
  elseif entry.category == 2 then
    -- Area runes - find best position
    local data = getBestTileByPattern(spellPatterns[entry.patternCategory][entry.pattern][context.settings.PvpSafe and 2 or 1], 
                                      entry.minHp, entry.maxHp, context.settings.PvpSafe, entry.monsters)
    if data and data.pos then
      useWith(entry.itemId, g_map.getTile(data.pos):getTopUseThing())
    end
  end
end

-- ============================================================================
-- MAIN SIMPLIFIED ATTACK FUNCTION
-- ============================================================================

function attackBotMain()
  -- Safety checks
  if not currentSettings or not currentSettings.enabled then return end
  if not panel or not panel.entryList then return end
  if not target() then return end
  if SafeCall.isInPz() then return end
  
  -- Cooldown gating
  if BotCore and BotCore.Cooldown and BotCore.Cooldown.isAttackOnCooldown() then return end
  if modules.game_cooldown.isGroupCooldownIconActive(1) then return end
  
  -- Healing priority checks disabled per user request (do not block attacks on critical/danger)
  -- if HealContext and HealContext.isCritical and HealContext.isCritical() then return end
  -- if HealContext and HealContext.isDanger and HealContext.isDanger() then return end
  if BotCore and BotCore.Priority and not BotCore.Priority.canAttack() then return end
  
  -- Training dummy check
  if currentSettings.Training and target():getName():lower():find("training") then return end
  
  -- Build context
  local context = {
    target = target(),
    mana = manapercent(),
    settings = currentSettings
  }
  
  -- Get entries
  local entries = panel.entryList:getChildren()
  
  -- Execute first valid entry (priority order)
  for _, child in ipairs(entries) do
    local entry = child.params
    if entry and shouldExecuteEntry(entry, context) then
      executeAttack(entry, context)
      return
    end
  end
end

local attackMacro = macro(100, function()
  attackBotMain()
end)

-- ============================================================================
-- UI AND CONFIGURATION (KEEP EXISTING)
-- ============================================================================

-- [Keep all the UI setup, configuration loading, and helper functions below]
-- (The UI code remains the same for compatibility)