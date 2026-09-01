local HealContext = dofile("/core/heal_context.lua")

-- Safe function calls to prevent "attempt to call global function (a nil value)" errors
-- SafeCall is loaded globally in Phase 4 by _Loader.lua; pcall-guarded fallback for safety.
local SafeCall = SafeCall
if not SafeCall then
  local ok, mod = pcall(dofile, "/core/safe_call.lua")
  SafeCall = ok and mod or {}
end

local getClient = nExBot.Shared.getClient
local getClientVersion = nExBot.Shared.getClientVersion

-- locales
local panelName = "AttackBot"
local currentSettings

local attack_analytics = AttackAnalytics or require("core.attack.attack_analytics")
local combat_executor = CombatExecutor or require("core.attack.combat_executor")

-- Record an attack action (delegates to BotCore.Analytics if available)
local function recordAttackAction(cat, idOrFormula)
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.recordAttack(cat, idOrFormula)
    return
  end

  if cat == 1 or cat == 4 or cat == 5 then
    attack_analytics.recordSpellUse(idOrFormula)
    if cat == 4 then
      attack_analytics.recordBuffUse(idOrFormula)
    end
  elseif cat == 2 or cat == 3 then
    attack_analytics.recordRuneUse(idOrFormula)
  end
end

-- Public API for SmartHunt
AttackBot = AttackBot or {}
AttackBot.getAnalytics = function()
  if BotCore and BotCore.Analytics then
    return BotCore.Analytics.AttackBot.getAnalytics()
  end
  return attack_analytics.getAnalytics()
end
AttackBot.resetAnalytics = function()
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.AttackBot.resetAnalytics()
    return
  end
  attack_analytics.resetAnalytics()
end

local attack_data = AttackData or require("core.attack.attack_data")
local categories = attack_data.categories
local patterns = attack_data.patterns
local spellPatterns = attack_data.spellShapes

-- direction patterns
local ek = (voc() == 1 or voc() == 11) and true

local posN = ek and [[
  111
  000
  000
]] or [[
  00011111000
  00011111000
  00011111000
  00011111000
  00000100000
  00000000000
  00000000000
  00000000000
  00000000000
  00000000000
  00000000000
]]

local posE = ek and [[
  001
  001
  001
]] or   [[
  00000000000
  00000000000
  00000000000
  00000001111
  00000001111
  00000011111
  00000001111
  00000001111
  00000000000
  00000000000
  00000000000
]]
local posS = ek and [[
  000
  000
  111
]] or   [[
  00000000000
  00000000000
  00000000000
  00000000000
  00000000000
  00000000000
  00000100000
  00011111000
  00011111000
  00011111000
  00011111000
]]
local posW = ek and [[
  100
  100
  100
]] or   [[
  00000000000
  00000000000
  00000000000
  11110000000
  11110000000
  11111000000
  11110000000
  11110000000
  00000000000
  00000000000
  00000000000
]]

local attack_config = AttackConfig or require("core.attack.attack_config")

attack_config.ensureDefaults(AttackBotConfig, panelName)

-- Load character-specific profile if available
local charProfile = getCharacterProfile("attackProfile")
if charProfile and charProfile >= 1 and charProfile <= 5 then
  AttackBotConfig.currentBotProfile = charProfile
elseif not AttackBotConfig.currentBotProfile or AttackBotConfig.currentBotProfile == 0 or AttackBotConfig.currentBotProfile > 5 then
  AttackBotConfig.currentBotProfile = 1
end

local function stateControl()
  local state = false
  return {
    setOn = function(_, value) state = value == true end,
    isOn = function() return state end,
    setText = function() end,
    setColor = function() end,
  }
end

local ui = { title = stateControl(), settings = stateControl(), name = stateControl() }
for index = 1, 5 do ui[index] = stateControl() end

-- finding correct table, manual unfortunately
local setActiveProfile = function()
  currentSettings = attack_config.getActiveProfile(AttackBotConfig, panelName)
  setCharacterProfile("attackProfile", AttackBotConfig.currentBotProfile)
end
setActiveProfile()

-- Ensure currentSettings is initialized (fallback if profile is nil)
if not currentSettings then
  AttackBotConfig.currentBotProfile = 1
  setActiveProfile()
end

if not currentSettings.AntiRsRange then
  currentSettings.AntiRsRange = 5 
end




    local profileChange = function()
    setActiveProfile()
    nExBotConfigSave("atk")
  end

    -- public functions (preserve existing analytics API)
    AttackBot = AttackBot or {}
  
    AttackBot.isOn = function()
      return currentSettings.enabled
    end
    
    AttackBot.isOff = function()
      return not currentSettings.enabled
    end
    
    AttackBot.setOff = function()
      currentSettings.enabled = false
      ui.title:setOn(currentSettings.enabled)
      nExBotConfigSave("atk")
    end
    
    AttackBot.setOn = function()
      currentSettings.enabled = true
      ui.title:setOn(currentSettings.enabled)
      nExBotConfigSave("atk")
    end
    
    AttackBot.getActiveProfile = function()
      return AttackBotConfig.currentBotProfile -- returns number 1-5
    end
  
    AttackBot.setActiveProfile = function(n)
      if not n or not tonumber(n) or n < 1 or n > 5 then
        return error("[AttackBot] wrong profile parameter! should be 1 to 5 is " .. n)
      else
        AttackBotConfig.currentBotProfile = n
        profileChange()
      end
    end

    AttackBot.show = function()
      -- no-op: the shell page renders the attack config; nothing to open.
    end

    AttackBot.getRules = function()
      local rules = {}
      for index, entry in ipairs(currentSettings.attackTable or {}) do
        rules[#rules + 1] = {
          index = index, enabled = entry.enabled ~= false, spell = entry.spell,
          itemId = tonumber(entry.itemId) and entry.itemId > 0 and entry.itemId or nil,
          count = entry.count, orMore = entry.orMore, mana = entry.mana,
          minHp = entry.minHp, maxHp = entry.maxHp, cooldown = entry.cooldown,
          category = entry.category, patternCategory = entry.patternCategory, pattern = entry.pattern,
          description = entry.description, revision = index .. ":" .. tostring(entry.enabled),
        }
      end
      return rules
    end

    AttackBot.toggleRule = function(index)
      local entry = currentSettings.attackTable and currentSettings.attackTable[index]
      if not entry then return false end
      entry.enabled = not entry.enabled
      nExBotConfigSave("atk")
      return true
    end

    AttackBot.removeRule = function(index)
      if not currentSettings.attackTable or not currentSettings.attackTable[index] then return false end
      table.remove(currentSettings.attackTable, index)
      nExBotConfigSave("atk")
      return true
    end

    AttackBot.moveRule = function(index, direction)
      local rules = currentSettings.attackTable or {}
      local destination = index + (direction == "up" and -1 or direction == "down" and 1 or 0)
      if not rules[index] or destination < 1 or destination > #rules or destination == index then return false end
      rules[index], rules[destination] = rules[destination], rules[index]
      nExBotConfigSave("atk")
      return true
    end

    AttackBot.getSetting = function(key)
      return currentSettings and currentSettings[key]
    end

    AttackBot.setSetting = function(key, value)
      if not currentSettings or key == nil then return false end
      currentSettings[key] = value
      nExBotConfigSave("atk")
      return true
    end

    AttackBot.addRule = function(params)
      if type(params) ~= "table" then return false end
      local creatures = tostring(params.creatures or "")
      local monsters = true
      if creatures ~= "" and creatures ~= "*" then
        monsters = string.split(creatures:lower(), ",")
      end
      local itemId = tonumber(params.itemId) or 0
      local spell = itemId > 0 and nil or params.spell
      local entry = {
        creatures = creatures,
        monsters = monsters,
        mana = tonumber(params.mana) or 1,
        count = tonumber(params.count) or 1,
        minHp = tonumber(params.minHp) or 0,
        maxHp = tonumber(params.maxHp) or 100,
        cooldown = tonumber(params.cooldown) or 0,
        itemId = itemId,
        spell = spell,
        enabled = params.enabled ~= false,
        category = tonumber(params.category) or 1,
        patternCategory = tonumber(params.patternCategory) or (tonumber(params.category) or 1),
        pattern = tonumber(params.pattern) or 1,
        orMore = params.orMore == true,
        tooltip = type(monsters) == "table" and creatures or nil,
        description = params.description,
      }
      if not entry.description then
        local attackType = itemId > 0 and ("rune " .. itemId) or (spell or "spell")
        local countLabel = entry.orMore and (entry.count .. "+") or entry.count
        entry.description = "[" .. attackType .. "] " .. countLabel .. " creatures, HP " .. entry.minHp .. "%-" .. entry.maxHp .. "%"
      end
      currentSettings.attackTable = currentSettings.attackTable or {}
      currentSettings.attackTable[#currentSettings.attackTable + 1] = entry
      nExBotConfigSave("atk")
      return true
    end

-- COOLDOWN MANAGEMENT (use ClientHelper for DRY)

local cooldowns = {}

local nowMs = ClientHelper and ClientHelper.nowMs or function()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

local function toCooldownMs(cd)
  local value = tonumber(cd) or 0
  if value <= 0 then return 0 end
  -- Backward compatibility: treat large values as already in ms
  if value >= 1000 then return value end
  return value * 1000
end

local spellState = {}
local globalCastBackoffUntil = 0
local GLOBAL_CAST_BACKOFF = 250
local FAILED_CAST_BACKOFF = 350

local function isSpellCategory(category)
  return category == 1 or category == 4 or category == 5
end

local function getSpellKey(entry)
  return (entry and entry.spell or ""):lower()
end

local function getSpellState(key)
  if not key or key == "" then return nil end
  local state = spellState[key]
  if not state then
    state = { nextReadyAt = 0, lastAttemptAt = 0 }
    spellState[key] = state
  end
  return state
end

local function applyGlobalBackoff(ms)
  if not ms or ms <= 0 then return end
  local untilTs = nowMs() + ms
  if untilTs > globalCastBackoffUntil then
    globalCastBackoffUntil = untilTs
  end
end

local function isGlobalBackoffActive()
  return nowMs() < globalCastBackoffUntil
end

local function confirmSpellCast(spellKey, beforeTs, onSuccess, onFail)
  schedule(120, function()
    local afterTs = SpellCastTable and SpellCastTable[spellKey] and SpellCastTable[spellKey].t or 0
    if afterTs > (beforeTs or 0) then
      if onSuccess then onSuccess() end
    else
      if onFail then onFail() end
    end
  end)
end

local function attemptSpellCast(entry, context)
  local deps = {
    cast = cast,
    getSpellKey = getSpellKey,
    getSpellState = getSpellState,
    toCooldownMs = toCooldownMs,
    nowMs = nowMs,
    SafeCall = SafeCall,
    confirmSpellCast = confirmSpellCast,
    applyGlobalBackoff = applyGlobalBackoff,
    recordAttackAction = recordAttackAction,
    currentSettings = currentSettings,
  }
  return combat_executor.attemptSpellCast(entry, context, deps)
end

-- Check individual action cooldown
local function ready(key, cd)
  if not key then return true end
  local last = cooldowns[key] or 0
  return (nowMs() - last) >= (cd or 1000)
end

-- Mark action as used
local function stamp(key)
  if key then
    cooldowns[key] = nowMs()
  end
end

-- otui covered, now support functions
function getPattern(category, pattern, safe)
  safe = safe and 2 or 1

  return spellPatterns[category][pattern][safe]
end

function getMonstersInArea(category, posOrCreature, pattern, minHp, maxHp, safePattern, monsterNamesTable)
  -- monsterNamesTable can be nil
  local monsters = 0
  local t = {}
  if monsterNamesTable == true or not monsterNamesTable then
    t = {}
  else
    t = monsterNamesTable
  end

  if safePattern then
    for i, spec in pairs(getSpectators(posOrCreature, safePattern)) do
      if spec ~= player and (spec:isPlayer() and not spec:isPartyMember()) then
        return 0
      end
    end
  end 

  if category == 1 or category == 3 or category == 4 then
    -- Anchor to provided creature/position or fallback to current target
    local anchorTarget = posOrCreature or SafeCall.getTarget()
    local anchorName = anchorTarget and (type(anchorTarget) == "table" and nil or (anchorTarget.getName and anchorTarget:getName())) or nil
    if category == 1 or category == 3 then
      if #t ~= 0 and anchorName and not table.find(t, anchorName, true) then
        return 0
      end
    end

    -- Use spectators relative to anchor when possible
    local spectators = nil
    if posOrCreature and pattern and type(pattern) == "number" then
      spectators = getSpectators(posOrCreature, pattern) or {}
    else
      spectators = SafeCall.global("getSpectators") or {}
    end
    local counted = 0

    for i, spec in pairs(spectators) do
      if spec ~= player then
        local specHp = spec:getHealthPercent()
        local name = spec:getName():lower()
        local withinRadius = true
        local dist = nil
        if posOrCreature and pattern and type(pattern) == "number" then
          local ok, aPos = pcall(function()
            if type(posOrCreature) == "table" then return posOrCreature end
            if posOrCreature.getPosition then return posOrCreature:getPosition() end
            return nil
          end)
          if ok and aPos then
            local sPos = spec:getPosition()
            local dx = math.abs(sPos.x - aPos.x)
            local dy = math.abs(sPos.y - aPos.y)
            local dz = math.abs((sPos.z or 0) - (aPos.z or 0))
            dist = math.max(dx, dy, dz)
            withinRadius = dist <= pattern
          else
            withinRadius = false
          end
        end
        local isMonster = spec:isMonster() and withinRadius and specHp >= minHp and specHp <= maxHp and (#t == 0 or table.find(t, name, true)) and
                   (getClientVersion() < 960 or spec:getType() < 3)
        if isMonster then
          monsters = monsters + 1
          counted = counted + 1
        end

      end
    end

    return monsters
  end

  for i, spec in pairs(getSpectators(posOrCreature, pattern)) do
      if spec ~= player then
        local specHp = spec:getHealthPercent()
        local name = spec:getName():lower()
        monsters = spec:isMonster() and specHp >= minHp and specHp <= maxHp and (#t == 0 or table.find(t, name)) and
                   (getClientVersion() < 960 or spec:getType() < 3) and monsters + 1 or monsters
      end
  end

  return monsters
end

-- for area runes only
-- should return valid targets number (int) and position
function getBestTileByPattern(pattern, minHp, maxHp, safePattern, monsterNamesTable)
  local Client = getClient()
  local playerPos = pos()
  local targetTile = {amount=0,pos=false}

  -- Only scan tiles within shootable range (max 3 sqm) instead of entire floor
  for dx = -3, 3 do
    for dy = -3, 3 do
      local tPos = {x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z}
      local tile = (Client and Client.getTile) and Client.getTile(tPos) or (g_map and g_map.getTile(tPos))
      if tile and tile:canShoot() and tile:isWalkable() then
        local amount = getMonstersInArea(2, tPos, pattern, minHp, maxHp, safePattern, monsterNamesTable)
        if amount > targetTile.amount then
          targetTile = {amount=amount,pos=tPos}
        end
      end
    end
  end

  return targetTile.amount > 0 and targetTile or false
end

-- Use rune on target - works even with closed backpack (hotkey-style)
-- Uses BotCore.Items for consolidated item usage
local function useRuneOnTarget(runeId, targetCreatureOrTile)
  lastAttackTime = now
  local deps = {
    useWith = useWith,
    g_game = g_game,
    SafeCall = SafeCall,
    Client = getClient(),
  }
  return combat_executor.useRuneOnTarget(runeId, targetCreatureOrTile, deps)
end

function executeAttackBotAction(categoryOrPos, idOrFormula, cooldown)
  cooldown = cooldown or 0
  lastAttackTime = now -- Update attack time for non-blocking cooldown
  
  -- Mark action as used for cooldown tracking
  stamp(tostring(idOrFormula))
  
  -- Record analytics before executing
  recordAttackAction(categoryOrPos, idOrFormula)
  
  if categoryOrPos == 4 or categoryOrPos == 5 or categoryOrPos == 1 then
    cast(idOrFormula, cooldown)
  elseif categoryOrPos == 3 then 
    useRuneOnTarget(idOrFormula, SafeCall.target())
  end
end

-- support function covered, now the main loop
-- State for non-blocking delay
local lastAttackTime = 0
local ATTACK_COOLDOWN = 100

-- Pre-allocated direction data (avoid table creation per tick)
local directionCounts = {0, 0, 0, 0}  -- N, E, S, W
local DIR_NORTH, DIR_EAST, DIR_SOUTH, DIR_WEST = 0, 1, 2, 3

-- Cache client version check (doesn't change at runtime)
local isOldClient = getClientVersion() < 960

-- Use UnifiedTick if available for reduced macro overhead
local attackMacro
if UnifiedTick and UnifiedTick.register then
  UnifiedTick.register("attackbot_main", {
    interval = 100,
    priority = UnifiedTick.Priority and UnifiedTick.Priority.HIGH or 75,
    handler = function() attackBotMain() end,
    group = "attackbot"
  })
else
  attackMacro = macro(100, function()
    attackBotMain()
  end)
end

-- SIMPLIFIED ATTACKBOT - HIGH PERFORMANCE & ACCURACY

-- Per-tick cache for expensive computations
local lastAutoRotate = 0
local rotationCooldown = 500 -- ms
local ATTACK_DEBUG = false -- set to true to enable debug logs

local function newAttackCache()
  return {
    monstersInArea = {}, -- key -> number
    bestTileByPattern = {}, -- key -> {amount=, pos=}
    now = now
  }
end

local function cacheKeyForArea(category, posOrCreature, pattern, minHp, maxHp, safePattern, monsterNamesTable)
  -- Create a stable key for caching getMonstersInArea
  local p = posOrCreature and (type(posOrCreature) == "table" and (posOrCreature.x..":"..posOrCreature.y..":"..posOrCreature.z) or tostring(posOrCreature)) or "nil"
  local namesKey = monsterNamesTable == true and "any" or (monsterNamesTable and table.concat(monsterNamesTable, ",") or "")
  return table.concat({tostring(category), p, tostring(pattern or "nil"), tostring(minHp), tostring(maxHp), tostring(safePattern), namesKey}, "|")
end

-- Build a stable cache key for area-rune pattern lookups (used by evaluateEntry + executeAttack)
local function buildPatternKey(entry, pvpSafe)
  local monstersKey = entry.monsters == true and "any" or (type(entry.monsters) == "table" and table.concat(entry.monsters, ",") or "")
  return entry.patternCategory..":"..entry.pattern..":"..tostring(pvpSafe)..":"..entry.minHp..":"..entry.maxHp..":"..monstersKey
end

-- Pure evaluator using caching and vBot semantics
local function evaluateEntry(entry, context, cache)
  if not entry.enabled then return false end

  -- Mana check
  if context.mana < entry.mana then return false end

  -- Cooldown check
  local cdMs = toCooldownMs(entry.cooldown)
  if context.settings.Cooldown then
    -- Categories 1, 4, 5 are spell-based; categories 2, 3 are rune-based
    if isSpellCategory(entry.category) then
      local state = getSpellState(getSpellKey(entry))
      if state and nowMs() < state.nextReadyAt then return false end
    else
      if not ready(entry.key or tostring(entry.itemId or entry.spell), cdMs) then return false end
    end
  end

  -- Target checks
  if not context.target then return false end
  local targetHp = context.target:getHealthPercent()
  local targetDist = distanceFromPlayer(context.target:getPosition())

  -- Safety checks (context-wide, already computed once per tick)
  if context.blacklisted or context.killsBlocked then return false end

  -- PVP mode: disallow area runes in pvp situations
  if context.settings.pvpMode and entry.category == 2 and targetHp >= entry.minHp and targetHp <= entry.maxHp and context.target:canShoot() then
    return false
  end

  -- HP condition for attack entries
  if targetHp < entry.minHp or targetHp > entry.maxHp then return false end

  -- Category-specific checks
  if entry.category == 2 then
    -- Area rune: use pattern-based search
    local pat = getPattern(entry.patternCategory, entry.pattern, context.settings.PvpSafe)
    local pKey = buildPatternKey(entry, context.settings.PvpSafe)
    local data = cache.bestTileByPattern[pKey]
    if not data then
      data = getBestTileByPattern(pat, entry.minHp, entry.maxHp, context.settings.PvpSafe, entry.monsters)
      cache.bestTileByPattern[pKey] = data
    end
    local monsterAmount = data and data.amount or 0

    if entry.orMore then return monsterAmount >= entry.count else return monsterAmount == entry.count end
  end

  -- For targeted/empowerment/absolute entries
  if entry.category == 1 or entry.category == 3 or entry.category == 4 or entry.category == 5 then
    -- Special-case: Absolute category
    if entry.category == 5 then
      -- For sweep (pattern == 8), we already handle directional counts above
      if entry.pattern == 8 then
        local cacheKeyN = "dirN:"..entry.minHp..":"..entry.maxHp
        local cacheKeyE = "dirE:"..entry.minHp..":"..entry.maxHp
        local cacheKeyS = "dirS:"..entry.minHp..":"..entry.maxHp
        local cacheKeyW = "dirW:"..entry.minHp..":"..entry.maxHp

        local monstersN = cache.monstersInArea[cacheKeyN]
        local monstersE = cache.monstersInArea[cacheKeyE]
        local monstersS = cache.monstersInArea[cacheKeyS]
        local monstersW = cache.monstersInArea[cacheKeyW]

        if monstersN == nil then
          monstersN = getMonstersInArea(2, pos(), posN, entry.minHp, entry.maxHp, false, entry.monsters)
          cache.monstersInArea[cacheKeyN] = monstersN
        end
        if monstersE == nil then
          monstersE = getMonstersInArea(2, pos(), posE, entry.minHp, entry.maxHp, false, entry.monsters)
          cache.monstersInArea[cacheKeyE] = monstersE
        end
        if monstersS == nil then
          monstersS = getMonstersInArea(2, pos(), posS, entry.minHp, entry.maxHp, false, entry.monsters)
          cache.monstersInArea[cacheKeyS] = monstersS
        end
        if monstersW == nil then
          monstersW = getMonstersInArea(2, pos(), posW, entry.minHp, entry.maxHp, false, entry.monsters)
          cache.monstersInArea[cacheKeyW] = monstersW
        end

        local bestSide = math.max(monstersN, monstersE, monstersS, monstersW)
        local bestDir = nil
        if bestSide == monstersN then bestDir = 0
        elseif bestSide == monstersE then bestDir = 1
        elseif bestSide == monstersS then bestDir = 2
        elseif bestSide == monstersW then bestDir = 3
        end
        -- require no players nearby if PvP safe is enabled
        local players = SafeCall.getPlayers and SafeCall.getPlayers(2) or {}
        local playersNearby = (#players > 0)
        local sweepMatch = entry.orMore and bestSide >= entry.count or bestSide == entry.count
        if sweepMatch and (not context.settings.PvpSafe or not playersNearby) then
          -- store best sweep direction for executeAttack to use (rotation)
          cache.bestSweepDir = bestDir
          cache.bestSweepSide = bestSide
          -- reset rotation attempts when best direction changes
          cache.rotationAttemptsDir = bestDir
          cache.rotationAttempts = 0
          cache.rotationAttemptsStart = now
          return true
        else
          return false
        end
      end

      -- For other absolute patterns, follow vBot behavior and use pattern shapes
      local pCat = entry.patternCategory
      local pattern = entry.pattern
      local anchorParam = (pattern == 2 or pattern == 6 or pattern == 7 or pattern > 9) and player or pos()
      local safe = context.settings.PvpSafe and spellPatterns[pCat][entry.pattern][2] or false
      local patternShape = spellPatterns[pCat][entry.pattern][1]
      local cacheKey = cacheKeyForArea(entry.category, anchorParam, patternShape, entry.minHp, entry.maxHp, safe, entry.monsters)
      local monsterAmount = cache.monstersInArea[cacheKey]
      if monsterAmount == nil then
        monsterAmount = getMonstersInArea(entry.category, anchorParam, patternShape, entry.minHp, entry.maxHp, safe, entry.monsters)
        cache.monstersInArea[cacheKey] = monsterAmount
      end

      if entry.orMore then return monsterAmount >= entry.count else return monsterAmount == entry.count end
    end

    -- Fallback for targeted/empowerment entries
    -- Anchor targeted/emp entries to the current target and respect numeric pattern as a radius
    local posArg = (entry.category == 1 or entry.category == 3) and context.target or nil
    local patternArg = (entry.category == 1 or entry.category == 3) and entry.pattern or nil
    local key = cacheKeyForArea(entry.category, posArg, patternArg, entry.minHp, entry.maxHp, false, entry.monsters)
    local monsterAmount = cache.monstersInArea[key]
    if monsterAmount == nil then
      monsterAmount = getMonstersInArea(entry.category, posArg, patternArg, entry.minHp, entry.maxHp, false, entry.monsters)
      cache.monstersInArea[key] = monsterAmount
    end

    -- For targeted categories, also ensure target is within configured range
    if entry.category == 1 or entry.category == 3 then
      if targetDist > entry.pattern then return false end
    end
    if entry.orMore then return monsterAmount >= entry.count else return monsterAmount == entry.count end
  end

  return true
end

-- Pure function: Execute attack action
local function executeAttack(entry, context)
  local deps = {
    isSpellCategory = isSpellCategory,
    getSpellKey = getSpellKey,
    getSpellState = getSpellState,
    toCooldownMs = toCooldownMs,
    nowMs = nowMs,
    SafeCall = SafeCall,
    cast = cast,
    confirmSpellCast = confirmSpellCast,
    applyGlobalBackoff = applyGlobalBackoff,
    recordAttackAction = recordAttackAction,
    spellPatterns = spellPatterns,
    buildPatternKey = buildPatternKey,
    getBestTileByPattern = getBestTileByPattern,
    getSpectators = getSpectators,
    Client = getClient(),
  }
  return combat_executor.executeAttack(entry, context, deps)
end

-- Main attack function — AAA pattern (Arrange → Act → Assert)
function attackBotMain()
  -- ========== ARRANGE: Gather world state and pre-check context ==========

  -- Global guards (cannot attack at all)
  if not currentSettings or not currentSettings.enabled then return end
  if not currentSettings.attackTable or #currentSettings.attackTable == 0 then return end
  if not target() then return end
  if SafeCall.isInPz() then return end
  if isGlobalBackoffActive() then return end
  if BotCore and BotCore.Cooldown and BotCore.Cooldown.isAttackOnCooldown() then return end
  if modules.game_cooldown.isGroupCooldownIconActive(1) then return end
  if BotCore and BotCore.Priority and not BotCore.Priority.canAttack() then return end
  if currentSettings.Training and target():getName():lower():find("training") then return end

  -- Build context snapshot (computed ONCE per tick, shared across all entries)
  local context = {
    target = target(),
    mana = manapercent(),
    settings = currentSettings,
    -- Pre-compute context-wide safety flags (avoids per-entry recalc)
    blacklisted = currentSettings.BlackListSafe and isBlackListedPlayerInRange(currentSettings.AntiRsRange),
    killsBlocked = currentSettings.Kills and killsToRs() <= currentSettings.KillsAmount,
    _attackCache = newAttackCache(),
  }

  -- Early-exit if context-wide safety blocks all attacks
  if context.blacklisted or context.killsBlocked then return end

  -- Resource availability cache (items/spells checked once per item/spell key)
  local availableItems = {}
  local canCastCaller = SafeCall.getCachedCaller("canCast")
  local entries = currentSettings.attackTable

  -- ========== ACT: Find highest-priority valid entry and execute ==========

  for _, entry in ipairs(entries) do
    if not entry then goto continue end

    -- Resource check (item in inventory / spell castable)
    local available = false
    if entry.itemId and entry.itemId > 100 then
      if availableItems[entry.itemId] == nil then
        availableItems[entry.itemId] = (not currentSettings.Visible) or SafeCall.findItem(entry.itemId)
      end
      available = availableItems[entry.itemId]
    else
      local spellKey = (entry.spell or ""):lower()
      local ok = true
      if canCastCaller then
        ok = canCastCaller(spellKey, not currentSettings.ignoreMana, not currentSettings.Cooldown)
      end
      if ok == nil then ok = true end
      available = ok
    end

    if not available then goto continue end

    -- ========== ASSERT: Verify cooldowns still clear before evaluation ==========
    if BotCore and BotCore.Cooldown and BotCore.Cooldown.isAttackOnCooldown() then break end
    if modules.game_cooldown.isGroupCooldownIconActive(1) then break end

    if evaluateEntry(entry, context, context._attackCache) then
      local attempted = executeAttack(entry, context)
      if attempted then return end  -- One action per tick (spell or rune)
    end
    ::continue::
  end
end
