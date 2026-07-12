# God File Extraction Design

**Date:** 2026-07-11
**Goal:** Extract pure functions from HealBot.lua and AttackBot.lua for testability
**Risk:** Low — originals call new modules, no global state changes

## Problem

HealBot.lua (1523 lines) and AttackBot.lua (1795 lines) are god files. Logic, UI, and event handling are tangled. Unit testing domain logic is impossible without OTClient runtime.

## Solution

Extract ~1875 lines (56%) into 10 testable modules. Config functions take config table as first parameter instead of accessing globals.

## New Modules

### HealBot Extractions

| Module | Lines | Functions |
|--------|-------|-----------|
| `core/heal/spell_resolver.lua` | ~80 | `resolveHealSpell(spells, hpPercent, mp, cooldowns)`, `resolvePotion(potions, hpPercent, inventory)` |
| `core/heal/heal_stats.lua` | ~55 | `recordHeal(type, name, cost)`, `getStats()`, `resetStats()` |
| `core/heal/heal_analytics.lua` | ~50 | `reportSpellUse(name, manaCost)`, `reportPotionUse(name)` |
| `core/heal/heal_config.lua` | ~250 | `loadProfile(config, name)`, `saveProfile(config, name)`, `resetProfile(config)`, `exportProfile(config)`, `importProfile(config, data)` |

### AttackBot Extractions

| Module | Lines | Functions |
|--------|-------|-----------|
| `core/attack/attack_data.lua` | ~500 | `categories`, `patterns`, `spellShapes`, `getSpellShape(category, pattern)` |
| `core/attack/attack_analytics.lua` | ~60 | `recordSpellUse(name)`, `recordRuneUse(name)`, `recordBuffUse(name)`, `getStats()` |
| `core/attack/attack_config.lua` | ~780 | `loadProfile(config, name)`, `saveProfile(config, name)`, `addEntry(config, entry)`, `removeEntry(config, index)`, `updateEntry(config, index, data)`, `getEntries(config)` |
| `core/attack/entry_compiler.lua` | ~100 | `compileEntries(config, profile)` → executable attack entries |

### Shared

| Module | Lines | Functions |
|--------|-------|-----------|
| `core/shared/config_utils.lua` | ~50 | `loadJsonConfig(path)`, `saveJsonConfig(path, data)`, `migrateConfig(config, schema)` |

## Changes to Originals

### HealBot.lua

Before:
```lua
local function resolveHealSpell()
  -- 30 lines of inline logic
end
```

After:
```lua
local spell_resolver = require("core.heal.spell_resolver")

local function resolveHealSpell()
  return spell_resolver.resolveHealSpell(
    HealBotConfig.healingSpells,
    hpPercent, mp, cooldowns
  )
end
```

### AttackBot.lua

Before:
```lua
local categories = { ... }  -- 500 lines of data
local function loadProfile(name)
  -- 50 lines of config logic
end
```

After:
```lua
local attack_data = require("core.attack.attack_data")
local attack_config = require("core.attack.attack_config")

local categories = attack_data.categories
local function loadProfile(name)
  return attack_config.loadProfile(AttackBotConfig, name)
end
```

## Config Function Signature Change

Before (global state):
```lua
function HealBot.loadProfile(name)
  local profile = HealBotConfig.profiles[name]
  -- ...
end
```

After (parameterized):
```lua
function heal_config.loadProfile(config, name)
  local profile = config.profiles[name]
  -- ...
end

-- Original delegates:
function HealBot.loadProfile(name)
  return heal_config.loadProfile(HealBotConfig, name)
end
```

## Tests

| Test File | Tests |
|-----------|-------|
| `tests/unit/domain/spell_resolver_spec.lua` | ~15 — spell resolution, potion resolution, edge cases |
| `tests/unit/domain/heal_stats_spec.lua` | ~8 — stat recording, reset, getStats |
| `tests/unit/domain/heal_analytics_spec.lua` | ~6 — reporting, aggregation |
| `tests/unit/domain/heal_config_spec.lua` | ~12 — load/save/reset/export/import |
| `tests/unit/domain/attack_data_spec.lua` | ~10 — data integrity, getSpellShape |
| `tests/unit/domain/attack_analytics_spec.lua` | ~8 — recording, aggregation |
| `tests/unit/domain/attack_config_spec.lua` | ~15 — load/save/add/remove/update |
| `tests/unit/domain/entry_compiler_spec.lua` | ~10 — compilation, edge cases |

**Total new tests:** ~84
**Grand total:** 128 + 84 = 212 tests

## Loading Order

No changes to `_Loader.lua`. New modules loaded via `require()` at first use (lazy loading). Originals remain the entry points.

## Risk Mitigation

1. **Fallback:** If new module fails to load, originals fall back to inline logic
2. **No global state changes:** Originals still own HealBotConfig/AttackBotConfig
3. **No loading order changes:** _Loader.lua unchanged
4. **Incremental:** Can extract one module at a time, test, commit

## TDD Approach

Each module follows red-green-refactor:

1. **Write failing test** — define expected behavior
2. **Implement minimum code** — make test pass
3. **Refactor** — clean up, remove duplication

Order of implementation:
1. `attack_data.lua` — pure data, no dependencies, easiest to test first
2. `spell_resolver.lua` — pure functions, minimal dependencies
3. `entry_compiler.lua` — depends on attack_data
4. `heal_stats.lua` — simple state tracking
5. `heal_analytics.lua` — thin wrapper
6. `attack_analytics.lua` — thin wrapper
7. `heal_config.lua` — config management
8. `attack_config.lua` — config management
9. `config_utils.lua` — shared utilities
10. Update originals to call new modules

## Documentation Updates

### README.md
- Update Architecture section to show new module structure
- Add `core/heal/` and `core/attack/` to folder tree

### docs/ARCHITECTURE.md
- Add extraction pattern to Design Patterns table
- Document config parameterization pattern

### docs/HEALBOT.md
- Note that spell resolution is now in `core/heal/spell_resolver.lua`
- Reference test coverage

### docs/ATTACKBOT.md
- Note that attack data is now in `core/attack/attack_data.lua`
- Reference test coverage

### CONTRIBUTING.md
- Create if missing — document TDD workflow, extraction pattern

## Success Criteria

- All 212 tests pass (128 existing + 84 new)
- No regressions in existing tests
- luacheck: 0 errors
- Original files still work identically
- README and docs reflect new module structure
- Each module has ≥80% test coverage
