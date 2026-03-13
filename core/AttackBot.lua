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

setDefaultTab("Main")
-- locales
local panelName = "AttackBot"
local currentSettings
local showItem = false
local category = 1
local patternCategory = 1
local pattern = 1
local mainWindow
local attackBotKeyboardBound = false
local attackEntryList

-- ============================================================================
-- BOTCORE INTEGRATION
-- ============================================================================

-- Local analytics wrapper (for fallback if BotCore not available)
local attackAnalytics = storage.attackAnalytics or {
  spells = {},
  runes = {},
  empowerments = 0,
  totalAttacks = 0,
  log = {}
}
storage.attackAnalytics = attackAnalytics

-- Record an attack action (delegates to BotCore.Analytics if available)
local function recordAttackAction(cat, idOrFormula)
  -- Use BotCore.Analytics if available
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.recordAttack(cat, idOrFormula)
    return
  end
  
  -- Fallback to local analytics
  attackAnalytics.totalAttacks = attackAnalytics.totalAttacks + 1
  
  if cat == 1 or cat == 4 or cat == 5 then
    local spellName = tostring(idOrFormula)
    attackAnalytics.spells[spellName] = (attackAnalytics.spells[spellName] or 0) + 1
    if cat == 4 then
      attackAnalytics.empowerments = attackAnalytics.empowerments + 1
    end
  elseif cat == 2 or cat == 3 then
    -- Use string key for runeId to prevent sparse array issues in JSON serialization
    local runeKey = tostring(tonumber(idOrFormula) or 0)
    attackAnalytics.runes[runeKey] = (attackAnalytics.runes[runeKey] or 0) + 1
  end
  
  local log = attackAnalytics.log
  log[#log + 1] = { t = now, cat = cat, action = tostring(idOrFormula) }
  TrimArray(log, 50)
end

-- Public API for SmartHunt (redirects to BotCore.Analytics if available)
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

-- label library

local categories = {
  "Targeted Spell (exori hur, exori flam, etc)",
  "Area Rune (avalanche, great fireball, etc)",
  "Targeted Rune (sudden death, icycle, etc)",
  "Empowerment (utito tempo, etc)",
  "Absolute Spell (exori, hells core, etc)",
}

local patterns = {
  -- targeted spells
  {
    "1 Sqm Range (exori ico)",
    "2 Sqm Range",
    "3 Sqm Range (strike spells)",
    "4 Sqm Range (exori san)",
    "5 Sqm Range (exori hur)",
    "6 Sqm Range",
    "7 Sqm Range (exori con)",
    "8 Sqm Range",
    "9 Sqm Range",
    "10 Sqm Range"
  },
  -- area runes
  {
    "Cross (explosion)",
    "Bomb (fire bomb)",
    "Ball (gfb, avalanche)"
  },
  -- empowerment/targeted rune
  {
    "1 Sqm Range",
    "2 Sqm Range",
    "3 Sqm Range",
    "4 Sqm Range",
    "5 Sqm Range",
    "6 Sqm Range",
    "7 Sqm Range",
    "8 Sqm Range",
    "9 Sqm Range",
    "10 Sqm Range",
  },
  -- absolute
  {
    "Adjacent (exori, exori gran)",
    "3x3 Wave (vis hur, tera hur)", 
    "Small Area (mas san, exori mas)",
    "Medium Area (mas flam, mas frigo)",
    "Large Area (mas vis, mas tera)",
    "Short Beam (vis lux)", 
    "Large Beam (gran vis lux)", 
    "Sweep (exori min)", -- 8
    "Small Wave (gran frigo hur)",
    "Big Wave (flam hur, frigo hur)",
    "Huge Wave (gran flam hur)",
  }
}

  -- spellPatterns[category][pattern][1 - normal, 2 - safe]
local spellPatterns = {
  {}, -- blank, wont be used
  -- Area Runes,
  { 
    {     -- cross
     [[ 
      010
      111
      010
     ]],
     -- cross SAFE
     [[
       01110
       01110
       11111
       11111
       11111
       01110
       01110
     ]]
    },
    { -- bomb
      [[
        111
        111
        111
      ]],
      -- bomb SAFE
      [[
        11111
        11111
        11111
        11111
        11111
      ]]
    },
    { -- ball
      [[
        0011100
        0111110
        1111111
        1111111
        1111111
        0111110
        0011100
      ]],
      -- ball SAFE
      [[
        000111000
        001111100
        011111110
        111111111
        111111111
        111111111
        011111110
        001111100
        000111000
      ]]
    },
  },
  {}, -- blank, wont be used
  -- Absolute
  {
    {-- adjacent
      [[
        111
        111
        111
      ]],
      -- adjacent SAFE
      [[
        11111
        11111
        11111
        11111
        11111
      ]]
    },
    { -- 3x3 Wave
      [[
        0000NNN0000
        0000NNN0000
        0000NNN0000
        00000N00000
        WWW00N00EEE
        WWWWW0EEEEE
        WWW00S00EEE
        00000S00000
        0000SSS0000
        0000SSS0000
        0000SSS0000
      ]],
      -- 3x3 Wave SAFE
      [[
        0000NNNNN0000
        0000NNNNN0000
        0000NNNNN0000
        0000NNNNN0000
        WWWW0NNN0EEEE
        WWWWWNNNEEEEE
        WWWWWW0EEEEEE
        WWWWWSSSEEEEE
        WWWW0SSS0EEEE
        0000SSSSS0000
        0000SSSSS0000
        0000SSSSS0000
        0000SSSSS0000
      ]]
    },
    { -- small area
      [[
        0011100
        0111110
        1111111
        1111111
        1111111
        0111110
        0011100
      ]],
      -- small area SAFE
      [[
        000111000
        001111100
        011111110
        111111111
        111111111
        111111111
        011111110
        001111100
        000111000
      ]]
    },
    { -- medium area
      [[
        00000100000
        00011111000
        00111111100
        01111111110
        01111111110
        11111111111
        01111111110
        01111111110
        00111111100
        00001110000
        00000100000
      ]],
      -- medium area SAFE
      [[
        0000011100000
        0000111110000
        0001111111000
        0011111111100
        0111111111110
        0111111111110
        1111111111111
        0111111111110
        0111111111110
        0011111111100
        0001111111000
        0000111110000
        0000011100000
      ]]
    },
    { -- large area
      [[
        0000001000000
        0000011100000
        0000111110000
        0001111111000
        0011111111100
        0111111111110
        1111111111111
        0111111111110
        0011111111100
        0001111111000
        0000111110000
        0000011100000
        0000001000000
      ]],
      -- large area SAFE
      [[
        000000010000000
        000000111000000
        000001111100000
        000011111110000
        000111111111000
        001111111111100
        011111111111110
        111111111111111
        011111111111110
        001111111111100
        000111111111000
        000011111110000
        000001111100000
        000000111000000
        000000010000000
      ]]
    },
    { -- short beam
      [[
        00000N00000
        00000N00000
        00000N00000
        00000N00000
        00000N00000
        WWWWW0EEEEE
        00000S00000
        00000S00000
        00000S00000
        00000S00000
        00000S00000
      ]],
      -- short beam SAFE
      [[
        00000NNN00000
        00000NNN00000
        00000NNN00000
        00000NNN00000
        00000NNN00000
        WWWWWNNNEEEEE
        WWWWWW0EEEEEE
        00000SSS00000
        00000SSS00000
        00000SSS00000
        00000SSS00000
        00000SSS00000
        00000SSS00000
      ]]
    },
    { -- large beam
      [[
        0000000N0000000
        0000000N0000000
        0000000N0000000
        0000000N0000000
        0000000N0000000
        0000000N0000000
        0000000N0000000
        WWWWWWW0EEEEEEE
        0000000S0000000
        0000000S0000000
        0000000S0000000
        0000000S0000000
        0000000S0000000
        0000000S0000000
        0000000S0000000
      ]],
      -- large beam SAFE
      [[
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        WWWWWWWNNNEEEEEEE
        WWWWWWWW0EEEEEEEE
        WWWWWWWSSSEEEEEEE
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
      ]],
    },
    {}, -- sweep, wont be used
    { -- small wave
      [[
        00NNN00
        00NNN00
        WW0N0EE
        WWW0EEE
        WW0S0EE
        00SSS00
        00SSS00
      ]],
      -- small wave SAFE
      [[
        00NNNNN00
        00NNNNN00
        WWNNNNNEE
        WWWWNEEEE
        WWWW0EEEE
        WWWWSEEEE
        WWSSSSSEE
        00SSSSS00
        00SSSSS00
      ]]
    },
    { -- large wave
      [[
        000NNNNN000
        000NNNNN000
        0000NNN0000
        WW00NNN00EE
        WWWW0N0EEEE
        WWWWW0EEEEE
        WWWW0S0EEEE
        WW00SSS00EE
        0000SSS0000
        000SSSSS000
        000SSSSS000
      ]],
      [[
        000NNNNNNN000
        000NNNNNNN000
        000NNNNNNN000
        WWWWNNNNNEEEE
        WWWWNNNNNEEEE
        WWWWWNNNEEEEE
        WWWWWW0EEEEEE
        WWWWWSSSEEEEE
        WWWWSSSSSEEEE
        WWWWSSSSSEEEE
        000SSSSSSS000
        000SSSSSSS000
        000SSSSSSS000
      ]]
    },
    { -- huge wave
      [[
        0000NNNNN0000
        0000NNNNN0000
        00000NNN00000
        00000NNN00000
        WW0000N0000EE
        WWWW00N00EEEE
        WWWWWW0EEEEEE
        WWWW00S00EEEE
        WW0000S0000EE
        00000SSS00000
        00000SSS00000
        0000SSSSS0000
        0000SSSSS0000
      ]],
      [[
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        WWWWWWWNNNEEEEEEE
        WWWWWWWW0EEEEEEEE
        WWWWWWWSSSEEEEEEE
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
      ]]
    }
  }
}

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

-- AttackBotConfig
-- create blank profiles 
if not AttackBotConfig[panelName] or not AttackBotConfig[panelName][1] or #AttackBotConfig[panelName] ~= 5 then
  AttackBotConfig[panelName] = {
    [1] = {
      enabled = true,  -- Enable by default so user doesn't have to manually toggle
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #1",
      Cooldown = true,
      Visible = true,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
    [2] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #2",
      Cooldown = true,
      Visible = true,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
    [3] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #3",
      Cooldown = true,
      Visible = true,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
    [4] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #4",
      Cooldown = true,
      Visible = true,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
    [5] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #5",
      Cooldown = true,
      Visible = true,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
  }
end

-- Load character-specific profile if available
local charProfile = getCharacterProfile("attackProfile")
if charProfile and charProfile >= 1 and charProfile <= 5 then
  AttackBotConfig.currentBotProfile = charProfile
elseif not AttackBotConfig.currentBotProfile or AttackBotConfig.currentBotProfile == 0 or AttackBotConfig.currentBotProfile > 5 then 
  AttackBotConfig.currentBotProfile = 1
end

-- create panel UI
ui = UI.createWidget("AttackBotBotPanel")
if not ui then
  warn("[AttackBot] Failed to create UI widget AttackBotBotPanel")
  return
end

-- finding correct table, manual unfortunately
local setActiveProfile = function()
  local n = AttackBotConfig.currentBotProfile
  currentSettings = AttackBotConfig[panelName][n]
  -- Save character's profile preference
  setCharacterProfile("attackProfile", n)
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

local setProfileName = function()
  if ui.name then
    ui.name:setText(currentSettings.name)
  end
end

-- small UI elements
if ui.title then
  ui.title.onClick = function(widget)
    currentSettings.enabled = not currentSettings.enabled
    widget:setOn(currentSettings.enabled)
    nExBotConfigSave("atk")
  end
end
  
if ui.setup then
  ui.setup.onClick = function(widget)
    mainWindow:show()
    mainWindow:raise()
    mainWindow:focus()
  end
end

  mainWindow = UI.createWindow("AttackBotWindow")
  if not mainWindow then
    warn("[AttackBot] Failed to create main window AttackBotWindow")
    return
  end
  mainWindow:hide()

  local panel = mainWindow.mainPanel
  local function rw(id)
    return mainWindow:recursiveGetChildById(id)
  end

  local uiFormPane = rw("formPane")
  local uiEntryList = rw("entryList")
  local uiUp = rw("up")
  local uiDown = rw("down")
  local uiMonsters = rw("monsters")
  local uiSpellName = rw("spellName")
  local uiItemId = rw("itemId")
  local uiCategory = rw("category")
  local uiRange = rw("range")
  local uiSelectorHint = rw("selectorHint")
  local uiPreviousCategory = rw("previousCategory")
  local uiNextCategory = rw("nextCategory")
  local uiPreviousSource = rw("previousSource")
  local uiNextSource = rw("nextSource")
  local uiPreviousRange = rw("previousRange")
  local uiNextRange = rw("nextRange")
  local uiManaPercent = rw("manaPercent")
  local uiCreatures = rw("creatures")
  local uiMinHp = rw("minHp")
  local uiMaxHp = rw("maxHp")
  local uiCooldown = rw("cooldown")
  local uiOrMore = rw("orMore")
  local uiAddEntry = rw("addEntry")

  if not uiEntryList or not uiMonsters or not uiSpellName or not uiItemId then
    warn("[AttackBot] Failed to bind AttackBotWindow controls")
    return
  end
  attackEntryList = uiEntryList

  mainWindow.onVisibilityChange = function(widget, visible)
    if not visible then
      currentSettings.attackTable = {}
      for i, child in ipairs(uiEntryList:getChildren()) do
        table.insert(currentSettings.attackTable, child.params)
      end
      nExBotConfigSave("atk")
    end
  end

  -- main panel

    local selectorHints = {
      [1] = "Spell mode: type spell name, then press Enter to add.",
      [2] = "Rune mode: drag a rune into the item slot, then press Enter.",
      [3] = "Rune mode: drag a rune into the item slot, then press Enter.",
      [4] = "Empowered spell: set conditions and add to queue.",
      [5] = "Directional spell: choose pattern/range and add."
    }

    local function focusPrimaryInput()
      if showItem then
        return
      end
      if uiSpellName and uiSpellName:isVisible() then
        uiSpellName:focus()
      end
    end

    local function updateMonstersWidth()
      local baseWidth = (uiFormPane and uiFormPane:getWidth()) or (panel:getWidth() or 500)
      local reserved = showItem and 90 or 200
      uiMonsters:setWidth(math.max(170, baseWidth - reserved))
    end

    function toggleItem()
      updateMonstersWidth()
      uiItemId:setVisible(showItem)
      uiSpellName:setVisible(not showItem)
    end
    toggleItem()

    panel.onGeometryChange = function()
      updateMonstersWidth()
    end

    function setCategoryText()
      uiCategory.description:setText(categories[category])
      if uiSelectorHint then
        uiSelectorHint:setText(selectorHints[category] or selectorHints[1])
      end
    end
    setCategoryText()

    function setPatternText()
      uiRange.description:setText(patterns[patternCategory][pattern])
    end
    setPatternText()

    -- in/de/crementation buttons
    uiPreviousCategory.onClick = function()
      if category == 1 then
        category = #categories
      else
        category = category - 1
      end

      showItem = (category == 2 or category == 3) and true or false
      patternCategory = category == 4 and 3 or category == 5 and 4 or category
      pattern = 1
      toggleItem()
      setPatternText()
      setCategoryText()
      focusPrimaryInput()
    end
    uiNextCategory.onClick = function()
      if category == #categories then
        category = 1 
      else
        category = category + 1
      end

      showItem = (category == 2 or category == 3) and true or false
      patternCategory = category == 4 and 3 or category == 5 and 4 or category
      pattern = 1
      toggleItem()
      setPatternText()
      setCategoryText()
      focusPrimaryInput()
    end
    uiPreviousSource.onClick = function()
      warn("[AttackBot] TODO, reserved for future use.")
    end
    uiNextSource.onClick = function()
      warn("[AttackBot] TODO, reserved for future use.")
    end
    uiPreviousRange.onClick = function()
      local t = patterns[patternCategory]
      if pattern == 1 then
        pattern = #t 
      else
        pattern = pattern - 1
      end
      setPatternText()
    end
    uiNextRange.onClick = function()
      local t = patterns[patternCategory]
      if pattern == #t then
        pattern = 1 
      else
        pattern = pattern + 1
      end
      setPatternText()
    end
    -- eo in/de/crementation

  ------- [[core table function]] -------
    function setupWidget(widget)
      local params = widget.params

      widget:setText(params.description)
      if params.itemId > 0 then
        if widget.spell then
          widget.spell:setVisible(false)
        end
        if widget.id then
          widget.id:setVisible(true)
          widget.id:setItemId(params.itemId)
        end
      else
        if widget.id then
          widget.id:setVisible(false)
        end
        if widget.spell then
          widget.spell:setVisible(true)
        end
      end
      widget:setTooltip(params.tooltip)
      widget.remove.onClick = function()
        uiUp:setEnabled(false)
        uiDown:setEnabled(false)
        widget:destroy()
      end
      widget.enabled:setChecked(params.enabled)
      widget.enabled.onClick = function()
        params.enabled = not params.enabled
        widget.enabled:setChecked(params.enabled)
      end
      -- will serve as edit
      widget.onDoubleClick = function(widget)
        uiManaPercent:setValue(params.mana)
        uiCreatures:setValue(params.count)
        uiMinHp:setValue(params.minHp)
        uiMaxHp:setValue(params.maxHp)
        uiCooldown:setValue(params.cooldown)
        showItem = params.itemId > 100 and true or false
        uiItemId:setItemId(params.itemId)
        uiSpellName:setText(params.spell or "")
        uiOrMore:setChecked(params.orMore)
        toggleItem()
        category = params.category
        patternCategory = params.patternCategory
        pattern = params.pattern
        setPatternText()
        setCategoryText()
        widget:destroy()
      end
      widget.onClick = function(widget)
        if #uiEntryList:getChildren() == 1 then
          uiUp:setEnabled(false)
          uiDown:setEnabled(false)
        elseif uiEntryList:getChildIndex(widget) == 1 then
          uiUp:setEnabled(false)
          uiDown:setEnabled(true)
        elseif uiEntryList:getChildIndex(widget) == uiEntryList:getChildCount() then
          uiUp:setEnabled(true)
          uiDown:setEnabled(false)
        else
          uiUp:setEnabled(true)
          uiDown:setEnabled(true)
        end
      end
    end


    -- refreshing values
    function refreshAttacks()
      if not currentSettings.attackTable then return end

      uiEntryList:destroyChildren()
      for i, entry in pairs(currentSettings.attackTable) do
        local label = UI.createWidget("AttackEntry", uiEntryList)
        label.params = entry
        setupWidget(label)
      end
    end
    refreshAttacks()
    uiUp:setEnabled(false)
    uiDown:setEnabled(false)

    -- adding values
    uiAddEntry.onClick = function(wdiget)
      -- first variables
      local creatures = uiMonsters:getText():lower()
      local monsters = (creatures:len() == 0 or creatures == "*" or creatures == "monster names") and true or string.split(creatures, ",")
      local mana = uiManaPercent:getValue()
      local count = uiCreatures:getValue()
      local minHp = uiMinHp:getValue()
      local maxHp = uiMaxHp:getValue()
      local cooldown = uiCooldown:getValue()
      local itemId = uiItemId:getItemId()
      local spell = uiSpellName:getText()
      local tooltip = monsters ~= true and creatures
      local orMore = uiOrMore:isChecked()

      -- validation
      if showItem and itemId < 100 then
        return warn("[AttackBot]: please fill item ID!")
      elseif not showItem and (spell:lower() == "spell name" or spell:len() == 0) then
        return warn("[AttackBot]: please fill spell name!")
      end

      local regex = patternCategory ~= 1 and [[^[^\(]+]] or [[^[^R]+]]
      local matchResult = SafeCall.regexMatch(patterns[patternCategory][pattern], regex)
      local type = matchResult and matchResult[1] and matchResult[1][1]:trim() or ""
      regex = [[^[^ ]+]]
      local categoryMatch = SafeCall.regexMatch(categories[category], regex)
      local categoryName = categoryMatch and categoryMatch[1] and categoryMatch[1][1]:trim():lower() or ""
      local specificMonsters = monsters == true and "Any Creatures" or "Creatures"
      local attackType = showItem and "rune "..itemId or spell

      local countDescription = orMore and count.."+" or count

      local params = {
        creatures = creatures,
        monsters = monsters,
        mana = mana,
        count = count,
        minHp = minHp,
        maxHp = maxHp,
        cooldown = cooldown,
        itemId = itemId,
        spell = showItem and nil or spell,
        enabled = true,
        category = category,
        patternCategory = patternCategory,
        pattern = pattern,
        tooltip = tooltip,
        orMore = orMore,
        description = '['..type..'] '..countDescription.. ' '..specificMonsters..': '..attackType..', '..categoryName..' ('..minHp..'%-'..maxHp..'%)'
      }

      local label = UI.createWidget("AttackEntry", uiEntryList)
      label.params = params
      setupWidget(label)
      resetFields()
    end

    -- moving values
    -- up
    uiUp.onClick = function(widget)
      local focused = uiEntryList:getFocusedChild()
      local n = uiEntryList:getChildIndex(focused)

      if n-1 == 1 then
        widget:setEnabled(false)
      end
      uiDown:setEnabled(true)
      uiEntryList:moveChildToIndex(focused, n-1)
      uiEntryList:ensureChildVisible(focused)
    end
    -- down
    uiDown.onClick = function(widget)
      local focused = uiEntryList:getFocusedChild()
      local n = uiEntryList:getChildIndex(focused)

      if n + 1 == uiEntryList:getChildCount() then
        widget:setEnabled(false)
      end
      uiUp:setEnabled(true)
      uiEntryList:moveChildToIndex(focused, n+1)
      uiEntryList:ensureChildVisible(focused)
    end

   -- window elements
  mainWindow.closeButton.onClick = function()
    resetFields()
    mainWindow:hide()
  end

  if not attackBotKeyboardBound then
    attackBotKeyboardBound = true
    onKeyPress(function(keys)
      if not mainWindow or not mainWindow:isVisible() then
        return
      end

      if keys == "Escape" then
        resetFields()
        focusPrimaryInput()
        return
      end

      if keys == "Enter" then
        if uiAddEntry and uiAddEntry.onClick then
          uiAddEntry.onClick(uiAddEntry)
        end
      end
    end)
  end

  -- core functions
  function resetFields()
    showItem = false
    toggleItem()
    pattern = 1
    patternCategory = 1
    category = 1
    setPatternText()
    setCategoryText()
    uiManaPercent:setText(1)
    uiCreatures:setText(1)
    uiMinHp:setValue(0)
    uiMaxHp:setValue(100)
    uiCooldown:setText(1)
    uiMonsters:setText("monster names")
    uiItemId:setItemId(0)
    uiSpellName:setText("spell name")
    uiOrMore:setChecked(false)
    focusPrimaryInput()
  end
  resetFields()

  function loadSettings()
    -- BOT panel
    ui.title:setOn(currentSettings.enabled)
    setProfileName()
    -- main panel
    refreshAttacks()
  end
  loadSettings()

  local activeProfileColor = function()
    for i=1,5 do
      if i == AttackBotConfig.currentBotProfile then
        ui[i]:setColor("green")
      else
        ui[i]:setColor("white")
      end
    end
  end
  activeProfileColor()

  local profileChange = function()
    setActiveProfile()
    activeProfileColor()
    loadSettings()
    resetFields()
    nExBotConfigSave("atk")
  end

  for i=1,5 do
    local button = ui[i]
      button.onClick = function()
      AttackBotConfig.currentBotProfile = i
      profileChange()
    end
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
      mainWindow:show()
      mainWindow:raise()
      mainWindow:focus()
    end

-- ============================================================================
-- COOLDOWN MANAGEMENT (use ClientHelper for DRY)
-- ============================================================================

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
  local spellKey = getSpellKey(entry)
  if spellKey == "" then return false end

  -- For Absolute Sweep (category 5, pattern 8) respect rotation setting
  if entry.category == 5 and entry.pattern == 8 and context and context._attackCache and context._attackCache.bestSweepDir and context.settings and context.settings.Rotate then
    local desired = context._attackCache.bestSweepDir
    if player:getDirection() ~= desired then
      -- Prevent rapid oscillation by enforcing a small cooldown
      if now - lastAutoRotate < rotationCooldown then
        return true
      end

      -- Rotation attempt window and throttling (avoid starvation)
      local cache = context._attackCache
      if cache then
        if cache.rotationAttemptsDir ~= desired then
          cache.rotationAttemptsDir = desired
          cache.rotationAttempts = 0
          cache.rotationAttemptsStart = now
        else
          if cache.rotationAttemptsStart and now - cache.rotationAttemptsStart > 3000 then
            cache.rotationAttempts = 0
            cache.rotationAttemptsStart = now
          end
        end

        local MAX_ROTATE_ATTEMPTS = 3
        if (cache.rotationAttempts or 0) >= MAX_ROTATE_ATTEMPTS then
          -- allow attack to proceed without rotating
        else
          -- Rotate towards best side and defer attack to next tick
          turn(desired)
          lastAutoRotate = now
          cache.rotationAttempts = (cache.rotationAttempts or 0) + 1
          return true
        end
      else
        -- No cache available: rotate normally
        turn(desired)
        lastAutoRotate = now
        return true
      end
    end
  end

  local state = getSpellState(spellKey)
  local cdMs = toCooldownMs(entry.cooldown)

  if context.settings.Cooldown and state and nowMs() < state.nextReadyAt then
    return false
  end

  local canCastCaller = SafeCall.getCachedCaller("canCast")
  if canCastCaller then
    local ok = canCastCaller(spellKey, not currentSettings.ignoreMana, not currentSettings.Cooldown)
    if ok == false then return false end
  end

  local beforeTs = SpellCastTable and SpellCastTable[spellKey] and SpellCastTable[spellKey].t or 0
  if state then state.lastAttemptAt = nowMs() end

  cast(spellKey, math.max(cdMs, 100))

  confirmSpellCast(spellKey, beforeTs, function()
    if state then
      state.nextReadyAt = nowMs() + cdMs
    end
    applyGlobalBackoff(GLOBAL_CAST_BACKOFF)
    recordAttackAction(entry.category, entry.spell)
  end, function()
    if context.settings.Cooldown and state then
      state.nextReadyAt = math.max(state.nextReadyAt or 0, nowMs() + FAILED_CAST_BACKOFF)
    end
    applyGlobalBackoff(FAILED_CAST_BACKOFF)
  end)

  return true
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
  lastAttackTime = now -- Update attack time for non-blocking cooldown
  local Client = getClient()
  
  -- Simplified like vBot for better OTCv8 compatibility
  if useWith and targetCreatureOrTile then
    local ok, res = pcall(useWith, runeId, targetCreatureOrTile)
    if ok then return true end
  end
  
  -- Fallback methods
  if BotCore and BotCore.Items and BotCore.Items.useOn then
    local ok, res = pcall(BotCore.Items.useOn, runeId, targetCreatureOrTile)
    if ok and res then return true end
  end
  
  -- Use ClientService if available
  if Client and Client.useInventoryItemWith then
    local ok, res = pcall(Client.useInventoryItemWith, runeId, targetCreatureOrTile)
    if ok then return true end
  elseif g_game and g_game.useInventoryItemWith then
    local ok, res = pcall(g_game.useInventoryItemWith, runeId, targetCreatureOrTile)
    if ok then return true end
  end
  
  local rune = SafeCall.findItem(runeId)
  if rune then
    if Client and Client.useWith then
      local ok, res = pcall(Client.useWith, rune, targetCreatureOrTile)
      if ok then return true end
    elseif g_game and g_game.useWith then
      local ok, res = pcall(g_game.useWith, rune, targetCreatureOrTile)
      if ok then return true end
    end
  end
  
  return false
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

-- ============================================================================
-- SIMPLIFIED ATTACKBOT - HIGH PERFORMANCE & ACCURACY
-- ============================================================================

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
  -- Categories 1 (targeted spell), 4 (empowerment), 5 (absolute) are spell-based
  if isSpellCategory(entry.category) then
    return attemptSpellCast(entry, context)
  end

  local stampKey = entry.key or tostring(entry.itemId or entry.spell)
  local actionId = entry.itemId > 100 and entry.itemId or entry.spell

  if entry.category == 3 then
    -- Targeted runes
    local okTargeted = useRuneOnTarget(entry.itemId, context.target)
    if okTargeted then
      stamp(stampKey)
      recordAttackAction(entry.category, actionId)
      if context and context._attackCache then context._attackCache.rotationAttempts = 0 end
      return true
    end
    return false
  elseif entry.category == 2 then
    -- Area runes - prefer cached best tile when available
    local pat = spellPatterns[entry.patternCategory][entry.pattern][context.settings.PvpSafe and 2 or 1]
    local pKey = buildPatternKey(entry, context.settings.PvpSafe)
    local data = context and context._attackCache and context._attackCache.bestTileByPattern and context._attackCache.bestTileByPattern[pKey]
    if not data then
      data = getBestTileByPattern(pat, entry.minHp, entry.maxHp, context.settings.PvpSafe, entry.monsters)
    end
    if data and data.pos then
      local Client = getClient()
      local tile = (Client and Client.getTile) and Client.getTile(data.pos) or (g_map and g_map.getTile(data.pos))
      if tile then
        local okArea = useRuneOnTarget(entry.itemId, tile:getTopUseThing())
        if okArea then
          stamp(stampKey)
          recordAttackAction(entry.category, actionId)
          if context and context._attackCache then context._attackCache.rotationAttempts = 0 end
          return true
        end
      end
    end
    return false
  end

  return true
end

-- Main attack function — AAA pattern (Arrange → Act → Assert)
function attackBotMain()
  -- ========== ARRANGE: Gather world state and pre-check context ==========

  -- Global guards (cannot attack at all)
  if not currentSettings or not currentSettings.enabled then return end
  if not attackEntryList then return end
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
  local entries = attackEntryList:getChildren()

  -- ========== ACT: Find highest-priority valid entry and execute ==========

  for _, child in ipairs(entries) do
    local entry = child.params
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
