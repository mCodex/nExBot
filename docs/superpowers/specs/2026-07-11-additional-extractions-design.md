# Additional God File Extractions Design

**Date:** 2026-07-11
**Goal:** Extract config management + combat execution from god files
**Prerequisites:** Wave 4 Tasks 1-4 complete (attack_data, attack_analytics, spell_resolver, heal_analytics)
**Risk:** Medium — combat_executor requires DI pattern

## Problem

HealBot.lua (1426 lines) and AttackBot.lua (1354 lines) still contain config management logic and combat execution logic that can be extracted for testability. The existing `core/bot_core/conditions.lua` already handles condition checking — no extraction needed there.

## Solution

Extract 3 new modules: config management (2) + combat execution (1). Config modules use pure functions. Combat executor uses dependency injection to decouple from runtime state.

## New Modules

### 1. `core/heal/heal_config.lua` (~60 lines)

**Responsibility:** Default profile creation + config validation

**Functions:**
- `createDefaults()` → returns array of 5 default profile tables
- `validateProfile(profile)` → returns boolean (checks required fields exist)
- `ensureDefaults(config, panelName)` → mutates config in-place, creates defaults if missing

**Pattern:** Pure functions. No globals. Config table passed as parameter.

**Interface:**
```lua
local heal_config = require("core.heal.heal_config")

-- Create 5 default profiles
local defaults = heal_config.createDefaults()

-- Validate a profile
local ok = heal_config.validateProfile(someProfile)

-- Ensure config has valid profiles (mutates in-place)
heal_config.ensureDefaults(HealBotConfig, "healbot")
```

**Extracted from HealBot.lua:**
- Lines 5-38: `ensureCurrentSettings()` default profile creation
- Lines 10-24: Default profile template

### 2. `core/attack/attack_config.lua` (~70 lines)

**Responsibility:** Default profile creation + profile switching

**Functions:**
- `createDefaults()` → returns array of 5 default profile tables
- `validateProfile(profile)` → returns boolean
- `ensureDefaults(config, panelName)` → mutates config in-place
- `getActiveProfile(config, panelName)` → returns current settings table

**Pattern:** Pure functions. No globals. Config table passed as parameter.

**Interface:**
```lua
local attack_config = require("core.attack.attack_config")

-- Create 5 default profiles
local defaults = attack_config.createDefaults()

-- Validate a profile
local ok = attack_config.validateProfile(someProfile)

-- Ensure config has valid profiles
attack_config.ensureDefaults(AttackBotConfig, "attackbot")

-- Get active profile settings
local settings = attack_config.getActiveProfile(AttackBotConfig, "attackbot")
```

**Extracted from AttackBot.lua:**
- Lines 138-217: Default profile creation
- Lines 220-248: Profile initialization + setActiveProfile logic

### 3. `core/attack/combat_executor.lua` (~200 lines)

**Responsibility:** Rune/spell execution with injected dependencies

**Functions:**
- `useRuneOnTarget(runeId, target, deps)` → boolean
- `attemptSpellCast(entry, context, deps)` → boolean
- `executeAttack(entry, context, deps)` → boolean

**Pattern:** Dependency injection. `deps` table contains all runtime dependencies.

**Interface:**
```lua
local combat_executor = require("core.attack.combat_executor")

-- deps table contains injected dependencies
local deps = {
  cast = cast,
  turn = turn,
  useWith = useWith,
  g_game = g_game,
  SafeCall = SafeCall,
  Client = Client,
  nowMs = nowMs,
  player = player,
  recordAttackAction = recordAttackAction,
  getSpellState = getSpellState,
  toCooldownMs = toCooldownMs,
  applyGlobalBackoff = applyGlobalBackoff,
  confirmSpellCast = confirmSpellCast,
  isSpellCategory = isSpellCategory,
  getSpellKey = getSpellKey,
  spellPatterns = spellPatterns,
  newAttackCache = newAttackCache,
  buildPatternKey = buildPatternKey,
  getBestTileByPattern = getBestTileByPattern,
  getSpectators = getSpectators,
}

-- Execute a rune on target
local ok = combat_executor.useRuneOnTarget(runeId, target, deps)

-- Attempt to cast a spell
local ok = combat_executor.attemptSpellCast(entry, context, deps)

-- Execute any attack type
local ok = combat_executor.executeAttack(entry, context, deps)
```

**Extracted from AttackBot.lua:**
- Lines 770-848: `attemptSpellCast()`
- Lines 982-1019: `useRuneOnTarget()`
- Lines 1239-1283: `executeAttack()`

## Changes to Originals

### HealBot.lua

Before:
```lua
local function ensureCurrentSettings()
  if not currentSettings then
    if not HealBotConfig then HealBotConfig = {} end
    if not HealBotConfig[healPanelName] or ... then
      local profiles = {}
      for i = 1, 5 do
        profiles[i] = { enabled = false, spellTable = {}, ... }
      end
      HealBotConfig[healPanelName] = profiles
      pcall(saveHeal)
    end
    ...
  end
end
```

After:
```lua
local heal_config = require("core.heal.heal_config")

local function ensureCurrentSettings()
  if not currentSettings then
    if not HealBotConfig then HealBotConfig = {} end
    heal_config.ensureDefaults(HealBotConfig, healPanelName)
    pcall(saveHeal)
    if setActiveProfile then pcall(setActiveProfile) end
  end
end
```

### AttackBot.lua

Before:
```lua
if not AttackBotConfig[panelName] or ... then
  AttackBotConfig[panelName] = {
    [1] = { enabled = true, attackTable = {}, ... },
    [2] = { enabled = false, attackTable = {}, ... },
    ...
  }
end

local setActiveProfile = function()
  local n = AttackBotConfig.currentBotProfile
  currentSettings = AttackBotConfig[panelName][n]
  setCharacterProfile("attackProfile", n)
end
```

After:
```lua
local attack_config = require("core.attack.attack_config")

attack_config.ensureDefaults(AttackBotConfig, panelName)

local setActiveProfile = function()
  currentSettings = attack_config.getActiveProfile(AttackBotConfig, panelName)
  setCharacterProfile("attackProfile", AttackBotConfig.currentBotProfile)
end
```

## Testing Strategy

### heal_config_spec.lua (~10 tests)
- `createDefaults()` returns 5 profiles
- Each profile has required fields (enabled, spellTable, itemTable, name)
- `validateProfile()` accepts valid profile
- `validateProfile()` rejects nil/empty/missing fields
- `ensureDefaults()` creates profiles when missing
- `ensureDefaults()` preserves existing profiles

### attack_config_spec.lua (~10 tests)
- `createDefaults()` returns 5 profiles
- Each profile has required fields (enabled, attackTable, name, Cooldown, etc.)
- `validateProfile()` accepts valid profile
- `validateProfile()` rejects invalid profile
- `ensureDefaults()` creates profiles when missing
- `getActiveProfile()` returns correct profile

### combat_executor_spec.lua (~12 tests)
- `useRuneOnTarget()` calls useWith with correct args
- `useRuneOnTarget()` falls back to BotCore.Items.useOn
- `useRuneOnTarget()` falls back to g_game.useInventoryItemWith
- `useRuneOnTarget()` returns false when all methods fail
- `attemptSpellCast()` checks cooldown before casting
- `attemptSpellCast()` calls cast on success
- `attemptSpellCast()` applies backoff on failure
- `executeAttack()` delegates to attemptSpellCast for spell categories
- `executeAttack()` calls useRuneOnTarget for rune categories
- `executeAttack()` handles area runes with pattern lookup

## File Structure

| File | Responsibility |
|------|---------------|
| `core/heal/heal_config.lua` | Default profile creation + validation |
| `core/attack/attack_config.lua` | Default profile creation + profile switching |
| `core/attack/combat_executor.lua` | Rune/spell execution with DI |
| `tests/unit/domain/heal_config_spec.lua` | Tests for heal config |
| `tests/unit/domain/attack_config_spec.lua` | Tests for attack config |
| `tests/unit/domain/combat_executor_spec.lua` | Tests for combat executor |

## Modified Files

| File | Changes |
|------|---------|
| `core/HealBot.lua` | Replace inline config with `heal_config` require |
| `core/AttackBot.lua` | Replace inline config with `attack_config` require, replace combat functions with `combat_executor` require |
| `docs/ARCHITECTURE.md` | Add new modules |
| `docs/HEALBOT.md` | Reference heal_config |
| `docs/ATTACKBOT.md` | Reference attack_config + combat_executor |
