# nExBot Restructuring v2.0 - Implementation Summary

## Overview

This document summarizes the big-bang restructuring of nExBot from a monolithic architecture to a feature-based modular architecture.

## New Directory Structure

```
nExBot/
├── _Loader.lua          # Original loader (preserved for rollback)
├── _Loader_v2.lua       # New loader with modular structure
│
├── lib/                 # NEW: Shared utility libraries (16 modules)
│   ├── object_pool.lua          # Memory-efficient table reuse
│   ├── unified_storage.lua      # Namespace-based storage system
│   ├── table_utils.lua          # Table helper functions
│   ├── string_utils.lua         # String helper functions
│   ├── message_utils.lua        # Status messages and logging
│   ├── player_utils.lua         # Local player functions
│   ├── creature_utils.lua       # Monster/NPC/player counting
│   ├── tile_utils.lua           # Tile and ground item functions
│   ├── spell_utils.lua          # Spell casting and cooldowns
│   ├── container_utils.lua      # Container operations
│   ├── player_list.lua          # Friend/enemy caching system
│   ├── item_utils.lua           # Item ID conversion maps
│   ├── area_patterns.lua        # getSpectators patterns (UE, waves, beams)
│   ├── damage_tracker.lua       # Incoming damage tracking
│   ├── potion_tracker.lua       # Potion usage exhaust tracking
│   └── usage_tracker.lua        # Item usage state tracking
│
├── tools/               # NEW: Tool macros (8 modules)
│   ├── money_exchanger.lua      # Auto-exchange coins
│   ├── auto_levitate.lua        # Event-driven auto-levitate
│   ├── auto_haste.lua           # Automatic haste casting
│   ├── auto_mount.lua           # Auto mount outside PZ
│   ├── fishing.lua              # Fishing with random water tile
│   ├── mana_training.lua        # Magic level training
│   ├── random_outfit.lua        # Outfit color randomization
│   └── follow_player.lua        # Follow player with attack coordination
│
├── features/            # NEW: Feature modules with init files
│   ├── analyzer/        # Hunt analysis system (9 modules)
│   │   ├── init.lua             # Main entry point & public API
│   │   ├── session_manager.lua  # Session time/stats tracking
│   │   ├── loot_tracker.lua     # Loot value tracking
│   │   ├── boss_tracker.lua     # Boss cooldown tracking
│   │   ├── party_analyzer.lua   # Party hunt data sync
│   │   ├── cavebot_stats.lua    # Round/refill statistics
│   │   ├── impact_tracker.lua   # Damage/healing tracking
│   │   ├── supply_tracker.lua   # Supply/waste tracking
│   │   └── kill_tracker.lua     # Monster kill tracking
│   │
│   ├── healing/         # Healing feature wrapper
│   │   └── init.lua             # Re-exports core/HealBot.lua
│   │
│   ├── attacking/       # Attacking feature wrapper
│   │   └── init.lua             # Re-exports core/AttackBot.lua
│   │
│   ├── targeting/       # Targeting feature wrapper
│   │   └── init.lua             # Re-exports targetbot/
│   │
│   ├── cavebot/         # CaveBot feature wrapper
│   │   └── init.lua             # Re-exports cavebot/
│   │
│   └── equipment/       # Equipment feature wrapper
│       └── init.lua             # Re-exports core/Equipper.lua
│
├── core/                # Original core modules (preserved)
├── targetbot/           # Original targetbot modules (preserved)
├── cavebot/             # Original cavebot modules (preserved)
├── utils/               # Original utility modules (preserved)
└── constants/           # Original constants (preserved)
```

## Key Changes

### 1. UnifiedStorage (lib/unified_storage.lua)

New namespace-based storage system replacing 5+ legacy patterns:
- `storage[key]`
- `HealBotConfig`
- `SuppliesConfig`
- `CharacterDB`
- `ProfileStorage`
- `BotDB`

**Key Features:**
- Namespace-based access: `UnifiedStorage.get("healing.enabled")`
- Batch updates: `UnifiedStorage.batch({...})`
- Migration helpers: `migrateFromHealBot()`, `migrateFromStorage()`
- Legacy proxy: `createLegacyProxy(namespace)` for drop-in replacement

### 2. Library Modularization (lib/)

Split core/lib.lua (1548 lines) into 15 focused modules:
- Each module exports functions to global namespace for backward compatibility
- Also available via `nExBot.Lib.*` namespace

### 3. Tools Modularization (tools/)

Split core/tools.lua (2021 lines) into 8 tool macros:
- Each tool is self-contained
- Registered via UI system when applicable

### 4. Analyzer Feature (features/analyzer/)

Split core/analyzer.lua (1904 lines) into 9 modules:
- `SessionManager` - Session time and statistics
- `LootTracker` - Loot value and drop tracking
- `BossTracker` - Boss cooldown tracking
- `PartyAnalyzer` - Party hunt data synchronization
- `CaveBotStats` - Round/refill statistics
- `ImpactTracker` - Damage/healing tracking
- `SupplyTracker` - Supply usage tracking
- `KillTracker` - Monster kill tracking

### 5. Feature Wrappers

Created init.lua files for major features that re-export existing modules:
- `features/healing/init.lua` → core/HealBot.lua
- `features/attacking/init.lua` → core/AttackBot.lua
- `features/targeting/init.lua` → targetbot/
- `features/cavebot/init.lua` → cavebot/
- `features/equipment/init.lua` → core/Equipper.lua

## New Loader (_Loader_v2.lua)

The new loader organizes loading into 13 phases:
1. ACL (Anti-Corruption Layer)
2. ACL Compatibility
3. Constants
4. Utils
5. **Lib Modules (NEW)**
6. Core Libraries
7. Architecture Layer
8. **Analyzer Modules (NEW)**
9. Feature Init Files
10. Legacy Features
11. **Tools Modules (NEW)**
12. Legacy Tools
13. Analytics/UI
14. TargetBot
15. CaveBot

## Public API

The new structure exposes a unified API via `nExBot`:

```lua
-- Analyzer
nExBot.Analyzer.getXpGained()
nExBot.Analyzer.getBalance()
nExBot.Analyzer.Boss.trackBoss(name, cooldown)

-- Features
nExBot.Healing.isEnabled()
nExBot.Targeting.getCurrentTarget()
nExBot.CaveBot.start()

-- Libraries
nExBot.Lib.ObjectPool.acquire()
nExBot.Lib.PlayerUtils.distanceFromPlayer(pos)
```

## Migration Notes

### Backward Compatibility
- All legacy global functions preserved
- Original core/ modules untouched
- Original _Loader.lua preserved for rollback

### Switching to New Loader
To use the new structure, rename files:
1. `_Loader.lua` → `_Loader_old.lua`
2. `_Loader_v2.lua` → `_Loader.lua`

### Rollback
To rollback, simply reverse the rename.

## Files Created

| Category | Count | Files |
|----------|-------|-------|
| lib/ | 16 | object_pool, unified_storage, table_utils, string_utils, message_utils, player_utils, creature_utils, tile_utils, spell_utils, container_utils, player_list, item_utils, area_patterns, damage_tracker, potion_tracker, usage_tracker |
| tools/ | 8 | money_exchanger, auto_levitate, auto_haste, auto_mount, fishing, mana_training, random_outfit, follow_player |
| features/analyzer/ | 9 | init, session_manager, loot_tracker, boss_tracker, party_analyzer, cavebot_stats, impact_tracker, supply_tracker, kill_tracker |
| features/*/ | 5 | healing/init, attacking/init, targeting/init, cavebot/init, equipment/init |
| Loader | 1 | _Loader_v2.lua |
| **Total** | **39** | New modular files |

## Date

Restructuring completed: January 29, 2026
