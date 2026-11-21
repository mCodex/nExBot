-- Panel name constant (must be defined before ensureCurrentSettings uses it)
local healPanelName = "healbot"
local heal_config = HealConfig or require("core.heal.heal_config")

-- Safety: auto-restore currentSettings if nil
local function ensureCurrentSettings()
  if not currentSettings then
    if not HealBotConfig then HealBotConfig = {} end
    heal_config.ensureDefaults(HealBotConfig, healPanelName)
    if not HealBotConfig.currentHealBotProfile or HealBotConfig.currentHealBotProfile < 1 or HealBotConfig.currentHealBotProfile > 5 then
      HealBotConfig.currentHealBotProfile = 1
    end
    -- Use setActiveProfile to properly assign currentSettings
    if setActiveProfile then
      pcall(setActiveProfile)
    else
      currentSettings = HealBotConfig[healPanelName][HealBotConfig.currentHealBotProfile]
    end
  end
end

local standBySpells, standByItems = false, false

-- Load heal modules using simple dofile; they set globals directly
-- Try multiple paths in order of likelihood
local function tryLoadModule(name)
  local paths = {
    "core/" .. name .. ".lua",
    "/core/" .. name .. ".lua"
  }
  for _, path in ipairs(paths) do
    local ok = pcall(dofile, path)
    if ok then return true end
  end
  return false
end

-- Load heal_context (sets global HealContext)
if not HealContext then
  tryLoadModule("heal_context")
end
if not HealContext or not HealContext.get then
  warn("[HealBot] HealContext not loaded")
end

-- Load heal_engine (sets global HealEngine)
if not HealEngine then
  tryLoadModule("heal_engine")
end
if not HealEngine then
  warn("[HealBot] HealEngine not loaded")
end
HealBot = HealBot or {}

local spell_resolver = SpellResolver or require("core.heal.spell_resolver")
local heal_analytics = HealAnalytics or require("core.heal.heal_analytics")

local function convertSpellsToEngineFormat(spellTable)
  return spell_resolver.convertSpellsToEngineFormat(spellTable)
end

local function convertPotionsToEngineFormat(itemTable)
  local function getItemName(itemId)
    if g_things and g_things.getThingType then
      local thing = g_things.getThingType(itemId, ThingCategoryItem)
      if thing and thing.getName then
        local name = thing:getName()
        if name and name ~= "" then
          return name:lower()
        end
      elseif thing and thing.getMarketData then
        local marketData = thing:getMarketData()
        if marketData and marketData.name and marketData.name ~= "" then
          return marketData.name:lower()
        end
      end
    end
    return nil
  end
  return spell_resolver.convertPotionsToEngineFormat(itemTable, getItemName)
end

local function applyHealEngineToggles()
  ensureCurrentSettings()
  if not HealEngine or not HealEngine.configure then return end
  if not currentSettings then
    warn("[HealBot] applyHealEngineToggles: currentSettings missing, aborting sync")
    return
  end
  local isOn = not not currentSettings.enabled
  local hasSpells = currentSettings.spellTable and #currentSettings.spellTable > 0
  local hasItems = currentSettings.itemTable and #currentSettings.itemTable > 0

  HealEngine.configure({
    selfSpells = isOn and hasSpells,
    potions = isOn and hasItems,
    friendHeals = false
  })

  -- Sync spell list to engine
  if HealEngine.setCustomSpells then
    local convertedSpells = convertSpellsToEngineFormat(currentSettings.spellTable)
    local ok = pcall(HealEngine.setCustomSpells, convertedSpells)
    if not ok then HealEngine._pendingSpells = convertedSpells
    else HealEngine._pendingSpells = nil end
    nExBot_LastConvertedSpells = convertedSpells
  end

  -- Sync potion list to engine
  if HealEngine.setCustomPotions then
    local convertedPotions = convertPotionsToEngineFormat(currentSettings.itemTable)
    local ok = pcall(HealEngine.setCustomPotions, convertedPotions)
    if not ok then HealEngine._pendingPotions = convertedPotions
    else HealEngine._pendingPotions = nil end
    nExBot_LastConvertedPotions = convertedPotions
  end
end

local red = "#ff0800" -- "#ff0800" / #ea3c53 best
local blue = "#7ef9ff"

local function stateControl()
  local state = false
  return {
    setOn = function(_, value) state = value == true end,
    isOn = function() return state end,
    setText = function() end,
    setColor = function() end,
  }
end

local ui = { title = stateControl(), settings = stateControl(), allySetup = stateControl(), name = stateControl() }
for index = 1, 5 do ui[index] = stateControl() end

heal_config.ensureDefaults(HealBotConfig, healPanelName)

-- Load character-specific profile if available
local charProfile = getCharacterProfile("healProfile")
if charProfile and charProfile >= 1 and charProfile <= 5 then
  HealBotConfig.currentHealBotProfile = charProfile
elseif not HealBotConfig.currentHealBotProfile or HealBotConfig.currentHealBotProfile == 0 or HealBotConfig.currentHealBotProfile > 5 then 
  HealBotConfig.currentHealBotProfile = 1
end

-- finding correct table, manual unfortunately
local currentSettings
local setActiveProfile = function()
  local n = HealBotConfig.currentHealBotProfile
  currentSettings = HealBotConfig[healPanelName][n]
  -- Save character's profile preference
  setCharacterProfile("healProfile", n)
end
setActiveProfile()

local function saveHeal()
  local ok = false
  local status, res = pcall(function() return nExBotConfigSave("heal") end)
  if status and res == true then
    ok = true
  end
  if not ok then
    warn("[nExBot] Failed to save Heal config")
  end
  return ok
end

-- Macro handle so we can fully stop/start execution with the UI toggle
local healMacro = nil
local function syncHealMacro()
  if healMacro and healMacro.setOn then
    healMacro:setOn(currentSettings.enabled)
  end
end

local activeProfileColor = function()
  for i=1,5 do
    if i == HealBotConfig.currentHealBotProfile then
      ui[i]:setColor("green")
    else
      ui[i]:setColor("white")
    end
  end
end
activeProfileColor()

ui.title:setOn(currentSettings.enabled)
ui.title.onClick = function(widget)
  currentSettings.enabled = not currentSettings.enabled
  widget:setOn(currentSettings.enabled)
  syncHealMacro()
  applyHealEngineToggles()  -- Update HealEngine when toggling on/off
  saveHeal()
end

-- Converter functions already defined at top of file

-- Public HealBot API. The standalone HealWindow is retired; the shell's
-- healing page drives this domain API directly (widget code never touches
-- domain tables).
local function profileChange()
  setActiveProfile()
  activeProfileColor()
  applyHealEngineToggles()  -- Update HealEngine with new profile's spells/potions
  saveHeal()
end

HealBot = {} -- global table

HealBot.isOn = function()
  return currentSettings.enabled
end

HealBot.isOff = function()
  return not currentSettings.enabled
end

HealBot.setOff = function()
  currentSettings.enabled = false
  syncHealMacro()
  applyHealEngineToggles()
  saveHeal()
end

HealBot.setOn = function()
  currentSettings.enabled = true
  syncHealMacro()
  applyHealEngineToggles()
  saveHeal()
end

HealBot.getActiveProfile = function()
  return HealBotConfig.currentHealBotProfile -- returns number 1-5
end

HealBot.setActiveProfile = function(n)
  if not n or not tonumber(n) or n < 1 or n > 5 then
    return error("[HealBot] wrong profile parameter! should be 1 to 5 is " .. tostring(n))
  end
  HealBotConfig.currentHealBotProfile = n
  profileChange()
end

-- Standalone window retired; kept as a safe no-op for legacy callers.
HealBot.show = function() end

-- Settings were widget-backed (Cooldown/Visible/Delay/Interval/Conditions);
-- they live in the same persisted profile table the retired window wrote to.
HealBot.getSetting = function(key)
  return currentSettings[key]
end

HealBot.setSetting = function(key, value)
  currentSettings[key] = not not value
  saveHeal()
end

local function describeRule(kind, entry)
  if kind == "item" then
    return string.format("%s%s%s: item %s", entry.origin or "", entry.sign or "", tostring(entry.value or ""), tostring(entry.item))
  end
  return string.format("(MP>%s) %s%s%s: %s", tostring(entry.cost), entry.origin or "", entry.sign or "", tostring(entry.value or ""), tostring(entry.spell))
end

local function ruleSource(kind)
  ensureCurrentSettings()
  if not currentSettings then return nil end
  return kind == "item" and currentSettings.itemTable or currentSettings.spellTable
end

-- Read-only projection for the shell's healing page. Widgets consume this;
-- they never touch spellTable/itemTable directly.
HealBot.getRules = function(kind)
  local source = ruleSource(kind)
  local rules = {}
  if not source then return rules end
  for index, entry in ipairs(source) do
    rules[#rules + 1] = {
      kind = kind, index = index, enabled = entry.enabled,
      label = describeRule(kind, entry), itemId = kind == "item" and entry.item or nil,
      spell = entry.spell, origin = entry.origin, sign = entry.sign,
      value = entry.value, cost = entry.cost, revision = index .. ":" .. tostring(entry.enabled),
    }
  end
  return rules
end

HealBot.addRule = function(kind, params)
  params = params or {}
  if kind ~= "spell" and kind ~= "item" then return false end
  local value = tonumber(params.value)
  if not value then return false end
  if kind == "item" then
    local item = tonumber(params.item)
    if not item or item <= 100 then return false end
    local source = currentSettings.itemTable or {}
    table.insert(source, { index = #source + 1, item = item, sign = "<", origin = "HP%", value = value, enabled = true })
    currentSettings.itemTable = source
  else
    local spell = tostring(params.spell or ""):match("^%s*(.-)%s*$")
    if spell == "" then return false end
    local source = currentSettings.spellTable or {}
    table.insert(source, { index = #source + 1, spell = spell, sign = "<", origin = "HP%", value = value, cost = tonumber(params.cost) or 0, enabled = true })
    currentSettings.spellTable = source
  end
  applyHealEngineToggles()
  saveHeal()
  return true
end

HealBot.toggleRule = function(kind, index)
  local source = ruleSource(kind)
  local entry = source and source[index]
  if not entry then return end
  entry.enabled = not entry.enabled
  applyHealEngineToggles()
  saveHeal()
end

HealBot.removeRule = function(kind, index)
  local source = ruleSource(kind)
  local entry = source and source[index]
  if not entry then return end
  table.removevalue(source, entry)
  applyHealEngineToggles()
  saveHeal()
end

HealBot.moveRule = function(kind, index, direction)
  local source = ruleSource(kind)
  local destination = index + (direction == "up" and -1 or direction == "down" and 1 or 0)
  if not source or not source[index] or destination < 1 or destination > #source or destination == index then return false end
  source[index], source[destination] = source[destination], source[index]
  applyHealEngineToggles()
  saveHeal()
  return true
end

--[[
  Optimized HealBot Engine
  
  Uses BotCore for unified stats, conditions, and analytics.
  Pre-caches stat functions and uses O(1) condition lookups.
]]

-- BOTCORE INTEGRATION

-- Use BotCore for stats (single source of truth)
local function getStats()
  if BotCore and BotCore.Stats then
    return BotCore.Stats.getAll()
  end
  -- Fallback for standalone testing
  local localPlayer = ClientService and ClientService.getLocalPlayer and ClientService.getLocalPlayer()
  if not localPlayer then return { hp = 0, maxHp = 1, hpPercent = 0, mp = 0, maxMp = 1, mpPercent = 0, burst = 0 } end
  local hp = localPlayer:getHealth()
  local maxHp = localPlayer:getMaxHealth()
  local mp = localPlayer:getMana()
  local maxMp = localPlayer:getMaxMana()
  return {
    hp = hp, maxHp = maxHp, hpPercent = math.floor((hp / maxHp) * 100),
    mp = mp, maxMp = maxMp, mpPercent = math.floor((mp / maxMp) * 100),
    burst = burstDamageValue and burstDamageValue() or 0
  }
end

-- Legacy analytics wrapper (redirects to BotCore.Analytics)
local analytics = heal_analytics.getAnalytics()

-- Flag to trigger immediate heal check
local needsHealCheck = true
local needsItemCheck = true

-- Use BotCore.Condition for checks (pure functions)
local function checkCondition(origin, sign, value)
  if BotCore and BotCore.Condition then
    return BotCore.Condition.check(origin, sign, value, getStats())
  end
  -- Fallback
  local stats = getStats()
  local current = nil
  if origin == "HP%" then current = stats.hpPercent
  elseif origin == "HP" then current = stats.hp
  elseif origin == "MP%" then current = stats.mpPercent
  elseif origin == "MP" then current = stats.mp
  elseif origin == "burst" then current = stats.burst end
  if not current then return false end
  if sign == "=" then return current == value end
  if sign == ">" then return current >= value end
  return current <= value
end

-- Cached player reference (avoid repeated lookups)
local cachedLocalPlayer = nil
local lastPlayerCheck = 0
local PLAYER_CHECK_INTERVAL = 1000  -- Revalidate player reference every 1s

-- Update stats (delegates to BotCore if available)
-- Analytics helpers (redirect to BotCore.Analytics if available)
local function appendLog(entry)
  if BotCore and BotCore.Analytics then
    -- BotCore handles logging internally
    return
  end
  local log = analytics.log
  log[#log + 1] = entry
  TrimArray(log, 50)
end

local function recordSpell(entry, hpPercent, mpPercent)
  -- Use BotCore.Analytics if available
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.recordHealSpell(entry.spell, entry.cost, hpPercent, mpPercent)
    return
  end
  
  -- Fallback to local analytics
  analytics.spellCasts = analytics.spellCasts + 1
  
  -- Track individual spell usage
  local spellName = entry.spell or "unknown"
  analytics.spells[spellName] = (analytics.spells[spellName] or 0) + 1
  
  local wasted = false
  if entry.cost and hpPercent and entry.value then
    -- If we cast while already above the trigger threshold by 10%, count as waste
    if hpPercent > (entry.value + 10) then
      analytics.manaWaste = analytics.manaWaste + entry.cost
      wasted = true
    end
  end
  appendLog({
    t = now,
    kind = "spell",
    name = entry.spell,
    hp = hpPercent,
    mp = mpPercent,
    cost = entry.cost,
    wasted = wasted
  })
end

local function recordPotion(entry, hpPercent, mpPercent)
  -- Use BotCore.Analytics if available
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.recordPotion(entry.item, hpPercent, mpPercent)
    return
  end
  
  -- Fallback to local analytics
  analytics.potionUses = analytics.potionUses + 1
  
  -- Track individual potion usage (use string key to prevent sparse array issues)
  local itemKey = tostring(entry.item or 0)
  analytics.potions[itemKey] = (analytics.potions[itemKey] or 0) + 1
  
  local wasted = false
  if entry.value then
    -- If we potion when HP is already 10% above trigger, count as waste
    if hpPercent > (entry.value + 10) then
      analytics.potionWaste = analytics.potionWaste + 1
      wasted = true
    end
  end
  appendLog({
    t = now,
    kind = "potion",
    name = entry.item,
    hp = hpPercent,
    mp = mpPercent,
    wasted = wasted
  })
end

HealBot = HealBot or {}

-- Redirect to BotCore.Analytics if available
HealBot.getAnalytics = function()
  if BotCore and BotCore.Analytics then
    return BotCore.Analytics.HealBot.getAnalytics()
  end
  return heal_analytics.getAnalytics()
end

HealBot.resetAnalytics = function()
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.HealBot.resetAnalytics()
    return
  end
  heal_analytics.resetAnalytics()
end

-- Subscribe to EventBus for instant reaction to stat changes
-- Note: BotCore handles event-driven stat updates, we just need to reset flags

-- Fast spell macro (driven by HealBot on/off state)
-- Main healing macro loop (keeps heal engine ticking)
local _lastApplyToggle = 0
local syncDone = false
local SYNC_INTERVAL_MS = 500  -- Reduced from 2000ms for faster profile updates

-- HealBot handler function (shared by UnifiedTick and fallback macro)
local function healBotHandler()
  ensureCurrentSettings()
  if not currentSettings or not currentSettings.enabled then return end
  
  if not HealContext or not HealContext.get then return end
  if not HealEngine or not HealEngine.planSelf then return end

  -- Force sync once on first run to ensure spells are loaded
  if not syncDone then
    applyHealEngineToggles()
    syncDone = true
  end

  -- Periodic sync to catch profile changes
  local nowTime = now or (g_clock and g_clock.millis and g_clock.millis()) or os.time() * 1000
  if (nowTime - _lastApplyToggle) > SYNC_INTERVAL_MS then
    _lastApplyToggle = nowTime
    applyHealEngineToggles()
  end

  -- Get context snapshot (includes currentMana for spell cost checks)
  local snap = HealContext.get()
  
  -- Ensure currentMana is set for proper spell eligibility
  if not snap.currentMana then
    if mana then snap.currentMana = mana() or 0
    elseif player and player.getMana then snap.currentMana = player:getMana() or 0
    else snap.currentMana = 0 end
  end
  
  local action = HealEngine.planSelf(snap)
  if action then
    HealEngine.execute(action)
  end
end

-- Use UnifiedTick if available, fallback to standalone macro
-- Healing uses CRITICAL priority for safety-critical response time
if UnifiedTick and UnifiedTick.register then
  -- Register with UnifiedTick for consolidated tick management
  UnifiedTick.register("healbot_main", {
    interval = 150,
    priority = UnifiedTick.Priority.CRITICAL,
    handler = healBotHandler,
    group = "healing"
  })
  -- Create a dummy macro for syncHealMacro compatibility
  healMacro = macro(150, function() end)
  healMacro:setOn(true)
  -- Sync macro toggle with UnifiedTick handler
  local origSyncHealMacro = syncHealMacro
  syncHealMacro = function()
    if origSyncHealMacro then origSyncHealMacro() end
    if currentSettings then
      UnifiedTick.setEnabled("healbot_main", currentSettings.enabled)
    end
  end
else
  -- Fallback to standalone macro if UnifiedTick not available
  healMacro = macro(150, healBotHandler)
end

syncHealMacro()

-- Initialize stats on load (BotCore handles this if available)
if BotCore and BotCore.Stats then
  BotCore.Stats.update()
end

local function validateStartup()
  if not HealContext or not HealContext.get then
    warn("[HealBot] HealContext missing or failed to load")
  end
  if not HealEngine then
    warn("[HealBot] HealEngine missing or failed to load")
  else
    applyHealEngineToggles()
  end
end

validateStartup()

-- ALLY HEALING UI (merged from new_healer.lua)

local allyPanelName = "newHealer"

if not storage[allyPanelName] or not storage[allyPanelName].priorities then
    storage[allyPanelName] = nil
end

if not storage[allyPanelName] then
    storage[allyPanelName] = {
        enabled = false,
        customPlayers = {},
        vocations = {},
        groups = {},
        priorities = {
            {name="Custom Spell",           enabled=false, custom=true},
            {name="Exura Gran Sio",         enabled=true,              strong = true},
            {name="Exura Tio Sio",          enabled=true,                             medium = true},
            {name="Exura Sio",              enabled=true,                                            normal = true},
            {name="Exura Gran Mas Res",     enabled=true,                                                          area = true},
            {name="Health Item",            enabled=true,                                                                      health=true},
            {name="Mana Item",              enabled=true,                                                                                  mana=true}
        },
        settings = {
            {type="HealItem",       text="Mana Item ",                   value=268},
            {type="HealScroll",     text="Item Range: ",                 value=6},
            {type="HealItem",       text="Health Item ",                 value=3160},
            {type="HealScroll",     text="Mas Res Players: ",            value=2},
            {type="HealScroll",     text="Heal Friend at: ",             value=80},
            {type="HealScroll",     text="Use Gran Sio at: ",            value=40},
            {type="HealScroll",     text="Use Tio Sio at: ",             value=65},
            {type="HealScroll",     text="Min Player HP%: ",             value=80},
            {type="HealScroll",     text="Min Player MP%: ",             value=50},
        },
        conditions = {
            knights = true,
            paladins = true,
            druids = false,
            sorcerers = false,
            monks = false,
            party = true,
            guild = false,
            friends = false
        }
    }
end

local allyConfig = storage[allyPanelName]

local function normalizeAllySettings(settings)
    if type(settings) ~= "table" then
        settings = {}
    end
    local hasTio = false
    for i = 1, #settings do
        local text = settings[i] and settings[i].text
        if text and text:find("Tio Sio") then
            hasTio = true
            break
        end
    end
    if not hasTio then
        table.insert(settings, 7, {type="HealScroll", text="Use Tio Sio at: ", value=65})
    end
    return settings
end

local function getAllySettingValue(idx, default)
    local entry = allyConfig.settings and allyConfig.settings[idx]
    if entry and entry.value ~= nil then
        return entry.value
    end
    return default
end

allyConfig.settings = normalizeAllySettings(allyConfig.settings)

-- CharacterDB integration for ally config
local function loadAllyCustomPlayers()
  if not CharacterDB or not CharacterDB.isReady or not CharacterDB.isReady() then
    return
  end
  local charPlayers = CharacterDB.get("friendHealer.customPlayers")
  if charPlayers and type(charPlayers) == "table" then
    local hasEntries = false
    for _ in pairs(charPlayers) do hasEntries = true; break end
    if hasEntries then
      allyConfig.customPlayers = charPlayers
    end
  elseif allyConfig.customPlayers then
    local hasEntries = false
    for _ in pairs(allyConfig.customPlayers) do hasEntries = true; break end
    if hasEntries then
      CharacterDB.set("friendHealer.customPlayers", allyConfig.customPlayers)
    end
  end
  local charConditions = CharacterDB.get("friendHealer.conditions")
  if charConditions and type(charConditions) == "table" then
    for k, v in pairs(charConditions) do
      allyConfig.conditions[k] = v
    end
  end
end

schedule(500, loadAllyCustomPlayers)

local function saveAllyCustomPlayers()
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    CharacterDB.set("friendHealer.customPlayers", allyConfig.customPlayers)
  end
end

-- Build config for BotCore (translates UI config → BotCore.FriendHealer shape)
local PRIORITY_FLAG_MAP = {
  strong = "useGranSio", medium = "useTioSio", normal = "useSio",
  area = "useMasRes", health = "useHealthItem", mana = "useManaItem",
}

local function buildAllyBotCoreConfig()
  local bcConfig = {
    enabled = allyConfig.enabled,
    customPlayers = allyConfig.customPlayers or {},
    conditions = allyConfig.conditions or {},
    settings = {
      manaItem = getAllySettingValue(1, 268), itemRange = getAllySettingValue(2, 6),
      healthItem = getAllySettingValue(3, 3160), masResPlayers = getAllySettingValue(4, 2),
      healAt = getAllySettingValue(5, 80), granSioAt = getAllySettingValue(6, 40),
      tioSioAt = getAllySettingValue(7, 65), minPlayerHp = getAllySettingValue(8, 80),
      minPlayerMp = getAllySettingValue(9, 50),
    },
    useSio = false, useGranSio = false, useTioSio = false,
    useMasRes = false, useHealthItem = false, useManaItem = false,
    customSpell = false, customSpellName = nil,
  }
  for _, p in ipairs(allyConfig.priorities or {}) do
    if p.enabled then
      local flag = PRIORITY_FLAG_MAP[p.strong and "strong" or p.medium and "medium"
        or p.normal and "normal" or p.area and "area" or p.health and "health"
        or p.mana and "mana"]
      if flag then bcConfig[flag] = true end
      if p.custom and p.name then
        bcConfig.customSpell = true
        bcConfig.customSpellName = p.name
      end
    end
  end
  return bcConfig
end

local friendHealerMacro  -- forward declaration (assigned below)

local function syncAllyBotCore()
  if not (BotCore and BotCore.FriendHealer) then return end
  if BotCore.FriendHealer.init then
    BotCore.FriendHealer.init(buildAllyBotCoreConfig())
  end
  if BotCore.FriendHealer.setEnabled then
    BotCore.FriendHealer.setEnabled(allyConfig.enabled)
  end
  if BotCore.FriendHealer.syncHealEngineSpells then
    BotCore.FriendHealer.syncHealEngineSpells()
  end
  if HealEngine and HealEngine.setFriendHealingEnabled then
    HealEngine.setFriendHealingEnabled(allyConfig.enabled)
  end
  if friendHealerMacro and friendHealerMacro.setOn then
    friendHealerMacro:setOn(allyConfig.enabled)
  end
end

-- Friend healing driver. The standalone FriendHealer window is retired; the
-- shell's friend_healer page drives the config through HealBot's domain API.
syncAllyBotCore()

  -- Sync HealEngine friend spells from config
  schedule(100, function()
    syncAllyBotCore()
    syncAllyBotCore()
    if HealEngine and HealEngine.setFriendSpells then
      local friendSpells = {}
      local healAt = getAllySettingValue(5, 80)
      local granSioAt = getAllySettingValue(6, 40)

      for i, action in ipairs(allyConfig.priorities or {}) do
        if action.enabled then
          if action.strong then
            table.insert(friendSpells, {
              name = "exura gran sio",
              hp = granSioAt,
              mpCost = 140,
              cd = 1100,
              prio = 1
            })
          end
          if action.medium then
            local tioSioAt = getAllySettingValue(7, 65)
            table.insert(friendSpells, {
              name = "exura tio sio",
              hp = tioSioAt,
              mpCost = 120,
              cd = 1100,
              prio = 2
            })
          end
          if action.normal then
            table.insert(friendSpells, {
              name = "exura sio",
              hp = healAt,
              mpCost = 100,
              cd = 1100,
              prio = 3
            })
          end
          if action.custom and action.name and action.name ~= "Custom Spell" then
            table.insert(friendSpells, {
              name = action.name,
              hp = healAt,
              mpCost = 50,
              cd = 1100,
              prio = 3
            })
          end
        end
      end

      if #friendSpells > 0 then
        HealEngine.setFriendSpells(friendSpells)
      end
    end
  end)

  -- Friend healing macro (delegates to BotCore.FriendHealer)
  friendHealerMacro = macro(100, function()
    if not allyConfig.enabled then return end
    if BotCore and BotCore.FriendHealer and BotCore.FriendHealer.tick then
      BotCore.FriendHealer.tick()
    end
  end)

  syncAllyBotCore()

-- Standalone FriendHealer window retired; kept as a safe no-op for legacy callers.
HealBot.showAlly = function()
  return false
end


local function friendSource()
  if allyConfig.conditions.party then return "party" end
  if allyConfig.conditions.guild then return "guild" end
  if allyConfig.conditions.friends then return "friends" end
  return "list"
end

HealBot.getFriendHealerProjection = function()
  local priorities = {}
  for index, action in ipairs(allyConfig.priorities or {}) do
    priorities[#priorities + 1] = {
      index = index, name = action.name, enabled = action.enabled == true,
      custom = action.custom == true, revision = index .. ":" .. tostring(action.enabled),
    }
  end
  local players = BotCore and BotCore.FriendHealer and BotCore.FriendHealer.getPlayerProjection
    and BotCore.FriendHealer.getPlayerProjection() or {}
  return {
    enabled = allyConfig.enabled == true,
    source = friendSource(),
    threshold = getAllySettingValue(5, 80),
    conditions = allyConfig.conditions or {},
    priorities = priorities,
    players = players,
  }
end

HealBot.getFriendCondition = function(key)
  return allyConfig.conditions and allyConfig.conditions[key] == true
end

HealBot.setFriendCondition = function(key, value)
  if not allyConfig.conditions or allyConfig.conditions[key] == nil then return false end
  allyConfig.conditions[key] = value == true
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    CharacterDB.set("friendHealer.conditions", allyConfig.conditions)
  end
  syncAllyBotCore()
  return true
end

HealBot.setFriendHealerEnabled = function(enabled)
  allyConfig.enabled = enabled == true
  syncAllyBotCore()
end

HealBot.setFriendSource = function(source)
  if source ~= "party" and source ~= "guild" and source ~= "friends" and source ~= "list" then return false end
  allyConfig.conditions.party = source == "party"
  allyConfig.conditions.guild = source == "guild"
  allyConfig.conditions.friends = source == "friends"
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    CharacterDB.set("friendHealer.conditions", allyConfig.conditions)
  end
  syncAllyBotCore()
  return true
end

HealBot.setFriendThreshold = function(value)
  value = tonumber(value)
  if not value or value < 1 or value > 100 then return false end
  allyConfig.settings[5].value = value
  syncAllyBotCore()
  return true
end

HealBot.toggleFriendPriority = function(index)
  local action = allyConfig.priorities and allyConfig.priorities[index]
  if not action then return false end
  action.enabled = not action.enabled
  syncAllyBotCore()
  return true
end

HealBot.moveFriendPriority = function(index, direction)
  local priorities = allyConfig.priorities or {}
  local destination = index + (direction == "up" and -1 or direction == "down" and 1 or 0)
  if not priorities[index] or destination < 1 or destination > #priorities or destination == index then return false end
  priorities[index], priorities[destination] = priorities[destination], priorities[index]
  syncAllyBotCore()
  return true
end
