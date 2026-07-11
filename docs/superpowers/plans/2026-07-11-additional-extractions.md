# Additional God File Extractions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract config management + combat execution from HealBot.lua and AttackBot.lua into testable modules

**Architecture:** Config modules use pure functions (no globals). Combat executor uses dependency injection to decouple from runtime state. Originals call new modules via `require()`.

**Tech Stack:** Lua 5.1, busted (testing), luacheck (linting)

## Global Constraints

- Lua 5.1/LuaJIT 2.1 target
- OTClient/OpenTibiaBR runtime (g_game, g_map, g_things globals)
- 2-space indentation
- No new dependencies
- All 159 existing tests must pass after each task

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `core/heal/heal_config.lua` | Default profile creation + validation |
| `core/attack/attack_config.lua` | Default profile creation + profile switching |
| `core/attack/combat_executor.lua` | Rune/spell execution with DI |
| `tests/unit/domain/heal_config_spec.lua` | Tests for heal config |
| `tests/unit/domain/attack_config_spec.lua` | Tests for attack config |
| `tests/unit/domain/combat_executor_spec.lua` | Tests for combat executor |

### Modified Files

| File | Changes |
|------|---------|
| `core/HealBot.lua` | Replace inline config with `heal_config` require |
| `core/AttackBot.lua` | Replace inline config with `attack_config` require, replace combat functions with `combat_executor` require |
| `docs/ARCHITECTURE.md` | Add new modules |
| `docs/HEALBOT.md` | Reference heal_config |
| `docs/ATTACKBOT.md` | Reference attack_config + combat_executor |

---

## Task 1: Extract heal_config.lua

**Files:**
- Create: `core/heal/heal_config.lua`
- Create: `tests/unit/domain/heal_config_spec.lua`
- Modify: `core/HealBot.lua`

**Interfaces:**
- Produces: `heal_config.createDefaults()`, `heal_config.validateProfile(profile)`, `heal_config.ensureDefaults(config, panelName)`

- [ ] **Step 1: Write the failing test**

```lua
local heal_config = require("core.heal.heal_config")

describe("heal_config", function()
  it("createDefaults returns 5 profiles", function()
    local defaults = heal_config.createDefaults()
    assert.equals(5, #defaults)
  end)

  it("each profile has required fields", function()
    local defaults = heal_config.createDefaults()
    for i = 1, 5 do
      assert.is_false(defaults[i].enabled)
      assert.is_table(defaults[i].spellTable)
      assert.is_table(defaults[i].itemTable)
      assert.equals("Profile #" .. i, defaults[i].name)
      assert.is_true(defaults[i].Visible)
      assert.is_true(defaults[i].Cooldown)
    end
  end)

  it("validateProfile accepts valid profile", function()
    local profile = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Test",
      Visible = true,
      Cooldown = true,
    }
    assert.is_true(heal_config.validateProfile(profile))
  end)

  it("validateProfile rejects nil", function()
    assert.is_false(heal_config.validateProfile(nil))
  end)

  it("validateProfile rejects empty table", function()
    assert.is_false(heal_config.validateProfile({}))
  end)

  it("validateProfile rejects missing spellTable", function()
    local profile = { enabled = false, itemTable = {}, name = "Test", Visible = true, Cooldown = true }
    assert.is_false(heal_config.validateProfile(profile))
  end)

  it("ensureDefaults creates profiles when missing", function()
    local config = {}
    heal_config.ensureDefaults(config, "healbot")
    assert.is_table(config.healbot)
    assert.equals(5, #config.healbot)
  end)

  it("ensureDefaults preserves existing profiles", function()
    local config = {
      healbot = {
        [1] = { enabled = true, spellTable = {}, itemTable = {}, name = "Custom" },
      }
    }
    heal_config.ensureDefaults(config, "healbot")
    assert.equals("Custom", config.healbot[1].name)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/heal_config_spec.lua`
Expected: FAIL with "module 'core.heal.heal_config' not found"

- [ ] **Step 3: Write minimal implementation**

```lua
local M = {}

local DEFAULT_PROFILE = {
  enabled = false,
  spellTable = {},
  itemTable = {},
  name = nil,  -- set per profile
  Visible = true,
  Cooldown = true,
  Interval = true,
  Conditions = true,
  Delay = true,
  MessageDelay = false,
}

function M.createDefaults()
  local profiles = {}
  for i = 1, 5 do
    profiles[i] = {}
    for k, v in pairs(DEFAULT_PROFILE) do
      profiles[i][k] = v
    end
    profiles[i].name = "Profile #" .. i
  end
  return profiles
end

function M.validateProfile(profile)
  if type(profile) ~= "table" then return false end
  if profile.spellTable == nil then return false end
  if profile.itemTable == nil then return false end
  return true
end

function M.ensureDefaults(config, panelName)
  if type(config) ~= "table" then return end
  if type(config[panelName]) ~= "table" or #config[panelName] ~= 5 then
    config[panelName] = M.createDefaults()
  end
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/heal_config_spec.lua`
Expected: 8 successes / 0 failures

- [ ] **Step 5: Update HealBot.lua to use heal_config**

Replace lines 5-38 (ensureCurrentSettings) with:

```lua
local heal_config = require("core.heal.heal_config")

local function ensureCurrentSettings()
  if not currentSettings then
    if not HealBotConfig then HealBotConfig = {} end
    heal_config.ensureDefaults(HealBotConfig, healPanelName)
    if not HealBotConfig.currentHealBotProfile or HealBotConfig.currentHealBotProfile < 1 or HealBotConfig.currentHealBotProfile > 5 then
      HealBotConfig.currentHealBotProfile = 1
    end
    if setActiveProfile then
      pcall(setActiveProfile)
    else
      currentSettings = HealBotConfig[healPanelName][HealBotConfig.currentHealBotProfile]
    end
  end
end
```

- [ ] **Step 6: Run all tests**

Run: `eval "$(luarocks path)" && busted tests/`
Expected: 167+ tests pass

- [ ] **Step 7: Run luacheck**

Run: `eval "$(luarocks path)" && luacheck core/heal/heal_config.lua tests/unit/domain/heal_config_spec.lua --config .luacheckrc`
Expected: 0 errors

- [ ] **Step 8: Commit**

```bash
git add core/heal/heal_config.lua tests/unit/domain/heal_config_spec.lua core/HealBot.lua
git commit -m "refactor: extract heal_config.lua with default profile management"
```

---

## Task 2: Extract attack_config.lua

**Files:**
- Create: `core/attack/attack_config.lua`
- Create: `tests/unit/domain/attack_config_spec.lua`
- Modify: `core/AttackBot.lua`

**Interfaces:**
- Consumes: `attack_config.createDefaults()`, `attack_config.validateProfile(profile)`, `attack_config.ensureDefaults(config, panelName)`, `attack_config.getActiveProfile(config, panelName)`

- [ ] **Step 1: Write the failing test**

```lua
local attack_config = require("core.attack.attack_config")

describe("attack_config", function()
  it("createDefaults returns 5 profiles", function()
    local defaults = attack_config.createDefaults()
    assert.equals(5, #defaults)
  end)

  it("each profile has required fields", function()
    local defaults = attack_config.createDefaults()
    for i = 1, 5 do
      assert.is_table(defaults[i].attackTable)
      assert.equals("Profile #" .. i, defaults[i].name)
      assert.is_true(defaults[i].Cooldown)
      assert.is_true(defaults[i].Visible)
      assert.equals(5, defaults[i].AntiRsRange)
    end
  end)

  it("first profile is enabled by default", function()
    local defaults = attack_config.createDefaults()
    assert.is_true(defaults[1].enabled)
  end)

  it("profiles 2-5 are disabled by default", function()
    local defaults = attack_config.createDefaults()
    for i = 2, 5 do
      assert.is_false(defaults[i].enabled)
    end
  end)

  it("validateProfile accepts valid profile", function()
    local profile = {
      enabled = false,
      attackTable = {},
      name = "Test",
      Cooldown = true,
      Visible = true,
      AntiRsRange = 5,
    }
    assert.is_true(attack_config.validateProfile(profile))
  end)

  it("validateProfile rejects nil", function()
    assert.is_false(attack_config.validateProfile(nil))
  end)

  it("validateProfile rejects missing attackTable", function()
    local profile = { enabled = false, name = "Test" }
    assert.is_false(attack_config.validateProfile(profile))
  end)

  it("ensureDefaults creates profiles when missing", function()
    local config = {}
    attack_config.ensureDefaults(config, "attackbot")
    assert.is_table(config.attackbot)
    assert.equals(5, #config.attackbot)
  end)

  it("ensureDefaults preserves existing profiles", function()
    local config = {
      attackbot = {
        [1] = { enabled = true, attackTable = {}, name = "Custom" },
      }
    }
    attack_config.ensureDefaults(config, "attackbot")
    assert.equals("Custom", config.attackbot[1].name)
  end)

  it("getActiveProfile returns current profile", function()
    local config = {
      currentBotProfile = 2,
      attackbot = {
        [1] = { name = "Profile #1" },
        [2] = { name = "Profile #2" },
      }
    }
    local settings = attack_config.getActiveProfile(config, "attackbot")
    assert.equals("Profile #2", settings.name)
  end)

  it("getActiveProfile falls back to profile 1", function()
    local config = {
      currentBotProfile = 99,
      attackbot = {
        [1] = { name = "Profile #1" },
      }
    }
    local settings = attack_config.getActiveProfile(config, "attackbot")
    assert.equals("Profile #1", settings.name)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/attack_config_spec.lua`
Expected: FAIL with "module 'core.attack.attack_config' not found"

- [ ] **Step 3: Write minimal implementation**

```lua
local M = {}

local DEFAULT_PROFILE = {
  enabled = false,
  attackTable = {},
  ignoreMana = true,
  Kills = false,
  Rotate = false,
  name = nil,
  Cooldown = true,
  Visible = true,
  pvpMode = false,
  KillsAmount = 1,
  PvpSafe = true,
  BlackListSafe = false,
  AntiRsRange = 5,
}

function M.createDefaults()
  local profiles = {}
  for i = 1, 5 do
    profiles[i] = {}
    for k, v in pairs(DEFAULT_PROFILE) do
      profiles[i][k] = v
    end
    profiles[i].name = "Profile #" .. i
  end
  profiles[1].enabled = true
  return profiles
end

function M.validateProfile(profile)
  if type(profile) ~= "table" then return false end
  if profile.attackTable == nil then return false end
  return true
end

function M.ensureDefaults(config, panelName)
  if type(config) ~= "table" then return end
  if type(config[panelName]) ~= "table" or #config[panelName] ~= 5 then
    config[panelName] = M.createDefaults()
  end
end

function M.getActiveProfile(config, panelName)
  local n = config.currentBotProfile
  if type(n) ~= "number" or n < 1 or n > 5 then
    n = 1
  end
  return config[panelName][n]
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/attack_config_spec.lua`
Expected: 11 successes / 0 failures

- [ ] **Step 5: Update AttackBot.lua to use attack_config**

Replace lines 138-248 (default profile creation + setActiveProfile) with:

```lua
local attack_config = require("core.attack.attack_config")

attack_config.ensureDefaults(AttackBotConfig, panelName)

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
  currentSettings = attack_config.getActiveProfile(AttackBotConfig, panelName)
  setCharacterProfile("attackProfile", AttackBotConfig.currentBotProfile)
end
setActiveProfile()
```

- [ ] **Step 6: Run all tests**

Run: `eval "$(luarocks path)" && busted tests/`
Expected: 178+ tests pass

- [ ] **Step 7: Run luacheck**

Run: `eval "$(luarocks path)" && luacheck core/attack/attack_config.lua tests/unit/domain/attack_config_spec.lua --config .luacheckrc`
Expected: 0 errors

- [ ] **Step 8: Commit**

```bash
git add core/attack/attack_config.lua tests/unit/domain/attack_config_spec.lua core/AttackBot.lua
git commit -m "refactor: extract attack_config.lua with profile management"
```

---

## Task 3: Extract combat_executor.lua

**Files:**
- Create: `core/attack/combat_executor.lua`
- Create: `tests/unit/domain/combat_executor_spec.lua`
- Modify: `core/AttackBot.lua`

**Interfaces:**
- Consumes: `combat_executor.useRuneOnTarget(runeId, target, deps)`, `combat_executor.attemptSpellCast(entry, context, deps)`, `combat_executor.executeAttack(entry, context, deps)`

- [ ] **Step 1: Write the failing test**

```lua
local combat_executor = require("core.attack.combat_executor")

describe("combat_executor", function()
  local deps

  before_each(function()
    deps = {
      cast = function() end,
      turn = function() end,
      useWith = function() return true end,
      g_game = { useInventoryItemWith = function() return true end },
      SafeCall = {
        findItem = function() return nil end,
        getCachedCaller = function() return nil end,
        target = function() return nil end,
        isInPz = function() return false end,
      },
      Client = { useInventoryItemWith = nil, useWith = nil },
      nowMs = function() return 1000 end,
      player = { getDirection = function() return 0 end },
      recordAttackAction = function() end,
      getSpellState = function() return { nextReadyAt = 0 } end,
      toCooldownMs = function(cd) return cd end,
      applyGlobalBackoff = function() end,
      confirmSpellCast = function(_, _, onSuccess) onSuccess() end,
      isSpellCategory = function(cat) return cat == 1 or cat == 4 or cat == 5 end,
      getSpellKey = function(entry) return (entry.spell or ""):lower() end,
      spellPatterns = {},
      buildPatternKey = function() return "key" end,
      getBestTileByPattern = function() return nil end,
      getSpectators = function() return {} end,
    }
  end)

  it("useRuneOnTarget calls useWith", function()
    local called = false
    deps.useWith = function(id, target)
      called = true
      assert.equals(3160, id)
      return true
    end
    local result = combat_executor.useRuneOnTarget(3160, "target", deps)
    assert.is_true(result)
    assert.is_true(called)
  end)

  it("useRuneOnTarget falls back to g_game", function()
    deps.useWith = nil
    local called = false
    deps.g_game.useInventoryItemWith = function(id, target)
      called = true
      return true
    end
    local result = combat_executor.useRuneOnTarget(3160, "target", deps)
    assert.is_true(result)
    assert.is_true(called)
  end)

  it("useRuneOnTarget returns false when all methods fail", function()
    deps.useWith = function() return false end
    deps.g_game.useInventoryItemWith = function() return false end
    deps.SafeCall.findItem = function() return nil end
    local result = combat_executor.useRuneOnTarget(3160, "target", deps)
    assert.is_false(result)
  end)

  it("executeAttack delegates to attemptSpellCast for category 1", function()
    local entry = { category = 1, spell = "exori", cooldown = 100 }
    local context = { settings = { Cooldown = true, PvpSafe = false }, target = "target" }
    local result = combat_executor.executeAttack(entry, context, deps)
    assert.is_true(result)
  end)

  it("executeAttack calls useRuneOnTarget for category 3", function()
    local entry = { category = 3, itemId = 3160, spell = "rune" }
    local context = { settings = { Cooldown = true, PvpSafe = false }, target = "target" }
    local result = combat_executor.executeAttack(entry, context, deps)
    assert.is_true(result)
  end)

  it("executeAttack returns false when rune fails", function()
    deps.useWith = function() return false end
    deps.g_game.useInventoryItemWith = function() return false end
    local entry = { category = 3, itemId = 3160, spell = "rune" }
    local context = { settings = { Cooldown = true, PvpSafe = false }, target = "target" }
    local result = combat_executor.executeAttack(entry, context, deps)
    assert.is_false(result)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/combat_executor_spec.lua`
Expected: FAIL with "module 'core.attack.combat_executor' not found"

- [ ] **Step 3: Write minimal implementation**

```lua
local M = {}

function M.useRuneOnTarget(runeId, target, deps)
  if deps.useWith and target then
    local ok = pcall(deps.useWith, runeId, target)
    if ok then return true end
  end

  if deps.g_game and deps.g_game.useInventoryItemWith then
    local ok = pcall(deps.g_game.useInventoryItemWith, runeId, target)
    if ok then return true end
  end

  if deps.SafeCall and deps.SafeCall.findItem then
    local rune = deps.SafeCall.findItem(runeId)
    if rune then
      if deps.Client and deps.Client.useWith then
        local ok = pcall(deps.Client.useWith, rune, target)
        if ok then return true end
      elseif deps.g_game and deps.g_game.useWith then
        local ok = pcall(deps.g_game.useWith, rune, target)
        if ok then return true end
      end
    end
  end

  return false
end

function M.attemptSpellCast(entry, context, deps)
  local spellKey = deps.getSpellKey(entry)
  if spellKey == "" then return false end

  local state = deps.getSpellState(spellKey)
  local cdMs = deps.toCooldownMs(entry.cooldown)

  if context.settings.Cooldown and state and deps.nowMs() < state.nextReadyAt then
    return false
  end

  local canCastCaller = deps.SafeCall.getCachedCaller("canCast")
  if canCastCaller then
    local ok = canCastCaller(spellKey, not context.settings.ignoreMana, not context.settings.Cooldown)
    if ok == false then return false end
  end

  local beforeTs = 0
  if state then state.lastAttemptAt = deps.nowMs() end

  deps.cast(spellKey, math.max(cdMs, 100))

  deps.confirmSpellCast(spellKey, beforeTs, function()
    if state then
      state.nextReadyAt = deps.nowMs() + cdMs
    end
    deps.applyGlobalBackoff(200)
    deps.recordAttackAction(entry.category, entry.spell)
  end, function()
    if context.settings.Cooldown and state then
      state.nextReadyAt = math.max(state.nextReadyAt or 0, deps.nowMs() + 200)
    end
    deps.applyGlobalBackoff(200)
  end)

  return true
end

function M.executeAttack(entry, context, deps)
  if deps.isSpellCategory(entry.category) then
    return M.attemptSpellCast(entry, context, deps)
  end

  local stampKey = entry.key or tostring(entry.itemId or entry.spell)

  if entry.category == 3 then
    local okTargeted = M.useRuneOnTarget(entry.itemId, context.target, deps)
    if okTargeted then
      deps.recordAttackAction(entry.category, entry.itemId > 100 and entry.itemId or entry.spell)
      return true
    end
    return false
  elseif entry.category == 2 then
    local pat = deps.spellPatterns[entry.patternCategory] and deps.spellPatterns[entry.patternCategory][entry.pattern]
    local pKey = deps.buildPatternKey(entry, context.settings.PvpSafe)
    local data = context._attackCache and context._attackCache.bestTileByPattern and context._attackCache.bestTileByPattern[pKey]
    if not data then
      data = deps.getBestTileByPattern(pat, entry.minHp, entry.maxHp, context.settings.PvpSafe, entry.monsters)
    end
    if data and data.pos then
      local Client = deps.Client
      local tile = (Client and Client.getTile) and Client.getTile(data.pos)
      if tile then
        local okArea = M.useRuneOnTarget(entry.itemId, tile:getTopUseThing(), deps)
        if okArea then
          deps.recordAttackAction(entry.category, entry.itemId > 100 and entry.itemId or entry.spell)
          return true
        end
      end
    end
    return false
  end

  return true
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval "$(luarocks path)" && busted tests/unit/domain/combat_executor_spec.lua`
Expected: 6 successes / 0 failures

- [ ] **Step 5: Update AttackBot.lua to use combat_executor**

Replace the inline functions with delegation:

```lua
local combat_executor = require("core.attack.combat_executor")

-- Replace useRuneOnTarget (lines 982-1019) with:
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

-- Replace attemptSpellCast (lines 770-848) with:
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

-- Replace executeAttack (lines 1239-1283) with:
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
```

- [ ] **Step 6: Run all tests**

Run: `eval "$(luarocks path)" && busted tests/`
Expected: 184+ tests pass

- [ ] **Step 7: Run luacheck**

Run: `eval "$(luarocks path)" && luacheck core/attack/combat_executor.lua tests/unit/domain/combat_executor_spec.lua --config .luacheckrc`
Expected: 0 errors

- [ ] **Step 8: Commit**

```bash
git add core/attack/combat_executor.lua tests/unit/domain/combat_executor_spec.lua core/AttackBot.lua
git commit -m "refactor: extract combat_executor.lua with DI pattern"
```

---

## Task 4: Update documentation

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/HEALBOT.md`
- Modify: `docs/ATTACKBOT.md`

- [ ] **Step 1: Add new modules to ARCHITECTURE.md**

Add to the module list:

```markdown
| Module | Lines | Purpose |
|--------|-------|---------|
| `core/heal/heal_config.lua` | ~60 | Default profile creation + validation |
| `core/attack/attack_config.lua` | ~70 | Default profile creation + profile switching |
| `core/attack/combat_executor.lua` | ~200 | Rune/spell execution with DI |
```

- [ ] **Step 2: Add heal_config reference to HEALBOT.md**

Add after "Technical Details" section:

```markdown
Profile defaults and validation are in `core/heal/heal_config.lua` — pure functions.
```

- [ ] **Step 3: Add attack_config + combat_executor reference to ATTACKBOT.md**

Add after "Technical Details" section:

```markdown
Profile management is in `core/attack/attack_config.lua` — pure functions.
Combat execution is in `core/attack/combat_executor.lua` — uses dependency injection.
```

- [ ] **Step 4: Run all tests**

Run: `eval "$(luarocks path)" && busted tests/`
Expected: 184+ tests pass

- [ ] **Step 5: Commit**

```bash
git add docs/ARCHITECTURE.md docs/HEALBOT.md docs/ATTACKBOT.md
git commit -m "docs: update architecture for additional extractions"
```

---

## Task 5: Final verification

- [ ] **Step 1: Run full test suite**

Run: `eval "$(luarocks path)" && busted tests/`
Expected: 184+ tests pass, 0 failures

- [ ] **Step 2: Run luacheck on all new files**

Run: `eval "$(luarocks path)" && luacheck core/heal/heal_config.lua core/attack/attack_config.lua core/attack/combat_executor.lua tests/unit/domain/heal_config_spec.lua tests/unit/domain/attack_config_spec.lua tests/unit/domain/combat_executor_spec.lua --config .luacheckrc`
Expected: 0 errors

- [ ] **Step 3: Verify original files still work**

Check that `core/HealBot.lua` and `core/AttackBot.lua` load without errors by running the full test suite.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "refactor: complete additional god file extractions"
```
