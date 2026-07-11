# God File Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract pure functions from HealBot.lua and AttackBot.lua into testable modules

**Architecture:** Extract pure data tables, conversion functions, and analytics into new modules. Originals call new modules via `require()`. Config functions take config table as parameter.

**Tech Stack:** Lua 5.1, busted (testing), luacheck (linting)

## Global Constraints

- Lua 5.1/LuaJIT 2.1 target
- OTClient/OpenTibiaBR runtime (g_game, g_map, g_things globals)
- 2-space indentation
- No new dependencies
- All 128 existing tests must pass after each task

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `core/attack/attack_data.lua` | Pure data: categories, patterns, spellShapes |
| `core/attack/attack_analytics.lua` | Analytics recording (spell/rune/empowerment counts) |
| `core/attack/attack_config.lua` | Profile config management (load/save/reset) |
| `core/heal/spell_resolver.lua` | Spell/potion format conversion functions |
| `core/heal/heal_analytics.lua` | Analytics reset and reporting |
| `tests/unit/domain/attack_data_spec.lua` | Tests for attack data |
| `tests/unit/domain/attack_analytics_spec.lua` | Tests for attack analytics |
| `tests/unit/domain/attack_config_spec.lua` | Tests for attack config |
| `tests/unit/domain/spell_resolver_spec.lua` | Tests for spell resolver |
| `tests/unit/domain/heal_analytics_spec.lua` | Tests for heal analytics |

### Modified Files

| File | Changes |
|------|---------|
| `core/AttackBot.lua` | Replace inline data/analytics/config with require calls |
| `core/HealBot.lua` | Replace inline conversion functions with require calls |
| `README.md` | Update architecture section |
| `docs/ARCHITECTURE.md` | Add extraction pattern |
| `docs/HEALBOT.md` | Reference spell_resolver |
| `docs/ATTACKBOT.md` | Reference attack_data |

---

## Task 1: Extract attack_data.lua (pure data)

**Files:**
- Create: `core/attack/attack_data.lua`
- Create: `tests/unit/domain/attack_data_spec.lua`
- Modify: `core/AttackBot.lua:85-504` (replace inline data)

**Interfaces:**
- Produces: `categories` (table), `patterns` (table), `spellShapes` (table)

- [ ] **Step 1: Write the failing test**

```lua
-- tests/unit/domain/attack_data_spec.lua
local attack_data = require("core.attack.attack_data")

describe("attack_data", function()
  describe("categories", function()
    it("has 5 categories", function()
      assert.equals(5, #attack_data.categories)
    end)

    it("category 1 is Targeted Spell", function()
      assert.truthy(attack_data.categories[1]:find("Targeted Spell"))
    end)

    it("category 2 is Area Rune", function()
      assert.truthy(attack_data.categories[2]:find("Area Rune"))
    end)
  end)

  describe("patterns", function()
    it("has 4 pattern groups", function()
      assert.equals(4, #attack_data.patterns)
    end)

    it("targeted spells has 10 range patterns", function()
      assert.equals(10, #attack_data.patterns[1])
    end)

    it("area runes has 3 patterns", function()
      assert.equals(3, #attack_data.patterns[2])
    end)

    it("absolute has 11 patterns", function()
      assert.equals(11, #attack_data.patterns[4])
    end)
  end)

  describe("spellShapes", function()
    it("has shape data for area runes", function()
      assert.is_table(attack_data.spellShapes[2])
    end)

    it("cross pattern has normal and safe variants", function()
      local cross = attack_data.spellShapes[2][1]
      assert.equals(2, #cross)
      assert.truthy(cross[1]:find("010"))
      assert.truthy(cross[2]:find("01110"))
    end)

    it("bomb pattern has normal and safe variants", function()
      local bomb = attack_data.spellShapes[2][2]
      assert.equals(2, #bomb)
      assert.truthy(bomb[1]:find("111"))
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/attack_data_spec.lua`
Expected: FAIL with "module 'core.attack.attack_data' not found"

- [ ] **Step 3: Write minimal implementation**

```lua
-- core/attack/attack_data.lua
local M = {}

M.categories = {
  "Targeted Spell (exori hur, exori flam, etc)",
  "Area Rune (avalanche, great fireball, etc)",
  "Targeted Rune (sudden death, icycle, etc)",
  "Empowerment (utito tempo, etc)",
  "Absolute Spell (exori, hells core, etc)",
}

M.patterns = {
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
    "Sweep (exori min)",
    "Small Wave (gran frigo hur)",
    "Big Wave (flam hur, frigo hur)",
    "Huge Wave (gran flam hur)",
  }
}

-- spellShapes[category][pattern][1 - normal, 2 - safe]
M.spellShapes = {
  {}, -- blank, wont be used
  -- Area Runes
  {
    { -- cross
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
    { -- adjacent
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
      ]]
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

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/attack_data_spec.lua`
Expected: PASS

- [ ] **Step 5: Update AttackBot.lua to use new module**

In `core/AttackBot.lua`, replace lines 85-504 with:

```lua
local attack_data = require("core.attack.attack_data")
local categories = attack_data.categories
local patterns = attack_data.patterns
local spellPatterns = attack_data.spellShapes
```

- [ ] **Step 6: Run all existing tests**

Run: `eval "$(luarocks path)" && busted tests/`
Expected: 128+ tests pass

- [ ] **Step 7: Commit**

```bash
git add core/attack/attack_data.lua tests/unit/domain/attack_data_spec.lua core/AttackBot.lua
git commit -m "refactor: extract attack_data.lua with pure data tables"
```

---

## Task 2: Extract attack_analytics.lua

**Files:**
- Create: `core/attack/attack_analytics.lua`
- Create: `tests/unit/domain/attack_analytics_spec.lua`
- Modify: `core/AttackBot.lua:25-83`

**Interfaces:**
- Produces: `recordSpellUse(name)`, `recordRuneUse(name)`, `recordBuffUse(name)`, `getAnalytics()`, `resetAnalytics()`

- [ ] **Step 1: Write the failing test**

```lua
-- tests/unit/domain/attack_analytics_spec.lua
local attack_analytics = require("core.attack.attack_analytics")

describe("attack_analytics", function()
  before_each(function()
    attack_analytics.resetAnalytics()
  end)

  it("starts with zero counts", function()
    local stats = attack_analytics.getAnalytics()
    assert.equals(0, stats.totalAttacks)
    assert.equals(0, stats.empowerments)
  end)

  it("records spell use", function()
    attack_analytics.recordSpellUse("exori gran")
    local stats = attack_analytics.getAnalytics()
    assert.equals(1, stats.totalAttacks)
    assert.equals(1, stats.spells["exori gran"])
  end)

  it("records multiple spell uses", function()
    attack_analytics.recordSpellUse("exori gran")
    attack_analytics.recordSpellUse("exori gran")
    attack_analytics.recordSpellUse("exori vis")
    local stats = attack_analytics.getAnalytics()
    assert.equals(3, stats.totalAttacks)
    assert.equals(2, stats.spells["exori gran"])
    assert.equals(1, stats.spells["exori vis"])
  end)

  it("records rune use", function()
    attack_analytics.recordRuneUse("3161")
    local stats = attack_analytics.getAnalytics()
    assert.equals(1, stats.totalAttacks)
    assert.equals(1, stats.runes["3161"])
  end)

  it("records buff use", function()
    attack_analytics.recordBuffUse("utito tempo")
    local stats = attack_analytics.getAnalytics()
    assert.equals(1, stats.totalAttacks)
    assert.equals(1, stats.empowerments)
  end)

  it("resets analytics", function()
    attack_analytics.recordSpellUse("exori gran")
    attack_analytics.recordRuneUse("3161")
    attack_analytics.resetAnalytics()
    local stats = attack_analytics.getAnalytics()
    assert.equals(0, stats.totalAttacks)
    assert.equals(0, stats.empowerments)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/attack_analytics_spec.lua`
Expected: FAIL with "module 'core.attack.attack_analytics' not found"

- [ ] **Step 3: Write minimal implementation**

```lua
-- core/attack/attack_analytics.lua
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

function M.recordBuffUse(name)
  analytics.totalAttacks = analytics.totalAttacks + 1
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

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/attack_analytics_spec.lua`
Expected: PASS

- [ ] **Step 5: Update AttackBot.lua to use new module**

In `core/AttackBot.lua`, replace lines 25-83 with:

```lua
local attack_analytics = require("core.attack.attack_analytics")

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
```

- [ ] **Step 6: Run all existing tests**

Run: `eval "$(luarocks path)" && busted tests/`
Expected: 128+ tests pass

- [ ] **Step 7: Commit**

```bash
git add core/attack/attack_analytics.lua tests/unit/domain/attack_analytics_spec.lua core/AttackBot.lua
git commit -m "refactor: extract attack_analytics.lua with pure recording functions"
```

---

## Task 3: Extract spell_resolver.lua

**Files:**
- Create: `core/heal/spell_resolver.lua`
- Create: `tests/unit/domain/spell_resolver_spec.lua`
- Modify: `core/HealBot.lua:73-181`

**Interfaces:**
- Produces: `convertSpellsToEngineFormat(spellTable)`, `convertPotionsToEngineFormat(itemTable, getitemName)`

- [ ] **Step 1: Write the failing test**

```lua
-- tests/unit/domain/spell_resolver_spec.lua
local spell_resolver = require("core.heal.spell_resolver")

describe("spell_resolver", function()
  describe("convertSpellsToEngineFormat", function()
    it("returns empty table for nil input", function()
      local result = spell_resolver.convertSpellsToEngineFormat(nil)
      assert.equals(0, #result)
    end)

    it("returns empty table for empty input", function()
      local result = spell_resolver.convertSpellsToEngineFormat({})
      assert.equals(0, #result)
    end)

    it("converts valid HP spell", function()
      local spells = {
        { enabled = true, spell = "exura vita", origin = "HP", value = 50, sign = "<", cost = 60 }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(1, #result)
      assert.equals("exura vita", result[1].name)
      assert.equals(50, result[1].hp)
      assert.equals(60, result[1].mana)
    end)

    it("converts valid MP spell", function()
      local spells = {
        { enabled = true, spell = "exura gran", origin = "MP", value = 40, sign = "<", cost = 100 }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(1, #result)
      assert.equals(40, result[1].mp)
    end)

    it("skips disabled spells", function()
      local spells = {
        { enabled = false, spell = "exura vita", origin = "HP", value = 50 }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(0, #result)
    end)

    it("skips spells without name", function()
      local spells = {
        { enabled = true, spell = "", origin = "HP", value = 50 }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(0, #result)
    end)

    it("skips spells with unknown origin", function()
      local spells = {
        { enabled = true, spell = "exura vita", origin = "UNKNOWN", value = 50 }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(0, #result)
    end)

    it("skips HP spells with above sign", function()
      local spells = {
        { enabled = true, spell = "exura vita", origin = "HP", value = 50, sign = ">" }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(0, #result)
    end)

    it("assigns priority based on order", function()
      local spells = {
        { enabled = true, spell = "exura", origin = "HP", value = 70 },
        { enabled = true, spell = "exura vita", origin = "HP", value = 50 },
        { enabled = true, spell = "exura gran", origin = "HP", value = 20 }
      }
      local result = spell_resolver.convertSpellsToEngineFormat(spells)
      assert.equals(1, result[1].prio)
      assert.equals(2, result[2].prio)
      assert.equals(3, result[3].prio)
    end)
  end)

  describe("convertPotionsToEngineFormat", function()
    it("returns empty table for nil input", function()
      local result = spell_resolver.convertPotionsToEngineFormat(nil)
      assert.equals(0, #result)
    end)

    it("converts valid HP potion", function()
      local potions = {
        { enabled = true, item = 3160, origin = "HP", value = 40, sign = "<" }
      }
      local result = spell_resolver.convertPotionsToEngineFormat(potions)
      assert.equals(1, #result)
      assert.equals(3160, result[1].id)
      assert.equals(40, result[1].hp)
    end)

    it("skips disabled potions", function()
      local potions = {
        { enabled = false, item = 3160, origin = "HP", value = 40 }
      }
      local result = spell_resolver.convertPotionsToEngineFormat(potions)
      assert.equals(0, #result)
    end)

    it("skips potions without item ID", function()
      local potions = {
        { enabled = true, item = 0, origin = "HP", value = 40 }
      }
      local result = spell_resolver.convertPotionsToEngineFormat(potions)
      assert.equals(0, #result)
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/spell_resolver_spec.lua`
Expected: FAIL with "module 'core.heal.spell_resolver' not found"

- [ ] **Step 3: Write minimal implementation**

```lua
-- core/heal/spell_resolver.lua
local M = {}

function M.convertSpellsToEngineFormat(spellTable)
  if not spellTable then return {} end
  local converted = {}
  for _, spell in ipairs(spellTable) do
    local valid = true
    if spell.enabled == false or not spell.spell or spell.spell == "" then
      valid = false
    end

    local hp, mp = nil, nil
    local isBelow = spell.sign == "<" or spell.sign == nil
    if spell.origin == "HP" or spell.origin == "HP%" then
      if isBelow then
        hp = spell.value or 50
      else
        valid = false
      end
    elseif spell.origin == "MP" or spell.origin == "MP%" then
      if isBelow then
        mp = spell.value or 50
      else
        valid = false
      end
    else
      valid = false
    end

    if not hp and not mp then
      valid = false
    end

    if valid then
      table.insert(converted, {
        name = spell.spell,
        key = (spell.spell or ""):lower(),
        hp = hp,
        mp = mp,
        op = spell.sign or "<",
        mana = spell.cost or spell.mana or 0,
        cd = 1100,
        prio = #converted + 1
      })
    end
  end
  return converted
end

function M.convertPotionsToEngineFormat(itemTable, getItemNameFn)
  if not itemTable then return {} end
  local converted = {}
  for _, item in ipairs(itemTable) do
    if item.enabled ~= false and item.item and item.item > 0 then
      local hp, mp = nil, nil
      local isBelow = item.sign == "<" or item.sign == nil

      if item.origin == "HP" or item.origin == "HP%" then
        if isBelow then
          hp = item.value or 50
        end
      elseif item.origin == "MP" or item.origin == "MP%" then
        if isBelow then
          mp = item.value or 50
        end
      end

      local itemName = nil
      if getItemNameFn then
        itemName = getItemNameFn(item.item)
      end
      if not itemName then
        itemName = "potion #" .. item.item
      end

      if hp or mp then
        table.insert(converted, {
          id = item.item,
          key = "potion_" .. item.item,
          hp = hp,
          mp = mp,
          cd = 1000,
          prio = #converted + 1,
          name = itemName
        })
      end
    end
  end
  return converted
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/spell_resolver_spec.lua`
Expected: PASS

- [ ] **Step 5: Update HealBot.lua to use new module**

In `core/HealBot.lua`, replace lines 73-181 with:

```lua
local spell_resolver = require("core.heal.spell_resolver")

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
```

- [ ] **Step 6: Run all existing tests**

Run: `eval "$(luarocks path)" && busted tests/`
Expected: 128+ tests pass

- [ ] **Step 7: Commit**

```bash
git add core/heal/spell_resolver.lua tests/unit/domain/spell_resolver_spec.lua core/HealBot.lua
git commit -m "refactor: extract spell_resolver.lua with conversion functions"
```

---

## Task 4: Extract heal_analytics.lua

**Files:**
- Create: `core/heal/heal_analytics.lua`
- Create: `tests/unit/domain/heal_analytics_spec.lua`
- Modify: `core/HealBot.lua:815-823`

**Interfaces:**
- Produces: `resetAnalytics()`, `getAnalytics()`

- [ ] **Step 1: Write the failing test**

```lua
-- tests/unit/domain/heal_analytics_spec.lua
local heal_analytics = require("core.heal.heal_analytics")

describe("heal_analytics", function()
  before_each(function()
    heal_analytics.resetAnalytics()
  end)

  it("starts with zero counts", function()
    local stats = heal_analytics.getAnalytics()
    assert.equals(0, stats.spellCasts)
    assert.equals(0, stats.potionUses)
  end)

  it("resets analytics", function()
    heal_analytics.resetAnalytics()
    local stats = heal_analytics.getAnalytics()
    assert.equals(0, stats.spellCasts)
    assert.equals(0, stats.potionUses)
    assert.equals(0, stats.potionWaste)
    assert.equals(0, stats.manaWaste)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/heal_analytics_spec.lua`
Expected: FAIL with "module 'core.heal.heal_analytics' not found"

- [ ] **Step 3: Write minimal implementation**

```lua
-- core/heal/heal_analytics.lua
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

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/heal_analytics_spec.lua`
Expected: PASS

- [ ] **Step 5: Update HealBot.lua to use new module**

In `core/HealBot.lua`, replace lines 815-823 with:

```lua
local heal_analytics = require("core.heal.heal_analytics")

local function resetHealAnalytics()
  heal_analytics.resetAnalytics()
end
```

- [ ] **Step 6: Run all existing tests**

Run: `eval "$(luarocks path)" && busted tests/`
Expected: 128+ tests pass

- [ ] **Step 7: Commit**

```bash
git add core/heal/heal_analytics.lua tests/unit/domain/heal_analytics_spec.lua core/HealBot.lua
git commit -m "refactor: extract heal_analytics.lua with reset function"
```

---

## Task 5: Update documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/HEALBOT.md`
- Modify: `docs/ATTACKBOT.md`

- [ ] **Step 1: Update README.md architecture section**

Replace the architecture tree with:

```markdown
## Architecture

```
_Loader.lua (entry)
├── ACL (vBot/OTCR detection + adapter)
├── EventBus (event-driven communication)
├── UnifiedTick (single 50ms master timer)
├── UnifiedStorage (per-character JSON persistence)
│
├── HealBot ←── player:health events
│   └── spell_resolver (conversion functions)
├── AttackBot ←─ TargetBot decisions
│   ├── attack_data (pure data tables)
│   └── attack_analytics (recording functions)
├── CaveBot ←─── 250ms waypoint engine
├── TargetBot ←─ creature events + Monster AI
│   ├── AttackStateMachine (sole attack issuer)
│   ├── Monster Insights (12 AI modules)
│   └── MovementCoordinator (intent voting)
│
└── Hunt Analyzer ←─ passive analytics
```
```

- [ ] **Step 2: Update ARCHITECTURE.md design patterns table**

Add to the Design Patterns table:

```markdown
| **Extract Pure Functions** | Testable domain logic | attack_data, spell_resolver |
```

- [ ] **Step 3: Update HEALBOT.md**

Add after "How Healing Works" section:

```markdown
## Technical Details

Spell/potion conversion logic is in `core/heal/spell_resolver.lua` — pure functions, testable independently.
```

- [ ] **Step 4: Update ATTACKBOT.md**

Add after "Attack Rules" section:

```markdown
## Technical Details

Attack categories, patterns, and spell shapes are in `core/attack/attack_data.lua` — pure data, testable independently.
Analytics recording is in `core/attack/attack_analytics.lua` — pure functions.
```

- [ ] **Step 5: Run all tests**

Run: `eval "$(luarocks path)" && busted tests/`
Expected: 128+ tests pass

- [ ] **Step 6: Run luacheck**

Run: `eval "$(luarocks path)" && luacheck core/attack/ core/heal/ --config .luacheckrc`
Expected: 0 errors

- [ ] **Step 7: Commit**

```bash
git add README.md docs/ARCHITECTURE.md docs/HEALBOT.md docs/ATTACKBOT.md
git commit -m "docs: update architecture to reflect extracted modules"
```

---

## Task 6: Final verification

- [ ] **Step 1: Run full test suite**

Run: `eval "$(luarocks path)" && busted tests/`
Expected: 128+ tests pass, 0 failures

- [ ] **Step 2: Run luacheck on all new files**

Run: `eval "$(luarocks path)" && luacheck core/attack/ core/heal/ tests/unit/domain/ --config .luacheckrc`
Expected: 0 errors

- [ ] **Step 3: Verify original files still work**

Check that `core/HealBot.lua` and `core/AttackBot.lua` load without errors by running the full test suite.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "refactor: complete god file extraction (128+ tests passing)"
```
